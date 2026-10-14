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
import sys, pathlib, collections, argparse, hashlib, ast

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
# BESIDE the rows it keys, not beside the module. It was `checks/rows-key.rows`, which
# `.gitignore:167` (`checks/rows-*.rows`) ignores, so a cache that could not say it was
# current could never learn to -- the refusal was SELF-SEALING. A pattern containing a slash
# is anchored, so `checks/rows/` is tracked while its sibling `checks/rows-*.rows` is not;
# MEASURED `git check-ignore`: YES for the latter, NO for both former and this key.
# A published set that is in the tree must be the set that can be checked.
KEYS = HERE / "rows" / "keys.rows"
GENERATOR = {"py": _GRAPH, "bend": G.BEND_PROBE}   # the DIRECT file each lane starts FROM
PKG = REPO / "tinybendygrad"                        # `import Base` resolves against THIS
ORACLE = REPO / "tinygrad"                          # the py lane's CPython subject


def _import_closure():
  """`checks/nvrows-deadrow-gate.py:89` LOADED BY PATH, NOT reimplemented.  It is the tree's
  only transitive `.bend` resolver and it understands BOTH spellings this tree uses --
  `import ./x.bend as Y` relative to the FILE and `import Base` relative to the PACKAGE ROOT
  -- and MEASURED 120 of 135 port files need the second form.  A second copy would be the
  `suffixset` class one level down, free to rot with nobody noticing."""
  import importlib.util
  sp = importlib.util.spec_from_file_location("nvrows", HERE / "nvrows-deadrow-gate.py")
  m = importlib.util.module_from_spec(sp)
  sp.loader.exec_module(m)                          # module level is defs + 3 constants
  return m.import_closure


def population(which):
  """The files the lane's rows are a FUNCTION OF.  Not a path, not a hand list, not a basename.

  bend -- the EXACT import closure, 7 files MEASURED 2026-10-14 from `.agents/slop/graphcmp.bend`.
    Bend's imports are static and total (`bend --check-only` checks "the file and its imports"),
    so the closure is a fact about the file and the honest key is that fact.  The other 127
    `.bend` files in the port are OUT of it, and an edit to any of them must leave this key
    still -- that half of the control is what makes the first half mean anything.

  py -- a DIRECTORY WALK of the CPython oracle, 214 files MEASURED, and it is a SUPERSET and
    says so.  The exact Python closure is NOT derivable, MEASURED both ways today:
      * an AST walk finds 87 path STRINGS, of which 39 are eager-loaded at runtime and 48 are
        edges no import takes -- `tinygrad/Tensor.py:8` reads
        `from tinygrad.helpers import cpu_profile, suppress_finalizing, disable_gc, VIZ`, where
        `VIZ` is the ContextVar DEFINED at `tinygrad/helpers.py:271`, not the `tinygrad/VIZ/`
        PACKAGE that happens to sit on disk under that name; and on this case-insensitive
        filesystem `tinygrad/DType.py` and `tinygrad/dtype.py` are ONE inode (6 such pairs
        MEASURED), so a spelling-keyed set counts files twice.
      * `sys.modules` UNDER-counts instead, because the imports are LAZY and PER-GRAPH --
        `graphcmp.py:1155` reaches `line_rewrite` inside one graph builder only, so the closure
        of the py lane is a function of WHICH GRAPH, and there are 34 of them.
    A LOWER BOUND IS NOT A KEY.  An under-count serves stale rows silently, which is the one
    outcome this file exists to prevent, so this side takes the superset and pays for it in
    FALSE staleness, named and counted in the report line below."""
  if which == "bend":
    return sorted(_import_closure()(PKG, GENERATOR["bend"]))
  return [GENERATOR["py"], *sorted(ORACLE.rglob("*.py"))]


def digest(path):
  return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "ABSENT"


LANE_DEF = {"py": "emit_py", "bend": None}   # bend's subject is the whole closure, not one def


def part_digest(path, which):
  """THE LANE's OWN BYTES, NOT THE FILE's.

  `graphcmp.py` holds `emit_py` AND `emit_bend`; they share a file and nothing else, so keying on
  the FILE claims a dependency that does not exist in EITHER direction. MEASURED 2026-10-15:
  `a13db09bd98a` changed `emit_bend` only -- 0 lines of `emit_py` -- and this gate refused **34 of
  34 healthy py slots**, all of them measured BYTE-IDENTICAL to the cache. So the unit is the
  SOURCE SEGMENT of the lane's own def, and the OFFSET goes in the digest too: a function that
  MOVES is an edit like any other, and without the line number two different defs could hash alike.
  """
  raw = path.read_bytes()
  want = LANE_DEF.get(which)
  if not want:
    return hashlib.sha256(raw).hexdigest()
  try:
    text = path.read_text(errors="replace")
    for node in ast.parse(text).body:
      if isinstance(node, ast.FunctionDef) and node.name == want:
        seg = ast.get_source_segment(text, node) or ""
        return hashlib.sha256(f"{want}@{node.lineno}\n{seg}".encode()).hexdigest()
  except (SyntaxError, ValueError):
    pass   # NO DEF FOUND IS NOT "UNCHANGED": fall through to the whole file, which is the safe side
  return hashlib.sha256(raw).hexdigest()


def gen_digest(which, _memo={}):
  """ONE sha256 over `relpath<TAB>sha256` for the WHOLE population, sorted by path.

  NOT a digest LIST in the row: 215 py files times two columns is a table nobody reads, and the
  only question a 4-column key row answers is `is this the same set as the set I wrote`.  The
  MEMBERSHIP stays derivable -- `population()` is a function, not a stored list -- so any reader
  can print WHICH file moved without this file carrying a second copy of the answer."""
  if which not in _memo:
    body = "".join(f"{p.relative_to(REPO).as_posix()}\t{part_digest(p, which)}\n"
                   for p in sorted(set(population(which))))
    _memo[which] = (hashlib.sha256(body.encode()).hexdigest(), body.count("\n"))
  return _memo[which][0]


def blind_spots(which):
  """HOW MANY IMPORT SPELLINGS THE RESOLVER CANNOT READ, so that a low count is never read as
  `there is nothing there`.  MEASURED 2026-10-14: `import_closure`'s `IMPORT` is `^import\\s+(\\S+)`,
  which KEEPS THE QUOTES, and this tree spells 325 lines
  `import "../../../.agents/slop/clangshim/libclang-tramp.c"`.  Those resolve to a path that
  contains a `"` and is therefore never a file, so they are dropped SILENTLY.  For this closure
  the drop MEASURED 0 and this prints 0; it is printed because a resolver that cannot see its
  own blind spot is the defect this project has catalogued twenty times."""
  return sum(1 for p in population(which) for ln in p.read_text(errors="replace").splitlines()
             if ln.strip().startswith("import ") and '"' in ln) if which == "bend" else 0


def read_keys():
  """{(graph, side): (GENERATOR sha, CACHE sha)}, as recorded when THAT SLOT was written.

  TWO DIGESTS, NOT ONE, and the second is the one MEASURED missing: with only the generator's
  digest, editing a single cached row left this gate at `rc=0` -- the key said "these bytes were
  written by that program" and nothing ever re-asked whether they still ARE those bytes. A KEY ON
  THE PRODUCER **IS NOT A KEY ON THE PRODUCT.** The producer being unchanged is evidence about the
  producer. Content resemblance is not authority, and neither is producer identity."""
  if not KEYS.is_file():
    return {}
  out = {}
  for ln in KEYS.read_text().splitlines():
    f = ln.split("\t")
    if len(f) == 4 and f[1] in GENERATOR:
      out[(f[0], f[1])] = (f[2], f[3])
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
  keys[(name, which)] = (gen_digest(which), digest(HERE / "rows" / f"rows-{name}-{which}.rows"))
  KEYS.write_text("".join(f"{g}\t{s}\t{d[0]}\t{d[1]}\n" for (g, s), d in sorted(keys.items())))


def side(name, which, dev, fresh, keys):
  # `.rows`, and it was `.txt` until 2026-10-06: these ARE expected values -- one lane's rows,
  # cached so a re-run does not re-pay for it -- which is the thing `.rows` names in this project.
  # Read and written here and nowhere else, so the extension is this file's own business.
  # It was `HERE / f"rows-{name}-{which}.rows"` -- a SIBLING of the published set, one trailing
  # slash away, and gitignored, so `git ls-files --others --exclude-standard` could not see it
  # and this gate checked a set nothing in the tree owned. The two sets differed only by `/`,
  # which is a SUFFIX: the `suffixset` class, wearing a directory's clothes.
  cache = HERE / "rows" / f"rows-{name}-{which}.rows"
  # BOTH an unkeyed slot AND a keyed slot that disagrees REFUSE, and that is deliberate.
  # I made the unkeyed case fall through to regenerate and it was WRONG, MEASURED: the py lane's
  # `P(i..)` slot is offset by a monotonic counter that reaches the rows via `ParamArg(next(...))`,
  # so a run that regenerates 34 graphs in ONE PROCESS writes 34 rows that depend on how many
  # graphs preceded them -- 37 distinct `P(i..)` values across 68 files where a per-graph run gives
  # one. RE-VERIFIED 2026-10-14 on this tree, and the NUMBERS hold exactly: 37 against 4, 25 of 34
  # slots differing, `alu` -> `P(i1,` and `binblob` -> `P(i2,`. THE MECHANISM WAS WRONG, though,
  # and it is worth the correction because the comment's whole job is to stop a maintainer
  # repeating the mistake: there is NO `itertools.count` here (`grep -n itertools
  # .agents/slop/graphcmp.py` answers nothing). The counter is TINYGRAD's `UOp.unique_num`,
  # cited at `graphcmp.py:864` as `ops.py:1208  if slot is None: slot = next(UOp.unique_num)`.
  # So the rule is right, the reason given names a file that does not contain it, and a reader who
  # audits the reason finds nothing and concludes there is nothing there.
  # So "heal it here" CORRUPTED it, and it corrupted it SILENTLY, which
  # is worse than the self-sealing refusal it replaced: the refusal was wrong about being able to
  # say so, and this lies about having said so. Regenerate OUT OF PROCESS, one graph per process,
  # which is the only way the counter is the same counter the comparison used.
  k = keys.get((name, which))
  if cache.exists() and not fresh:
    # BOTH digests must hold: the generator unchanged says the ROWS WOULD be the same, and the
    # cache unchanged says THEY STILL ARE. Either alone is a clean number from a missing question.
    if k is None or k != (gen_digest(which), digest(cache)):
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
  # THE ENVIRONMENT IS THE FOURTH THING A KEY CANNOT SEE, AND MEASURED HERE, NOT ASSUMED.
  # Regenerating all 68 slots out of process on 2026-10-14 reproduced **67 of 68 rows
  # byte-for-byte**; the one that did not is `lin`/py, and it differed in ONE field -- the
  # `<bytecount>:` prefix, `66:` against `120:` -- with the content after the colon identical.
  # The cause is tinygrad's colourised kernel name: `tinygrad`'s `rgb()` wraps the `4` and the
  # `3` of `sr_4_5_3` in ANSI SGR when `NO_COLOR` is unset, and each escape is a byte the
  # `String.length`-vs-byte-length rule `graphcmp.bend` documents counts wrongly.  So the py
  # lane's ROWS depend on an environment variable that the key did not cover, the tool did not
  # set, and the cache did not record -- and the failure is SILENT, because a differently
  # configured shell rewrites one slot's bytes and `census.py` reports it as a fresh emission.
  # `emit_bend`'s `clean_env` pins `LC_ALL`/`DEV`/`PYTHONPATH` for the BEND side; this is the
  # same move for the PY side, and it is placed beside `DEV` because that is the other
  # production condition this file decides.  ONE environment, decided HERE, is what makes a
  # closure digest sufficient -- and the list may still be incomplete, which is why this line
  # names the one that was MEASURED rather than claiming the set is closed.
  G.os.environ["NO_COLOR"] = "1"
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
  # THE KEY'S OWN SCOPE, IN THE GATE'S OWN OUTPUT, because a key whose scope is invisible is a
  # key nobody can audit -- and this file's `write_key` docstring records that a revision keyed
  # per SIDE was MEASURED wrong precisely because its scope was wider than it looked.
  for _w in ("py", "bend"):
    _n = len(set(population(_w)))
    print(f"key {_w:<4}     : sha256 over {_n} files"
          + (f", blind spots {blind_spots(_w)}" if _w == "bend" else " (oracle walk, a SUPERSET)")
          + f"   digest {gen_digest(_w)[:16]}")
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
