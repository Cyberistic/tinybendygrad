#!/usr/bin/env python3
"""onnx_census-gate.py -- THE CENSUS for `tinybendygrad/nn/onnx.bend`, layer 1 of 3.

    .venv/bin/python gates/onnx_census-gate.py        # 167 rows, 3 lanes, rc 0
    .venv/bin/python gates/onnx_census-gate.py --plant

WHAT "UNGATED" MEASURED TO BE, WHICH IS NOT "NO GATE". `.agents/slop/onnx-gate.py` EXISTS
(11 566 bytes, its sha256 in `DRIFT_PIN`), it runs (MEASURED rc=0, 123 rows), and its output
is BYTE-IDENTICAL to `./bin/bend tinybendygrad/nn/onnx.bend` (MEASURED 2026-10-16, diff rc=0).
What it was not is WIRED: no `gates/*onnx*` file named it, nothing in `gates/` imported it,
and `gates/gates-pop.ledger.tsv` -- NOT MINE TO EDIT -- has no row for it. An unwired
instrument is a note. AND it lived in `.agents/slop/`, WHICH IS BEING PRUNED: `mixin/rand`'s
CPython lane `.agents/slop/rd-truth.py` is ALREADY GONE and is in no git history at all, so
`gates/rand_census-gate.py` had to be written from nothing. This gate and its oracle therefore
live in `gates/`, which is `gates/README.md`'s rule.

THE ROWS ARE 167 AND THE FIRST 123 ARE THE PORT'S OWN, UNCHANGED. `gates/onnx_census.bend`
reproduces `nn/onnx.bend`'s `main` verbatim -- MEASURED, the driver's first 123 lines are
byte-identical to the port's own -- and ADDS 44 `v_*`/`ctrl_*` rows that print the SUBJECT of
one of `main`'s Booleans as a VALUE. Nothing was removed: the six literal `*_rows` and
`onnx_stage2=True` rows stay, because deleting a row the port ships to make a gate pass is
weakening an instrument, and they are CLASSIFIED as C-CONST below instead.

THE THREE CLASSES THAT MATTER HERE, AND MEASURED ON THIS LANE.

  C-BOOL   76 rows. `main` asserts `Bool.eq(port_def(), <literal>)` for forty-six of them and
           the groups add thirty more. CANNOT DISTINGUISH agreement from a shared wrong
           transcription, and the `v_*` rows exist because of exactly that.
  C-VALUE  84 rows, and the 44 added ones are here: counts as numbers (`v_cnt_wt=6`,
           `v_cnt_ops=171`), every enum cell through the port's own lookups (`v_odt_1=FLOAT/
           float`), and every `_select_op` fixture's NAME.
  C-CONST   6 rows: `onnx_ops_rows`, `onnx_p2t_rows`, `onnx_ap_rows`, `onnx_pool_rows`,
           `onnx_axes_rows`, `onnx_stage2`. Their value is a LITERAL on both sides, so they
           say the group was entered and nothing about what it produced. THE SIX ARE THE
           ANSWER TO "WHAT CAN THIS NOT DISTINGUISH" and they are the reason `ctrl_p2t_4`,
           `ctrl_ap_su_neg1` and `ctrl_sel_conv` exist: a C-CONST row's only repairable
           weakness is determinism and double-emission, and a control row is the only thing
           that measures either.

DRIFT, MEASURED, AND IT IS A FINDING. `oracles/tinybendygrad_nn_onnx.bend.rows` is a frozen
snapshot of this oracle's stdout and it is TWO ROWS STALE against HEAD:

    onnx_odt_dtbl     frozen `float,unsigned char,...,__bf16`   HEAD `f32,u8,i8,...,bf16`
    onnx_odt_hole_dts frozen `-,float,-,-,-`                     HEAD `-,f32,-,-,-`

The cause is UPSTREAM and it is a named commit: `793abbb16 "modernize tinygrad's dtype to
match rust (#18575)"` moved `DType.name` onto the rust spellings. The PORT already moved with
it (`tinybendygrad/nn/onnx.bend:820-823` says so, and `tinybendygrad/dtype.bend`'s `dt_name`
prints the new vocabulary), the LIVE oracle agrees with both, and only the frozen file is
behind. So this is NOT a port defect and NOT an oracle defect: it is a PIN that was not
moved when its subject moved, and the pin below is the instrument that would have said so
instead of a stale file sitting there looking authoritative. THE STALE FILE IS LEFT ALONE --
`oracles/` is not in this unit's grant and `differ.declared()` does not name it (MEASURED:
`len(differ.declared())` is 176 and neither `oracles/tinybendygrad_nn_onnx.bend.rows` nor
`oracles/tinybendygrad_mixin_rand.bend.rows` is in it), so nothing in the tree currently
regenerates or checks them. THAT IS A REPORT ITEM, NOT A FIX.

EXIT STATUS: 0 three lanes identical, population and classes as declared, pins intact ·
1 a lane disagreed or the population/class census failed · 3 a precondition was absent (a pin
moved, the substrate, the oracle, the output directory) · 5 a lane emitted nothing.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate, oracle_drift
from state_census import (class_census as _class_census, declared_rows as _declared,
                          lanes, plant as _plant, row_population as _row_population)

DRIVER = "onnx_census.bend"
ORACLE = "onnx_census-oracle.py"
PORT = "tinybendygrad/nn/onnx.bend"
ROOT = Path(__file__).resolve().parent.parent

# THE CPYTHON-SIDE BLOBS, MEASURED 2026-10-16 by `shasum -a 256`. Four, not three:
# `tinygrad/dtype.py` is the one that MOVED (793abbb16, twelve of thirteen `DType.name`
# spellings) and it is pinned so that the day it moves again the gate REFUSES with a reason
# instead of reporting a diff about vocabulary.
DRIFT_PIN = {
  "tinygrad/nn/onnx.py": "743f447feb4d12406a1a526b866d2d14c16a5716b19cab8421f87abecd7374ba",
  "tinygrad/dtype.py": "356ba326d9d221bdf5d6f9253d561b94f18b224499d5fc77c21e88c0aed00504",
  "tinygrad/nn/state.py": "8b709853bca9edf31b99eb7e76c756968cb9bf521747f7dc50a86110ff974e6b",
  "gates/onnx_census-oracle.py": "5e28720a1bb704b9a39901a1a6377647b28609f6cec98404d2c93b39f4f37c81",
}

GATE = Gate("onnx_census-gate", bend=DRIVER, oracle=ORACLE, rows=167, compared=167,
            diverges={},
            pins=[(lane, r) for lane in ("py", "bd", "bn")
                  for r in ("onnx_odt_dtbl", "v_cnt_ops", "ctrl_sel_conv")])

# THE DRIVER DECLARES every row it prints with a `p`/`pu`/`pb` first-argument string; the PORT
# declares the rest, and in TWO SHAPES -- `onx_row("nm", ...)` in `main`, and
# `IO.print(String.concat(["nm=", ...]))` in the five group helpers. Both patterns are read,
# and the first version of this file passed only the first: the census reported
# `emitted=167 declared=49` and FAILED, which is the instrument doing its job.
# A ROW DECLARATION IS NOT NECESSARILY THE FIRST TOKEN ON ITS LINE. The first version of this
# pattern was `^\s*(?:p|pu|pb)\("...` and it found 137 of the driver's 167 rows; the thirty it
# missed were exactly the ones BIND to a name (`a : Unit <- p("v_wt_0", ...)`) rather than
# standing as the block's tail expression. The population census reported
# `emitted=167 declared=137` and FAILED, which is the instrument working -- but the fix is a
# LOOKBEHIND, not a looser anchor: `(?<![\w.])` will not match the `p` of `print(`, of
# `onx_row(`, or of any other name ending in `p`.
_DECL = re.compile(r'(?<![\w.])(?:p|pu|pb)\("([^"]+)"', re.M)
_PORT_DECL = [re.compile(r'onx_row\("([^"]+)"'),
              re.compile(r'String\.concat\(\["([^"]+)="')]

# THE C-CONST ROWS: six names, named because "the value is a literal" is not decidable from
# the lane -- `onnx_p2t_rows=True` and a row that genuinely evaluated to `True` look alike.
CONST = ("onnx_ops_rows", "onnx_p2t_rows", "onnx_ap_rows", "onnx_pool_rows", "onnx_axes_rows",
         "onnx_stage2")
NEG = ("onnx_pc_absent", "onnx_pc_absent2", "v_odt_0", "v_odt_8", "v_odt_14", "v_odt_15")


def _lane_text():
  f = GATE.dir / "bd.out"
  return f.read_text() if f.is_file() else ""


def row_population() -> bool:
  return _row_population(_declared(ROOT / "gates" / DRIVER, ROOT / PORT, _DECL, _PORT_DECL),
                         [k for k, _ in lanes(_lane_text())], " (onnx)")


def class_census() -> bool:
  return _class_census(lanes(_lane_text()), neg=NEG, const=CONST,
                       floors={"C-CTRL": 3, "C-CONST": 6, "C-EMPTY": 2, "C-NEG": 6,
                               "C-BOOL": 1, "C-VALUE": 40})


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
  sys.exit(gate(GATE, "onnx_census-gate: 167 rows (the port's own 123 plus 44 value rows), "
                      "3 lanes byte-identical; population and class census clean; four "
                      "CPython pins intact", checks=lambda: row_population() and class_census()))
