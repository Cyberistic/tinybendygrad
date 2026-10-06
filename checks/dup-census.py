#!/usr/bin/env python3
"""dup-census.py -- THE DUPLICATE-ROW-NAME CENSUS.  Both sides of every lane, from DATA.

    .venv/bin/python checks/dup-census.py --all
    .venv/bin/python checks/dup-census.py --names
    .venv/bin/python checks/dup-census.py --one FILE [FILE...]

WHY A DUPLICATE IS THE SAME SPECIES OF BUG AS AN `=` IN A NAME.  `rebase-gate.py:rows()` is
`{name: value}` keyed on the producer's name, so the LAST row on a key wins and every earlier
row on it is invisible to every mutation that harness drives.  Two rows sharing a name
therefore cost `n-1` measurements and leave 1 merely MISNAMED -- exactly the arithmetic the
`=`-class unit measured.  The difference is the FIX: an `=` in a name is one reader's opinion,
so it is a rename; a duplicate is the PRODUCER printing the same name twice, so it is a
generator defect, a loop, or a legitimately-set-valued row.

NOTHING HERE IS FORKED.  `rebase-gate.py:row()`/`rows()` are the shipped reader and
`eq-census2.py`'s `scan()`/`boundary()`/`lane_shape()` are the shipped STRUCTURAL reader, both
IMPORTED.  `dup-census.py` adds one thing and one thing only: the multiplicity analysis, and a
duplication is invisible to a `set()` -- which is how `eq-census2.py` read 0 on the one lane in
this tree that HAS one, twice.

THE NAME FIELD IS MEASURED TWICE, ON EVERY ROW, AND BOTH ANSWERS ARE REPORTED, because the
`=`-class unit's decisive finding was about DIRECTION:

    `row()` cuts at the FIRST `=`.  On an F1 lane that IS the writer's boundary.  On an F2 lane
    it is not, and a NAME may legally contain one -- in which case `row()` invents a collision
    that no producer printed.

So a duplicate counted under ONE name definition is not yet a duplicate, and `dup-census.py`
reports both definitions and their disagreement:

    strict    the writer's own boundary (`eq-census2.boundary`), so the name is what the
              PRODUCER printed;
    shipped   `rebase-gate.py:row()`'s first-`=` cut, which is what a mutation harness keys on.

`lost = accepted_lines - distinct_keys` is the reader's own arithmetic and is the number that
matters, because the loss is a property of the reader.  It is attributed afterwards, and the
attribution is asserted to sum to it.
"""
import argparse, importlib.util, json, pathlib, sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
# `parents[0]` IS the repo root, and the depth is PROVED by `refuse()` below, not assumed.
# `3f0e70ff1` MOVED this file from `.agents/slop/dup/` to `checks/`, ONE level shallower, and
# carried BOTH constants across without recomputing them: `SLOP = HERE.parent` became the repo
# root (so `SLOP/"rebase-gate.py"` was `<repo>/rebase-gate.py`, which does not exist) and `REPO`
# became `/Users/cyberistic/src`.  Note the trap: `parents[1]` is ALSO wrong -- it is
# `/Users/cyberistic/src/tries`.  `SLOP` was `.agents/slop/` at the old depth, because that is
# where `rebase-gate.py` and `eq/` lived, and `371cc64c9` swept `eq/eq-census2.py`.
REPO = HERE.parents[0]
SLOP = REPO / ".agents" / "slop"
CACHE = HERE / "lanes"


def refuse(*why) -> None:
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE `load()` below, because under bare `python3` a stale `SLOP` made
  `load()` raise `FileNotFoundError` FIRST, and an assertion DOWNSTREAM of what it asserts
  cannot turn an exception into a refusal: rc 1 and a traceback, which carries no denominator
  and so counts nowhere."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# TWO TRACKED MARKERS, so a FOURTH relocation is a refusal rather than a third exception:
# the substrate this root claim rests on, then every input this gate LOADS at import.
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
_EQ = SLOP / "eq" / "eq-census2.py"
for _p in (SLOP / "rebase-gate.py", _EQ):
  if not _p.is_file():
    refuse(f"input absent: {_p}"
           + ("  (swept by 371cc64c9; recoverable from git at 371cc64c9^:)"
              if _p == _EQ else "")
           + "  This gate cannot produce a denominator without it.")


def load(path, name):
  """`rebase-gate.py` and `eq-census2.py` both carry a `-`, so neither imports by name.  ONE
  loader for both, and it is the only one in this file: a second reader is how this project got
  a two-round contradiction between two gates (`agent-core.md`)."""
  spec = importlib.util.spec_from_file_location(name, str(path))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG = load(SLOP / "rebase-gate.py", "rebase_gate")
EQ = load(SLOP / "eq" / "eq-census2.py", "eq_census2")
ROW = RG.row                    # THE shipped reader's row rule
SCAN, BOUNDARY = EQ.scan, EQ.boundary

# Separators a name pair may differ by and STILL be one name.  Used ONLY to CHECK the closed `=`
# class from the duplicate side -- a pair that differs only by one of these is reported as
# SEPARATOR and is NOT counted as a new duplicate.
SEPS = "-_ .:/|"


def names_strict(text):
  """[(lineno, name, line)] for every physical row the WRITER emitted, under the writer's own
  boundary.  `eq-census2.scan()` is the decision, so this file never makes a second one."""
  sc, shape, n2, n = SCAN(text)
  src = text.splitlines()
  return [(i, nm, src[i - 1]) for i, k, nm, _ in sc if k in ("F1", "F2")], shape, sc


def measure(text, label=""):
  """The figures, with a denominator for every count.

  ⚠ THE DUPLICATES ARE COUNTED OVER THE LINES THE READER ACCEPTS, NOT OVER EVERY LINE THE
  WRITER EMITTED, and the difference is 13 measurements on one lane in this tree.
  `schedule/prepare.bend`'s oracle prints 14 `== SECTION ==` banners; `boundary()` reads their
  first `=` and gives them all the name `""`, so a census over WRITER rows reads one name
  printed 14 times and calls it a 13-measurement duplicate.  It is not: `rebase-gate.py:row()`
  refuses a row with an EMPTY name -- deliberately, and with the argument in its own docstring
  -- so all fourteen are outside the table before any of them is counted.  Counting them made
  the reconciliation line read 82 + 0 + 136 = 218 against a measured 205, and the 13 is exactly
  the banner population.  **A loss is a property of the READER, so a duplicate is measured where
  the reader lives.**
  """
  src = text.splitlines()
  rows, shape, sc = names_strict(text)
  cont = [(i, w) for i, k, _, w in sc if k == "continuation"]
  nob = [(i, w) for i, k, _, w in sc if k == "no-boundary"]
  unbal = [(i, w) for i, k, _, w in sc if k == "end-unbalanced"]
  # SPLIT the writer's rows into the ones `row()` ACCEPTS and the ones it REFUSES.  A refused row
  # is a measurement printed and compared against nothing, which is a different defect with a
  # different owner (`uop/fold.bend`'s 93 and `prepare`'s 14 banners), and both are reported.
  kept = [(i, nm, ROW(ln)) for i, nm, ln in rows if ROW(ln) is not None]
  refuse = [(i, nm, ln) for i, nm, ln in rows if ROW(ln) is None]

  # STRICT: the names the producer printed, WITH MULTIPLICITY.  `Counter` over a LIST; a `set()`
  # here has already overwritten the duplicate and reads 0 on a lane that has one.
  strict = Counter(nm for _, nm, _ in kept)
  dup_s = {k: v for k, v in strict.items() if v > 1}
  # SHIPPED: what `rows()` keys on, also with multiplicity.  It is the SAME population under a
  # second name definition, so `len(acc) - len(ship)` and `len(kept) - len(strict)` are two
  # readings of one loss and they are printed against each other.
  acc = [(i, ROW(l)) for i, l in enumerate(src, 1) if ROW(l) is not None]
  ship = Counter(r[0] for _, r in acc)
  dup_p = {k: v for k, v in ship.items() if v > 1}

  lost = len(acc) - len(ship)                 # the reader's OWN arithmetic
  lost_s = len(kept) - len(strict)            # the same loss under the writer's names
  # THE TWO NAME DEFINITIONS DISAGREEING is the finding the `=`-class unit paid for, so it is a
  # reported number and not a silent preference.
  sdiff = sorted(set(dup_s) ^ set(dup_p))

  # PER-DUPLICATE VALUE ARITHMETIC.  Two rows on one key with the SAME value are a producer that
  # printed one measurement twice (a loop); two rows with DIFFERENT values are two measurements
  # and the NAME is what is wrong.  A mutation harness cannot tell those apart from the name
  # alone, and the fix is different for each.
  dupes = {}
  for nm, n in sorted(dup_s.items(), key=lambda kv: (-kv[1], kv[0])):
    vs = [r[1] for _, m, r in kept if m == nm]
    dupes[nm] = {"n": n, "vals": vs, "distinct_vals": len(set(vs)),
                 "identical": len(set(vs)) == 1,
                 "lines": [i for i, m, _ in kept if m == nm]}
  return {"label": label, "shape": shape, "phys": len(rows), "accepted": len(acc),
          "names_strict": len(strict), "names_shipped": len(ship),
          "dup_n_strict": len(dup_s), "dup_rows_strict": sum(dup_s.values()),
          "lost_strict": lost_s, "dup_n_shipped": len(dup_p), "lost_shipped": lost,
          "name_defs_differ": sdiff, "dupes": dupes,
          "refuse": refuse, "cont": cont, "nob": nob, "unbal": unbal,
          "src": src}


def classify(m):
  """Stage 2's four classes, decided FROM THE ROW TEXT and reported with the evidence that
  decided each one.  The classes are NOT assumed to partition the population: an unclassified
  duplicate is printed as one rather than folded into whichever class is nearest."""
  out = {}
  for nm, d in m["dupes"].items():
    lines = [m["src"][i - 1] for i in d["lines"]]
    # SET: the name itself names a SET of things, so a repeat is the row doing its job.
    if any(s in nm for s in "|+/"):
      c = "SET-ROW (the name itself carries a set operator)"
    elif d["identical"]:
      c = "PRODUCER-LOOP (same name, same value, printed more than once)"
    elif len(set(d["vals"])) == len(d["vals"]):
      c = "DISTINCT-VALUES (one name, two measurements -- the NAME is wrong)"
    else:
      c = "PARTIAL-DUPLICATE (some repeats share a value, some do not)"
    out.setdefault(c, []).append((nm, d, lines))
  return out


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--all", action="store_true",
                  help="print EVERY lane, INCLUDING the clean ones.  Without it a FIXED lane "
                       "disappears from the table and a reader cannot tell 'fixed' from 'not "
                       "looked at' -- measured, when `nir_llvmir` vanished the moment its "
                       "rename landed.")
  ap.add_argument("--names", action="store_true")
  ap.add_argument("--one", nargs="+")
  a = ap.parse_args()
  texts = ([(pathlib.Path(p).name, pathlib.Path(p).read_text()) for p in a.one] if a.one
           else [(p.name, p.read_text()) for p in sorted(CACHE.glob("*.txt"))])
  # ⚠ `texts` pairs are (LABEL, TEXT) -- `eq-census2.py` builds them the same way -- so the
  # unpacking order is load-bearing.  Writing `for t, lb in texts` passes the LABEL as the text
  # and the TEXT as the label, and the first symptom is a census that reports ZERO rows and
  # prints one lane's whole text in the label column.  It is in this file's history; the reason
  # it is worth writing down is that it is SILENT: every count is a real int and all of them
  # are 0, and a census of 0 rows over 1 lane reads exactly like a clean lane.
  ms = [measure(t, lb) for lb, t in texts]
  # `eq-census2.measure()` is IMPORTED for the `=`-class's share of the reader's loss, so the
  # CLOSED class is reported by its own author and this unit never re-derives it.  Two numbers,
  # two implementations, one reconciliation -- and a disagreement is a finding, not a rounding.
  cross = [EQ.measure(t, lb) for lb, t in texts]
  print(f"{'lane':<62} {'phys':>5} {'acc':>5} {'nmS':>5} {'nmP':>5} {'dupN':>5} {'dupR':>5} "
        f"{'LOST':>5} {'refuse':>6} {'cont':>5} {'defs?':>5}")
  for m in ms:
    if a.all or m["dup_n_strict"] or m["lost_strict"] or m["refuse"] or m["cont"]:
      print(f"{m['label']:<62} {m['phys']:5} {m['accepted']:5} {m['names_strict']:5} "
            f"{m['names_shipped']:5} {m['dup_n_strict']:5} {m['dup_rows_strict']:5} "
            f"{m['lost_strict']:5} {len(m['refuse']):6} {len(m['cont']):5} "
            f"{len(m['name_defs_differ']):5}")
  g = lambda k: sum(m[k] for m in ms)
  lanes, dup_lanes = len(ms), [m for m in ms if m["dup_n_strict"]]
  A, P, N = g("accepted"), g("phys"), g("names_strict")
  print()
  print(f"TOTAL over {lanes} lane texts of {len({m['label'].split('.bend')[0] for m in ms})} ports")
  print(f"  DENOMINATOR: {len(dup_lanes)} of {lanes} lane texts carry at least one duplicate "
        f"name under the WRITER'S OWN boundary")
  print(f"  rows the writer emitted: {P}   lines the shipped reader ACCEPTS: {A}   distinct "
        f"names the producer printed: {N}   distinct keys `rows()` produces: {g('names_shipped')}")
  print(f"  DUPLICATE NAMES: {g('dup_n_strict')} over {g('dup_rows_strict')} rows, costing "
        f"{g('lost_strict')} measurements (one per surplus row)")
  print(f"  the reader's OWN loss: accepted {A} − keys {g('names_shipped')} = {g('lost_shipped')}")
  # The shipped reader also loses rows to an `=` in a name and to a continuation line.  Both are
  # OTHER classes, measured by `eq-census2.measure()` -- IMPORTED, never re-derived here, so the
  # closed `=` class is reported by its own author and this unit cannot inflate its own number.
  LC = sum(c["lost_cont"] for c in cross)
  LR = sum(c["lost_reshape"] for c in cross)
  print(f"  and the reader's loss attributes to: {LC} continuation + {LR} `=`-in-a-name + "
        f"{g('lost_strict')} duplicate = {LC + LR + g('lost_strict')}"
        f"   {'RECONCILES' if LC + LR + g('lost_strict') == g('lost_shipped') else 'DOES NOT RECONCILE'}")
  if LC + LR + g("lost_strict") != g("lost_shipped"):
    for m, c in zip(ms, cross):
      if m["lost_shipped"] != c["lost_cont"] + c["lost_reshape"] + m["lost_strict"]:
        print(f"      {m['label']}: reader {m['lost_shipped']} vs "
              f"{c['lost_cont']}+{c['lost_reshape']}+{m['lost_strict']} "
              f"(accepted {m['accepted']}, keys {m['names_shipped']})")
  print(f"  NAME-DEFINITION DISAGREEMENT: {sum(len(m['name_defs_differ']) for m in ms)} name(s) "
        f"are a duplicate under one name definition and not under the other -- a duplicate "
        f"counted from one definition alone is not yet a duplicate")
  if a.names:
    print()
    for m in sorted(ms, key=lambda r: (-r["lost_strict"], r["label"])):
      cls = classify(m)
      if not (cls or m["refuse"]):
        continue
      print(f"== {m['label']}  shape={m['shape']} rows={m['phys']} accepted={m['accepted']} "
            f"dupN={m['dup_n_strict']} lost={m['lost_strict']} refused={len(m['refuse'])}")
      for c, items in sorted(cls.items()):
        print(f"   CLASS {c}: {len(items)} name(s)")
        for nm, d, lines in items:
          print(f"     {nm!r} x{d['n']} lines={d['lines']} distinct_vals={d['distinct_vals']}")
          for l in lines:
            print(f"        {l[:150]}")
      for i, nm, ln in m["refuse"][:4]:
        print(f"   REFUSED-BY-ROW() L{i} name={nm!r}: {ln[:120]!r}")
      if len(m["refuse"]) > 4:
        print(f"   ... and {len(m['refuse']) - 4} more refused")
      for i, w in m["nob"][:4]:
        print(f"   NO-BOUNDARY L{i}: {m['src'][i - 1][:120]!r}   [{w}]")
      if len(m["nob"]) > 4:
        print(f"   ... and {len(m['nob']) - 4} more with no boundary")
      if m["name_defs_differ"]:
        print(f"   NAME-DEFINITION DISAGREEMENT on {m['name_defs_differ']}: duplicated under one "
              f"definition only")
  (HERE / "dup-census.json").write_text(json.dumps(
    [{k: v for k, v in m.items() if k != "src"} for m in ms], indent=1, default=str))
  return 0


if __name__ == "__main__":
  sys.exit(main())