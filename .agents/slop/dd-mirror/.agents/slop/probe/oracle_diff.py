#!/usr/bin/env python3
"""Diff the rows jit.bend / worker.bend SHARE with the CPython oracle.

Prints SHARED=<n> GREEN=<n> RED=<n>, then every RED row. A row with no oracle is
BEND-ONLY and is listed by name, never filtered -- `creation.bend` rule 8.

    ./bin/bend tinybendygrad/engine/jit.bend > /tmp/jit_i.txt
    DEBUG=1 DEV=PYTHON PYTHONPATH=. python3 .agents/slop/probe/jit_oracle.py jit > /tmp/o.txt
    python3 .agents/slop/probe/oracle_diff.py /tmp/jit_i.txt /tmp/o.txt jit
"""
import subprocess, sys, os

BEND_ROWS = sys.argv[1]
ORACLE = sys.argv[2]
MODE = sys.argv[3] if len(sys.argv) > 3 else "jit"


def load(path):
    d = {}
    for line in open(path):
        line = line.rstrip("\n")
        if "=" in line:
            k, v = line.split("=", 1)
            d[k] = v
    return d


def oracle(which):
    env = dict(os.environ, PYTHONPATH=".", DEV="PYTHON")
    if which == "jit":
        env["DEBUG"] = "1"
    r = subprocess.run(["python3", ".agents/slop/probe/jit_oracle.py", which],
                       capture_output=True, text=True, env=env)
    return load_from_text(r.stdout)


def load_from_text(t):
    d = {}
    for line in t.split("\n"):
        line = line.strip()
        if "=" in line and not line.startswith("opened"):
            k, v = line.split("=", 1)
            d[k] = v
    return d


bend = load(BEND_ROWS)
orc = oracle(MODE)

# the oracle's own renaming, where a CPython row names a different claim than the
# Bend row it corresponds to
ALIAS = {
    "msg_execs10": "msg_execs_n",
    "msg_names_mismatch": "msg_names_mismatch",
}

shared = sorted(k for k in bend if k in orc)
red = [k for k in shared if bend[k] != orc[k]]
bend_only = sorted(k for k in bend if k not in orc)
orc_only = sorted(k for k in orc if k not in bend)

print("MODE=%s  bend_rows=%d  oracle_rows=%d  SHARED=%d  GREEN=%d  RED=%d  BEND-ONLY=%d"
      % (MODE, len(bend), len(orc), len(shared), len(shared) - len(red), len(red), len(bend_only)))
for k in red:
    print("RED  %s\n  bend   =%s\n  oracle =%s" % (k, bend[k], orc[k]))
if "-v" in sys.argv:
    print("BEND-ONLY (%d): %s" % (len(bend_only), " ".join(bend_only)))
    print("ORACLE-ONLY (%d): %s" % (len(orc_only), " ".join(orc_only)))
sys.exit(1 if red else 0)