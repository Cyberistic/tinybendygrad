#!/usr/bin/env python3
"""The three-lane diff for tinybendygrad/runtime/ops_metal.bend.

  .venv/bin/python .agents/slop/mt_diff.py [port.bend]

FIVE lanes, and lanes 3-5 are the reason this file can be trusted with its
constants:

  1. INTERPRETED        `bin/bend <file>`
  2. NATIVE             `bin/bend <file> -o x && x`   (named file: `-o -` writes 0 bytes)
  3. `mt_rows.py`       the graph oracle
  4. `mt_constmap.py`   EVERY numeric constant def, against ITS OWN authority --
     `autogen/metal.py` by getattr, `ops_metal.py` by CPython's `ast`, a real
     `MetalDevice` and a real kernel launch for what is only knowable by running it
  5. `mt_seam_rows.py`  the real `MTLCodeGenServiceBuildRequest`, instrumented
     callback, for `:42-71`

Lane 1 and 2 must be byte-identical. Lanes 3-5 are compared ROW BY ROW against
lane 1, and an oracle row with no gate row (or the reverse) is reported, because
"0 disagreements" over an unmatched pair is the reconciliation failure that
`ops_nv` shipped.

A LANE THAT DID NOT RUN IS NOT A RESULT. On this machine lane 4 dies -- clang
cannot compile the `DEV=CPU` kernel it launches, so `mt_constmap.py` exits 1 with
a 150-line C error dump -- and the old wrapper printed that dump and nothing else,
which reads like a gate failure rather than an absent gate. Now every lane reports
`LANE DID NOT RUN` with its reason, every lane's row count is printed, and a lane
with 0 rows fails instead of contributing 0 agreements.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / "tinybendygrad/runtime/ops_metal.bend"
PY = str(ROOT / ".venv/bin/python")
ORACLES = {
    "graph": [PY, ".agents/slop/mt_rows.py"],
    "const": [PY, ".agents/slop/mt_constmap.py", "--rows", None],   # None -> the port
    "seam": [PY, ".agents/slop/mt_seam_rows.py"],
}



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


def lane(name, cmd):
  """Run one lane or say plainly that it did not run. `tail` is what a reader
  wants: an absent check reported as 150 lines of C errors is a check nobody
  reads twice."""
  r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
  if r.returncode != 0:
    print("LANE DID NOT RUN [%s]: %s exited %d\n  %s"
          % (name, " ".join(str(c) for c in cmd[:2]), r.returncode,
             "\n  ".join((r.stderr or r.stdout).strip().splitlines()[-6:])))
    return None
  return r.stdout


def main():
  bend = sys.argv[1] if len(sys.argv) > 1 else str(BEND)
  print("CHECK:", (lane("check", [str(ROOT / "bin/bend"), bend, "--check-only"]) or "").splitlines()[:1])

  print("AUTHORITIES: mt_rows.py (graph), mt_constmap.py (constants, by getattr / "
        "CPython ast / a real launch), mt_seam_rows.py (the real build request)")
  native_bin = pathlib.Path(__file__).resolve().parent / "mt.native.bin"
  interp = lane("interpreted", [str(ROOT / "bin/bend"), bend])
  build = lane("native-build", [str(ROOT / "bin/bend"), bend, "-o", str(native_bin)])
  native = None
  if build is not None:
    native_bin.chmod(0o755)
    native = lane("native-run", [str(native_bin)])
  texts = {k: lane("oracle:" + k, [bend if c is None else c for c in v])
           for k, v in ORACLES.items()}
  if None in (interp, native, *texts.values()):
    print("\nGATE DID NOT RUN: at least one lane produced no output. Nothing was compared.")
    return 1

  i, n = rows(interp), rows(native)
  o = {k: rows(v) for k, v in texts.items()}
  print("\nROWS COUNTED, EACH LANE SEPARATELY")
  for k, v in (("interpreted", i), ("native", n), *sorted(o.items())):
    print("  %-11s: %d rows" % (k, len(v)))
  empty = [k for k, v in [("interpreted", i), ("native", n), *sorted(o.items())] if not v]
  if empty:
    print("\nGATE DID NOT RUN: 0 rows from %s -- a lane with no rows has nothing to "
          "disagree about, and reporting it as agreement is how a gate lies." % ", ".join(empty))
    return 1

  bad = 0
  if i != n:
    bad = 1
    print("\nINTERPRETED vs NATIVE")
    for k in sorted(set(i) | set(n)):
      if i.get(k) != n.get(k):
        print(f"  {k}: interp={i.get(k)!r} native={n.get(k)!r}")
  else:
    print("interpreted == native  (byte identical)")

  agree = differ = only = 0
  compared = 0
  for lane_name, o_rows in sorted(o.items()):
    print(f"\nCPYTHON ORACLE [{lane_name}] -- {len(o_rows)} rows, "
          f"{len(set(o_rows) & set(i))} compared with the interpreted lane")
    compared += len(set(o_rows) & set(i))
    for k, v in sorted(o_rows.items()):
      if k not in i:
        print(f"  ORACLE-ONLY  {k}={v!r}")
        only += 1
      elif i[k] == v or (v in ("1", "0") and i[k] == str(v == "1")):
        agree += 1
      else:
        print(f"  DIFFER  {k}: oracle={v!r} bend={i[k]!r}")
        differ += 1
        bad = 1
  print(f"\nagree={agree} differ={differ} oracle-only={only} bend-only={len(i) - agree - differ - only} "
        f"COMPARED={compared} of {len(i)} gate rows")
  if not compared:
    print("GATE DID NOT RUN: 0 rows compared -- nothing can be red, so this is not a pass.")
    return 1
  print("PROBLEMS" if bad else "ALL LANES AGREE")
  return bad


if __name__ == "__main__":
  sys.exit(main())