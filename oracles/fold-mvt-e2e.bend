# fold-mvt-e2e.bend -- the DOWNSTREAM PROOF: a graph whose ROOT is a movement op, so
# the fold's answer for that root is what a caller gets.
#
# This is the shape `.agents/slop/notes/bend2-constraints.md` rule 18 (line 4099)
# calls out: "AN UNANSWERABLE NODE POISONS ITS CONSUMERS, so 'CAN THE FOLD ANSWER X'
# IS A PROPERTY OF THE WHOLE SUBGRAPH". Before this unit, a graph containing an
# EXPAND made the ROOT unanswerable. Now it does not, and this file prints the ROOT's
# four facts and its answer.
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/LAWS/spec.bend as S

def pa(size: U32) -> O.ParamArg:
  O.ParamArg{0, S.int32(), Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def buf(size: U32) -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{pa(size)}, O.TNone{})

def cst(ar: O.Arena, n: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

# EXPAND(BUFFER(4), CONST(2)) <- STORE(const, expanded)
def g_expand_store() -> O.Found:
  +b = buf(4)
  +c = cst(O.Found.ar(b), 2)
  +e = O.UOp.new(O.Found.ar(c), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})
  +z = cst(O.Found.ar(e), 0)
  O.UOp.new(O.Found.ar(z), O.OpsSTORE{}, [O.Found.i(z), O.Found.i(e)], O.ANone{}, O.TNone{})

# PERMUTE(RESHAPE(BUFFER(6), STACK(2,3)), (1,0)) <- AFTER(perm, cont)
def g_permute_after() -> O.Found:
  +b = buf(6)
  +c2 = cst(O.Found.ar(b), 2)
  +c3 = cst(O.Found.ar(c2), 3)
  +k = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c2), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r = O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})
  +p = O.UOp.new(O.Found.ar(r), O.OpsPERMUTE{}, [O.Found.i(r)], O.ATuple{[1, 0]}, O.TNone{})
  +z = cst(O.Found.ar(p), 0)
  O.UOp.new(O.Found.ar(z), O.OpsAFTER{}, [O.Found.i(p), O.Found.i(z)], O.ANone{}, O.TNone{})

def dim_str(d: O.Sint) -> String:
  match d:
    case O.SU{u}: "UOp"
    case O.SI{i}: U32.show(H.lo32(i))

def dims_str.go(ds: List<&2, O.Sint>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case d <> t: dims_str.go(t, List.append(&2, String, acc, [dim_str(d)]))

def dims_str(ds: List<&2, O.Sint>) -> String:
  String.concat(["(", String.join(dims_str.go(ds, Nil{}), ","), ")"])

def dt_nm(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def settled_str(+f: O.Found) -> String:
  +x = F.folded(O.Found.ar(f))
  Bool.show(F.Kahn.settled(F.Folded.ar(x), F.Folded.t(x)))

# LOCAL, not `F.shape_str`: the ORIGINAL fold.bend has no such printer, and this probe
# has to run against BOTH versions to measure what changed.
def shape_str.go(m: Maybe<&2, List<&2, O.Sint>>) -> String:
  match m:
    case Some{ds}: dims_str(ds)
    case None{}  : "RAISE"

def shape_str.of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case Some{g}: shape_str.go(g)
    case None{}  : "ABSENT"

def shape_str(+f: O.Found) -> String:
  +x = F.folded(O.Found.ar(f))
  shape_str.of(F.UOp.shape(F.Folded.ar(x), F.Folded.t(x), O.Found.i(f)))

# A `match` MAY NOT SCRUTINISE A CALL, so the `Maybe` is a PARAMETER of its own def --
# the same split `fliplen`-by-hand costs everywhere else in this port.
def dt_str.of(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: dt_nm(d)
    case None{}  : "ABSENT"

def dt_str(+f: O.Found) -> String:
  +x = F.folded(O.Found.ar(f))
  dt_str.of(F.UOp.dtype(F.Folded.ar(x), F.Folded.t(x), O.Found.i(f)))

def op_str(+f: O.Found) -> String:
  O.Ops.name(O.Arena.op(O.Found.ar(f), O.Found.i(f)))

def report(nm: String, +f: O.Found) -> IO(Unit):
  IO.print(String.concat(["mv_e2e_", nm, " root=", op_str(f), " settled=", settled_str(f),
                          " shape=", shape_str(f), " dtype=", dt_str(f)]))

def main() -> IO(Unit):
  do IO<Unit>:
    report("expand_store", g_expand_store())
    report("permute_after", g_permute_after())
