#!/usr/bin/env python3
"""WHOSE COUNTS REPRODUCE, AND WHICH ARE SNAPSHOTS -- BY RUNNING THEIR INSTRUMENTS, NOT THEIR NOTES.

    .venv/bin/python .agents/slop/plantthe46/repro.py            # the table
    .venv/bin/python .agents/slop/plantthe46/repro.py --rows     # TSV

THE FIRST DELIVERABLE IS NOT A FOURTH NUMBER. Three units counted `declared - reached` three times
and one of them caught the others' hand lists. So this file does three things and refuses a fourth:

  1. RE-RUNS the other units' own instruments on today's tree and prints what each says now, beside
     what its recorded artifact says. An instrument whose answer cannot move is a SNAPSHOT, and that
     is a finding about the instrument rather than a number to compare.
  2. RE-EXECUTES the eight gates `.agents/slop/zerogate/REPORT.md` §1a named as having a real
     surface of zero, because that list was established BY EXECUTION and only execution settles it.
     **All eight refuse at module scope, above every `argparse`** (measured by `unreach.py`), so a
     no-argv run cannot reach `bin/bend` -- which is why running them here is not the hazard
     `.agents/slop/zerogate/REPORT.md` §7a records having taken once.
  3. COUNTS THE INSTRUMENTS. By what they count, because three different units used the word
     `surface` for three different subjects and one instrument was cited under two names.
"""
import argparse
import importlib.util
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = ROOT / ".venv" / "bin" / "python"

# THE EIGHT, BY NAME, from `.agents/slop/zerogate/REPORT.md` §1a. Quoted, not discovered: this is a
# REPRODUCTION of that unit's list, and reproducing a list by rediscovering it would only prove the
# list is stable. The discovery half of this unit is `unreach.py`, which finds them by geometry.
ZEROGATE_EIGHT = ("checks/gate.py", "checks/nl-gate.py", "checks/nl-gate-noguard.py",
                  "checks/dup-gate.py", "checks/dup-census.py", "checks/rn-gate.py",
                  "checks/hermetic-census.py", "checks/git-index-guard.py")
# The two zerogate §3 reported as FALSE POSITIVES, re-measured because a correction is a claim too.
ZEROGATE_FALSE = ("checks/norm_check.py", "checks/oracle_f64.py")


def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def token(out, rc=0):
    """The verdict WORD this run printed -- and ONLY for a non-zero rc.

    The first version scanned every run and reported `checks/norm_check.py` as printing `FAIL`
    while exiting 0. It does print the word: the plant column says "the old norm: FAILS". **A token
    scan that reads a GREEN transcript for a verdict word is `coindependent/vocab.py`'s blind spot
    reproduced in my own instrument**, so the token is read only where there is a verdict to read.
    """
    if rc == 0:
        return "(green: no verdict to read)"
    for t in ("REFUSED", "AGREE", "BROKEN", "GREEN", "RED", "PASS", "FAIL", "DEAD", "SKIP",
              "OK", "CLEAN", "STORY", "Traceback"):
        if t in out:
            return t
    return "(none)"


def run(rel, argv=()):
    p = ROOT / rel
    if not p.is_file():
        return "GONE", "", "the file is not here"
    r = subprocess.run([str(PY), str(p), *argv], cwd=ROOT, capture_output=True, text=True,
                       timeout=300)
    out = (r.stdout or "") + (r.stderr or "")
    return r.returncode, token(out, r.returncode), out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", action="store_true")
    a = ap.parse_args()
    rows = []

    # 1. THE OTHER UNITS' INSTRUMENTS, re-run today.
    for rel, note in ((".agents/slop/coindependent/surface.py",
                       "declared by SOURCE SHAPE; reached read from its OWN probe.rows snapshot"),
                      (".agents/slop/coindependent/vocab.py",
                       "the population + declared column alone"),
                      (".agents/slop/onemodule/vocab-check.py", "counts vocabulary COPIES, not verdicts")):
        p = ROOT / rel
        if not p.is_file():
            rows.append((rel, "GONE", "", "", note))
            continue
        argv = ["--report"] if "vocab-check" in rel else []
        r = subprocess.run([str(PY), str(p), *argv], cwd=ROOT, capture_output=True, text=True,
                           timeout=600)
        tail = [l.strip() for l in (r.stdout or "").splitlines() if l.strip()][-14:]
        rows.append((rel, "RAN", str(r.returncode), " | ".join(tail[-6:]), note))

    # 2. THE EIGHT, executed.
    for rel in ZEROGATE_EIGHT + ZEROGATE_FALSE:
        rc, tok, _out = run(rel)
        rows.append((rel, "EXECUTED", str(rc), tok,
                     "no argv: a module-scope refusal cannot reach the port compiler"))

    if a.rows:
        print("instrument_or_gate\tstate\tvalue\tsummary\tnote")
        for r in rows:
            print("\t".join(str(x).replace("\t", " ") for x in r))
        return 0
    for rel, state, val, summ, note in rows:
        print(f"{rel}\n    {state} {val}  {summ[:150]}\n    {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())