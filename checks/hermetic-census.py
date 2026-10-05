#!/usr/bin/env python3
"""hermetic-census.py -- the ops-reached number, with every graph's result INDEPENDENT of
what ran before it and of what is on disk.

MECHANISM FOR (1), the slot leak: `isolate.emit` gives each graph its own process, so no
`UOp.unique_num` value can be inherited. See `isolate.py` for why that and not a counter reset.

MECHANISM FOR (2), the stale cache: THERE IS NO CACHE ON THE VERDICT PATH. `census()` always
emits. The row sets on disk are a PUBLISHED ARTIFACT, written from that fresh emission, and
`--check` is the only thing that reads them -- so "default vs --fresh" is not a comparison this
file can lose, because there is no flag that makes the default read a cache. Chosen over
"verify-on-read" for a reason measured against the actual failure: re-emitting to compare
costs the same emit, so verify-on-read is a fresh emission PLUS a comparison, i.e. strictly
this file plus a tamper check that `--check` already does at zero emission cost.

**THE FAILURE THIS IS BUILT AGAINST, AND IT IS NOT HYPOTHETICAL.** Measured: 15 of the 24
published py row sets under `.agents/slop/arith/` disagree with a fresh process, every one of
them with the SAME row count and differing only inside the `45:`/`46:` chunk -- the
`ParamArg` record, whose first field is `slot`. `checks/both-census.py:39` reads that file by
default, so its number was computed from bytes no fresh run could reproduce. The union still
read 59 because the census reads field 1, the OP, and the op census is INVARIANT to the slot:
the agreement was luck, not verification. A census that cannot see a 15-of-24 byte corruption
in its own inputs is not a coverage statement.

`ops_of` is IMPORTED from `checks/both-census.py` rather than retyped, because that file's own
comment asks for it ("Kept as one function so both instruments cannot drift") and a second
copy of the field-1 read is a second thing to be wrong about.
"""
from __future__ import annotations
import sys, pathlib, argparse, hashlib, collections

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE)); sys.path.insert(0, str(REPO / ".agents" / "slop" / "arith"))
sys.path.insert(0, str(REPO / ".agents" / "slop")); sys.path.insert(0, str(REPO))
import graphcmp as G
import isolate
# `checks/both-census.py` has a HYPHEN, so it is not importable by name; load it by path rather
# than retyping its `ops_of`. That file asks for this in its own comment ("Kept as one function so
# both instruments cannot drift"), and a second copy of the field-1 read is a second thing to be
# wrong about. It is another unit's file, so a MISSING or RENAMED copy is loud, not silent.
import importlib.util
_spec = importlib.util.spec_from_file_location(
    "both_census", REPO / ".agents" / "slop" / "arith" / "both-census.py")
_bc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_bc)
ops_of = _bc.ops_of


def digest(rows: list[str]) -> str:
  return hashlib.md5("\n".join(rows).encode()).hexdigest()


def census(names: list[str], dev: str, out: pathlib.Path, publish: bool) -> tuple:
  """Every graph, both sides, each in its own process. Returns the two op Counters."""
  if publish: out.mkdir(parents=True, exist_ok=True)
  py_tot, bd_tot, walls = collections.Counter(), collections.Counter(), []
  for name in names:
    for which, tot in (("py", py_tot), ("bend", bd_tot)):
      try:
        rows = isolate.emit(name, which, dev)
      except SystemExit as e:                        # a wall, not a count
        walls.append(f"{name}/{which}: {e}")
        print(f"#   {name:<10} {which:<4} WALL {e}")
        continue
      tot.update(ops := ops_of(rows))
      if publish:
        (out / f"rows-{name}-{which}.txt").write_text("\n".join(rows) + "\n")
      print(f"#   {name:<10} {which:<4} rows={len(rows):<4} ops={len(ops):<3} "
            f"md5={digest(rows)}  {dict(sorted(ops.items()))}")
  return py_tot, bd_tot, walls


def check(names: list[str], dev: str, out: pathlib.Path) -> int:
  """Re-emit and byte-compare the PUBLISHED artifact. Any mismatch is named per graph and
  exits 3 -- loudly, and not in a shape a reader can mistake for a census."""
  bad = []
  for name in names:
    for which in ("py", "bend"):
      f = out / f"rows-{name}-{which}.txt"
      if not f.exists():
        bad.append((f"{name}/{which}", "ABSENT")); continue
      published = [ln for ln in f.read_text().splitlines() if ln.strip()]
      fresh = isolate.emit(name, which, dev)
      if published != fresh:
        bad.append((f"{name}/{which}", f"published rows={len(published)} fresh rows={len(fresh)} "
                                      f"md5 {digest(published)} vs {digest(fresh)}"))
  for k, why in bad:
    print(f"# STALE {k}: {why}")
  print(f"# --check: {len(names) * 2 - len(bad)}/{len(names) * 2} published row sets reproduce; "
        f"{len(bad)} do not")
  return 3 if bad else 0


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--dev", default="CPU")
  ap.add_argument("--only", default=None, help="comma list of graphs")
  ap.add_argument("--out", default=str(HERE / "rows"), help="published row sets")
  ap.add_argument("--check", action="store_true", help="re-emit and byte-compare the published "
                                                       "row sets; exit 3 on any disagreement")
  ap.add_argument("--no-publish", action="store_true", help="census without writing artifacts")
  a = ap.parse_args()
  names = sorted(G.GRAPHS) if a.only is None else a.only.split(",")
  out = pathlib.Path(a.out)

  if a.check:
    return check(names, a.dev, out)

  # The PARENT imports tinygrad for exactly one thing: the denominator `len(list(Ops))`. It
  # builds no graph, so its own `unique_num` and ucache are irrelevant here -- every row comes
  # from `isolate.emit`, in a child that has never seen another graph.
  G.os.environ["DEV"] = a.dev
  G.load_tinygrad()

  py_tot, bd_tot, walls = census(names, a.dev, out, publish=not a.no_publish)
  denom = len(list(G.Ops))                            # measured, never transcribed
  both = set(py_tot) & set(bd_tot)
  print("#")
  print(f"# graphs in corpus       : {len(names)}")
  print(f"# ops UPSTREAM (denom)  : {denom}   (measured len(list(Ops)))")
  print(f"# reached PY             : {len(py_tot)}")
  print(f"# reached BEND           : {len(bd_tot)}")
  print(f"# reached BOTH           : {len(both)}   <- the honest coverage number")
  print(f"# py-only  (bend MISSING): {sorted(set(py_tot) - set(bd_tot))}")
  print(f"# bend-only (py MISSING) : {sorted(set(bd_tot) - set(py_tot))}")
  print(f"# WALLS                  : {walls}")
  return 0


if __name__ == "__main__":
  sys.exit(main())