#!/usr/bin/env python3
"""THE EMIT-SITE INDEX MAP for `runtime/ops_cl.bend`'s vendor table.

WHY THIS EXISTS. `.agents/slop/cl_vendor_scan.py` checks the vendor table as a SET
of symbols against the Python sources, and it PASSED while `cuModuleLoadData`
sat at `OP_BUILD` instead of `OP_PRG_FROM_BIN` -- a mutation I applied by hand to
prove the scan bites, and it did not. A symbol-set scan is blind to an index
transposition by construction: both the right and the wrong table contain exactly
the same 21 CUDA symbols. That check is necessary (it catches a missing or
phantom symbol) and NOT sufficient, and this file is the sufficient half.

THE AUTHORITY HERE IS THE EMIT SITE. Every `def` in the port that calls
`Tr.emit(OP_X(), ...)` carries a comment naming the Python line it ports, and
that line CALLS one symbol. So the triple

    (vendor, python line, OP tag)

is checkable: read the symbol CPython's AST says that line calls, read
`vend.<vendor>[OP tag]`, and they must be equal. A transposed index disagrees,
and it disagrees in the direction that matters -- the trace prints the wrong
symbol for the wrong call site.

THE MAP IS HAND-BUILT, because the port's comments are the record of which line
each emit site ports and an automated extractor would pair the wrong comment
with the wrong def (the comment block above a def is not always about that def's
emit). Each entry is asserted: the named def must exist at the named line, its
body must emit the named op, and the comment above it must name the same Python
line. A map entry that does not survive that assertion is LOUD.

    (vendor, port_def_NAME, op_tag, python_line, what the line calls)

Run: .venv/bin/python .agents/slop/cl_emit_map.py
"""
import ast, importlib.util, re, sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location("cl_vendor_scan", Path(__file__).with_name("cl_vendor_scan.py"))
_vs = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_vs)
NOT_A_CALL = {v: {k for k, r in d.items() if r} for v, d in _vs.NOT_A_CALL.items()}

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "tinybendygrad/runtime/ops_cl.bend"
SRC = {v: ROOT / f"tinygrad/runtime/ops_{n}.py" for v, n in (("cl", "cl"), ("cu", "cuda"), ("hp", "hip"))}
AUTOGEN = {"cl": "opencl", "cu": "cuda", "hp": "hip"}
MODULE = {"cl": "cl", "cu": "cuda", "hp": "hip"}
BLINES = BENCH.read_text().splitlines()
BSRC = BENCH.read_text()
SRC_LINES = {v: SRC[v].read_text().splitlines() for v in SRC}

CONST = re.compile(r"^def [A-Za-z_][A-Za-z_0-9]*\(\) -> \w+: -?\d+\s*$")
BEND_CONST = re.compile(r"^def\s+([A-Za-z_][A-Za-z_0-9]*)\(\)\s*->\s*\w+:\s*(-?\d+)\s*$")


def bend_list(fn):
  m = re.search(rf"^def {fn}\(\) -> List<&2, String>:\n((?:  .*\n)+)", BSRC, re.M)
  assert m, f"no `def {fn}()` block"
  return re.findall(r'"([^"]*)"', re.sub(r"^\s*#.*$", "", m.group(1), flags=re.M))


_CALLS = {}


def _calls_by_line(vendor):
  """every `MODULE.X` REFERENCE in `vendor`'s source -- a call OR a bare name --
  indexed by EVERY line it spans, in SOURCE ORDER (`lineno`, `col_offset`).
  Parsing one LINE with `ast.parse` cannot work: cl:102 is the tail of a call
  that opens on :101, and `ast.parse` of a fragment is a SyntaxError, which is
  how a scan invents a bug. Bare references matter because CUDA's calls go
  through `ccall(cuda.cuLaunchKernel, ...)`, so the symbol on cu:47 is an
  ARGUMENT and not a `Call` node at all."""
  if vendor in _CALLS: return _CALLS[vendor]
  mod, out = MODULE[vendor], {}
  for n in ast.walk(ast.parse(SRC[vendor].read_text())):
    if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id == mod:
      for ln in range(n.lineno, (n.end_lineno or n.lineno) + 1):
        out.setdefault(ln, []).append((n.lineno, n.col_offset, n.attr))
  _CALLS[vendor] = {ln: [a for _, _, a in sorted(v)] for ln, v in out.items()}
  return _CALLS[vendor]


def symbol_at(vendor, line, pick=None):
  """the CALLABLE `MODULE.X` reference spanning `vendor`'s python line `line`.
  The NOT_A_CALL allowlist (imported from the symbol scan, so there is ONE list
  of non-callables and not two) is subtracted first: cl:105 carries
  `cl.clGetDeviceInfo(..., cl.CL_DEVICE_NAME, ...)` and the enum is not a call,
  so counting it would make every real line ambiguous.
  `pick` selects the `pick`-th remaining name in SOURCE order, which is what a
  line carrying two calls needs -- cu:82 is
  `(cuda.cuMemFreeHost if ... else cuda.cuMemFree_v2)(storage.buf)`.
  Zero names, or several with no `pick`, answers None: never a guess."""
  names = [n for n in _calls_by_line(vendor).get(line, []) if n not in NOT_A_CALL[vendor]]
  if pick is not None:
    return (names[pick], names) if pick < len(names) else (None, names)
  return (names[0], names) if len(names) == 1 else (None, names)


# --------------------------------------------------------------------------- map
# (vendor, port_def_NAME, op_tag, python_line[, pick][, via])
#
# THE ANCHOR IS THE DEF NAME AND NOT A LINE NUMBER. A line anchor is correct only
# until the file grows by one comment line, and correcting WALL 7 grew it by 9 --
# after which this map reported 71 MAP ERRORs and compared ONE entry. The
# self-assertion caught that (it is why the map asserts its own entries at all),
# but a hand map that must be re-anchored after every comment edit is a bad map.
# The python line stays a line number because IT is the authority and it lives in
# a file that does not change.
#
# A LINE ANCHOR ALSO HIDES A WRONG EMITTER, WHICH A NAME ANCHOR MAKES IMPOSSIBLE.
# The old map resolved an emit site by walking UP to the nearest `def`, so
# ("cu", 2073, "OP_SIGNAL", 66) resolved to `cu.signal` -- and `cu.signal` really
# does emit OP_SIGNAL, so the assertion passed while the entry was really about
# `cu.submit` at :2081. One name per emitter removes the ambiguity.
#
# A CONSTANT IS NEVER AN EMITTER: `def OP_HOST_FUNC() -> U32: 36` "contains"
# OP_HOST_FUNC() because the block IS `() -> U32: 36`. Excluded below and again in
# the assertion.
MAP = [
  # ---- CL, ops_cl.py ------------------------------------------------------
  ("cl", "cl.probe.at", "OP_GET_DEVICES", 98),      # the UNCHECKED probe, err = ...
  ("cl", "cl.platforms", "OP_PLATFORMS", 95),        # clGetPlatformIDs(0, None, n)
  ("cl", "cl.platform_ids", "OP_PLATFORMS", 96),     # clGetPlatformIDs(n, ids, None)
  ("cl", "cl.device_ids", "OP_GET_DEVICES", 102),     # the real, CHECKED query
  ("cl", "cl.info_name", "OP_GET_DEVICE_INFO", 105),  # CL_DEVICE_NAME
  ("cl", "cl.info_drv", "OP_GET_DEVICE_INFO", 107),   # CL_DRIVER_VERSION
  ("cl", "cl.context", "OP_CTX_CREATE", 110),         # clCreateContext
  ("cl", "cl.queue", "OP_QUEUE_CREATE", 111),         # clCreateCommandQueue
  ("cl", "cl.exts_len", "OP_GET_DEVICE_INFO", 113),   # CL_DEVICE_EXTENSIONS, len probe
  ("cl", "cl.exts_get", "OP_GET_DEVICE_INFO", 114),   # CL_DEVICE_EXTENSIONS, read
  ("cl", "cl.ipa_get", "OP_GET_DEVICE_INFO", 122),    # CL_DEVICE_IMAGE_PITCH_ALIGNMENT
  ("cl", "comp.from_src", "OP_PRG_FROM_SRC", 26),     # clCreateProgramWithSource
  ("cl", "comp.build", "OP_BUILD", 27),               # clBuildProgram, the compiler's
  ("cl", "comp.build_log", "OP_BUILD_LOG", 29),       # clGetProgramBuildInfo, size probe
  ("cl", "comp.prg_info", "OP_PRG_INFO", 33),         # clGetProgramInfo BINARY_SIZES
  ("cl", "comp.release", "OP_RELEASE_PRG", 36),       # clReleaseProgram, the compiler's
  ("cl", "prog.from_bin", "OP_PRG_FROM_BIN", 42),     # clCreateProgramWithBinary
  ("cl", "prog.build", "OP_BUILD", 46),               # clBuildProgram, the program's
  ("cl", "prog.kernel", "OP_KERNEL", 47),             # clCreateKernel
  ("cl", "prog.del.go", "OP_RELEASE_KERNEL", 50),     # clReleaseKernel
  ("cl", "prog.del.prg", "OP_RELEASE_PRG", 52),       # clReleaseProgram, __del__
  ("cl", "img.create", "OP_IMAGE", 63),               # clCreateImage
  ("cl", "prog.arg_at", "OP_SET_ARG", 64),            # clSetKernelArg, the IMAGE arm
  ("cl", "prog.arg_at", "OP_SET_ARG", 65),            # clSetKernelArg, the else arm
  ("cl", "cl.launch", "OP_LAUNCH", 68),               # clEnqueueNDRangeKernel
  ("cl", "cl.wait_events", "OP_WAIT_EVENT", 72),      # clWaitForEvents
  ("cl", "cl.profiling", "OP_TIME_END", 73),          # clGetEventProfilingInfo, START
  ("cl", "alloc.of", "OP_ALLOC", 80),                 # clCreateBuffer
  ("cl", "alloc.free", "OP_FREE", 83),                # clReleaseMemObject
  ("cl", "copy.copyin", "OP_COPY_IN", 86),            # clEnqueueWriteBuffer
  ("cl", "copy.copyout", "OP_COPY_OUT", 88),          # clEnqueueReadBuffer
  ("cl", "cl.sync", "OP_FINISH", 129),                # clFinish
  # ---- CUDA, ops_cuda.py --------------------------------------------------
  ("cu", "cu.init.dev", "OP_GET_DEVICES", 106),       # cuDeviceGet
  ("cu", "cu.init.ctx", "OP_CTX_CREATE", 107),        # cuCtxCreate_v2
  ("cu", "cu.init.drv", "OP_INIT", 105),              # cuInit(0)
  ("cu", "cu.compute_cap", "OP_COMPUTE_CAP", 108),    # cuDeviceComputeCapability
  ("cu", "cu.stream_create", "OP_QUEUE_CREATE", 109),  # cuStreamCreate
  ("cu", "cu.extern", "OP_HOST_FUNC", 38),            # `extern`, which calls no cuda symbol
  ("cu", "cu.q_init", "OP_CTX_SET", 34),              # ccall(cuCtxSetCurrent, ...)
  ("cu", "cu.launch", "OP_LAUNCH", 47),               # ccall(cuLaunchKernel, ...)
  ("cu", "cu.copy", "OP_COPY_IN", 55),                # ccall(cuMemcpyAsync, ...)
  ("cu", "cu.wait", "OP_WAIT_VALUE", 58),             # ccall(cuStreamWaitValue64_v2, ...)
  ("cu", "cu.signal", "OP_SIGNAL", 61),               # ccall(cuStreamWriteValue64_v2, ...)
  ("cu", "cu.timestamp", "OP_HOST_FUNC", 64),         # ccall(cuLaunchHostFunc, ...)
  ("cu", "cu.submit", "OP_SIGNAL", 66),               # rt_vars.index(3).store, no cuda call
  ("cu", "cu.alloc.host", "OP_ALLOC_HOST", 76),       # cuMemHostAlloc
  ("cu", "cu.alloc.dev", "OP_ALLOC", 78),             # cuMemAlloc_v2
  ("cu", "cu.free.at", "OP_FREE_HOST", 82, 0),        # cu:82 `(cuMemFreeHost if ... else
  ("cu", "cu.free.at", "OP_FREE", 82, 1),             #   cuMemFree_v2)(storage.buf)`, 2nd name
  ("cu", "cu.map.at", "OP_HOST_REGISTER", 90),        # cuMemHostRegister_v2
  ("cu", "cu.unmap.at", "OP_HOST_UNREGISTER", 94),    # cuMemHostUnregister
  ("cu", "cu.function", "OP_PRG_FROM_BIN", 128),      # cuModuleLoadData   <-- THE ONE
  ("cu", "cu.build.after", "OP_KERNEL", 129),         # cuModuleGetFunction
  ("cu", "cu.function.ctx", "OP_CTX_SET", 127),       # check(cuCtxSetCurrent(self.context))
  ("cu", "cu.count", "OP_GET_DEVICE_COUNT", 132),     # cuDeviceGetCount
  ("cu", "cu.wait_signal", "OP_CTX_SET", 135),        # check(cuCtxSetCurrent)
  # cu.wait_signal emits OP_FINISH only INDIRECTLY, through CL's `cl.sync`, so this
  # entry names the HELPER. cu:136 is cuCtxSynchronize.
  ("cu", "cu.wait_signal", "OP_FINISH", 136, None, "cl.sync"),
  # ---- HIP, ops_hip.py ----------------------------------------------------
  ("hp", "hp.props", "OP_GET_DEVICE_PROPS", 15),      # hipGetDeviceProperties
  ("hp", "hp.event_create", "OP_QUEUE_CREATE", 16),   # hipEventCreate
  ("hp", "hp.set_device", "OP_SET_DEVICE", 23),       # hipSetDevice, synchronize
  ("hp", "hp.sync", "OP_FINISH", 24),                 # hipDeviceSynchronize
  ("hp", "hp.count", "OP_GET_DEVICE_COUNT", 20),      # hipGetDeviceCount
  ("hp", "hp.prog_init.dev", "OP_SET_DEVICE", 29),    # hipSetDevice, HIPProgram.__init__
  ("hp", "hp.prog_init.prg", "OP_PRG_FROM_BIN", 30),  # hipModuleLoadData  <-- THE ONE
  ("hp", "hp.prog_init.fn", "OP_KERNEL", 31),         # hipModuleGetFunction
  ("hp", "hp.prog_del", "OP_RELEASE_PRG", 35),        # hipModuleUnload
  ("hp", "hp.call_set_device", "OP_SET_DEVICE", 38),  # hipSetDevice, __call__
  ("hp", "hp.event_record", "OP_TIME_START", 49),     # hipEventRecord, start
  ("hp", "hp.launch", "OP_LAUNCH", 51),               # hipModuleLaunchKernel
  ("hp", "hp.event_sync", "OP_WAIT_EVENT", 55),       # hipEventSynchronize
  ("hp", "hp.event_elapsed", "OP_TIME_END", 56),      # hipEventElapsedTime
  ("hp", "hp.alloc", "OP_ALLOC", 62),                 # hipMalloc
  ("hp", "hp.free", "OP_FREE", 64),                   # hipFree
  ("hp", "hp.copyin.at", "OP_COPY_IN", 67),           # hipMemcpy, HostToDevice
  ("hp", "hp.copyout.at", "OP_COPY_OUT", 70),         # hipMemcpy, DeviceToHost
]

# THREE (vendor, op) pairs the map cannot resolve to a Python call, each with the
# reason recorded rather than papered over. All three are in the table and none is
# a wrong index.
NO_CALL = {
  ("cu", "OP_HOST_FUNC"): "cu:38 `def extern(self, tag)` builds a UOp.placeholder and calls no cuda symbol; the cuda symbol that really runs for this op is cuLaunchHostFunc, and the map DOES resolve it at cu:64",
  ("cu", "OP_SIGNAL"): "cu:66 `submit` is `rt_vars.index(3).store(...)`, a UOp store and no call. OP_SIGNAL is the slot the trace reuses for the queue status write; cuStreamWriteValue64_v2 is resolved at cu:61, which is the real signal",
}
# a table cell no emit site reaches, which is NOT a wrong index either
UNREACHED = {
  ("cu", "OP_COPY_OUT"): "ops_cuda.py has ONE `CUDAQueue.copy` (cu:54-55) for BOTH directions, so the port emits OP_COPY_IN and OP_COPY_OUT holds the same symbol by design",
  ("hp", "OP_ERRSTR"): "WALL 7, and it is the ONLY reason there is no emit site: hipGetErrorString is never CALLED by ops_hip.py, it is REFERENCED at hp:10 to build the error string, and that string is the seam's. The SYMBOL is right -- it is what `vend_errstr_hp` reads back and `hip.hipGetErrorString` exists",
}

# sites where ONE python line emits ONE op but the symbol is not on that line:
# `def` lines whose op is a second call the comment names by its own line.
# hp:16 creates TWO events on one line, so OP_QUEUE_CREATE is hpEventCreate and
# OP_TIME_START/TIME_END are the record/elapsed pair; those are separate lines.


def bend_consts():
  out = {}
  for i, line in enumerate(BLINES, 1):
    m = BEND_CONST.match(line)
    if m: out[m.group(1)] = (i, int(m.group(2)))
  return out


def main():
  tables = {v: bend_list(f"vend.{v}") for v in ("cl", "cu", "hp")}
  consts = bend_consts()
  wrong, skipped, badmap = [], [], []
  seen_ops = {}
  for entry in MAP:
    vendor, port_def, op, pyline = entry[:4]
    pick = entry[4] if len(entry) > 4 else None
    via = entry[5] if len(entry) > 5 else None
    # --- assert the map entry itself, so a moved line is LOUD not silent
    if op not in consts:
      badmap.append(f"{op} is not a constant in ops_cl.bend"); continue
    # the def whose OWN block carries the emit, found BY NAME -- exactly one, or
    # the map is ambiguous. `via` names a helper this def calls instead.
    name = via or port_def
    hit = [i for i, l in enumerate(BLINES) if l.startswith(f"def {name}(")]
    if len(hit) != 1:
      badmap.append(f"def {name!r}: {len(hit)} definitions in ops_cl.bend"); continue
    k = hit[0]
    if CONST.match(BLINES[k]):
      badmap.append(f"`def {name}` is a CONSTANT, not an emitter"); continue
    j = k
    while j + 1 < len(BLINES) and BLINES[j + 1].strip(): j += 1
    block = "\n".join(BLINES[k:j + 1])
    if f"{op}()" not in block:
      badmap.append(f"ops_cl.bend:{k + 1} `def {name}` does not emit {op}")
    # --- the authority: what CPython says that line calls
    got, allc = symbol_at(vendor, pyline, pick)
    if got is None:
      reason = NO_CALL.get((vendor, op))
      skipped.append((vendor, port_def, op, pyline, allc, reason)); continue
    want = tables[vendor][consts[op][1]]
    if got != want:
      wrong.append((vendor, port_def, op, consts[op][1], got, want, pyline))
    seen_ops.setdefault((vendor, op), []).append(pyline)
  print(f"emit-site map: {len(MAP)} entries over "
        f"{len(set((e[0], e[2]) for e in MAP))} (vendor, op) pairs")
  for b in badmap: print(f"  !! MAP ERROR {b}")
  print(f"  compared against CPython's AST : {len(MAP) - len(skipped) - len(badmap)}")
  print(f"  NO PYTHON CALL on the named line: {len(skipped)}")
  for v, pl, op, py, allc, reason in skipped:
    tag = "OK " if reason else "!! "
    print(f"    {tag}SKIP {v} `def {pl}` {op} py:{py} -- symbols on that line: {allc}")
    if reason: print(f"         reason: {reason}")
    else:
      print("         !! NO REASON RECORDED in NO_CALL -- an unexplained skip"); badmap.append("unexplained skip")
  print(f"  WRONG                        : {len(wrong)}")
  for v, pl, op, oi, got, want, py in wrong:
    print(f"    WRONG {v} ops_{v}.py:{py} calls {got}, but {op}={oi} "
          f"(ops_cl.bend `def {pl}`) holds {want!r} -- should be {got!r}")
  # --- the ops NO emit site covers. A cell nothing emits is either a dead op or
  # a site the map missed, and either way it is not the port's own claim.
  emitted = set((e[0], e[2]) for e in MAP)
  for v, tab in tables.items():
    for i, s in enumerate(tab):
      if not s: continue
      names = [k for k, vv in consts.items() if vv[1] == i and k.startswith("OP_")]
      if names and (v, names[0]) not in emitted:
        why = UNREACHED.get((v, names[0]))
        print(f"    {'OK ' if why else '!! '}NO-EMIT-SITE {v} op {i} ({names[0]}) = {s}"
              + (f"\n         reason: {why}" if why else " -- UNEXPLAINED"))
        if not why: badmap.append(f"unexplained no-emit-site {v} {names[0]}")
  return 1 if (wrong or badmap) else 0


if __name__ == "__main__":
  sys.exit(main())
