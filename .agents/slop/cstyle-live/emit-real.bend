import Base
import ./cstyle.bend as C
import ./../LAWS/spec.bend as S

# COPIED INTO THE $TMPDIR SNAPSHOT TREE by `.agents/slop/cstyle-live/run-all.sh`; it is not a
# repo source file and it never runs against the live tree. It exists to answer one question
# the 227-row gate cannot: does the C text `cstyle.bend` emits COMPILE, and does it compute the
# right numbers?
#
# THE FIXTURES ARE CPYTHON'S OWN OUTPUT, NOT GUESSES. `.agents/slop/cstyle-live/cstyle-oracle.py`
# captures what tinygrad's real CPU backend hands clang for `(a + 1.0)` over four contiguous f32
# (captured live with CCACHE=0, so `compile` really was called):
#
#   typedef float float4 __attribute__((aligned(16),ext_vector_type(4)));
#   void E_4(float* restrict data0_4, float* restrict data1_4) {
#     float4 val0 = (*((float4*)((data1_4+0))));
#     *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f),(val0[1]+1.0f),(val0[2]+1.0f),(val0[3]+1.0f)};
#   }
#
# so `g_clang_vecs` is that typedef line VERBATIM and `g_real_kernel` is that body VERBATIM.
# Both are FIXTURES because `render_kernel`'s `kernel` argument is a `List<&2, String>` of
# ALREADY-RENDERED lines and `Emit_.vecs` is the already-rendered `_render_defines` list --
# the port has no fold to walk them, which is wall (a) at cstyle.bend:1640.
def g_clang_vecs() -> List<&2, String>:
  ["typedef float float4 __attribute__((aligned(16),ext_vector_type(4)));"]

def g_real_kernel() -> List<&2, String>:
  ["  float4 val0 = (*((float4*)((data1_4+0))));",
   "  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f),(val0[1]+1.0f),(val0[2]+1.0f),(val0[3]+1.0f)};"]

def g_real_bs() -> List<&2, C.BArg>:
  [C.BArg{"data0_4", S.single(), S.AGlobal{}, True{}, False{}, False{}},
   C.BArg{"data1_4", S.single(), S.AGlobal{}, True{}, False{}, False{}}]

def g_real_emit() -> C.Emit_: C.emit_of(C.uses_off(), g_clang_vecs(), Nil{}, Nil{}, Nil{}, False{})

# `IO.print` STOPS AT A NEWLINE (measured; ffi-experiment/EXPECTED.md), so a multi-line value
# printed raw prints only its FIRST LINE and every comparison over it is a prefix comparison
# -- a row that cannot fail. `C.esc_row` is the port's own escaper, used for that reason.
def row(nm: String, s: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", C.esc_row(s), "]"]))

# ONE `def` PER ROW, and that is not style. MEASURED on bend 2.0.35, twice, and the two halves
# are separate rules (constraints C-1 and C-2 at the end of notes/bend2-constraints.md):
#   * inside `do IO<Unit>:`, `x : T <- expr` accepts only an `IO` EXPRESSION, so the pure
#     `render_kernel` result has to be a nested call inside an `IO` expression;
#   * a `do` block must not END with a `<-` bind, and must hold exactly ONE block's worth of
#     statements -- which is why `main` below calls bare `def`s and ends with `IO.print("")`.
# `renderer/cstyle.bend:2373` ends its own 227-row `main` with `IO.print("")` for the second
# reason and its comment does not say so.
def row_full_clang() -> IO(Unit):
  row("live CLANG full", C.render_kernel(C.dev_clang(), "E_4", 1, g_real_bs(), g_real_kernel(), g_real_emit(), False{}))

# The port's OWN `kern2 CLANG` gate fixture, called LIVE, so the recorded row can be diffed
# against a live call of the same def. This is the one that does NOT compile: `emit_min()`
# carries no `vecs`, and `float4` is undefined without one.
def row_fixture_clang() -> IO(Unit):
  row("live CLANG fixture", C.render_kernel(C.dev_clang(), "E_4", 1, C.g_bs(S.single()), C.g_kernel(), C.emit_min(), False{}))

# The SAME full kernel on the BASE device -- clang's `restrict` dropped, clang's wrapper
# framing gone -- so a difference between this and `row_full_clang` names clang's own
# contribution instead of blaming the shared body. It also does not compile, and that is
# upstream's shape too: only `ClangRenderer` overrides `render_kernel` (cstyle.py:313), so the
# base never emits `_render_defines` and cannot make `float4` real.
def row_full_base() -> IO(Unit):
  row("live BASE full", C.render_kernel(C.dev_base(), "E_4", 1, g_real_bs(), g_real_kernel(), g_real_emit(), False{}))

def main() -> IO(Unit):
  do IO<Unit>:
    row_full_clang()
    row_fixture_clang()
    row_full_base()
    IO.print("")