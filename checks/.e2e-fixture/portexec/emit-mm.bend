# checks/.e2e-fixture/portexec/emit-mm.bend -- ASK THE PORT FOR A 4-BUFFER MATMUL KERNEL.
#
#   ./bin/bend checks/.e2e-fixture/portexec/emit-mm.bend > mm-rows.txt
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
import ../../../tinybendygrad/uop/ops.bend as O
import ../../../tinybendygrad/helpers.bend as H

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

# THE `kus` LIST, AND IT IS NOT EMPTY BECAUSE OF THE ARITHMETIC -- IT IS THERE
# SO THE PORT EMITS THE `float4` TYPEDEF.
#
# **⇒ AND `render_kernel`'s SIGNATURE CHANGED**, and the fixture was not moved
# with it. It used to be
# `render_kernel(dev, fn, lb, bufs, body, emit, cpu)` and it is NOW
# `render_kernel(dev, cpu, fn, kernel, bufs, kus, lb)` -- upstream's own
# `ClangRenderer.render_kernel(self, function_name, kernel, bufs, uops,
# prefix=None)` (`tinygrad/renderer/cstyle.py:312-314`), which takes the UOP
# LIST because the CLANG OVERRIDE's VECTOR TYPEDEFS COME FROM IT.
#
# **⇒ AND THE `kus` ARE WHAT `uops_to_dtypes` READS** (`cstyle.bend:2242`), and
# a `KU` with `numel = 4` and an ALU ADDRESS IS WHAT MAKES
# `render_vector_prefix` EMIT `typedef float float4 ...`. **⇒ AND THE BODY USES
# `float4`?** NO -- this body's own arithmetic is scalar `float`. **⇒ BUT THE
# HARNESS'S `vec4_typedef` PREAMBLE AND THE PORT's OWN `float4` TYPEDEF MUST
# AGREE**, or the kernel does not compile -- and the mm kernel's INPUTS are
# `float*`, so the typedef is not needed by the body at all.
#
# **⇒ AND THEREFORE THE `kus` ARE THE PORT's OWN REAL KERNERS' `kus`**, taken
# from the fixture the cpuseam lane already generated
# (`.agents/slop/cpuseam/gen/r_10_98_4.bend`), so the typedef the port emits is
# THE PORT's OWN and not a hand-written guess.
def kus() -> List<&2, C.KU>:
  [C.KU{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, Nil{}, C.KAConst{O.CInt{H.i64_of_i32(10)}}, Nil{}},
   C.KU{O.OpsPARAM{}, S.single(), S.AGlobal{}, 10, [10], C.KAParam{0, None{}, False{}, 40}, [0]},
   C.KU{O.OpsPARAM{}, S.single(), S.AGlobal{}, 392, [392], C.KAParam{1, None{}, False{}, 1568}, [2]},
   C.KU{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, Nil{}, C.KAConst{O.CInt{H.i64_of_i32(392)}}, Nil{}},
   C.KU{O.OpsPARAM{}, S.single(), S.AGlobal{}, 3920, [3920], C.KAParam{2, None{}, False{}, 15680}, [4]},
   C.KU{O.OpsPARAM{}, S.single(), S.AGlobal{}, 10, [10], C.KAParam{3, None{}, False{}, 40}, [0]}]

def main() -> IO(Unit):
  do IO<Unit>:
  IO.print("KERNEL_BEGIN")
  IO.print(C.render_kernel(C.dev_clang(), True{}, "mm", body(), bs(), kus(), NN()))
  IO.print("KERNEL_END")
