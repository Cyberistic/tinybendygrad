#!/usr/bin/env python3
"""THE PER-ROW CONTROLS -- and the control ON the control.

    .venv/bin/python .agents/slop/backward2/ctl-rows.py <got.rows> <want.rows>

FOR EVERY ROW, TWICE:
  (a) a WRONG BUT NON-EMPTY expectation  -> the gate must report EXACTLY that row and
      every other row must still PASS.  *** THIS IS THE CONTROL ON THE CONTROL: a gate
      that only caught EMPTY values would be catching VACUITY, not WRONGNESS. ***
  (b) an EMPTY expectation                 -> the gate must report EXACTLY that row.

and once:
  (c) the UNPERTURBED expectations          -> the gate must PASS.

The perturbation is MECHANICAL and is stated here so it is not a choice made per row:
a numeric value becomes `value + 1`; any other value has its LAST CHARACTER replaced by
a different one, so the wrong value is still a plausible value of the same shape and
is NOT empty.

Exits 0 iff every control behaved as stated.
"""
import subprocess
import sys
import tempfile
import os

GATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gate.py")


def load(path):
  rows = []
  for line in open(path):
    line = line.rstrip("\n")
    if "=" in line:
      k, _, v = line.partition("=")
      rows.append((k, v))
  return rows


def perturb_nonempty(v):
  if v.isdigit():
    return str(int(v) + 1)
  if not v:
    return "X"
  return v[:-1] + ("0" if v[-1] != "0" else "1")


def run(got, want):
  """Returns (mismatched_row_names, verdict)."""
  with tempfile.NamedTemporaryFile("w", suffix=".rows", delete=False) as f:
    f.write(want)
    tmp = f.name
  try:
    p = subprocess.run([sys.executable, GATE, got, tmp], capture_output=True, text=True)
  finally:
    os.unlink(tmp)
  names = []
  for line in p.stdout.splitlines():
    s = line.strip()
    if s.startswith("MISMATCH "):
      names.append(s[len("MISMATCH "):])
  verdict = "PASS" if "VERDICT: PASS" in p.stdout else "FAIL"
  return names, verdict, p.stdout


def main():
  got_path, want_path = sys.argv[1], sys.argv[2]
  rows = load(want_path)

  names, verdict, out = run(got_path, want_path)
  ok = verdict == "PASS"
  print("(c) the UNPERTURBED expectations -> %s  %s" % (verdict, "OK" if ok else "NOT OK"))
  if not ok:
    print(out)
  fails = 0 if ok else 1

  for k, v in rows:
    # (a) WRONG BUT NON-EMPTY
    bad = perturb_nonempty(v)
    want = "".join("%s=%s\n" % (kk, bad if kk == k else vv) for kk, vv in rows)
    names, verdict, out = run(got_path, want)
    good = (verdict == "FAIL") and (names == [k])
    print("(a) %-14s wrong-but-non-empty -> %s  mismatched=%s  %s"
          % (k, verdict, names, "OK" if good else "NOT OK"))
    if not good:
      fails += 1
      print(out)
    # (b) EMPTY
    want = "".join("%s=%s\n" % (kk, "" if kk == k else vv) for kk, vv in rows)
    names, verdict, out = run(got_path, want)
    good = (verdict == "FAIL") and (names == [k])
    print("(b) %-14s empty              -> %s  mismatched=%s  %s"
          % (k, verdict, names, "OK" if good else "NOT OK"))
    if not good:
      fails += 1
      print(out)

  print("CONTROLS: %d rows x 2 perturbations + the clean run -> failures: %d"
        % (len(rows), fails))
  sys.exit(0 if fails == 0 else 1)


main()
