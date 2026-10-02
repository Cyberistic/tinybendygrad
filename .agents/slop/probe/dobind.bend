import Base
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def hdr0(+r: Bool) -> U32: Bool.pick(U32, r, 196736, 196864)
def t() -> IO(Unit):
  do IO<Unit>:
    urow("a", U32.and(U32.shrn(hdr0(False{}), 8n), 255))
def main() -> IO(Unit):
  do IO<Unit>:
    z : Unit <- t()
    IO.print("ok")
