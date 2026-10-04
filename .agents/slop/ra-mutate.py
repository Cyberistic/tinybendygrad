#!/usr/bin/env python3
"""ra-mutate.py -- the mutation table for `codegen/late/regalloc.bend`.

    python3 .agents/slop/ra-mutate.py

⚠ IT NO LONGER WRITES THE LIVE TREE.  It used to: `open(MUTATED,'w').write(...)`
plus a `finally` restore, with the digest sampled ONCE at start.  On a file another
unit is editing that restore reverts their work, and it had no way to know -- the
guard is what establishes that nothing else touched the file, and a guard that runs
once cannot.  `staged_mut.StagedSet` now stages `jj file show -r @` beside each of
the three `late/` files, ASSERTs `sha256(mirror) == sha256(live)`, edits only the
staged copies, unlinks them in a `finally`, and REPORTS whether the live digest
moved during the run.

IT ALSO COULD NOT RUN AT ALL.  The baseline came from a frozen `full.txt` in scratch
that does not exist, so the module raised `FileNotFoundError` at import -- and it had
already `shutil.copy`d the live file over its own snapshot on the way there.  The
baseline is now taken from the staged mirror, per run, and RULE C's control is
asserted before any mutation is measured.

POST-SPLIT.  `codegen/late.bend` was ONE file for linearizer.py + regalloc.py +
gater.py and the 1:1 ruling gave each upstream .py its own file at its own path.  All
three are staged and run, and `q()` applies the `LT.` qualifier the split forced on a
call site AND on a type mention, because a cross-file type name is not in scope
unqualified.  An anchor that names a `def` can MOVE BETWEEN THESE THREE FILES without
changing by one character -- `tb_pset.put` is now in `linearizer.bend` -- so the
anchor is searched across the whole set and the edit lands in the file that holds it.
"""
import os
import pathlib
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_not_apply as PNA
import staged_mut as SM

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
LATE = ROOT / "tinybendygrad" / "codegen" / "late"
FILES = ("linearizer", "regalloc", "gater")
OUT = ROOT / ".agents/slop/ra-mutations.txt"

# The `LT.` qualifier the split forced, as a regex over the names that actually
# cross the boundary.  UNCHANGED from the original: it is a fact about the port's
# names, and inventing a second copy of it is how a reader ends up auditing a
# string the harness never searches for.
import re  # noqa: E402  (after sys.path, so `import patch_not_apply` resolves first)

_qpat = re.compile(r'(?<![\w.])(%s)(?![\w])' % '|'.join(re.escape(n) for n in
    ['RaEn', 'RaEn.k', 'RaEn.v', 'RaTb', 'RaTb.es', 'at', 'b2u', 'cfg_entry',
     'lt_is_exit', 'lt_is_range', 'lt_key', 'lt_lines', 'lt_op_is', 'row', 'tb_get',
     'tb_has', 'tb_ins', 'tb_keys', 'tb_new', 'tb_pget', 'tb_pput', 'tb_pset',
     'tb_put', 'tb_vput', 'tb_vs', 'u32_none']))


def q(s):
    return _qpat.sub(lambda m: 'LT.' + m.group(1), s)


# (name, old, new) -- ONE entry per ported rule.
#
# RE-AIMED 2026-10-04, five entries, and each drift is named in the table below.
# All five were reported STALE by `anchor-audit.py`.  21 of the 36 anchors it
# reported were FALSE -- it searched for the RAW literal, while the harness searches
# for `q(literal)` -- and `mutanchor.anchors()` now executes `q` instead of
# transcribing it.  These five survived that correction, so they really had moved.
#
#   'alloc: free does not have priority'          `ra_key` gained `+` on `r`
#   'prologue: live_in[v] is not written'         the two-write site split into `ra_in`
#   'epilogue: it reloads everything'             the anchor was the MUTANT, not the port
#   'the main loop starts at 1'                   `List.reverse` moved to the call site
#   'rewrite: the tag rewrite is not threaded'   the `List.append` operands were swapped
MUT = [
 ('PSEUDO_OPS: drop BARRIER', 'O.OpsAFTER{}, O.OpsBARRIER{}, O.OpsGROUP{}', 'O.OpsAFTER{}, O.OpsGROUP{}'),
 ('live range: backward walk becomes forward', 'ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s)',
  'ra_lr.go(ops, U32.sub(ra_nm(s), 1), s)'),
 ('live range: dedup(u.src) becomes identity', 'Bool.pick(List<&2, U32>, u32_in(r, s), acc,', 'Bool.pick(List<&2, U32>, False{}, acc,'),
 ('live range: loop-interval append dropped', 'ra_lr.d2.put(t, v, ra_hi(lp, tb_last(t, v)))', 't'),
 ('loops: max user becomes first user', 'ra_lastuse.go(ops, 0, k, 0)', 'ra_lastuse.go(ops, 0, k, 4294967295)'),
 ('loops: the RANGE bound flipped', 'U32.is_lt(lo, RaEn.v(e))', 'U32.is_lt(RaEn.v(e), lo)'),
 ('live[v] = alloc(...) dropped', 'def ra_lv(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  ra_st.lv(s, tb_put(RaSt.lv(s), v, r, Nil{}))',
  'def ra_lv(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  s'),
 ('alloc: first-wins becomes last-wins', 'ra_alloc.keep(Bool.or(RaBd.f(a), U32.is_lt(RaBd.d(a), RaBd.d(ra_key(lv, lr, r, i, nmx)))),',
  'ra_alloc.keep(Bool.or(RaBd.f(a), U32.is_lt(RaBd.d(ra_key(lv, lr, r, i, nmx)), RaBd.d(a))),'),
 ('alloc: the seed no longer yields', 'Bool.or(RaBd.f(a), U32.is_lt', 'Bool.or(False{}, U32.is_lt'),
 # RE-AIMED: `r` became `+r` in the header.  The BODY was already right.
 ('alloc: free does not have priority', 'def ra_key(+lv: RaTb, +lr: RaTb, +r: U32, i: U32, +nmx: U32) -> RaBd:\n  RaBd{ra_dist(tb_vs(lr, ra_linv(RaTb.es(lv), r)), i, nmx), r, ra_linv(RaTb.es(lv), r), False{}}',
  'def ra_key(+lv: RaTb, +lr: RaTb, +r: U32, i: U32, +nmx: U32) -> RaBd:\n  RaBd{0, r, ra_linv(RaTb.es(lv), r), False{}}'),
 ("alloc: the END/BACKEDGE use-skip dropped", 'def ra_uses.ex(ex: Bool, +s: RaSt, +i: U32, ss: List<&2, U32>, +ops: List<&2, RaUop>) -> RaSt:\n  match ex:\n    case True{} : s',
  'def ra_uses.ex(ex: Bool, +s: RaSt, +i: U32, ss: List<&2, U32>, +ops: List<&2, RaUop>) -> RaSt:\n  match ex:\n    case True{} : ra_uses.go(ss, i, s, ops)'),
 ('a non-Register src is no longer skipped', 'ra_use.got(U32.is_ne(v, u32_none()),', 'ra_use.got(True{},'),
 ("live.get is a zero test again (W5b)", 'ra_use.got(U32.is_ne(v, u32_none()), Bool.not(tb_has(RaSt.lv(s), v)), s, i, v)',
  'ra_use.got(U32.is_ne(v, u32_none()), U32.is_ne(tb_get(RaSt.lv(s), v), u32_none()), s, i, v)'),
 ('the i+1 for a non-RANGE def becomes i', 'Bool.pick(U32, lt_is_range(op), i, U32.add(i, 1))', 'Bool.pick(U32, lt_is_range(op), i, i)'),
 ('two-address: the cons reorder dropped', 'Bool.pick(List<&2, U32>, RaSt.ta(s),\n            ra_tw(ra_uses_tw(RaSt.lv(s), RaSt.ops(s), ss), ra_cons(RaSt.un(s), v)),\n            ra_cons(RaSt.un(s), v))',
  'Bool.pick(List<&2, U32>, RaSt.ta(s),\n            ra_cons(RaSt.un(s), v),\n            ra_cons(RaSt.un(s), v))'),
 ('two-address: uses[0] goes last instead of first', 'ra_tw.go(us, t, Bool.pick(List<&2, U32>, u32_in(us, r), pre,\n                                              List.append(&2, U32, pre, [r])))',
  'ra_tw.go(us, t, Bool.pick(List<&2, U32>, u32_in(us, r), List.append(&2, U32, pre, [r]), pre))'),
 ('two-address: only the head def is reordered', 'ra_defs.go(r, ra_def(ra_cons2(s, ss, v), s, i, op, v), i, op, ss, un)',
  'ra_defs.go(r, ra_def(ra_cons(un, v), s, i, op, v), i, op, ss, un)'),
 ('sorted_uses: the name tiebreak dropped', 'su_le.n0(String.is_le(n, m), String.eq(n, m),\n            U32.is_le(x, y))))', 'su_le.n0(True{}, False{}, True{})))'),
 ('sorted_uses: lr[k][0] tiebreak dropped', 'su_le.n0(U32.is_le(f, g), U32.is_eq(f, g),\n          su_le.n0(String.is_le(n, m), String.eq(n, m),\n            U32.is_le(x, y))))',
  'su_le.n0(U32.is_le(f, g), U32.is_eq(f, g),\n          su_le.n0(True{}, False{}, True{})))'),
 ('sorted_uses: the next-use distance is constant', 'Su{ra_dist(tb_vs(lr, v), i, 0), at(tb_vs(lr, v), 0n),', 'Su{0, at(tb_vs(lr, v), 0n),'),
 ('prologue: used_in_loop is never filtered', 'Bool.pick(List<&2, U32>, ra_inloop(tb_vs(lr, RaEn.k(en)), i, e),', 'Bool.pick(List<&2, U32>, True{},'),
 ('prologue: the constraint subset test is an OR', 'ra_blk.go(t, es, Bool.and(acc, ra_invals(es, r)))', 'ra_blk.go(t, es, Bool.or(acc, ra_invals(es, r)))'),
 # RE-AIMED: `ra_st.in` is now a WHOLE-TABLE write (`ra_st.in(+s, t: LT.RaTb)`),
 # so "live_in[v] is not written" is a mutation of `ra_in`, the def that owns the
 # `live_in` table, and not of `ra_w.put`, which now only sequences two calls.
 ('prologue: live_in[v] is not written', 'def ra_in(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  ra_st.in(s, tb_put(RaSt.in(s), v, r, Nil{}))',
  'def ra_in(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  s'),
 ('prologue: the push is dropped', 'ra_st.ns(s, List.append(&2, RaTb, RaSt.ns(s),\n    [RaSt.in(ra_w.go(', 'ra_st.ns(s, List.append(&2, RaTb, RaSt.ns(s),\n    [tb_new()]))\n#(\n    [RaSt.in(ra_w.go('),
 ('prologue: the set union becomes a concatenation of live only', 'ra_used(RaSt.lv(s), RaSt.sp(s), i, RaSt.lr(s), tb_get(RaSt.lp(s), i))',
  'ra_used(RaSt.lv(s), RaSt.sp(s), i, RaSt.lr(s), 4294967295)'),
 ('epilogue: the reload condition dropped', 'Bool.and(tb_has(RaSt.lv(s), v), U32.is_eq(tb_get(RaSt.lv(s), v), r))', 'False{}'),
 # RE-AIMED: this entry's anchor was the MUTANT -- it searched for
 # `def ra_epi.ok(...): False{}` and replaced it with the real body, so on a file
 # that HAS the real body it was a no-op patch that could never apply.  Inverted to
 # anchor on the port and force `True{}`, which is what "reloads everything" means.
 ('epilogue: it reloads everything', 'def ra_epi.ok(+s: RaSt, +v: U32, r: U32) -> Bool:\n  Bool.and(tb_has(RaSt.lv(s), v), U32.is_eq(tb_get(RaSt.lv(s), v), r))',
  'def ra_epi.ok(+s: RaSt, +v: U32, r: U32) -> Bool:\n  True{}'),
 ('epilogue: the pop is dropped', 'ra_st.ns(s, ra_pop(RaSt.ns(s)))', 'RaSt.ns(s)'),
 ('fill: the spill slot is never recorded', 'ra_fill.slot(U32.is_ne(tb_get(RaSt.sp(s), v), 0), s, v)', 's'),
 ('fill: the fill is never recorded', 'ra_fill.put(ra_alloc(cs, s, i), i, v)', 'Al{Al.r(ra_alloc(cs, s, i)), s}'),
 ('fill: the state is the pre-alloc state again', 'ra_st.ib(Al.st(a), tb_put(RaSt.ib(Al.st(a)), i, 0,\n                                        tb_pput(tb_vs(RaSt.ib(Al.st(a)), i), v, Al.r(a))))',
  'ra_st.ib(s, tb_put(RaSt.ib(s), i, 0,\n                      tb_pput(tb_vs(RaSt.ib(s), i), v, Al.r(a))))'),
 ('live.pop becomes a no-op', 'Al{RaBd.r(b), ra_st.lv(s, ra_del(RaSt.lv(s), RaBd.v(b)))}', 'Al{RaBd.r(b), s}'),
 ('reals[i][v] appends instead of replacing', 'ra_st.re(s, tb_pset(RaSt.re(s), i, v, r))', 'ra_st.re(s, tb_put(RaSt.re(s), i, 0, [v, r]))'),
 ('the pseudo-op continue is dropped', 'ra_lr.lp(lt_is_range(RaUop.op(u)), ra_lr.ps(ra_is_pseudo(RaUop.op(u)), s, i, u), i,',
  'ra_lr.lp(lt_is_range(RaUop.op(u)), ra_lr.d2(ra_lr.d1(s, i, u), i, u), i,'),
 # RE-AIMED: `List.reverse` moved from inside `ra_lr.go` to the `ra_run.of` call
 # site, so the `ra_run.go` call no longer spells it.
 ('the main loop starts at 1', 'ra_run.go(ops, ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s), 0)',
  'ra_run.go(ops, ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s), 1)'),
 ('rewrite: the pseudo-op answer is not None', 'Bool.pick(String, ps, "-",', 'Bool.pick(String, ps, O.Ops.name.of(RaUop.op(u)),'),
 # RE-AIMED: `rw_items` had its `List.append` OPERANDS SWAPPED -- `List.append(x, A,
 # xs, ys)` is `xs ++ ys`, so the fix reversed the nesting.  The anchor below is the
 # fixed spelling and the mutation drops `rw_after`.
 ('rewrite: the tag rewrite is not threaded', 'List.append(&2, Em, List.append(&2, Em, rw_before(s, i), [Em{RaUop.op(u), ""}]),\n              rw_after(s, u))',
  'List.append(&2, Em, List.append(&2, Em, rw_before(s, i), [Em{RaUop.op(u), ""}]),\n              Nil{})'),
 ('the row order moves the per-uop rows first', 'List.append(&2, String, ra_lead(pre, s),\n              List.append(&2, String, ra_a_lines.g(pre, s, ra_keys(RaSt.re(s)), Nil{}),\n                         ra_tail(pre, s)))',
  'List.append(&2, String, ra_a_lines.g(pre, s, ra_keys(RaSt.re(s)), Nil{}),\n              List.append(&2, String, ra_lead(pre, s), ra_tail(pre, s)))'),
 ('the row sorts by intern index instead of by text', 'String.join(List.sort(String, sle, ra_pairs.go(tb_vs(t, i), un, tb_vs(t, i), Nil{})), " ")',
  'String.join(ra_pairs.go(tb_vs(t, i), un, tb_vs(t, i), Nil{}), " ")'),
 ('the intern table loses v4', 'Ru{"v4", 10, [1, 2]}]', 'Ru{"v4", 9, [1, 2]}]'),
]


def main():
    lines = ["# ra-mutate.py -- regalloc.bend, MEASURED.  rows moved are whole "
             "`name=value` lines.\n"]
    with SM.StagedSet([LATE / ("%s.bend" % f) for f in FILES], "ra", transform=q) as unit:
        base = unit.rows()
        SM.control(base, unit.rows(), "regalloc baseline")
        lines.append("# baseline: %d rows over %s, row-set digest %s\n"
                     % (len(base), ", ".join(FILES), SM.row_digest(base)[:16]))
        lines.append("| mutation | file | rows moved | how many |")
        lines.append("| --- | --- | --- | --- |")
        unapplied, blind, dnc = [], [], []
        for name, old, new in MUT:
            where = unit.apply(old, new)
            if where is None:
                unapplied.append(name)
                lines.append(PNA.pipe([name, PNA.not_applied("the anchor is in none of "
                                  "the three staged files"), "-", 0], 4))
                unit.restore()
                continue
            got = unit.rows()
            unit.restore()
            if got is None:
                dnc.append(name)
                lines.append(PNA.pipe([name, PNA.not_a_program(), unit.why(), 0], 4))
                continue
            lost = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
            lines.append("| %s | %s | %s | %d |"
                         % (name, where, ", ".join(lost) if lost else "NONE", len(lost)))
            if not lost:
                blind.append(name)
    OUT.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("\nwrote %s" % OUT)
    print("PATCH-NOT-APPLY %d | DID-NOT-COMPILE %d | moved-nothing(blind) %d | ran %d"
          % (len(unapplied), len(dnc), len(blind), len(MUT) - len(unapplied) - len(dnc)))
    for n in dnc:
        print("  NOT A PROGRAM: %s" % n)
    for n in blind:
        print("  BLIND SPOT (0 rows, still a program): %s" % n)
    return 1 if (unapplied or dnc) else 0


if __name__ == "__main__":
    sys.exit(main())