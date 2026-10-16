# OFF-GATE PROBE. WHAT DOES THE PORT ANSWER FOR AN f64 TARGET, AND FOR THE f16 FAMILY?
# MEASURED BEFORE ANY ROW IS ADDED, so the class the new row gets is read off the lanes and
# not guessed. THE CENSUS'S OWN PRINTER AND ITS OWN FIXTURE BUILDER ARE REUSED BY IMPORT --
# this file re-derives nothing.
#
#   bin/bend .agents/slop/l2ipool/probe64.bend

import ../../../tinybendygrad/helpers.bend as H
import ../../../tinybendygrad/LAWS/spec.bend as S
import ../../../tinybendygrad/uop/ops.bend as O
import ../../../tinybendygrad/codegen/decomp/dtype.bend as D
import ../../../gates/decomp_graph_census.bend as C

# THE CENSUS'S OWN `dc_l2i1`: rebuild `fixtures()` per cell, read the pool off THAT arena,
# and print the DEEP CONE with the census's own `dc_sig.of`.
def p64(+nm: String, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, base: Nat, nw: U32) -> List<&2, String>:
  +ga = D.fixtures()
  +ws = D.dd_ws(ga, base, nw)
  +r = D.l2i(D.Ga.ar(ga), op, dt, xdt, ws)
  C.dc_put(nm, C.dc_sig.of(r, D.Ga.ar(ga)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- C.dc_putl(p64("f64<-f32@19", O.OpsCAST{}, S.double(), S.single(), 19n, 2))
    b : Unit <- C.dc_putl(p64("f32<-f32@19", O.OpsCAST{}, S.single(), S.single(), 19n, 2))
    c : Unit <- C.dc_putl(p64("f64<-u32@9 ", O.OpsCAST{}, S.double(), S.uint32(), 9n, 2))
    d : Unit <- C.dc_putl(p64("f64<-i32@4 ", O.OpsCAST{}, S.double(), S.int32(), 4n, 2))
    e : Unit <- C.dc_putl(p64("f64<-bool@14", O.OpsCAST{}, S.double(), S.boolean(), 14n, 2))
    f : Unit <- C.dc_putl(p64("f16<-f32@19", O.OpsCAST{}, S.half(), S.single(), 19n, 2))
    g : Unit <- C.dc_putl(p64("bf16<-f32@19", O.OpsCAST{}, S.bfloat16(), S.single(), 19n, 2))
    h : Unit <- C.dc_putl(p64("i64<-f32@19", O.OpsCAST{}, S.int64(), S.single(), 19n, 2))
    return Unit{}