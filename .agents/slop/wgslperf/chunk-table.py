#!/usr/bin/env python3
"""**THE **CHUNKED **TABLE: **A **LOOKUP **WALKS **THE **SPINE **AND **ONE **CHUNK.**

**WHY.** V8's OWN CPU PROFILE OF THE COMPILED FORM (`.agents/slop/wgslperf/prof-read.py`) SAYS THE
FLAT TABLE's LOOKUP (`Kahn.get.go2`) IS 35.7% OF THE TURN's EXCLUSIVE TIME: 2,520,919 LOOKUPS A
TURN, EACH ONE SCANNING A LIST OF ~478 ENTRIES. THE CHUNKED TABLE WALKS THE SPINE (THE INDEX
DIVIDED BY 32) AND THEN ONE CHUNK (32 ENTRIES), SO A LOOKUP IS ~31 CELLS AND NOT ~383.

**AND** THE CHUNKS ARE BY THE NODE INDEX, SO THE FOLD -- WHICH WALKS THE ARENA IN INDEX ORDER --
FILLS THEM IN ORDER, AND THE TABLE's LAYOUT IS MINE: NO `Table` USE IS OUTSIDE `fold.bend`.
"""

import pathlib

P = pathlib.Path("tinybendygrad/uop/fold.bend")
src = P.read_text()


def swap(old, new):
  global src
  assert old in src, old[:120]
  src = src.replace(old, new)


# ── THE TABLE IS A SPINE OF CHUNKS ────────────────────────────────────────────────
swap("""type Table is Data:
  Table{es: List<&2, Resolved>}

def Table.es(tb: Table) -> List<&2, Resolved>:
  match tb:
    case Table{es}: es
""", """# THE TABLE IS A SPINE OF CHUNKS, NOT A FLAT LIST.
#
# MEASURED (V8's OWN CPU PROFILE OF THE COMPILED FORM, `.agents/slop/wgslperf/prof-read.py`): A
# LOOKUP IN THE FLAT TABLE (`Kahn.get.go2`) IS 35.7% OF THE TURN's EXCLUSIVE TIME -- 2,520,919
# LOOKUPS A TURN, AND EACH ONE SCANNED A LIST OF ~478 ENTRIES. THE CHUNKED TABLE WALKS THE
# SPINE (THE INDEX DIVIDED BY 32 CHUNKS) AND THEN ONE CHUNK (32 ENTRIES), SO A LOOKUP IS ~31
# CELLS AND NOT ~383.
#
# THE CHUNKS ARE BY THE NODE INDEX: THE ENTRY FOR INDEX `i` IS IN CHUNK `i / 32`, AND THAT
# CHUNK HOLDS THE INDICES IN `[32k, 32k+32)`. THE FOLD WALKS THE ARENA IN INDEX ORDER, SO THE
# ENTRIES COME OUT IN ASCENDING INDEX ORDER AND THE CHUNKS FILL IN ORDER.
type Table is Data:
  Table{cs: List<&2, List<&2, Resolved>>, cur: List<&2, Resolved>, ci: U32}

def Table.cs(tb: Table) -> List<&2, List<&2, Resolved>>:
  match tb:
    case Table{cs, cur, ci}: cs

def Table.cur(tb: Table) -> List<&2, Resolved>:
  match tb:
    case Table{cs, cur, ci}: cur

def Table.ci(tb: Table) -> U32:
  match tb:
    case Table{cs, cur, ci}: ci
""")

swap("""def Table.put(tb: Table, r: Resolved) -> Table:
  match tb:
    case Table{es}: Table{r <> es}

def Table.len(tb: Table) -> Nat:
  List.length(&2, Resolved, Table.es(tb))
""", """def Table.put(i: U32, tb: Table, r: Resolved) -> Table:
  match tb:
    case Table{cs, cur, ci}: Table{cs, r <> cur, ci}

# THE CHUNK ENDS WITH THE NODE WHOSE INDEX IS `32k + 31`.
def Kahn.chunk_end(i: U32) -> Bool:
  U32.is_zero(U32.and(U32.add(i, 1), 31))

# THE FULL CHUNK GOES ON THE SPINE AND THE NEXT ONE STARTS EMPTY.
def Kahn.roll(tb: Table, i: U32) -> Table:
  match Kahn.chunk_end(i):
    case True{}: Table{List.append(&2, List<&2, Resolved>, Table.cs(tb), [Table.cur(tb)]), Nil{}, U32.add(Table.ci(tb), 1)}
    case False{}: tb

def Table.len(tb: Table) -> Nat:
  Nat.add(List.length(&2, List<&2, Resolved>, Table.cs(tb)), List.length(&2, Resolved, Table.cur(tb)))
""")

# ── THE LOOKUP ───────────────────────────────────────────────────────────────────
swap("""def Kahn.get.go2(+t: List<&2, Resolved>, +i: U32, acc: Maybe<&2, Derived>) -> Maybe<&2, Derived>:
  match t:
    case Nil{}: acc
    case Resolved{ri, rd} <> rest:
      match acc:
        case Some{d}: acc
        case None{}: Kahn.get.go2(rest, i, Kahn.get.at(Kahn.get.eq(i, ri), rd))

def Kahn.get.go(+i: U32, es: List<&2, Resolved>) -> Maybe<&2, Derived>:
  Kahn.get.go2(es, i, None{})
""", """def Kahn.get.chunk.go(i: U32, es: List<&2, Resolved>, acc: Maybe<&2, Derived>) -> Maybe<&2, Derived>:
  match es:
    case Nil{}: acc
    case Resolved{ri, rd} <> rest:
      match acc:
        case Some{d}: acc
        case None{}: Kahn.get.chunk.go(i, rest, Kahn.get.at(Kahn.get.eq(i, ri), rd))

def Kahn.get.chunk(i: U32, es: List<&2, Resolved>) -> Maybe<&2, Derived>:
  Kahn.get.chunk.go(i, es, None{})

# THE SPINE WALK: THE CHUNK OF INDEX `i` IS THE `i / 32`th ONE.
def Kahn.get.spine(i: U32, cs: List<&2, List<&2, Resolved>>, +k: U32) -> List<&2, Resolved>:
  match cs:
    case Nil{}: Nil{}
    case c <> t:
      match U32.is_eq(U32.shrn(i, 5n), k):
        case True{}: c
        case False{}: Kahn.get.spine(i, t, U32.add(k, 1))

def Kahn.get(i: U32, tb: Table) -> Maybe<&2, Derived>:
  match U32.is_eq(U32.shrn(i, 5n), Table.ci(tb)):
    case True{}: Kahn.get.chunk(i, Table.cur(tb))
    case False{}: Kahn.get.chunk(i, Kahn.get.spine(i, Table.cs(tb), 0n))
""")

# ── THE OLD ENTRY POINT GOES ─────────────────────────────────────────────────────
swap("""def Kahn.get(i: U32, tb: Table) -> Maybe<&2, Derived>:
  Kahn.get.go(i, Table.es(tb))

""", "")

# ── THE FOLD PUTS AND ROLLS ──────────────────────────────────────────────────────
swap("""def Kahn.ans.of(d: Maybe<&2, Derived>, i: U32, +tb: Table) -> Table:
  match d:
    case Some{x}: Table.put(tb, Resolved{i, x})
    case None{}: tb
""", """def Kahn.ans.of(d: Maybe<&2, Derived>, i: U32, +tb: Table) -> Table:
  match d:
    case Some{x}: Table.put(i, tb, Resolved{i, x})
    case None{}: tb
""")

swap("""    case nd <> t: Kahn.walk(ar, t, U32.add(i, 1), Kahn.step(ar, nd, i, tb))
""", """    case nd <> t: Kahn.walk(ar, t, U32.add(i, 1), Kahn.roll(Kahn.step(ar, nd, i, tb), i))
""")

swap("""def UOp.fold(+ar: O.Arena) -> Table:
  Kahn.walk(ar, O.Arena.nodes(ar), 0, Table{Nil{}})
""", """def UOp.fold(+ar: O.Arena) -> Table:
  Kahn.walk(ar, O.Arena.nodes(ar), 0, Table{Nil{}, Nil{}, 0})
""")

P.write_text(src)
print("THE CHUNKED TABLE IS IN")
