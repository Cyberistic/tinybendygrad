# .agents/slop/e2e_mm.py -- THE ORACLE AND THE FIXTURE GENERATOR for the one
# computation this project has never proved: a matmul, run through the Bend
# port's WebGPU call layer on a real GPU, compared against tinygrad's answer on
# the identical input.
#
# WHY A GENERATED .bend, and why that is not "a fixture that restates the port".
# The lane needs three things Bend cannot obtain for itself: tinygrad's OWN WGSL
# for the kernel, the input BYTES, and the dispatch geometry. All three are
# littlegrad's answers to its own questions, so they are produced by CALLING
# CPython here and written into the .bend as literals. What the .bend then builds
# -- the buffer creations, the writes, the shader module, the bind group layout,
# the bind group, the pipeline, the encoder, the pass, the dispatch, the finish,
# the submit, the staging copy, the map and the readback -- is NOT written here
# and NOT transcribed: it is `Cs.call` and friends, called, unmodified, from
# tinybendygrad/runtime/webgpu_call.bend. A generator that re-implemented the
# call sequence would be testing itself; this one only supplies what a `dev` would
# supply.
#
# THE COMPUTATION. `(A @ B) @ C`, three 8x8 f32 matrices, TWO launches, because
# the second launch's first input is the FIRST launch's output. That is the whole
# point of choosing two: if the port re-uploaded the intermediate, or bound the
# wrong buffer, the answer is wrong, and an all-equal fixture cannot see it.
# `mm_writes` is the row that catches a re-upload, because its expectation is the
# number of buffers no earlier launch wrote, counted here from the trace.
#
# EVERY NUMBER IN THE .bend AND IN THE ORACLE COMES FROM CALLING CPYTHON. Nothing
# is typed. `runs/e2e/e2e-mm-oracle.json` is the record of the call, and the gate
# refuses any row whose name is not in it.
#
# RUN:  .venv/bin/python .agents/slop/e2e_mm.py
#      -> runs/e2e/e2e-mm-oracle.json   and   .agents/slop/e2e_mm.bend

import base64, json, os, re, sys
from pathlib import Path

os.environ.setdefault("DEV", "CPU")
os.environ.setdefault("NO_MEMORY_PLANNER", "1")   # one storage per buffer: no aliasing
os.environ.setdefault("BEAM", "0")
os.environ.setdefault("CACHELEVEL", "0")          # the traced pass must not hit a cache

import numpy as np
from tinygrad import Tensor
from tinygrad.codegen import to_program
from tinygrad.renderer.wgsl import WGSLRenderer
from tinygrad.device import Device
from tinygrad.uop.ops import Ops, PatternMatcher, UPat
import tinygrad.engine.realize as RZ

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "runs/e2e"
BEND = ROOT / ".agents/slop/e2e_mm.bend"

M = K = N = 8                      # 8x8 f32 = 256 bytes = 64 u32 per buffer
SEED = 0x5EED                      # one seed, so the fixture is reproducible
BASE_ID = 100                      # `bufs3`'s convention: a caller's id cannot
                                   # collide with a slot the seam mints

# THE INPUT VALUES, AND WHY THEY ARE DYADIC RATHER THAN RANDOM. This is the whole
# reason the E2E can claim BIT-EXACTNESS instead of a tolerance, so it is a
# theorem and not a hope:
#
#   every entry is a multiple of 2^-6 (0.015625) with |entry| <= 2;
#   every product of two of them is a multiple of 2^-12 with |product| <= 4;
#   every PARTIAL SUM of the eight products is a multiple of 2^-12 with
#     |partial| <= 32, so it needs at most 18 significand bits;
#   f32 has a 24-bit significand, so every partial sum is EXACTLY representable.
#
# A sum of exactly-representable values is the same value in any association order
# and under any multiply-add CONTRACTION, because no rounding ever occurs. So the
# CPU's answer and the GPU's answer are the same bits whichever one of them fuses
# and whichever order the eight terms are added in.
#
# WHY THAT MATTERED. With `np.random.randn` inputs the GPU and CPython disagreed by
# up to 2.86e-6 absolute, and the cause was measured rather than guessed:
# `tinygrad/runtime/support/compiler_cpu.py:21` compiles the generated C with `-O2`
# and no `-ffp-contract=off`, and the LLVM IR for that exact kernel contains
# `llvm.fmuladd` -- 57 of them at `-O2` and ZERO with the flag added. So the CPU
# contracts; the WGSL path (Tint -> SPIR-V -> MSL on this `apple/metal-3` adapter)
# contracts too, differently. Neither side is the reference and no tolerance can
# settle it, so the inputs are chosen where contraction is a theorem instead of a
# difference. The random-input distance is recorded in the run notes as the
# measurement that forced this choice.
DYADIC = [-2.0, -1.5, -0.75, -0.5, -0.25, 0.25, 0.5, 1.5]
ENTRY_RE = re.compile(r"@compute[^\n]*\bfn\s+(\w+)\s*\(", re.M)
# `@group(0) @binding(N) var<uniform|storage,...>` -- the layout tinygrad's OWN
# emitted WGSL declares, parsed rather than transcribed, so the port's
# `bgl.flat` answer is checked against the shader and not against a comment.
BIND_RE = re.compile(r"@group\(0\)\s*@binding\((\d+)\)\s*var<(uniform|storage[^>]*)>")


class Renderer(WGSLRenderer):
  """`trace_forward.py`'s GAP 2 verbatim, and it is the ONLY shim: a matmul's
  WGSL stacks four f32 into a `vec4`, `WGSLRenderer.supports_float4` is False,
  and that flag is read in only one place (codegen/late/coalesce.py:143), so a
  STACK still reaches `CStyleLanguage.string_rewrite` with `float4 = None` and
  raises AttributeError. The arity is the stack's own src count and the element
  type is `type_map[x.dtype]`, NOT `render_type(x)` -- a GLOBAL source renders as
  `var<storage,read_write>f32`, a type WGSL has no `vec<...>` of.

  GAP 1 (`code_for_op` has no `Ops.FDIV`) is NOT shimmed here, and its absence is
  deliberate: a matmul chain has no division, so shimming it would widen the
  fixture past the program under test. Softmax does divide -- measured, and it is
  why the program is `(A@B)@C` and not `(A@B).softmax()`.
  """
  string_rewrite = PatternMatcher([
    (UPat(Ops.STACK, name="x"),
     lambda ctx, x: f"vec{len(x.src)}<{ctx.type_map[x.dtype]}>({','.join(ctx[y] for y in x.src)})"),
  ]) + WGSLRenderer.string_rewrite


renderer = Renderer(Device["CPU"])
_orig_exec_kernel = RZ.exec_kernel
launches = []
_names, _keep, _order = {}, [], [0]


def bits_of(buf):
  """The buffer's bytes, base64'd. The words are u32 either way; base64 is only a
  transport, and the readback comes back through the same one, so a disagreement
  cannot be a printed-decimal rounding artefact."""
  raw = bytes(buf.as_memoryview(allow_zero_copy=True))
  assert len(raw) % 4 == 0, f"{buf.dtype} is not 4-byte items"
  return raw


def u32_of(raw):
  """u32 little-endian bit patterns -- the READBACK's unit, and the oracle's."""
  return [int(w) for w in np.frombuffer(raw, dtype="<u4")]


def bytes_of(raw):
  """ONE BYTE PER ELEMENT, and that is not the same list as `u32_of`. `WriteBuffer`'s
  `bytes` field is a byte list: `webgpu_call.js` does `Uint8Array.from(bytes)`, so a
  u32 word there truncates to its LOW byte and the other three become zero. MEASURED
  by getting it wrong: the first GPU run returned 0x7FC00000 (a quiet NaN) in every
  element, because both inputs were three-quarters zeros. `Uniform`'s bytes are the
  same shape -- the gate row `wgc_wall3_int_bytes` reads `[7, 0, 0, 0]` for the
  value 7 -- so this is the port's own unit and not an accident of the driver."""
  return list(raw)


def name_of(buf):
  """A buffer's stable name, keyed on the STORAGE owner. The strong ref is
  load-bearing: `trace_forward.py` measured that without it CPython frees the
  Buffer and hands the same id to the next allocation, which made a launch report
  buffers it provably never touched. All three matrices here are 64 bytes, so
  SIZE cannot identify a buffer and the id map is the only thing that can."""
  key = id(buf.base)
  if key not in _names:
    _names[key] = f"b{_order[0]}"
    _order[0] += 1
    _keep.append(buf.base)
  return _names[key]


def traced_exec_kernel(ctx, call, ast, devices=None):
  resolved = RZ.resolve_params(call, ctx.input_uops)
  for device, (bufs, device_vars) in zip(devices or RZ.to_tuple(call.src[1].device),
                                         RZ.unwrap_multi(call, [resolved[i] for i in ast.arg.globals])):
    var_vals = {**ctx.var_vals, **device_vars}
    g, l = ast.arg.launch_dims(var_vals)
    rec = {"names": [], "global": list(g), "local": list(l), "vals": list(ast.arg.vals(var_vals))}
    prg = to_program(ast.src[0], renderer)          # the SAME ast, rendered to WGSL
    src = [str(u.arg) for u in prg.src if u.op is Ops.SOURCE]
    rec["wgsl"] = src[0]
    m = ENTRY_RE.search(rec["wgsl"])
    # The entry point is read back OUT OF THE WGSL rather than from the uop graph:
    # that string is what reaches `createComputePipeline`, so one source of truth
    # decides both sides. `trace_forward.py` does the same and says why.
    rec["entry"] = m.group(1) if m else None
    rec["bindings"] = [[int(b), k] for b, k in BIND_RE.findall(rec["wgsl"])]
    for b in bufs:
      rec["names"].append(name_of(b))
    # OUTPUT POSITIONS: `ProgramInfo.globals` is position -> buffer slot and
    # `ProgramInfo.outs` is a set of slots, so a position is an output iff its
    # slot is in outs. The page needs this to know which buffers it must upload.
    out_slots = set(ast.arg.outs)
    rec["outs"] = [pos for pos, slot in enumerate(ast.arg.globals) if slot in out_slots]
    rec["_bufs"] = [b.ensure_allocated() for b in bufs]
    # INPUT BYTES, read BEFORE the launch. Only a buffer no earlier launch wrote:
    # one an earlier launch wrote is already correct on the GPU by the time this
    # launch reads it, and re-uploading it would turn a computation into a memory
    # dump. `trace_forward.py` states the rule and measures what happens without
    # it. `NO_MEMORY_PLANNER=1` gives one storage per buffer, so a read here is
    # the tensor's own bytes and not an alias.
    for pos, b in enumerate(rec["_bufs"]):
      if pos not in rec["outs"]:
        rec.setdefault("in", {})[rec["names"][pos]] = base64.b64encode(bits_of(b)).decode()
    launches.append(rec)
  return _orig_exec_kernel(ctx, call, ast, devices)


def snapshot(launches_):
  """`in`/`after` for every launch, folded in one place so the ORDER of the read
  relative to the launch is stated once. `in` was taken before the launch inside
  the trace; `after` is taken here, after the whole program, which is the same
  thing for every buffer the program does not write after its last use."""
  for r in launches_:
    for pos, nm in enumerate(r["names"]):
      r.setdefault("after", {})[nm] = base64.b64encode(bits_of(r["_bufs"][pos])).decode()


def trace():
  RZ._orig_exec_kernel = _orig_exec_kernel
  RZ.exec_kernel = traced_exec_kernel
  rng = np.random.RandomState(SEED)
  pick = lambda r, c: Tensor(np.array(DYADIC, dtype=np.float32)[rng.randint(0, len(DYADIC), (r, c))])
  A = pick(M, K)
  B = pick(K, N)
  Cm = pick(N, N)
  E = (A.matmul(B)).matmul(Cm)          # the program: two launches, one buffer chained
  real = E.realize()
  RZ.exec_kernel = _orig_exec_kernel
  snapshot(launches)
  return real, {"A": A.numpy().copy(), "B": B.numpy().copy(), "Cm": Cm.numpy().copy()}


def main():
  OUT.mkdir(parents=True, exist_ok=True)
  E, mats = trace()
  for r in launches:
    r.pop("_bufs", None)

  if len(launches) != 2:
    sys.exit(f"expected 2 launches, traced {len(launches)} -- a zero-launch trace "
             f"reads exactly like a program that computes nothing (trace_forward.py)")

  # ---- the id map: first-bind order, from BASE_ID, as `bufs3` does ----------
  first_bind, ids, sizes = [], {}, {}
  for r in launches:
    for nm in r["names"]:
      if nm not in ids:
        ids[nm] = BASE_ID + len(ids)
        first_bind.append(nm)
  for nm in first_bind:
    sizes[nm] = next(len(base64.b64decode(r["after"][nm])) for r in launches if nm in r["after"])

  # ---- the upload list: a buffer no EARLIER launch wrote --------------------
  written, uploads = set(), []
  for i, r in enumerate(launches):
    for nm in r["names"]:
      if nm not in written and nm not in [u[0] for u in uploads] and nm in r.get("in", {}):
        uploads.append((nm, bytes_of(base64.b64decode(r["in"][nm]))))
    written.update(r["names"][p] for p in r["outs"])

  # ---- CPython's answer, and the reference for each launch's output ---------
  #
  # THE FINAL BUFFER IS THE LAST LAUNCH'S OUTPUT, and getting this wrong is not
  # hypothetical. `first_bind[-1]` is the last buffer to be BOUND, which for
  # `(A @ B) @ C` is `C` -- an INPUT of the last launch, not its result. tinygrad
  # gives the output slot 0, so the launch's buffers read `[out, in, in]` and the
  # first-bind order ends on the last input. MEASURED here: reading `b4` back
  # would have compared `C` against the answer and found them unequal.
  answer = u32_of(bits_of(E.uop.base.realized))
  last = launches[-1]
  assert len(last["outs"]) == 1, f"expected one output position, got {last['outs']}"
  final = last["names"][last["outs"][0]]
  # The answer must be the bytes OF THAT BUFFER, or the readback and the
  # expectation are about different tensors.
  final_after = u32_of(base64.b64decode(last["after"][final]))
  if final_after != answer:
    sys.exit(f"answer is not the final buffer's bytes: {final} {final_after[:4]} vs {answer[:4]}")
  oracle = {
    "note": "every value below was produced by CALLING CPython tinygrad (DEV=CPU) in "
            "this file; nothing here is transcribed. u32 little-endian bit patterns.",
    "program": "(A @ B) @ C, three 8x8 f32 matrices, entries drawn from "
               "DYADIC by np.random.RandomState(0x5EED); see the DYADIC note at "
               "the top of this file for why every partial sum is exact in f32.",
    "dyadic": DYADIC,
    "shape": {"M": M, "K": K, "N": N},
    "seed": SEED,
    "mats": {k: u32_of(v.tobytes()) for k, v in mats.items()},
    "mat_tensors": {k: [int(x) for x in v.reshape(-1)] for k, v in mats.items()},
    "launches": len(launches),
    "per_launch": [{"entry": r["entry"], "global": r["global"], "local": r["local"],
                    "names": r["names"], "ids": [ids[nm] for nm in r["names"]],
                    "bufs": [ids[nm] for nm in r["names"]],
                    "sizes": [sizes[nm] for nm in r["names"]],
                    "outs": r["outs"], "vals": r["vals"],
                    "bindings": r["bindings"], "wgsl_b64": base64.b64encode(r["wgsl"].encode()).decode()}
                   for r in launches],
    "ids": ids, "first_bind": first_bind, "sizes": sizes,
    "uploads": [[nm, ws] for nm, ws in uploads],
    "upload_words": len([w for _, ws in uploads for w in ws]),
    "final_buffer": final,
    "probe_buffer": uploads[0][0],
    "probe_bytes_u32": uploads[0][1],
    "answer_u32": answer,
    "answer_f64": [float(np.frombuffer(np.uint32(x).tobytes(), dtype="<f4")[0]) for x in answer],
    "csum_f64": float(E.numpy().sum()),
  }
  (OUT / "e2e-mm-oracle.json").write_text(json.dumps(oracle, indent=1) + "\n")

  # ---- the .bend ------------------------------------------------------------
  BEND.write_text(emit_bend(oracle))
  print(f"launches {len(launches)}  uploads {len(uploads)} ({oracle['upload_words']} words)  "
        f"ids {ids}  answer_u32[:4]={answer[:4]}  csum={oracle['csum_f64']:.6f}")
  print(f"wrote {BEND.relative_to(ROOT)} and {(OUT / 'e2e-mm-oracle.json').relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# THE .bend. Generated. Every literal in it is a value this file obtained by
# CALLING CPython; every step in it is a `webgpu_call.bend` def, called
# unmodified. The WGSL is escaped rather than wrapped because a wrapped literal
# would be a second hand-made copy of the shader, and a shader that differs by a
# space is a different program.
# ---------------------------------------------------------------------------
def bend_str(s):
  return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def u32s(words):
  return "[" + ",".join(str(w) for w in words) + "]"


def emit_bend(o):
  L = o["per_launch"]
  out = []
  A = out.append
  A(BEND_HEADER)
  A("")
  A("# ---------------------------------------------------------------------------")
  A("# THE BUFFERS. One id each, in FIRST-BIND order from 100 -- `bufs3`'s")
  A("# convention and for its reason: a caller's id must never collide with a slot")
  A("# the seam mints. Every one is the same size, so SIZE cannot identify a")
  A("# buffer and the id is the only identity there is.")
  for nm in o["first_bind"]:
    A(f"def id_{nm}() -> U32: {o['ids'][nm]}")
    A(f"def size_{nm}() -> U32: {o['sizes'][nm]}")
  A("")
  A("# THE BYTES EACH BUFFER IS WRITTEN WITH -- BYTES, one per element, because")
  A("# `WriteBuffer`'s field is a byte list (`webgpu_call.js` does")
  A("# `Uint8Array.from(bytes)`), NOT the u32 words the readback is compared in.")
  A("# `mm_uploads` is the number of WriteBuffers the run must issue and it is a gate")
  A("# row, because it is what says the port did NOT re-upload launch 0's output.")
  for nm, bs in o["uploads"]:
    A(f"def bytes_{nm}() -> List<&2, U32>: {u32s(bs)}")
  A(f"def mm_upload_count() -> U32: {len(o['uploads'])}")
  A("")
  A("# THE BIND LISTS, one per launch, in `ProgramInfo.globals` order -- the order")
  A("# tinygrad's own WGSL binds them, checked against the shader by the gate.")
  for i, r in enumerate(L):
    bufs = ", ".join(f"W.Buf{{id_{nm}(), size_{nm}()}}" for nm in r["names"])
    A(f"def bufs{i}() -> List<&2, W.Buf>: [{bufs}]")
  A("")
  A("# THE SHADERS, ENTRIES AND GEOMETRY, from `renderer/wgsl.py` and")
  A("# `ProgramInfo.launch_dims` on the ast the CPU executed. `local_size` is")
  A("# recorded and never dispatched on: ops_webgpu.py never reads it and the")
  A("# workgroup size is the WGSL attribute.")
  for i, r in enumerate(L):
    wgsl = base64.b64decode(r["wgsl_b64"]).decode()
    A(f"def entry{i}() -> String: {bend_str(r['entry'])}")
    A(f"def wgsl{i}() -> String: {bend_str(wgsl)}")
    for ax, v in zip("xyz", r["global"]):
      A(f"def g{ax}{i}() -> U32: {v}")
  A("")
  A(BEND_DEFS)
  for i in range(len(L)):
    A(f"def l{i}() -> G.Cs: G.Cs.call(bufs{i}(), 0n, Nil{{}}, gx{i}(), gy{i}(), gz{i}(), "
      f"False{{}}, Nil{{}}, entry{i}(), wgsl{i}())")
  A("")
  # `mm_buffers` and `mm_read` are SPELLED OUT from the oracle's own lists, so a
  # fixture with a different number of buffers or uploads needs no edit here and
  # cannot drift from the trace that produced it. The first version wrote
  # `mkbuf(size_b0()) .. size_b4()` and `putbytes(id_b0(), words_b0())` by hand and
  # did not compile: the trace's upload list is b1, b2, b4 -- tinygrad gives the
  # OUTPUT slot 0, so a launch's buffers read `[out, in, in]` and the intermediate
  # is the FIRST buffer of launch 0, not the first input. The readback likewise is
  # not `b4`.
  A("")
  A("# THE DEVICE BUFFERS, one `CreateBuffer` each in first-bind order, then one")
  A("# `putbytes` per upload in the oracle's order. Spelled out from the oracle's")
  A("# own lists so a different fixture needs no edit here and cannot drift from")
  A("# the trace that produced it.")
  chain = "G.Cs.of()"
  for nm in o["first_bind"]:
    A(f"def mkbuf_{nm}(+c: G.Cs) -> G.Cs: mkbuf(c, id_{nm}(), size_{nm}())")
    chain = f"mkbuf_{nm}({chain})"
  A("")
  A("def mm_buffers() -> G.Cs:")
  A(f"  c = {chain}")
  for nm, _ in o["uploads"]:
    A(f"  c = putbytes(c, id_{nm}(), bytes_{nm}())")
  A("  c")
  A("")
  A("# TWO READBACKS OF THE SAME RUN, and the second one is what makes the first one")
  A("# interpretable. `mm_read_out` maps the ANSWER; `mm_read_in` maps an UPLOADED")
  A("# INPUT. If `mm_read_in` comes back bit-identical to the words that were written,")
  A("# then the buffers held exactly what CPython held and any difference in the")
  A("# answer is the ARITHMETIC; if it does not, the difference is the DATA and the")
  A("# arithmetic is not what needs looking at. One number cannot tell those apart.")
  A("#")
  A("# They are two `walk`es rather than two `MappedRange`es in one, because")
  A("# `webgpu_call.js` keeps only the LAST mapped range (`m.range` is overwritten),")
  A("# so a single walk would silently drop the first readback -- a null range that")
  A("# reads as an empty answer rather than as a missing one.")
  fin = o["final_buffer"]
  probe = o["uploads"][0][0]
  for nm, label in ((fin, "out"), (probe, "in")):
    A(f"def mm_read_{label}() -> G.Cs:")
    A(f"  +r = G.Cs.readable(G.Cs.of(), id_{nm}(), size_{nm}())")
    A(f"  G.Cs.read(r, G.Cs.next(G.Cs.of()), size_{nm}())")
  A("")
  A("def mm_read() -> G.Cs: mm_read_out()")
  A("# THE WHOLE RUN, as the `List<&2, G.Cs>` `webgpu_call.js`'s `walk` consumes: the")
  A("# device init, the device buffers, the two launches, the staging read.")
  A("#")
  A("# `mm_read` is `Cs.timing.on` with the wait arm off. `Cs.readable` mints the")
  A("# STAGING buffer first, so its handle is `Cs.next` of the state it was handed")
  A("# -- `webgpu_call.bend` names the mistake: `next(r) - 1` is the command buffer")
  A("# and the walk stops with \"unbound slot\".")
  A("def mm_prefix() -> List<&2, G.Cs>: [G.Cs.init(G.METAL(), Nil{}), mm_buffers(), l0(), l1()]")
  A("def mm_run() -> List<&2, G.Cs>: List.append(&2, G.Cs, mm_prefix(), [mm_read_out()])")
  A("def mm_run_in() -> List<&2, G.Cs>: List.append(&2, G.Cs, mm_prefix(), [mm_read_in()])")
  A("")
  A(BEND_MAIN)
  return "\n".join(out) + "\n"


BEND_HEADER = r'''# .agents/slop/e2e_mm.bend -- GENERATED by .agents/slop/e2e_mm.py. DO NOT EDIT.
#
# WHAT THIS IS. The one computation in this repo that is proved rather than
# counted: `(A @ B) @ C` for three 8x8 f32 matrices, dispatched by
# tinybendygrad/runtime/webgpu_call.bend's OWN call layer -- `Cs.call`,
# `Cs.readable`, `Cs.read` -- onto a real WebGPU adapter, and read back bit for
# bit against CPython tinygrad's answer on the identical bytes.
#
# PORT OR FIXTURE. The call sequence is the port's: every step below is a
# `webgpu_call.bend` def called unmodified, and no step order, buffer size, usage
# mask or binding index is written here. The fixture is the literals the generator
# got by CALLING CPython -- tinygrad's own WGSL, the input words, the geometry.
# The gate's expectations live in runs/e2e/e2e-mm-oracle.json, beside the call
# that made them, and the gate refuses any row whose name is not there.
#
# WHY TWO LAUNCHES. The second launch's first input is the FIRST launch's output,
# so the intermediate must have been computed ON THE GPU. A one-launch program
# could be satisfied by re-uploading everything, and `mm_uploads_eq_fixture` --
# whose expectation is the number of buffers no earlier launch wrote, counted in
# the generator -- is the row that says the re-upload did not happen. An
# all-equal fixture cannot detect that, and neither can a single launch.
#
# GENERATED, so the WGSL is escaped into a string literal rather than wrapped: a
# wrapped literal would be a second hand-made copy of the shader.

import Base
import ../../tinybendygrad/runtime/ops_webgpu.bend as W
import ../../tinybendygrad/runtime/webgpu_call.bend as G
'''


BEND_DEFS = r'''
# ---------------------------------------------------------------------------
# THE DEVICE BUFFERS. `Cs.call` begins at `Cs.of()`, so the buffers are their own
# `Cs` and `webgpu_call.js`'s `walk` concatenates the step lists through ONE
# machine -- a `Cs` per phase is how that driver is meant to be driven, not a
# workaround. `WriteBuffer`'s `(CALL_WRITE, write_len)` pair is `copy.copyin`'s
# own emission (ops_webgpu.py:221), not a shape invented for this file.
# ---------------------------------------------------------------------------
# THE HANDLE IS THE CALLER'S OWN ID, NOT A MINT. `webgpu_call.bend` binds a `bufs`
# slot to `bs[i-1].id` -- the caller's id -- precisely so the seam's minted slots and
# the caller's buffers are two namespaces a collision would be visible in, and
# `webgpu_call.js`'s `buf()` resolves `m.slots.get(id) ?? m.owned.get(id)`. So the
# `CreateBuffer` op carries `id_bN` as its `slot`, and `Cs.mint` is not called here
# at all. MEASURED the other way round: minting and then writing to `id_bN` stopped
# the walk at step 13 of 84 with "unbound slot 101", because the create was filed
# under 1 and the write asked for 101.
def mkbuf(+c: G.Cs, id: U32, size: U32) -> G.Cs:
  G.Cs.at(c, W.CALL_CREATE, W.OBJ_BUFFER, G.CreateBuffer{id, size, W.alloc.usage()})

def putbytes(+c: G.Cs, buf: U32, +bytes: List<&2, U32>) -> G.Cs:
  G.Cs.at(c, W.CALL_WRITE, W.copy.write_len(U32.from_nat(List.length(&2, U32, bytes))),
          G.WriteBuffer{buf, bytes})

def one(v: U32) -> List<&2, U32>: [v]

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)
'''


BEND_MAIN = r'''
# ---------------------------------------------------------------------------
# THE PURE HALF, and it runs with no GPU at all:
#   ./bin/bend .agents/slop/e2e_mm.bend
# Every row is read off a `Cs` the driver later executes, so a wrong row here is a
# wrong PROGRAM and not a wrong number about the program.
# ---------------------------------------------------------------------------
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), ",")]))

def t_buffers() -> IO(Unit):
  do IO<Unit>:
    +c : G.Cs <- IO.pure(G.Cs, mm_buffers())
    lrow("mm_buffer_len", one(G.Cs.len(c)))
    lrow("mm_uploads", one(G.Cs.count(W.CALL_WRITE, c)))
    row("mm_uploads_eq_fixture", U32.is_eq(G.Cs.count(W.CALL_WRITE, c), mm_upload_count()))
    lrow("mm_usage", one(W.alloc.usage()))
    lrow("mm_readable_usage", one(W.copy.readable_usage()))

def t_launch0() -> IO(Unit):
  do IO<Unit>:
    +c : G.Cs <- IO.pure(G.Cs, l0())
    lrow("mm_l0_len", one(G.Cs.len(c)))
    lrow("mm_l0_bg_sizes", G.Cs.bg_sizes(G.Cs.bg(c)))
    lrow("mm_l0_bg_ids", G.Cs.bg_ids(G.Cs.bg(c)))
    lrow("mm_l0_bg_bufs", G.Cs.bg_bufs(G.Cs.bg(c)))
    row("mm_l0_nowait", Bool.not(G.Cs.wait(c)))

def t_launch1() -> IO(Unit):
  do IO<Unit>:
    +c : G.Cs <- IO.pure(G.Cs, l1())
    lrow("mm_l1_len", one(G.Cs.len(c)))
    lrow("mm_l1_bg_sizes", G.Cs.bg_sizes(G.Cs.bg(c)))
    lrow("mm_l1_bg_ids", G.Cs.bg_ids(G.Cs.bg(c)))
    lrow("mm_l1_bg_bufs", G.Cs.bg_bufs(G.Cs.bg(c)))
    row("mm_l1_nowait", Bool.not(G.Cs.wait(c)))

# THE BIND GROUP LAYOUT THE PORT DERIVES, as `(binding, type)` pairs. This is the
# one row that is not a restatement: the gate compares it against the bindings
# tinygrad's OWN WGSL declares, which this generator PARSED out of the shader.
def t_layout() -> IO(Unit):
  do IO<Unit>:
    lrow("mm_layout", W.bgl.flat(W.bgl.of(3, 0), Nil{}))
    lrow("mm_layout_n", one(U32.from_nat(List.length(&2, W.Bgl, W.bgl.of(3, 0)))))
    lrow("mm_bind_uniform", one(W.BIND_UNIFORM()))
    lrow("mm_bind_storage", one(W.BIND_STORAGE()))

def t_read() -> IO(Unit):
  do IO<Unit>:
    +c : G.Cs <- IO.pure(G.Cs, mm_read())
    lrow("mm_read_len", one(G.Cs.len(c)))
    lrow("mm_read_slots", G.Cs.slots(c))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_buffers()
    b : Unit <- t_launch0()
    c : Unit <- t_launch1()
    d : Unit <- t_layout()
    e : Unit <- t_read()
    IO.print("e2e-mm-done=1")
'''


if __name__ == "__main__":
  main()
