# .agents/slop/browser/skl.bend -- `St.kernel`'s LINES IN ORDER. `_render.plain` writes
# `ku_indent(St.depth(st0))` before every statement, so a line's LEADING SPACES are its depth at
# emission. If `int cast0 = ...` already carries two spaces here and the C shows it at eight, then
# `render_kernel` moved it; if it carries eight here, `_render` computed the depth too deep.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./fchainl.bend as CH

def kus0(+i: U32) -> (O.Arena & List<&2, C.KU>):
  +k = CH.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +ar = SCH.lin_ar(lin)
  +kk = CH.one2.go(SCH.lin_kernels(lin), ar, 0, i, 0)
  DEV.body_kus(ar, kk)

def show.go(+xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: show.go(t, List.append(&2, String, acc, [String.concat([".", x])]))

def lines2(p: (O.Arena & List<&2, C.KU>)) -> List<&2, String>:
  (+a, +ks) = p
  show.go(List.reverse(&2, String, C.St.kernel(C._render(C.dev_clang(), ks))), Nil{})

def lines(+i: U32) -> List<&2, String>:
  lines2(kus0(i))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["lines3=", String.join(lines(3), "\n")]))
