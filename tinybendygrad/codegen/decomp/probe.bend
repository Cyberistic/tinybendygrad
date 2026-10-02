import Base

def w64.lo(x: Word(64n)) -> Word(32n):
  Word.shr(32n, x)

def w64.pad(n: Word(32n)) -> Word(64n):
  Word.add(64n, Word(32n, n), Word.zero(32n), Word.zero(64n))

def w64.mul(a: Word(64n), b: Word(64n)) -> Word(64n):
  Word.mul(64n, a, b)

def w64.to_u32(x: Word(64n)) -> U32:
  U32{U32.data(w64.lo(x))}

def w64.hi_u32(x: Word(64n)) -> U32:
  U32{U32.data(Word.shr(32n, Word.shr(32n, x)))}

def w64.of(x: Word(64n), hi: U32) -> Word(64n):
  Word.add(64n, Word.mul(32n, U32.data(hi), Word.zero(63n)), Word(32n, w64.lo(x)), Word.zero(64n))

def p1() -> IO(Unit):
  do IO<Unit>:
    a : U32 <- IO.pure(U32, 1234567891)
    b : U32 <- IO.pure(U32, 2147483647)
    wa : Word(64n) <- IO.pure(Word(64n), w64.pad(U32.data(a)))
    wb : Word(64n) <- IO.pure(Word(64n), w64.pad(U32.data(b)))
    p : Word(64n) <- IO.pure(Word(64n), w64.mul(wa, wb))
    IO.print(String.concat(["mul_lo=", U32.show(w64.to_u32(p))]))
    IO.print(String.concat(["mul_hi=", U32.show(w64.hi_u32(p))]))

def main() -> IO(Unit):
  do IO<Unit>:
    p1()