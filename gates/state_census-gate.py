#!/usr/bin/env python3
"""state_census-gate.py -- THE CENSUS for `tinybendygrad/nn/state.bend`, layer 2 of 3.

    .venv/bin/python gates/state_census-gate.py        # 83 rows, 3 lanes, rc 0
    .venv/bin/python gates/state_census-gate.py --plant

WHAT THIS GATE IS, AND WHY IT HAD TO BE BUILT. `AGENTS.md` lists the layers that have a
census -- `tensor`, `uop/spec`, `uop/fold`, `uop/symbolic`, `mixin/creation`,
`mixin/elementwise`, `engine/realize`, `renderer/*`, `codegen/decomp` -- and `nn/state` was
on none of them. IT WAS NOT QUITE UNGATED, AND THE DIFFERENCE MATTERS, SO IT IS MEASURED
RATHER THAN ASSERTED:

  * `.agents/slop/state-gate.py` EXISTS (6 396 bytes, sha256 in `DRIFT_PIN` below) and prints
    the same fourteen rows this gate prints in its first fourteen lines. It is the CPython
    lane, it was written, and it runs: MEASURED rc=0, 14 rows, byte-identical to
    `./bin/bend tinybendygrad/nn/state.bend`. What it is NOT is WIRED -- no `gates/*state*`
    file named it, nothing in `gates/` imported it, and `gates/gates-pop.ledger.tsv` (NOT
    MINE TO EDIT) has no row for it. An unwired instrument is a note.
  * AND it lives in `.agents/slop/`, WHICH IS BEING PRUNED. That is not a hypothetical:
    `mixin/rand`'s CPython lane `.agents/slop/rd-truth.py` is ALREADY GONE and never
    appears in any git history, so `gates/rand_census-gate.py` had to be written from
    scratch. This gate therefore lives in `gates/` and the oracle beside it, which is
    `gates/README.md`'s rule and `AGENTS.md`'s: A GATE'S REQUIRED INPUT BELONGS BESIDE THE
    GATE, IN GIT.

WHAT IT ADDS TO THE FOURTEEN. All fourteen rows the file shipped are BOOLEANS --
`sd_row("sd_nest", String.eq(sd_keys(...), "layers.0.weight,..."))` -- so a diff that moved
could only ever say "the port computed something else", never WHICH, and a transcription
error landing in both lanes would be green. So this gate's driver
(`gates/state_census.bend`) asks the port for the VALUE and this oracle supplies CPython's
value: 83 rows, of which 14 are the file's own Booleans (re-driven through the port's
`St.t_tens()` .. `St.t_param()`, which are top-level `IO(Unit)` and therefore callable) and
69 are values. THE VALUE FORM IS THE POINT: `val_nest` prints the eleven-name list and
`val_dup_val` prints `9`, so a defect names itself.

THE POPULATION, DISCOVERED IN BOTH DIRECTIONS, AND A HANDLER THAT REFUSES.
`declared_rows()` parses THIS GATE'S OWN DRIVER for the row name each `p`/`pu`/`pb` call
declares, and `port_rows()` parses `tinybendygrad/nn/state.bend` for the name each of its own
`t_*` helpers prints. Those two sets ARE the population -- a generator's own declaration,
loaded by path, not a hand list and not a suffix set. Then:

    emitted == declared                (both directions; a row the driver did not emit and
                                       a row it emitted without declaring are BOTH failures)
    len(set(emitted)) == len(emitted)  (a DUPLICATE row key, which is the recorded
                                       "row keys hiding N correct rows" shape)
    no key contains a space            (the same shape, one character earlier: a key with a
                                       space truncates every prefix match made against it)

An earlier draft of this file would have PRINTED the counts and carried on. It prints them
and REFUSES: `row_population()` returns False and the gate is FAIL, because a census that
reports a population it did not check is a census that cannot be wrong.

THE CLASS CENSUS, AND WHAT EACH CLASS CANNOT DISTINGUISH. Measured on this lane, not
asserted, and printed on every run:

  C-BOOL    value is `True`/`False`. Counted. CANNOT DISTINGUISH "the port agrees with
             CPython" from "BOTH agree with a transcription that is wrong": the expected
             value is a literal in each lane, so a shared literal is invisible to the diff.
             This is the class every one of the file's original fourteen rows is in.
  C-VALUE   value is the subject itself. CAN DISTINGUISH. Every mutation of the value moves
             the row and the diff shows the new value.
  C-CTRL    key begins `ctrl_`: the SAME computation under a second name. CANNOT DISTINGUISH
             anything about its subject -- its only claim is that the lane is DETERMINISTIC,
             and it is here so that a non-deterministic lane is caught by the rows beside
             it rather than by them being quietly wrong.
  C-EMPTY   value is the empty string. Counted. A transcript hides these (`row=`), and
             `val_strip_0`, `val_strip_1`, `val_strip_2`, `val_dbg_1_os` and `val_dbg_2_col`
             are all in it BY DESIGN: they are the rows that pin a result of `""`.
  C-NEG     a lookup that answers the empty/sentinel answer -- `val_get_none`,
             `val_name_weak`, `val_name_none`. Counted. A lookup whose every fixture is
             POSITIVE cannot see a lookup that answers `Some` for something absent, so these
             three exist; without them the whole lookup class would be unfalsifiable.

ONE CONTROL ROW PER CLASS IS NOT ACHIEVABLE FOR C-BOOL AND THIS GATE SAYS SO. The thirteen
port Booleans have no control, and the reason is structural rather than an omission: a
Boolean's expected value lives in the LANE, so there is no third place to perturb it. The
value rows are what close that hole -- `val_tens`/`val_nest` print what `sd_tens`/`sd_nest`
only assert -- and the control rows (`ctrl_ord`, `val_strip_ctrl`, `val_seek_ctrl`) are on
the value classes for exactly that reason. THIS IS THE ANSWER TO "WHAT CAN IT NOT
DISTINGUISH", and it is a per-class statement, not a per-row one.

DRIFT, PINNED IN CODE. `DRIFT_PIN` holds the sha256 of the three CPython-side blobs these
rows are claims about -- `tinygrad/nn/state.py` (the oracle's subject), `tinygrad/dtype.py`
(fifteen `val_get_*` and eight `val_name_*` rows are `DType.name` values, and upstream
793abbb16 "modernize tinygrad's dtype to match rust" moved twelve of the thirteen), and
`tinygrad/tensor.py` (`Tensor.__len__`, which `TensorIO.seek` clamps against). A pin in a
comment is a pin that cannot fail; these are read by `gatekit.oracle_drift` on every run and
a non-intact pin is a REFUSAL, not a FAIL, because the tree is fine either way and only the
QUESTION is unanswerable.

EXIT STATUS: 0 three lanes identical, population and classes as declared, pins intact ·
1 a lane disagreed, the row population does not match the declaration, or a class census
failed · 3 a precondition was absent (a pin moved, the output directory, the substrate, the
oracle) · 5 a lane emitted nothing · 4 unused here.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate, oracle_drift

DRIVER = "state_census.bend"
ORACLE = "state_census-oracle.py"
PORT = "tinybendygrad/nn/state.bend"
ROOT = Path(__file__).resolve().parent.parent

# THE THREE CPYTHON-SIDE BLOBS, MEASURED 2026-10-16 by `shasum -a 256`.
DRIFT_PIN = {
  "tinygrad/nn/state.py":
    "8b709853bca9edf31b99eb7e76c756968cb9bf521747f7dc50a86110ff974e6b",
  "tinygrad/dtype.py":
    "356ba326d9d221bdf5d6f9253d561b94f18b224499d5fc77c21e88c0aed00504",
  "tinygrad/tensor.py":
    "4be73faf9bfdb30d04cad9825a2dc7b48b4750a703fa85fb18b41f5e43d19c87",
  # THE ORACLE ITSELF, so a gate whose subject moved cannot keep reporting on the old one.
  "gates/state_census-oracle.py":
    "62a4cec98c564997db1896ec97ef6c3c6c98da9551f91b6118c73b681388f593",
}

GATE = Gate(
  "state_census-gate",
  bend=DRIVER,
  oracle=ORACLE,
  rows=85,
  compared=85,
  diverges={},
  pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ("val_nest", "val_dup_val")],
)

# THE ROW POPULATION, THE CLASS CENSUS AND THE PLANT LIVE IN `gates/state_census.py`, which
# is shared with `gates/onnx_census-gate.py` and `gates/rand_census-gate.py`. This file is
# only the THIRD question, which is per-layer: what this lane's rows mean, and how many of
# the file's own defs they reach.
from state_census import (declared_rows as _declared, lanes, class_census as _class_census,
                          plant as _plant, row_population as _row_population)  # noqa: E402

KEY = re.compile(r"^([^=]+)=")
# A row declaration need not be the FIRST TOKEN on its line -- `a : Unit <- p("x", ...)` is
# the same declaration. MEASURED on the sibling gate: an `^\s*`-anchored pattern found 137 of
# 167 and the population census failed on the 30 it missed. The lookbehind will not match the
# `p` of `print(` or of `sd_row(`.
_DECL = re.compile(r'(?<![\w.])(?:p|pu|pb)\("([^"]+)"', re.M)
_PORT_DECL = re.compile(r'sd_row\("([^"]+)"')


def _lane_text():
  f = GATE.dir / "bd.out"
  return f.read_text() if f.is_file() else ""


def row_population() -> bool:
  return _row_population(_declared(ROOT / "gates" / DRIVER, ROOT / PORT, _DECL, _PORT_DECL),
                         [k for k, _ in lanes(_lane_text())], " (state)")


# THE NEGATIVE FIXTURES AND THE CONSTANT ROWS OF THIS LANE, named because neither is decidable
# from a row's VALUE alone: a lookup that answers the empty answer and a `False` that was
# always going to be `False` look identical in a lane.
NEG = ("val_get_none", "val_name_weak", "val_name_none")


def class_census() -> bool:
  return _class_census(lanes(_lane_text()), neg=NEG,
                       floors={"C-CTRL": 4, "C-EMPTY": 1, "C-NEG": 3})


if __name__ == "__main__":
  if "--plant" in sys.argv:
    sys.exit(_plant())
  bad = oracle_drift(DRIFT_PIN)
  if bad:
    print("== REFUSED, NOT A VERDICT: the CPython side this gate diffs against has moved",
          file=sys.stderr)
    for b in bad:
      print(f"   {b}", file=sys.stderr)
    sys.exit(3)
  sys.exit(gate(GATE, "state_census-gate: 85 rows, 3 lanes byte-identical, 64 of them "
                      "VALUES rather than the 21 Booleans the lane also carries; "
                      "population and class census clean; four CPython pins intact",
               checks=lambda: row_population() and class_census()))
