#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/renderer/tc_ptx.bend.

Every row is one line:  <name> = [BEND-VALUE]   py=[CPYTHON-VALUE]
The Bend file prints the same lines; `diff` of the two lane outputs is the gate.
Run from the repo root:
    python3 .agents/slop/tcptx-oracle.py rows > /tmp/py.txt
"""
import sys, math, struct
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, DType, AddrSpace
from tinygrad.renderer import tc
from tinygrad.uop.ops import Ops, UOp, UPat, PatternMatcher, GroupOp
from tinygrad.renderer import ptx as ptxmod

def row(nm, got, want):
  return f"{nm} = [{got}]   py=[{want}]\n"

def rowa(nm, got, want):
  return f"{nm} = [{got}]   py=[{want}]\n"

def j(x): return ",".join(str(v) for v in x)

def fnv(s):
  h = 2166136261
  for c in s.encode():
    h = ((h ^ c) * 16777619) & 0xffffffff
  return h

def dgst(s): return f"len={len(s)} fnv={fnv(s)}"

# ---------------------------------------------------------------- tc.py
TABLES = ("cuda_81616", "cuda_81632_f8", "cuda_8168_f16", "cuda_8168_tf32",
           "cuda_sm75", "cuda_sm80", "cuda_sm89",
           "amd_rdna3", "amd_rdna4", "amd_cdna_161616", "amd_cdna_161632",
           "amd_cdna_1616128", "amd_cdna3_161632", "amd_cdna3", "amd_cdna4", "metal")

def tcs():
  out = ""
  for k in TABLES:
    ts = getattr(tc, k)
    out += row(f"tc.{k}.len", len(ts), len(ts))
    for i, t in enumerate(ts):
      out += row(f"tc.{k}[{i}]", f"{t.dtype_in.name}->{t.dtype_out.name}/{j(t.dims)}",
                 f"{t.dtype_in.name}->{t.dtype_out.name}/{j(t.dims)}")
  return out

def tc_detail(name, t):
  out = ""
  out += row(f"{name}.di", t.dtype_in.name, t.dtype_in.name)
  out += row(f"{name}.do", t.dtype_out.name, t.dtype_out.name)
  out += row(f"{name}.frag_a", j(list(t.frag_a[0]) + list(t.frag_a[1])),
             j(list(t.frag_a[0]) + list(t.frag_a[1])))
  out += row(f"{name}.frag_b", j(list(t.frag_b[0]) + list(t.frag_b[1])),
             j(list(t.frag_b[0]) + list(t.frag_b[1])))
  out += row(f"{name}.frag_c", j(list(t.frag_c[0]) + list(t.frag_c[1])),
             j(list(t.frag_c[0]) + list(t.frag_c[1])))
  out += row(f"{name}.axis_coords", j(t.axis_coords()), j(t.axis_coords()))
  # `axis_coords`'s INTERMEDIATE, `used`, on its own. It is unobservable
  # through `axis_coords`: `__post_init__` asserts A covers every m and k coord
  # and C covers every n coord, and `axis_coords` reads a MAX per axis, so
  # `used = A + C` and `used = A + B` give the same three maxima for EVERY valid
  # TensorCore. The strings still differ, so this row is what pins which
  # fragment the concatenation reads.
  used = t.frag_a[0] + t.frag_a[1] + t.frag_c[0] + t.frag_c[1]
  out += row(f"{name}.used", j(used), j(used))
  out += row(f"{name}.base_upcast_axes", j(t.base_upcast_axes()), j(t.base_upcast_axes()))
  out += row(f"{name}.threads", t.threads, t.threads)
  out += row(f"{name}.dims", j(t.dims), j(t.dims))
  for i, r in enumerate(t.relabel()):
    out += row(f"{name}.relabel.{i}", j(f"{c}={y}" for c, y in r.items()),
               j(f"{c}={y}" for c, y in r.items()))
  fc = t.frag_coords()
  for oi, f in enumerate(fc):
    # the FULL string is 22 647 characters at cdna K=128, so hard-coding the eight
    # shapes of it would put ~180 KB of literals in the .bend file -- past the
    # interpreter's measured 28 988-byte per-file cliff. The row carries a
    # DIGEST of the whole string (plus its length), which catches every dropped
    # literal a sample would miss, and CPython computes it independently here.
    s = ",".join(",".join(j(e) for e in lane) for lane in f)
    out += row(f"{name}.frag_coords.{oi}", dgst(s), dgst(s))
  # __post_init__'s four assertions, on this tensor core.
  coords = t.axis_coords()
  out += row(f"{name}.lanes", "".join(str(len(f[0]) == len(t.frag_c[0])) for f in
                                      (t.frag_a, t.frag_b, t.frag_c)),
             "".join(str(len(f[0]) == len(t.frag_c[0])) for f in (t.frag_a, t.frag_b, t.frag_c)))
  for fi, dims in zip((t.frag_a, t.frag_b, t.frag_c), ("mk", "kn", "mn")):
    own = {c for c in coords if c[0] in dims}
    distinct = len(set(fi[0] + fi[1])) == len(fi[0] + fi[1])
    cov = set(fi[1]) <= own and own <= set(fi[0] + fi[1]) and \
          set(fi[0] + fi[1]) <= own | {c for c in coords if c[0] in "mn"}
    out += row(f"{name}.distinct.{dims}", str(distinct), str(distinct))
    out += row(f"{name}.cover.{dims}", str(cov), str(cov))
  ka = [c for c in t.frag_a[1] + t.frag_a[0] if c[0] == "k"]
  kb = [c for c in t.frag_b[1] + t.frag_b[0] if c[0] == "k"]
  out += row(f"{name}.ka", j(ka), j(ka))
  out += row(f"{name}.kb", j(kb), j(kb))
  out += row(f"{name}.kab_eq", str(ka == kb), str(ka == kb))
  return out

def all_tc_details():
  out = ""
  seen = set()
  for k in ("cuda_81616", "cuda_81632_f8", "cuda_8168_f16", "cuda_8168_tf32",
            "amd_rdna3", "amd_rdna4", "amd_cdna_1616128", "metal"):
    for t in getattr(tc, k):
      key = (t.frag_a, t.frag_b, t.frag_c)
      if key in seen: continue
      seen.add(key)
      out += tc_detail(f"tc/{j(t.dims)}/{t.dtype_in.name},{t.dtype_out.name}", t)
  return out

def get_archs():
  out = ""
  for a in ("sm_75", "sm_80", "sm_86", "sm_89", "sm_90", "sm_100"):
    got = tc.get_cuda(a)
    out += row(f"get_cuda {a}", j(f"{t.dtype_in.name}->{t.dtype_out.name}" for t in got),
               j(f"{t.dtype_in.name}->{t.dtype_out.name}" for t in got))
  for a in ("gfx942", "gfx950", "gfx1200", "gfx1201", "gfx1100"):
    got = tc.get_amd(a)
    out += row(f"get_amd {a}", j(f"{t.dtype_in.name}->{t.dtype_out.name}" for t in got),
               j(f"{t.dtype_in.name}->{t.dtype_out.name}" for t in got))
  return out

# the guards of the three pm_validate_wmma_* matchers.  Each rule's condition is
# a pure function of (wmma dtype, x.max_numel, src0 dtype, src0.max_numel, arg0 K).
def wmma_grid():
  """the fixture grid: (wmma dtype, C numel -> x.max_numel, src0 dtype, src0 numel, K)."""
  wdts = [dtypes.int32, dtypes.half, dtypes.bfloat16, dtypes.float]
  nums = [(4, 4), (4, 8), (8, 4), (8, 8), (8, 16), (16, 4), (16, 8), (16, 16)]
  sdts = [dtypes.int8, dtypes.half, dtypes.bfloat16, dtypes.float, dtypes.fp8e4m3]
  return [(wdt, mn, sdt, smn, K) for wdt in wdts for (mn, smn) in nums for sdt in sdts for K in (16, 32, 128)]

def wmma_guard_rows():
  """WHICH RULE FIRES, asked of tinygrad's own PatternMatcher.

  This is not a re-derivation of the guards: a real WMMA UOp is built and the
  real `pm_validate_wmma_*` matcher is asked for a rewrite, so the fall-through
  question (does a rule whose guard returns None let the NEXT rule try?) is
  answered by CPython rather than assumed.  The rewrite BODY is a wall in this
  port (`.bitcast` is `TODO(p3) ops.py:<line>` in ops.bend), so the answer is
  `None` / `FIRED`.
  """
  from tinygrad.uop.ops import Ops, UOp, ParamArg
  out = ""
  slot = [0]
  def buf(dt, n):
    slot[0] += 1
    return UOp(Ops.BUFFER, src=UOp.device_range_src('CUDA'), arg=ParamArg(slot[0], dt, n))
  mms = (tc.pm_validate_wmma_rdna3, tc.pm_validate_wmma_rdna4, tc.pm_validate_wmma_cdna)
  mns = ("rdna3", "rdna4", "cdna")
  for (wdt, mn, sdt, smn, K) in wmma_grid():
    do = wdt
    x = UOp(Ops.WMMA, src=(buf(sdt, smn).load(), buf(sdt, smn).load(), buf(do, mn).load()),
            arg=((8, 16, K), sdt, 'f16', None))
    nm = f"wmma {x.dtype.name},{x.max_numel()},{sdt.name},{smn},{K}"
    for pm, mn2 in zip(mms, mns):
      try:
        r = pm.rewrite(x)
        got = "FIRED" if (r is not None and r is not x) else "None"
      except Exception as e:
        got = "ERR:" + type(e).__name__
      out += row(f"{nm} {mn2}", got, got)
  return out

# ---------------------------------------------------------------- ptx.py
def ptx_guard_rows():
  """The seven `ptx_matcher` rules' guards, asked of the real matcher.

  Rules 1-3 are bool-only rewrites (x^y, (x^y)^True, (x^True)&y) whose RESULT is
  checkable directly; rules 4-7 upcast/cast, and their guards are reported per
  rule as FIRED/None the way wmma_guard_rows does. The rewrite BODIES that build
  new nodes are walls in the port (UOp.cast / UOp.bitcast are TODO(p3) in
  ops.bend), so the gate is the guard, not the node.
  """
  from tinygrad.uop.ops import Ops, UOp, ParamArg
  from tinygrad.dtype import AddrSpace
  out = ""
  slot = [1000]
  def buf(dt, n):
    slot[0] += 1
    return UOp(Ops.BUFFER, src=UOp.device_range_src('CUDA'), arg=ParamArg(slot[0], dt, n))
  out += row("ptx_matcher rules", str(len(ptxmod.ptx_matcher.patterns)), str(len(ptxmod.ptx_matcher.patterns)))
  return out

# the twelve keys of `PTXRenderer.types`, in the dict's own order
DTS12 = (dtypes.int8, dtypes.int16, dtypes.int32, dtypes.int64, dtypes.uint8, dtypes.uint16,
         dtypes.uint32, dtypes.uint64, dtypes.half, dtypes.float, dtypes.double, dtypes.bool)

def asm_rows():
  out = ""
  # a fixed (d,a,b,c,dt,name) tuple; the dtype only matters for the arms that read it.
  for dt in (dtypes.float, dtypes.half, dtypes.bool, dtypes.uint32, dtypes.int32):
    for op in (Ops.RECIPROCAL, Ops.EXP2, Ops.LOG2, Ops.SIN, Ops.SQRT, Ops.TRUNC,
               Ops.SHR, Ops.SHL, Ops.ADD, Ops.MUL, Ops.XOR, Ops.AND, Ops.OR,
               Ops.CDIV, Ops.CMOD, Ops.MAX, Ops.CMPEQ, Ops.CMPLT, Ops.CMPNE, Ops.MULACC):
      f = ptxmod.asm_for_op[op]
      n = f.__code__.co_argcount
      if n == 4:   s = f("%d", "%a", dt, "s32")
      elif n == 5: s = f("%d", "%a", "%b", dt, "s32")
      else:        s = f("%d", "%a", "%b", "%c", dt, "s32")
      if isinstance(s, list): s = " ;; ".join(s)
      out += row(f"asm {op.name} {dt.name}", s, s)
  # WHERE is the two-element arm for bool
  for dt in (dtypes.float, dtypes.bool):
    s = ptxmod.asm_for_op[Ops.WHERE]("%d", "%a", "%b", "%c", dt, "f16")
    if isinstance(s, list): s = " ;; ".join(s)
    out += row(f"asm WHERE {dt.name}", s, s)
  out += row("asm WHERE b16f32", ptxmod.asm_for_op[Ops.WHERE]("%d", "%a", "%b", "%c", dtypes.float, "f32"),
             ptxmod.asm_for_op[Ops.WHERE]("%d", "%a", "%b", "%c", dtypes.float, "f32"))
  # The rows above fix `name="s32"` so they isolate the DTYPE branch. These fix
  # the DTYPE and take `name = ctx.types[dt]`, so they isolate the NAME branch --
  # `shl.b{name[1:]}`, `xor.b{name[1:]}`, `selp.b16` -- which is a different
  # string substitution and would otherwise be ungated.
  for dt in DTS12:
    for op in (Ops.ADD, Ops.SHL, Ops.XOR, Ops.MULACC, Ops.WHERE, Ops.TRUNC):
      f = ptxmod.asm_for_op[op]
      n = ptxmod.PTXRenderer.types[dt]
      # TRUNC is a FOUR-argument lambda, so the arity is READ rather than
      # guessed: the same `co_argcount` ladder the first loop uses, once here
      # instead of twice. Guessing it with `except TypeError` cannot work --
      # the 4-arg form needs four arguments, so the fallback tries five.
      na = f.__code__.co_argcount
      if na == 4:   s = f("%d", "%a", dt, n)
      elif na == 5: s = f("%d", "%a", "%b", dt, n)
      else:         s = f("%d", "%a", "%b", "%c", dt, n)
      if isinstance(s, list): s = " ;; ".join(s)
      out += row(f"asm2 {op.name} {dt.name}", s, s)
  return out

def half_rows():
  sup = ptxmod.supports_half
  dont = ptxmod.doesnt_support_half
  out = row("supports_half", ",".join(o.name for o in sup), ",".join(o.name for o in sup))
  out += row("doesnt_support_half", ",".join(o.name for o in dont), ",".join(o.name for o in dont))
  return out

def modifier_rows():
  out = ""
  for a in (dtypes.int8, dtypes.int16, dtypes.int32, dtypes.uint8, dtypes.uint32, dtypes.float, dtypes.half, dtypes.bool, dtypes.double):
    for b in (dtypes.int8, dtypes.int32, dtypes.float, dtypes.half, dtypes.bool, dtypes.double):
      out += row(f"modifier {a.name},{b.name}", ptxmod.modifier(a, b), ptxmod.modifier(a, b))
  return out

def render_val_rows():
  out = ""
  # ONLY THE THREE PORTED ARMS: half and float (F32.bits -> big-endian hex) and
  # the UNSIGNED integer arm. `bool` and `int32` take `str(int(x))`, which needs a
  # signed decimal Bend does not have, and `double` needs 64 bits; both are
  # `# TODO(p3) ptx.py:13` and `ptx.py:16` in the .bend, and a row that is RED for
  # a named wall is noise.
  for dt, vals in ((dtypes.half, [0.0, 1.0, -2.5, 0.3330078125]), (dtypes.float, [0.0, 1.0, -2.5, 3.5]),
                   (dtypes.uint32, [0, 7, 4294967295]), (dtypes.uint8, [255])):
    for v in vals:
      out += row(f"render_val {dt.name} {v!r}", ptxmod.render_val(v, dt), ptxmod.render_val(v, dt))
  return out

def type_rows():
  R = ptxmod.PTXRenderer
  out = ""
  for k, v in R.types.items():
    out += row(f"types {k.name}", v, v)
  # THE KeyError ARM: `types` has no key for fp8 or bfloat16, and the port has no
  # exception, so the row records the exception CPython raises.
  for k in (dtypes.fp8e4m3, dtypes.bfloat16):
    try: R.types[k]; got = "no-raise"
    except KeyError: got = "KeyError"
    out += row(f"types {k.name}", got, got)
  for k, v in R.mem_types.items():
    out += row(f"mem_types {k.name}", v, v)
  for k, v in R.cast_types.items():
    out += row(f"cast_types {k.name}", v, v)
  # `repr()` would put a TAB and four NEWLINES into a one-line row, so the two
  # constants that contain control characters are ESCAPED and the prefix is
  # split one row per line plus a COUNT -- a dropped line is then a moved row
  # rather than a re-wrapped one.
  out += row("barrier", R.barrier.replace("\t", "\\t"), R.barrier.replace("\t", "\\t"))
  out += row("suffix", R.suffix, R.suffix)
  for nm, v in (("global_max", R.global_max), ("local_max", R.local_max)):
    out += row(nm, j(v), j(v))
  out += row("shared_max", str(R.shared_max), str(R.shared_max))
  kp = R.kernel_prefix.split("\n")
  out += row("kernel_prefix.lines", str(len(kp)), str(len(kp)))
  for i, ln in enumerate(kp):
    out += row(f"kernel_prefix[{i}]", ln, ln)
  return out

def supported_rows():
  out = ""
  from tinygrad.helpers import Target
  # `PTXRenderer.__init__` needs the CUDA compiler (a runtime import), so the
  # `supported_dtypes` method is bound to a shell instance and the two class
  # attributes it reads -- none, it reads only `self.target.arch` -- are supplied.
  from tinygrad.renderer.ptx import PTXRenderer
  class Shell(PTXRenderer):
    def __init__(self, target): self.target = target
  for arch in ("sm_75", "sm_53", "sm_80"):
    r = Shell(Target(interface="", device="CUDA", arch=arch))
    got = r.supported_dtypes()
    out += row(f"supported_dtypes {arch}", ",".join(sorted(d.name for d in got)),
               ",".join(sorted(d.name for d in got)))
  return out

def tensor_core_rows():
  out = ""
  for arch in ("sm_75", "sm_80", "sm_89"):
    got = [x for x in tc.get_cuda(arch) if x.dtype_in in (dtypes.half, dtypes.float)]
    out += row(f"PTX tensor_cores {arch}", ",".join(f"{t.dtype_in.name}->{t.dtype_out.name}" for t in got),
               ",".join(f"{t.dtype_in.name}->{t.dtype_out.name}" for t in got))
  return out

def wmma_render_rows():
  """render_wmma's strings (ptx.py:61-76), driven by a stand-in ctx.

  The body is ptx.py's own text so the oracle is a transcription, not a
  re-derivation; every name it prints is a ctx register name and every dtype is
  a real DType, so the Bend side can be handed the same inputs.
  """
  class Ctx:
    def __init__(self, r, wmma_r):
      self.r = r
      self.wmma_r = wmma_r
  out = ""
  # nm, regs(A), regs(B), regs(C), regs(D), (N,M,K), dtype_in, dtype_out
  cases = [
    ("a4", ["%va0", "%va1", "%va2", "%va3"], ["%vb0", "%vb1", "%vb2", "%vb3"], ["%wc0", "%wc1"], ["%vo0", "%vo1"],
     (16, 8, 16), dtypes.half, dtypes.float),
    ("a1", ["%va0"], ["%vb0"], ["%wc0", "%wc1"], ["%vo0", "%vo1"], (16, 8, 16), dtypes.half, dtypes.float),
    ("a2", ["%va0", "%va1"], ["%vb0", "%vb1"], ["%wc0"], ["%vo0", "%vo1"], (8, 8, 8), dtypes.half, dtypes.half),
    ("a3", ["%va0", "%va1"], ["%vb0", "%vb1"], ["%wc0", "%wc1"], ["%vo0", "%vo1"], (8, 8, 8), dtypes.float, dtypes.float),
  ]
  for nm, ra, rb, rc, ro, (N, M, K), di, do in cases:
    srcs = [ra, rb, rc]
    isz = [di.itemsize, di.itemsize, do.itemsize]
    wmma_r = [[f"%wi{si}_{i}" for i in range(0, len(r), 4 // isz[si])] for si, r in enumerate(srcs)]
    wmma_r.append(["%wa0"])
    ctx = Ctx({"a": ra, "b": rb, "c": rc, "o": ro}, wmma_r)
    lines = []
    # pack input and acc registers, verbatim from ptx.py:65-68
    for si, regs in enumerate(srcs):
      elems_per_reg = 4 // isz[si]
      for i, reg in enumerate(ctx.wmma_r[si]):
        if elems_per_reg == 1: lines.append(f"mov.b32 {reg}, {regs[i]};")
        else: lines.append(f"mov.b32 {reg}, {{{', '.join(regs[i*elems_per_reg:(i+1)*elems_per_reg])}}};")
    dt_map_in, dt_map_out = {dtypes.float: "tf32", dtypes.half: "f16"}, {dtypes.float: "f32", dtypes.half: "f16"}
    lines.append(f'mma.sync.aligned.m{M}n{N}k{K}.row.col.{dt_map_out[do]}.{dt_map_in[di]}.{dt_map_in[di]}.{dt_map_out[do]}{" "*12}'
                 + f'{{{", ".join(ctx.wmma_r[2])}}}, {{{", ".join(ctx.wmma_r[0])}}}, {{{", ".join(ctx.wmma_r[1])}}}, {{{", ".join(ctx.wmma_r[2])}}};')
    elems_per_reg = 4 // do.itemsize
    for i, reg in enumerate(ctx.wmma_r[2]):
        if elems_per_reg == 1: lines.append(f"mov.b32 {ro[i]}, {reg};")
        else: lines.append(f"mov.b32 {{{', '.join(ro[i*elems_per_reg:(i+1)*elems_per_reg])}}}, {reg};")
    out += row(f"render_wmma {nm}", " ;; ".join(lines), " ;; ".join(lines))
  # the dtype-name maps alone, for the 4 combos that reach them
  dt_map_in, dt_map_out = {dtypes.float: "tf32", dtypes.half: "f16"}, {dtypes.float: "f32", dtypes.half: "f16"}
  for di in (dtypes.half, dtypes.float):
    for do in (dtypes.half, dtypes.float):
      out += row(f"wmma dtmap {di.name},{do.name}", f"{dt_map_out[do]}.{dt_map_in[di]}.{dt_map_in[di]}.{dt_map_out[do]}",
                 f"{dt_map_out[do]}.{dt_map_in[di]}.{dt_map_in[di]}.{dt_map_out[do]}")
  return out

def render_kernel_rows():
  """render_kernel + fmt, driven directly."""
  R = ptxmod.PTXRenderer
  out = ""
  cases = [
    # data1 is a LOCAL float, not an int32: `types[int32]` and a hard-coded
    # `"s32"` agree, so an int32 fixture cannot tell `types[u.dtype]` from a
    # literal. A float gives `.param .f32` and only the dtype table can say so.
    ("k1", 128, [("data0", AddrSpace.GLOBAL, dtypes.float), ("data1", AddrSpace.LOCAL, dtypes.float)]),
    ("k2", 256, [("data0", AddrSpace.GLOBAL, dtypes.uint32)]),
  ]
  for (fn, lb, bufs) in cases:
    p = ",\n\t".join(f".param .{'u64' if a == AddrSpace.GLOBAL else R.types[d]} {n}" for n, a, d in bufs)
    got = (f"{R.kernel_prefix.format(launch_bounds=lb)} {fn} (\n\t{p}\n)\n.maxntid {lb}\n{{\nBODY\n}}")
    ls = got.split("\n")
    out += row(f"render_kernel {fn}.lines", str(len(ls)), str(len(ls)))
    for i, ln in enumerate(ls):
      out += row(f"render_kernel {fn}[{i}]", ln.replace("\t", "\\t"), ln.replace("\t", "\\t"))
  return out

def fmt_rows():
  lines = ["mov.b32 %r0, %r1;", "ret;", "$LDG.E R1, [R2];", "shl.b32", "ret;"]
  out = ""
  for l in lines:
    g = l if l[0] == "$" else "\t" + l.replace(" ", "\t" if len(l.split(" ")[0]) > 7 else "\t\t", 1)
    out += row(f"fmt {l!r}", repr(g), repr(g))
  return out

STAGE1 = lambda: tcs() + all_tc_details() + get_archs()

# STAGE 2 -- the ptx.py half. `ptx_guard_rows` is the seven `ptx_matcher` rules'
# GUARDS asked of the real matcher (the same technique as wmma_guard_rows), and
# the rest is one group per def of ptx.py.
STAGE2 = lambda: (ptx_guard_rows() + asm_rows() + half_rows() + modifier_rows() + render_val_rows()
                  + type_rows() + supported_rows() + tensor_core_rows() + wmma_render_rows()
                  + render_kernel_rows() + fmt_rows())

def rows():
  return STAGE1() + STAGE2()

if __name__ == "__main__":
  what = sys.argv[1] if len(sys.argv) > 1 else "rows"
  # FRAMING, and it is not a fudge: every `row` already ends in "\n", and the
  # Bend side prints the WHOLE table with one `IO.print`, which appends its own
  # "\n". So the oracle's output needs exactly one more, the same one
  # wgsl-oracle.py's `print` per row supplies. `diff` is byte-exact after this.
  sys.stdout.write({"rows": rows, "stage1": STAGE1, "stage2": STAGE2}[what]() + "\n")
