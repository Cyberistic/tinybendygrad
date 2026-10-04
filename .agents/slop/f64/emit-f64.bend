# .agents/slop/f64/emit-f64.bend -- ASK THE PORT FOR A **DOUBLE** KERNEL.
#
#   ./bin/bend .agents/slop/f64/emit-f64.bend > mm-rows.txt
#
# This is the f64 TWIN of `.agents/slop/portexec/emit-mm.bend`, and it is the SAME
# HARNESS in every respect except one: the four `BArg`s carry `S.double()` instead
# of `S.single()`.  Nothing here is new machinery.  `portexec/run-kernel.sh mm`
# reads the C text between the two markers below, PARSES the signature out of it
# (`exec_harness.signature`), builds the shim and the Bend driver from that parse
# (`gen_ffi.py`), `cc`s the kernel, links it against Bend's own `bend -o` output,
# and Bend allocates three buffers, fills them, LAUNCHES THE KERNEL BY POINTER and
# reads the words back.
#
# WHY THIS IS NOT A NEW CLAIM BUT A WIDER ONE.  `render_dtype` has NO `f64` GATE
# ROW: `cstyle.bend:2984-3015` calls `rd_row` for exactly SEVEN dtypes -- f32, f16,
# bf16, bool, u8, fp8e4m3, i32 -- across six devices, and f64 is not among them, so
# all 227 rows are silent about `double`.  `tmap CLANG` does carry `double`
# (`cstyle-live/port.txt:2`), but a NAME in a type map is not a `double*` in a
# signature.  So the first thing this file does that no gate row does is make the
# port EMIT an `f64` parameter list, and the harness then hands that text to a C
# compiler and a machine.  `PORT PROTOTYPE` in the lane log is the evidence.
#
# WHAT IS THE PORT'S AND WHAT IS THE FIXTURE, verbatim from `emit-mm.bend:10-24`
# because it is the same boundary one level down:
#   PORT      the signature `void mm(double* restrict data0_4, ... )`, the typedef,
#             the `restrict` suffix, the buffer TYPES, the `void` return, the
#             braces and the framing -- all read out of `render_kernel`'s tables.
#   FIXTURE   the loop nest and the eight-tap expression, which are LITERALS here in
#             exactly the way `g_kernel()` at `cstyle.bend:1879` is a literal.  There
#             is no `_render`: nothing in the port turns a UOp list into lines.
#
# THE BODY.  `(A @ B) @ D` with a LOCAL `double tmp[16]`, so a kernel that re-uploaded
# `tmp` instead of carrying it would answer differently, plus ONE `double` constant
# on the way out.  Shapes, chosen so that all three of `run-kernel.sh`'s mm-mode
# plants apply VERBATIM to the emitted C -- which is why the `k < 8` tap count in
# the first dot is 8 and the second dot's is 4:
#     A = data1_4  4x8 = 32 doubles = 64 u32 words   (this sets `nwords` = 64)
#     B = data2_4  8x4 = 32 doubles = 64 u32 words
#     D = data3_4  4x8 = 32 doubles = 64 u32 words
#     out = data0_4  4x8 = 32 doubles = 64 u32 words  -> `NW`=64 WORD lines, as in
#                                                          the f32 lane, so the two
#                                                          lanes are comparable.
# `oracle_f64.py` CHOOSES A and B so that `A @ B` is exactly the 4x4 IDENTITY and
# `D[0] = 1.0`, which makes `out[0] = 1.0 + DELTA` -- the one value in this lane
# that f32 cannot represent.  The arithmetic here is mine; the numbers are not.
#
# DELTA IS A C LITERAL, AND THE LITERAL IS CHECKED, NOT TRUSTED.  `9.094947017729282e-13`
# is `repr(2.0**-40)` -- CPython's shortest round-tripping decimal -- and
# `oracle_f64.py` re-derives it and REFUSES TO RUN if this file's text disagrees.
# The port itself emits no float literal at all (there is no `_render`), so this is
# a fixture literal exactly as the matmul body is, and the proof that it survived is
# not the literal: it is the OUTPUT WORD, `0x3FF0000000001000`.  A dropped or
# truncated constant gives `0x3FF0000000000000` and the lane goes red.
import ../../../tinybendygrad/renderer/cstyle.bend as C
import ../../../tinybendygrad/LAWS/spec.bend as S

def NN() -> U32: 8

# `S.double()` IS `Dt{15, 64, CFloat{}, "f64"}` (spec.bend:742) -- the ONLY change
# from emit-mm.bend:33-37, and the whole of what makes this lane an f64 lane.
def bs() -> List<&2, C.BArg>:
  [C.BArg{"data0_4", S.double(), S.AGlobal{}, True{}, False{}, False{}},
   C.BArg{"data1_4", S.double(), S.AGlobal{}, True{}, False{}, False{}},
   C.BArg{"data2_4", S.double(), S.AGlobal{}, True{}, False{}, False{}},
   C.BArg{"data3_4", S.double(), S.AGlobal{}, True{}, False{}, False{}}]

def body() -> List<&2, String>:
  ["  double tmp[16];",
   "  for (int i = 0; i < 4; i++) {",
   "    for (int j = 0; j < 4; j++) {",
   "      double s = 0.0;",
   "      for (int k = 0; k < 8; k++) { s += data1_4[i*8+k] * data2_4[k*4+j]; }",
   "      tmp[i*4+j] = s;",
   "    }",
   "  }",
   "  for (int i = 0; i < 4; i++) {",
   "    for (int j = 0; j < 8; j++) {",
   "      double s = 0.0;",
   "      for (int k = 0; k < 4; k++) { s += tmp[i*4+k] * data3_4[k*8+j]; }",
   "      data0_4[i*8+j] = s + 9.094947017729282e-13;",
   "    }",
   "  }"]

def main() -> IO(Unit):
  do IO<Unit>:
  IO.print("KERNEL_BEGIN")
  IO.print(C.render_kernel(C.dev_clang(), "mm", NN(), bs(), body(), C.emit_min(), False{}))
  IO.print("KERNEL_END")