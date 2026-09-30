#!/usr/bin/env python3
"""Run `bend --check-only` repeatedly, listing every DISTINCT error it reports.

`bend` stops at the first failure, so a file with N errors takes N runs by hand.
This drives the loop and prints the error head each time, deduplicated, so the
whole backlog is visible in one command. It never edits: the fixes are the
agent's judgement, not a regex's.

usage: bendall.py FILE [MAX]
"""
import re
import subprocess
import sys


def head(err):
  loc = re.search(r"^(\d+)>\s*\|(.*)$", err, re.M)
  loc = f"{loc.group(1)}: {loc.group(2).strip()}" if loc else ""
  msg = " ".join(re.findall(r"^- \w[\w ]*?: (.*)$", err, re.M))[:200]
  return f"{loc}\n    {msg}"


def main():
  path, limit = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 200
  seen = set()
  for n in range(limit):
    out = subprocess.run(["./bin/bend", path, "--check-only"],
                         capture_output=True, text=True)
    err = out.stdout + out.stderr
    if "SOME PROOFS FAIL" not in err:
      print(err.strip() or "clean")
      return
    key = re.sub(r"^\d+", "", head(err))
    if key in seen:
      print(f"(same error at iteration {n}; stopping)")
      print(err[:1200])
      return
    seen.add(key)
    print(f"--- {n}")
    print(head(err))


if __name__ == "__main__":
  main()
