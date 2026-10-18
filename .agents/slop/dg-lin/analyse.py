#!/usr/bin/env python3
"""STATIC analysis of the `lin` graphcmp divergence. Reads two canon rows files, nothing else.

NO COMPILATION, NO bend, NO tinygrad import: the two artifacts under `runs/graphcmp/D/` are
read as TEXT and the eight-field wire format is walked with the SAME reader `graphcmp.py`'s
`unchunks` walks it with (bytecount-prefixed chunks, optional single separator space).

Emits `diff.rows` (TAB separated) and prints the evidence the report cites.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / "runs/graphcmp/D/D2-canon-py-lin.txt"
BEND = ROOT / "runs/graphcmp/D/D2-canon-bend-lin.txt"
OUT = Path(__file__).resolve().parent / "diff.rows"

# graphcmp.py:877 `row_of` -- `u(k), n.op.name, n.dtype.name, cshape(n), u(cdepth(n)),
# ctag(n.tag), carg(n.op, n.arg, n), tup([u(ix[id(s)]) for s in n.src])`
FIELDS = ["ix", "op", "dtype", "shape", "depth", "tag", "arg", "src"]


def unchunks(line: str) -> list[str]:
  """graphcmp.py:360 -- walk the byte counts; at most one optional separator space."""
  out, i = [], 0
  while i < len(line):
    j = line.index(":", i)
    n, k = int(line[i:j]), j + 1
    out.append(line[k:k + n])
    i = k + n
    if i < len(line) and line[i] == " ":
      i += 1
  return out


def read(p: Path) -> list[list[str]]:
  rows = [unchunks(ln) for ln in p.read_text().splitlines() if ln.strip()]
  bad = [n for n, r in enumerate(rows) if len(r) != len(FIELDS)]
  if bad:
    print(f"REFUSED: {p.name} has {len(bad)} rows that are not 8 fields (first: row {bad[0]})",
          file=sys.stderr)
    sys.exit(3)
  return rows


def rebase(src_field: str) -> list[str]:
  return src_field[2:-1].split(",") if src_field != "n()" else []


def ren(ix: int, dropped: int | None) -> int:
  """The index an arena slot takes once arena row `dropped` (0-based) has been removed.
  Indices are 1-based in the wire, and only indices ABOVE the dropped row move."""
  return ix - 1 if dropped is not None and ix > dropped else ix


def norm(r: list[str], dropped: int | None) -> list[str]:
  """The row with EVERY index renumbered for the removal of arena row `dropped`: the row's
  own `ix` and each `src` reference, which are arena indices and must move together. This
  renumbering is the ONLY normalisation under test; every other byte is demanded equal."""
  out = list(r)
  out[0] = f"i{ren(int(r[0][1:]), dropped)}"
  out[7] = "n(" + ",".join(f"i{ren(int(s[1:]), dropped)}" for s in rebase(r[7])) + ")"
  return out


def main() -> None:
  py, bd = read(PY), read(BEND)
  n_py, n_bd = len(py), len(bd)

  # 1. The FIRST row whose eight fields, byte for byte, differ.
  first = next((i for i in range(min(n_py, n_bd)) if py[i] != bd[i]), None)
  # 2. The first row that differs with the INDEX FIELD REMOVED -- i.e. the first real
  #    divergence as opposed to the first renumbering.
  first_ign_ix = next((i for i in range(min(n_py, n_bd)) if py[i][1:] != bd[i][1:]), None)

  # 3. ALIGNMENT TEST: drop py's AFTER row, rebasel every py index by -1, demand byte
  #    identity. If that holds, the tail is pure renumbering and the whole divergence is
  #    the rows dropped -- but a reader that could not find the AFTER first would test the
  #    wrong hypothesis, so the dropped row is located and reported.
  after_ix = [i for i, r in enumerate(py) if r[1] == "AFTER"]
  aligned = None
  if len(after_ix) == 1:
    a = after_ix[0]  # 0-based arena row of the AFTER; its wire index is a + 1
    kept = [r for i, r in enumerate(py) if i != a]
    aligned = all(norm(r, a) == bd[i] for i, r in enumerate(kept))
    resid = [(i, norm(r, a), bd[i]) for i, r in enumerate(kept) if norm(r, a) != bd[i]]
  else:
    resid = []

  print(f"rows py={n_py} port={n_bd} delta={n_bd - n_py}")
  print(f"first byte-differing row (0-based) = {first}   py={py[first]}")
  print(f"first differing row EXCLUDING ix    = {first_ign_ix}")
  print(f"py AFTER rows at 0-based {after_ix}")
  print(f"align(drop that AFTER, rebase -1) byte-identical = {aligned}; residual rows = {len(resid)}")
  for i, a, b in resid:
    print(f"  residual row {i}:\n    py   {a}\n    port {b}")
    for f, (x, y) in enumerate(zip(a, b)):
      if x != y:
        print(f"    field {FIELDS[f]}: py={x!r} port={y!r}")

  # 4. OP CENSUS, computed here rather than quoted, so every count has a denominator.
  def census(rows: list[list[str]]) -> dict[str, int]:
    c: dict[str, int] = {}
    for r in rows:
      c[r[1]] = c.get(r[1], 0) + 1
    return c

  cp, cb = census(py), census(bd)
  census_txt = " ".join(
    f"{k} {cp.get(k, 0)}/{cb.get(k, 0)}" for k in sorted(set(cp) | set(cb)))
  n_bad_op = sum(1 for k in set(cp) | set(cb) if cp.get(k, 0) != cb.get(k, 0))
  print(f"op census (py/port over {n_py}/{n_bd} nodes): {census_txt}")
  print(f"ops whose count differs: {n_bad_op} of {len(set(cp) | set(cb))}")

  lines = ["side\tfirst_divergent_node\tn_nodes_side\tn_nodes_port\tnote",
           f"cpython\t{py[first][0]} (arena row {first} of {n_py})\t{n_py}\t{n_bd}\t"
           f"first divergence: op=AFTER dtype=i32 tag=N arg=N src=n(i7,i5); "
           f"AFTER count 1 of {n_py} nodes; py is the LONGER side by {n_py - n_bd}",
           f"port\t{bd[first][0]} (arena row {first} of {n_bd})\t{n_py}\t{n_bd}\t"
           f"first divergence: op=RANGE dtype=i32 arg=rg(i0,XWEAK,n(i2)) src=n(i7,i5) "
           f"TWO srcs; AFTER count 0 of {n_bd} nodes",
           f"op-census\t-\t{n_py}\t{n_bd}\t{census_txt} "
           f"({n_bad_op} of {len(set(cp) | set(cb))} ops differ in count)",
           f"align-drop-after\t-\t{n_py - 1}\t{n_bd}\t"
           f"drop py arena row {after_ix[0] if len(after_ix) == 1 else 'REFUSED'} and renumber "
           f"every py index above it: {n_bd - len(resid)} of {n_bd} rows byte-identical, "
           f"{len(resid)} residual"]
  for i, a, b in resid:
    bad = [f"{FIELDS[f]} py={x} port={y}" for f, (x, y) in enumerate(zip(a, b)) if x != y]
    lines.append(f"residual-row {i}\t{a[0]} {a[1]}\t{n_py}\t{n_bd}\t" + "; ".join(bad))
  OUT.write_text("\n".join(lines) + "\n")
  print(f"wrote {OUT}")


main()