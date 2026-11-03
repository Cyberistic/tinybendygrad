# decprobe.bend -- DECODE ONLY: the live renderer's parser with the renderer removed.
#
# This exists to SPLIT the live path's per-kernel cost into its two halves. It imports the real `live.bend`
# and calls the real decode (`walk`), so the number it produces is the parser's and not a replica's.
import Base
import ./../../../tinybendygrad/renderer/live.bend as L
import ./../../../tinybendygrad/renderer/cstyle.bend as C

def sink(+xs: List<&2, C.KU>) -> U32:
  match xs:
    case Nil{}: 0
    case _ <> t: U32.add(1, sink(t))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    ks : List<&2, C.KU> <- L.walk(L.skip_first(as), Nil{})
    IO.print(U32.show(sink(ks)))

