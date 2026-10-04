#!/usr/bin/env python3
"""measure39.py -- for each of rebase-gate.py's BASE_ORACLES lanes, RUN both sides and report

  port rows / oracle rows / shared names / disagreeing names / BYTE-IDENTICAL?

using rebase-gate.py's OWN row()/rows() -- imported, never forked (156 forked readers exist).
Nothing is written to the repo. Read-only: bend compiles to memory, oracles import tinygrad.
"""
import importlib.util, os, pathlib, subprocess, sys, time

REPO = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
SLOP = REPO / ".agents/slop"
sys.path.insert(0, str(SLOP))

spec = importlib.util.spec_from_file_location("rebase_gate", SLOP / "rebase-gate.py")
rg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rg)

src = (SLOP / "rebase-gate.py").read_text()
i = src.index("BASE_ORACLES = {")
j = src.index("\n}", i)
ns = {}
exec(src[i:j + 2], ns)
BO = ns["BASE_ORACLES"]

ORACLE_PY = str(REPO / ".venv/bin/python")


def bend_stdout(port):
    return subprocess.run(["./bin/bend", port], cwd=REPO, capture_output=True, text=True,
                          timeout=3600)


def oracle_stdout(spec_str):
    argv = spec_str.split()
    return subprocess.run([ORACLE_PY] + argv, cwd=REPO, capture_output=True, text=True,
                          env=dict(os.environ, DEV="NULL"), timeout=3600)


print(f"{'#':>2} {'port':46} {'p':>5} {'o':>5} {'shared':>7} {'disagree':>9} {'ident':>6}  oracle")
for n, (port, oracles) in enumerate(BO.items(), 1):
    try:
        a = bend_stdout(port)
        b = oracle_stdout(oracles[0])
    except Exception as e:                                   # a lane that DIED is a finding
        print(f"{n:>2} {port:46} {'DEAD':>5}  {type(e).__name__}: {e}")
        continue
    pr, orr = rg.rows(a.stdout), rg.rows(b.stdout)
    shared = set(pr) & set(orr)
    bad = sorted(k for k in shared if pr[k] != orr[k])
    ident = a.stdout == b.stdout
    print(f"{n:>2} {port[14:]:46} {len(pr):5} {len(orr):5} {len(shared):7} {len(bad):9} "
          f"{str(ident):>6}  {oracles[0]}"
          + (f"  port_rc={a.returncode} orc_rc={b.returncode}" if (a.returncode or b.returncode) else "")
          + (f"  DISAGREE={bad[:4]}" if bad else ""), flush=True)