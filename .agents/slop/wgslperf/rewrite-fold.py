#!/usr/bin/env python3
"""**THE **FOLD **REWRITE: **THE **KAHN **SORT **BECOMES **A **FORWARD **PASS.**

**WHAT.** THE OLD FOLD WAS A KAHN TOPOLOGICAL SORT OVER THE WHOLE ARENA, AND IT PAID FOR THE
SORT THREE TIMES OVER (ALL MEASURED, `.agents/slop/wgslperf/count-calls.py` AND
`.agents/slop/wgslperf/topo-check.py`):

  1. EVERY POP WALKED THE WHOLE ARENA TO FIND THE POPPED NODE's CONSUMERS -- 495,015,580
     VISITS A TURN.
  2. EVERY RESOLUTION WALKED THE ARENA FOR THE NODE ITSELF (`O.Arena.at` IS A LINEAR LIST
     WALK) -- 5,333,512 WALKS A TURN, ~1.3 BILLION LIST-CELL STEPS.
  3. EVERY PUT COPIED THE WHOLE TABLE (`List.append` COPIES) -- 866,746 COPIES A TURN.

**THE FIX.** MEASURED OVER 1,815 FOLDS, 886,514 NODES AND 1,698,277 EDGES: **NO **NODE's **SRC
HAS **AN **INDEX **AT **OR **ABOVE **THE **NODE's **OWN** -- SO THE ARENA's INDEX ORDER IS A
TOPOLOGICAL ORDER AND THE SORT IS NOT NEEDED. THE FOLD BECOMES ONE FORWARD PASS.

**AND** THE TABLE IS PREPENDED INSTEAD OF APPENDED, WHICH IS BOTH THE CHEAP BUILD (A CONS IS
O(1) AND `List.append` IS O(n)) AND THE FAST LOOKUP: THE TABLE IS IN DESCENDING INDEX ORDER,
SO A NODE's SRC IS AT THE DISTANCE FROM THE NODE, AND A NODE's SRCS ARE BUILT JUST BEFORE IT.
"""

import pathlib
import re

P = pathlib.Path("tinybendygrad/uop/fold.bend")
src = P.read_text()
orig = src

# ── THE BLOCKS THAT GO ────────────────────────────────────────────────────────────
DROP = [
  "Kahn.new", "Kahn.out_of", "Kahn.pend", "Kahn.work", "Kahn.degree", "Kahn.seed.keep",
  "Kahn.seed.work", "Kahn.seed.pend", "Kahn.seed", "Kahn.edges.f", "Kahn.edges",
  "Kahn.budget", "Kahn.dec.go", "Kahn.dec", "Kahn.zero", "Kahn.dec_k", "Kahn.reached.of",
  "Kahn.reached", "Kahn.src_count.add", "Kahn.src_count.f", "Kahn.src_count.go",
  "Kahn.src_count", "Kahn.consumers.dec", "Kahn.consumers.times", "Kahn.consumers.step",
  "Kahn.consumers.go", "Kahn.consumers", "Kahn.ans.of", "Kahn.ans", "Kahn.go.of",
  "Kahn.go", "Kahn.pop", "Kahn.run", "Kahn.step", "UOp.fold", "Kahn.inc.step",
  "Kahn.inc.count", "Kahn.inc.srcs", "Kahn.inc.degree", "Kahn.inc.zero", "Kahn.inc.nodes",
  "Kahn.inc.ready.of", "Kahn.inc.walk", "Kahn.inc.zeros", "Kahn.inc.seed", "UOp.fold_from",
  "folded_from",
]

NEW_FOLD = """# THE FOLD IS ONE FORWARD PASS OVER THE ARENA, NOT A SORT.
#
# MEASURED (`.agents/slop/wgslperf/topo-check.py`, THE COMPILED FORM's OWN COUNT): OVER 1,815
# FOLDS, 886,514 NODES AND 1,698,277 EDGES, NO NODE's SRC HAS AN INDEX AT OR ABOVE THE
# NODE's OWN INDEX. SO THE ARENA's INDEX ORDER IS A TOPOLOGICAL ORDER, AND THE FOLD IS A WALK.
#
# THE SORT COST THREE WALKS A TURN (MEASURED, `.agents/slop/wgslperf/count-calls.py`): EVERY POP
# WALKED THE WHOLE ARENA FOR THE POPPED NODE's CONSUMERS (495,015,580 VISITS), EVERY RESOLUTION
# WALKED THE ARENA FOR THE NODE ITSELF (`O.Arena.at` IS A LINEAR LIST WALK, 5,333,512 WALKS),
# AND EVERY PUT COPIED THE WHOLE TABLE (`List.append` COPIES, 866,746 COPIES).
def Kahn.ans.of(d: Maybe<&2, Derived>, i: U32, +tb: Table) -> Table:
  match d:
    case Some{x}: Table.put(tb, Resolved{i, x})
    case None{}: tb

def Kahn.ans(+ar: O.Arena, nd: O.Node, +i: U32, +tb: Table, ss: List<&2, Derived>) -> Table:
  Kahn.ans.of(derived(ar, i, nd, ss), i, tb)

def Kahn.step.of(gs: Maybe<&2, List<&2, Derived>>, +ar: O.Arena, nd: O.Node, i: U32, +tb: Table) -> Table:
  match gs:
    case Some{ss}: Kahn.ans(ar, nd, i, tb, ss)
    case None{}: tb

def Kahn.step(+ar: O.Arena, +nd: O.Node, i: U32, +tb: Table) -> Table:
  Kahn.step.of(Kahn.gather.of(O.Node.src(nd), tb), ar, nd, i, tb)

def Kahn.walk(+ar: O.Arena, ns: List<&2, O.Node>, +i: U32, +tb: Table) -> Table:
  match ns:
    case Nil{}: tb
    case nd <> t: Kahn.walk(ar, t, U32.add(i, 1), Kahn.step(ar, nd, i, tb))

def UOp.fold(+ar: O.Arena) -> Table:
  Kahn.walk(ar, O.Arena.nodes(ar), 0, Table{Nil{}})"""


def block_of(lines, name):
  pat = re.compile(r"^def " + re.escape(name) + r"\(")
  hits = [i for i, l in enumerate(lines) if pat.match(l)]
  if len(hits) != 1:
    raise SystemExit(f"!! {name}: {len(hits)} definitions")
  i = hits[0]
  j = i + 1
  while j < len(lines) and not re.match(r"^(def |type |#)", lines[j]):
    j += 1
  return i, j


lines = src.split("\n")
# THE LINES THAT GO ARE MARKED, NOT DELETED AS THE SPANS ARE FOUND: A SPAN's LINE NUMBERS
# GO STALE THE MOMENT A LINE BEFORE IT IS GONE, AND A STALE SPAN EATS ITS NEIGHBOUR.
GONE = set()
PUT = None
for nm in DROP:
  pat = re.compile(r"^def " + re.escape(nm) + r"\(")
  i = next(k for k, l in enumerate(lines) if k not in GONE and pat.match(l))
  j = i + 1
  while j < len(lines) and (j in GONE or not re.match(r"^(def |type |#)", lines[j])):
    j += 1
  # THE COMMENT LINES ABOVE THE DEF GO WITH IT, UP TO THE BLANK LINE.
  a = i
  while a > 0 and lines[a - 1].startswith("#"):
    a -= 1
  b = a
  while b > 0 and lines[b - 1].startswith("#"):
    b -= 1
  if b > 0 and lines[b - 1] == "":
    b -= 1
  if nm == "UOp.fold":
    PUT = (b, j)
  for k in range(b, j):
    GONE.add(k)
# AND THE NEW FOLD GOES WHERE `UOp.fold` WAS.
keep = [l for k, l in enumerate(lines) if k not in GONE]
if PUT is not None:
  b, j = PUT
  # THE PUT's PLACE IS COUNTED IN THE KEPT LIST's COORDINATES, NOT IN THE ORIGINAL's.
  pb = sum(1 for k in range(b) if k not in GONE)
  pj = sum(1 for k in range(j) if k not in GONE)
  keep = keep[:pb] + NEW_FOLD.split("\n") + keep[pj:]
src = "\n".join(keep)

# ── THE INCREMENTAL FOLD's COMMENT GOES WITH IT ─────────────────────────────────
lines = src.split("\n")
a = next((i for i, l in enumerate(lines) if l.startswith("# THE INCREMENTAL FOLD -- THE FOLD OF AN ARENA")), None)
if a is not None:
  b = next(i for i, l in enumerate(lines) if l.startswith("# THE RANGES FOLD -- ops.py:483"))
  del lines[a:b]
  src = "\n".join(lines)

# ── THE `Kahn` RECORD AND THE `Incs` RECORD GO WITH THE SORT ──────────────────────
src = src.replace("""type Kahn is Data:
  Kahn{pend: List<&2, U32>, work: List<&2, U32>, out: Table}

""", "")
src = src.replace("""type Incs is Data:
  Incs{ds: List<&2, U32>, ws: List<&2, U32>}

def Incs.ds(ix: Incs) -> List<&2, U32>:
  match ix:
    case Incs{ds, ws}: ds

def Incs.ws(ix: Incs) -> List<&2, U32>:
  match ix:
    case Incs{ds, ws}: ws

""", "")

# ── THE TABLE IS PREPENDED ───────────────────────────────────────────────────────
OLD_PUT = """def Table.put(tb: Table, r: Resolved) -> Table:
  match tb:
    case Table{es}: Table{List.append(&2, Resolved, es, [r])}"""
NEW_PUT = """def Table.put(tb: Table, r: Resolved) -> Table:
  match tb:
    case Table{es}: Table{r <> es}"""
assert OLD_PUT in src
src = src.replace(OLD_PUT, NEW_PUT)

# ── THE GATHER TAKES THE SRCS, NOT THE ARENA AND THE INDEX ───────────────────────
OLD_GATHER = """def Kahn.gather(ar: O.Arena, i: U32, tb: Table) -> Maybe<&2, List<&2, Derived>>:
  Kahn.gather.go(O.Arena.srcs(ar, i), tb, Gathered{Nil{}, True{}})"""
NEW_GATHER = """def Kahn.gather.of(srcs: List<&2, U32>, tb: Table) -> Maybe<&2, List<&2, Derived>>:
  Kahn.gather.go(srcs, tb, Gathered{Nil{}, True{}})"""
assert OLD_GATHER in src
src = src.replace(OLD_GATHER, NEW_GATHER)

P.write_text(src)
print(f"THE FILE WENT FROM {len(orig.splitlines())} LINES TO {len(src.splitlines())}")
