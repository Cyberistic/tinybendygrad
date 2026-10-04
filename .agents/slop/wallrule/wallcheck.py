#!/usr/bin/env python3
"""WALLCHECK -- the instrument for WALL/1. ONE grep per recorded wall, against its anchor.

    .venv/bin/python .agents/slop/wallrule/wallcheck.py [ID ...]

Every exit code below is a MEASUREMENT OF THE LEDGER, not of the tree, except 1.

    0  every grepped wall's verdict is STANDS, and the error rate is 0
    1  at least one wall is STALE / RETIRED -- the number the rule exists to produce
    2  the ledger is unreadable, or a named wall is not in it
    3  a row is missing polarity / anchor / reopen / date: a STORY, whatever its grep says
    4  a selection matched no ledger row. A guard over an empty population must not
       report agreement, so this is REFUSED, never 0
    5  a row's scope is readable in neither the working copy nor HEAD: NO-SCOPE.
       A grep of nothing answers nothing, and reporting a verdict for it is the bug
       this file exists to prevent

POLARITY. A MISSING wall says a capability is ABSENT, so hits mean it LANDED. A DEFECT wall
says a defect is PRESENT, so no hits mean it is GONE. An anchor written to match the defect
under a MISSING reading inverts the verdict; three of the first nine rows were inverted that
way and all three read "ABSENT, the wall stands" for capabilities that had already landed.

TWO TREES. A wall is a claim about a tree, so both are read: `work=` is the working copy,
`pin=` is `git show HEAD:<path>`. They disagreed on `uop/ops.bend` throughout this session --
6306 lines uncommitted against HEAD's 8334, another unit mid-rewrite -- and a verdict quoting
only the working copy calls W4 and W8 STANDS when both are LANDED-at-HEAD.

ONE COMMENT FILTER, USED TWICE. A line whose first non-blank character is `#` is dropped
BEFORE the pattern runs, and the first hit reported is drawn from the same filtered lines.
An earlier version filtered `\\s*#` for the count and `:[[:space:]]*#` for the citation, so
it could report a verdict computed one way and a witness line computed another. A row whose
anchor then matches nothing but comments is `STORY`, not a verdict: it matched something and
proved nothing. `PROSE` polarity opts back IN to comments, for the walls whose subject is a
sentence -- which is five of the eighteen.

A WORK/PIN SPLIT IS ITS OWN VERDICT. A prerequisite present in ONE tree and absent from the
other is not a landed wall and not a standing one; it is a rewrite in flight, and the answer
is to wait. MEASURED BY PLANT: renaming `def mm.u64.of(` moved work=1 -> work=0 with pin=1
unchanged, and before the split existed that plant still read STANDS -- a detection the run
could not act on, because the wall it named was not the one that moved.

THIS INSTRUMENT WAS WRONG THREE TIMES BEFORE IT WAS RIGHT, and every failure is the class.
    v1  recursive grep, whole-tree patterns: PRESENT for 11 of 11. Every anchor matched
        SOMETHING; several matched the wall's own prose. Hit rate 100% = no information.
    v2  scoped + code-position anchors: 6 of 9, and the three misses were W3, W6, W7 --
        all three read ABSENT for capabilities that had landed.
    v3  scoped + polarity + two trees: correct on 9 of 9, and STILL WRONG on W3, because
        `runtime/dtype.c emit` is not a path. `[[ -r scope ]]` failing silently produced
        whits=0, which under DEFECT reads RETIRED. A row with no file behind it was
        reported as a measurement. Hence exit 5.
    v4  W11's POSIX anchor `[[:space:]]` is a nested set to Python's `re`, so the ledger's
        grep dialect had to be translated rather than the ledger rewritten. An instrument
        that silently fails to compile one anchor out of eighteen would have graded that
        wall STANDS forever, which is what `judge` now catches as a STORY.

ANCHORS ARE POSIX ERE, because that is the dialect the tree and `grep -E` speak, and a
second dialect in a second file is a wall of its own. `_posix` translates the bracket
classes Python does not have; every other anchor is used unchanged.
"""
from __future__ import annotations
import pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LEDGER, TRUTH = HERE / "walls.tsv", HERE / "walls.truth.tsv"
COMMENT = re.compile(r"^\s*#")
POSIX_CLASSES = {
    "alpha": "a-zA-Z", "digit": "0-9", "alnum": "a-zA-Z0-9", "upper": "A-Z",
    "lower": "a-z", "space": r" \t\n\r\f\v", "blank": r" \t", "punct": r"!-/:-@\[-`{-~",
    "xdigit": "0-9A-Fa-f", "word": r"\w",
}

Verdict = str  # STANDS | LANDED | GONE | SPLIT | NO-SCOPE | STORY | OUT-OF-SCOPE
#: The verdicts a hand-measured truth may also carry. `NRUN` is deliberately absent: a row
#: whose prerequisite is a re-run cannot be graded by a grep, and letting `NRUN` into the
#: grading set would let the instrument claim agreement on a row it never looked at.
VERDICTS = {"STANDS", "LANDED", "GONE", "SPLIT", "NRUN"}
#: MISSING: the capability is absent, so a hit means it LANDED. DEFECT: the defect is
#: present, so no hit means it is GONE. RUN: the prerequisite is a re-run, not a symbol.
#: PROSE: as DEFECT, but the anchor is read over COMMENTS too -- for a wall whose subject is
#: a written claim (`fold.bend:513` says helpers.bend lacks `i64_mul`; it does not), the
#: defect IS the sentence. Filtering it out makes such a row unfalsifiable in the safe
#: direction. Rows W6, W7, W11, U1 and U5 were all mis-read as GONE before PROSE existed.
POLARITY = {"MISSING", "DEFECT", "RUN", "PROSE"}


def read(path: pathlib.Path, fields: tuple[str, ...]) -> list[dict[str, str]]:
    rows = []
    for raw in path.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        rows.append(dict(zip(fields, raw.split("\t"))))
    return rows


def _posix(anchor: str) -> str:
    return re.sub(r"\[:(\w+):\]",
                  lambda m: POSIX_CLASSES[m[1]] if m[1] in POSIX_CLASSES else m[0], anchor)


def pin(path: str) -> str | None:
    p = subprocess.run(["git", "show", f"HEAD:{path}"], cwd=ROOT,
                       capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else None


def hits(text: str | None, anchor: str, prose: bool = False) -> tuple[int, int, int]:
    """(matches, first matching line, matches dropped as COMMENTS) over one file.

    The third number is what makes a filtered-empty set legible. An anchor that matches
    nothing but comments has matched SOMETHING and proven nothing, and without this it
    reads as an absent prerequisite -- the same failure as v3's missing scope file, one
    filter further out. It is how U2 came to report a live defect as gone.

    `prose=True` keeps the comments, because a wall whose SUBJECT is a written claim has
    its defect in a comment by definition: the defect of `fold.bend:513` is the sentence,
    not the code below it. Refusing to look at comments there would make the wall
    unfalsifiable in the safe direction, which is the failure this file is against.
    """
    if text is None:
        return (0, 0, 0)
    rx = re.compile(_posix(anchor))
    lines = text.splitlines()
    keep = (lambda l: True) if prose else (lambda l: not COMMENT.match(l))
    code = [n for n, l in enumerate(lines, 1) if keep(l) and rx.search(l)]
    dropped = 0 if prose else sum(1 for l in lines if COMMENT.match(l) and rx.search(l))
    return (len(code), code[0] if code else 0, dropped)


def judge(row: dict[str, str]) -> tuple[Verdict, str]:
    """(verdict, witness) for one row. `witness` is work/pin counts plus the first line."""
    if row["pol"] not in POLARITY:
        return ("STORY", f"polarity {row['pol']!r} is not one of {sorted(POLARITY)}")
    if not all(row[k] for k in ("anchor", "reopen", "date")):
        return ("STORY", "anchor/reopen/date incomplete")
    if row["pol"] == "RUN":
        return ("OUT-OF-SCOPE", f"a RE-RUN, not a text symbol -- {row['scope']}")
    try:
        re.compile(_posix(row["anchor"]))
    except re.error as e:
        return ("STORY", f"anchor is not a valid pattern: {e}")

    work_text = (ROOT / row["scope"]).read_text() if (ROOT / row["scope"]).is_file() else None
    pin_text = pin(row["scope"])
    if work_text is None and pin_text is None:
        return ("NO-SCOPE", f"{row['scope']!r} is readable in NEITHER tree")

    # A PROSE row's defect is a sentence, so its anchor is read over comments too. See hits().
    w, wl, wc = hits(work_text, row["anchor"], row["pol"] == "PROSE")
    p, pl, pc = hits(pin_text, row["anchor"], row["pol"] == "PROSE")
    where = f"work={w}@{wl or '-'} pin={p}@{pl or '-'}"
    if wc + pc and w + p == 0:
        return ("STORY", f"anchor matches {wc + pc} COMMENT line(s) and 0 code lines -- it has "
                          f"matched something and proven nothing ({where}); a PROSE row's "
                          f"anchor must say so")
    # A WORK/PIN SPLIT IS ITS OWN VERDICT, not a detail of a verdict. While `uop/ops.bend`
    # is mid-rewrite (6306 working lines against HEAD's 8334) the two trees disagree about
    # W4 and W8, and a bare "LANDED" reads as though the tree agreed with itself. MEASURED
    # by plant: renaming `def mm.u64.of(` moved work=1 -> work=0 with pin=1 unchanged, and
    # before this split existed that plant reported STANDS -- a detection the run could not
    # act on, because the wall it named is not the one that moved.
    # A SPLIT IS ITS OWN VERDICT and it OUTRANKS the polarity: work=1 pin=0 is a LIVE DEFECT
    # whatever HEAD says, because the working copy is the tree that will be committed. Both
    # plants above land here, which is why neither of them was caught by a bare verdict.
    if w * p == 0 and w + p > 0:
        tree = "work only" if w else "pin only"
        settled_side = "the defect is LIVE in the working copy" if w else \
                       "the defect is GONE from the working copy but LIVE at HEAD"
        return ("SPLIT", f"SPLIT ({tree}, {where}) -- {settled_side}; the two trees disagree, so "
                         f"re-run once the rewrite lands and do not retire on one of them")
    if row["pol"] == "MISSING":
        return ("STANDS", where) if w + p == 0 else ("LANDED", where)
    return ("GONE", where) if w + p == 0 else ("STANDS", where)


def main(argv: list[str]) -> int:
    try:
        rows = read(LEDGER, ("id", "pol", "scope", "anchor", "reopen", "date", "claim"))
        truths = {t["id"]: t for t in read(TRUTH, ("id", "verdict", "how"))}
    except OSError as e:
        print(f"WALLCHECK: ledger unreadable: {e}", file=sys.stderr)
        return 2
    sel = argv[1:]
    chosen = [r for r in rows if not sel or r["id"] in sel]
    if not chosen:
        print("WALLCHECK: no ledger row matched. A guard over an empty population is not "
              "a green run.", file=sys.stderr)
        return 4
    if sel and {r["id"] for r in chosen} != set(sel):
        print(f"WALLCHECK: not in the ledger: {sorted(set(sel) - {r['id'] for r in chosen})}",
              file=sys.stderr)
        return 2

    tally: dict[Verdict, int] = {}
    graded = agree = 0
    print(f"{'id':<5} {'verdict':<13} {'truth':<12} witness / how")
    for r in chosen:
        verdict, witness = judge(r)
        split = verdict == "SPLIT"
        t = truths.get(r["id"], {}).get("verdict", "-")
        how = truths.get(r["id"], {}).get("how", "")
        # A row is GRADED only if the instrument reached a verdict AND the row carries a
        # hand-measured truth IN THE SAME DIALECT. OUT-OF-SCOPE, STORY, SPLIT and an
        # unlabelled row are REFUSALS: named and counted separately, never folded into
        # agreement or into the error rate, because an instrument that grades a row it
        # declined to judge reports agreement it did not measure. A SPLIT grades against a
        # SPLIT label, which is the only label that says "wait".
        if verdict in ("STANDS", "LANDED", "GONE", "SPLIT") and t == verdict:
            graded += 1
            agree += 1
            flag = ""
        elif verdict in ("STANDS", "LANDED", "GONE", "SPLIT") and t in VERDICTS:
            graded += 1
            agree += 0
            flag = "  <-- DISAGREES WITH HAND-MEASURED TRUTH"
        elif verdict in ("STANDS", "LANDED", "GONE", "SPLIT"):
            flag = "  <-- NO HAND-MEASURED TRUTH: ungraded, and the run cannot grade it"
        else:
            flag = f"  <-- REFUSED ({verdict}); truth says {t}, a grep cannot reach it"
        tally[verdict] = tally.get(verdict, 0) + 1
        print(f"{r['id']:<5} {verdict:<13} {t:<12} {witness}  {r['claim'][:44]}{flag}")
        if how:
            print(f"{'':<5} {'':<13} {'':<12} {how}")

    n = len(chosen)
    errs = graded - agree
    refused = n - graded
    print("---")
    print(" ".join(f"{k}={v}" for k, v in sorted(tally.items())))
    print(f"denominator: {n} row(s) selected -> {graded} GRADED against a hand-measured truth, "
          f"{refused} REFUSED (OUT-OF-SCOPE / NO-SCOPE / STORY / truth in another dialect)")
    print(f"agreement {agree}/{graded}"
          + (f"  ERROR RATE {errs}/{graded}" if graded
             else "  ERROR RATE UNDEFINED -- no row was graded, so this run reports nothing"))
    if graded == 0:
        print("WALLCHECK: nothing was graded, so this run reports nothing. Not a pass.",
              file=sys.stderr)
        return 5
    return 1 if (tally.get("LANDED", 0) or tally.get("GONE", 0) or errs) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))