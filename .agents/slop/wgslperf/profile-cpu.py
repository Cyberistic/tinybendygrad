#!/usr/bin/env python3
"""**THE **V8 **CPU **PROFILE **OF **THE **COMPILED **FORM**, **AT **THE **CURRENT **TREE.**

**WHY.** THE TREE's OWN RULE: A COUNT WITHOUT THE COMMAND THAT PRODUCED IT IS NOT A MEASUREMENT,
SO THE COMMAND IS IN THIS FILE AND IN THE DOCSTRING. THE INSTRUMENTED CLOCKS
(`profile-wgsl.py`) ARE INCLUSIVE, SO A NESTED CALL IS COUNTED TWICE; V8's OWN PROFILE CARRIES
THE EXCLUSIVE TIME, AND IT IS OF THE COMPILED FORM -- THE SAME FORM THE PAGE RUNS.

**THE **COMMANDS.**
  `.venv/bin/python .agents/slop/wgslperf/profile-cpu.py`        -- build, profile, read.
  `.venv/bin/python .agents/slop/wgslperf/profile-cpu.py --keep` -- keep the old profile too.

**THE **OUTPUT.** THE EXCLUSIVE TIME PER FUNCTION, AND (WITH `--callers NAME`) THE CALLERS OF A
FUNCTION, BOTH READ OFF THE PROFILE's OWN CALL TREE.
"""

import collections
import json
import pathlib
import subprocess
import sys
import time

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents/slop/wgslperf"
BEND = R / "bin/bend"

sys.path.insert(0, str(HERE))
import wgslbase
PROF = HERE / "prof"
DRIVER = HERE / "cpuprof.run.mjs"


def build(tree: pathlib.Path | None = None) -> pathlib.Path:
  """**THE **COMPILED **FORM**, **BUILT **FROM **THE **CURRENT **TREE** -- **⇒⇒† AND **AND **A
  **STALE **BUILD **IS **A **SECOND **SOURCE **OF **TRUTH**.

  **⇒⇒† AND **AND **A **`tree` **OVERRIDES **THE **WORKING **TREE** (⇒⇒† AND **AND **THAT **IS **HOW
  **A **TREE **IS **MEASURED **WHILE **ANOTHER **PANE **IS **MID-EDIT **IN **THE **SHARED
  **ONE**)**."""
  out = HERE / "wgslprof.cpu.mjs"
  driver = wgslbase.driver_for(tree, "probundle") if tree else (HERE / "wgslprof.bend")
  b = subprocess.run([str(BEND), str(driver), "-o", str(out)],
                     capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: the driver did not build:\n{b.stderr[:1500]}")
  return out


def run_profile() -> pathlib.Path:
  PROF.mkdir(exist_ok=True)
  for old in PROF.glob("*.cpuprofile"):
    old.unlink()
  env = dict(subprocess.os.environ)
  t0 = time.perf_counter()
  b = subprocess.run(["node", "--cpu-prof", "--cpu-prof-dir", str(PROF), str(DRIVER)],
                     capture_output=True, text=True, env=env, cwd=str(HERE))
  wall = (time.perf_counter() - t0) * 1000
  if b.returncode != 0:
    print(b.stderr[:2000])
    raise SystemExit("WARN: the driver did not run")
  print(b.stdout.strip())
  print(f"THE WHOLE DRIVER: {wall:.1f} ms (the node process, including the start-up)")
  profs = sorted(PROF.glob("*.cpuprofile"))
  if not profs:
    raise SystemExit("WARN: no profile was written")
  return profs[-1]


def read(path: pathlib.Path):
  P = json.loads(path.read_text())
  byid = {n["id"]: n for n in P["nodes"]}
  parent = {}
  for n in P["nodes"]:
    for c in n.get("children", []):
      parent[c] = n["id"]
  hit = collections.Counter(P["samples"])
  total = sum(hit.values())
  return byid, parent, hit, total


def main():
  tree = (pathlib.Path(sys.argv[sys.argv.index("--tree") + 1]) / "tinybendygrad") if "--tree" in sys.argv else None
  build(tree)
  path = run_profile()
  byid, parent, hit, total = read(path)
  print(f"THE PROFILE: {path.name}  ({total:,} samples)")
  print("THE EXCLUSIVE TIME:")
  rows = []
  for nid, c in hit.items():
    n = byid.get(nid)
    if not n:
      continue
    cf = n["callFrame"]
    rows.append((c, cf.get("functionName") or "(anonymous)", (cf.get("url") or "").split("/")[-1]))
  rows.sort(reverse=True)
  for c, name, url in rows[:30]:
    if c < 3:
      break
    print(f"  {c:7,}  {100.0*c/total:5.1f}%  {name}  [{url}]")
  if "--callers" in sys.argv:
    want = sys.argv[sys.argv.index("--callers") + 1]
    callers = collections.Counter()
    mine = 0
    for nid, c in hit.items():
      n = byid.get(nid)
      if not n:
        continue
      name = n["callFrame"].get("functionName") or "(anonymous)"
      if want not in name:
        continue
      mine += c
      p = parent.get(nid)
      who = "(the root)"
      while p is not None:
        pn = byid.get(p)
        if pn is None:
          break
        pname = pn["callFrame"].get("functionName") or "(anonymous)"
        if want not in pname:
          who = pname
          break
        p = parent.get(p)
      callers[who] += c
    print(f"THE SAMPLES ON `{want}`: {mine:,}  ({100.0*mine/total:.1f}%)")
    print("THE CALLERS:")
    for who, c in callers.most_common(20):
      if c < 2:
        break
      print(f"  {c:6,}  {100.0*c/total:5.1f}%  {who}")


if __name__ == "__main__":
  main()
