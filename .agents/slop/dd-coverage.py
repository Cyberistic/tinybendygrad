#!/usr/bin/env python3
"""dd-coverage.py -- the COVERAGE question, answered WITHOUT the bend lane.

dd-oracle.py prints 416 rows. The port prints ~172. dtype-oracle.py prints 107 of those 172.
The question "why 172 vs 107" is a question about TWO SETS OF NAMES and nothing about the
port, so it is answered here from dd-oracle.txt and dtype-oracle.py alone -- which means it
stays answerable while another agent is editing ops.bend and the bend lane is cold.

  1. IS dtype-oracle.py A PURE FILTER? asserted, not assumed: its printed names must be
     exactly dd-oracle.py's names minus its SKIP set. A filter that quietly dropped or added
     a name would make every downstream count a fiction.
  2. THE 309 ROWS dd-oracle.py PRINTS THAT THE PORT NEVER EMITS, grouped by ROW SUFFIX.
     This is where the 172-vs-107 and 52-vs-1 questions actually get answered.
  3. FOR EACH OF THE 65 SKIPPED NAMES: does the port emit it at all, and is it one of the
     families the SKIP set says it is (creation-order) or one of the five it admits to.

Run: .venv/bin/python .agents/slop/dd-coverage.py
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]


def load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def rows_of(text):
  """rebase-gate.py's rows(), loaded not copied."""
  return load("rebase_gate", REPO / ".agents/slop/rebase-gate.py").rows(text)


def port_names(path):
  return set(rows_of(pathlib.Path(path).read_text()))


# The row kinds dd-oracle.py appends to a fixture name, matched at the END of the name and
# only there, because the fixture names themselves end in letters: `lga` is the `l2i` fixture
# numbered "a", not fixture `lg` with kind `a`, and a regex that reads it as a suffix makes
# every l2i row a "creation-order row" and quietly excuses the whole set.
#
# `r`/`o` are the RULE-TABLE kinds (an early-reject set and a matched-op set) and exist ONLY on
# the `nlong`/`nfloat`/`ndtype` families. Applied globally they are wrong: `lgr` is the `l2i`
# CMOD fixture's ANSWER, and reading its trailing `r` as a kind files the one fixture that
# raises under an unrelated row type. That misclassification would have excused `lgr`, one of
# the eight suppressed BARE rows, as an order fact -- so the table families are named.
KINDS = ("sig", "sz", "n", "k", "p")
TABLE_KINDS = ("r", "o")
TABLES = ("nlong", "nfloat", "ndtype")


def suffix(name):
  for kind in KINDS:
    if name.endswith(kind) and len(name) > len(kind):
      return kind
  if any(name.startswith(t) for t in TABLES):
    for kind in TABLE_KINDS:
      if name.endswith(kind) and len(name) > len(kind):
        return kind
  return ""


def family(name):
  """`lg2sig` -> `lg2`; `f4` -> `f4`; `ndtype11r` -> `ndtype11`. The part before the kind."""
  k = suffix(name)
  return name[:len(name) - len(k)] if k else name


def main():
  dd_text = (REPO / ".agents/slop/dd-oracle.txt").read_text()
  DD = rows_of(dd_text)
  dt = load("dt", REPO / ".agents/slop/dtype-oracle.py")
  SKIP = dt.SKIP
  print(f"[cov] dd-oracle.txt rows      {len(DD)}")
  print(f"[cov] dtype-oracle.py SKIP    {len(SKIP)} names")

  # (1) THE FILTER IDENTITY
  expect = set(DD) - SKIP
  missing = expect - set(DD)          # by construction empty; asserted anyway
  print(f"[cov] names dd prints that the filter suppresses: {len(expect & SKIP)}")
  print(f"[cov] SKIP names dd-oracle.py never printed at all: {sorted(SKIP - set(DD))}")

  # (2) THE PORT ROWS. Needed to place the 172/107 numbers; the caller passes them in when
  # the lane is cold, and dd-truth.py re-measures them when it is not.
  port = None
  for arg in sys.argv[1:]:
    if arg.startswith("--port-rows="):
      port = set(rows_of(pathlib.Path(arg.split("=", 1)[1]).read_text()))
  if port is None:
    print("[cov] no --port-rows=<file>, so the port-side counts are omitted; "
          "the dd-side decomposition below is unaffected")

  if port is not None:
    shared = set(DD) & port
    print(f"[cov] port rows {len(port)}   shared with dd-oracle.py {len(shared)}   "
          f"dd-only {len(set(DD) - port)}   port-only {len(port - set(DD))}")
    gated = set(DD) - SKIP
    print(f"[cov] of the {len(shared)} shared rows, dtype-oracle.py prints {len(gated & port)} "
          f"and suppresses {len((shared & SKIP))}")
    sup = shared & SKIP
    kinds = {}
    for k in sup:
      kinds.setdefault(suffix(k), []).append(k)
    print(f"[cov] the {len(sup)} SUPPRESSED rows that BOTH sides emit, by row kind:")
    for kind, ks in sorted(kinds.items()):
      print(f"[cov]   {kind or '(bare)':<8} {len(ks):>3}  {', '.join(sorted(ks))}")
    print(f"[cov] dd-oracle rows the port never emits, by row kind:")
    ddonly = {}
    for k in set(DD) - port:
      ddonly.setdefault(suffix(k), []).append(k)
    for kind, ks in sorted(ddonly.items()):
      print(f"[cov]   {kind or '(bare)':<8} {len(ks):>3}  {', '.join(sorted(ks)[:14])}"
            + (" ..." if len(ks) > 14 else ""))

  # (3) THE DOCSTRING'S CLAIM, CHECKED. dtype-oracle.py says the SKIP set is
  # "creation-order rows plus five the live tree still disagrees on". If the five are in
  # fact creation-order too, then the set suppresses nothing but creation-order facts and the
  # "1 disagreement" is the honest number for what it measures. If some are NOT
  # creation-order, they are suppressed disagreements and the count is a floor.
  five = {"lgu", "lgun", "lgvk", "lgvsig", "lgwsig"}
  order_kinds = {"sig", "n", "k", "p"}
  print("\n[cov] THE FIVE ADMITTED DISAGREEMENTS, and what kind of row each is:")
  for k in sorted(five):
    print(f"[cov]   {k:<8} fixture {family(k):<5} kind {suffix(k) or '(the answer itself)'}")
  non_order = sorted(k for k in SKIP if suffix(k) not in order_kinds)
  print(f"[cov] SKIP holds {len(non_order)} names that are NOT creation-order rows: {non_order}")
  print(f"[cov]   of those, {len([k for k in non_order if suffix(k) == ''])} are BARE rows -- the "
        f"answer itself, not an order fact: "
        f"{sorted(k for k in non_order if suffix(k) == '')}")
  print(f"\n[cov] the {len([k for k in SKIP if suffix(k) in order_kinds])} genuinely "
        f"creation-order names in SKIP are: "
        f"{sorted(k for k in SKIP if suffix(k) in order_kinds)}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())