import Base
type Sec is Data:
  Sec{nm: String, hdr: Sh, cont: String}
type Sh is Data:
  Sh{a: U32, b: U32}
def Sh.a(s: Sh) -> U32:
  match s:
    case Sh{a, b}: a
def Sh.b(s: Sh) -> U32:
  match s:
    case Sh{a, b}: b
def mk1(x: String, y: Sh, z: String) -> Sec: Sec{x, y, z}
def Sec.nm(s: Sec) -> String:
  match s:
    case Sec{nm, hdr, cont}: nm
def Sec.hdr(s: Sec) -> Sh:
  match s:
    case Sec{nm, hdr, cont}: hdr
def Sec.cont(s: Sec) -> String:
  match s:
    case Sec{nm, hdr, cont}: cont
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([Sec.nm(mk1("hi", Sh{1,2}, "zz")), "/",
      U32.show(Sh.a(Sec.hdr(mk1("hi", Sh{1,2}, "zz"))))]))
