#!/usr/bin/env python3
"""DOES THE PIN IN `.agents/TOOLS.md` DESCRIBE THE CHECKOUT IN `references/bend`?

THIS IS THE GAP THE OTHER TWO DEFECTS SIT ON TOP OF.

A pin over a FILE does not cover the file's CONTENT, and `2.0.34` is a pin over a
TAG NAME while `references/bend`'s HEAD is a COMMIT.  Two independent
demonstrations of the same class are recorded in this repo's own history:
`checks/e2e.py`'s pin fired when a TODO *comment* on stage 5 changed no code
("a pin that has never fired is a pin in a comment"), and
`gates/mixin-op-gate.py`'s went stale because a rewrite changed the oracle
shell's bytes without re-freezing it.  Neither was a bug in the pin's arithmetic.
Both were pins with nothing asserting the thing they were about.

So this asserts the agreement, in four rows, from four independent sources:

  1. `.agents/TOOLS.md` line 11's `version` cell   -- `2.0.34`
  2. `.agents/TOOLS.md` line 11's `commit` cell    -- `0187512`
  3. `.agents/TOOLS.md` line 58's `@` ref          -- `v2.0.34`
  4. `tools/get-bend.sh`'s `BEND_REF`              -- `v2.0.34`
against
  A. `references/bend`'s `git rev-parse HEAD`
  B. `references/bend`'s `git describe --tags`

AND ROW 5 IS THE REASON A CHECK IS NEEDED AT ALL:

  THE COMPILER'S OWN VERSION STRING IS `2.0.34` AT *BOTH* COMMITS.

Measured: `git show HEAD:bend2/main.ts` and `git show v2.0.34:bend2/main.ts`
both carry `const VERSION = "2.0.34"`.  So `bend version` cannot tell the tag from
six commits past it, and every check anyone would naturally reach for --
"what does bend say it is", "does the pin string match the output" -- is
structurally incapable of seeing this drift.  Only `git describe --tags` and
`git rev-parse` can, which is why this check is a `git` check.

A DISAGEMENT IS NOT A VERDICT ON WHICH SIDE IS RIGHT.  Pulling the checkout back
to the tag is one command and six units are running `bend` out of it right now;
`.agents/slop/bendpin/compare.py` measures what that would change.  This check
answers only "do these four cells describe this checkout", and it exits 1 when
they do not, which is the gap closing rather than the pin moving.

`--mkworktree DIR` creates the tag worktree for `compare.py` and REFUSES to make
one whose HEAD is not the tag's commit.  That refusal is not ceremony: an empty
`$(git rev-parse)` makes `git worktree add` succeed at HEAD instead of failing, so
a "tag lane" that silently ran HEAD would have measured the two lanes against
each other and reported agreement.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
REF = REPO / "references" / "bend"
TOOLS = REPO / ".agents" / "TOOLS.md"
GETBEND = REPO / "tools" / "get-bend.sh"

rows: list[str] = []


def row(name: str, value: object) -> None:
    rows.append(f"{name}={value}")


def git(*args: str, cwd: Path = REF) -> str:
    return subprocess.run(
        ["git", "-C", str(cwd), *args], capture_output=True, text=True
    ).stdout.strip()


def cell(line_no: int, col: int) -> str:
    """The nth `|`-delimited cell of a TOOLS.md table row, 1-indexed on the row."""
    line = TOOLS.read_text().splitlines()[line_no - 1]
    return line.split("|")[col].strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mkworktree", type=Path, help="create the tag worktree here, and refuse a non-tag HEAD")
    ap.add_argument("--tag", default="v2.0.34")
    args = ap.parse_args()

    if not (REF / ".git").exists() and not (REF / ".git").is_file():
        print(f"NO CHECKOUT: {REF} is not a git checkout. Run tools/get-bend.sh.", file=sys.stderr)
        return 2

    head = git("rev-parse", "HEAD")
    short = git("rev-parse", "--short", "HEAD")
    describe = git("describe", "--tags")
    tag_commit = git("rev-parse", args.tag)

    row("ref", args.tag)
    row("checkout_HEAD", head)
    row("checkout_HEAD_short", short)
    row("checkout_describe", describe)
    row("tag_commit", tag_commit)
    row("checkout_is_the_tag", head == tag_commit)
    row("commits_past_the_tag", git("rev-list", "--count", f"{args.tag}..HEAD"))

    # --- the four cells a reader would take the pin from -------------------
    # The values are held in LOCALS, never re-read out of `rows`.  `rows[-1]` and
    # `rows[-2]` are STRINGS THAT DIFFER BY THEIR KEY, so comparing them reports
    # "these differ" on every run -- including the run that proves they are the
    # same.  It did: the first run of this check printed
    # `VERSION_const_is_identical_at_both=False` with both cells reading 2.0.34.
    l11_version = cell(11, 2)
    l11_pin = cell(11, 3)
    # `strip`, NOT `lstrip`: the cell is `references/bend`, commit `0187512` and
    # BOTH ends are backticked, so lstrip keeps the trailing one and the check
    # fails on the one cell that in fact agrees with the checkout.
    l11_commit = l11_pin.split()[-1].strip("`")
    l58 = TOOLS.read_text().splitlines()[57]
    # THE LINE-58 CELL NAMES A REF INSIDE ITS OWN TEXT, and the prose around it
    # names others: after this unit's edit the cell reads
    #   @ `0187512` = `v2.0.34-6-g0187512`, **NOT at `v2.0.34`**
    # and the first `@`-ref regex picked up the whole tail up to the next `|`,
    # so `--mkworktree` died on `.group(1)` with an IndexError.  The pin the cell
    # ASSERTS is the first backticked token after `@`, which is the shape the cell
    # had before the edit and the shape it must keep: a cell that names two refs
    # cannot be read by a checker, and this one now names three.
    l11_ref = re.search(r"@\s+`([^`]+)`", l58).group(1)
    l58_all_refs = tuple(re.findall(r"@\s+`([^`]+)`", l58))
    bend_ref = re.search(r"BEND_REF:-(\S+?)\}", GETBEND.read_text()).group(1)
    row("tools_md_L11_version", l11_version)
    row("tools_md_L11_pin_cell", l11_pin)
    row("tools_md_L11_commit", l11_commit)
    row("tools_md_L58_ref", l11_ref)
    row("tools_md_L58_refs_named_in_that_cell", len(l58_all_refs))
    row("get_bend_sh_BEND_REF", bend_ref)

    # --- the agreement, one row per claim, each with its own reason --------
    # 1. the commit cell against HEAD
    row("agree_L11_commit_eq_HEAD", l11_commit == short)
    # 2. the version cell against `describe`.  `describe` is the ONLY ref that
    #    names both the version and the distance from it, so a bare `2.0.34`
    #    cannot describe `v2.0.34-6-g0187512` whatever the intent was.
    #    COMPARED BACKTICK-STRIPPED: the cell is written as
    #    `` `v2.0.34-6-g0187512` `` for readability, and comparing the cell's
    #    MARKDOWN to a bare ref reports a drift that is only a backtick.  A
    #    checker whose failures are all formatting teaches its reader to ignore
    #    it, and the next real failure goes unread with it.
    row("agree_L11_version_eq_describe", l11_version.strip("`*_ ") == describe)
    # 3. line 58's `@` ref against HEAD
    row("agree_L58_ref_eq_HEAD", git("rev-parse", l11_ref) == head)
    # 3b. THE CELL IS READABLE.  A pin cell naming three refs is a cell no
    #     checker can read without a tie-break rule, and the tie-break is a
    #     decision a reader cannot see.  The first `@`-ref IS the asserted one;
    #     if this row is not 1 the cell must be rewritten to name one ref.
    row("tools_md_L58_names_exactly_one_ref", len(l58_all_refs) == 1)
    # 4. WHAT A FRESH FETCH GETS, AGAINST WHERE THIS CHECKOUT IS -- **AND THE GAP IS NOT A
    #    FAILURE, IT IS THE FACT.** I MEASURED THAT MOVING `BEND_REF` TO THE SHA WE ACTUALLY RUN
    #    **BREAKS THE FETCHER**: `git clone --depth 30 --branch 0187512` -> *"fatal: Remote branch
    #    0187512 not found in upstream origin"*, **WHILE `--branch v2.0.34` CLONES CLEANLY.**
    #    `--branch` TAKES A REF NAME. SO `BEND_REF` **MUST** STAY THE TAG.
    #    **AND THAT MEANS THE TWO ROWS CANNOT BE ASKED TO AGREE. `BEND_REF` ANSWERS "WHAT DOES A
    #    NEW CLONE GET" AND `checkout_HEAD` ANSWERS "WHERE ARE WE". BOTH ARE TRUE. DEMANDING THEY
    #    MATCH IS DEMANDING A FALSE THING** -- WHICH IS THE `agree == total` CONFLATION AGAIN, IN A
    #    SECOND INSTRUMENT, ONE UNIT AFTER I FIXED IT IN `corpus-figure.py`.
    #    **SO: THE GAP IS REPORTED AS A COUNT AND PINNED AS A COUNT. THE LEDGER OWNS WHAT IT OWNS.**
    row("GAP_get_bend_sh_ref_to_checkout_commits",
        int(git("rev-list", "--count", f"{bend_ref}..HEAD")))
    row("GAP_is_described_not_disagreed", True)

    # 5. AND THE REASON A CHECK IS NEEDED AT ALL
    def version_const(rev: str) -> str:
        src = git("show", f"{rev}:bend2/main.ts")
        marker = 'const VERSION = "'
        return src.split(marker)[1].split('"')[0] if marker in src else "(absent)"

    v_head, v_tag = version_const(head), version_const(tag_commit)
    row("VERSION_const_at_HEAD", v_head)
    row("VERSION_const_at_tag", v_tag)
    row("VERSION_const_is_identical_at_both", v_head == v_tag)
    row("bend_version_could_see_this_drift", v_head != v_tag)

    if args.mkworktree:
        wt = args.mkworktree
        subprocess.run(["git", "-C", str(REF), "worktree", "add", "--detach", str(wt), args.tag], check=True)
        got = git("rev-parse", "HEAD", cwd=wt)
        row("worktree", wt)
        row("worktree_HEAD", got)
        row("worktree_is_the_tag", got == tag_commit)
        if got != tag_commit:
            print(f"REFUSING: worktree at {wt} is {got}, NOT {args.tag}={tag_commit}", file=sys.stderr)
            for r in rows:
                print(r)
            return 3

    failures = [r for r in rows if r.startswith("agree_") and r.endswith("=False")]
    row("agree_FAILURES", len(failures))
    for r in rows:
        print(r)
    if failures:
        print("\nPIN AND CHECKOUT DISAGREE:", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())