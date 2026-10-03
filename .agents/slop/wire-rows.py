#!/usr/bin/env python3
"""wire-rows.py -- dump the row NAMES one .bend prints, and its row COUNT, so a new oracle
can be written against names that were MEASURED rather than guessed from the filename.

Two things this refuses to do:

  * It trusts ONE run. bend's machine stack overflows on roughly 1 run in 20 and prints
    NOTHING, so a 0 here is re-run (three times) before being believed. Measured on this
    tree: `uop/weak.bend` printed 52 rows on one invocation and 0 on the next, in the same
    shell, seconds apart. A 0 read off a single run is how "not started" gets confused with
    "the interpreter fell over".
  * It trusts no count. `static_names()` also counts the `row("`/`cnt("` CALLS in `main`
    straight out of the source, and the two numbers are printed side by side. A runtime
    count alone cannot separate "this port has no main" from "this run died"; the static
    count is an independent witness and where they AGREE the runtime number is credible.
    Where they disagree, the disagreement is printed rather than resolved. A census of
    "ten ports" was typed here and is retired: it is a count, and a count in a comment
    is not re-checked. On the cached set the static regex already missed 22 ports, not
    10, and that number will move again the moment a helper is inlined. The two numbers
    are printed; the reader re-measures. Do not put the census back.

  usage: python3 .agents/slop/wire-rows.py PORT [PORT...]
         python3 .agents/slop/wire-rows.py --names PORT     (names only, one per line)
"""
import os, pathlib, re, subprocess, sys

from wire_parse import read_fresh_cache, rows, write_cache

REPO = pathlib.Path(__file__).resolve().parents[2]
CACHE = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "rebase-wired-rows"
NSET = re.compile(r'(?:row|cnt)\(\s*"([^"]+)"')


def bend_rows(port, tries=3):
  src = REPO / port
  cached, why = read_fresh_cache(CACHE, port, src)
  if why == "fresh":
    return cached
  if why == "stale":
    print(f"  ({port} cache is older than the source; not using it)", file=sys.stderr)
  for i in range(tries):
    r = subprocess.run(["./bin/bend", str(src)], cwd=REPO, capture_output=True, text=True,
                       timeout=1800)
    d = rows(r.stdout)
    if d:
      write_cache(CACHE, port, d)
      return d
    print(f"  ({port} printed 0 rows on attempt {i + 1}; re-running)", file=sys.stderr)
  return {}


def static_names(port):
  """The row NAMES main asks for, read out of the source. Independent of the interpreter:
  a static count and a runtime count agreeing is what makes the runtime count credible."""
  src = (REPO / port).read_text()
  i = src.find("def main")
  return NSET.findall(src[i:]) if i >= 0 else []


def main():
  a = sys.argv[1:]
  names_only = "--names" in a
  for port in [x for x in a if not x.startswith("--")]:
    d = bend_rows(port)
    st = static_names(port)
    if not names_only:
      agree = "AGREE" if len(st) == len(d) else f"static={len(st)} (helper not matched)"
      print(f"{port}  rows={len(d)}  {agree}")
    for k in d:
      print(k if names_only else f"  {k}={d[k]}")
  return 0


if __name__ == "__main__":
  sys.exit(main())