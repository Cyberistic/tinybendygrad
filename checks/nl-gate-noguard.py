#!/usr/bin/env python3
"""nl-gate-noguard.py -- THE `nir_llvmir` GATE AS IT WAS, and the reason `nl-gate.py` exists.

    .venv/bin/python .agents/slop/eq/nl-gate-noguard.py [--port-stdout F] [--oracle-stdout F]

THIS FILE DELIBERATELY CONTAINS NO COVERAGE GUARD.  It is the value comparison alone: read both
lanes with `rebase-gate.py`'s own `rows()` (imported, never copied), print the two name COUNTS as
decoration, compare every shared name's answer, and print `AGREE` or `BROKEN`.

It is not dead code and it is not a straw man to be laughed at -- it is the CONTROL, and it has to
be a RUNNING detector rather than a stub, because a control run against itself is not a control.
It exists so the same captured bytes can be shown to give DIFFERENT VERDICTS under a gate that has
the guard and a gate that does not.  If both gates agreed, the guard would have proved nothing.

MEASURED, on this lane, pre-rename and with BOTH lanes captured: the `osx=` collapse put 4 of the
205 rows on keys that cannot be addressed, and this file reported

    gated 201   agree 201   disagree []
    AGREE

rc=0.  Four measurements were unreachable by any name, on both sides, under a green verdict.  That
is the entire failure `nl-gate.py`'s `reshape()` exists to make red.

⚠ THE LINE THAT IS BOTH THE POINT AND THE CRIME.  `orr - pr` names NO producer ever printed: it is
the residue of a name after `row()` cut it at the first `=`, so on the pre-rename bytes it is the
four MANUFACTURED keys `sd cpullvm {LLVM,x86_64,arm,riscv64} osx`.  Saying "only it finds" reports
a manufactured name as a found one, which inflates the denominator of everything computed from it.
Kept verbatim as the control's behaviour -- `nl-gate.py` prints the same two sets with the opposite
words ("MANUFACTURES out of a reshape, which NO producer printed") and puts them in `bad`, before
the value comparison runs.
"""
import argparse, hashlib, importlib.util, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
PORT = "tinybendygrad/renderer/nir_llvmir.bend"
ORACLE = [".agents/slop/nl/nl-oracle.py", "rows"]

spec = importlib.util.spec_from_file_location("rebase-gate", str(HERE.parent / "rebase-gate.py"))
_rebase = importlib.util.module_from_spec(spec)
spec.loader.exec_module(_rebase)
rows_shipped = _rebase.rows


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--port-stdout")
  ap.add_argument("--oracle-stdout")
  a = ap.parse_args()
  p = (pathlib.Path(a.port_stdout).read_text() if a.port_stdout
       else subprocess.run(["./bin/bend", PORT], cwd=REPO, capture_output=True,
                           text=True).stdout)
  o = (pathlib.Path(a.oracle_stdout).read_text() if a.oracle_stdout
       else subprocess.run([sys.executable] + ORACLE, cwd=REPO, capture_output=True,
                           text=True).stdout)
  pr, orr = rows_shipped(p), rows_shipped(o)
  print(f"port md5={hashlib.md5(p.encode()).hexdigest()[:8]}   "
        f"oracle md5={hashlib.md5(o.encode()).hexdigest()[:8]}   lanes BYTE-IDENTICAL: {p == o}")
  print(f"the SHARED reader (rebase-gate.py:rows()) over each lane: {len(pr)} names on the port, "
        f"{len(orr)} on the oracle -- {len(set(orr) - set(pr))} only it finds, "
        f"{len(set(pr) - set(orr))} only this reader finds, {len(set(pr) & set(orr))} in common")
  print(f"physical rows on stdout: port {len(p.splitlines())}, oracle {len(o.splitlines())}")
  agree, disagree = [], []
  for n in sorted(set(pr) & set(orr)):
    (agree if pr[n] == orr[n] else disagree).append(n)
  print(f"gated {len(agree) + len(disagree)}   agree {len(agree)}   disagree {disagree[:8]}")
  print("AGREE" if not disagree else "BROKEN")
  return 1 if disagree else 0


if __name__ == "__main__":
  sys.exit(main())