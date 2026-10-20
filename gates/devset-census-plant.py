#!/usr/bin/env python3
"""devset-census-plant.py -- THE PLANT FOR `gates/devset-census-gate.py`, AND IT HAS FOUR ARMS
BECAUSE ONE LANE RED IS NOT EVIDENCE.

    .venv/bin/python gates/devset-census-plant.py            # the arms; exit 0 iff all held
    .venv/bin/python gates/devset-census-plant.py --falsify  # ARM 1's expectation INVERTED; exit 1

**THE PLANT NEVER WRITES THE TREE.** Every arm runs in a `tempfile.mkdtemp()` scratch that
mirrors the two files the gate reads out of the port tree -- `tinybendygrad/runtime/support/hcq2.bend`
and `tinybendygrad/device.bend` -- and the gate is pointed at the scratch with `--root` while its
GIT calls are pointed at the REAL repo with `--repo`. That split is why the scratch does not have
to be a git repo: the pin lives in git and the port lives in the scratch.

THE ARMS, AND WHAT EACH ONE IS FOR.

| arm | what is planted | the gate | the lane that must fire |
|---|---|---|---|
| 0 CONTROL | nothing | **PASS** | -- |
| 1 CITATION | the prose citation `hcq2.py:20` -> `hcq2.py:21` | **FAIL** | 4, the CITATION |
| 2 THE SET | a 7th member `CL` in `HCQ_DEVS()` and in `HCQ_DEV_*`, and NOWHERE ELSE | **FAIL** | 2, the THREE TABLES, and 6, the FIDELITY |
| 3 THE PIN | a re-pin to a 584-line `hcq2.py`, where the constant is NOT in `hcq2.py` at all | **FAIL** | 4 and 6 |
| 4 NEGATIVE | a re-pin to the 626-line `hcq2.py` -- the SAME set, one line up | **PASS** | -- |

**ARM 4 IS THE UNBROKEN CONTROL FOR ARM 3, AND IT IS THE POINT OF THIS PLANT.** Both arms re-pin
the port; they differ in WHICH upstream file they re-pin to. Arm 3's re-pin lands where the set
DIFFERS and the gate goes red; arm 4's re-pin lands where the set AGREES and the gate stays
green. Without arm 4 a reader could not tell arm 3's FAIL from "this gate reds on any re-pin", and
"the gate reds on any re-pin" is a gate that measures the re-pin and not the set.

**ARM 2 IS THE PLANT THAT PAYS FOR THE WHOLE INSTRUMENT.** The port carries the same six device
names in THREE places -- `HCQ_DEVS()` (ids), `dev_head.name()` (names) and `dev_name()` (the
id->name ladder) -- and `all_in` asks `dev_id(dev_head(x)) != NO_HCQ_DEV`, so a name added to one
table and not to another makes the membership predicate disagree with the set. Nothing in the
tree checked that, and the plant shows the gate now does.

**ARM 1 IS THE CHEAPEST INSTANCE OF THE DISEASE THIS TREE HAS FOUND FIVE TIMES IN TWO DAYS**: a
prose claim that names the wrong line. The port's table row says `:20` and its comment says
`:21`, and the gate calls that a disagreement rather than picking a winner.

`--falsify` INVERTS ARM 1's expectation and MUST exit 1. A plant whose expectations cannot be
violated proves nothing, and one arm going red for the wrong reason would otherwise read as
success.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = ROOT / "gates" / "devset-census-gate.py"
PORT_FILES = ("tinybendygrad/runtime/support/hcq2.bend", "tinybendygrad/device.bend")

L_CITE = "4 the port's CITED LINE resolves AT the pin"
L_TABLES = "2 the port's THREE parallel tables agree with EACH OTHER"
L_FIDELITY = "6 the port's set IS the pin's set"

# (name, [(old, new), ...], want_exit, the lanes that MUST fire)
ARMS: tuple[tuple[str, list[tuple[str, str]], int, tuple[str, ...]], ...] = (
    ("1 CITATION", [("hcq2.py:20", "hcq2.py:21")], 1, (L_CITE,)),
    ("2 THE SET", [("def HCQ_DEV_AMD() -> U32: 6", "def HCQ_DEV_AMD() -> U32: 6\ndef HCQ_DEV_CL() -> U32: 7"),
                   ("HCQ_DEV_METAL(), HCQ_DEV_AMD()]", "HCQ_DEV_METAL(), HCQ_DEV_AMD(), HCQ_DEV_CL()]")],
     1, (L_TABLES, L_FIDELITY)),
    ("3 THE PIN", [("hcq2.py:1-646", "hcq2.py:1-584"), ("AT PIN `0a5776355`", "AT PIN `e8308c08f`")],
     1, (L_CITE, L_FIDELITY)),
    ("4 NEGATIVE", [("hcq2.py:1-646", "hcq2.py:1-626"), ("AT PIN `0a5776355`", "AT PIN `cff94ae88`"),
                    ("hcq2.py:20", "hcq2.py:19"), ("#   :20  HCQ_DEVS", "#   :19  HCQ_DEVS")],
     0, ()),
)


def scratch() -> Path:
  """A mirror of the two files the gate reads out of the port tree."""
  tmp = Path(tempfile.mkdtemp(prefix="devsetplant."))
  for rel in PORT_FILES:
    dst = tmp / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / rel, dst)
  return tmp


def run_gate(tmp: Path) -> tuple[int, str]:
  """`(exit, stdout+stderr)` of the gate against the scratch, with its git calls on the REAL repo."""
  p = subprocess.run([sys.executable, str(GATE), "--root", str(tmp), "--repo", str(ROOT)],
                     capture_output=True, text=True)
  return p.returncode, p.stdout + p.stderr


def failing(out: str) -> set[str]:
  """The lane names the gate reported as FAILED."""
  m = re.search(r"^# FAILED: \[(.*)\]$", out, re.M)
  if not m:
    return set()
  return {x.strip().strip("'\"") for x in m.group(1).split(",") if x.strip()}


def row(ok: bool, label: str) -> bool:
  print(f"  {'OK  ' if ok else 'FAIL'} {label}")
  return ok


def main() -> int:
  falsify = "--falsify" in sys.argv[1:]
  results: list[bool] = []
  before = {rel: (ROOT / rel).read_bytes() for rel in PORT_FILES}
  tmp = scratch()
  try:
    base = (tmp / PORT_FILES[0]).read_text()
    code, out = run_gate(tmp)
    results.append(row(code == 0 and not failing(out),
                       f"0 CONTROL the unplanted tree is clean (exit {code})"))

    for name, edits, want_exit, want_lanes in ARMS:
      text = base
      for old, new in edits:
        if old not in text:
          results.append(row(False, f"{name} -> the plant's own text `{old[:40]}` is NOT IN THE "
                                    f"TREE, so the arm did not plant anything"))
          text = None
          break
        text = text.replace(old, new)
      if text is None:
        continue
      (tmp / PORT_FILES[0]).write_text(text)
      code, out = run_gate(tmp)
      lanes = failing(out)
      ok = (code == want_exit) and set(want_lanes) <= lanes
      if falsify and name.startswith("1 "):
        ok = not ok
      results.append(row(ok, f"{name} -> exit {code} (want {want_exit}), lanes that fired "
                            f"{sorted(lanes)} (want {sorted(want_lanes) or 'none'} from a PASS)"))

    (tmp / PORT_FILES[0]).write_text(base)
    code, out = run_gate(tmp)
    results.append(row(code == 0 and not failing(out),
                       f"CONTROL the port was restored; the gate is clean again (exit {code})"))
    results.append(row(all((ROOT / rel).read_bytes() == b for rel, b in before.items()),
                       "CONTROL the REAL tree was never written"))
  finally:
    shutil.rmtree(tmp, ignore_errors=True)
  print(f"--- {sum(results)} of {len(results)} arm(s) behaved as required"
        + ("   [FALSIFY: ARM 1's expectation was inverted, so the failure below is required]"
           if falsify else ""))
  return 0 if all(results) else 1


if __name__ == "__main__":
  sys.exit(main())
