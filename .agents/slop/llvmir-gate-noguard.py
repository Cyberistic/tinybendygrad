#!/usr/bin/env python3
"""llvmir-gate-noguard.py -- THE GATE AS IT WAS, and the reason llvmir-gate.py exists.

    .venv/bin/python .agents/slop/llvmir-gate-noguard.py [--port-stdout F] [--oracle-stdout F]

THIS FILE DELIBERATELY CONTAINS NO `reshape()`. It is the value comparison alone: read both
lanes with `rebase-gate.py`'s own `rows()` (imported, not copied), print the two name COUNTS as
decoration, compare every shared name's answer, and print `AGREE` or `BROKEN`.

It is not dead code and it is not a straw man to be laughed at -- it is the **control**, and it
has to be a RUNNING detector rather than a stub, because a control run against itself is not a
control. It exists so the same planted bytes can be shown to give DIFFERENT VERDICTS under a gate
that has the coverage guard and a gate that does not. If both gates agreed, the new guard would
have proved nothing.

⚠ IT REPRODUCES, ON THIS LANE, THE PREDECESSOR'S FAILURE THAT MATTERED, and it is worth stating
precisely because it is not the failure people expect. `cstyle-gate.py` printed

    the SHARED reader (rebase-gate.py:rows()) over the SAME oracle stdout: 222 names --
      6 only it finds, 8 only rows_strict finds, 216 in common
    gated 221   agree 221   disagree []
    AGREE

Six names that NO producer ever printed were reported as *"only it finds"*, i.e. as names that
exist, and the verdict below that paragraph was `AGREE` with `rc=0`. So this file's
`print(f"{len(p)} -- {len(o - p)} only the shipped reader finds, {len(p - o)} only this reader "
      f"finds, {len(p & o)} in common")` is deliberately the WRONG PHRASING: `o - p` is
manufactured by `row()`'s cut, not found. `llvmir-gate.py` prints the same two sets with the
opposite words (`MANUFACTURES out of a reshape, which NO producer printed`) and puts them in
`bad`, before the value comparison runs.
"""
import argparse, hashlib, importlib.util, pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
PORT = "tinybendygrad/renderer/llvmir.bend"
ORACLE = [".agents/slop/llvmir-oracle.py", "rows"]


def load(name):
  spec = importlib.util.spec_from_file_location(
    name, str(pathlib.Path(__file__).parent / f"{name}.py"))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


_rebase = load("rebase-gate")
rows_shipped = _rebase.rows


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--port-stdout")
  ap.add_argument("--oracle-stdout")
  a = ap.parse_args()
  p = (pathlib.Path(a.port_stdout).read_text() if a.port_stdout
       else subprocess.run(["./bin/bend", PORT], cwd=REPO, capture_output=True, text=True).stdout)
  o = (pathlib.Path(a.oracle_stdout).read_text() if a.oracle_stdout
       else subprocess.run([sys.executable] + ORACLE, cwd=REPO, capture_output=True,
                           text=True).stdout)
  pr, orr = rows_shipped(p), rows_shipped(o)
  print(f"port md5={hashlib.md5(p.encode()).hexdigest()[:8]}   "
        f"oracle md5={hashlib.md5(o.encode()).hexdigest()[:8]}   "
        f"lanes BYTE-IDENTICAL: {p == o}")
  # ⚠ THE LINE THAT IS BOTH THE POINT AND THE CRIME. `orr - pr` names NO producer ever printed:
  # it is the residue of a name after `row()` cut it at the first `=`. Saying "only it finds"
  # reports a manufactured name as a found one, which inflates the denominator of everything
  # computed from it. Kept verbatim as the control's behaviour.
  print(f"the SHARED reader (rebase-gate.py:rows()) over each lane: "
        f"{len(pr)} names on the port, {len(orr)} on the oracle -- "
        f"{len(set(orr) - set(pr))} only it finds, {len(set(pr) - set(orr))} only this reader "
        f"finds, {len(set(pr) & set(orr))} in common")
  print(f"physical rows on stdout: port {len(p.splitlines())}, oracle {len(o.splitlines())}")
  agree, disagree = [], []
  for n in sorted(set(pr) & set(orr)):
    (agree if pr[n] == orr[n] else disagree).append(n)
  print(f"gated {len(agree) + len(disagree)}   agree {len(agree)}   disagree {disagree[:8]}")
  print("AGREE" if not disagree else "BROKEN")
  return 1 if disagree else 0


if __name__ == "__main__":
  sys.exit(main())