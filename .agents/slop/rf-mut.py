#!/usr/bin/env python3
"""rf-mut.py -- the MEASURED mutation table for `schedule/rangeify.bend`.

    python3 .agents/slop/rf-mut.py

Applies one textual mutation at a time, re-checks, re-runs, and diffs against the
clean gate.  A mutation that does not compile is reported as such, because "the
refused edit" is a result too -- and it is a DIFFERENT result from "the edit never
landed", which is `PATCH-NOT-APPLY`.  A table that uses one spelling for both indicts
the edit when the build is what failed.

⚠ IT NO LONGER WRITES THE LIVE TREE.  It used to: `open(F,'w').write(...)` plus a
`shutil.copy(BAK, F)` restore, digest sampled once at start.  `rangeify.bend` is a
file other units are editing, and a restore over a concurrent edit destroys the
straddling work permanently -- `ops-501-mutate.py`'s docstring records exactly that
happening.  `staged_mut.Staged` now stages `jj file show -r @` BESIDE the file (so
`./../helpers.bend` and `./../LAWS/spec.bend` still resolve -- a `$TMPDIR` copy
cannot, and that produced 22 phantom blind spots in one unit), ASSERTS
`sha256(mirror) == sha256(live)`, edits only the staged copy, unlinks it in a
`finally`, and REPORTS whether the live digest moved during the run.

`BEND --check-only` is used for the liveness gate on its OUTPUT TEXT and never on its
exit status, because agent-core.md records it exiting 1 on a file that is fine.
"""
import os
import pathlib
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_not_apply as PNA
import staged_mut as SM

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
F = ROOT / "tinybendygrad/schedule/rangeify.bend"
OUT = ROOT / ".agents/slop/rf-mutations.txt"

MUTS = [
  # 1. THE FIRST-WINS FOLD.  `hop_first` is movement.bend's, so the mutation is on
  #    the ONE thing this file owns that decides first-wins: `M.hop_next`'s ordering,
  #    by making `rf_self` KEEP the node under examination rather than drop it.  That
  #    is the `ret is not uop` direction and it is the single mutation most likely to
  #    be written by mistake.
  ("M1  `rf_self` keeps `self` instead of dropping it (ret-is-not-upop inverted)",
   "def rf_self.of(same: Bool, +r: M.Hop) -> M.Hop:\n  match same:\n    case True{} : M.Hop{M.hop_ar(r), 0}\n    case False{}: r",
   "def rf_self.of(same: Bool, +r: M.Hop) -> M.Hop:\n  match same:\n    case True{} : r\n    case False{}: M.Hop{M.hop_ar(r), 0}"),

  # 2. THE IDENTITY CHECK of the header.  `rb_ident` is the only one in the file.
  ("M2  `rb_ident` always True (the upat.py:100-105 check removed)",
   "def rb_ident(+ar: O.Arena, +self: U32) -> Bool:\n  U32.is_eq(M.mp_src(ar, self, 0), M.mp_src(ar, self, 1))",
   "def rb_ident(+ar: O.Arena, +self: U32) -> Bool:\n  Bool.or(U32.is_eq(M.mp_src(ar, self, 0), M.mp_src(ar, self, 1)), M.mp_nsrc_is(ar, self, 2))"),

  # 3. `early_reject`'s subset test, `and` -> `or`.
  ("M3  `rf_early`'s subset test `and` -> `or`",
   "    case o <> t: Bool.and(O.op_in(have, o), rf_early.go(have, t))",
   "    case o <> t: Bool.or(O.op_in(have, o), rf_early.go(have, t))"),

  # 4. A MISSPELLED reject set, which is the failure mode `early_reject` really has.
  ("M4  `dg_3`'s reject set {PARAM} misspelled as {RANGE}",
   "   O.PMEntry{3, [O.OpsINDEX{}],  [O.OpsPARAM{}]},",
   "   O.PMEntry{3, [O.OpsINDEX{}],  [O.OpsRANGE{}]},"),

  # 5. `is_noop_after_dep`'s NOOP arm: the `len(x.src) == 0` conjunct removed, so
  #    EVERY NOOP is a dead dep.  This is the row that pins the arm.
  ("M5  `noopf.at`'s `len(x.src) == 0` conjunct removed",
   "def noopf.at(+ar: O.Arena, +self: U32) -> Bool:\n  Bool.and(M.mp_is(ar, self, O.OpsNOOP{}), M.mp_nsrc_is(ar, self, 0))",
   "def noopf.at(+ar: O.Arena, +self: U32) -> Bool:\n  M.mp_is(ar, self, O.OpsNOOP{})"),

  # 6. `remove_noop_afters`'s `src[0]` KEPT-UNCONDITIONALLY half: filter the head
  #    too.  This is the subtlety the three raf rows exist for.
  ("M6  `raf.keep_srcs` filters `src[0]` as well",
   "  raf.keep.go(ar, O.Arena.src_from(ar, self, 1), [M.mp_src0(ar, self)])",
   "  raf.keep.go(ar, M.mp_srcs(ar, self), Nil{})"),

  # 7. `remove_noop_afters`'s `len(src) == 1` arm turned into the rebuild arm.
  ("M7  `raf_one`'s one-src arm removed (always rebuilds)",
   "def raf_one(kept: List<&2, U32>) -> Bool:\n  Nat.is_eq(List.length(&2, U32, kept), 1n)",
   "def raf_one(kept: List<&2, U32>) -> Bool:\n  Bool.not(Nat.is_eq(List.length(&2, U32, kept), 1n))"),

  # 8. `strip_zero_offset_shrink`'s SHRINK test dropped, so every node strips.
  ("M8  `rf_strip`'s `x.op is Ops.SHRINK` test dropped",
   "def rf_strip.of(shrink: Bool, zero: Bool, +ar: O.Arena, self: U32) -> M.Hop:\n  match shrink:\n    case True{} : match zero:\n                  case True{} : M.Hop{ar, M.mp_src0(ar, self)}\n                  case False{}: M.Hop{ar, self}\n    case False{}: M.Hop{ar, self}",
   "def rf_strip.of(shrink: Bool, zero: Bool, +ar: O.Arena, self: U32) -> M.Hop:\n  match zero:\n    case True{} : M.Hop{ar, M.mp_src0(ar, self)}\n    case False{}: M.Hop{ar, self}"),

  # 9. `no_indexing_calls`'s INDEX arm turned into the pass-through arm.
  ("M9  `nic.of`'s INDEX arm turned into pass-through",
   "    case True{} : List.append(&2, U32, acc, [M.mp_src0(ar, x)])",
   "    case True{} : List.append(&2, U32, acc, [x])"),

  # 10. `pm_add_param_range_tags`'s ALU conjunct removed.
  ("M10 `rf_alu_param`'s `op is Ops.PARAM` conjunct removed",
   "def rf_alu_param(+fx: F.Folded, +ar: O.Arena, +self: U32) -> Bool:\n  Bool.and(M.mp_is(ar, self, O.OpsPARAM{}), rf_addr_eq(fx, self, S.Aalu{}))",
   "def rf_alu_param(+fx: F.Folded, +ar: O.Arena, +self: U32) -> Bool:\n  rf_addr_eq(fx, self, S.Aalu{})"),

  # 11. `renumber_range`'s tag guard INVERTED -- the bug this file actually had.
  ("M11 `rf_renumber`'s `r.tag != ()` guard inverted",
   "def rf_renumber.of(tagged: Bool, +ar: O.Arena, +self: U32, n: U32) -> M.Hop:\n  match tagged:\n    case True{} : M.mp_hit(O.UOp.new(ar, O.OpsRANGE{}, M.mp_srcs(ar, self),\n                                    O.ARange{[n], rf_axis(ar, self)}, rf_no_tag()))\n    case False{}: M.Hop{ar, 0}",
   "def rf_renumber.of(tagged: Bool, +ar: O.Arena, +self: U32, n: U32) -> M.Hop:\n  match tagged:\n    case True{} : M.Hop{ar, 0}\n    case False{}: M.mp_hit(O.UOp.new(ar, O.OpsRANGE{}, M.mp_srcs(ar, self),\n                                    O.ARange{[n], rf_axis(ar, self)}, rf_no_tag()))"),

  # 12. `rf_renumber`'s AxisType half rebuilt from scratch rather than read off
  #     the node -- the mistake `ren_axis_weak` is the row for.
  ("M12 `rf_renumber` rebuilds the AxisType instead of reading it",
   "                                    O.ARange{[n], rf_axis(ar, self)}, rf_no_tag()))\n    case False{}: M.Hop{ar, 0}",
   "                                    O.ARange{[n], O.AXIS_LOOP{}}, rf_no_tag()))\n    case False{}: M.Hop{ar, 0}"),

  # 13. `ab_4`'s STRICT-two-src claim relaxed, which DESTROYS the two-rules node.
  ("M13 `ab_4_claim`'s `len(x.src) == 2` relaxed to `>= 2`",
   "def ab_4_claim(+ar: O.Arena, +self: U32) -> Bool:\n  Bool.and(M.mp_is(ar, self, O.OpsSTAGE{}), M.mp_nsrc_is(ar, self, 2))",
   "def ab_4_claim(+ar: O.Arena, +self: U32) -> Bool:\n  Bool.and(M.mp_is(ar, self, O.OpsSTAGE{}), M.mp_nsrc_ge(ar, self, 1))"),

  # 14. `flatten_bufferize`'s `len(x.src) == 2` early return inverted -- the other
  #     half of the same fixture.
  ("M14 `rf_fb_two`'s `len(x.src) == 2` test inverted",
   "def rf_fb_two(+ar: O.Arena, +self: U32) -> Bool:\n  U32.is_eq(M.mp_nsrc(ar, self), 2)",
   "def rf_fb_two(+ar: O.Arena, +self: U32) -> Bool:\n  Bool.not(U32.is_eq(M.mp_nsrc(ar, self), 2))"),

  # 15. `ab_8`'s `arg == Invalid` test weakened to "is a CONST".
  ("M15 `ab_8.pat`'s `arg == Invalid` weakened to `op is CONST`",
   "  O.eq_arg(M.mp_arg(ar, x), O.APy{O.CInvalid{}})",
   "  M.mp_is(ar, x, O.OpsCONST{})"),

  # 16. `pm_no_views`'s six-op set reduced to one, which is the pattern test.
  ("M16 `rf_is_bufid5`'s op set reduced to {BUFFER} only",
   "    case O.OpsAFTER{}  : True{}\n    case O.OpsPARAM{}  : True{}\n    case O.OpsUNSHARD{}: True{}\n    case O.OpsMSTACK{} : True{}\n    case O.OpsBUFFER{} : True{}\n    case O.OpsALLOC{}  : True{}",
   "    case O.OpsBUFFER{} : True{}"),

  # 17. `dg_3`'s ALU test flipped to GLOBAL.
  ("M17 `dg_3`'s `addrspace is ALU` test flipped",
   "  dg_3.of(rf_addr_eq(fx, M.mp_src0(ar, self), S.Aalu{}), ar, self)",
   "  dg_3.of(rf_addr_eq(fx, M.mp_src0(ar, self), S.AGlobal{}), ar, self)"),

  # 18. `claim_n` used where the FULL claim belongs -- the mutation that would
  #     silently turn the first-wins row into an op-set count.
  ("M18 `claim_full` replaced by `claim_n` (the src half of the claim dropped)",
   "def t_claim_ab_stg3() -> U32: claim_full(ab_table(), G.fx(g()), g_ar(g()), g_st3(g()))",
   "def t_claim_ab_stg3() -> U32: claim_n(ab_table(), g_ar(g()), g_st3(g()))"),

  # 19. a table entry DELETED -- the COUNT rows' reason for existing.
  ("M19 `dg_6`'s RANGE rule given the wrong op set",
   "   O.PMEntry{6, [O.OpsRANGE{}],  Nil{}}]                     # 327  r -> renumber_range",
   "   O.PMEntry{6, [O.OpsNOOP{}],   Nil{}}]                     # 327  r -> renumber_range"),

  # 20. the COUNT rows' reason for existing: an entry DELETED -- not edited, not
  #     given a wrong op set.  It is the LAST entry, so no tag after it renumbers
  #     and no rule can fire differently: the only thing in the whole gate that can
  #     possibly see this is `ct_len`.  If that row did not exist, this mutation
  #     would be invisible.
  #
  # RE-AIMED 2026-10-04.  The old anchor had drifted in three ways at once, and all
  # three were whitespace-or-content rather than structural: `[O.OpsINDEX{}],` took
  # FIVE spaces before the second column and now takes three, entry 8's left column
  # said `OpsMSTACK` where it says `OpsINDEX`, and the trailing comments were
  # rewritten.  Re-aimed to the file's current two lines; the mutation is unchanged,
  # which is the point -- only the anchor moved.  The REPLACEMENT also gained the
  # closing `]}`: deleting the last `PMEntry` verbatim leaves the entry LIST
  # unterminated, so M20 as written was `DID-NOT-COMPILE` and never measured the
  # thing it exists for.  A mutation that deletes an entry has to leave a table.
  ("M20 `ct_8`'s MSTACK.f(INDEX) rule DELETED from the table",
   "   O.PMEntry{7, [O.OpsINDEX{}],   [O.OpsAFTER{}]},          # 124  AFTER.f(INDEX) -- root INDEX\n   O.PMEntry{8, [O.OpsINDEX{}],   [O.OpsMSTACK{}]}]         # 127  MSTACK.f(INDEX) -- root INDEX",
   "   O.PMEntry{7, [O.OpsINDEX{}],   [O.OpsAFTER{}]}]         # 124  AFTER.f(INDEX) -- root INDEX"),
]

def checks(text):
    """`ALL PROOFS CHECK` on the OUTPUT TEXT.  Never the exit status: agent-core.md
    records `--check-only` exiting 1 on a file that is fine, and one agent lost a
    ten-minute retry loop to that."""
    return "ALL PROOFS CHECK" in text


def main():
    lines = ["# rf-mut.py -- schedule/rangeify.bend, MEASURED.  rows moved are whole "
             "`name=value` lines.\n"]
    results = []
    with SM.Staged(F, "rf") as unit:
        if not checks(unit.run(("--check-only",))):
            raise SystemExit("rangeify.bend does not ALL-PROOFS-CHECK to begin with; "
                             "fix the substrate before measuring anything against it")
        base = unit.rows()
        if base is None:
            raise SystemExit("the BASELINE produced no rows; refusing to measure")
        SM.control(base, unit.rows(), "rangeify baseline")
        lines.append("# baseline: %d rows, row-set digest %s\n"
                     % (len(base), SM.row_digest(base)[:16]))
        lines.append("| mutation | rows moved | how many |")
        lines.append("| --- | --- | --- |")
        for name, old, new in MUTS:
            if unit.text().count(old) != 1:
                results.append((name, PNA.not_applied("the anchor appears %d times"
                                  % unit.text().count(old)), 0))
                lines.append(PNA.pipe([name, PNA.not_applied("the anchor appears %d "
                                  "times, so which occurrence is meant is undecided"
                                  % unit.text().count(old)), 0], 3))
                continue
            unit.write(unit.text().replace(old, new, 1))
            if not checks(unit.run(("--check-only",))):
                unit.write(unit.origin())
                results.append((name, PNA.not_a_program(), 0))
                lines.append(PNA.pipe([name, PNA.not_a_program(), 0], 3))
                continue
            got = unit.rows()
            unit.write(unit.origin())
            if got is None:
                results.append((name, PNA.not_a_program(), 0))
                lines.append(PNA.pipe([name, PNA.not_a_program(), 0], 3))
                continue
            lost = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
            results.append((name, "ok", len(lost)))
            lines.append("| %s | %s | %d |"
                         % (name, ", ".join(lost) if lost else "NONE", len(lost)))
    OUT.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    zeros = [r for r in results if r[2] == 0]
    print("\nwrote %s" % OUT)
    print("%d mutations, %d PATCH-NOT-APPLY, %d DID-NOT-COMPILE, %d moved nothing"
          % (len(MUTS), sum(PNA.MARKER in r[1] for r in results),
             sum(PNA.NOT_A_PROGRAM in r[1] for r in results), len(zeros)))
    for name, st, _ in zeros:
        print("  ZERO: %s -> %s" % (name, st))
    return 1 if any(PNA.MARKER in r[1] or PNA.NOT_A_PROGRAM in r[1] for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())