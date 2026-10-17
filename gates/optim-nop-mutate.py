#!/usr/bin/env python3
"""Mutation harness for the `op_nop` rows of `tinybendygrad/nn/optim.bend`.

    .venv/bin/python gates/optim-nop-mutate.py

`nn/optim.bend`'s own `main` is the instrument and its mutation table is its proof, but the
table was PROSE until this file, and a table whose numbers were typed by hand is a claim. So
the table lives here as `(name, upstream line, find, replace)` -- `mutkit`'s tuple shape --
and `mutkit.bend_rows` IS the lane reader; only the loop is this file's, because
`mutkit.main` wants a `gates/*-gate.py` and these rows have no gate: their verdict is
`op_nop*=<Bool>` on the file's own stdout and there is no CPython oracle for the LETTER.

THE COPY LIVES BESIDE THE ORIGINAL. `optim.bend` imports `../tensor.bend` RELATIVE TO ITS OWN
PATH and is `.gitignore`d as `*mut.bend` beside the tree, so a copy anywhere else answers "the
substrate did not warm" -- a REFUSED exit for the wrong reason. The tree's own own file is NEVER
written.

WHY THIS TABLE EXISTS AT ALL. `nn/optim.bend`'s `M3` row read **NOTHING** for eight days and
the reason it gave -- "a `Dn` fixture would un-gate the `D1` arm" -- was measured FALSE, because
`op_nop` was ONE row with ONE fixture and the device was hardcoded inside `g_opt`. `op_nop.dn`
is the second row, and the PLANTS below are the proof that the two cannot be traded.

**AND THE VACUITY PLANT IS A PAIR, AND IT IS WHY `op_nop.tag` EXISTS.** The question "can the new
arm be silently un-gated?" has one honest reading: an edit that leaves `op_nop.dn` GREEN while the
`Dn` arm never fires. MEASURED, and the answer is YES, and it takes TWO tokens. Collapsing
`nop_name`'s `Nzl` arm to `Nzs` (`P4`) AND replacing `op_nop.dn`'s expectation with `op_nop`'s
(`P2`) together leave `op_nop=True` and `op_nop.dn=True` at rc=0 with the `Nzl`/`Nzs` distinction
GONE. **"THE TWO EXPECTATIONS ARE MUTUALLY EXCLUSIVE" IS NOT A GUARD**, because the vacuity route
never hands both rows one string: it collapses the PRINTER until both rows read the same line, and
only `op_nop.dn`'s literal has to move because `op_nop`'s was already `Nzs`. `P5` is that pair
and it is the ONE PLANT THAT WAS GREEN BEFORE `op_nop.tag` EXISTED. `op_nop.tag` builds the three
`NewOpt`s BY HAND, so nothing in `op_nop.arm`, in the fixtures or in the device reaches it, and it
catches `P5` -- **THE WITNESS FOR A PRINTER IS A SEPARATE DEF, because every other row's use of it
is a comparison whose other operand moves with it.**

THE TWO ENTRIES THAT ARE EXPECTED TO MOVE NOTHING. `M4` is a VACUOUS EDIT -- a control that is
SUPPOSED to move nothing, and its zero is what proves this harness can report one at all;
without it a green "0 rows moved" from Z2 would be indistinguishable from a green "0 rows moved"
from a mutation that did not run. `Z2` is a DEAD ARM: `op_nop.arm` has a THIRD arm, `case True{}
_: [Nz{op_last(pp)}]`, and NO fixture reaches it -- `g_opt.on`'s `fused` is `False{}`, so `Nz` is
never PRINTED BY `op_nop`, even though the PRINTER's `Nz` letter IS pinned by `op_nop.tag`.
Those are two different objects and the table keeps them apart: `Z1` (the printer's letter) moves
BECAUSE `op_nop.tag` exists, and `Z2` (the arm) does not because no row builds a fused record.
**SO `Z2` IS THE ONE MEASURED LIMIT LEFT IN `nn/optim.bend`, and it is NOT three tokens: a fused
record needs `fused=True{}` AND `pos_params = op_acc(params)`, and `Optim` has twenty-four
fields, so it costs a second record-mutation def rather than an edit.** `op_pos.of` already
computes the right `pos_params` from `fused` and the tensors, so the missing piece is the record
mutation and nothing else.

**AND THE EXIT IS NOW THE RUN, BECAUSE FOUR OF ELEVEN ENTRIES PRINTED `REFUSED` AND EXITED 0.**
`gates/exitcode-census-gate.py` reads this file's `sys.exit(main())` as `FOREIGN`, which is CORRECT
and was never the complaint: the trailing `0` is a number the author chose, so the shape census
cannot see this and should not be asked to. What it cannot see is one process up -- the harness
computed three states, printed every one of them, and returned a constant. The three, and the number
each gets, are `gatekit`'s and are not invented here: a `find` that matched nothing or twice is
`REFUSED` (a precondition was absent), a `bend` that ran and emitted no rows is `DEAD` (it ran and
emitted nothing), and an entry that moved nothing without being expected to is `FAIL` (the table
carries a rule no row observes). `gates/gatekit.py:766` `gate()` is the precedent for combining:
FIRST NON-PASS WINS, and a later finding can only move `PASS` somewhere else. MEASURED on the run
that motivated it: `P2`, `P4`, `P5` and `Z1` name `find` strings with 0 occurrences in
`nn/optim.bend`, so that run now exits `3` instead of `0`.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gatekit
import mutkit

DRIVER = Path(__file__).resolve().parents[1] / "tinybendygrad/nn/optim.bend"

# WHY ZERO IS THE EXPECTED READING. A harness that reports every entry as FOUND cannot be read
# at the entries that are not, so the expectation is part of the entry. COMPOSED holds the
# labels whose edits are applied TOGETHER -- one entry, one run, one verdict.
COMPOSED = {"P5": ("P2", "P4")}
ZERO_IS_THE_FINDING = ("M4", "Z2")

MUTATIONS = [
    # ---- the table `nn/optim.bend` already carried, now re-runnable ------------
    ("M1 op_acc's `initial=0` seed is dropped", "optim.py:22",
     "  op_acc.go(params, [0])", "  op_acc.go(params, Nil{})"),
    ("M2 op_filter.t selects the non-params", "optim.py:13",
     "    case T.Tensor{ar, uop, True{}, grad}: List.append(&2, U32, acc, [uop])",
     "    case T.Tensor{ar, uop, False{}, grad}: List.append(&2, U32, acc, [uop])"),
    ("M3 the `S.Dn` arm is the `S.D1` arm's body -- WAS NOTHING, NOW A ROW",
     "optim.py:26",
     "    case False{} S.Dn{tags}: map_nzl(szs)", "    case False{} S.Dn{tags}: map_nzs(szs)"),
    ("M4 a no-op edit: the CONTROL, which must move nothing", "-",
     'row("op_nop.dn"', 'row("op_nop.dn"'),

    # ---- the plants: an edit that MUST turn one arm red ----------------------
    # THE SHARED FIXTURE BUILDER IGNORES ITS DEVICE. This is the sharpest of the single edits:
    # it is not an edit to the row but to the def BOTH rows call, which is what "a later fixture
    # edit" actually means in practice. MEASURED: `op_nop` stayed True and `op_nop.dn` went
    # red, so the new arm is not reachable through the old row's green.
    ("P1 g_opt.on ignores its device argument and writes S.D1{0}", "-",
     "Nil{}, Nil{}, d, S.single(), False{}, 0, Nil{},", "Nil{}, Nil{}, S.D1{0}, S.single(), False{}, 0, Nil{},"),
    # HALF THE VACUITY EDIT. Replacing the Dn row's expectation with the D1 row's is the only
    # one-token way to make the Dn row agree with a single-device fixture -- and it does NOT
    # make it green, because the Dn FIXTURE still prints `Nzl`. MEASURED: `op_nop.dn` red,
    # `op_nop` untouched. This entry was first labelled "make the new arm VACUOUS" and the
    # label was WRONG in the direction that matters: read the measurement, not the label.
    ("P2 op_nop.dn's expectation is op_nop's -- HALF the vacuity edit", "-",
     '"Nzl:2,Nzl:3,"))', '"Nzs:2,Nzs:3,"))'),
    # THE THREE-TOKEN EDIT the prior unit measured, re-measured on the row it belongs to. Its
    # damage is now LOCAL: before this change it landed on `op_nop`. This is also the OTHER
    # vacuity direction -- a single-device fixture against a Dn expectation.
    ("P3 op_nop.dn's fixture is a single device -- the Dn arm never fires", "optim.py:26",
     "op_nop(g_opt.grown.on(S.Dn{[6, 0]},", "op_nop(g_opt.grown.on(S.D1{0},"),
    # THE PRINTER COLLAPSES THE LETTER -- `ptx.bend`'s alias defect shape, where every fixture
    # put the aliased node at one position. Only `op_nop.dn` can see it.
    ("P4 nop_name prints Nzl as Nzs -- the two arms' LETTERS collapse", "-",
     '    case Nzl{sz}: "Nzl"', '    case Nzl{sz}: "Nzs"'),
    # THE VACUITY PLANT: P2 AND P4 TOGETHER, and this entry was the REASON `op_nop.tag` was
    # added. Measured with only `op_nop` and `op_nop.dn` present it moved NOTHING at rc=0: both
    # rows printed `Nzs:2,Nzs:3,`, both compared True, and the `Nzl`/`Nzs` distinction that is
    # the whole of the two arms was GONE. "The two expectations are mutually exclusive" is NOT a
    # guard, because the vacuity route never hands both rows one string -- it collapses the
    # PRINTER until both rows read the same line, and only `op_nop.dn`'s literal has to move
    # because `op_nop`'s was already `Nzs`. With `op_nop.tag` this composition is caught.
    ("P5 P2 + P4 together -- the new arm green and the Dn arm DEAD", "-",
     None, None),

    # ---- expected to move NOTHING, and the cause is named ------------------------
    ("Z1 nop_name prints Nz as Nzl -- CAUGHT BY `op_nop.tag`", "optim.py:24",
     '    case Nz{n}: "Nz"', '    case Nz{n}: "Nzl"'),
    ("Z2 the fused arm returns Nzs -- `op_nop.arm`'s THIRD arm", "optim.py:24",
     "    case True{} _: [Nz{op_last(pp)}]", "    case True{} _: [Nzs{op_last(pp)}]"),
]

# A CAUSE PER ZERO, because "moved nothing" and "moved nothing for a reason I can name" are
# different findings and only one of them is a deliverable. The nine names this tree records
# are COVERAGE GAP, DEAD DEF, DEAD ARM, VACUOUS EDIT, FIXTURE AVOIDING THE BRANCH, A DEFECT THAT
# SWALLOWS THE ROW, A FORM THAT DID NOT COMPILE, A ROW WHOSE TOKEN IS A REFUSAL and THE WITNESS IS
# A SEPARATE DEF; M4 and Z2 are two of the nine, named here rather than folded into the generic
# string, and `op_nop.tag` is the ninth one paid for.
CAUSE = {
    "M4": "VACUOUS EDIT -- the CONTROL, and it is SUPPOSED to move nothing. Its zero is what "
          "proves this harness can report one, so a zero from Z2 below is not the harness "
          "answering zero to everything",
    "Z2": "DEAD ARM -- `op_nop.arm`'s `case True{} _` is unreachable from every fixture here "
          "(every `g_opt.on` record has `fused=False{}`), so the arm's BODY is changed and no "
          "row can see it. NOT `op_nop.tag`'s business: the PRINTER's `Nz` letter is pinned and "
          "Z1 moves; what is unpinned is that `op_nop.arm` can PRODUCE `Nz` at all",
}


def mutant_text(src, label, find, repl):
    """`src` with one entry's edit applied, and for a COMPOSED entry with its halves' too.

    EVERY `find` IS ASSERTED UNIQUE FIRST, INCLUDING A COMPOSED ENTRY'S HALVES, so a mutation
    that silently stopped matching is a REFUSED entry and not a green one -- and a composition
    whose half went stale refuses rather than half-applying, which would print a green for an
    edit the table no longer describes. `None` MEANS REFUSED.
    """
    def apply_one(text, f, r):
        return text.replace(f, r) if text.count(f) == 1 else None

    if find is not None:
        return apply_one(src, find, repl)
    text = src
    for half in COMPOSED[label]:
        _, _, f, r = next(m for m in MUTATIONS if m[0].split()[0] == half)
        text = apply_one(text, f, r)
        if text is None:
            return None
    return text


def main():
    src = DRIVER.read_text()
    base, brc = mutkit.bend_rows(DRIVER)
    if brc != 0 or len(base) != len(set(base)):
        print(f"{DRIVER.name}: the UNMUTATED file is rc={brc} and printed {len(base)} rows, so "
              f"a mutation reading would be meaningless"
              + ("" if brc == 0 else " -- it did not run"))
        # A BASELINE THAT DID NOT RUN IS `REFUSED`, NOT `FAIL`. `gatekit.py`: "REFUSED a
        # precondition was absent"; the precondition here is the base reading, and the message
        # above already says the run did not happen, so billing it FAIL said the TABLE was wrong
        # when what was missing was the measurement.
        return gatekit.REFUSED
    mut = DRIVER.with_name("optim-mut.bend")   # `.gitignore`d as `*mut.bend`
    zeros, moved_any, refused, expected = [], 0, 0, 0
    code = gatekit.PASS
    try:
        print(f"{DRIVER.name}: BASE rc=0, {len(base)} rows\n")
        for name, line, find, repl in MUTATIONS:
            key = name.split()[0]
            text = mutant_text(src, key, find, repl)
            if text is None:
                print(f"  REFUSED   {name}: a pattern is not unique ({line})")
                refused += 1
                if code == gatekit.PASS:
                    code = gatekit.REFUSED
                continue
            mut.write_text(text)
            rows, mrc = mutkit.bend_rows(mut)
            moved = sorted(k for k, v in rows.items() if k in base and base[k] != v)
            appeared = sorted(set(rows) - set(base))
            vanished = sorted(set(base) - set(rows))
            # AN EMPTY LANE IS NOT A MOVEMENT. `mutkit`'s own note is about a lane that got
            # LONGER, which mutkit reads as a mutation that moved; a lane that came back with
            # NOTHING is the other thing entirely -- a form that did not compile -- and reporting
            # its thirteen disappearances as "13 rows moved" would charge a coverage claim for an
            # edit nobody could evaluate. MEASURED HERE, and the row is real: one run of four
            # answered `bend rc=1` with all thirteen rows VANISHED for `Z2`, whose edit compiles
            # and prints thirteen green rows in isolation (re-measured three times). A concurrent
            # writer on this tree -- loadavg 17-24 on 12 cores, four users -- is the reading, and
            # THIS HARNESS CANNOT TELL A COMPILE FAILURE FROM A CORRUPTED READ, so it says
            # "did not compile" and refuses to count it either way.
            if mrc != 0 or not rows:
                print(f"  {name:<62} bend rc={mrc}, {len(rows)} rows  DID NOT COMPILE -- "
                      f"no reading, counted as neither a movement nor a zero")
                refused += 1
                # NOT `REFUSED`. `bend` RAN and emitted nothing, and `gatekit.py` already has a word
                # for exactly that and a number for it: DEAD. Calling it REFUSED would bill a
                # caller a "precondition was absent" whose precondition WAS present.
                if code == gatekit.PASS:
                    code = gatekit.DEAD
                continue
            got = len(moved) + len(appeared) + len(vanished)
            moved_any += bool(got)
            print(f"  {name:<62} bend rc={mrc}  {got} rows moved"
                  + (f"  [{moved[0]}{' +%d more' % (len(moved) - 1) if len(moved) > 1 else ''}]"
                     if moved else "")
                  + (f"  APPEARED {appeared}" if appeared else "")
                  + (f"  VANISHED {vanished}" if vanished else ""))
            for k in moved:
                print(f"      {k}: {base[k]} -> {rows[k]}")
            if not got:
                zeros.append(name)
                if key in ZERO_IS_THE_FINDING:
                    expected += 1
                    print(f"      MOVED NOTHING AT rc=0 -- EXPECTED. {CAUSE[key]}")
                else:
                    print("      MOVED NOTHING AT rc=0 -- NOT EXPECTED. COVERAGE GAP: this "
                          "rule has no row.")
                    # A TABLE ENTRY THAT MEASURED NOTHING AND WAS NOT SUPPOSED TO IS A FAIL OF THE
                    # TABLE. It was already the loudest line this harness prints; here it also
                    # reaches `$?`.
                    if code == gatekit.PASS:
                        code = gatekit.FAIL
    finally:
        mut.unlink(missing_ok=True)
    print(f"\n{DRIVER.name}: {moved_any} of {len(MUTATIONS) - refused} mutations moved rows; "
          f"{len(zeros)} moved nothing at rc=0 and {expected} of those {len(zeros)} were "
          f"EXPECTED to ({refused} refused: a non-unique pattern or a form that did not "
          f"compile)")
    # THE EXIT IS THE RUN, NOT A CONSTANT.  THE PRECEDENT IS `gates/gatekit.py`'s OWN COMBINING
    # RULE -- `gate(g, summary, checks)`: `code = g.run(); if code == PASS and not
    # _checks_answer(checks): code = FAIL` -- so FIRST NON-PASS WINS and a later finding can only
    # ever move PASS somewhere else. No precedence table is invented here, and no sixth state is.
    #
    # MEASURED, AND IT IS NOT HYPOTHETICAL: at the time this was written `P2`, `P4`, `P5` and `Z1`
    # each name a `find` string with **0** occurrences in `nn/optim.bend`, so this loop printed four
    # `REFUSED` lines and then returned 0, and a caller reading `$?` saw PASS on a run in which
    # four of eleven mutations were never applied. `gates/exitcode-census-gate.py` grades that
    # site FOREIGN -- the `0` at the end IS a number the author chose -- so the shape census was
    # right and still could not see this: the defect is one process up, and it is the state the
    # harness COMPUTED AND DISCARDED.
    return code


if __name__ == "__main__":
    sys.exit(main())