#!/usr/bin/env python3
"""NAME THE 6 DISAGREEING GRAPHS, AND FOR EACH THE FIRST ROW THAT DISAGREES.

READ-ONLY over `runs/graphcmp/D/` AND over the harness source that declares the
population (`graphcmp.py`'s `GRAPHS`) and its dispatcher (`graphcmp.bend`'s `rows.pick3`).
RUNS NOTHING: every number printed here is read back out of the artifacts `checks/differ.py
run` left on disk, or out of those two source files, so this script cannot perturb the run
it reads and cannot be accused of agreeing with itself -- it has no arithmetic of its own on
the port.

A canonical row is `N:i<id>` then SEVEN length-prefixed chunks -- the op NAME and the
SIX fields the differ compares, in this fixed wire order.  `fields=6` on every
`DENOMINATOR` line is the count of the compared ones; the op name is chunk 0 and is
matched, not compared:

    2:i46 4:SINK 4:void 1:R 2:i0 2:i1 66:kI(...) 6:n(i45)
    |     |     |      |    |    |      |
    |     |     |      |    |    |      +-- src
    |     |     |      |    |    +--------- arg
    |     |     |      |    +-------------- tag
    |     |     |      |    +------------------- depth
    |     |     |      +------------------------ shape
    |     |     +------------------------------- dtype
    |     +------------------------------------- op name  (matched, NOT compared)
    +------------------------------------------- in-degree, arena id

So the WIRE SHAPE question ("is the canonical serialisation itself different, which
would let the port be CORRECT and the comparison still disagree?") is answerable by
parsing every row of both sides, and `wire_shape_agrees` does exactly that.  A
serialisation defect -- a missing field, a different order, a bad prefix -- fails the
parse; a differing VALUE never does.
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]  # .agents/slop/disagree/names.py -> repo root
D = ROOT / "runs" / "graphcmp" / "D"
BEND = ROOT / ".agents" / "slop" / "graphcmp.bend"
PY = ROOT / ".agents" / "slop" / "graphcmp.py"

# chunk 0 is the op name: matched, not compared.  Named once so the script cannot
# invent a column and cannot silently drop one either.
CHUNKS = ("op", "dtype", "shape", "depth", "tag", "arg", "src")
FIELDS = CHUNKS[1:]

VERDICT = re.compile(r"^# VERDICT: (\w+)$", re.M)
ROWS = re.compile(r"^# py rows=(\d+)\s+bend rows=(\d+)\b", re.M)
HUNK = re.compile(r"^(\d+)(?:,(\d+))?([acd])(\d+)(?:,(\d+))?$", re.M)

# the dispatcher's structure: an ARM is `String.eq(name, "x"), g_x()`, and the FALLBACK is
# the one `g_*()` call in `rows.pick3` no arm routes to.
ARM = re.compile(r'String\.eq\(name, "([^"]+)"\),\s*(g_\w+)\(\)')
CALL = re.compile(r"\b(g_\w+)\(\)")
GRAPH_KEY = re.compile(r'"([^"]+)":\s*(g_\w+)')


class Tree:
  """`runs/graphcmp/D` under a name.  The PLANT lane points this at a copy, so the
  gate can move a byte without writing a byte into the run it reads."""

  def __init__(self, d: Path):
    self.d = d

  def rows(self) -> list[Path]:
    return sorted(self.d.glob("D1-graph-*.txt"))

  def graph(self, p: Path) -> str:
    return p.name.removeprefix("D1-graph-").removesuffix(".txt")

  def verdict(self, p: Path) -> str:
    m = VERDICT.search(p.read_text())
    if m is None:
      raise ValueError(f"{p.name}: no VERDICT line, so this file says nothing")
    return m.group(1)

  def rows_seen(self, p: Path) -> tuple[int, int]:
    m = ROWS.search(p.read_text())
    if m is None:
      raise ValueError(f"{p.name}: no `py rows=`/`bend rows=` line")
    return int(m.group(1)), int(m.group(2))

  def canon(self, g: str, side: str) -> list[str]:
    return (self.d / f"D2-canon-{side}-{g}.txt").read_text().splitlines()

  def cmp_record(self, g: str) -> str:
    """the differ's OWN record of the byte comparison, `diff` output."""
    return (self.d / f"D2-cmp-{g}.txt").read_text()

  def digest(self, g: str, side: str) -> str:
    return hashlib.sha256((self.d / f"D2-canon-{side}-{g}.txt").read_bytes()).hexdigest()

  def summary(self, key: str) -> str | None:
    for line in (self.d / "D0-run-summary.txt").read_text().splitlines():
      if line.startswith(f"{key}="):
        return line
    return None


def parse_row(line: str) -> tuple[str, dict[str, str]]:
  """`N:i<id>` + six `len:text` fields -> (id, {field: text}).  Length-prefixed, so
  a field may contain `:` and the parse needs no regex to find the boundaries."""
  head, _, rest = line.partition(" ")
  if not head.endswith(tuple("0123456789")) or "i" not in head:
    raise ValueError(f"not a canonical row: {line!r}")
  out: dict[str, str] = {}
  for name in CHUNKS:
    n, _, rest = rest.partition(":")
    n = int(n)
    if n > len(rest):
      raise ValueError(f"row truncated in {name}: {line!r}")
    out[name], rest = rest[:n], rest[n:]
    if rest[:1] == " ":
      rest = rest[1:]
  if rest:
    raise ValueError(f"{len(CHUNKS)} chunks consumed {len(line) - len(rest)} chars, "
                     f"{len(rest)} left over: {rest!r}")
  return head.partition("i")[2], out


def wire_shape_agrees(t: Tree, graphs: list[str]) -> str | None:
  """The brief's cheap hypothesis, falsified or not: a canonical form that differs in
  SHAPE (a missing field, a different order) would let the port be right and the
  comparison still disagree.  The wire is LENGTH-PREFIXED, so the test is that every
  row of both sides parses into exactly seven length-prefixed chunks and consumes
  itself exactly.  A
  missing field, a reordered field or a bad prefix all fail that; a differing VALUE
  never does.  Counting spaces instead would be wrong -- a bytes arg spells `y n(97)`,
  which carries a space, and that is why the wire is length-prefixed at all."""
  for g in graphs:
    for side in ("py", "bend"):
      for ln, line in enumerate(t.canon(g, side), 1):
        try:
          parse_row(line)
        except ValueError as e:
          return f"{side}/{g}:{ln}: {e}"
  return None


def first_row_from_cmp(t: Tree, g: str) -> int | None:
  """BELT 1: read the FIRST HUNK HEADER out of the differ's own `diff` record.
  Two methods that do not share a regex -- see `first_row_recomputed`."""
  text = t.cmp_record(g)
  if "DIFFERS" not in text:
    return None
  for line in text.splitlines():
    m = HUNK.match(line)
    if m:
      return int(m.group(1))
  raise ValueError(f"{g}: D2-cmp says DIFFERS but names no hunk header")


def first_row_recomputed(t: Tree, g: str) -> int | None:
  """BELT 2: recompute the first differing line by walking the two canonical files
  side by side.  Shares no code, no regex and no INPUT FILE with belt 1: belt 1 reads
  the differ's own `diff` record, belt 2 reads the bytes that record is a diff OF.  A
  record and its diff disagreeing is itself the finding, so they are compared, not
  reconciled."""
  a, b = t.canon(g, "py"), t.canon(g, "bend")
  if a == b:
    return None
  for i, (x, y) in enumerate(zip(a, b), 1):
    if x != y:
      return i
  return min(len(a), len(b)) + 1


def row_at(lines: list[str], n: int) -> str | None:
  return lines[n - 1] if 0 < n <= len(lines) else None


def diagnose(t: Tree) -> list[dict]:
  out = []
  for p in t.rows():
    g = t.graph(p)
    v = t.verdict(p)
    py_n, bend_n = t.rows_seen(p)
    d: dict = {"graph": g, "verdict": v, "py_rows": py_n, "bend_rows": bend_n}
    if v != "DISAGREE":
      continue
    n1 = first_row_from_cmp(t, g)
    n2 = first_row_recomputed(t, g)
    d["first_row_from_cmp"] = n1
    d["first_row_recomputed"] = n2
    d["first_row"] = n1
    d["belts_agree"] = n1 == n2
    a, b = t.canon(g, "py"), t.canon(g, "bend")
    if n1 is None:
      # the graph's two canonical files are equal, so there is no row to name.  Only a
      # PLANT gets here on a run; a real run never has a DISAGREE with no first row.
      d["py_row"] = d["bend_row"] = None
      d["fields"], d["values"] = [], {}
      d["extra_rows"] = py_n - bend_n
      d["one_sided"] = one_sided_ops(a, b)
      out.append(d)
      continue
    pa, pb = row_at(a, n1), row_at(b, n1)
    d["py_row"], d["bend_row"] = pa, pb
    if pa is not None and pb is not None:
      _, fa = parse_row(pa)
      _, fb = parse_row(pb)
      d["fields"] = [k for k in FIELDS if fa[k] != fb[k]]
      d["values"] = {k: (fa[k], fb[k]) for k in d["fields"]}
    else:  # the row exists on one side only, or the two files have different lengths
      d["fields"] = ["<no row on that side>"]
      d["values"] = {}
    d["extra_rows"] = py_n - bend_n
    d["one_sided"] = one_sided_ops(a, b)
    out.append(d)
  return out


def one_sided_ops(a: list[str], b: list[str]) -> list[str]:
  """Ops on one side only.  A disagreement can be a DIFFERENT VALUE in a row both sides
  have (`lin`, `loop`), or a row one side has and the other does not (`flip`: the bend
  side mints a GROUP the py side never built).  Naming the ops is what tells the two
  classes apart without the reader diffing two node lists by eye."""
  def ops(lines: list[str]) -> dict[str, int]:
    out: dict[str, int] = {}
    for ln in lines:
      try:
        i, c = parse_row(ln)
      except ValueError:
        continue
      out[f"{c['op']}#{i}"] = out.get(f"{c['op']}#{i}", 0) + 1
    return out

  ao, bo = ops(a), ops(b)
  only_a = sorted(k for k in ao if k not in bo)
  only_b = sorted(k for k in bo if k not in ao)
  return [f"py-only {k}" for k in only_a] + [f"bend-only {k}" for k in only_b]


def silent_default_cluster(t: Tree, graphs: list[str]) -> dict[str, list[str]]:
  """A graph name the BEND side has no fixture for cannot be compared at all: the
  fallback hands back some OTHER graph, and an 18-row graph is indistinguishable from
  a correct one.  Group the bend canonical files by sha256 and name the clusters that
  contain more than one name."""
  by_hash: dict[str, list[str]] = {}
  for g in graphs:
    by_hash.setdefault(t.digest(g, "bend"), []).append(g)
  return {h: sorted(v) for h, v in by_hash.items() if len(v) > 1}


def dispatcher_substitutions(bend: Path, py: Path) -> list[str]:
  """Every `GRAPHS` name `rows.pick3` has no arm for and whose fallback is a DIFFERENT
  graph.  A substitution is a property of the DISPATCHER, not of any run: a name with no
  `String.eq` arm falls through to `rows.pick3`'s single fallback builder, the bend side
  builds THAT graph while the py side built the real one, and the differ compares two
  different graphs -- AGENTS.md's `SKIP`, which a per-graph verdict cannot see because the
  substituted report prints `ops-reached=n/n` and looks symmetrical.

  THE POPULATION IS DERIVED: `GRAPHS` is the population, the dispatcher's own arms are the
  ARMED set, and the fallback's name leaves the set with no edit.  The hand list this
  replaced (`("allred","cdiv","late")`) could only ever name the three it already knew --
  the very fault this gate exists to catch, inside the gate.  BOTH FILES ARE RE-READ ON
  EVERY CALL: a discovery that baked 29/34 would be a hand list with extra steps."""
  text = bend.read_text()
  start = text.index("def rows.pick3")
  body = text[start:text.index("def rows.pick(", start)]
  pairs = ARM.findall(body)
  armed, builders = {n for n, _ in pairs}, {b for _, b in pairs}
  defaults = set(CALL.findall(body)) - builders
  if len(defaults) != 1:
    raise ValueError(f"rows.pick3 has {len(defaults)} fallback builders, expected 1: "
                     f"{sorted(defaults)}")
  fallback = next(iter(defaults)).removeprefix("g_")
  source = py.read_text()
  graphs = source[source.index("GRAPHS = {"):]
  graphs = graphs[:graphs.index("}")]
  return sorted(g for g, _ in GRAPH_KEY.findall(graphs) if g not in armed and g != fallback)


def main() -> int:
  import argparse

  ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
  ap.add_argument("--tree", type=Path, default=D,
                  help="a graphcmp run directory to read (default: runs/graphcmp/D)")
  ap.add_argument("--json", action="store_true",
                  help="emit the machine-readable form `checks/disagree-gate.py` reads")
  a = ap.parse_args()
  tree = a.tree if a.tree.is_absolute() else ROOT / a.tree

  if not (ROOT / "checks" / "differ.py").exists():
    print(f"FATAL: ROOT is {ROOT}, which is not the repo root "
          f"(-- HERE.parents[{HERE.parents.index(ROOT)}] is wrong); "
          f"checks/differ.py is missing under it.", file=sys.stderr)
    return 2
  if not tree.is_dir():
    print(f"FATAL: no run at {tree}.  Run `python checks/differ.py run` first.", file=sys.stderr)
    return 2

  t = Tree(tree)
  graphs = [t.graph(p) for p in t.rows()]
  bad = wire_shape_agrees(t, graphs)
  clusters = silent_default_cluster(t, graphs)
  substituted = dispatcher_substitutions(BEND, PY)

  if a.json:
    import json
    print(json.dumps({
      "graphs": graphs,
      "disagree": [{**d, "first_row_from_cmp": first_row_from_cmp(t, d["graph"]),
                    "first_row_recomputed": first_row_recomputed(t, d["graph"])}
                   for d in diagnose(t)],
      "substituted": substituted,
      "wire_shape_defect": bad,
    }, indent=2))
    return 1 if bad is not None else 0

  print(f"# graphs on disk: {len(graphs)}")
  print(f"# {t.summary('graphs-disagree')}")
  print(f"# SUBSTITUTED, derived from `GRAPHS` and `rows.pick3`'s dispatch (a property of "
        f"the harness, not of this run): {substituted or 'none'}")
  print(f"# WIRE SHAPE, both sides, all graphs: "
        f"{'SAME 7-chunk length-prefixed wire on every row -- a serialisation defect is FALSIFIED' if bad is None else bad}")
  if bad is not None:
    return 1

  for d in diagnose(t):
    print()
    print(f"{d['graph']:8s} VERDICT={d['verdict']}  py rows={d['py_rows']} bend rows={d['bend_rows']}")
    if d["first_row"] is None:
      print("  NO DISAGREEING ROW: the two canonical files are equal")
      continue
    print(f"  FIRST DISAGREEING ROW: line {d['first_row']} of the canonical file"
          f"   (two belts agree: {d['belts_agree']})")
    print(f"  py   {d['py_row']}")
    print(f"  bend {d['bend_row']}")
    for k, (x, y) in d["values"].items():
      print(f"    FIELD {k}: py={x!r}  bend={y!r}")
    if d["extra_rows"]:
      print(f"    ROW COUNT: py={d['py_rows']} bend={d['bend_rows']}, "
            f"{abs(d['extra_rows'])} node(s) on one side only")
    if d["one_sided"]:
      print(f"    ONE-SIDED OPS: {', '.join(d['one_sided'])}")

  print()
  if clusters:
    for h, names in sorted(clusters.items()):
      print(f"# BEND-SIDE CANONICAL FILES THAT ARE ONE FILE: {names}  sha256={h[:16]}")
    print("#   ^ every name in such a cluster got the SAME graph back from the bend side;")
    print("#     a missing fixture cannot disagree, it substitutes.  THIS IS A PROPERTY OF")
    print("#     THE RUN's artifacts and can lag the dispatcher; the derived set above is")
    print("#     the harness's current state.")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
