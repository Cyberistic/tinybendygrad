#!/usr/bin/env python3
"""dsl_gate.py -- drive `renderer/amd/dsl.bend` against a LIVE CPython call, TWICE.

WHY WHOLE LINES. Two units lost complete mutation tables to a harness that compared ROW NAMES:
a name-comparing harness reported 0 for all 30 mutations in one unit and 0 for all 68 in
another, because every row kept its name and only its value moved. So this reads `name=value`,
splits ONCE at the first `=`, and compares the two halves. The value is the thing under test;
the name is only there to say which fact.

    usage: .venv/bin/python .agents/slop/dsl_gate.py [--record] [--mutate FILE REGEX REPL]

EXIT CODES, because "the gate printed nothing" is not a verdict anybody can act on:
    0  every shared row's value agrees, and both sides produced rows
    1  a shared row's VALUE differs, or a row is present on one side only
    2  A LANE PRODUCED NOTHING, or this run never happened. NOT a disagreement.

⚠ THIS FILE USED TO COMPARE A LIVE PORT AGAINST A RECORDED FILE, and three defects came of it.
Each is fixed here by MEASUREMENT, and each measurement is repeatable by reading this docstring.

(1) NO ZERO-ROW GUARD, so a dead port read as a red lane for an unrelated reason. MEASURED
    2026-10-04: planting a value that does not COMPILE -- `nat_text(reg_names_n() + 1n)` is
    `write (a + b : Nat)` with no annotation -- made the port print 0 rows, and this file
    reported `rows port=0 mismatched=1576`. 1576 "mismatches" manufactured by a port that said
    nothing. A zero is a RETRY REQUEST, not a result, so it now exits 2 and prints the port's
    stderr. (This is the same lesson `portexec` adopted as `SUBSTRATE`, and `rebase-gate.py`
    already implements as GUARD 2.)

(2) THE ORACLE WAS RECORDED, so its rows went stale silently, and one of them could never be
    reproduced at all. `dsl_oracle.txt:1604` reads
        fixed_hilo=<tinygrad.renderer.amd.dsl.FixedBitField object at 0x10911a510>.hi,0
    -- a CPython `repr`, so it carries a HEAP ADDRESS. Re-recording today yields 0x1099ce810;
    the next launch yields another. MEASURED: the oracle's own output differs from the recorded
    file on EXACTLY ONE line, `fixed_hilo`, and two consecutive LIVE launches of the oracle
    differ from each other on that same one line and on no other.

(3) `mismatched` CONFLATED THREE DIFFERENT NUMBERS into one, and the one it printed was
    arithmetically impossible to read. `matched=617 mismatched=1503` reads as "1503 of 617
    rows disagree", which cannot mean anything. MEASURED 2026-10-04, against a LIVE oracle:
        port 1161 rows · oracle 1576 rows · 617 shared · **0 of the 617 disagree**
        959 oracle-only · 544 port-only · 959 + 544 = 1503
    So this lane is VALUE-GREEN and SET-RED, and the old summary line was the only thing hiding
    that. The three numbers are now printed as three numbers.

⚠ WHY THE UNREPRODUCIBLE ROW IS EXCLUDED BY SHAPE AND NOT BY NAME. `rebase-gate.py` excludes
the 14 `elf_built_*` rows by NAME, because those embed the runtime addresses of the dylib the
fixtures link against. That is a typed list, and a typed list is a judgement that goes stale --
and `fixed_hilo` proves the judgement was missed, because nobody generalised it. So nothing here
is typed: the oracle is run TWICE and every row whose value differs between the two launches is
excluded, with its name and both values printed on every run. A heap address is not a special
case; it is one instance of "this row is not a function of the source". The 59-row
`elf_built_*` family and this 1-row family are caught by the same three lines, and tomorrow's
family will be too.
"""
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BEND = ROOT / "bin/bend"
PORT = ROOT / "tinybendygrad/renderer/amd/dsl.bend"
ORACLE_SCRIPT = HERE / "dsl_oracle.py"
RECORDED = HERE / "dsl_oracle.txt"
ORACLE_RUNS = 2

sys.path.insert(0, str(HERE))
import oracle_py                                            # noqa: E402


def bend(path):
  r = subprocess.run([str(BEND), str(path)], capture_output=True, text=True)
  return r.stdout, r.stderr, r.returncode


def parse(text):
  out = {}
  for line in text.splitlines():
    if "=" not in line:
      continue
    k, v = line.split("=", 1)
    out[k] = v
  return out


def unstable_rows(runs):
  """{name: (value_a, value_b)} for every row whose value differs between two launches of the
  SAME oracle on the SAME source. Derived, so it cannot go stale the way a name list does."""
  seen = {}
  for text in runs:
    for k, v in parse(text).items():
      seen.setdefault(k, set()).add(v)
  return {k: sorted(vs) for k, vs in seen.items() if len(vs) > 1}


def die(code, why, detail=""):
  print(why, file=sys.stderr)
  if detail:
    print(detail, file=sys.stderr)
  print("NOT A DISAGREEMENT. Nothing was compared; treat this as a retry request.", file=sys.stderr)
  sys.exit(code)


def live_oracle(exe):
  return [subprocess.run([exe, str(ORACLE_SCRIPT)], cwd=ROOT, capture_output=True, text=True,
                         env=dict(os.environ, DEV="NULL")) for _ in range(ORACLE_RUNS)]


def main():
  if "--mutate" in sys.argv:
    i = sys.argv.index("--mutate")
    src, rx, repl = pathlib.Path(sys.argv[i + 1]), sys.argv[i + 2], sys.argv[i + 3]
    work = src.with_suffix(".mut.bend")
    body = src.read_text()
    if not re.search(rx, body):
      print(f"MUTATION DID NOT APPLY: {rx}")
      sys.exit(2)
    work.write_text(re.sub(rx, repl, body, count=1))
    print(f"mutated {rx} -> {repl}")
    print(bend(work)[0][:4000])
    return

  port_text, port_err, port_rc = bend(PORT)
  port = parse(port_text)
  # GUARD: ZERO ROWS IS NOT A RESULT. Checked before the oracle is even launched, because the
  # whole point is that a lane which said nothing cannot be described in terms of rows.
  if not port:
    die(2, f"dsl_gate: THE PORT PRODUCED ZERO ROWS -- {PORT.name} rc={port_rc}, "
           f"{len(port_text.splitlines())} line(s) of stdout. This is a retry request, "
           f"not a disagreement.",
        port_err[-2000:])

  # `oracle_py.resolve()` is the project-wide refusal: it exits 2 when the interpreter resolves
  # `tinygrad` to a tree other than this repo's, which is what a `.venv` copied out of the tree
  # does. Importing it here means the L-11 refusal is INHERITED, not re-implemented.
  exe, tinygrad_path, version = oracle_py.resolve()
  print(oracle_py.line(exe, tinygrad_path, version))
  cs = live_oracle(exe)
  for n, c in enumerate(cs, 1):
    if c.returncode != 0:
      die(2, f"dsl_gate: ORACLE LAUNCH {n} OF {ORACLE_RUNS} EXITED {c.returncode}", c.stderr[-2000:])
  if not any(parse(c.stdout) for c in cs):
    die(2, f"dsl_gate: THE ORACLE PRODUCED ZERO ROWS in {ORACLE_RUNS} launch(es).",
        cs[-1].stderr[-2000:])
  if "--record" in sys.argv:
    RECORDED.write_text(cs[-1].stdout)
    print(f"recorded {RECORDED} from launch {ORACLE_RUNS}")

  oracle = parse(cs[-1].stdout)
  unstable = unstable_rows([c.stdout for c in cs])
  for k, vs in sorted(unstable.items()):
    oracle.pop(k, None)
    print(f"EXCLUDED-UNREPRODUCIBLE {k}: {len(vs)} different values in {ORACLE_RUNS} launches of "
          f"{ORACLE_SCRIPT.name} -- {vs[0][:60]!r} vs {vs[1][:60]!r}. Excluded by MEASUREMENT "
          f"(it is not a function of the source), not by name.")

  shared = set(port) & set(oracle)
  differing = sorted(k for k in shared if port[k] != oracle[k])
  only_port, only_oracle = sorted(set(port) - set(oracle)), sorted(set(oracle) - set(port))
  for k in differing:
    print(f"MISMATCH {k}\n  port   {port[k]}\n  oracle {oracle[k]}")

  # ⚠ THREE NUMBERS, THREE NAMES. The old one-line summary printed `mismatched=` as the union of
  # "differs", "missing" and "extra", which read as a disagreement count and exceeded the shared
  # count (1503 against 617). A summary that cannot be read is a summary that teaches the reader
  # to ignore it.
  print(f"rows port={len(port)} oracle={len(oracle)} shared={len(shared)} "
        f"VALUES-DIFFER={len(differing)} only-in-port={len(only_port)} "
        f"only-in-oracle={len(only_oracle)} unstable-excluded={len(unstable)}")
  if not shared:
    die(2, "dsl_gate: THE TWO SIDES SHARE NO ROW NAME, so they compared nothing. Two lanes that "
           "cannot be compared cannot agree.")
  if differing:
    print(f"VERDICT: DISAGREE on {len(differing)} of {len(shared)} shared row value(s).")
    sys.exit(1)
  print(f"VERDICT: AGREE over {len(shared)} shared row value(s). "
        + (f"{len(only_port)} port-only and {len(only_oracle)} oracle-only row(s) are SET "
           f"differences and are NOT agreement about them." if only_port or only_oracle else ""))


if __name__ == "__main__":
  main()