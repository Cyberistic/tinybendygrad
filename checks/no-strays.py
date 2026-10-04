#!/usr/bin/env python3
"""Refuse a stray at the repository root. `checks/no-strays.py`

WHAT IT CLAIMS, with its denominator: every FILE at the repository root is either named in
`ROOT_ENTRIES` or is explained by this script, and the count of unexplained files is printed
beside the count of root files. Exit 0 only when that count is zero.

WHY IT IS A GATE AND NOT A TIDY RULE.  Four strays accumulated at the root on one day and
three of them had the same cause, which no directory-organising rule would have caught:

    after.txt   33 KB   80 lines, all `/var/folders/...`   <- a `find` listing of a $TMPDIR tree
    before.txt 114 KB  284 lines, all `/var/folders/...`   <- ditto, the before half
    closure.txt  14 KB                                    <- ditto, a third copy of the listing
    .err          0 bytes                                 <- a redirect target that never filled

`after`/`before`/`closure` were ONE gate's output, written three times, at the root, because
`find "$T" > after.txt` had no path discipline. `bf_base_tmp.c` was a port file copied out to
the root by `sed`. So the two failure modes are:

  1. a NAME this project uses for scratch, and
  2. CONTENT that is a listing of a `$TMPDIR` path -- which is debris from a machine, not a
     fact about this repository, and is unreadable on any other machine.

Mode 2 is not what the allowlist misses -- MEASURED, after I first wrote this file claiming it
was: the allowlist catches `listing-of-the-closure.txt` by name, and catches it correctly. What
the allowlist cannot catch is a name ADDED TO THE ALLOWLIST, because this guard's own message
invites that ("add it to ROOT_ENTRIES deliberately") and nothing then looks at the content again.
So the content test's job is to survive its own allowlist: a `$TMPDIR` listing stays a stray even
after somebody has blessed its name.

MEASURED, both directions, on this tree:
    innocent name + 100% $TMPDIR lines  -> caught BY CONTENT ("100% of its lines are ...")
    scratch name  + one hand-written line -> caught BY NAME    ("name is a scratch name")
**AND THE CORRECTION MATTERED: MY FIRST VERSION OF THIS DOCSTRING SAID THE NAME TEST COULD NOT
CATCH MODE 2. IT CAN. THE CLAIM WAS WRONG IN THE DIRECTION THAT MAKES A GUARD LOOK STRONGER THAN
IT IS, WHICH IS THE ONLY DIRECTION THAT IS SAFE TO BE WRONG IN AND ALSO THE ONLY ONE THAT HIDES A
GAP.**

WHAT IT DELIBERATELY DOES NOT DO.  It does not delete anything, and it does not judge DIRECTORIES
by name -- 33 directories are listed here and a new one should be added deliberately rather than
discouraged. A guard that makes adding a directory annoying gets a directory added to the
allowlist without being looked at, which is the same failure as an unenforced pin.

ONE THING THIS FILE GOT WRONG FIRST, because the correction is the useful part.  Deciding what
"a report cites" by matching the bare basename reported 6 citers for a ZERO-BYTE `.err` and 89
for a file named `bend`. Every one was a substring hit inside a longer word -- `.err` inside
`.error`, `bend` inside `bender`. **That is the third time this project has made that mistake**
(`_cleanup/classify.py` reported 3,574 false citations for the same reason). So a citation here
must be a WHOLE PATH TOKEN, matched by `WORD`, never `in`.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Measured 2026-10-05, after the four strays above were cleared. Every entry is real project
# structure. `sz.py` is the one that looks wrong: it is COMMITTED and four reports cite it, so
# it stays until its owner decides where it belongs -- a guard is not a reorganisation.
ROOT_ENTRIES = set("""
    .agents .coveragerc .git .github .gitignore .jj .pre-commit-config.yaml .pylintrc .venv
    AGENTS.md bin checks conftest.py docs examples extra langs LICENSE mkdocs.yml opencode.json
    probe pyproject.toml README.md references runs serve_docs.sh spec sz.py test tinybendygrad
    tinygrad tinygrad.egg-info tools uv.lock
""".split())

# Scratch names this project actually uses. A file at the root with one of these is debris
# whatever it contains, because the root is not where a run's output belongs.
SCRATCH_NAME = re.compile(
    r"(^\.|\.(err|out|tmp|bak|orig|rej|swp)$|~$|\.staged-(mem|blob)-|^\.|^_)"
    r"|^(before|after|baseline|closure)\.[a-z]+$"
    r"|(^|[-_.])(tmp|temp|scratch|workdir|probe|dump)([-_.]|$)")

# A listing of a machine-local path. `find $TMPDIR > f` writes exactly this and it means nothing
# to anyone else. Requiring MOST lines to be machine-local keeps an ordinary report from being
# caught by one stray path in prose.
MACHINE_PATH = re.compile(r"(/var/folders/|/private/var/folders/|/tmp/[A-Za-z0-9_.-]+/)")
MIN_BLOB_RATIO = 0.6


def root_files() -> list[Path]:
    return sorted(p for p in ROOT.iterdir() if p.is_file() and p.name not in ROOT_ENTRIES)


def machine_path_ratio(text: str) -> float:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return 0.0
    return sum(1 for ln in lines if MACHINE_PATH.search(ln)) / len(lines)


def cited_by_a_report(path: Path) -> list[str]:
    """Committed files naming this path, matched as a WHOLE PATH TOKEN.

    `git grep -F <name>` is a substring match and is how six reports 'cited' a zero-byte `.err`.
    The boundary class keeps `.err` from matching inside `.error` and `bend` inside `bender`.
    """
    r = subprocess.run(
        ["git", "grep", "-l", "-E",
         rf"(^|[^A-Za-z0-9_./-]){re.escape(path.name)}([^A-Za-z0-9_-]|$)", "--", "*.md"],
        cwd=ROOT, capture_output=True, text=True)
    return [ln for ln in r.stdout.split() if ln] if r.returncode in (0, 1) else []


def main() -> int:
    all_files = [p for p in sorted(ROOT.iterdir()) if p.is_file()]
    strays = root_files()
    print(f"no-strays: {len(all_files)} files at the root, {len(ROOT_ENTRIES)} entries allowed, "
          f"{len(strays)} to explain")
    if not strays:
        print("  CLEAN: every root file is named in ROOT_ENTRIES")
        return 0

    unexplained = []
    for p in strays:
        reasons = []
        if SCRATCH_NAME.search(p.name):
            reasons.append("name is a scratch name")
        try:
            text = p.read_text(errors="replace")
        except OSError as exc:
            reasons.append(f"unreadable: {exc.strerror}")
            text = ""
        ratio = machine_path_ratio(text)
        if ratio >= MIN_BLOB_RATIO:
            reasons.append(f"{ratio:.0%} of its lines are a machine-local $TMPDIR listing")
        citers = cited_by_a_report(p)
        if reasons:
            print(f"  STRAY  {p.name:<24} {p.stat().st_size:>9d} B   {'; '.join(reasons)}")
            if citers:
                print(f"          cited by {len(citers)} report(s): {', '.join(citers[:4])}"
                      f"{' …' if len(citers) > 4 else ''}")
                print("          -> it is CITED, so MOVE it under .agents/slop/ and keep the "
                      "basename; do not delete evidence")
            unexplained.append(p)
        else:
            print(f"  new    {p.name:<24} {p.stat().st_size:>9d} B   not on the allowlist and no "
                  f"stray shape -- add it to ROOT_ENTRIES deliberately or remove it")
            unexplained.append(p)

    print(f"  {len(unexplained)} unexplained of {len(all_files)} root files")
    if unexplained:
        print("  NOT CLEAN. A root file nobody can explain is how a repo stops being navigable.")
    return 1


if __name__ == "__main__":
    sys.exit(main())