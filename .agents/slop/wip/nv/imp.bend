import Base
import ../../../../tinybendygrad/helpers.bend as H
import ../../../../tinybendygrad/LAWS/spec.bend as S
import ../../../../tinybendygrad/device.bend as D

def row(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def brow(nm: String, +b: D.BFound) -> IO(Unit): row(nm, D.nbytes(D.BFound.ar(b), D.BFound.i(b)))

def main() -> IO(Unit):
  do IO<Unit>:
    +a : List<&2, U32> <- IO.pure(List<&2, U32>, D.iter_sig([8, 8, 8, 4, 4]))
    row("sig_len", U32.from_nat(List.length(&2, U32, a)))
    row("sig_ok", Bool.to_u32(H.u32_list_eq(a, [0, 8, 16, 24, 32])))
    +b : D.BFound <- IO.pure(D.BFound, D.bnew(D.bar_empty(), D.root(3, 1, S.uint32(), D.spec())))
    brow("bar_nbytes", b)
    +v : D.BFound <- IO.pure(D.BFound, D.bview(D.BFound.ar(b), 0, 1, S.uint8(), 8))
    brow("view_nbytes", v)
    row("view_off", D.Bn.off(D.bar_at(D.BFound.ar(v), 0)))
    row("host_off", D.host_offset(4096, 16))
    IO.print("imp-done=1")
