#!/usr/bin/env python3
"""pycell-plant.py -- THE PLANT: EVERY ARM IS A TEXT EDIT, AND EVERY ARM MUST GO RED.

    .venv/bin/python gates/pycell-plant.py          # the arms, driven
    .venv/bin/python gates/pycell-plant.py --prove  # ... and the 224 KNOWN CASES

WHAT A PLANT IS FOR HERE
------------------------
`gates/pycell-census.py` classifies each `py=` cell by PROVENANCE.  A classifier that
cannot tell a transcription from a derived cell is not a classifier: it is a rule that
cannot fail, and `AGENTS.md`'s DOCTRINE 2 says a gate that exits 0 having measured nothing
is worse than no gate.  So the census's own correctness is ASSERTED, and it is asserted
against a FIXTURE THIS FILE EDITS.

**EVERY ARM IS A TEXT EDIT.**  MEASURED, and it is the lesson of the night: a unit's plant
read `git show HEAD:` and scored GREEN under `--falsify`, because the moment HEAD carried
the defect's fix the planted text was gone and the arm asserted nothing.  A blob SHA is
content-addressed and cannot move, so the ONE arm that reads git reads a PINNED BLOB and
not a revision -- and every other arm is a string replacement in a file in this directory.

THE ARMS, AND WHAT EACH ONE CLAIMS
-----------------------------------
  1  THE BLIND SPOT.      A cell whose value is a NUMBER is a TRANSCRIPTION.  The old
                           syntactic rule read `2` as "not a quoted string, therefore
                           DERIVED".  The arm rewrites the fixture's LITERAL cell as the
                           NUMBER `2` -- which the OLD rule still calls DERIVED -- and
                           asserts the NEW rule calls it TRANSCRIPTION.
  2  THE CONSTANT FOLD.   A cell whose value is a CONSTANT FOLDED FROM A CONSTANT is a
                           TRANSCRIPTION: `U32.show(2)` is `"2"` whatever the port does.
                           The old rule sees a CALL and says DERIVED.
  3  THE PARAMETER CHAIN. A cell whose value comes from a `py=`-SLOT PARAMETER that the
                           CALLER fills with a LITERAL is a TRANSCRIPTION.  The arm rewrites
                           the literal the caller passes and asserts the verdict moves.
  4  THE VACUITY GUARD.   The DERIVED cell must STAY DERIVED.  **A RULE THAT FIRES ON
                           EVERYTHING IS SATISFIED BY ARMS 1-3 ALONE**, so this arm holds
                           the other side down.
  5  THE 224 KNOWN CASES. On a PINNED CONTENT-ADDRESSED BLOB: the classifier must call
                           the 224 number/bool cells TRANSCRIPTIONS that the old rule
                           called DERIVED.

THE VERDICTS COME FROM THE SHIPPED CLASSIFIER, NEVER FROM A COPY OF IT
-------------------------------------------------------------------------
Every arm drives `gates/pycell-census.py`'s own `census_text()` and the module's own
`resolve()`.  A plant that re-implements the decision cannot fail when the decision
changes.
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
FIXTURE = HERE / "pycell-plant.bend"
CENSUS = HERE / "pycell-census.py"


def load_census():
    """The census module, LOADED BY PATH -- never imported, so a half-written census
    cannot be executed by a plant that only wants its answer."""
    spec = importlib.util.spec_from_file_location("pycell_census_for_plant", CENSUS)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def verdicts(mod, text):
    """`{row name: (kind, form)}` for the fixture, by the SHIPPED classifier."""
    rows = mod.census_text(text, "gates/pycell-plant.bend", set())
    out = {}
    for (kind, form, builder, _ordinal, _detail, name) in rows:
        nm = name.strip().strip('"')
        out.setdefault(nm, (kind, form))
    return out


def plant(mod, text):
    """The arms.  Every one is a TEXT EDIT of the fixture, and every one must hold."""
    checks = []

    # -- ARM 0: THE FIXTURE AS COMMITTED.  The four shapes and their verdicts.
    base = verdicts(mod, text)
    want = {
        "plant literal": (mod.TRANSCRIPTION, mod.LITERAL_STRING),
        "plant param": (mod.TRANSCRIPTION, mod.LITERAL_STRING),
        "plant derived": (mod.DERIVED, None),
        "plant number": (mod.TRANSCRIPTION, mod.LITERAL_NUMBER),
    }
    ok0 = all(base.get(k, (None, None))[0] == v[0] for k, v in want.items())
    for k, v in want.items():
        got = base.get(k, ("MISSING", ""))
        ok = got[0] == v[0] and (v[1] is None or got[1] == v[1])
        checks.append((f"base:{k}", ok, f"{got[0]}/{got[1]}"))
    checks.append(("base:four-cells", ok0 and len(base) == 4, f"{len(base)} cells"))

    # -- ARM 1: THE BLIND SPOT.  A NUMBER where a quoted string was.
    edited = text.replace('r("plant literal", U32.show(port_answer(1)), "2"),',
                          'r("plant literal", U32.show(port_answer(1)), 2),')
    got = verdicts(mod, edited).get("plant literal", ("MISSING", ""))
    old = mod.syntactic_classify("2")[0]
    checks.append(("arm1:number-is-a-transcription",
                   got[0] == mod.TRANSCRIPTION and got[1] == mod.LITERAL_NUMBER
                   and old == "DERIVED",
                   f"new={got[0]}/{got[1]} old-rule={old}"))

    # -- ARM 2: THE CONSTANT FOLD.  `U32.show(2)` is "2" whatever the port does.
    edited = text.replace('r("plant literal", U32.show(port_answer(1)), "2"),',
                          'r("plant literal", U32.show(port_answer(1)), U32.show(2)),')
    got = verdicts(mod, edited).get("plant literal", ("MISSING", ""))
    old = mod.syntactic_classify("U32.show(2)")[0]
    checks.append(("arm2:constant-fold-is-a-transcription",
                   got[0] == mod.TRANSCRIPTION and old == "DERIVED",
                   f"new={got[0]}/{got[1]} old-rule={old}"))

    # -- ARM 3: THE PARAMETER CHAIN.  The caller fills the `py=`-slot parameter with a
    # literal, and the cell must be a TRANSCRIPTION.  The arm swaps the literal for a
    # NUMBER, which the OLD rule cannot tell from a call.
    edited = text.replace('row_from_param("plant param", U32.show(port_answer(2)), "3"),',
                          'row_from_param("plant param", U32.show(port_answer(2)), 3),')
    got = verdicts(mod, edited).get("plant param", ("MISSING", ""))
    checks.append(("arm3:parameter-filled-with-a-literal",
                   got[0] == mod.TRANSCRIPTION and got[1] == mod.LITERAL_NUMBER,
                   f"new={got[0]}/{got[1]}"))

    # -- ARM 4: THE VACUITY GUARD.  The DERIVED cell must stay DERIVED, and the OLD rule
    # must call it DERIVED too -- so this arm is not a tautology of the new rule.
    got = verdicts(mod, text).get("plant derived", ("MISSING", ""))
    checks.append(("arm4:derived-stays-derived",
                   got[0] == mod.DERIVED, f"new={got[0]}/{got[1]}"))

    # -- ARM 5: THE 224 KNOWN CASES, ON A PINNED BLOB.
    p = mod.prove(str(ROOT / "tinybendygrad"), verbose=False)
    ok5 = p is not None and p["numbers"] == mod.KNOWN_CASES \
        and p["old"].get("DERIVED", 0) == mod.KNOWN_CASES
    checks.append(("arm5:the-224-known-cases",
                   ok5,
                   f"numbers={p['numbers'] if p else 'REFUSED'} "
                   f"old-derived={p['old'].get('DERIVED') if p else '-'} "
                   f"want={mod.KNOWN_CASES}"))

    return checks


def main(argv=None):
    ap = argparse.ArgumentParser(prog="gates/pycell-plant.py",
                                 description=__doc__.split("\n")[0])
    ap.add_argument("--prove", action="store_true", help="print the 224 KNOWN CASES")
    a = ap.parse_args(argv)
    mod = load_census()
    if a.prove:
        p = mod.prove(str(ROOT / "tinybendygrad"))
        return 0 if p and p["numbers"] == mod.KNOWN_CASES else 1
    text = FIXTURE.read_text()
    checks = plant(mod, text)
    bad = []
    for (label, ok, detail) in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {label:<44} -> {detail}")
        if not ok:
            bad.append(label)
    print(f"--plant: {'GREEN' if not bad else 'RED'} ({len(checks) - len(bad)}/{len(checks)})")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
