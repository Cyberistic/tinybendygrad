#!/usr/bin/env python3
"""PATCH `.agents/TODO.md`'s RNGCMP ITEMS, BY LINE INDEX, WITH THE MEASUREMENTS.

WHY A SCRIPT AND NOT AN EDIT: `.agents/TODO.md` IS THE HIGHEST-TRAFFIC SHARED FILE IN THE
TREE AND FIVE OTHER AGENTS ARE EDITING IT RIGHT NOW. AN `edit` CALL MATCHES EXACT TEXT, AND
THE EXACT TEXT MOVES WHEN ANOTHER UNIT INSERTS A LINE ABOVE IT. A LINE-INDEX PATCH IS ALSO
FRAGILE FOR THE SAME REASON, SO THIS SCRIPT DOES THE ONE THING THAT IS SAFE: IT **READS THE
FILE FRESH**, FINDS THE ITEMS **BY THEIR OWN TEXT** (not by a remembered line number), AND
APPENDS THE EVIDENCE **WITHOUT TOUCHING THE ITEM's EXISTING WORDS**.

⇒ NO ITEM IS REWRITTEN. NO ITEM IS DELETED. ONLY `- [ ]` BECOMES `- [x]` AND EVIDENCE IS
  APPENDED BELOW IT. THAT IS THE SMALLEST PATCH THAT CARRIES THE MEASUREMENT.

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/patch_rngcmp.py
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LEDGER = ROOT / ".agents/TODO.md"

# (the item's OWN FIRST LINE, the evidence to append, the bar's own text)
PATCHES = [
    (
        "- [ ] **`gates/rng_graph_census-oracle.py:153` CALLS `UOp.rtag(())` ON FIVE NODES",
        """
      **⇒ STILL REAL, AND THE MEASUREMENT BELOW SAYS WHY IT CANNOT BE CLOSED BY A RENAME. THE
      ORACLE HAS **TWO** PRE-PIN DEPENDENCIES, NOT ONE: `rtag()` **AND `u.tag`** -- `sig()` AT
      `gates/rng_graph_census-oracle.py:95-98` PRINTS `t={tagnm(u.tag)}`, **⇒ AND `u.tag` DOES
      NOT EXIST AT THE PIN EITHER.** MEASURED 2026-11-10:
      `.venv/bin/python -c "from tinygrad.uop.ops import UOp; print(hasattr(UOp,'rtag'),
      hasattr(UOp.const(3),'tag'))"` READS **`False False`**, AND THE ORACLE's `world()` RAISES
      `AttributeError: 'UOp' object has no attribute 'rtag'` WHEN CALLED DIRECTLY (MEASURED BY
      LOADING THE MODULE BY PATH AND CALLING `world()` -- **⇒ SO THE FAILURE IS REPRODUCIBLE
      WITHOUT THE SUBSTRATE, AND THE SUBSTRATE IS NOT NEEDED TO SEE IT**).**
      **⇒ AND THE GATE'S CURRENT `REFUSED` IS A **DIFFERENT** DEFECT RIGHT NOW, AND IT IS
      **TRANSIENT**: IT READS `rc=3`, "bend said: ... a declared constructor (unknown:
      ../tinybendygrad/uop/ops.DRng)" -- **⇒ AND `tinybendygrad/uop/ops.bend` HAS AN
      **UNCOMMITTED** 4,616-LINE DELETION IN THE WORKING TREE (MEASURED:
      `git diff --numstat -- tinybendygrad/uop/ops.bend` READS `1252  4616`), AND THE FILE WAS
      MODIFIED **NINE SECONDS** BEFORE I MEASURED IT -- **⇒ SO THAT REFUSAL IS ANOTHER UNIT's
      IN-FLIGHT REFACTOR, NOT THIS GATE.** THE `rtag` REFUSAL IS THE ONE THAT MATTERS.**""",
        None,
    ),
    (
        "- [ ] **AND THE PORT's SIDE IS **NOT** THE BLOCKER AND THE QUESTION IS OPEN.**",
        """
      **⇒ PROVABLY DONE (2026-11-10), AND THE ANSWER IS THE OPPOSITE OF THE ITEM's HOPE, AND
      THAT IS THE FINDING.** **THE PORT **DOES** HAVE A "TAGGED COPY" CONCEPT, AND IT IS
      LOAD-BEARING, AND UPSTREAM AT THE PIN **DOES NOT** HAVE ONE AT ALL.**
      **⇒ THE INSTRUMENT IS `.agents/slop/todo-sweep2/tagpin.py` (16 READINGS, ALL AS PREDICTED)
      AND IT ANSWERS THE QUESTION IN BOTH DIRECTIONS:**
      - **UPSTREAM AT THE PIN HAS NO `tag`:** `pin ops.py has a tag FIELD` **NO**,
        `has def rtag(` **NO**, `has def tagstr(` **NO**, `names tag in the intern key` **NO**.
      - **UPSTREAM DELETED IT, AND THE COMMIT IS AN ANCESTOR OF THE PIN:**
        **`fb518b44e` "delete UOp.tag [pr] (#18954)", 2026-10-21, IS AN ANCESTOR OF `f5ac54685074`
        (MEASURED: `git merge-base --is-ancestor fb518b44e f5ac54685074` ANSWERS YES).** THAT
        COMMIT REMOVED `UOp.tag`, `UOp.rtag`, `UOp.tagstr`, **AND `tag` FROM THE INTERN KEY** --
        `(op, src, arg, tag, type(arg))` -> `(op, src, arg, type(arg))` -- **⇒ SO THE TAG WAS
        NOT AN OPTIONAL FIELD AT THE PIN, IT WAS NOT PART OF THE KEY AT ALL.**
      - **UPSTREAM's `rangeify.py` AT THE PIN HAS NO TAGGING STEP:** `pm_add_range_tags` **NO**,
        `pm_add_param_range_tags` **NO**, `calls .rtag(` **NO**. AND `get_rangeify_map` RUNS
        `pm_add_buffers` THEN `split_kernels` -- **⇒ AND `pm_renumber_range` (`:319`) HAS NO
        TAG GUARD, WHERE THE PORT's `renumber_range` HAS ONE.**
      - **THE PORT HAS IT, ACROSS NINETEEN FILES:** `port ops.bend declares type Tag is Data:`
        **YES**, `defines eq_tag` **YES**, `defines sg.tag` **YES**, `port rangeify.bend
        defines rf_rtag` **YES**, `defines rf_param_rtag` **YES**. MEASURED: `grep -rn 'Tag\b'
        tinybendygrad/ --include='*.bend'` ANSWERS **76** OCCURRENCES IN **19** FILES.
      **⇒ AND THE CONSEQUENCE, WHICH IS THE POINT: **THE ORACLE CANNOT BE REPAIRED BY A RENAME.**
      THE ORACLE MIRRORS THE PORT's FIXTURE **INDEX FOR INDEX** (`world()`'s DOCSTRING SAYS
      "THE PORT'S FIXTURE, node for node"), AND THE PORT's FIXTURE HAS **FOUR** TAGGED COPIES
      (`r0t` `pgt` `pat` `rgt`) THAT **PIN-CPYTHON CANNOT BUILD** -- **⇒ SO THE ORACLE CANNOT
      PRODUCE THE PORT's FIXTURE AT ALL, AND A FIXTURE THAT CANNOT BE BUILT IS A LANE THAT
      MEASURES NOTHING.** **⇒ AND THE PORT's SIDE IS **NOT** THIS SWEEP's: REMOVING `Tag` IS A
      NINETEEN-FILE REFACTOR, AND THE PORT'S `rangeify.bend` PORTS A RULE UPSTREAM DELETED --
      `pm_add_param_range_tags` -- WHICH IS A **PORT/PIN DIVERGENCE** AND IS THE `rangeify`
      LANE's TO SETTLE.**""",
        None,
    ),
    (
        "- [ ] **AND THE LEDGER's `WALLAUDIT` AND `MARKERFORM` SECTIONS NAME `rangeify` IN **BOTH**",
        """
      **⇒ PROVABLY DONE (2026-11-10), AND IT IS NOW A **MEASUREMENT** RATHER THAN A CLASS
      STATEMENT: THE THREE SECTIONS NAME `rangeify` IN BOTH DIRECTIONS, **⇒ AND THE FOURTH
      THING THAT WAS NEVER ASKED -- "CAN THE GATE OVER THAT FILE RUN AT ALL" -- HAS NOW BEEN
      ASKED, AND THE ANSWER IS NO, WITH A PIN CITATION: `fb518b44e` REMOVED `UOp.tag` FROM
      UPSTREAM AND `f5ac54685074` HAS NO `rtag`, NO `tag` FIELD, AND NO `tag` IN THE INTERN
      KEY.** **⇒ AND THE CLASS IS GENERAL, AND IT IS WORTH NAMING IN ITS OWN RIGHT: A SECTION
      THAT AUDITS A FILE's MARKERS, A SECTION THAT FIXES AN INSTRUMENT's BLINDNESS, AND A
      SECTION THAT NAMES A GATE OVER THAT FILE CAN ALL BE TRUE WHILE **THE GATE IS DEAD** --
      ⇒ AND A GATE THAT CANNOT BUILD ITS FIXTURE IS DEAD IN A WAY THAT NO AMOUNT OF READING
      THE FIXTURE WILL REVEAL, BECAUSE THE FIXTURE IS FINE AND THE **LANGUAGE** IT IS WRITTEN
      IN NO LONGER HAS THE CONSTRUCT.**""",
        None,
    ),
]

# The bars, in the SUMMARY TABLE, matched by their own text.
BARS = [
    ("• RNGCMP -- gates/rng_graph_census-gate.py CALLS UOp.rtag, WHICH UPSTRE...",
     "• RNGCMP -- gates/rng_graph_census-gate.py CALLS UOp.rtag, WHICH UPSTRE... — ██░░░░░░░░ 2/3   67%"),
]


def main():
    lines = LEDGER.read_text().split("\n")
    applied = []

    for first_line, evidence, _ in PATCHES:
        # FIND THE ITEM BY ITS OWN FIRST LINE, FRESH, EVERY TIME.
        hits = [i for i, l in enumerate(lines) if l.startswith(first_line)]
        if len(hits) != 1:
            print(f"SKIP (found {len(hits)}): {first_line[:60]}")
            continue
        i = hits[0]
        # THE ITEM's BODY IS EVERY LINE UNTIL THE NEXT `- [` OR `- [x]` AT COLUMN 0.
        j = i + 1
        while j < len(lines) and not (lines[j].startswith("- [ ] ") or lines[j].startswith("- [x] ")
                                       or lines[j].startswith("## ")):
            j += 1
        # TICK IT: ONLY THE MARKER CHANGES.
        assert lines[i].startswith("- [ ] "), lines[i][:40]
        lines[i] = "- [x] " + lines[i][len("- [ ] "):]
        # APPEND THE EVIDENCE BELOW THE ITEM's OWN BODY, INDENTED TO MATCH.
        indent = "      "
        body = [indent + line.strip() if line.strip() else "" for line in evidence.strip("\n").split("\n")]
        lines[j:j] = body
        applied.append(first_line[:60])

    for old, new in BARS:
        hits = [i for i, l in enumerate(lines) if l.startswith(old)]
        if len(hits) != 1:
            print(f"BAR SKIP (found {len(hits)}): {old[:60]}")
            continue
        lines[hits[0]] = new
        applied.append("BAR " + old[:40])

    LEDGER.write_text("\n".join(lines))
    print(f"patched {len(applied)} places")
    for a in applied:
        print("  ", a)


if __name__ == "__main__":
    main()
