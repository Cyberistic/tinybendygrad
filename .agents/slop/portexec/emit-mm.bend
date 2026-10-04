# .agents/slop/portexec/emit-mm.bend -- ASK THE PORT FOR A 4-BUFFER MATMUL KERNEL.
#
#   ./bin/bend .agents/slop/portexec/emit-mm.bend > mm-rows.txt
#
# THIS FILE DECLARES NO FOREIGN EFFECT AND NO `law`. It calls
# `tinybendygrad/renderer/cstyle.bend:1643`'s `render_kernel` -- the SAME def the
# 222-row gate calls -- with FOUR buffer arguments instead of two, and prints the
# C text it returns between two markers.
#
# WHAT IS THE PORT'S HERE, PRECISELY, because it is much less than it looks:
#   PORT      the signature `void mm(float* restrict data0_4, float* restrict
#             data1_4, float* restrict data2_4, float* restrict data3_4)` -- the
#             kernel typedef, the `restrict` suffix, the buffer types, the `void`
#             return, the braces and the framing. Every one of those is read out
#             of `render_kernel`'s tables by the port.
#   FIXTURE   the loop nest and the eight-tap expression, which are LITERALS here
#             in exactly the way `g_kernel()` at `cstyle.bend:1879` is a literal.
#             `cstyle.bend` has no `_render`: nothing in the port turns a UOp list
#             into lines, and `fold.bend`'s deferred SHRINK is the wall
#             `cstyle.bend:49` names.
#
# SO THE CLAIM IS EXACTLY: the port's four-buffer KERNEL INTERFACE is semantically
# live C that a compiler accepts and a machine executes, and the arithmetic in
# this file is mine. It is NOT a claim that the port scheduled a matmul.
import ../../../tinybendygrad/renderer/cstyle.bend as C
import ../../../tinybendygrad/LAWS/spec.bend as S

def NN() -> U32: 8

# THE FOUR `BArg`s. THE SAME SHAPE `cstyle.bend:1864` `g_bs` builds, with a third
# and fourth GLOBAL buffer: `data0_4` is the OUTPUT (the body stores into it) and
# `data1_4`, `data2_4`, `data3_4` are the three 8x8 inputs.
def bs() -> List<&2, C.BArg>:
  [C.BArg{"data0_4", S.single(), S.AGlobal{}, True{}, False{}, False{}},
   C.BArg{"data1_4", S.single(), S.AGlobal{}, True{}, False{}, False{}},
   C.BArg{"data2_4", S.single(), S.AGlobal{}, True{}, False{}, False{}},
   C.BArg{"data3_4", S.single(), S.AGlobal{}, True{}, False{}, False{}}]

# `(A @ B) @ C`, TWO CHAINED 8-TAP DOTS INTO A LOCAL `tmp[64]`. The second dot's
# input is the first dot's output, so a kernel that re-uploaded `tmp` instead of
# carrying it would answer differently -- which is the reason the E2E is two
# matmuls and not one.
def body() -> List<&2, String>:
  ["  float tmp[64];",
   "  for (int i = 0; i < 8; i++) {",
   "    for (int j = 0; j < 8; j++) {",
   "      float s = 0.0f;",
   "      for (int k = 0; k < 8; k++) { s += data1_4[i*8+k] * data2_4[k*8+j]; }",
   "      tmp[i*8+j] = s;",
   "    }",
   "  }",
   "  for (int i = 0; i < 8; i++) {",
   "    for (int j = 0; j < 8; j++) {",
   "      float s = 0.0f;",
   "      for (int k = 0; k < 8; k++) { s += tmp[i*8+k] * data3_4[k*8+j]; }",
   "      data0_4[i*8+j] = s;",
   "    }",
   "  }"]

def main() -> IO(Unit):
  do IO<Unit>:
  IO.print("KERNEL_BEGIN")
  IO.print(C.render_kernel(C.dev_clang(), "mm", NN(), bs(), body(), C.emit_min(), False{}))
  IO.print("KERNEL_END")
