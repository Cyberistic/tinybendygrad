import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S

# Probe: l2i(CAST, long, UOp.const(0, uint32)) and the neighbours the note
# conflated with it. Prints REFUSED or the two-level tree the gate prints.
# Does not edit dtype.bend.

def show.w(m: Maybe<&2, D.W2>) -> String:
  match m:
    case None{}: "REFUSED"
    case Some{+w}:
      String.concat([D.dd_tree(D.W2.ar(w), D.W2.lo(w)), " | ",
                     D.dd_tree(D.W2.ar(w), D.W2.hi(w))])

def one(+ar: O.Arena, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, +x: U32, +nm: String) -> String:
  String.concat([nm, "=", show.w(D.l2i(ar, op, dt, xdt, [x])), "\n"])

def main() -> IO(Unit):
  +c = D.dd_const.int(O.Arena.empty(), 0, S.uint32())
  +ar = O.Found.ar(c)
  +i = O.Found.i(c)
  +ci = D.dd_const.int(ar, 0, S.int32())
  +ari = O.Found.ar(ci)
  +cf = D.dd_cf(ari, 0.0, S.single())
  IO.print(String.concat([
    one(ar, O.OpsCAST{}, S.int64(), S.uint32(), i, "long_u32"),
    one(ari, O.OpsCAST{}, S.int64(), S.int32(), O.Found.i(ci), "long_i32"),
    one(O.Found.ar(cf), O.OpsCAST{}, S.int64(), S.single(), O.Found.i(cf), "long_f32"),
    one(ar, O.OpsCAST{}, S.uint64(), S.uint32(), i, "ulong_u32"),
    one(ar, O.OpsCAST{}, S.single(), S.uint32(), i, "f32_u32"),
    one(ar, O.OpsFLOORDIV{}, S.int32(), S.uint32(), i, "floordiv")]))
