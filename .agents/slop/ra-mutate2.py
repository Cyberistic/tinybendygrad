#!/usr/bin/env python3
"""ra-mutate2.py -- the SECOND mutation table for the same `codegen/late/` unit.

    python3 .agents/slop/ra-mutate2.py

⚠ IT NO LONGER WRITES THE LIVE TREE.  `open(MUTATED,'w').write(...)` plus a
`finally` restore, digest sampled once at start: on a file another unit is editing
that restore reverts their work and the harness cannot tell.  `staged_mut.StagedSet`
stages `jj file show -r @` beside each of the three `late/` files, ASSERTS
`sha256(mirror) == sha256(live)`, edits only the staged copies, unlinks them in a
`finally`, and REPORTS whether a live digest moved during the run.

IT ALSO COULD NOT RUN.  Its baseline came from a frozen `full.txt` in scratch that
does not exist, so the module raised at import -- after `shutil.copy` had already put
the live file over its own snapshot.  The baseline is now taken from the staged
mirror, per run, and RULE C's control is asserted before anything is measured.

Same prologue as `ra-mutate.py`: the written files are `late/linearizer.bend`,
`late/regalloc.bend` and `late/gater.bend`, all three are run, and `q()` applies the
`LT.` qualifier the split forced on a call site AND on a type mention.
"""
import os
import pathlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_not_apply as PNA
import staged_mut as SM

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
LATE = ROOT / "tinybendygrad" / "codegen" / "late"
FILES = ("linearizer", "regalloc", "gater")
OUT = ROOT / ".agents/slop/ra2-mutations.txt"

_qpat = re.compile(r'(?<![\w.])(%s)(?![\w])' % '|'.join(re.escape(n) for n in
    ['RaEn', 'RaEn.k', 'RaEn.v', 'RaTb', 'RaTb.es', 'at', 'b2u', 'cfg_entry',
     'lt_is_exit', 'lt_is_range', 'lt_key', 'lt_lines', 'lt_op_is', 'row', 'tb_get',
     'tb_has', 'tb_ins', 'tb_keys', 'tb_new', 'tb_pget', 'tb_pput', 'tb_pset',
     'tb_put', 'tb_vput', 'tb_vs', 'u32_none']))


def q(s):
    return _qpat.sub(lambda m: 'LT.' + m.group(1), s)


# (name, old, new)
#
# RE-AIMED 2026-10-04, two entries, and BOTH drifted for the same structural reason:
# the 1:1 split moved defs between the three `late/` files, so an anchor that names a
# `def` can leave the file it was written for without changing by one character.
#   'prologue: live_in[v] is not written'  `ra_st.in(s, v, r)` became `ra_in(s, v, r)`
#                                          -- `ra_st.in` is now a whole-TABLE write.
#   'reals[i][v]: replace becomes whole-list append'
#                                       `tb_pset.put` now lives in `linearizer.bend`.
# The second one is why the harness searches the anchor across all three staged files:
# re-aiming it into `regalloc.bend` would have meant editing a `.bend`, which is the
# one thing this rewrite exists to prevent.
MUT = [
  ('loops: max user becomes first user',
   'Bool.pick(U32, u32_in(RaUop.ss(u), k), i, best))',
   'Bool.pick(U32, u32_in(RaUop.ss(u), k), Bool.pick(U32, U32.is_eq(best, 0), i, best), best))'),
  ('alloc: free does not have priority',
   'RaBd{ra_dist(tb_vs(lr, ra_linv(RaTb.es(lv), r)), i, nmx), r, ra_linv(RaTb.es(lv), r), False{}}',
   'RaBd{0, r, ra_linv(RaTb.es(lv), r), False{}}'),
  # RE-AIMED: `live_in[v] = live[v]` is now the def `ra_in`, reached from `ra_w.put`.
  ('prologue: live_in[v] is not written',
   'def ra_w.put(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  ra_in(ra_lv(s, v, r), v, r)',
   'def ra_w.put(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  ra_lv(s, v, r)'),
  ('prologue: the push is dropped',
   '  ra_st.ns(s, List.append(&2, RaTb, RaSt.ns(s),\n    [RaSt.in(ra_w.go(ra_srt(ra_pro.us(s, i), i, RaSt.lr(s), RaSt.un(s)),\n                     ra_st.in(s, tb_new()), i, u32_none()))]))',
   '  ra_st.ns(s, List.append(&2, RaTb, RaSt.ns(s), [tb_new()]))'),
  ('epilogue: it reloads everything',
   'def ra_epi.ok(+s: RaSt, +v: U32, r: U32) -> Bool:\n  Bool.and(tb_has(RaSt.lv(s), v), U32.is_eq(tb_get(RaSt.lv(s), v), r))',
   'def ra_epi.ok(+s: RaSt, +v: U32, r: U32) -> Bool:\n  True{}'),
  ('epilogue: the pop is dropped',
   'ra_epi.go(RaTb.es(ra_head(RaSt.ns(s))), ra_st.ns(s, ra_pop(RaSt.ns(s))), i)',
   'ra_epi.go(RaTb.es(ra_head(RaSt.ns(s))), s, i)'),
  ('the main loop starts at 1',
   'ra_run.go(ops, ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s), 0)',
   'ra_run.go(ops, ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s), 1)'),
  ('rewrite: the tag rewrite is not threaded',
   'List.append(&2, Em, List.append(&2, Em, rw_before(s, i), [Em{RaUop.op(u), ""}]),\n              rw_after(s, u))',
   'List.append(&2, Em, List.append(&2, Em, rw_before(s, i), [Em{RaUop.op(u), ""}]),\n              Nil{})'),
  ('rewrite: the spilled-src fills are dropped',
   'Bool.pick(Em, rw_ispill(s, i, rw_vreg(s, i, u, j)),', 'Bool.pick(Em, False{},'),
  # RE-AIMED: this `def` is in `linearizer.bend` now, where it is spelled WITHOUT
  # the `LT.` qualifier its regalloc call site needs.  `StagedSet` is given `q` as
  # the transform and offers the qualified spelling first and the raw one second,
  # so the file decides.  Re-aiming it into `regalloc.bend` would have meant editing
  # a `.bend`, which is the one thing this rewrite exists to prevent.
  ('reals[i][v]: replace becomes whole-list append',
   'def tb_pset.put(t: RaTb, +b: U32, vs: List<&2, U32>, k: U32, r: U32) -> RaTb:\n  tb_vput(t, b, tb_pput(vs, k, r))',
   'def tb_pset.put(t: RaTb, +b: U32, vs: List<&2, U32>, k: U32, r: U32) -> RaTb:\n  tb_put(t, b, 0, tb_pput(vs, k, r))'),
  ('reals[i][v]: append a second copy of the pair',
   'def ra_set(+s: RaSt, i: U32, v: U32, r: U32) -> RaSt:\n  ra_st.re(s, tb_pset(RaSt.re(s), i, v, r))',
   'def ra_set(+s: RaSt, i: U32, v: U32, r: U32) -> RaSt:\n  ra_st.re(s, tb_pset(tb_pset(RaSt.re(s), i, v, r), i, v, r))'),
  ('the row order moves the per-uop rows first',
   'List.append(&2, String, ra_lead(pre, s),\n              List.append(&2, String, ra_a_lines.g(pre, s, ra_keys(RaSt.re(s)), Nil{}),\n                         ra_tail(pre, s)))',
   'List.append(&2, String, ra_a_lines.g(pre, s, ra_keys(RaSt.re(s)), Nil{}),\n              List.append(&2, String, ra_lead(pre, s), ra_tail(pre, s)))'),
  ('the row reads an INDEX where the oracle reads a NAME',
   'def ra_pair(+vs: List<&2, U32>, +un: List<&2, Ru>, +k: U32) -> String:\n  String.concat([ra_reg(un, k), ">", U32.show(k), "->",\n                 ra_reg(un, tb_pget(vs, k)), ">", U32.show(tb_pget(vs, k))])',
   'def ra_pair(+vs: List<&2, U32>, +un: List<&2, Ru>, +k: U32) -> String:\n  String.concat([U32.show(k), "->", U32.show(tb_pget(vs, k))])'),
  ('the register name is replaced by its index',
   'def ra_reg(+un: List<&2, Ru>, r: U32) -> String:\n  Ru.nm(ra_uni(un, r))',
   'def ra_reg(+un: List<&2, Ru>, r: U32) -> String:\n  U32.show(r)'),
]


def main():
    lines = ["# ra-mutate2.py -- codegen/late, MEASURED.  rows moved are whole "
             "`name=value` lines.\n"]
    with SM.StagedSet([LATE / ("%s.bend" % f) for f in FILES], "ra2", transform=q) as unit:
        base = unit.rows()
        if base is None:
            raise SystemExit("the BASELINE does not compile (%s) -- refusing to measure"
                             % unit.why())
        SM.control(base, unit.rows(), "codegen/late baseline")
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