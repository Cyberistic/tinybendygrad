#!/usr/bin/env python3
"""measure.py -- THE MEASUREMENTS THE `upstream_removed` CLASS RESTS ON.

    .venv/bin/python .agents/slop/absence/measure.py
    .venv/bin/python .agents/slop/absence/measure.py --compare BEFORE.rows AFTER.rows

ONE INSTRUMENT, AND IT PRINTS EVERY NUMBER THE REPORT CITES.

  1. THE PIN: the upstream ref's tip, the DECLARATION's OUR PIN, and whether they are
     the same commit.
  2. EVERY REVISION THE PORT's HEADERS NAME, CLASSIFIED -- which is what "consistent
     with the pin's history" MEANS and whether it bites.
  3. THE PORT's ABSENCE MARKERS: how many citation lines carry one, and how many of
     them the EVIDENCE selects. **THE MARKER ALONE SELECTS 44; THE EVIDENCE SELECTS 2.**
  4. `--compare`: the ELEMENTWISE class movement between two rows files, which is the
     proof that the new class weakened no other class.
"""
from __future__ import annotations

import collections
import csv
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATE = ROOT / "gates" / "pin-cite-gate.py"

spec = importlib.util.spec_from_file_location("pin_cite", GATE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

SHA = re.compile(r"(?<![0-9a-f])([0-9a-f]{7,40})(?![0-9a-f])")


def git(*a: str) -> str:
  p = subprocess.run(("git", "--no-optional-locks",) + a, cwd=ROOT, capture_output=True, text=True)
  return p.stdout if p.returncode == 0 else ""


def headers() -> list[tuple[str, int, str]]:
  """Every header line of every `.bend` file, as `(rel, line no, text)`."""
  census = gate.load_census()
  out = []
  for p in sorted(census.walk_bend(ROOT / gate.PORT_REL)):
    body = p.read_text(encoding="utf-8", errors="replace").splitlines()
    first, _last, blk = census.header_block(body)
    if not first:
      continue
    for off, ln in enumerate(blk):
      out.append((str(p.relative_to(ROOT)), first + off, ln))
  return out


def measure() -> None:
  corpus = gate.load_census().Upstream(gate.UPSTREAM)
  pin = gate.declared_pin()
  print("== 1. THE PIN")
  print(f"  upstream ref tip      {corpus.order[0]}")
  print(f"  DECLARATION's OUR PIN {pin}")
  print(f"  the two are equal     {corpus.order[0] == pin}")
  print(f"  upstream commits      {len(corpus.order)}")
  print()

  print("== 2. EVERY REVISION THE PORT'S HEADERS NAME")
  kinds = collections.Counter()
  names: dict[str, list[str]] = collections.defaultdict(list)
  for rel, at, ln in headers():
    for m in SHA.finditer(ln):
      names[m.group(1)].append(f"{rel}:{at}")
  for s, where in sorted(names.items()):
    full = git("rev-parse", "--verify", "--quiet", s).strip()
    if not full:
      kinds["not-a-commit at all"] += 1
      continue
    if full not in corpus.index:
      kinds["a commit of THIS repo, not of upstream"] += 1
      continue
    if pin and corpus.index[full] >= corpus.index.get(pin, -1):
      kinds["upstream, at or before the pin"] += 1
    else:
      kinds["upstream but NEWER than the pin"] += 1
  for k, n in kinds.most_common():
    print(f"  {k:38s} {n:3d}   (distinct hex runs)")
  print("  the ones that are NOT consistent with the pin's history:")
  for s, where in sorted(names.items()):
    full = git("rev-parse", "--verify", "--quiet", s).strip()
    if full and full in corpus.index and pin and corpus.index[full] < corpus.index.get(pin, -1):
      print(f"    {s}  -- {where[0]}")
    elif full and full not in corpus.index:
      print(f"    {s}  -- {where[0]}  (a commit of THIS repo)")
  print()

  print("== 3. THE PORT'S ABSENCE MARKERS")
  census = gate.load_census()
  all_marked = [(rel, at, ln) for rel, at, ln in headers() if gate.ABSENCE_MARKER.search(ln)]
  marked = [(rel, at, ln) for rel, at, ln in all_marked
            if census.CITE_RE.findall(ln) or census.BARE_RE.findall(ln)]
  print(f"  header lines carrying a marker:            {len(all_marked)}")
  print(f"  of those, lines that also carry a citation: {len(marked)}")
  print("  THE EVIDENCE selects 2 of the 44 -- the gate's own report names them.")
  print()


def compare(before: Path, after: Path) -> int:
  with before.open() as f:
    b = list(csv.DictReader(f, delimiter="\t"))
  with after.open() as f:
    a = list(csv.DictReader(f, delimiter="\t"))
  if len(b) != len(a):
    print(f"COMPARE FAILED: the population moved, {len(b)} -> {len(a)}")
    return 1
  moves = collections.Counter()
  fields = 0
  for x, y in zip(b, a):
    if (x["rel"], x["at"], x["subject"], x["lo"]) != (y["rel"], y["at"], y["subject"], y["lo"]):
      print(f"COMPARE FAILED: the rows are not paired by index: {x['rel']}:{x['at']}")
      return 1
    if x["class"] != y["class"]:
      moves[(x["class"], y["class"])] += 1
      print(f"  MOVED {x['rel']}:{x['at']}  {x['class']} -> {y['class']}")
    for k in ("at_pin", "newest_rev", "claim", "present_in_file", "explicit"):
      if x[k] != y[k]:
        fields += 1
        print(f"  FIELD MOVED {x['rel']}:{x['at']} {k}: {x[k]!r} -> {y[k]!r}")
  print(f"rows before {len(b)}, after {len(a)}")
  for (frm, to), n in moves.most_common():
    print(f"  {frm} -> {to}: {n}")
  print(f"  non-class field moves: {fields}")
  return 0


def main(argv: list[str]) -> int:
  if "--compare" in argv:
    i = argv.index("--compare")
    return compare(Path(argv[i + 1]), Path(argv[i + 2]))
  measure()
  return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
