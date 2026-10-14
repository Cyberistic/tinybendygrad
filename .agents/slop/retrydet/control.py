#!/usr/bin/env python3
"""control.py -- THE CONTROL FOR THE CRASH/ANSWER CLASSIFIER, AND PROOF THAT IT CAN FAIL.

    .venv/bin/python .agents/slop/retrydet/control.py

Zero `bend` processes, zero corpus graphs.  `graphcmp.CRASH_CONTROL` is a table of stream
shapes the pinned compiler can produce and `graphcmp.classify` reads them as pure data, so
this runs in well under a second on a host that cannot afford a `bend`.

TWO HALVES, and the second is the one that matters:

  ROWS    every row of `CRASH_CONTROL` gets the verdict it cites.
  MUTANTS four wrong classifiers, each of which the table MUST reject.  A control that has
          never been seen to fail is not a control -- that is the standing rule about
          `elf-run`'s 354 and the naming-gate's 283-vs-278, and it is why the harness comes
          before the code it checks.  Each mutant here is a mistake this edit could plausibly
          have shipped: keying on emptiness instead of on the compiler's name, trusting the
          exit status, reading the token off the wrong stream, and losing the token entirely.
"""
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / ".agents" / "slop"))
import graphcmp as g  # noqa: E402


def mutant_rows_empty(rc: int, out: str, err: str):
  """M1: the OLD rule -- keep going whenever the stream is empty.  This is the defect."""
  lines = [ln for ln in out.splitlines() if ln.strip()]
  return [ln for ln in lines if not ln.startswith("#")], [], "RETRY" if not lines else "ANSWER"


def mutant_trust_rc(rc: int, out: str, err: str):
  """M2: trust the exit status -- `bend` exits 1 for a stack overflow AND for a missing file."""
  lines = [ln for ln in out.splitlines() if ln.strip()]
  rows = [ln for ln in lines if not ln.startswith("#")]
  return rows, [], "RETRY" if rc != 0 else "ANSWER"


def mutant_stdout_token(rc: int, out: str, err: str):
  """M3: read the compiler's name off STDOUT, which is where it never goes."""
  lines = [ln for ln in out.splitlines() if ln.strip()]
  rows = [ln for ln in lines if not ln.startswith("#")]
  tok = any(t in out for t in g.STACK_OVERFLOW)
  return rows, [], "RETRY" if tok else ("ANSWER" if rc == 0 else "BROKE")


MUTANTS = [
  ("M1 retry-on-empty (the defect being fixed)", mutant_rows_empty),
  ("M2 retry-on-exit-status", mutant_trust_rc),
  ("M3 token read off stdout", mutant_stdout_token),
]


def sweep_rows(fn) -> list[int]:
  """Which rows does `fn` get wrong?  The index is into CRASH_CONTROL, so a report names it."""
  return [i for i, (rc, out, err, want, _why) in enumerate(g.CRASH_CONTROL)
          if fn(rc, out, err)[2] != want]


def main() -> int:
  bad: list[str] = []

  # ROWS
  wrong = sweep_rows(g.classify)
  if wrong:
    bad.append(f"classify disagrees with CRASH_CONTROL on rows {wrong}")
  print(f"# ROWS: {len(g.CRASH_CONTROL) - len(wrong)} of {len(g.CRASH_CONTROL)} "
        f"shapes get the verdict they cite")

  # MUTANTS -- each must be CAUGHT, or the control is blind to that mistake.
  for name, fn in MUTANTS:
    caught = sweep_rows(fn)
    print(f"# MUTANT {name}: caught on {len(caught)} row(s) {caught}"
          + ("" if caught else "   *** NOT CAUGHT -- this control cannot see that mistake ***"))
    if not caught:
      bad.append(f"the control does not catch {name}")

  # M4: the token table itself.  Losing it turns every crash into a hard failure -- which is
  # the SAFE direction, so this mutant is reported as DEGRADED, not as a defect, and the
  # row it degrades is named so the cost is visible.
  saved = g.STACK_OVERFLOW
  try:
    g.STACK_OVERFLOW = ()
    degraded = sweep_rows(g.classify)
    print(f"# MUTANT M4 the token table emptied: {len(degraded)} row(s) degrade to BROKE "
          f"{degraded} -- loud, never green, which is the direction a stale pin must fail")
  finally:
    g.STACK_OVERFLOW = saved

  # THE ARITHMETIC, printed from the constants so a reader does not have to trust the prose.
  per_graph = g.TRIES * g.BEND_TIMEOUT
  corpus = 34 * per_graph
  before = 5 * 1800
  print(f"# BOUND tries={g.TRIES} timeout={g.BEND_TIMEOUT}s -> {per_graph}s worst case per "
        f"graph, {corpus}s for the 34-graph corpus; was 5 x 1800 = {before}s per graph "
        f"({before // 3600}h) and {34 * before}s for the corpus ({34 * before // 3600}h)")
  print(f"# CONTROL: " + ("OK" if not bad else "FAIL"))
  for b in bad:
    print("#   " + b)
  return 0 if not bad else 1


if __name__ == "__main__":
  sys.exit(main())
