#!/usr/bin/env python3
"""Prove the substitution DISCOVERY can go red.  Reads `.agents/slop/disagree/names.py`
BY PATH (it lives under `.agents/slop/`, so `checks/` is not on `sys.path`), and calls its
`dispatcher_substitutions(bend, py)` -- the one function the gate now consumes.

Three readings, each on a SCRATCH copy of the dispatcher, never the tree's own file:

  HEAD blob   `git show HEAD:.agents/slop/graphcmp.bend` -- 29 arms, the four
              `custom_function`/`mselect`/`mstack`/`stage` NOT routed;
  working     the tree's dispatcher, whatever `armfour` has landed by run time;
  PLANT       the working dispatcher with ONE arm REMOVED (the whole `Bool.pick` node
              collapsed to its else) -- the removed graph MUST be named -- then RESTORED,
              when it MUST NOT be.

The discovery is a pure function of the two source texts, so every reading is a scratch
file and the tree is never written.  A discovery that cannot go red here cannot see the
next un-armed graph.
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
NAMES = ROOT / ".agents" / "slop" / "disagree" / "names.py"
BEND = ROOT / ".agents" / "slop" / "graphcmp.bend"
PY = ROOT / ".agents" / "slop" / "graphcmp.py"


def by_path(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def measure(names_mod, py: Path, text: str) -> list[str]:
  with tempfile.TemporaryDirectory() as td:
    scratch = Path(td) / "graphcmp.bend"
    scratch.write_text(text)
    return names_mod.dispatcher_substitutions(scratch, py)


def unarm(text: str, graph: str) -> str:
  """Collapse `Bool.pick(O.Found, String.eq(name, "<graph>"), g_<graph>(),` and its else
  branch into just the else: one `Bool.pick(` opens one paren, so the whole arm LINE goes
  and ONE `)` after the fallback on the next line goes with it."""
  lines = text.splitlines(keepends=True)
  arm = next(i for i, l in enumerate(lines) if f'String.eq(name, "{graph}")' in l)
  nxt = lines[arm + 1]
  cut = nxt.index("g_matmul()") + len("g_matmul()")
  assert nxt[cut] == ")", nxt
  del lines[arm]
  lines[arm] = nxt[:cut] + nxt[cut + 1:]
  return ''.join(lines)


def main() -> int:
  names_mod = by_path("nameshandlist_mod", NAMES)
  head = subprocess.run(["git", "show", "HEAD:.agents/slop/graphcmp.bend"],
                        cwd=ROOT, capture_output=True, text=True, check=True).stdout
  work = BEND.read_text()

  readings = {
    "HEAD blob (armfour's four arms absent)": measure(names_mod, PY, head),
    "working tree (armfour's arms as landed)": measure(names_mod, PY, work),
  }
  planted = unarm(work, "stage")
  readings["PLANT: stage arm removed from a scratch copy"] = measure(names_mod, PY, planted)
  readings["PLANT restored"] = measure(names_mod, PY, work)

  # The two states that make it a proof, not a print: the plant NAMES the removed graph,
  # and the restore does NOT.  Anything else is a discovery that cannot go red.
  fails = []
  if "stage" not in readings["PLANT: stage arm removed from a scratch copy"]:
    fails.append("the plant did not name the removed `stage` arm")
  if readings["PLANT restored"] != readings["working tree (armfour's arms as landed)"]:
    fails.append("the restore did not return the working-tree reading")

  print(json.dumps(readings, indent=2))
  for why in fails:
    print(f"FAIL: {why}", file=sys.stderr)
  return 1 if fails else 0


if __name__ == "__main__":
  raise SystemExit(main())
