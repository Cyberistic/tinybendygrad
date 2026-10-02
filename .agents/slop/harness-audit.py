#!/usr/bin/env python3
"""harness-audit.py -- read every script under .agents/slop/ and answer, per script:

    ORACLE  does it RUN a CPython authority, or only read a literal out of a port?
    LOUD    does it fail loudly when a lane cannot run, or let a dead lane pass?
    COUNTS  does it distinguish "0 rows compared" from "0 rows disagreed"?
    CLAIM   what does it print that sounds like a verdict?

    .venv/bin/python .agents/slop/harness-audit.py [-v] [substring ...]

This is a LINTER over harnesses, not a runner: it does not execute them. The point
is that 180 scripts is more than any one agent can read, and the three that were
found lying were found by ONE agent's incidental use, so the population needs a
cheap screen and then human eyes on the ones that claim a verdict.

A screen is not a verdict. `-v` prints the matched evidence lines so a reader can
see WHY a row says what it says, and a `NO` in any column means "not found by this
screen", which is not the same as "the harness is unsafe".
"""
import pathlib
import re
import sys

SLOP = pathlib.Path(__file__).resolve().parent

# An ORACLE is a script that asks CPython a question: it runs python on a *oracle*,
# or imports tinygrad itself. Reading a `py=` literal out of a port is the opposite.
RUNS_PY = re.compile(r'sys\.executable|\.venv/bin/python|python3?\s|uv run')
ORACLE_ARG = re.compile(r'oracle', re.I)
IMPORTS_TINYGRAD = re.compile(r'^\s*(import|from)\s+tinygrad', re.M)
RUNS_BEND = re.compile(r'bin/bend|["\']\./bin/bend|bend\b')
# A verdict a human would trust without reading further.
CLAIMS = re.compile(r'ALL LANES AGREE|ALL PROOFS CHECK|byte for byte|match CPython'
                    r'|\bGREEN\b|OK\b|PROBLEMS|\bPASS\b|\bCLEAN\b|IDENTICAL',
                    re.M)
# A literal expectation lifted out of the port: the self-referential failure.
READS_PY_LITERAL = re.compile(r'py=\[|py=\(|split\(["\']\s*py=|group\(["\']py')
SELFREF_DIFF = re.compile(r'\bdiff\b.{0,40}\b(bd|bd\.txt|interp|i\.txt)\b')
COUNT_PRINT = re.compile(r'len\(.*\)|wc -l|count|rows?:')
LOUD = re.compile(r'DID NOT RUN|returncode|rc\b|FAILED|except\b|sys\.exit\(1\)', re.M)
NAMES_AUTHORITY = re.compile(r'AUTHORITY|authorit', re.I)
ZERO_IS_FAIL = re.compile(r'not [a-z_]+\s*(?:or|and)|== 0|if not \w+\b.*rows'
                          r'|NO ROWS|0 rows|GATE DID NOT RUN', re.I)


def cells(text):
  oracle = bool(RUNS_PY.search(text) and (ORACLE_ARG.search(text) or IMPORTS_TINYGRAD.search(text)))
  return {
    'ORACLE': 'yes' if oracle else ('self' if READS_PY_LITERAL.search(text) else 'no'),
    'BEND': 'yes' if RUNS_BEND.search(text) else 'no',
    'LOUD': 'yes' if LOUD.search(text) else 'no',
    'COUNTS': 'yes' if COUNT_PRINT.search(text) else 'no',
    'ZERO': 'yes' if ZERO_IS_FAIL.search(text) else 'no',
    'CLAIM': 'yes' if CLAIMS.search(text) else 'no',
    'AUTHORITY': 'yes' if NAMES_AUTHORITY.search(text) else 'no',
  }


def main(argv):
  verbose = '-v' in argv
  pats = [a for a in argv if a != '-v']
  rows = []
  for p in sorted(SLOP.rglob('*')):
    if p.suffix not in ('.py', '.sh') or p.name.startswith('.'):
      continue
    if p.parts[len(SLOP.parts)] == 'opstree':
      continue          # a vendored tinygrad reference tree, not a harness
    if '__pycache__' in p.parts:
      continue
    if pats and not any(x in str(p) for x in pats):
      continue
    text = p.read_text(errors='replace')
    rows.append((p.relative_to(SLOP), cells(text), text))
  w = max(len(str(r[0])) for r in rows)
  print(f"{len(rows)} scripts under .agents/slop/  (ORACLE: self = reads a py= literal out of a port)")
  print(f"{'script'.ljust(w)}  ORACLE BEND LOUD COUNTS ZERO CLAIM AUTHORITY")
  for rel, c, text in rows:
    print(f"{str(rel).ljust(w)}  {c['ORACLE']:<6} {c['BEND']:<4} {c['LOUD']:<4} "
          f"{c['COUNTS']:<6} {c['ZERO']:<4} {c['CLAIM']:<5} {c['AUTHORITY']}")
  if verbose:
    for rel, c, text in rows:
      if not any(p in str(rel) for p in pats) and pats:
        continue
      print(f"\n--- {rel}")
      for line in text.splitlines():
        if (CLAIMS.search(line) or READS_PY_LITERAL.search(line) or NAMES_AUTHORITY.search(line)
            or 'DID NOT RUN' in line):
          print("   ", line.strip()[:160])
  # The population summary that matters: a harness that claims a verdict, does not
  # run an oracle, and does not count rows is the shape of the three that lied.
  print("\nSHAPE OF A LIAR -- claims a verdict, no CPython authority, no row count:")
  liars = [str(r) for r, c, _ in rows if c['CLAIM'] == 'yes' and c['ORACLE'] != 'yes'
           and c['COUNTS'] == 'no']
  for l in liars:
    print("  ", l)
  print(f"   ({len(liars)} of {len(rows)})")


if __name__ == '__main__':
  main(sys.argv[1:])