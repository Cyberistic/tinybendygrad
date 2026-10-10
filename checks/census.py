#!/usr/bin/env python
"""DENOM census -- reach for BOTH sides, caching into THIS unit's own directory.

WHY A COPY AND NOT `checks/both-census.py`: both now sit in `checks/`, so that script's
cache is `checks/rows-<graph>-<side>.txt` -- the SAME DIRECTORY as this one's, so running
it would OVERWRITE this unit's rows, and `.txt` is an extension `checks/no-txt.py`
forbids outright (it exits 1 on the tree as it stands).  A copy, so the two cannot share
a cache; own cache, own output.  Read-only use of its ideas.  Everything it does that
matters is here: both sides emitted, the py-only/bend-only split, the denominator MEASURED
at run time as `len(list(Ops))`, and a WALL reported as a WALL and never counted as a zero.

THERE ARE **THREE** CACHES OF THIS ONE CORPUS, NOT TWO, and only one of them can say it is
stale.  MEASURED today, py lane, 34 slots, against the live `isolate.emit`:
  * THIS ONE, `checks/rows-<graph>-<side>.rows` -- 11 of 34 reproduce.  No check, until now.
  * `checks/both-census.py`'s, `checks/both-rows-<graph>-<side>.rows` -- 11 of 34, and
    byte-identical to this one's on every one of the 34: same emitter, same rows, same age.
  * `checks/hermetic-census.py`'s PUBLISHED set, `checks/rows/rows-<graph>-<side>.rows` --
    27 of 27 py slots reproduce, and `--check` answers rc=3 over BOTH lanes with
    `# --check: 39/68 published row sets reproduce; 29 do not`.
So the third is the one to read, it is the only one with a generator that will say `STALE`,
and this file's is kept rather than deleted for one measured reason: deleting it re-pays a
`bend` process per slot on every run.  WHAT IT MAY NOT DO ANY MORE IS SERVE A CACHE THAT
CANNOT SAY WHETHER IT IS CURRENT -- see `GENERATOR` below.
"""
import sys, pathlib, collections, argparse, hashlib

HERE = pathlib.Path(__file__).resolve().parent
# `parents[0]` IS the repo root, and the depth is PROVED by `refuse()` below, not assumed.
# The pair of constants was copied VERBATIM (same `# the tinygrad tree` comment) from
# `.agents/slop/arith/both-census.py:24`, where BOTH were correct: at that depth
# `parents[0]` was `.agents/slop`, which held `graphcmp`, and `parents[2]` was the tinygrad
# tree.  `3f0e70ff1` moved the copy to `checks/`, ONE level shallower, and carried both
# constants across without recomputing them -- so `parents[2]` became `/Users/cyberistic/src`,
# which MEASURED holds only `tries/`: no tinygrad, no graphcmp, no tinybendygrad.  One
# constant stayed live by luck (this repo IS the tinygrad tree); the other became a NO-OP
# THAT LOOKS LIKE A FIX -- `sys.path.insert` of a directory holding no importable module.
# `graphcmp` was NEVER reachable from `checks/`: the dead copy in `checks/` was already
# dead at `3f0e70ff1`, so `import graphcmp` raised and no one could see which line was to blame.
REPO = HERE.parents[0]


def refuse(*why: str) -> None:
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE the `sys.path` manipulation and before the `graphcmp` import, because under
  bare `python3` the wrong root made THAT import raise `ModuleNotFoundError` -- and an
  assertion DOWNSTREAM of what it asserts cannot turn an exception into a refusal.  The
  unfixed tree did exactly that: rc 1 and a traceback, which carries no denominator and so
  counts nowhere."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# TWO TRACKED MARKERS, so a FOURTH relocation is a refusal rather than a third exception:
# the substrate this file's root claim rests on, and the one module it imports.
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
_GRAPH = REPO / ".agents" / "slop" / "graphcmp.py"
if not _GRAPH.is_file():
  refuse(f"input absent: {_GRAPH}")

sys.path.insert(0, str(REPO))                    # the tinygrad tree
sys.path.insert(0, str(_GRAPH.parent))           # `graphcmp`; reachable from NEITHER above
import graphcmp as G


def ops_of(rows):
  recs = {r[1:]: G.unchunks(r) for r in rows}
  return collections.Counter(f[1] for f in recs.values())


# --- THE KEY, AND WHY A CACHE WITHOUT ONE IS A DIARY -------------------------------------------
# A cache is WHAT THE RUN LAST WROTE. Without the generator beside it, that is all it is: a
# row set with a date on it and nothing that can say the date is current. MEASURED on this
# file's own cache, `checks/rows-<graph>-<side>.rows`, 34 py slots against the live
# `isolate.emit`: **11 reproduce, 23 do not** -- and this file exited 0 over all 68 slots with
# `WALLS: []`, a census of the PRE-FIX tree reported as a census.
#
# THE KEY IS THE GENERATING FIXTURE'S BYTES, NOT A COMMIT. A commit is not the generator's
# identity: units commit into this tree while a run is in flight, so a commit key churns for
# edits that cannot change a row, and it is a plain falsehood whenever the worktree is dirty.
# If `graphcmp.py` has not changed `emit_py` cannot have; if `graphcmp.bend` has not changed
# `emit_bend` cannot have. Both paths come from the module, never retyped.
#
# IT IS ALSO NOT A `SUBJECTS.rows` COLUMN. `.agents/slop/SUBJECTS.rows` carries
# `path in_head on_disk readable_now`, which is the right SHAPE -- one row per claim, claim
# and truth side by side, so a file's own drift is visible in the file itself -- and the wrong
# CONTENT: it answers "is this path still there", and a cache's failure mode is not a path
# going missing, it is a path staying exactly where it was while the thing that fills it moved
# underneath. A column can make drift visible to a READER. It cannot stop `side()` serving,
# and serving is the whole failure.
KEYS = HERE / "rows-key.rows"       # already gitignored: `.gitignore:167` is `checks/rows-*.rows`
GENERATOR = {"py": _GRAPH, "bend": G.BEND_PROBE}   # `G.BEND_PROBE` IS `.agents/slop/graphcmp.bend`


def digest(path):
  return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "ABSENT"


def read_keys():
  """{(graph, side): sha256}, as recorded when THAT SLOT was written. AN ABSENT FILE IS NOT AN
  ERROR and is not `{}` either: it means every slot on disk was written by a generator nobody
  named, and that is `STALE`, which is the answer rather than a fallback."""
  if not KEYS.is_file():
    return {}
  out = {}
  for ln in KEYS.read_text().splitlines():
    f = ln.split("\t")
    if len(f) == 3 and f[1] in GENERATOR:
      out[(f[0], f[1])] = f[2]
  return out


def write_key(name, which):
  """ONE ROW PER SLOT, `graph<TAB>side<TAB>sha256`, and the per-slot granularity is not
  tidiness -- it is a bug this file had and MEASURED. A revision keyed per SIDE, on the
  reasoning that one generator file emits one lane for all 34 graphs and so one digest decides
  all 34. That is true of the DECISION and false of the KEY. `--fresh --only flip` records the
  py digest having written exactly ONE slot, and the next `census.py --only allred` served a
  slot MEASURED stale (`allred` py: live sha256 c132f982b000, cached a26fae5f072e) off it and
  exited 0. A KEY WHOSE SCOPE IS WIDER THAN THE RUN THAT WROTE IT IS THE CLASS ONE LEVEL
  DOWN, and a scope column that says `ALL rows-*-py.rows` is the lie that let it through."""
  keys = read_keys()
  keys[(name, which)] = digest(GENERATOR[which])
  KEYS.write_text("".join(f"{g}\t{s}\t{d}\n" for (g, s), d in sorted(keys.items())))


def side(name, which, dev, fresh, keys):
  # `.rows`, and it was `.txt` until 2026-10-06: these ARE expected values -- one lane's rows,
  # cached so a re-run does not re-pay for it -- which is the thing `.rows` names in this project.
  # Read and written here and nowhere else, so the extension is this file's own business.
  cache = HERE / f"rows-{name}-{which}.rows"
  if cache.exists() and not fresh:
    if keys.get((name, which)) != digest(GENERATOR[which]):
      return ("STALE", 0, None, set())   # served NOTHING, and `0` here is "not counted"
    rows = [ln for ln in cache.read_text().splitlines() if ln.strip()]
    return ("CACHE", len(rows), ops_of(rows), set())
  try:
    rows = G.emit_py(name, None) if which == "py" else G.emit_bend(dev, name)[0]
  except Exception as e:
    return ("WALL", 0, None, set())
  if not rows:                     # THE TRAP: 0 rows is not a census, it is a failure
    return ("WALL", 0, None, set())
  cache.write_text("\n".join(rows) + "\n")
  write_key(name, which)
  return ("OK", len(rows), ops_of(rows), set())


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--dev", default="CPU")
  ap.add_argument("--only", default=None)
  ap.add_argument("--fresh", action="store_true")
  a = ap.parse_args()
  G.os.environ["DEV"] = a.dev
  G.load_tinygrad()
  G.COMM = G.commutative()
  names = sorted(G.GRAPHS) if a.only is None else a.only.split(",")
  keys = read_keys()
  py, bn, walls, stale = set(), set(), [], []
  for n in names:
    st, nr, c, _ = side(n, "py", a.dev, a.fresh, keys)
    st2, nr2, c2, _ = side(n, "bend", a.dev, a.fresh, read_keys())
    if c: py |= set(c)
    if c2: bn |= set(c2)
    if st == "WALL" or st2 == "WALL": walls.append(n)
    if "STALE" in (st, st2):
      stale += [f"{n}/{w}" for w, s in (("py", st), ("bend", st2)) if s == "STALE"]
    print(f"# {n:<10} py={st:<6}{nr:<5} bend={st2:<6}{nr2:<5}", flush=True)
  denom = len(list(G.Ops))
  print()
  print(f"graphs      : {len(names)}")
  print(f"denominator : {denom}   (measured len(list(Ops)))")
  print(f"reached PY  : {len(py)}")
  print(f"reached BEND: {len(bn)}")
  print(f"reached BOTH: {len(py & bn)}")
  print(f"py-only     : {sorted(py - bn)}")
  print(f"bend-only   : {sorted(bn - py)}")
  print(f"WALLS       : {walls}")
  print(f"NEITHER     : {len(denom and set(o.name for o in G.Ops) - (py | bn))}")
  print("NEITHER-list:" + " ".join(sorted(set(o.name for o in G.Ops) - (py | bn))))
  # A STALE SLOT IS A REFUSAL, NOT A COVERAGE NUMBER. The `reached` rows above are computed
  # over what was SERVED, so with a stale slot among them they are a census of the OLD tree and
  # must not be read as one. exit 3 is `checks/hermetic-census.py --check`'s own exit for the
  # same condition, so the two share a number AND a vocabulary -- both are Python, and both
  # print the offending slot and a denominator.
  if stale:
    print(f"STALE       : {len(stale)} of {len(names) * 2} slots are on disk and their generator "
          f"has moved since they were written: {stale}")
    print("             a stale slot is SERVED NEITHER, so the `reached` rows above are a "
          "census of the OLD tree; --fresh re-emits")
    return 3
  return 0


if __name__ == "__main__":
  sys.exit(main())
