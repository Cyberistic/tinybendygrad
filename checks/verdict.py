#!/usr/bin/env python3
"""verdict.py -- PRINT THE VERDICT AND EXIT WITH IT, in the two sentences this tree already prints.

    sys.path.insert(0, str(Path(__file__).resolve().parent))   # or an existing HERE
    from verdict import DEAD, FAIL, PASS, REFUSED, settle

    if not out.exists():
        settle(DEAD if not r.returncode else REFUSED, f"bend -o emitted no JS: {r.stderr.strip()[:300]}")

WHY THIS FILE, MEASURED. THIRTY-THREE sites under `checks/` handed `sys.exit`/`raise SystemExit` a
SENTENCE, and `gates/exitcode-census-gate.py` grades each of them the `STR` shape -- "a string
handed to sys.exit is PRINTED and exits 1 == FAIL". So a lane that RAN AND EMITTED NOTHING and an
input that was ABSENT both reached a caller as `FAIL`, i.e. as a disagreement about the tree, and a
reader of `$?` cannot tell which verdict was meant. `gates/gatekit.py:542` names the repair in the
tree's own words: "STAGE EVERY WRITE, AND SETTLE ON EVERY EXIT -- INCLUDING A RAISED ONE".

THE CODES ARE `gates/gatekit.py`'s, LOADED BY PATH AND NEVER RE-SPELLED: `gates/gatekit.py:60` is
`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`. `checks/cl-port-gate.py:65` is the ground for the
rule and quotes it -- "a second copy of the vocabulary is the same fault as a second copy of a
population" -- and a table that can disagree with the first is a table nobody can check. That load
cannot fail on a caller's stale root: `gates/gatekit.py`'s module level is inert, measured by an AST
walk that finds `import hashlib/os/re/subprocess/sys/tempfile`, `from pathlib import Path`, and one
`Assign` -- `PASS, FAIL, REFUSED, SKIP, DEAD = (0, 1, 3, 4, 5)` -- and nothing else.

THE SENTENCES ARE COPIED, NOT INVENTED.
  REFUSED  `== REFUSED, NOT A VERDICT: <file>.py: <why>`. Already printed by 22 files under
           `checks/` and `gates/` -- `checks/gate_norm.py:60`, `checks/cl-port-gate.py:72`,
           `gates/runner.py:533`, `gates/gates-pop.py:239`, `gates/ops_python_census-oracle.py:90`.
           It is also LOAD-BEARING rather than decorative: `gates/gates-pop.py:561`'s `REFUSE`
           regex and `:764`'s `_CERTIFY_OR` both match the string to decide that a file CAN refuse,
           so a refusal spelled any other way is invisible to the tree that certifies gates.
  DEAD     `== DEAD: <file>.py: <why>`. `gates/citations-census-gate.py:610,630` is the tree's only
           `==`-prefixed DEAD and the structural twin of the refusal line; the gloss is
           `gates/gatekit.py:55`'s and `checks/gatesweep.py:122`'s in as many words, "it ran and
           emitted nothing", and the exit is `gates/gatekit.py:547` and `:590`'s own.
BOTH GO TO STDERR, because a message about the run must not be mistakable for one of its rows.

ONE EXIT SITE IN THIS FILE, AND IT IS CHOSEN. `sys.exit(code)` hands the exit a PARAMETER, so
`gates/exitcode-census-gate.py:classify_site` reads the shape `OTHER` -- "a value computed over
runtime data", which is in its `CHOSEN` set -- instead of `STR`. `settle` NEVER RETURNS, and nothing
here re-decides what `gates/gatekit.py` has decided: `VERDICT` names the sentence for every code it
holds, and a code it does not hold raises `KeyError` AT THE EXIT RATHER THAN EXITING 0, so a
misspelled verdict is a crash a reader can see and not a green run nobody can.

`PASS` IS EXPORTED AND UNUSED HERE, because a reader must be able to see that the whole vocabulary
is available. A caller that spells it pays in the census row, not in a silently green run.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gates"))
from gatekit import DEAD, FAIL, PASS, REFUSED, SKIP, VERDICT  # noqa: E402

__all__ = ["DEAD", "FAIL", "PASS", "REFUSED", "SKIP", "VERDICT", "settle"]


def settle(code: int, *why: str) -> None:
    """Print `code`'s sentence on stderr naming THIS file, then exit `code`. Never returns.

    `why` is the STATE and never the verdict: "the fixture is absent", "the lane emitted no rows".
    The verdict word is already in the sentence, so repeating it in `why` is the shape
    `gates/runner.py:283` calls a gate that says one verdict and exits another.

    `sys._getframe` is the ONE private name in this file, read only on the exiting path because the
    caller's own filename is what makes the sentence findable and passing it 33 times is the
    copy-paste `checks/cl-port-gate.py:65` rules out. `*why` is `str` BY CONTRACT and the contract is
    the annotation, not a coercion: `"; ".join` raising `TypeError` is a crash at the exit, which
    is the failure this file exists to remove, so a caller that passes a list gets a traceback it can
    see rather than a `-- DEAD` line nobody believes. MEASURED, that is not hypothetical -- it
    happened here once, at `checks/gate.py`'s REGISTERED row.
    """
    head = "REFUSED, NOT A VERDICT" if code == REFUSED else VERDICT[code]
    print(f"== {head}: {Path(sys._getframe(1).f_code.co_filename).name}: " + "; ".join(why),
          file=sys.stderr)
    sys.exit(code)
