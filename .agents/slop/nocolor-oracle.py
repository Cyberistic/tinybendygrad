#!/usr/bin/env python3
"""
CPython side of the NO_COLOR gate.  Its output is the `py=` half.

tinygrad/helpers.py:239   NO_COLOR = ContextVar("NO_COLOR", 0)
tinygrad/helpers.py:162   getenv    = type(default)(os.getenv(key, default))
tinygrad/helpers.py:41     if NO_COLOR: return st

so the observable is bool(int(os.getenv("NO_COLOR", 0))) -- an INT coercion,
because the default is the int 0, not a bool.  Every line is produced by
importing tinygrad in a FRESH process with the environment set and reading
H.NO_COLOR; a line that says REFUSED is tinygrad failing to import, which is
what int() does to a string it cannot read.  The probe list is byte for byte the
one in .agents/slop/nocolor-probe.bend and the two walk it in the same order,
so the row key is the index and no answer is transcribed.

Run: uv run python .agents/slop/nocolor-oracle.py > .agents/slop/nocolor-oracle.txt
"""
import os, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PROBES = [b"", b"0", b"1", b"2", b"00", b"-0", b"0 ", b" 0", b"+0", b"+1", b"-1", b"-2",
          b"007", b"0x10", b"1_0", b"1.0", b"0.0", b".5", b"abc", b"false", b"True",
          b"no", b"off", b"nan", b"inf", b"1e3", b" 1 ", b"\t2", b"2\n",
          "٣".encode(), b"2 "]

SRC = ("import sys;sys.path.insert(0,%r);import tinygrad.helpers as H;"
       "print('True' if H.NO_COLOR else 'False')" % REPO)


def main():
  base = {k: v for k, v in os.environ.items() if k != "NO_COLOR"}
  p = subprocess.run([sys.executable, "-c", SRC], capture_output=True, text=True,
                     cwd=REPO, env=base)
  print(p.stdout.strip())
  for pr in PROBES:
    env = dict(base)
    env["NO_COLOR"] = pr.decode("utf-8", "surrogateescape")
    p = subprocess.run([sys.executable, "-c", SRC], capture_output=True, text=True,
                       cwd=REPO, env=env)
    out = p.stdout.strip() if not p.returncode else "REFUSED"
    print(out)


if __name__ == "__main__":
  main()