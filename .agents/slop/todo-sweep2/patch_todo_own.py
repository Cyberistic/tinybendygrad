#!/usr/bin/env python3
"""APPLY **MY OWN** LEDGER EDITS TO THE **HEAD** VERSION OF `.agents/TODO.md`.

WHY THIS EXISTS. `.agents/TODO.md` IS THE HIGHEST-TRAFFIC SHARED FILE IN THE TREE AND
FIVE OTHER AGENTS ARE EDITING IT RIGHT NOW. `git commit --only -- .agents/TODO.md` COMMITS
THE FILE's **CURRENT BYTES**, so committing it while another unit's uncommitted edit is in
the working tree **SWEPS THEIR WORK INTO MY COMMIT** -- which is the hazard `AGENTS.md`'s
`GITINDEX` section names, one level down from the index.

SO THE MOVE IS: **TAKE THE HEAD VERSION, APPLY **ONLY** MY OWN PATCHES TO IT, COMMIT
   THAT, AND THEN PUT THE OTHER UNIT's WORKING-TREE VERSION BACK.** Their bytes are
   restored verbatim, so their work is neither committed by me nor lost by me.

AND EVERY PATCH BELOW IS MATCHED BY **THE ITEM's OWN TEXT**, NEVER BY A LINE NUMBER,
BECAUSE A LINE NUMBER MOVES WHEN ANOTHER UNIT INSERTS A LINE ABOVE IT.

AND EVERY PATCH DOES EXACTLY TWO THINGS TO AN ITEM: **CHANGE `- [ ]` TO `- [x]`** AND
**APPEND THE EVIDENCE BELOW THE ITEM's OWN BODY.** NO ITEM's EXISTING WORDS ARE REWRITTEN
AND NO ITEM IS DELETED.

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/patch_todo_own.py <target-todo.md>
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# ---- THE MSGDIFFQ ITEMS -------------------------------------------------------------------
MSGDIFFQ = [
    (
        "- [ ] **THE REPO IS RED AT REST AND IT IS THE GATE'S BLIND SPOT, NOT A BAD MESSAGE.**",
        """
      **IMPLEMENTED (`1a21a25b1`). MEASURED AFTER: `8ec4631fa79` READS `PASS: 8ec4631fa79 --
      0 deletion claims checked, 4 uncheckable`, AND A BARE RUN ON HEAD READS `PASS: HEAD --
      0 deletion claims checked, 0 uncheckable`.** **AND THE FOUR THAT REFUSED ARE ALL FOUR
      OF A CLASS, NOT FOUR INCIDENTS:** `8ec4631fa79` (`11 files changed`), `ee517b8191b` (the
      same figure), `951e589231d` (`435 changed files` AND `delete mode 100644
      gates/README.md`), `6ed4e1c1e55` (`6141 FILES DELETED`) -- **ALL FOUR READ `PASS` NOW,
      AND ALL FOUR BY THE SAME MECHANISM.** **AND THE GATE's OWN PLANT STILL PASSES:
      `--plant: all states OK`, AND THE TEN REAL STEM LEDGER ROWS ALL RE-DERIVE WITH A BROKEN
      ROW DISCHARGING NOTHING.**""",
    ),
    (
        "- [ ] **THREE COMMITS IN A ROW, WHICH IS WHAT MAKES IT A CLASS AND NOT AN INCIDENT:**",
        """
      **PROVABLY DONE (`1a21a25b1`). MEASURED: `c7ad2ac4d` READS `PASS` (IT IS THE REAL
      DEFECT AND IT WAS REVERTED, SO THE GATE STILL EARNS ITS KEEP), AND `ee517b8191b` AND
      `8ec4631fa79` READ `PASS` -- **AND THE CLASS IS **FOUR**, NOT THREE: A WALK OF THE
      COMMITS SINCE `2026-10-06T12:00` OVER THE GATE's OWN `COUNT` REGEX FINDS **6** PHRASES IN
      **4** COMMITS, SO THE GATE's OWN DOCSTRING CLAIM "ZERO such phrases" IS **FALSE** -- AND
      THE DOCSTRING IS WHAT SAYS THE LANE IS DORMANT.** (THE TWO THE WALK ADDS ARE
      `6ed4e1c1e55`'s `6141 FILES DELETED` AND `951e589231d`'s `435 FILES CHANGED`, BOTH
      UPPERCASE, AND `COUNT` IS `re.I`.)**""",
    ),
    (
        "- [ ] **THE INSTRUMENT CANNOT TELL A QUOTATION FROM A SELF-DESCRIPTION.**",
        """
      **IMPLEMENTED (`1a21a25b1`). THE LEDGER IS `gates/msgdiff-quote-ledger.rows`, BESIDE THE
      GATE AND IN GIT, AND IT IS THE **SECOND** LEDGER AFTER `gates/msgdiff-stem-ledger.rows` AND
      IT CARRIES THE **SAME** DISCIPLINE.** **AND THE CLAIM IS **MECHANICAL**, NOT PROSE: A ROW
      IS `(sha, kind, value, other, reason)` AND THE GATE'S CHECK IS **ONE COMPARISON AGAINST
      THE QUOTED COMMIT's OWN DIFF** -- `file-count` ASKS WHETHER THAT COMMIT'S DIFF CHANGES
      EXACTLY `value` FILES, AND `path-deleted` ASKS WHETHER IT **DELETES** `value` UNDER THE
      SAME `-M` RENAME DETECTION THE DELETION LANE USES. THE `reason` COLUMN IS **NEVER READ**,
      SO A ROW CANNOT EXCUSE A COMMIT BY ASSERTING A REASON THE TREE DOES NOT BEAR OUT: A ROW
      NAMING A COMMIT THAT IS NOT IN THE REPOSITORY, OR WHOSE DIFF DOES NOT CARRY THE VALUE,
      **DISCHARGES NOTHING AND THE REFUSAL STANDS.** **ALL THREE FIGURES RE-DERIVE EXACTLY:
      `c7ad2ac4d` -> 11 FILES CHANGED, `591f6b499` -> 435 FILES CHANGED, `813bbec3e` -> 6141
      FILES DELETED; AND `591f6b499` DELETES `gates/README.md` WHILE `951e589231d` DOES NOT
      TOUCH IT AT ALL.** **AND A CLAIM IN THE **SUBJECT** IS NEVER A QUOTATION -- A SUBJECT
      DESCRIBES ITS OWN COMMIT -- AND THE GATE ENFORCES THAT BY THE CLAIM's OWN POSITION, NOT
      BY A MESSAGE-WIDE TEST.**""",
    ),
    (
        "- [ ] **THE CHEAP ALTERNATIVE IS A MESSAGE CONVENTION:**",
        """
      **PROVABLY OBSOLETE, AND THE REASON IS THE LEDGER LANDED: THE GATE's REGEX **CAN** NOW
      SCOPE A COUNT TO THE ENCLOSING COMMIT, BECAUSE THE LEDGER SAYS WHICH COMMIT THE FIGURE IS
      **ANOTHER'S** AND THE GATE CHECKS THAT COMMIT's OWN DIFF. THE CONVENTION IS THEREFORE NOT
      ONLY UNNECESSARY, IT IS **OBSOLETE**: A MESSAGE THAT QUOTES A FIGURE NOW PASSES WITHOUT
      GIVING THE FIGURE UP, AND `951e589231d` -- WHICH QUOTED **TWO** FIGURES IN ONE SENTENCE --
      IS THE PROOF.** **AND THE FIGURE IS THE THING THE MESSAGE IS FOR, SO THE LEDGER IS
      STRICTLY BETTER THAN THE CONVENTION, WHICH IS WHAT THE ITEM SAID IT WOULD BE.**""",
    ),
    (
        "- [ ] **THE DEFAULT INDEX'S GAP WIDENS WITH EVERY OUT-OF-BAND COMMIT, MEASURED.**",
        """
      **STILL REAL, AND IT IS NOT MINE: THE ITEM SAYS SO ITSELF, AND THE INDEX IS A SHARED
      WRITABLE PATH THAT FIVE OTHER AGENTS HOLD. THE FIX IS THE ONE `AGENTS.md` RECORDS AS THE
      MEASURED-SAFE FORM (`git commit --only` WITH AN EXPLICIT PATHSPEC), AND EVERY COMMIT THIS
      SWEEP MADE USED IT.** **AND IT IS A DIFFERENT CLASS FROM THE FOUR ABOVE: THE INDEX IS
      NOT A GATE THAT CANNOT RUN, IT IS A SHARED RESOURCE, AND A ROW THAT CANNOT GO RED IS
      NOT THE PROBLEM HERE -- A ROW THAT IS RIGHT AND CANNOT BE CHANGED IS.**""",
    ),
]

# ---- THE FIXTUREOWN ITEMS ----------------------------------------------------------------
FIXTUREOWN = [
    (
        "- [ ] **THE LINE IS A PLANT FIXTURE, NOT CODE.**",
        """
      **PROVABLY DONE. MEASURED 2026-11-10: THE NEEDLE IS NOW A **NAMED CONSTANT**,
      `checks/cites-census.py:187` `NEEDLE_OFFREPO_ROOT = "pathlib.Path(__file__).resolve().parents[3]"`,
      AND IT IS USED AT `:844` IN THE FIXTURE TABLE -- **AND THE GATE's OWN HEADER SAYS WHY
      EXACTLY: "A BARE LITERAL IS NOT COLLECTED AND A NAMED ONE IS."** **AND
      `gates/gates-pop.py --ledger check` NO LONGER NAMES `checks/cites-census.py` AT ALL.**""",
    ),
    (
        "- [ ] **THE RULE ALREADY EXISTS AND THIS FILE IS NOT COVERED BY IT.**",
        """
      **PROVABLY DONE, AND THE MECHANISM IS EXACTLY WHAT THE ITEM ASKED FOR: A **PER-FILE
      REGISTRY**, `gates/gates-pop.py:801` `FIXTURE_NAMES_BY_FILE = {"checks/cites-census.py":
      ("NEEDLE_OFFREPO_ROOT",)}`, READ BY `_fixtures_for(p)` (`:806`), WHICH **APPLIES THE BLANK
      SET ONLY WHEN THE FILE BEING READ IS THE OWNING FILE** -- **AND THE OWNERSHIP IS BY
      **PATH**, NOT BY A REGEX OVER THE SOURCE, WHICH IS THE SHAPE 670 OF 675 FILES SATISFIED AND
      NO GATE NAMED.** **MEASURED: THE FALSE POSITIVE IS GONE -- `gates-pop.py --ledger check`
      PRINTS `checks/cites-census.py  py-main  root=OK  asserts=NO  ROOT =
      Path(__file__).resolve().parents[1]`.**""",
    ),
    (
        "- [ ] **AND `checks/cites-census.py` IS NOT IN FLIGHT**",
        """
      **PROVABLY OBSOLETE, AND THE ITEM PREDICTED ITS OWN OBSOLESCENCE: THE FIX LANDED IN
      `71a58399f` ("the LAST gate that computed a root OUTSIDE the repo, and it was a NEEDLE the
      matcher is tested against"), WHICH IS AN ANCESTOR OF HEAD, **SO THE "NOT IN FLIGHT"
      PREMISE WAS TRUE AT THE TIME AND IS NO LONGER THE POINT -- THE FINDING IS FIXED IN GIT.**
      **AND THE CLASS IS NOT GONE, IT MOVED: MEASURED 2026-11-10, `gates-pop.py --ledger check`
      STILL PRINTED **ONE** `RESOLVES OUTSIDE` -- **AND IT WAS A **DIFFERENT** FILE, AND A
      REAL DEFECT: `gates/e2estage8-stage-legacy.py:28` `ROOT = Path(__file__).resolve().parents[3]`,
      A FILE THAT USED TO BE `.agents/slop/e2estage8/verdicts.py` (WHERE `parents[3]` WAS THE REPO
      ROOT) AND WAS MOVED TO `gates/` **WITHOUT** ITS CONSTANT.** **FIXED IN `1a21a25b1`: THE
      ROOT IS `HERE.parent` NOW, AND THE INSTRUMENT **IS ALIVE** -- IT HAD BEEN **DEAD OVER 0
      ROWS**, RAISING `FileNotFoundError: '/Users/cyberistic/src/.agents/slop/e2epy/artifacts/
      live.port.out'` -- AND IT READS `7 stage(s) emitted, 1 retired` WITH ALL THREE READERS
      AGREEING, rc=0, **AND IT IS FALSIFIABLE: PLANTING THE TRANSCRIPT BY REMOVING STAGE 5's
      DENOMINATOR ROW PRINTS `DENOMINATOR FAIL: stage 5: EMITTED, verdict PASS, and no denominator
      counted` AND EXITS 1.** **AND `gates-pop.py --ledger check`'s `RESOLVES OUTSIDE` FINDING
      IS NOW **GONE** -- THE POPULATION HAS **ZERO** OFF-REPO ROOTS.**""",
    ),
]

# ---- THE RNGCMP ITEMS ---------------------------------------------------------------------
RNG_ITEM1 = """
      **STILL REAL, AND THE MEASUREMENT BELOW SAYS WHY IT CANNOT BE CLOSED BY A RENAME. THE
      ORACLE HAS **TWO** PRE-PIN DEPENDENCIES, NOT ONE: `rtag()` **AND `u.tag`** -- `sig()` AT
      `gates/rng_graph_census-oracle.py:95-98` PRINTS `t={tagnm(u.tag)}`, **AND `u.tag` DOES
      NOT EXIST AT THE PIN EITHER.** MEASURED 2026-11-10:
      `.venv/bin/python -c "from tinygrad.uop.ops import UOp; print(hasattr(UOp,'rtag'),
      hasattr(UOp.const(3),'tag'))"` READS **`False False`**, AND THE ORACLE's `world()` RAISES
      `AttributeError: 'UOp' object has no attribute 'rtag'` WHEN CALLED DIRECTLY (MEASURED BY
      LOADING THE MODULE BY PATH AND CALLING `world()` -- **SO THE FAILURE IS REPRODUCIBLE
      WITHOUT THE SUBSTRATE, AND THE SUBSTRATE IS NOT NEEDED TO SEE IT**).**
      **AND THE GATE'S CURRENT `REFUSED` IS A **DIFFERENT** DEFECT RIGHT NOW, AND IT IS
      **TRANSIENT**: IT READS `rc=3`, "bend said: ... a declared constructor (unknown:
      ../tinybendygrad/uop/ops.DRng)" -- **AND `tinybendygrad/uop/ops.bend` HAS AN
      **UNCOMMITTED** 4,616-LINE DELETION IN THE WORKING TREE (MEASURED:
      `git diff --numstat -- tinybendygrad/uop/ops.bend` READS `1252  4616`), AND THE FILE WAS
      MODIFIED **NINE SECONDS** BEFORE I MEASURED IT -- **SO THAT REFUSAL IS ANOTHER UNIT's
      IN-FLIGHT REFACTOR, NOT THIS GATE.** THE `rtag` REFUSAL IS THE ONE THAT MATTERS.**"""

RNG_ITEM2 = """
      **PROVABLY DONE (2026-11-10), AND THE ANSWER IS THE OPPOSITE OF THE ITEM's HOPE, AND
      THAT IS THE FINDING.** **THE PORT **DOES** HAVE A "TAGGED COPY" CONCEPT, AND IT IS
      LOAD-BEARING, AND UPSTREAM AT THE PIN **DOES NOT** HAVE ONE AT ALL.**
      **THE INSTRUMENT IS `.agents/slop/todo-sweep2/tagpin.py` (16 READINGS, ALL AS PREDICTED)
      AND IT ANSWERS THE QUESTION IN BOTH DIRECTIONS:**
      - **UPSTREAM AT THE PIN HAS NO `tag`:** `pin ops.py has a tag FIELD` **NO**,
        `has def rtag(` **NO**, `has def tagstr(` **NO**, `names tag in the intern key` **NO**.
      - **UPSTREAM DELETED IT, AND THE COMMIT IS AN ANCESTOR OF THE PIN:**
        **`fb518b44e` "delete UOp.tag [pr] (#18954)", 2026-10-21, IS AN ANCESTOR OF `f5ac54685074`
        (MEASURED: `git merge-base --is-ancestor fb518b44e f5ac54685074` ANSWERS YES).** THAT
        COMMIT REMOVED `UOp.tag`, `UOp.rtag`, `UOp.tagstr`, **AND `tag` FROM THE INTERN KEY** --
        `(op, src, arg, tag, type(arg))` -> `(op, src, arg, type(arg))` -- **SO THE TAG WAS
        NOT AN OPTIONAL FIELD AT THE PIN, IT WAS NOT PART OF THE KEY AT ALL.**
      - **UPSTREAM's `rangeify.py` AT THE PIN HAS NO TAGGING STEP:** `pm_add_range_tags` **NO**,
        `pm_add_param_range_tags` **NO**, `calls .rtag(` **NO**. AND `get_rangeify_map` RUNS
        `pm_add_buffers` THEN `split_kernels` -- **AND `pm_renumber_range` (`:319`) HAS NO
        TAG GUARD, WHERE THE PORT's `renumber_range` HAS ONE.**
      - **THE PORT HAS IT, ACROSS NINETEEN FILES:** `port ops.bend declares type Tag is Data:`
        **YES**, `defines eq_tag` **YES**, `defines sg.tag` **YES**, `port rangeify.bend
        defines rf_rtag` **YES**, `defines rf_param_rtag` **YES**. MEASURED: `grep -rn 'Tag\b'
        tinybendygrad/ --include='*.bend'` ANSWERS **76** OCCURRENCES IN **19** FILES.
      **AND THE CONSEQUENCE, WHICH IS THE POINT: **THE ORACLE CANNOT BE REPAIRED BY A RENAME.**
      THE ORACLE MIRRORS THE PORT's FIXTURE **INDEX FOR INDEX** (`world()`'s DOCSTRING SAYS
      "THE PORT'S FIXTURE, node for node"), AND THE PORT's FIXTURE HAS **FOUR** TAGGED COPIES
      (`r0t` `pgt` `pat` `rgt`) THAT **PIN-CPYTHON CANNOT BUILD** -- **SO THE ORACLE CANNOT
      PRODUCE THE PORT's FIXTURE AT ALL, AND A FIXTURE THAT CANNOT BE BUILT IS A LANE THAT
      MEASURES NOTHING.** **AND THE PORT's SIDE IS **NOT** THIS SWEEP's: REMOVING `Tag` IS A
      NINETEEN-FILE REFACTOR, AND THE PORT'S `rangeify.bend` PORTS A RULE UPSTREAM DELETED --
      `pm_add_param_range_tags` -- WHICH IS A **PORT/PIN DIVERGENCE** AND IS THE `rangeify`
      LANE's TO SETTLE.**"""

RNG_ITEM3 = """
      **PROVABLY DONE (2026-11-10), AND IT IS NOW A **MEASUREMENT** RATHER THAN A CLASS
      STATEMENT: THE THREE SECTIONS NAME `rangeify` IN BOTH DIRECTIONS, **AND THE FOURTH
      THING THAT WAS NEVER ASKED -- "CAN THE GATE OVER THAT FILE RUN AT ALL" -- HAS NOW BEEN
      ASKED, AND THE ANSWER IS NO, WITH A PIN CITATION: `fb518b44e` REMOVED `UOp.tag` FROM
      UPSTREAM AND `f5ac54685074` HAS NO `rtag`, NO `tag` FIELD, AND NO `tag` IN THE INTERN
      KEY.** **AND THE CLASS IS GENERAL, AND IT IS WORTH NAMING IN ITS OWN RIGHT: A SECTION
      THAT AUDITS A FILE's MARKERS, A SECTION THAT FIXES AN INSTRUMENT's BLINDNESS, AND A
      SECTION THAT NAMES A GATE OVER THAT FILE CAN ALL BE TRUE WHILE **THE GATE IS DEAD** --
AND A GATE THAT CANNOT BUILD ITS FIXTURE IS DEAD IN A WAY THAT NO AMOUNT OF READING
      THE FIXTURE WILL REVEAL, BECAUSE THE FIXTURE IS FINE AND THE **LANGUAGE** IT IS WRITTEN
      IN NO LONGER HAS THE CONSTRUCT.**"""

RNGCMP = [
    (
        "- [ ] **`gates/rng_graph_census-oracle.py:153` CALLS `UOp.rtag(())` ON FIVE NODES",
        RNG_ITEM1,
    ),    (
        "- [ ] **AND THE PORT's SIDE IS **NOT** THE BLOCKER AND THE QUESTION IS OPEN.**",
        RNG_ITEM2,
    ),
    (
        "- [ ] **AND THE LEDGER's `WALLAUDIT` AND `MARKERFORM` SECTIONS NAME `rangeify` IN **BOTH**",
        RNG_ITEM3,
    ),
]

ALL_ITEMS = MSGDIFFQ + FIXTUREOWN + RNGCMP

# ---- THE BARS, IN THE SUMMARY TABLE, MATCHED BY THEIR OWN TEXT ----------------------------
BARS = [
    ("• MSGDIFFQ — msgdiff-gate.py REFUSES A MESSAGE THAT FAITHFULLY QUOTES...",
     "• MSGDIFFQ — msgdiff-gate.py REFUSES A MESSAGE THAT FAITHFULLY QUOTES... — ████░ 4/5   80%"),
    ("• FIXTUREOWN -- gates-pop reads ANOTHER FILE'S PLANT FIXTURE as an EX...",
     "• FIXTUREOWN -- gates-pop reads ANOTHER FILE'S PLANT FIXTURE as an EX... — ██████████ 3/3  100%"),
    ("• RNGCMP -- gates/rng_graph_census-gate.py CALLS UOp.rtag, WHICH UPSTRE...",
     "• RNGCMP -- gates/rng_graph_census-gate.py CALLS UOp.rtag, WHICH UPSTRE... — ██░░░░░░░░ 2/3   67%"),
]

# THE TWO ITEMS THAT STAY OPEN, AND WHY EACH DOES.
#   THE INDEX ONE: ITS OWN TEXT SAYS SO ("NOT REPAIRED ON PURPOSE"), AND THE INDEX IS A
#     SHARED WRITABLE PATH FIVE OTHER AGENTS HOLD.
#   THE `rtag` ONE: **THE EVIDENCE THIS SWEEP APPENDED TO IT SAYS "STILL REAL"** -- AND
#     **TICKING AN ITEM WHOSE OWN EVIDENCE SAYS IT IS STILL REAL IS THE FORBIDDEN MOVE.**
# IT WAS TICKED BY MISTAKE IN `eeb4e7de9` AND UN-TICKED HERE, AND THE UN-TICK IS
#     PART OF THE PATCH SO A RE-RUN CANNOT RE-TICK IT.
KEEP_OPEN = (
    "THE DEFAULT INDEX'S GAP WIDENS WITH EVERY OUT-OF-BAND COMMIT",
    "gates/rng_graph_census-oracle.py:153` CALLS `UOp.rtag(())`",
)


def patch_items(lines):
    applied = []
    for first_line, evidence in ALL_ITEMS:
        # **THE MARKER MAY ALREADY BE `[x]`, BECAUSE A PREVIOUS COMMIT TICKED IT.** THE
        # `rtag` ITEM IS ONE: `eeb4e7de9` TICKED IT BY MISTAKE AND THIS PATCH MUST **UN-TICK**
        # IT, SO THE SEARCH IS OVER **BOTH** MARKERS AND THE ITEM'S OWN TEXT IS WHAT
        # IDENTIFIES IT, NOT ITS MARKER.
        stem = first_line[len("- [ ] "):]
        hits = [i for i, l in enumerate(lines)
                if l.startswith("- [ ] " + stem) or l.startswith("- [x] " + stem)]
        if len(hits) != 1:
            print(f"SKIP (found {len(hits)}): {first_line[:64]}")
            continue
        i = hits[0]
        j = i + 1
        while j < len(lines) and not (lines[j].startswith("- [ ] ") or lines[j].startswith("- [x] ")
                                       or lines[j].startswith("## ")):
            j += 1
        if any(k in first_line for k in KEEP_OPEN):
            # **LEAVE IT OPEN, AND UN-TICK IT IF A PREVIOUS COMMIT TICKED IT.** THE
            # APPENDMENT IS THE POINT: THE ITEM's OWN TEXT MAY SAY "STILL REAL" AND THE
            # MARKER MUST AGREE WITH IT.
            if lines[i].startswith("- [x] "):
                lines[i] = "- [ ] " + lines[i][len("- [x] "):]
        else:
            if lines[i].startswith("- [x] "):
                # ALREADY TICKED: THE EVIDENCE IS APPENDED AND THE MARKER IS LEFT ALONE.
                pass
            else:
                assert lines[i].startswith("- [ ] "), lines[i][:40]
                lines[i] = "- [x] " + lines[i][len("- [ ] "):]
        # **THE PATCH MUST BE IDEMPOTENT.** A RE-RUN OVER A FILE THAT ALREADY CARRIES THE
        # EVIDENCE MUST NOT APPEND IT AGAIN -- **AND THE FIRST VERSION DID, SO THE
        # EVIDENCE WAS DUPLICATED IN THE COMMITTED FILE.** THE TEST IS THE EVIDENCE's OWN
        # FIRST LINE, WHICH IS LONG AND UNIQUE.
        first_ev = evidence.strip("\n").split("\n")[0].strip()
        if first_ev and any(first_ev in l for l in lines[i:j]):
            applied.append("SKIP dup " + first_line[:58])
            continue
        body = ["      " + line.strip() if line.strip() else "" for line in evidence.strip("\n").split("\n")]
        lines[j:j] = body
        applied.append(("OPEN " if any(k in first_line for k in KEEP_OPEN) else "TICK ") + first_line[:58])
    return lines, applied


def patch_bars(lines):
    applied = []
    for old, new in BARS:
        hits = [i for i, l in enumerate(lines) if l.startswith(old)]
        if len(hits) != 1:
            print(f"BAR SKIP (found {len(hits)}): {old[:64]}")
            continue
        lines[hits[0]] = new
        applied.append("BAR " + old[:44])
    return lines, applied


def main():
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else (ROOT / ".agents/TODO.md")
    lines = target.read_text().split("\n")
    lines, items = patch_items(lines)
    lines, bars = patch_bars(lines)
    target.write_text("\n".join(lines))
    print(f"patched {len(items)} items and {len(bars)} bars in {target}")
    for a in items + bars:
        print("  ", a)


if __name__ == "__main__":
    main()
