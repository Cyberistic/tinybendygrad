# opseven.bend -- the SEVEN `Ops` `runs/graphcmp/D/D1-graph-*.txt` never reaches.
#
#   .venv/bin/python gates/opseven-gate.py
#
# WHY A DRIVER THAT CONSTRUCTS, AND NOT A CENSUS THAT WAITS. The corpus reaches 70 of the 77
# members of `uop/ops.bend`'s `type Op is Data:` block, on all 34 graphs, with `py == bend`
# on every one. The seven it never reaches are therefore not OBSERVED, so NOTHING in this tree
# can say whether the port's answers for them are right -- which is the same position
# `gates/ops_bend_exec-e2e.py` and `gates/tnvalue-census.py`'s V-LADDER take when a shape has to
# be compared: BUILD IT. Every row below is a node this file MINTS, and every one of them has a
# CPython counterpart built from the SAME upstream construction site, named per row below. That
# makes the port's answer comparable to CPython's for the FIRST time on these seven ops.
#
# CAN CPYTHON EMIT EACH OF THE SEVEN? Yes, all seven, and six of them by ONE `UOp(...)`
# constructor call -- so the honest fixture is a direct construction, NOT a forced failure. The
# per-op construction site, MEASURED by reading the row out of upstream (`git show
# upstream:tinygrad/...`, 75 members: upstream DELETED `GROUP` and `FLIP`):
#
#   REWRITE_ERROR  ops.py:1713  UOp(Ops.REWRITE_ERROR, src=uop.src, arg=err_str)      (a str arg)
#   PYLITERAL      upat.py:26    UOp(Ops.PYLITERAL, arg=self.op[0])                     (a bare Ops)
#   PYLITERAL      upat.py:29    the SAME op also carries a non-int arg, hence `pyliteral_str`
#   SOURCE         codegen/__init__.py:453  UOp(Ops.SOURCE, arg=src)                    (a str arg)
#   CUSTOM         upat.py:26    UOp(Ops.CUSTOM, src=(base, ...), arg=("{0}.op is {1}", dtypes.void))
#   CUSTOM         llm/kernels/amd.py:45     the non-void arm, the dtype is in the arg
#   CUSTOMI        upat.py:66    UOp(Ops.CUSTOMI, arg=("True", dtypes.void))
#   CUSTOMI        llm/kernels/amd.py:113    two shaped srcs, non-void
#   INS            ops.py:600     def ins(self, arg, **kwargs): return UOp(Ops.INS, ...)
#   PROGRAM        codegen/__init__.py:500   UOp(Ops.PROGRAM, src=(full_sink,), arg=prog_info)
#
# TWO OF THE SEVEN ARE ONLY LEGAL IN ONE OF THE FIVE SPEC TABLES, and the rows say so:
# `rewrite_error` is `sf=1` and `9` everywhere else, because its ONLY rule is spec.py:239 in
# `spec_full`, the matcher whose own comment reads "these ops can exist in programs but not the
# tensor spec / everything should be deleted from here". A fixture that forced a REWRITE_ERROR
# into a program graph would force an ILLEGAL state -- which is the D8 shape `AGENTS.md` names
# as the wrong one -- so no row does. `source` and `program_*` are `st=1 sp=9`: their rules are
# spec.py:194-198, which live in `spec_tensor`, NOT in `spec_program`, and that is upstream's
# own placement.
#
# `sp=0` ON THREE ROWS IS A REAL ANSWER, NOT A FIXTURE ACCIDENT, and it is worth naming because it
# looks like one: `custom_void`, `custom_f32` and `customi_f32` carry a CONST src, and
# spec.py:204's FIRST `spec_program` rule returns False for "a CONST under anything but a CAST".
# So those three nodes are genuinely not program-legal, for a reason that has nothing to do with
# CUSTOM. `customi_void` has NO srcs and so passes -- which is the discrimination: the three
# rows that fail and the one that passes differ in exactly the CONST src. SO ALL TWELVE `sp_*`
# ROWS AGREE NOW, on the SAME reason where they agree: before the fix in `spec.bend` the port
# rejected all twelve for the wrong reason (non-CAST) and these three for the right one, so the
# 3 of 12 that agreed agreed BY COINCIDENCE and `3 of 12` was not a pass rate.
#
# WHAT IS PRINTED, AND WHY NOTHING HERE REIMPLEMENTS A PROPERTY. `dtype` is `F.UOp.dtype` read
# off the finished fold (the port's only well-founded spelling -- Bend refuses the mutual
# recursion `UOp.dtype`'s `recursive_property` breaks in Python) and `shape` is `F.UOp.shape`. The
# spec columns are `Sp.{tensor,full,hcq,kernel_graph}_rewrite` INLINE and `Sp.pr_rewrite` on a
# SECOND row of its own, each through `Sp.show_v`: 1 for VTrue, 0 for VFalse, 9 for VSkip.
# CPython's oracle prints 1 for "a rule fired AND its lambda returned True" -- `bool(m.rewrite(u))`
# and NOT `is not None`, because `rewrite` returns the lambda's answer, so `is not None` would
# score a REJECTED rule as a pass, and this lane's whole job is to say which rules REJECT.
#
# WHY `spec_program` GETS A ROW TO ITSELF. It is the ONE column that did not agree, on any of the
# twelve rows, and keeping it inline would have turned twelve real matches into twelve divergences
# with no way for a reader to tell which half of a row was sound. The split is the finding made
# readable: `tinybendygrad/uop/spec.bend`'s `pr_0` read
# `Bool.not(sp_op(fx, self, O.OpsCAST{}))` where spec.py:204 reads
# `x.op is not Ops.CAST and any(s.op is Ops.CONST for s in x.src)` -- the second conjunct DROPPED, the
# claim's `-GroupOp.Defines` DROPPED, and the file's OWN HEADER quoted the rule three lines above the
# def that dropped it -- so the port's `spec_program` answered VFalse for every node that is not a CAST.
# MEASURED while it was live: the port's column was the CONSTANT `0` on 12 of 12 while CPython's took
# three values (5 at '1', 4 at '9', 3 at '0'). FIXED in `spec.bend`: `pr_0.claims` now reads
# `GroupOp.defines` (already ported at `ops.bend:495`, uncalled until now) and `pr_0.body` now reads
# `any_const` (already ported at `spec.bend:526`, likewise uncalled), and this column agrees with
# CPython's on 12 of 12 -- so the twelve rows that used to be pinned divergences are COMPARED rows and
# the ordinary diff guards them. `gates/opseven-gate.py` keeps `spec_program_holds` as a regression
# guard in its falsifiable form, "the column is not constant", because a check that names nothing goes
# green by accident.
#
# `Ops.value` IS A SEPARATE ROW SET, and it is the only thing in this file that is PORT-DEPENDENT
# BY CONSTRUCTION: `UOp.tuplize` puts `op.value` first in the sort key, and `FastEnum`'s
# `_generate_next_value_` is 1 + max, so the number IS the declaration order. MEASURED on this
# tree by `gates/opseven-gate.py --plant`'s siblings and by its own live run: the `Ops.value` table,
# `Ops.name.of`, `all_ops` and the `type Op is Data:` block all carry the SAME count and every arm
# sits at its own declaration position -- so the table is not transcribed wrong, it is a faithful
# reading of this port's own enum, and it is the SAME count as upstream's. `GROUP` (once position 14)
# and `FLIP` (once position 73) were the whole of the disagreement until `69bfc2ee9` re-indexed them
# OUT of this file too, so all seven rows now AGREE and none of them is pinned. The count is not
# written here on purpose: a header that carries a count stops carrying it the day the enum moves, and
# `ops_value_is_declaration_order` prints the live one on every run.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/spec.bend as Sp

# ===========================================================================
# THE PRINTERS. `ABSENT` is this port's own word for "the fold produced no `Derived` for the
# node" and is DIFFERENT from `none`, which is Python's `_shape is None`. The differ spells the
# first `?` and the second `R`; conflating them is the `?`/`R` bug `fold.bend`'s `custom_ds`
# header records, so this file keeps them apart.
# ===========================================================================

def dtv(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: F.dt_nm(d)
    case None{}: "ABSENT"

def shape_inner(+ar: O.Arena, g: Maybe<&2, List<&2, O.Sint>>) -> String:
  match g:
    case None{}: "none"
    case Some{ds}: F.dims_str(ar, ds)

def shapev(+ar: O.Arena, m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case None{}: "ABSENT"
    case Some{g}: shape_inner(ar, g)

def vd(+n: U32) -> String:
  Bool.pick(String, U32.is_eq(n, 1), "1", Bool.pick(String, U32.is_zero(n), "0", "9"))

def nsrc_s(ar: O.Arena, i: U32) -> String:
  U32.show(O.Arena.nsrc(ar, i))

# TWO ROWS PER FIXTURE, AND THE SPLIT IS THE POINT. ONE row carries the four facts both lanes
# agree on -- the op, the src count, the dtype and the shape, plus the FOUR of the FIVE spec
# columns that agree (`st` `sf` `sh` `sk`) -- and the SECOND row carries the one that does not,
# `sp` (`spec_program`), on its own. Keeping `sp` inline would have turned twelve real matches
# into twelve divergences and left a reader unable to tell which half of the row is sound.
#
# `+` on the locals pays for reading `ar` more than once; a `Data` record is not implicitly
# copyable and Bend rejects a second read of an unannotated one. TWO prints need the `do` block
# (Bend has no bare statement sequence inside an effectful def), which is why `main` below binds
# one row per fixture rather than two.
def row(+nm: String, +f: O.Found) -> IO(Unit):
  +fx = F.folded(O.Found.ar(f))
  +ar = F.Folded.ar(fx)
  +tb = F.Folded.t(fx)
  +i = O.Found.i(f)
  +pr = Sp.pr_rewrite(Sp.program_table(), fx, i)
  do IO<Unit>:
    a : Unit <- IO.print(String.concat([nm, "=op=", O.Ops.name(O.Arena.op(ar, i)), " nsrc=", nsrc_s(ar, i),
      " dtype=", dtv(F.UOp.dtype(ar, tb, i)),
      " shape=", shapev(ar, F.UOp.shape(ar, tb, i)),
      " st=", vd(Sp.show_v(Sp.tensor_rewrite(fx, i))),
      " sf=", vd(Sp.show_v(Sp.fu_rewrite(Sp.full_table(), fx, i))),
      " sh=", vd(Sp.show_v(Sp.hq_rewrite(Sp.hcq_table(), fx, i))),
      " sk=", vd(Sp.show_v(Sp.kg_rewrite(Sp.kernel_graph_table(), fx, i)))]))
    b : Unit <- IO.print(String.concat(["sp_", nm, "=", vd(Sp.show_v(pr))]))
    return Unit{}

# ===========================================================================
# THE FIXTURE. `cst_f32` is upstream's `UOp.const(1.0)` and `sink_of` is upstream's
# `UOp(Ops.SINK, src=(C_F32,), arg=KernelInfo())`. The port's `SINK` arg is `ANone{}` rather than
# a `KernelInfo` because the port's `Arg` has no `KernelInfo` spell for a SINK; no spec rule for
# any row below reads the SINK's arg, and the SINK is not itself a row, so the difference is
# outside the comparison and is recorded here rather than measured into a row that cannot fail.
# ONE ARENA PER FIXTURE, so no row can read a sibling's node: the house idiom, and the reason
# `gates/fold_graph_census.bend` builds each of its 28 fixtures the same way.
# ===========================================================================

def cst_f32(ar: O.Arena) -> O.Found: O.UOp.const(ar, O.CFloat{1.0})

def ink0(ar: O.Arena, op: O.Op, s: String, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, op, Nil{}, O.AInk{s, dt}, O.TNone{})

# --- REWRITE_ERROR: ops.py:1713 ---
def f_rewrite_error() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsREWRITE_ERROR{}, Nil{}, O.AStr{"boom"}, O.TNone{})

# --- PYLITERAL: upat.py:26 (a bare Ops) and upat.py:29 (a non-int arg) ---
def f_pyliteral_op() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsPYLITERAL{}, Nil{}, O.AOpLit{O.OpsADD{}}, O.TNone{})

def f_pyliteral_str() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsPYLITERAL{}, Nil{}, O.AStr{"hello"}, O.TNone{})

# --- SOURCE: codegen/__init__.py:453 ---
def f_source() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsSOURCE{}, Nil{}, O.AStr{"int main(){}"}, O.TNone{})

# --- CUSTOM: upat.py:26 (void) and llm/kernels/amd.py:45 (dtype in the arg) ---
def f_custom_void() -> O.Found:
  +c = cst_f32(O.Arena.empty())
  O.UOp.new(O.Found.ar(c), O.OpsCUSTOM{}, [O.Found.i(c)], O.AInk{"{0}.op is {1}", S.void()}, O.TNone{})

def f_custom_f32() -> O.Found:
  +c = cst_f32(O.Arena.empty())
  O.UOp.new(O.Found.ar(c), O.OpsCUSTOM{}, [O.Found.i(c)], O.AInk{"sqrt({0})", S.single()}, O.TNone{})

# --- CUSTOMI: upat.py:66 (no srcs) and llm/kernels/amd.py:113 (two shaped srcs) ---
def f_customi_void() -> O.Found:
  ink0(O.Arena.empty(), O.OpsCUSTOMI{}, "x", S.void())

def f_customi_f32() -> O.Found:
  +c = cst_f32(O.Arena.empty())
  O.UOp.new(O.Found.ar(c), O.OpsCUSTOMI{}, [O.Found.i(c), O.Found.i(c)], O.AInk{"{0}+{1}", S.single()}, O.TNone{})

# --- INS: ops.py:600 `UOp.ins`, which defaults src to `self.src` and the dtype to `self.dtype`.
#     Both rows pass NO src and so answer nsrc=0; that is upstream's own default (an empty
#     `self.src` on a CONST), not a fixture shortcut. ---
def f_ins_void() -> O.Found:
  ink0(O.Arena.empty(), O.OpsINS{}, "NOP", S.void())

def f_ins_f32() -> O.Found:
  ink0(O.Arena.empty(), O.OpsINS{}, "VADDPS", S.single())

# --- PROGRAM: codegen/__init__.py:500, the two of the four progressive shapes spec.py:195-198
#     that discriminate (`src=(SINK,)` and the full four), plus the `arg=ProgramInfo` case ---
def f_program_1() -> O.Found:
  +c = cst_f32(O.Arena.empty())
  +sk = O.UOp.new(O.Found.ar(c), O.OpsSINK{}, [O.Found.i(c)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(sk), O.OpsPROGRAM{}, [O.Found.i(sk)], O.AProgram{O.ProgramInfo.of()}, O.TNone{})

def f_program_4() -> O.Found:
  +c = cst_f32(O.Arena.empty())
  +sk = O.UOp.new(O.Found.ar(c), O.OpsSINK{}, [O.Found.i(c)], O.ANone{}, O.TNone{})
  +ln = O.UOp.new(O.Found.ar(sk), O.OpsLINEAR{}, Nil{}, O.ANone{}, O.TNone{})
  +sr = O.UOp.new(O.Found.ar(ln), O.OpsSOURCE{}, Nil{}, O.AStr{"int main(){}"}, O.TNone{})
  +bn = O.UOp.new(O.Found.ar(sr), O.OpsBINARY{}, Nil{}, O.ABlob{[1, 2, 3, 4]}, O.TNone{})
  O.UOp.new(O.Found.ar(bn), O.OpsPROGRAM{}, [O.Found.i(sk), O.Found.i(ln), O.Found.i(sr), O.Found.i(bn)],
    O.AProgram{O.ProgramInfo.of()}, O.TNone{})

def vrow2(nm: String, op: O.Op) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(O.Ops.value(op))]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("rewrite_error", f_rewrite_error())
    b : Unit <- row("pyliteral_op", f_pyliteral_op())
    c : Unit <- row("pyliteral_str", f_pyliteral_str())
    d : Unit <- row("source", f_source())
    e : Unit <- row("custom_void", f_custom_void())
    f : Unit <- row("custom_f32", f_custom_f32())
    g : Unit <- row("customi_void", f_customi_void())
    h : Unit <- row("customi_f32", f_customi_f32())
    i : Unit <- row("ins_void", f_ins_void())
    j : Unit <- row("ins_f32", f_ins_f32())
    k : Unit <- row("program_1", f_program_1())
    l : Unit <- row("program_4", f_program_4())
    m : Unit <- vrow2("value_rewrite_error", O.OpsREWRITE_ERROR{})
    n : Unit <- vrow2("value_source", O.OpsSOURCE{})
    o : Unit <- vrow2("value_program", O.OpsPROGRAM{})
    p : Unit <- vrow2("value_custom", O.OpsCUSTOM{})
    q : Unit <- vrow2("value_customi", O.OpsCUSTOMI{})
    r : Unit <- vrow2("value_ins", O.OpsINS{})
    s : Unit <- vrow2("value_pyliteral", O.OpsPYLITERAL{})
    return Unit{}
