#!/usr/bin/env python3
"""mutate.py -- BUILD THE TWO MUTANTS OF THE PROMOTED CENSUS, so the control is shown to GO RED.

A control that has never failed is a label, not a control (`checks/differ.py`'s own plant 3:
"if it does not go red, the row is a label").  Two mutants, each breaking ONE coupling between
the census's grammar and the live `gates/gatekit.py`:

  MUTANT A  the vocabulary is a TYPED COPY instead of a LOAD.  The census no longer follows the
             owner at all: it cannot see a code the owner gains, cannot see a rename, cannot see
             an ambiguous owner, and cannot see that the owner is gone.

  MUTANT B  the DECLARING word set is RETYPED instead of DERIVED.  The code->word map still
             follows the owner, but the words the prose test recognises do not.

Both are written under this directory; neither touches the promoted scratch.
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "scratch" / "exitcode-census.py"

MUT_A = SRC.read_text()
ANCHOR_A = "    p = Path(owner) if owner else GATEKIT\n"
assert MUT_A.count(ANCHOR_A) == 1, "MUTANT A anchor is not unique"
MUT_A = MUT_A.replace(ANCHOR_A,
                      "    return {0: \"PASS\", 1: \"FAIL\", 3: \"REFUSED\", 4: \"SKIP\", 5: \"DEAD\"}\n"
                      + ANCHOR_A)
(HERE / "scratch" / "mutant-a.py").write_text(MUT_A)

MUT_B = SRC.read_text()
ANCHOR_B = "    words = set(vocab.values())\n"
assert MUT_B.count(ANCHOR_B) == 1, "MUTANT B anchor is not unique"
MUT_B = MUT_B.replace(ANCHOR_B,
                      "    words = {\"PASS\", \"FAIL\", \"REFUSED\", \"SKIP\", \"DEAD\", \"USAGE\",\n"
                      "              \"GREEN\", \"RED\", \"VERDICT\"}\n"
                      "    return words\n")
(HERE / "scratch" / "mutant-b.py").write_text(MUT_B)
print("wrote scratch/mutant-a.py (typed vocabulary) and scratch/mutant-b.py (retyped word set)")
