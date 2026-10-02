import Base
import ../../../../tinybendygrad/runtime/ops_nv.bend as N
def row(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def main() -> IO<Unit):
  do IO<Unit>:
    row("bit_ada", N.iface.bit(N.CLASS_ADA_COMPUTE_A()))
    row("bit_turing", N.iface.bit(N.CLASS_TURING_USERMODE()))
    row("bit_nvc9b0", N.iface.bit(N.CLASS_NVC9B0_VIDEO_DECODER()))
    row("bit_ampgpfifo", N.iface.bit(N.CLASS_AMPERE_GPFIFO()))
    row("has_ada_1386", Bool.to_u32(N.iface.has(N.Hav{1386}, N.CLASS_ADA_COMPUTE_A())))
    row("has_turing_1386", Bool.to_u32(N.iface.has(N.Hav{1386}, N.CLASS_TURING_USERMODE())))
    row("shrn_1386_5", U32.shrn(1386, 5n))
    row("has_dummy", Bool.to_u32(N.iface.has(N.Hav{1386}, 51648)))
    IO.print("done=1")
