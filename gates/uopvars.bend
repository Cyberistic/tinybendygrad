# uopvars.bend -- the PORT lane of the `is_variable` / `unbound` / `variables`
# parity gate. tinygrad/uop/ops.py:1009, :1027 and :1037.
#
#   .venv/bin/python gates/uopvars-gate.py
#
# WHAT IT MEASURES, AND WHY THESE THREE NAMES. `schedule/__init__.bend`'s
# `resolve_linear_call` stands on `variables()`, which stands on `is_variable`
# and `unbound`. They were WALL C of that file's deferral and all three were
# absent; a `variables()` that drops one of its two arms answers a PLAUSIBLE
# parameter set and is wrong, so the rows below are what make the arms visible.
#
# THE FOUR CONJUNCTS OF `is_variable` ARE ONE ROW EACH, because a conjunction
# with one row that is only ever True cannot say WHICH conjunct fired:
#   op is PARAM · vmin_vmax is Some · addrspace is ALU · _shape == ()
# `iv_alu_img` is the SHAPE conjunct and not a fifth fixture: an image2d PARAM
# has a range and an ALU addrspace and its shape is (h, w, 4), so it is the ONLY
# fixture where the last conjunct is the one that answers False.
#
# `iv_alu_bound` is True AND `ub_*` is why: a BOUND Variable is still a Variable
# (`val` is not a conjunct). `unbound()` is what makes the set dedup a bound
# Variable against its unbound form, so `ub_same_as_unbound` asks IDENTITY and
# not equality of fields -- the port's `U32` index is the hash-consed key.
#
# THE ARENA IS READ FROM THE ANSWER AND NOT FROM THE FIXTURE
# (`F.VarR.ar(r)`), and this gate found out why: `variables` MINTS, `UOp.new`
# APPENDS, and the first draft read the caller's pre-growth arena. Every COUNT
# row was right and `vs_dev_*` answered NA -- a node that is unreachable while
# the count says it exists.
import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as SP
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F

def bf(v: Bool) -> String: Bool.pick(String, v, "1", "0")

def rng(hi: U32) -> Maybe<&2, O.PyRange>: Some{O.PyRange{H.i64_zero(), H.i64_of_i32(hi)}}

def pa(slot: U32, r: Maybe<&2, O.PyRange>, ad: SP.Addr, val: Maybe<&2, O.Const>, nm: Maybe<&2, String>) -> O.ParamArg:
  O.ParamArg{slot, SP.int32(), r, None{}, nm, ad, None{}, False{}, None{}, None{}, False{}, val}

# the ONE fixture whose shape is not `()`, so the fourth conjunct is the answer
def pa_img(slot: U32, r: Maybe<&2, O.PyRange>) -> O.ParamArg:
  O.ParamArg{slot, SP.int32(), r, None{}, None{}, SP.Aalu{}, None{}, False{}, Some{O.Img{2, 2}}, None{}, False{}, None{}}

def param(ar: O.Arena, +p: O.ParamArg) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{}, O.AParam{p}, O.TNone{})

def varpa(hi: U32, val: Maybe<&2, O.Const>) -> O.ParamArg:
  pa(3, rng(hi), SP.Aalu{}, val, Some{"v"})

def ivrow(nm: String, +f: O.Found) -> IO(Unit):
  +ar = O.Found.ar(f)
  +x = F.folded(ar)
  +tb = F.Folded.t(x)
  IO.print(String.concat([nm, "=", bf(F.UOp.is_variable(ar, tb, O.Found.i(f)))]))

# ---- unbound (leaf helpers first: Bend is defined-before-use) --------------
def ubval_of(m: Maybe<&2, O.Const>) -> String:
  match m:
    case None{}: "1"
    case Some{_}: "0"

def ubval(arg: O.Arg) -> String:
  match arg:
    case O.AParam{p}: ubval_of(O.ParamArg.val(p))
    case _: "NA"

def ubname_of(m: Maybe<&2, String>) -> String:
  match m:
    case None{}: "none"
    case Some{s}: s

def ubname(arg: O.Arg) -> String:
  match arg:
    case O.AParam{p}: ubname_of(O.ParamArg.name(p))
    case _: "NA"

# `a0` BOUND and `a1` unbound, BOTH in one arena: `ub_same_as_unbound` is then
# "did `unbound(a0)` INTERN onto the node that already existed", which is the
# property upstream's `set` relies on and which a rebuild-by-fields cannot have.
def ubrows() -> IO(Unit):
  +a0 = param(O.Arena.empty(), varpa(10, Some{O.CInt{H.i64_of_i32(5)}}))
  +a1 = param(O.Found.ar(a0), varpa(10, None{}))
  +ub = F.UOp.unbound(O.Found.ar(a1), O.Found.i(a0))
  +ar = O.Found.ar(ub)
  +arg = O.Arena.arg(ar, O.Found.i(ub))
  do IO<Unit>:
    p : Unit <- IO.print(String.concat(["ub_val_none=", ubval(arg)]))
    q : Unit <- IO.print(String.concat(["ub_name_kept=", ubname(arg)]))
    IO.print(String.concat(["ub_same_as_unbound=", bf(U32.is_eq(O.Found.i(ub), O.Found.i(a1)))]))

# ---- variables -------------------------------------------------------------
def vslen(m: Maybe<&2, F.VarR>) -> String:
  match m:
    case None{}: "NONE"
    case Some{r}: U32.show(U32.from_nat(List.length(&2, U32, F.VarR.xs(r))))

def vsrow(nm: String, +f: O.Found) -> IO(Unit):
  +ar = O.Found.ar(f)
  +x = F.folded(ar)
  +tb = F.Folded.t(x)
  IO.print(String.concat([nm, "=", vslen(F.UOp.variables(ar, tb, O.Found.i(f), O.Arena.budget(ar)))]))

def oneof_go(xs: List<&2, U32>) -> Maybe<&2, U32>:
  match xs:
    case Nil{}: None{}
    case x <> _: Some{x}

def devvmax_r(r: O.PyRange) -> String:
  match r:
    case O.PyRange{lo, hi}: String.concat([H.i64_text(lo), "..", H.i64_text(hi)])

def devvmax_of(m: Maybe<&2, O.PyRange>) -> String:
  match m:
    case None{}: "none"
    case Some{r}: devvmax_r(r)

def devvmax(arg: O.Arg) -> String:
  match arg:
    case O.AParam{p}: devvmax_of(O.ParamArg.vmin_vmax(p))
    case _: "NA"

def devname_of(m: Maybe<&2, String>) -> String:
  match m:
    case None{}: "none"
    case Some{s}: s

def devname(arg: O.Arg) -> String:
  match arg:
    case O.AParam{p}: devname_of(O.ParamArg.name(p))
    case _: "NA"

def oneof_h.of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{i}: i
    case None{}: 0

def oneof_h(xs: List<&2, U32>) -> U32:
  oneof_h.of(oneof_go(xs))

def devrows_vm(+r: F.VarR) -> String:
  devvmax(O.Arena.arg(F.VarR.ar(r), oneof_h(F.VarR.xs(r))))

def devrows_nm(+r: F.VarR) -> String:
  devname(O.Arena.arg(F.VarR.ar(r), oneof_h(F.VarR.xs(r))))

def devrows_v(m: Maybe<&2, F.VarR>) -> String:
  match m:
    case None{}: "MISSING"
    case Some{r}: devrows_vm(r)

def devrows_n(m: Maybe<&2, F.VarR>) -> String:
  match m:
    case None{}: "MISSING"
    case Some{r}: devrows_nm(r)

# THE ARENA IS `F.VarR.ar(r)`, THE GROWN ONE. Reading the fixture's arena here is
# the defect this gate found, so this def is where a regression would go red.
def devrows(+f: O.Found) -> IO(Unit):
  +ar = O.Found.ar(f)
  +x = F.folded(ar)
  +tb = F.Folded.t(x)
  +m = F.UOp.variables(ar, tb, O.Found.i(f), O.Arena.budget(ar))
  do IO<Unit>:
    p : Unit <- IO.print(String.concat(["vs_dev_count=", vslen(m)]))
    q : Unit <- IO.print(String.concat(["vs_dev_vmax=", devrows_v(m)]))
    IO.print(String.concat(["vs_dev_name=", devrows_n(m)]))

# ---- fixtures --------------------------------------------------------------
def vvar(nm: String, hi: U32) -> O.Found:
  O.UOp.variable(O.Arena.empty(), nm, H.i64_zero(), H.i64_of_i32(hi), 1, SP.weakint())

def v2same() -> O.Found:
  +a = vvar("v", 7)
  O.UOp.alu(O.Found.ar(a), O.OpsADD{}, [O.Found.i(a), O.Found.i(a)])

def v2diff() -> O.Found:
  +a = vvar("v", 7)
  +w = O.UOp.variable(O.Found.ar(a), "w", H.i64_zero(), H.i64_of_i32(3), 1, SP.weakint())
  O.UOp.alu(O.Found.ar(w), O.OpsADD{}, [O.Found.i(a), O.Found.i(w)])

def vrng(at: O.AxisType) -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(8)})
  O.UOp.range_end(O.Found.ar(c), O.Found.i(c), [0], at)

# the range and a variable TOGETHER, so `vs_device` is 2 and `vs_weak` is 1:
# the difference is the AXIS, not the presence of the range
def vrngvar(at: O.AxisType) -> O.Found:
  +r = vrng(at)
  +v = O.UOp.variable(O.Found.ar(r), "v", H.i64_zero(), H.i64_of_i32(7), 1, SP.weakint())
  O.UOp.alu(O.Found.ar(v), O.OpsADD{}, [O.Found.i(r), O.Found.i(v)])

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- ivrow("iv_alu_range", param(O.Arena.empty(), pa(0, rng(10), SP.Aalu{}, None{}, None{})))
    b1 : Unit <- ivrow("iv_alu_norange", param(O.Arena.empty(), pa(1, None{}, SP.Aalu{}, None{}, None{})))
    c : Unit <- ivrow("iv_global_range", param(O.Arena.empty(), pa(2, rng(10), SP.AGlobal{}, None{}, None{})))
    d : Unit <- ivrow("iv_alu_bound", param(O.Arena.empty(), varpa(10, Some{O.CInt{H.i64_of_i32(5)}})))
    e : Unit <- ivrow("iv_variable", vvar("v", 7))
    f2 : Unit <- ivrow("iv_alu_img", param(O.Arena.empty(), pa_img(4, rng(10))))
    g : Unit <- ivrow("iv_not_param", O.UOp.const(O.Arena.empty(), O.CInt{H.i64_zero()}))
    h : Unit <- ubrows()
    i : Unit <- vsrow("vs_none", O.UOp.const(O.Arena.empty(), O.CInt{H.i64_zero()}))
    j : Unit <- vsrow("vs_one", vvar("v", 7))
    k : Unit <- vsrow("vs_dedup", v2same())
    l : Unit <- vsrow("vs_two", v2diff())
    m : Unit <- vsrow("vs_bound", param(O.Arena.empty(), varpa(10, Some{O.CInt{H.i64_of_i32(5)}})))
    n : Unit <- vsrow("vs_device", vrngvar(O.AXIS_DEVICE{}))
    o : Unit <- vsrow("vs_weak", vrngvar(O.AXIS_WEAK{}))
    devrows(vrng(O.AXIS_DEVICE{}))
