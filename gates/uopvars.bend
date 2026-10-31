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
import ./../tinybendygrad/schedule/__init__.bend as SC

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


# ---- `binds` -- the CONSUMER, schedule/__init__.py:104-106 -------------------
# Four params on ONE call, chosen so the FILTER and the VALUE disagree:
#   slot 0  ALU variable, UNBOUND  -> a bind, value is ITSELF
#   slot 1  ALU variable, BOUND    -> a bind, value is the UNBOUND TWIN
#   slot 2  ALU PARAM, NO RANGE    -> a bind, value is ITSELF (the filter does not read vmin_vmax)
#   slot 3  GLOBAL PARAM           -> NOT a bind
# `lb_k1_unbound` is the one row a "return x" implemention cannot pass, and
# `lb_k2_self` is the one a "always unbound" implementation cannot pass.
type LBFx is Data:
  LBFx{f: O.Found, a0: U32, a1: U32, a2: U32, a3: U32}

def LBFx.f(x: LBFx) -> O.Found:
  match x:
    case LBFx{f, a0, a1, a2, a3}: f

def LBFx.a0(x: LBFx) -> U32:
  match x:
    case LBFx{f, a0, a1, a2, a3}: a0

def LBFx.a1(x: LBFx) -> U32:
  match x:
    case LBFx{f, a0, a1, a2, a3}: a1

def LBFx.a2(x: LBFx) -> U32:
  match x:
    case LBFx{f, a0, a1, a2, a3}: a2

# THE FIXTURE CARRIES ITS OWN INDICES. A row that hardcodes the arena position of
# `a0` is a row about the arena's allocation order, not about `binds` -- MEASURED:
# the first draft asserted `binds[0] == 1` and the arena gave `2`, so the row went
# red while the DEF was right.
def lbcall() -> LBFx:
  +body = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_zero()})
  +a0 = param(O.Found.ar(body), pa(0, rng(7), SP.Aalu{}, None{}, Some{"a"}))
  +a1 = param(O.Found.ar(a0), pa(1, rng(7), SP.Aalu{}, Some{O.CInt{H.i64_of_i32(3)}}, Some{"b"}))
  +a2 = param(O.Found.ar(a1), pa(2, None{}, SP.Aalu{}, None{}, Some{"c"}))
  +a3 = param(O.Found.ar(a2), pa(3, None{}, SP.AGlobal{}, None{}, Some{"d"}))
  +c = O.UOp.new(O.Found.ar(a3), O.OpsCALL{},
    [O.Found.i(body), O.Found.i(a0), O.Found.i(a1), O.Found.i(a2), O.Found.i(a3)], O.ANone{}, O.TNone{})
  LBFx{c, O.Found.i(a0), O.Found.i(a1), O.Found.i(a2), O.Found.i(a3)}

# `Map.get` answers a `Sigma`, not the value -- `render.bend:1064`'s `ctx_get.of`
# is the tree's own projection, and this is the same match.
def lbget.of(r: Sigma<&1, &1, Map<&2, U32>, _ => U32>) -> U32:
  match r:
    case Tuple{m, v}: v

def lbget(+m: Map<&2, U32>, k: String) -> U32:
  lbget.of(Map.get(U32, O.ParamArg.no_slot(), m, k))

def lbval(arg: O.Arg) -> String:
  match arg:
    case O.AParam{p}: ubval_of(O.ParamArg.val(p))
    case _: "NA"

# 9 is a slot the call never names (must SURVIVE); 0 is a slot the call DOES bind
# (must be OVERRIDDEN). Both are 42/41, which no node index is, so a leaked outer
# value cannot be mistaken for the inner one.
def lbouter() -> Map<&2, U32>:
  Map.set(&2, U32, Map.set(&2, U32, Map.new(&2, U32), "9", 42), "0", 41)

def lbrows(+fx: LBFx) -> IO(Unit):
  +f = LBFx.f(fx)
  +lb = SC.sc_linear_binds_outer(lbouter(), O.Found.ar(f), O.Found.i(f))
  +ar = SC.LinBinds.ar(lb)
  +m = SC.LinBinds.m(lb)
  do IO<Unit>:
    p1 : Unit <- IO.print(String.concat(["lb_k0_self=", bf(U32.is_eq(lbget(m, "0"), LBFx.a0(fx)))]))
    p2 : Unit <- IO.print(String.concat(["lb_k1_moved=", bf(Bool.not(U32.is_eq(lbget(m, "1"), LBFx.a1(fx))))]))
    p3 : Unit <- IO.print(String.concat(["lb_k1_unbound=", lbval(O.Arena.arg(ar, lbget(m, "1")))]))
    p4 : Unit <- IO.print(String.concat(["lb_k2_self=", bf(U32.is_eq(lbget(m, "2"), LBFx.a2(fx)))]))
    p5 : Unit <- IO.print(String.concat(["lb_gone=", bf(U32.is_eq(lbget(m, "3"), O.ParamArg.no_slot()))]))
    p6 : Unit <- IO.print(String.concat(["lb_outer_keep=", bf(U32.is_eq(lbget(m, "9"), 42))]))
    IO.print(String.concat(["lb_outer_over=", bf(U32.is_eq(lbget(m, "0"), LBFx.a0(fx)))]))


# ---- `subs` -- the SECOND consumer, schedule/__init__.py:109 -----------------
# `si.src` is ALL of src (the CALL BODY included); `binds` walks `src[1:]`.
# So `subs_body` is the row a port that copied `binds`'s slice cannot pass: the
# body's variable is on `src[0]` and a `src[1:]` walk never sees it.
type SubFx is Data:
  SubFx{f: O.Found, v0: U32, v2: U32}

def SubFx.f(x: SubFx) -> O.Found:
  match x:
    case SubFx{f, v0, v2}: f

def SubFx.v0(x: SubFx) -> U32:
  match x:
    case SubFx{f, v0, v2}: v0

def SubFx.v2(x: SubFx) -> U32:
  match x:
    case SubFx{f, v0, v2}: v2

# the body holds slot 2's ALU variable; the call's one positional src is slot 0's
def subscall() -> SubFx:
  +v2 = param(O.Arena.empty(), pa(2, rng(3), SP.Aalu{}, None{}, Some{"p2"}))
  +body = O.UOp.alu(O.Found.ar(v2), O.OpsADD{}, [O.Found.i(v2), O.Found.i(v2)])
  +v0 = param(O.Found.ar(body), pa(0, rng(7), SP.Aalu{}, None{}, Some{"p0"}))
  +c = O.UOp.new(O.Found.ar(v0), O.OpsCALL{}, [O.Found.i(body), O.Found.i(v0)], O.ANone{}, O.TNone{})
  SubFx{c, O.Found.i(v0), O.Found.i(v2)}

def subsonly(k: String, v: U32) -> Map<&2, U32>:
  Map.set(&2, U32, Map.new(&2, U32), k, v)

def subsget.of(m: Maybe<&2, SC.LinBinds>, k: String) -> U32:
  match m:
    case None{}: O.ParamArg.no_slot()
    case Some{lb}: SC.sc_mapget(SC.LinBinds.m(lb), k)

def subsget(m: Maybe<&2, SC.LinBinds>, k: String) -> U32:
  subsget.of(m, k)

# PRESENCE, NOT VALUE, AND THE PLANT IS WHY. `sc_mapget` answers the NO-SLOT
# sentinel for an absent key, so "absent" and "present and mapped to the sentinel"
# are the SAME U32 -- which made `subs_miss` a row that a port DROPPING the
# membership test could not turn red. MEASURED: that plant moved 0 of 31 rows
# before this changed. `Map.has` answers a Sigma whose second component is the Bool.
def subshas.of2(r: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, v}: v

def subshas.of(m: Maybe<&2, SC.LinBinds>, k: String) -> Bool:
  match m:
    case None{}: False{}
    case Some{lb}: subshas.of2(Map.has(&2, U32, SC.LinBinds.m(lb), k))

def subshas(m: Maybe<&2, SC.LinBinds>, k: String) -> Bool:
  subshas.of(m, k)

def subsrows(+fx: SubFx) -> IO(Unit):
  +f = SubFx.f(fx)
  +ar = O.Found.ar(f)
  +si = O.Found.i(f)
  do IO<Unit>:
    p1 : Unit <- IO.print(String.concat(["subs_body=",
      bf(U32.is_eq(subsget(SC.sc_apply_subs(ar, si, subsonly("2", 99)), U32.show(SubFx.v2(fx))), 99))]))
    p2 : Unit <- IO.print(String.concat(["subs_hit=",
      bf(U32.is_eq(subsget(SC.sc_apply_subs(ar, si, subsonly("0", 88)), U32.show(SubFx.v0(fx))), 88))]))
    p3 : Unit <- IO.print(String.concat(["subs_miss=",
      bf(Bool.not(subshas(SC.sc_apply_subs(ar, si, subsonly("1", 77)), U32.show(SubFx.v0(fx)))))]))
    IO.print(String.concat(["subs_none=",
      bf(Bool.not(subshas(SC.sc_apply_subs(ar, si, Map.new(&2, U32)), U32.show(SubFx.v0(fx)))))]))

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
    lbrows(lbcall())
    subsrows(subscall())
