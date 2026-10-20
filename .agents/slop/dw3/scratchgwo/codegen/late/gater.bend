# codegen/late/gater.bend -- port of tinygrad/codegen/late/gater.py
#
# ONE OF THREE SLICES. `codegen/late.bend` held `linearizer.py`, `regalloc.py` and
# `gater.py` together and the 1:1 ruling gives each upstream .py its own file at its
# own path. The other two are `linearizer.bend` and `regalloc.bend` beside this one,
# the rows are the rows, and the DEF-BY-DEF MAP for all three is
# `linearizer.bend`'s head.
#
# W4 APPLIES HERE AND IS NOT RESTATED: `gater.py:6-7` compares
# `a.src[0].dtype == l.dtype` and `gater.py:25-28` annotates `dtype=dtypes.bool`, and
# a dtype cannot be CARRIED in bend 2.0.34. Every rule below takes its dtype predicate
# as a `Bool` PARAMETER, the shape `linearizer.bend`'s W4 paragraph prescribes.
#
# ===========================================================================
# `gater.py` -- 1-29, WHOLE FILE. TWO TABLES: a six-rule `pm_move_gates_from_index`
# and the `move_where_load` function those last two rules name.
#
# THE TABLE'S OP SETS ARE THE PORTED HALF and the REST of each rule is a WALL. All
# six rules are `UPat.var(...).index(...).load(...)`, `.store(...)`,
# `UPat((INDEX, SHRINK), ...).load/.store(...)` and `UPat.var("gate").where(...)`,
# and what a rule MATCHES is its nested structure: the `index`, the `where`, the
# `Invalid` arg, the `dtype=bool` annotation and the `~` on the gate. None of those
# is a `UPat` OP, so there is no op set to print and the rules are gated by their
# top-level op plus their COUNT -- which is what `gt_tbl_len` and `gt_ops<i>` are,
# and the mutation table reports the arms those rows cannot move.
# ===========================================================================
import Base
import ./../../LAWS/spec.bend as S
import ./../../uop/ops.bend as O
import ./../kernel.bend as KER
import ./linearizer.bend as LT

# ===========================================================================
# `gater.py` -- 1-29, WHOLE FILE. TWO TABLES: a six-rule `pm_move_gates_from_index`
# and the `move_where_load` function those last two rules name.
#
# THE TABLE'S OP SETS ARE THE PORTED HALF and the REST of each rule is a WALL. All
# six rules are `UPat.var(...).index(...).load(...)`, `.store(...)`,
# `UPat((INDEX, SHRINK), ...).load/.store(...)` and `UPat.var("gate").where(...)`,
# and what a rule MATCHES is its nested structure: the `index`, the `where`, the
# `Invalid` arg, the `dtype=bool` annotation and the `~` on the gate. None of those
# is a `UPat` OP, so there is no op set to print and the rules are gated by their
# top-level op plus their COUNT -- which is what `gt_tbl_len` and `gt_ops<i>` are,
# and the mutation table reports the arms those rows cannot move.
# ===========================================================================
def gt_tbl() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsLOAD{}], Nil{}},    # 0  buf.index(where, where).load(l)
   O.PMEntry{1, [O.OpsSTORE{}], Nil{}},   # 1  buf.index(where, where).store(d)
   O.PMEntry{2, [O.OpsLOAD{}], Nil{}},    # 2  (INDEX|SHRINK).load(l)
   O.PMEntry{3, [O.OpsSTORE{}], Nil{}},   # 3  (INDEX|SHRINK).store(d)
   O.PMEntry{4, [O.OpsWHERE{}], Nil{}},   # 4  gate.where(load.gate, a)
   O.PMEntry{5, [O.OpsWHERE{}], Nil{}}]   # 5  gate.where(a, load.~gate)

# `gt_ops<i>` IS THE TABLE ROW. `pat.op` is a single op for all six rules -- the
# two-armed `(INDEX, SHRINK)` tuple and the `| PSEUDO_OPS` union of
# `pm_regalloc_rewrite` are the two multi-op patterns in these three files, and
# neither is in this table.
def gt_ops(+i: U32) -> String:
  LT.lt_ops_name(O.PMEntry.ops(LT.cfg_entry(gt_tbl(), U32.to_nat(i))))

# `move_where_load` -- gater.py:5-7, PORTED AS A FOUR-LINK TERNARY CHAIN plus the
# trailing `.cast(w.dtype)`:
#
#     l.replace(src=(l.src[0],
#                   l.vconst_like(0)   if a.is_invalid else
#                   l.const_like(a.val) if a.op is Ops.CONST else
#                   a.src[0]            if a.op is Ops.CAST and a.src[0].dtype == l.dtype else
#                   a.cast(l.dtype),
#                   l.src[2])).cast(w.dtype)
#
# W4: THE DTYPE IS A `Maybe`. `a.src[0].dtype == l.dtype` (:7) is a comparison of
# two `Maybe<&2, S.Dt>` and `a.cast(l.dtype)` / `.cast(w.dtype)` need the dtype as
# a VALUE; `fold.dt` answers a `Maybe`, and bend 2.0.34 mis-parses `Maybe<&2,
# S.Dt>` in a def signature at this position (kernel.bend's header, and the note
# appended to bend2-constraints.md). So `same` is the FIXTURE's answer to the one
# predicate the dtype decides, and the port's answer to a cast is a CAST DEPTH --
# which is the whole of what the four rows print.
#
# `Ga` is `a` plus that one predicate: `inv` is `a.is_invalid`, `cn` is `a.op is
# CONST`, `ld` is how many CASTs the port BUILT over `a`'s leaf, `lf` is the leaf
# CONST's value and `same` is the dtype identity.
type Ga is Data:
  Ga{inv: Bool, cn: Bool, ld: U32, lf: String, same: Bool}

def Ga.inv(+a: Ga) -> Bool:
  match a:
    case Ga{inv, cn, ld, lf, same}: inv

def Ga.cn(+a: Ga) -> Bool:
  match a:
    case Ga{inv, cn, ld, lf, same}: cn

def Ga.ld(+a: Ga) -> U32:
  match a:
    case Ga{inv, cn, ld, lf, same}: ld

def Ga.lf(+a: Ga) -> String:
  match a:
    case Ga{inv, cn, ld, lf, same}: lf

def Ga.same(+a: Ga) -> Bool:
  match a:
    case Ga{inv, cn, ld, lf, same}: same

# THE ANSWER: the CAST DEPTH of the alt value and its leaf. `alt` is ALWAYS a CAST
# because of the trailing `.cast(w.dtype)`, which is why all four rows print
# `alt=CAST` and only `d` moves.
type Gt is Data:
  Gt{d: U32, lf: String}

def Gt.d(+t: Gt) -> U32:
  match t:
    case Gt{d, lf}: d

def Gt.lf(+t: Gt) -> String:
  match t:
    case Gt{d, lf}: lf

# LINK 1 -- `l.vconst_like(0)`. Its leaf is the ZERO of `l.dtype` and there is no
# node to read it from, so the arm OWNS the literal: that is what the Python does,
# and `gt_mwl_invalid`'s `leaf=0.0` is the arm's own value rather than `a`'s.
def gt_w0() -> Gt:
  Gt{0, "0.0"}

# LINK 2 -- `l.const_like(a.val)`.
def gt_w1(+a: Ga) -> Gt:
  Gt{0, Ga.lf(a)}

# LINK 3 -- `a.src[0]`, i.e. the CAST is DROPPED because the inner dtype already
# matches. Same depth and leaf as link 2, which is the two links looking alike and
# a `List.sort`-free reader mistaking for one link.
def gt_w2(+a: Ga) -> Gt:
  Gt{0, Ga.lf(a)}

# LINK 4 -- `a.cast(l.dtype)`, which BUILDS one more CAST over `a`'s own run.
def gt_w3(+a: Ga) -> Gt:
  Gt{U32.add(Ga.ld(a), 1), Ga.lf(a)}

# THE CHAIN, in Python's order, and the order is load-bearing only because
# `Bool.pick` is strict: every predicate runs on every arm and the RESULT is the
# first arm that fires. `gt_mwl_*` is one row per arm, so a dropped arm moves
# exactly the row that names it.
def move_where_load.w3(+a: Ga) -> Gt:
  Bool.pick(Gt, Bool.and(Bool.not(Ga.cn(a)), Ga.same(a)), gt_w2(a), gt_w3(a))

def move_where_load.w2(+a: Ga) -> Gt:
  Bool.pick(Gt, Ga.cn(a), gt_w1(a), move_where_load.w3(a))

def move_where_load.w1(+a: Ga) -> Gt:
  Bool.pick(Gt, Ga.inv(a), gt_w0(), move_where_load.w2(a))

def move_where_load(+a: Ga) -> Gt:
  move_where_load.w1(a)

# `.cast(w.dtype)` -- the trailing link, ONE for every arm, and the reason `d` is
# never 0.
def gt_mwl.put(+t: Gt) -> Gt:
  Gt{U32.add(Gt.d(t), 1), Gt.lf(t)}

def gt_mwl(+a: Ga) -> Gt:
  gt_mwl.put(move_where_load(a))

# `n` is `len(l.src)` and `len(r.src)`: the replacement is
# `(l.src[0], alt, l.src[2])` -- a PERMUTATION of `l`'s three srcs, not a new arity.
# `nm` is the row class the PORT needs (one per link, so a dropped link moves
# exactly one row) and the CALLER supplies it to `srow`, so the value here starts
# at the `=` and the name is written once.
def gt_row(+a: Ga, n: U32) -> String:
  String.concat(["LOAD alt=CAST d=", U32.show(Gt.d(gt_mwl(a))),
                 " leaf=", Gt.lf(gt_mwl(a)), " nsrc=", U32.show(n)])

# THE FOUR `a`s, one per link. `inv` and `same` are the fixture's answers to the
# two predicates the dtype and `Invalid` decide; `cn` and `ld` are `a`'s own shape
# and are PORTED reads.
#   invalid : a is CONST(Invalid)      -> link 1, leaf 0.0, no CAST
# `a0`'s OWN leaf is 9.0 and NOT 0.0 on purpose. `a.is_invalid` is a CONST whose
# `arg` is `Invalid`, and if the fixture spelled that leaf "0.0" then link 1's answer
# (`l.vconst_like(0)`, the zero of l's dtype) and link 2's answer (`l.const_like(a.val)`)
# would be the SAME ROW, and the mutation table's "drop link 1" would move nothing.
# 9.0 is what CPython would `str` for the const if it ever reached link 2.
#   const   : a is CONST(2.0)          -> link 2, leaf 2.0, no CAST
#   cast_same  : CAST(5.0) at l.dtype  -> link 3, leaf 5.0, no CAST
#   cast_diff  : CAST(7) at i32 != f32 -> link 4, leaf 7, one CAST over a's own
def gt_a0() -> Ga:
  Ga{True{}, True{}, 0, "9.0", True{}}

def gt_a1() -> Ga:
  Ga{False{}, True{}, 0, "2.0", True{}}

def gt_a2() -> Ga:
  Ga{False{}, False{}, 1, "5.0", True{}}

def gt_a3() -> Ga:
  Ga{False{}, False{}, 1, "7", False{}}

def main() -> IO(Unit):
  do IO<Unit>:
    t1 : Unit <- LT.row("gt_tbl_len", KER.n_of(gt_tbl()))
    t2 : Unit <- LT.srow("gt_ops0", gt_ops(0))
    t3 : Unit <- LT.srow("gt_ops1", gt_ops(1))
    t4 : Unit <- LT.srow("gt_ops2", gt_ops(2))
    t5 : Unit <- LT.srow("gt_ops3", gt_ops(3))
    t6 : Unit <- LT.srow("gt_ops4", gt_ops(4))
    t7 : Unit <- LT.srow("gt_ops5", gt_ops(5))
    t8 : Unit <- LT.srow("gt_mwl_invalid", gt_row(gt_a0(), 3))
    t9 : Unit <- LT.srow("gt_mwl_const", gt_row(gt_a1(), 3))
    ta : Unit <- LT.srow("gt_mwl_cast_same", gt_row(gt_a2(), 3))
    # THE LAST ROW IS UNBOUND and IS the `do IO<Unit>` block's final expression, so
    # there is no trailing `IO.print("")` and the file ends with the LAST ROW's
    # newline -- exactly what the oracle's `print("\n".join(out))` does. A trailing
    # empty line is a one-line diff that a reader has to notice.
    # THE LAST ROW IS UNBOUND and IS the `do IO<Unit>` block's final
    # expression, so there is no trailing `IO.print("")` and the file ends
    # with the LAST ROW's newline -- what the oracle's `print("\n".join(out))`
    # does. A trailing empty line is a one-line diff a reader must notice.
    LT.srow("gt_mwl_cast_diff", gt_row(gt_a3(), 3))
