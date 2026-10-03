import Base
import ./../../tinybendygrad/schedule/memory.bend as M

def r(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def rows(+p: M.Planned) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- r("e0", Maybe.default(&2, U32, List.get(&2, U32, M.Planned.bs(p), 0n), 999))
    _ : Unit <- r("e1", Maybe.default(&2, U32, List.get(&2, U32, M.Planned.bs(p), 1n), 999))
    _ : Unit <- r("e2", Maybe.default(&2, U32, List.get(&2, U32, M.Planned.bs(p), 2n), 999))
    _ : Unit <- r("e3", Maybe.default(&2, U32, List.get(&2, U32, M.Planned.bs(p), 3n), 999))
    _ : Unit <- r("e4", Maybe.default(&2, U32, List.get(&2, U32, M.Planned.bs(p), 4n), 999))
    _ : Unit <- r("head", M.mem_head(M.Planned.bs(p)))
    _ : Unit <- r("tail_len", M.mem_len(List.tail(&2, U32, M.Planned.bs(p))))
    _ : Unit <- r("tail_head", M.mem_head(List.tail(&2, U32, M.Planned.bs(p))))
    IO.print("")

def main() -> IO(Unit):
  do IO<Unit>:
    p : M.Planned <- IO.pure(M.Planned, M.mem_plan(M.proj_of()))
    _ : Unit <- rows(p)
    IO.print("")