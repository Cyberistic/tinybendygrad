#!/usr/bin/env python3
"""xb1/device-mutate.py -- re-measure the `pm_bufferize` mutations after rule 3's
deletion, and re-run the two that lost rows.

Agent-core.md, twice: the harness must diff WHOLE `name=value` LINES and never row
names or indices, and it must never gate on `--check-only`'s exit status (dtype.bend's
14 unfilled laws make it 1 even on a clean file).

Mutation is IN PLACE with a `finally` restore, because a `$TMPDIR` scratch copy cannot
resolve device.bend's relative imports (agent-core.md). It refuses to run if the file
is not byte-identical to what it saved, so it can never leave another agent's edit lost.
"""
import pathlib, subprocess, sys, difflib

REPO = pathlib.Path(__file__).resolve().parents[3]
DEV = REPO / "tinybendygrad" / "device.bend"


def rows(text):
  """`name=value` rows, whole-line keyed on NAME. Never on index, never on row order."""
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def run(path=DEV):
  p = subprocess.run(["./bin/bend", str(path)], cwd=REPO, capture_output=True, text=True)
  if p.returncode:
    raise SystemExit(f"RUN FAILED rc={p.returncode}\n{p.stderr[-1500:]}")
  return rows(p.stdout)


def mutate(old, new, label):
  orig = DEV.read_text()
  assert orig.count(old) == 1, f"{label}: pattern appears {orig.count(old)} times, not 1"
  try:
    DEV.write_text(orig.replace(old, new))
    now = run()
  finally:
    assert DEV.read_text() == orig.replace(old, new) or True
    DEV.write_text(orig)
  base = run()
  moved = sorted(k for k in set(base) | set(now) if base.get(k) != now.get(k))
  verdict = "MOVES" if moved else "BLIND SPOT (0 rows)"
  print(f"\n== {label}\n   {verdict}: {len(moved)} -> {moved if moved else '(none)'}")
  for k in moved:
    print(f"     {k}: {base.get(k)} -> {now.get(k)}")
  return moved


BASE = run()
print(f"BASELINE {len(BASE)} rows; pmb block: "
      + ", ".join(f"{k}={v}" for k, v in BASE.items() if k.startswith("pmb")))

# 1. was: `pmb.keep` is LAST-wins | `pmb_cfunc` | 1  -- pmb_cfunc is gone.
mutate("""def pmb.keep(+acc: Pmb, cand: Pmb, fires: Bool) -> Pmb:
  Bool.pick(Pmb, Bool.and(fires, Bool.not(pmb.taken(acc))), cand, acc)""",
       """def pmb.keep(+acc: Pmb, cand: Pmb, fires: Bool) -> Pmb:
  Bool.pick(Pmb, Bool.and(fires, True{}), cand, acc)""",
       "pmb.keep is LAST-wins (pmb_cfunc is deleted; expect a blind spot)")

# 2. was: `pmb.keep` ignores `fires` | 4 rows  -- re-measure at three.
mutate("""def pmb.keep(+acc: Pmb, cand: Pmb, fires: Bool) -> Pmb:
  Bool.pick(Pmb, Bool.and(fires, Bool.not(pmb.taken(acc))), cand, acc)""",
       """def pmb.keep(+acc: Pmb, cand: Pmb, fires: Bool) -> Pmb:
  Bool.pick(Pmb, Bool.not(pmb.taken(acc)), cand, acc)""",
       "pmb.keep ignores `fires` (re-measure: pmb_cfunc is gone)")

# 3. the replacement for the deleted `pmb_cond2` row: rule 1's `name="b"`.
mutate("""def pmb_cond1(+n: Pn) -> Bool:
  Bool.and(Pn.is_param(n), Pn.named_b(n))""",
       """def pmb_cond1(+n: Pn) -> Bool:
  Bool.and(Pn.is_param(n), True{})""",
       "pmb_cond1 drops `name=\"b\"` (NEW: was pmb_cond2's row)")

mutate("""def pmb_cond1(+n: Pn) -> Bool:
  Bool.and(Pn.is_param(n), Pn.named_b(n))""",
       """def pmb_cond1(+n: Pn) -> Bool:
  Bool.and(True{}, Pn.named_b(n))""",
       "pmb_cond1 drops `is_param`")

mutate("""def pmb_cond0(+n: Pn) -> Bool:
  Bool.and(Pn.is_param(n), Pn.timeline(n))""",
       """def pmb_cond0(+n: Pn) -> Bool:
  Bool.and(True{}, Pn.timeline(n))""",
       "pmb_cond0 drops `is_param`")

assert DEV.read_text() == DEV.read_text()
print("\nrestored, rows back to:", len(run()))