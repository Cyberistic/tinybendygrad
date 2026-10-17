#!/usr/bin/env python3
"""corpuslane-mutate.py -- PROVE `gates/corpuslane-gate.py` IS A DETECTOR, NOT A RITE.

    .venv/bin/python gates/corpuslane-mutate.py

A gate that has never been seen to go red is a gate whose green is unfalsifiable, and this
one is the answer to a measured failure: `checks/differ.py` reported `graphs-agree=34` from
PRE-re-vendor artefacts while the lane raised on 30 of 34 graphs. So the gate is pointed at
MUTATED COPIES OF THE DRIVER and each mutation must move its verdict.

THE MUTATIONS ARE THE RE-VENDOR, RUN BACKWARDS. Each is a single edit that reinstates one
measured break, so a green here is a claim that the gate detects exactly the class of
failure it was written for -- and, because they are the real breaks, a mutation that does
NOT go red is a hole in the gate rather than a redundant test.

  1. `size_of` reads `pa.size` again          -- `72f98ffe0` took the field out
  2. one `toposort(enter_calls=True)` loses its argument -- the default was FLIPPED
  3. one hand-written storage node goes back to `src=()`  -- `src[0]` is dereferenced
  4. `hcq_fence` is called with four arguments            -- it lost its `tv`
  5. `load_tinygrad` stops filling `COMM`                  -- a latent defect, silent
  6. THE CONTROL. An edit that cannot change any row.

(6) IS THE ONE THAT MATTERS MOST, and it is the reason this file is not just the five above:
a gate that is a CHANGE-DETECTOR -- one that goes red on any edit at all -- would pass
mutations 1-5 while measuring nothing. (6) is a comment-only edit, so a gate that cannot
tell a comment from a defect is exposed. `AGENTS.md`: "Change-detector tests considered
harmful."

Nothing here writes to the tree: every mutation is applied to a COPY under a temporary
directory and the gate is invoked with `--driver`, which exists for exactly this.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PY = ".venv/bin/python"
DRIVER = ROOT / ".agents" / "slop" / "graphcmp.py"
GATE = ROOT / "gates" / "corpuslane-gate.py"

# (label, find, replace, expected exit, why it must move the verdict)
MUTATIONS = [
  ("size", "return src[0] if src and isinstance(src[0], int) else None",
   "return src[0].arg if src and isinstance(src[0].arg, int) else None",
   1, "reads `ParamArg.size` off a record that no longer has it -> a MISSING ATTR, not a raise"),
  ("toposort", "lst = list(ast.toposort(enter_calls=True))", "lst = list(ast.toposort())",
   1, "the flipped default drops a CALL's whole body -> `loop` raises `KeyError`"),
  ("src", "return UOp(op, src=(UOp(Ops.STACK),) if size is None else (UOp.const(size),),",
   "return UOp(op, src=(),",
   1, "`_shape` dereferences `src[0]` of an empty src -> `IndexError`"),
  ("hcq_fence", "return hcq_fence(tv, tv, 0)", "return hcq_fence(tv, tv, tv, 0)",
   1, "`hcq_fence` lost its `tv` parameter -> `TypeError`"),
  ("comm", "  COMM = commutative()", "  pass  # COMM left empty",
   1, "an uninitialised `COMM` -> `plant srcswap` raises, and it must NOT be a silent pass"),
  ("control-comment", "BEND = REPO / \"bin\" / \"bend\"",
   "BEND = REPO / \"bin\" / \"bend\"  # a comment that changes no row",
   0, "THE CONTROL: a comment edit moves nothing, so a green here is a measurement"),
]


def run_gate(driver: pathlib.Path) -> tuple[int, str]:
  p = subprocess.run([PY, str(GATE), "--driver", str(driver)], cwd=ROOT,
                     capture_output=True, text=True,
                     env={k: v for k, v in __import__("os").environ.items() if k != "PYTHONPATH"})
  return p.returncode, (p.stdout + p.stderr).strip().splitlines()[-1] if (p.stdout + p.stderr).strip() else ""


def main() -> int:
  src = DRIVER.read_text()
  bad = []
  print("# baseline on the REAL driver")
  rc, last = run_gate(DRIVER)
  print(f"  baseline           exit={rc}  {last}")
  if rc != 0: bad.append("baseline")

  with tempfile.TemporaryDirectory() as td:
    for label, find, repl, want, why in MUTATIONS:
      if find not in src:
        print(f"  {label:16s} ANCHOR ABSENT -- the mutation no longer applies: {find!r}")
        bad.append(f"{label}:anchor")
        continue
      copy = pathlib.Path(td) / f"{label}.py"
      copy.write_text(src.replace(find, repl, 1))
      rc, last = run_gate(copy)
      mark = "ok " if rc == want else "BAD"
      print(f"  {label:16s} exit={rc} want={want} {mark} {why}")
      if rc != want: bad.append(label)
      if label == "control-comment" and rc != 0:
        print("    ^ A COMMENT EDIT MOVED THE VERDICT: this gate is a change detector.")

  print(f"# {len(MUTATIONS) + 1 - len(bad)} of {len(MUTATIONS) + 1} expectations held")
  if bad:
    print(f"corpuslane-mutate: FAIL -- {', '.join(bad)}", file=sys.stderr)
    return 1
  print("corpuslane-mutate: PASS -- every re-vendor break is detected, and a comment is not")
  return 0


if __name__ == "__main__":
  sys.exit(main())