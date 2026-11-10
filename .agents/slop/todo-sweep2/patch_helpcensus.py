#!/usr/bin/env python3
"""TICK `HELPCENSUS`'s ONE OPEN ITEM, WITH ITS MEASUREMENT.

⇒ **THE ITEM'S CLAIM WAS "**STILL LIVE**", AND IT IS NOT: ALL FOUR NAMED SITES WERE FIXED IN
`3313ac76f` ("ARGV: 3 OF THE 4 REMAINING SITES STATE THEIR CONTRACT, AND THE 4TH IS A
DIFFERENT SHAPE"), WHICH IS AN ANCESTOR OF HEAD.** THE ITEM'S OWN TEXT NAMES THE TWO LINES
THAT ARE STILL THERE (`gates/amd_dsl_census-mutate.py:371` and `:379`), AND **THEY ARE STILL
THERE -- AND THE CRASH SITE IS STRUCTURALLY UNREACHABLE BECAUSE THE CONTRACT IS STATED
BEFORE THE SELECTION**, WHICH IS THE REMEDY `16220ac10` PROVED.

⇒ **⇒ AND THE ITEM ALSO SAID "OUT OF GRANT, REPORTED NOT TOUCHED" -- SO A LATER UNIT TOOK
THE GRANT.** THE ITEM IS A **RECORD OF A HANDOFF**, AND THE HANDOFF WAS COMPLETED.

⇒ **THE INSTRUMENT IS `.agents/slop/todo-sweep2/argvcheck.py`**, AND IT MEASURES **THE
STRUCTURAL CLAIM**, NOT "IT DID NOT CRASH TODAY":

  - `MUTATIONS_BY` is built from `MUTATIONS`, **⇒ AND IT KEYS ON `e[0].split()[0]` -- THE SAME
    TOKEN THE SELECTOR FILTERS ON (`m[0].split()[0] in argv`)**, **⇒ SO THE DOMAIN THE
    CONTRACT NAMES IS THE DOMAIN THE SELECTOR READS, AND `want` IS EMPTY **ONLY** WHEN
    `argv` IS EMPTY -- AND `not argv` IS THE `or` BRANCH THAT KEEPS EVERYTHING.**
  - **A SECOND, INDEPENDENT GUARD FIRES FIRST**: `unknown = [a for a in argv if a not in
    MUTATIONS_BY]` -> rc 3, **BEFORE** `want` IS COMPUTED.
  - `checks/graphcmp-census-audit.py`: the bare `next()` IS REPLACED BY `STATES_BY`.
  - `gates/tc_ptx_render-oracle.py`: EVERY out-of-domain selector, `--help` INCLUDED, IS
    REFUSED AT rc 3 **WITH THE SELECTORS ON STDERR** -- **⇒ AND THAT IS THE FILE's OWN OUTPUT
    CHANNEL, BECAUSE STDOUT **IS** THE ARTIFACT.**
  - `checks/coverage.py`: **A DIFFERENT SHAPE, CLASSIFIED AS ONE** -- THE ARGUMENT IS THE PATH.

⇒ **AND EVERY SITE IS RUN WITH AN OUT-OF-DOMAIN ARGUMENT, AND NONE CRASHES.** A SITE THAT
EXITS CLEANLY IS NOT PROOF THAT THE CLASS IS GONE; THE POINT IS THE **STATE EACH SITE
REPORTS**, AND A CRASH IS EXPLICITLY NOT AN ACCEPTABLE STATE.

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/patch_helpcensus.py <target-todo.md>
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

ITEM = "- [ ] **AND THE CLASS IS **ONE SHAPE**: `argv` REACHING A LOOKUP WHOSE DOMAIN DOES NOT CONTAIN `argv`.**"

EVIDENCE = """
      **⇒ PROVABLY DONE (2026-11-10), AND THE ITEM's OWN CLAIM "**STILL LIVE**" IS **FALSE**:
      ALL FOUR NAMED SITES WERE FIXED IN `3313ac76f` ("ARGV: 3 OF THE 4 REMAINING SITES STATE
      THEIR CONTRACT, AND THE 4TH IS A DIFFERENT SHAPE"), **⇒ WHICH IS AN ANCESTOR OF HEAD**
      (MEASURED: `git merge-base --is-ancestor 3313ac76f HEAD` ANSWERS YES).** **⇒ AND THE ITEM
      ALSO SAID "**OUT OF GRANT, REPORTED NOT TOUCHED**" -- SO THIS ITEM WAS A **RECORD OF A
      HANDOFF**, AND THE HANDOFF WAS COMPLETED.**
      **⇒ AND THE TWO LINES THE ITEM NAMES ARE **STILL THERE** -- `gates/amd_dsl_census-mutate.py:467`
      `want = [m for m in MUTATIONS if not argv or m[0].split()[0] in argv]` AND `:475`
      `width = max(len(m[0]) for m in want)` -- **⇒ AND THE CRASH SITE IS **STRUCTURALLY
      UNREACHABLE**, NOT MERELY UNREACHED TODAY.**
      **⇒ THE INSTRUMENT IS `.agents/slop/todo-sweep2/argvcheck.py`, AND IT MEASURES **THE
      STRUCTURAL CLAIM**, NOT "IT DID NOT CRASH TODAY":**
      - **`MUTATIONS_BY` IS BUILT FROM `MUTATIONS` AND KEYS ON `e[0].split()[0]` -- THE SAME
        TOKEN THE SELECTOR FILTERS ON (`m[0].split()[0] in argv`).** **⇒ SO THE DOMAIN THE
        CONTRACT NAMES **IS** THE DOMAIN THE SELECTOR READS, AND `want` IS EMPTY **ONLY** WHEN
        `argv` IS EMPTY -- AND `not argv` IS THE `or` BRANCH THAT KEEPS EVERYTHING.**
      - **A SECOND, INDEPENDENT GUARD FIRES FIRST**: `unknown = [a for a in argv if a not in
        MUTATIONS_BY]` -> rc 3, **BEFORE** `want` IS COMPUTED (MEASURED BY THE ORDER OF THE TWO
        `str.find` CALLS IN THE INSTRUMENT).
      - **`checks/graphcmp-census-audit.py`: THE BARE `next()` IS REPLACED BY `STATES_BY`.**
      - **`gates/tc_ptx_render-oracle.py`: EVERY OUT-OF-DOMAIN SELECTOR, `--help` INCLUDED, IS
        REFUSED AT rc 3 WITH THE SELECTORS ON STDERR** -- **⇒ AND THAT IS THE FILE's OWN OUTPUT
        CHANNEL, BECAUSE STDOUT **IS** THE ARTIFACT** (`... > /tmp/pyall.rows`, THEN `diff`),
        **⇒ SO A `--help` EXITING 0 HAVING WRITTEN NOTHING TO STDOUT WOULD BE THE `SILENT`
        SHAPE `gates/help-census.py` ALREADY HAS TWO ROWS OF.**
      - **`checks/coverage.py`: A DIFFERENT SHAPE, CLASSIFIED AS ONE** -- THERE IS NO LOOKUP
        TABLE; THE ARGUMENT **IS** THE PATH.
      **⇒ AND EVERY SITE IS RUN WITH AN OUT-OF-DOMAIN ARGUMENT AND **NONE CRASHES**: MEASURED
      `--help` -> rc 0 (A USAGE LINE) OR rc 3 (A REFUSAL NAMING THE DOMAIN), AND AN UNKNOWN
      LABEL -> rc 3. **⇒ A SITE THAT EXITS CLEANLY IS NOT PROOF THAT THE CLASS IS GONE; THE
      POINT IS THE **STATE EACH SITE REPORTS**, AND A CRASH IS EXPLICITLY NOT AN ACCEPTABLE
      STATE.** **⇒ AND THE INSTRUMENT'S FIRST VERSION REPORTED A DEFECT THAT WAS NOT THERE:
      IT GREPPED THE WHOLE FILE FOR THE OLD `next()` FORM AND MATCHED **THE FILE's OWN COMMENT
      RECORDING THE FIX** -- **⇒ SO THE CHECK IS OVER THE **CODE LINES ONLY** (COMMENT LINES
      DROPPED), WHICH IS THE CLASS THIS LEDGER KEEPS FINDING.**"""


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
