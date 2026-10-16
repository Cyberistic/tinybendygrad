# OFF-GATE PROBE 2. WHICH GUARD REFUSES ON `dt = double`, AND IS IT THE SELECTOR?
# The census carries two rows that differ in `dt`'s CLASS and not in its WIDTH -- `lg5`
# (i64 <- f32) and the new `lgz` (f64 <- f32) -- so `dd_cast_sel` reads the SAME for both.
# This file prints the selector, `l2i_dt`'s answer, and `dd_is_long`/`dd_is_float` per cell,
# because a claim about WHICH guard refuses must be MEASURED and not read off a `match`.
#
#   bin/bend .agents/slop/l2ipool/probe65.bend

import ../../../tinybendygrad/LAWS/spec.bend as S
import ../../../tinybendygrad/uop/ops.bend as O
import ../../../tinybendygrad/codegen/decomp/dtype.bend as D
import ../../../gates/decomp_graph_census.bend as C

def bs(b: Bool) -> String:
  match b:
    case True{}: "T"
    case False{}: "F"

# `l2i_dt`'s shape is a `Maybe<Dt>`, so it is rendered by ITS OWN two answers.
def ld(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: O.dt_name(d)
    case None{}: "NONE"

def p65(+nm: String, +dt: S.Dt, +xdt: S.Dt) -> List<&2, String>:
  +sel = D.dd_cast_sel(D.dd_is_long(dt), D.dd_is_float(xdt), D.dd_is_float(dt))
  [String.concat([nm, " sel=", U32.show(sel), " is_long=", bs(D.dd_is_long(dt)),
                  " srcfl=", bs(D.dd_is_float(xdt)), " flt=", bs(D.dd_is_float(dt)),
                  " l2i_dt=", ld(D.l2i_dt(dt))])]

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- C.dc_putl(p65("lg5 i64<-f32", S.int64(), S.single()))
    b : Unit <- C.dc_putl(p65("lgz f64<-f32", S.double(), S.single()))
    c : Unit <- C.dc_putl(p65("lgu f32<-f32", S.single(), S.single()))
    d : Unit <- C.dc_putl(p65("lgv i64<-u32", S.int64(), S.uint32()))
    e : Unit <- C.dc_putl(p65("lg2 i64<-i32", S.int64(), S.int32()))
    f : Unit <- C.dc_putl(p65("f16<-f32  ", S.half(), S.single()))
    g : Unit <- C.dc_putl(p65("f64<-u32  ", S.double(), S.uint32()))
    h : Unit <- C.dc_putl(p65("u64<-f32  ", S.uint64(), S.single()))
    return Unit{}