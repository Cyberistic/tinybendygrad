import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S

def bl32(+x: U32) -> U32:
  +a = Bool.pick(U32, U32.is_ge(x, 65536), U32.shrn(x, 16n), x)
  +ba = Bool.pick(U32, U32.is_ge(x, 65536), 16, 0)
  +b = Bool.pick(U32, U32.is_ge(a, 256), U32.shrn(a, 8n), a)
  +bb = Bool.pick(U32, U32.is_ge(a, 256), 8, 0)
  +c = Bool.pick(U32, U32.is_ge(b, 16), U32.shrn(b, 4n), b)
  +bc = Bool.pick(U32, U32.is_ge(b, 16), 4, 0)
  +d = Bool.pick(U32, U32.is_ge(c, 4), U32.shrn(c, 2n), c)
  +bd = Bool.pick(U32, U32.is_ge(c, 4), 2, 0)
  +e = Bool.pick(U32, U32.is_ge(d, 2), U32.shrn(d, 1n), d)
  +be = Bool.pick(U32, U32.is_ge(d, 2), 1, 0)
  +tail = Bool.pick(U32, U32.is_zero(e), 0, 1)
  +s1 = U32.add(ba, bb)
  +s2 = U32.add(s1, bc)
  +s3 = U32.add(s2, bd)
  +s4 = U32.add(s3, be)
  U32.add(s4, tail)

def bl64(+hi: U32, lo: U32) -> U32:
  Bool.pick(U32, U32.is_zero(hi), bl32(lo), U32.add(32, bl32(hi)))

def p(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- p("bl32_255", bl32(255))
    b : Unit <- p("bl32_256", bl32(256))
    c : Unit <- p("bl32_0", bl32(0))
    d : Unit <- p("bl32_1", bl32(1))
    e : Unit <- p("bl64_1_0", bl64(1, 0))
    p("bl64_0_5", bl64(0, 5))
