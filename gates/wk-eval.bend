# wk-eval.bend -- the GATE DRIVER for `_eval` and the three dunders, ops.py:521-529.
#
#   .venv/bin/python gates/wk-eval-gate.py
#
# WHY THESE LIVE IN weak.bend AND NOT IN ops.bend, which is the finding and not a detail. The
# marker for `_eval` sat in `ops.bend`'s NOT-PORTED block, and it CANNOT be written there:
# `_eval` needs the node's dtype AND its two bounds, and `ops.bend` imports only `Base`,
# `helpers` and `LAWS/spec` -- while `UOp.vmin`/`vmax` are in `fold.bend` and the node-level
# dtype reader is in `weak.bend`, and BOTH of those import `ops.bend`. So the def sits downstream
# of the file that wanted it. That is the same relocation `wk_commit_dtype` already got, and the
# same shape of finding: an import edge, not a language limit. MEASURED, not inferred -- the
# driver below calls `W.wk_eval_*`, and `ops.bend` cannot name them at all.
#
# WHAT THE ROWS ARE. `_eval` makes THREE checks in a fixed order and refuses on the first that
# fails, so a row that only printed the outcome could not say WHICH check refused. Two facts per
# case instead -- the VALUE (`none` on any refusal) and the DTYPE SET membership -- and the pair
# separates the two refusals without the driver re-deciding anything:
#
#     val=none, dt=0   the dtype is not in the caller's set      (ops.py:521's first assert)
#     val=none, dt=1   the dtype is fine and the bounds differ   (ops.py:521's ValueError)
#
# So no row's meaning depends on the driver, and a reader that refused for the wrong reason
# cannot pass: the two refusals have disjoint `dt` values and both are pinned.
#
# THE `dt` ROWS ARE NOT REDUNDANT WITH THE `val` ROWS. CPython's third check,
# `isinstance(vmin, expected_type)`, has no separate port spelling because `Cls` IS the value's
# type; these rows are what make that claim checkable rather than merely argued, and they pin it
# per cell on the SAME nodes the `val` rows read.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/mixin/dtype.bend as D
import ./../tinybendygrad/uop/weak.bend as W

# ONE PRINTER, AND IT TAKES A FINISHED LINE. Every row builder below spells its own whole name --
# `sh` makes `nm_val=...`, `dti` makes `nm_dt=...` -- so a two-argument printer would have to be
# handed a name that is already in the string, and a row whose name is built in two places is a
# row whose name can be built wrong in one of them.
def pr(v: String) -> IO(Unit): IO.print(v)

# `Maybe<&1, H.I64>` prints as its value or `none`, and the two refusals both land on `none` --
# which is why the `_dt` row beside it is what says which one happened.
def sh(nm: String, m: Maybe<&1, H.I64>) -> String:
  match m:
    case Some{v}: String.concat([nm, "_val=", H.i64_text(v)])
    case _: String.concat([nm, "_val=none"])

def shf(nm: String, m: Maybe<&1, F32>) -> String:
  match m:
    case Some{v}: String.concat([nm, "_val=", H.f32_show(v)])
    case _: String.concat([nm, "_val=none"])

def bl(v: Bool) -> String: Bool.pick(String, v, "1", "0")

# `dt_ok` is the FIRST of `_eval`'s two checks, published as its own row rather than folded into
# the value, because it is the half that decides which refusal happened.
def dti(nm: String, d: S.Dt) -> String: String.concat([nm, "_dt=", bl(D.dt_is_int(d))])
def dtf(nm: String, d: S.Dt) -> String: String.concat([nm, "_dt=", bl(D.dt_is_float(d))])
def dtb(nm: String, d: S.Dt) -> String: String.concat([nm, "_dt=", bl(D.dt_is_bool(d))])

# TWO KINDS OF FIXTURE, AND THE DIFFERENCE IS THE POINT.
#
# A CONST DERIVES ITS DTYPE FROM ITS ARG (`ops.py:637`), so a bare `CInt` is WEAKINT and a bare
# `CFloat` is WEAKFLOAT -- and a bare CONST is also the only node whose value the port can read
# without `simplify`. That gives the success rows.
#
# A PARAM CARRIES AN EXPLICIT DTYPE AND EXPLICIT BOUNDS, which is what the refusal rows need: a
# node whose dtype is outside the caller's set AND whose bounds are a single number, so the ONLY
# thing that can refuse it is the dtype check. `PyRange{5, 5}` rather than a bare int CONST for
# that reason, and it is also why these rows exist at all -- three helpers each hard-coding their
# arg would have produced three more weakint rows wearing int32 names, and the dtype refusals
# would have been rows where nothing was refused.
def int_at(nm: String, k: H.I64, dt: S.Dt) -> IO(Unit):
  +ar = O.Arena.empty()
  +f = O.UOp.cconst(ar, O.CInt{k}, dt)
  +med = F.min_maxed(O.Found.ar(f))
  pr(sh(nm, W.wk_eval_int(F.folded(F.MMed.ar(med)), F.MMed.bt(med), O.Found.i(f))))

def flt_at(nm: String, k: F32) -> IO(Unit):
  +ar = O.Arena.empty()
  +f = O.UOp.const(ar, O.CFloat{k})
  +med = F.min_maxed(O.Found.ar(f))
  pr(shf(nm, W.wk_eval_float(F.folded(F.MMed.ar(med)), F.MMed.bt(med), O.Found.i(f))))

def bool_at(nm: String, b: Bool) -> IO(Unit):
  +ar = O.Arena.empty()
  +f = O.UOp.const(ar, O.CBool{b})
  +med = F.min_maxed(O.Found.ar(f))
  pr(sh(nm, W.wk_eval_bool(F.folded(F.MMed.ar(med)), F.MMed.bt(med), O.Found.i(f))))

# A PARAM with `lo == hi` is a single number wearing an explicit dtype, which is the shape the
# dtype refusal needs; `lo != hi` is the same shape that makes the RANGE refusal instead. THREE
# helpers rather than one with a flag, because the flag would be a Bool nobody could read off the
# fixture -- and because each reader is the dunder under test, so sharing one helper across the
# three would have quietly measured `__int__` three times.
def p_int(nm: String, lo: H.I64, hi: H.I64, dt: S.Dt) -> IO(Unit):
  +ar = O.Arena.empty()
  +f = O.UOp.new(ar, O.OpsPARAM{}, Nil{},
                 O.AParam{F.mw_pa(dt, Some{O.PyRange{lo, hi}})}, O.TNone{})
  +med = F.min_maxed(O.Found.ar(f))
  pr(sh(nm, W.wk_eval_int(F.folded(F.MMed.ar(med)), F.MMed.bt(med), O.Found.i(f))))

def p_bool(nm: String, lo: H.I64, hi: H.I64, dt: S.Dt) -> IO(Unit):
  +ar = O.Arena.empty()
  +f = O.UOp.new(ar, O.OpsPARAM{}, Nil{},
                 O.AParam{F.mw_pa(dt, Some{O.PyRange{lo, hi}})}, O.TNone{})
  +med = F.min_maxed(O.Found.ar(f))
  pr(sh(nm, W.wk_eval_bool(F.folded(F.MMed.ar(med)), F.MMed.bt(med), O.Found.i(f))))

def p_flt(nm: String, lo: H.I64, hi: H.I64, dt: S.Dt) -> IO(Unit):
  +ar = O.Arena.empty()
  +f = O.UOp.new(ar, O.OpsPARAM{}, Nil{},
                 O.AParam{F.mw_pa(dt, Some{O.PyRange{lo, hi}})}, O.TNone{})
  +med = F.min_maxed(O.Found.ar(f))
  pr(shf(nm, W.wk_eval_float(F.folded(F.MMed.ar(med)), F.MMed.bt(med), O.Found.i(f))))

# `param_noshape` -- ops.py:1229 -- TWO rows per fixture, and the pair is what matters: a STRONG
# dtype must build a PARAM and a WEAK one must refuse, so a reader that answered `Some` for both (or
# `None` for both) is caught by the disagreement. The `_dt` row names the dtype the node ended up
# carrying, because "a PARAM exists" and "a PARAM of the dtype I asked for" are two claims.
#
# A `+` binding is DEF-BODY form and a `do` block takes `: Type <-`, so the fixture is built by a
# def and only the two prints live in the block. `Maybe<Found>` cannot be a local either -- a match
# may not scrutinise a local -- so the def answers the Maybe and the block matches it.
def param_of(dt: S.Dt) -> Maybe<&1, O.Found>:
  +ar = O.Arena.empty()
  W.wk_param_noshape(ar, 0, dt, None{})

# THE MATCHER IN ITS OWN DEF, taking the `Maybe` whole -- `wk-cd.bend`'s `show`, and the reason
# the shape is two defs here too: a `match` heads a DEF BODY and a local may not be scrutinised.
# `Found` is DESTRUCTURED rather than read through `Found.ar`/`Found.i` twice, because a `case`
# binder is consumed once and the record already carries both halves.
def pm_built(nm: String, m: Maybe<&1, O.Found>) -> String:
  match m:
    case Some{O.Found{a, i}}: String.concat([nm, "_built=",
      Bool.show(O.eq_op(O.Arena.op(a, i), O.OpsPARAM{}))])
    case _: String.concat([nm, "_built=none"])

# THE SECOND ROW IS NOT THE DTYPE, and it was until `sg.ctor` answered `other`: `AParam` has no arm
# in `sg.ctor`'s match, so that row would have said the same thing for every dtype and looked like a
# claim. THIS one asks a DIFFERENT question -- CPython RAISES before building, so a refused dtype must
# leave the arena UNCHANGED. A reader that allocated the node and then refused would pass `_built=none`
# and fail here, which is the difference between "refused" and "refused after doing the work".
def param_of_on(+ar: O.Arena, +dt: S.Dt) -> O.Found:
  Bool.pick(O.Found, Bool.not(D.md_weak(dt)),
            O.UOp.new(ar, O.OpsPARAM{}, Nil{},
                      O.AParam{O.ParamArg{0, dt, None{}, None{}, None{}, None{}, S.AGlobal{}, None{},
                                         False{}, None{}, None{}, False{}, None{}}}, O.TNone{}),
            O.Found{ar, 0})

def pm_alloc(nm: String, dt: S.Dt) -> U32:
  +ar = O.Arena.empty()
  +before = O.Arena.next(ar)
  +made = param_of_on(ar, dt)
  U32.sub(O.Arena.next(O.Found.ar(made)), before)

def pm(+nm: String, +dt: S.Dt) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- pr(pm_built(nm, param_of(dt)))
    pr(String.concat([nm, "_alloc=", U32.show(pm_alloc(nm, dt))]))

def rows() -> IO(Unit):

  do IO<Unit>:
    a : Unit <- int_at("int_weakint", H.i64_of_i32(7), S.weakint())
    b : Unit <- flt_at("float_weakfloat", 0.5)
    c : Unit <- bool_at("bool_true", True{})
    d : Unit <- bool_at("bool_false", False{})
    e : Unit <- p_int("int_i32", H.i64_of_i32(5), H.i64_of_i32(5), S.int32())
    # THE REFUSALS. Two are the DTYPE set and one is the RANGE, and all three print `_val=none`,
    # so the `_dt` row beside each is what tells them apart -- without it a reader that refused
    # for the wrong reason would be indistinguishable from one that refused for the right one.
    # These five rows are the whole point of the five above them.
    f : Unit <- p_int("int_on_range", H.i64_of_i32(1), H.i64_of_i32(5), S.int32())
    g : Unit <- p_bool("bool_on_i32", H.i64_of_i32(0), H.i64_of_i32(0), S.int32())
    h : Unit <- p_flt("float_on_i32", H.i64_of_i32(3), H.i64_of_i32(3), S.int32())
    k : Unit <- pr(dti("int_weakint", S.weakint()))
    l : Unit <- pr(dtf("float_weakfloat", S.weakfloat()))
    m : Unit <- pr(dtb("bool_true", S.boolean()))
    n : Unit <- pr(dti("int_i32", S.int32()))
    o : Unit <- pr(dti("int_on_range", S.int32()))
    q : Unit <- pr(dtb("bool_on_i32", S.int32()))
    r : Unit <- pr(dtf("float_on_i32", S.int32()))
    # `param_noshape`: a strong dtype builds, a weak one refuses. The refusal is CPython's
    # `raise RuntimeError(f"cannot create param for weak dtype {dtype}")`, which the port answers
    # with `None{}` -- and `None` is what `case _:` prints, so the two are the same row shape.
    w : Unit <- pm("param_i32", S.int32())
    x : Unit <- pm("param_weakint", S.weakint())
    y : Unit <- pm("param_weakfloat", S.weakfloat())
    pr(dtb("bool_false", S.boolean()))

def main() -> IO(Unit): rows()
