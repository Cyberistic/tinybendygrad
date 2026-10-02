import Base
type PKey is Data:
  PKey{src3: U32, dev0: U32, dev1: U32}
type PC is Data:
  PC{n: U32, next: U32, ks: List<&2, PKey>}
def PC.of() -> PC: PC{0, 0, Nil{}}
def row(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def main() -> IO(Unit):
  do IO<Unit>:
    row("n", PC.n(PC.of()))
    IO.print("ok=1")
