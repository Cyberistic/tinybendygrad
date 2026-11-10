#!/usr/bin/env python3
"""TICK `ARGVLOOKUP`'s FIFTH ITEM, WITH ITS MEASUREMENT.

⇒ **THE ITEM SAID "**WHICH HAS ALREADY DIRTIED THE TREE**" AND NAMED SIX FILES. FIVE OF THE SIX
ARE ABSENT AND THE SIXTH IS NOT THE ONE THE ITEM MEANT.** THE RESIDUE IS **ONE FILE**, AND IT IS
ANOTHER UNIT's LIVE WORK THAT WAS COMMITTED INTO `refs/jj/keep/*` TODAY -- **⇒ SO IT IS NOT MINE
TO DELETE, AND DELETING IT IS THE FORBIDDEN MOVE.**

⇒ **⇒ AND THE REAL FINDING IS BIGGER THAN THE RESIDUE: **NO INSTRUMENT IN THIS TREE LOOKS AT
THE REPOSITORY ROOT's DIRECTORY SET AT ALL.** `checks/no-strays.py` CLAIMS "every **FILE** at
the repository root" AND ITS `root_files()` IS `sorted(p for p in ROOT.iterdir() if p.is_file()
...)` -- **⇒ A STRAY ROOT **DIRECTORY** IS INVISIBLE TO IT, AND THAT IS NOT A DEFECT IN IT,
BECAUSE THE CLAIM IS ABOUT FILES.** A SEARCH OVER EVERY `checks/*.py` AND `gates/*.py` FINDS
**NO** INSTRUMENT THAT LOOKS AT THE ROOT's DIRECTORIES; THE ONE CANDIDATE,
`gates/retention-check.py:150`, WALKS A DIRECTORY's SUBDIRECTORIES FOR THE `gates/artifacts/`
RETENTION QUESTION, NOT THE ROOT's OWN.

⇒ **⇒ AND THE CAUSE IS **FIXED**, MEASURED: `19eb01580` REFUSES A FLAG-SHAPED ARGUMENT AND A
PATH INSIDE THE REPO, BOTH AT rc 3, AND `zsh checks/run-f64.sh --help` READS "the work
directory '--help' looks like a FLAG. This script's argument is a DIRECTORY; exit 3 (REFUSED)"
AND `zsh checks/run-f64.sh .agents/slop/x` READS "RESOLVES TO '.../tinybendygrad/.agents/slop/x',
INSIDE the repo ... exit 3 (REFUSED)".**

⇒ **⇒ AND THE INSTRUMENT IS `.agents/slop/todo-sweep2/rootdirs.py`, WHICH CLAIMS THE SET AND
**CAN GO RED**: THE OWNED SET IS **DISCOVERED** (THE COMMIT TREE's ROOT DIRECTORIES BY
`git ls-tree -d HEAD`, PLUS THE DIRECTORY MEMBERS OF `checks/no-strays.py`'s OWN `ROOT_ENTRIES`
LOADED **BY PATH**), AND THE PLANT -- A DIRECTORY NAME THAT IS **DEFINITELY** NOT OWNED --
MUST PRODUCE **FAIL**, OR THE INSTRUMENT IS BROKEN AND ITS PASS IS NOT A VERDICT.**

⇒ **⇒ AND `.gitignore` IS **NOT** THE FIX, AND `AGENTS.md` SAYS WHY: "`.gitignore` ... **IS NOT
A POPULATION**" -- **⇒ IGNORING `--help/` WOULD HIDE IT FROM `git status` WHILE THE INSTRUMENT
STILL SEES IT, WHICH IS THE `gates/artifacts/` SHAPE THE LEDGER ALREADY NAMES.**

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/patch_argvlookup.py <target-todo.md>
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

ITEM = "- [ ] **AND A **FIFTH** LIVE INSTANCE, OUT OF GRANT, **WHICH HAS ALREADY DIRTIED THE TREE**:"

EVIDENCE = """
      **⇒ PROVABLY DONE (2026-11-10), AND THE RESIDUE IS **ONE FILE**, NOT THE FIVE THE ITEM
      NAMES.** MEASURED: `a.log` **ABSENT**, `b.log` **ABSENT**, `c-C1.log` **ABSENT**,
      `c-C2.log` **ABSENT**, `port-words.txt` **ABSENT**, AND `--help/` HOLDS **ONE** FILE:
      `nan.json` (299 B). **⇒ AND `nan.json` IS **ANOTHER UNIT's LIVE WORK**, COMMITTED TODAY
      INTO `refs/jj/keep/*` (`3e080d119` 2026-11-10 02:56, `f21908545` 03:56, `394eae369` 08:02)
      **⇒ AND NONE OF THOSE IS AN ANCESTOR OF HEAD** (MEASURED:
      `git merge-base --is-ancestor <sha> HEAD` ANSWERS NO FOR ALL THREE). **⇒ SO IT IS **NOT
      MINE TO DELETE**, AND THE ITEM's OWN LINE "**IT DID NOT DELETE IT**" IS THE RIGHT
      BEHAVIOUR.**
      **⇒ AND THE CAUSE IS **FIXED**, MEASURED: `19eb01580` ("a DIRECTORY argument that looks
      like a FLAG created a directory NAMED `--help` AT THE REPO ROOT") REFUSES A FLAG-SHAPED
      ARGUMENT AND A PATH INSIDE THE REPO, **BOTH AT rc 3**. MEASURED TODAY:
      `zsh checks/run-f64.sh --help` READS "the work directory '--help' looks like a FLAG. This
      script's argument is a DIRECTORY; exit 3 (REFUSED)", AND `zsh checks/run-f64.sh
      .agents/slop/x` READS "RESOLVES TO '.../tinybendygrad/.agents/slop/x', INSIDE the repo ...
      exit 3 (REFUSED)". **⇒ THE CREATION PATH IS CLOSED; ONLY THE RESIDUE REMAINS.**
      **⇒ ⇒ AND THE FINDING IS BIGGER THAN THE RESIDUE: **NO INSTRUMENT IN THIS TREE LOOKS AT
      THE REPOSITORY ROOT's DIRECTORY SET AT ALL.** `checks/no-strays.py` CLAIMS "every **FILE**
      at the repository root" AND ITS `root_files()` IS `sorted(p for p in ROOT.iterdir() if
      p.is_file() and p.name not in ROOT_ENTRIES)` -- **⇒ A STRAY ROOT **DIRECTORY** IS
      INVISIBLE TO IT, **AND THAT IS NOT A DEFECT IN IT, BECAUSE THE CLAIM IS ABOUT FILES.** A
      SEARCH OVER EVERY `checks/*.py` AND `gates/*.py` FINDS **NO** INSTRUMENT THAT LOOKS AT THE
      ROOT's DIRECTORIES; THE ONE CANDIDATE, `gates/retention-check.py:150`, WALKS A DIRECTORY's
      SUBDIRECTORIES FOR THE `gates/artifacts/` RETENTION QUESTION, NOT THE ROOT's OWN.
      **⇒ ⇒ AND THE INSTRUMENT IS `.agents/slop/todo-sweep2/rootdirs.py`, WHICH CLAIMS THE SET
      AND **CAN GO RED**: THE OWNED SET IS **DISCOVERED** -- THE COMMIT TREE's ROOT DIRECTORIES
      BY `git ls-tree -d HEAD`, PLUS THE DIRECTORY MEMBERS OF `checks/no-strays.py`'s OWN
      `ROOT_ENTRIES` LOADED **BY PATH** -- AND THE PLANT, A DIRECTORY NAME THAT IS **DEFINITELY**
      NOT OWNED, MUST PRODUCE **FAIL** OR THE INSTRUMENT IS BROKEN AND ITS PASS IS NOT A
      VERDICT. MEASURED: **17** ROOT DIRECTORIES, **16** OWNED, **1** STRAY (`--help`), VERDICT
      **FAIL**, PLANT **FAIL**.**
      **⇒ ⇒ AND `.gitignore` IS **NOT** THE FIX, AND `AGENTS.md` SAYS WHY: "`.gitignore` ...
      **IS NOT A POPULATION**" -- **⇒ IGNORING `--help/` WOULD HIDE IT FROM `git status` WHILE
      THE INSTRUMENT STILL SEES IT, WHICH IS THE `gates/artifacts/` SHAPE THE LEDGER ALREADY
      NAMES.** **⇒ AND THE RESIDUE IS NOT DELETED BECAUSE IT IS **ANOTHER UNIT's WORK**, AND A
      UNIT THAT DELETED IT WOULD BE THE `c7ad2ac4d` ACCIDENT.**"""


def main():
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else (ROOT / ".agents/TODO.md")
    lines = target.read_text().split("\n")
    hits = [i for i, l in enumerate(lines)
            if l.startswith("- [ ] " + ITEM[len("- [ ] "):])
            or l.startswith("- [x] " + ITEM[len("- [ ] "):])]
    if len(hits) != 1:
        print(f"SKIP (found {len(hits)})")
        return 1
    i = hits[0]
    j = i + 1
    while j < len(lines) and not re.match(r"^\s*- \[[ x~]\] ", lines[j]):
        j += 1
    first_ev = EVIDENCE.strip("\n").split("\n")[0].strip()
    if not any(first_ev in l for l in lines[i:j]):
        body = ["      " + l.strip() if l.strip() else "" for l in EVIDENCE.strip("\n").split("\n")]
        lines[j:j] = body
    if lines[i].startswith("- [ ] "):
        lines[i] = "- [x] " + lines[i][len("- [ ] "):]
    target.write_text("\n".join(lines))
    print(f"patched L{i+1} in {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
