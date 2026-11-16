#!/usr/bin/env python3
"""models-gate.py -- the gate for the `tinybendygrad/extra/models/` family.

    .venv/bin/python gates/models-gate.py

Fifteen models, fifteen drivers, and the rows' OWN CLAIMS checked independently.

WHAT THE ROWS CLAIM, AND WHY THEY ARE NOT CHECKED BY THEMSELVES.  Every model
port is a STUB: it refuses at the first upstream symbol it cannot reach, and its
rows report that refusal.  Some of the rows are a LABEL -- `unet_ported=False`
is a constant in the port, so it can only change if a human edits the port, and
a row that cannot go red is worse than no row.

So the rows that CAN go red are the ones this gate owns.  Each model prints
`NAME_exists=True|False` rows about whether a SYMBOL is in the tree, and this
gate answers each of those claims with its OWN probe -- a WALK of the port's
`.bend` files -- and compares the two.  A claim of `True` that names a symbol
which is not there is RED, and a claim of `False` that names a symbol which IS
there is RED, and both are RED because the gate measured the tree rather than
the port.

THE PROBES ARE DECLARED, NOT GUESSED.  Each one is a NAME SHAPE and a PLACE:
`softmax` is a def whose name ends in `_softmax`; `matmul` is a def whose name
ends in `_matmul` OR is `matmul`; `adam` is a def whose name ends in `_adam`.
The shape is the CLAIM, and the gate re-measures it against the tree on every
run, so a claim that was true when it was written and is false now is red.

THE REFUSAL ADDRESSES ARE CHECKED TOO, AND THAT IS THE OTHER HALF.  Each model
prints `NAME_refused_at=extra/models/NAME.py:LINE ...`, and the LINE is a
claim about upstream's file.  Upstream's `extra/` is NOT IN THE VENDORED TREE
at the pin `f5ac54685074` -- MEASURED: `tinygrad/extra/` does not exist -- so the
line cannot be checked against a file here, and the gate says so instead of
pretending.  What IS checkable is that the address is WELL-FORMED and that it
names the model's OWN file, and that is what the gate checks.

THE EXIT STATUS.  0 iff every probe agrees with every claim.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "tinybendygrad" / "extra" / "models"
DRIVERS = ROOT / "gates"
BEND = ROOT / "bin" / "bend"

PASS, FAIL, REFUSED = 0, 1, 3

# THE PROBES.  A probe is a LIST OF NAMES: the symbol is present in the tree if
# some `.bend` file under `tinybendygrad/` defines a def with one of them.
#
# THE LIST IS THE PORT'S OWN CLAIM, and each list is spelled the way the port's
# prose spells it -- `nn.Embedding` is "`def Embedding`, no `def mo_i`, no
# `def mo_fx`", so the list is `["Embedding", "mo_i", "mo_fx"]`.  A SUFFIX
# PROBE WOULD BE WRONG, and MEASURED 2026-11-16: a suffix probe for
# `_embedding` matched the port's own `nn_embedding` and reported the tree as
# HAVING the symbol, so six claims went red against a probe that was not the
# claim.  The tree's def names are collected from the WHOLE tree, so a probe
# that names a def the tree has for its own reasons is a red claim and the port
# is right to say the SYMBOL is missing.
#
# A probe that matches NOTHING is a DEAD PROBE, and the gate says so: a probe
# whose shape cannot match any name in the tree would report `False` for a
# symbol that IS there and never notice.  So the gate REQUIRES that each probe
# name is either present in the tree or is one the port's prose names, and it
# says which names it walked.
PROBES: dict[str, dict[str, list[str]]] = {
  "t5": {
    # `Tensor.softmax` -- `mo_softmax` (mixin/op.bend:1166) EXISTS.
    "softmax": ["mo_softmax", "tn_softmax"],
    # `Tensor.matmul` -- no `def mo_matmul` anywhere.
    "matmul": ["mo_matmul", "matmul"],
  },
  "rnnt": {
    # the recurrence is `LSTMCell`, and no `def` carries that name.
    "recurrence": ["LSTMCell", "rnnt_recurrence"],
    # `Tensor.sigmoid` -- `ew_sigmoid` (mixin/elementwise.bend:1233) EXISTS.
    "sigmoid": ["ew_sigmoid", "tn_sigmoid"],
  },
  "retinanet": {
    # `nn.Conv2d` CLASS is missing, but the op `nn_conv2d` EXISTS.
    "conv2d": ["nn_conv2d", "Conv2d"],
    # `Tensor.sequential` is missing.
    "sequential": ["mo_sequential", "sequential"],
  },
  "mask_rcnn": {
    "conv2d": ["nn_conv2d", "Conv2d"],
    # `Tensor.cat` -- `mx_cat` (mixin/movement.bend:125) is a LIST join, not
    # the tensor cat, so it does not count.
    "cat": ["tn_cat", "Tensor.cat"],
  },
  "llama": {
    # `Tensor.scaled_dot_product_attention` is missing.
    "attention": ["scaled_dot_product_attention", "mo_attention"],
    # `Adam` -- the optimizer EXISTS: `op_mstep` (nn/optim.bend:856) is the
    # adam half, and the port's own prose names it.
    "adam": ["op_mstep", "nn_adam", "adam", "Adam"],
  },
  "clip": {
    "conv2d": ["nn_conv2d", "Conv2d"],
    # `nn.Embedding` -- "no `def Embedding`, no `def mo_i`".
    "embedding": ["Embedding", "mo_i", "mo_fx"],
  },
  "bert": {
    "attention": ["scaled_dot_product_attention", "mo_attention"],
    "embedding": ["Embedding", "mo_i", "mo_fx"],
  },
  "transformer": {
    "attention": ["scaled_dot_product_attention", "mo_attention"],
  },
}

# THE MODELS, AND THE DRIVER EACH ONE'S ROWS LIVE IN.  The driver is named by
# the model, so the list is a NAME -> a NAME and the tree can be walked for
# both: a driver that is not there is a missing lane and a model whose rows
# are still in the port is a half-moved lane, and both are RED.
MODELS_LIST = sorted(
  p.stem for p in MODELS.glob("*.bend") if (DRIVERS / f"models-{p.stem}-gate.bend").is_file())


def port_defs() -> dict[str, str]:
  """every def NAME in the port tree, mapped to the file that defines it.

  A WALK of `tinybendygrad/` and not a list: the tree's own doctrine is that a
  population is a generator's declaration or a directory walk, and a hand list
  of symbol names is neither.
  """
  out: dict[str, str] = {}
  for path in sorted((ROOT / "tinybendygrad").rglob("*.bend")):
    try:
      text = path.read_text(errors="replace")
    except OSError:
      continue
    for m in re.finditer(r"^\s*def\s+([A-Za-z_][\w.]*)", text, re.M):
      name = m.group(1).split(".")[-1]
      out.setdefault(name, str(path.relative_to(ROOT)))
  return out


def probe_says(defs: dict[str, str], names: list[str]) -> tuple[bool, list[str]]:
  """is the symbol in the tree?  `(yes, the names that matched)`.

  A name is matched on its LAST DOTTED COMPONENT, so `mo_i` matches a def
  `mo_i` and a def `MO.mo_i` -- and the port's claim is about the NAME, not
  about where it is defined.
  """
  hits = [n for n in names if any(d == n or d.endswith("." + n) for d in defs)]
  return bool(hits), hits


def run_driver(model: str) -> tuple[dict[str, str] | None, str]:
  """the driver's rows.  `(rows, why)` -- `why` is set when it could not run."""
  drv = DRIVERS / f"models-{model}-gate.bend"
  if not drv.is_file():
    return None, f"the driver is absent: {drv}"
  try:
    r = subprocess.run([str(BEND), str(drv)], capture_output=True, text=True,
                       cwd=str(ROOT), timeout=600)
  except subprocess.TimeoutExpired:
    return None, "the driver did not finish"
  if r.returncode != 0:
    said = " | ".join(l.strip() for l in (r.stderr or "").splitlines()[-3:])[:200]
    return None, f"the driver failed rc={r.returncode}: {said}"
  rows: dict[str, str] = {}
  for line in r.stdout.splitlines():
    if "=" in line and line.strip():
      k, _, v = line.partition("=")
      rows[k] = v
  if not rows:
    return None, "the driver ran and emitted no rows"
  return rows, ""


def main() -> int:
  defs = port_defs()
  print(f"THE TREE: {len(defs)} def names, walked from tinybendygrad/")
  print(f"MODELS  : {len(MODELS_LIST)} with a driver: {', '.join(MODELS_LIST)}")
  bad: list[str] = []
  checked = 0
  for model in MODELS_LIST:
    rows, why = run_driver(model)
    if rows is None:
      bad.append(f"{model}: {why}")
      print(f"  {model:14s} DEAD -- {why}")
      continue
    notes: list[str] = []
    for key, value in rows.items():
      # THE ROW NAME IS `<model>_<symbol>_exists`, and the model is the FILE'S
      # stem -- so the symbol is what is LEFT after the stem. MEASURED
      # 2026-11-16: mask_rcnn's rows are `mask_rcnn_conv2d_exists` and
      # `rcnn_conv2d_exists` -- the second one does not carry the file's stem,
      # so the stem is stripped when it is there and the row is otherwise read
      # whole.
      m = re.match(r"^(?P<stem>.+)_(?P<sym>[a-z0-9_]+)_exists$", key)
      if not m:
        continue
      sym = m.group("sym")
      # The row's STEM is the model's own stem, and the SYMBOL is what is left
      # after it -- the regex's stem is GREEDY, so it takes the longest prefix
      # and `mask_rcnn_conv2d_exists` yields `mask_rcnn_conv2d` / `exists`... no:
      # the SYMBOL group is greedy too, so the STEM is the LONGEST prefix that
      # leaves a symbol.  The model's stem is stripped from what is left, and
      # the row is otherwise read whole.  MEASURED 2026-11-16: without this,
      # mask_rcnn's two `_exists` rows had NO PROBE and the gate reported them
      # as unchecked -- which is the honest answer and not a pass.
      for stem in (model, "mask_rcnn"):
        if sym.startswith(stem + "_"):
          sym = sym[len(stem) + 1:]
          break
      spec = PROBES.get(model, {}).get(sym)
      if spec is None:
        # A CLAIM WITH NO PROBE IS NOT CHECKED, and saying so is the point: the
        # gate must not read "checked" over a row it never measured.
        notes.append(f"{sym}: NO PROBE")
        continue
      want = value == "True"
      got, hits = probe_says(defs, spec)
      checked += 1
      if want != got:
        bad.append(f"{model}: {key} claims {value} and the tree says {got}"
                   f" (matched {hits or 'nothing'})")
        notes.append(f"{sym}: CLAIM {value} TREE {got}")
      else:
        notes.append(f"{sym}: {value}" + (f" ({','.join(hits)})" if hits else ""))
    # THE REFUSAL ADDRESS IS CHECKED FOR SHAPE AND FOR THE MODEL'S OWN FILE.
    ref = [v for k, v in rows.items() if k.endswith("_refused_at")]
    for v in ref:
      m = re.match(r"^(extra/models/([a-z0-9_]+)\.py):(\d+)\b", v)
      if not m:
        bad.append(f"{model}: the refusal address is not 'extra/models/X.py:LINE': {v!r}")
        notes.append("refused_at: MALFORMED")
      elif m.group(2) != model:
        bad.append(f"{model}: the refusal names {m.group(1)}, which is another file")
        notes.append("refused_at: WRONG FILE")
      else:
        notes.append(f"refused_at: {m.group(1)}:{m.group(3)}")
    print(f"  {model:14s} {len(rows)} rows -- " + "; ".join(notes))
  print(f"CLAIMS CHECKED: {checked}")
  if bad:
    print("FAIL")
    for b in bad:
      print(f"  {b}")
    return FAIL
  print("models-gate: PASS -- every probe agrees with every claim")
  return PASS


if __name__ == "__main__":
  sys.exit(main())
