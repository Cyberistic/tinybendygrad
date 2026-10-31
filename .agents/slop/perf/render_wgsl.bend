# render_wgsl.bend -- THE PORT's OWN `wgsl.bend` MODULE ASSEMBLY, ON A REAL KERNEL.
#
#   ./bin/bend .agents/slop/perf/render_wgsl.bend E_1024
#
# THE BUFFERS ARE THE ONES THE SCHEDULER MADE, not a fixture: `E_1024`'s uop list
# (`.agents/slop/perf/stage1/E_1024.rows`) has three GLOBAL f32 PARAMs of 1024 elements, and
# `data{slot}_{numel}` is upstream's name for them (`wgsl.py`'s `PARAM` arm), which is why
# the names below are spelled rather than guessed.
#
# ⇒ AND THE BODY IS EMPTY, BECAUSE `wgsl.bend` HAS NO UOP->BODY WALK YET. `render_kernel`
# takes `kernel: List<String>` and `kern_alu()`/`kern_mixed()` in `wgsl.bend` build those
# strings BY HAND. So this driver answers the part of the module the port CAN make from a
# real kernel -- the prologue, the bindings, the signature and the workgroup size -- and the
# body is the missing walker, named rather than faked.
import Base
import ./../../../tinybendygrad/renderer/wgsl.bend as W
import ./../../../tinybendygrad/LAWS/spec.bend as S

def bufs() -> List<&2, W.Buf>:
  [W.Buf{"data0_1024", S.single(), S.AGlobal{}, 1024},
   W.Buf{"data1_1024", S.single(), S.AGlobal{}, 1024},
   W.Buf{"data2_1024", S.single(), S.AGlobal{}, 1024}]

def nth(xs: List<&1, String>, k: Nat) -> String:
  Maybe.default(&1, String, List.get(&1, String, xs, k), "")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    fn : String = nth(args, 1n)
    # `Scan{sz, half}` is what `rk_scan` computes from the uop list: the LOCAL-size axes sorted
    # (`[1]` here -- the kernel's only SPECIAL is `gidx0`) and whether any uop is f16 (`False`).
    IO.print(W.render_kernel(fn, Nil{}, bufs(), W.Scan{[1], False{}}))
