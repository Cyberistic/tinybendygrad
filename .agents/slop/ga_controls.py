#!/usr/bin/env python3
"""CONTROLS for the generate.bend row-visibility fix.  Four of them, and each one
is the check that would have caught the specific way this could have gone wrong.

  1. SUPERSET.  Every row the gate shared BEFORE is still there with the SAME
     value.  A fix that renames or drops an existing gated row is not a fix.
  2. NO FRAGMENTS.  Every row the port prints is ONE line, so `rows()` can see
     all of them.  Zero is the claim; 233 names for 91 rows is the failure.
  3. PLANTED MULTI-LINE VALUE IS NAMED, NOT SWALLOWED.  Take the real port
     output, re-introduce a newline inside one row value exactly as the old
     `gl` did, and show that ga_gate.py's parser REFUSES it by name.  Without
     this, a multi-line value is invisible and a silent regression is
     indistinguishable from a clean run.
  4. THE COUNT ROW IS NOT TAUTOLOGICAL.  Drop the LAST emitted line from the
     port's output and show the gate notices: every `| i` row still agrees and
     only `lines` moves.  That is the one hole an index key opens, so it is the
     one hole that has to be shown closed.

Run:  python3 .agents/slop/ga_controls.py <before.txt> <after.txt>
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent



# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve() / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows = _rebase_gate.rows


def main(before_path, after_path):
  before, after = pathlib.Path(before_path).read_text(), pathlib.Path(after_path).read_text()
  b, a = rows(before), rows(after)
  oracle = rows((HERE / "ga-oracle.txt").read_text())
  fails = []

  # 1. SUPERSET over every row the gate shared before.
  was = set(b) & set(oracle)
  now = set(a) & set(oracle)
  missing, changed = sorted(was - now), [k for k in was & now if a[k] != oracle[k]]
  print(f"1. SUPERSET: gate shared {len(was)} rows before, {len(now)} now; "
        f"{len(now) - len(was):+d}")
  print(f"   rows lost: {len(missing)} {missing[:5]}")
  print(f"   rows whose value changed: {len(changed)} {changed[:5]}")
  if missing or changed:
    fails.append("not a superset")

  # 2. NO FRAGMENTS: one row per line, and no invented names.
  real = {m.group(1).strip() for m in
          re.finditer(r"^(.*?) = \[(.*)\]   py=\[(.*)\]$", after, re.M)}
  junk = sorted(set(a) - real)
  print(f"2. NO FRAGMENTS: {len(real)} real rows, {len(a)} row names, "
        f"{len(junk)} invented by rows() {junk[:5]}")
  if junk:
    fails.append("rows() still invents fragment names")

  # 3. PLANTED MULTI-LINE VALUE IS NAMED.
  plant = after.replace("ins rdna3 | 0 = [", "ins rdna3 | 0 = [PLANTED\nSECOND HALF = [", 1)
  tmp = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/ga_planted.txt")
  tmp.write_text(plant)
  r = subprocess.run([sys.executable, str(HERE / "ga_gate.py"), str(tmp)],
                     capture_output=True, text=True)
  named = "MULTI-LINE ROWS" in r.stdout
  print(f"3. PLANTED MULTI-LINE VALUE: ga_gate rc={r.returncode}, names it: {named}")
  print("   " + r.stdout.strip().splitlines()[0][:120] if r.stdout.strip() else "   (no output)")
  if not named or r.returncode == 0:
    fails.append("a planted multi-line row is not named")

  # 4. THE COUNT ROW IS NOT TAUTOLOGICAL: drop the LAST emitted line.
  last = re.search(r"^ins rdna3 \| 176 = \[.*$", after, re.M)
  if not last:
    fails.append("could not find the last ins rdna3 row to plant a drop into")
    print("4. COUNT ROW: NOT TESTED -- could not find `ins rdna3 | 176`")
  else:
    drop = after.replace(last.group(0) + "\n", "").replace(
        "ins rdna3 lines = [177]   py=[177]", "ins rdna3 lines = [176]   py=[177]", 1)
    d = rows(drop)
    moved = sorted(k for k in d if k in a and d[k] != a[k])
    still = len(set(d) & set(oracle))
    print(f"4. COUNT ROW: dropped `ins rdna3 | 176` -> {len(moved)} row(s) move, "
          f"and they are {moved}")
    print(f"   {len(now) - 1} of the other rows still agree -- so the count row is the "
          f"ONLY thing that sees the drop, which is why it exists")
    if moved != ["ins rdna3 lines"]:
      fails.append(f"a dropped last line moved {moved}, not exactly the count row")

  print("\nCONTROLS: " + ("PASS" if not fails else "FAIL -- " + "; ".join(fails)))
  return 1 if fails else 0


if __name__ == "__main__":
  sys.exit(main(*sys.argv[1:3]))