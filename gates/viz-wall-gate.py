#!/usr/bin/env python3
"""viz-wall-gate.py -- WHAT `tinybendygrad/viz/serve.bend` HAS, against WHAT UPSTREAM'S
`tinygrad/viz/serve.py` HAS, re-derived on every run.

    .venv/bin/python gates/viz-wall-gate.py
    .venv/bin/python gates/viz-wall-gate.py --rows OUT.rows
    .venv/bin/python gates/viz-wall-gate.py --refresh

THE QUESTION THIS ANSWERS. A user asked whether `VIZ=1` is implemented. The port's
`tinybendygrad/viz/serve.bend` is 1967 lines and answers, in its own words, "viz's LOGIC,
without viz's SERVER". This gate measures the gap between that file and upstream's
`tinygrad/viz/serve.py` WITHOUT EDITING EITHER, and it goes RED THE MOMENT A CAPABILITY
APPEARS -- which is the whole point of a wall table: it is only useful if it can notice the
wall coming down.

BOTH POPULATIONS ARE DISCOVERED, AND NEITHER IS A LIST I TYPED.

  UPSTREAM's capabilities are DISCOVERED by `ast` over the blob at
  `refs/remotes/upstream/master:tinygrad/viz/serve.py`: every top-level `def` and `class`,
  with its line number. MEASURED: 46 of them at HEAD.

  UPSTREAM's ROUTES are DISCOVERED from the SAME tree, not transcribed: the string constants
  that `Handler.do_GET` compares a request path against, and the `fmt` comparisons in
  `get_render`. The route set is therefore upstream's own, and a route upstream adds shows up
  here without this file being edited.

  THE PORT's defs are DISCOVERED by `os.walk` over `tinybendygrad/` plus `endswith(".bend")`
  -- never `glob`, which returns `[]` when `.bend` files ARE on disk. Every `def NAME` and
  every `type NAME is` in every `.bend` file is a port capability.

WHAT IS A HAND LIST HERE, AND WHY IT IS NOT A POPULATION. Three small tables, each admitted
in the source with its reason:

  ALIAS      upstream name -> port name, for the THREE capabilities the port renamed
             (`parse_branch` -> `parse_branch_row`, `get_int` -> `get_int_row`,
             `canonicalize_ast` -> `canonicalize_ast_is`).
  PARTIAL    the capabilities the port HAS a def for but does NOT do the whole thing of.
             Each carries its reason, and the reason is the finding, not a tolerance.
  The PIN FILE `gates/viz-wall-pins.rows` holds the EXPECTED state per capability. The gate
  re-derives the state and diffs it against the pin, so a capability appearing in the port
  turns the diff non-empty and the gate RED.

THIS GATE IS RED ON THIS TREE, AND IT SAYS SO RATHER THAN HIDING IT. Two rows are red, and
both are ONE-TOKEN FIXES IN A `.bend` FILE:

  `op_color_len.literal`  the row at `tinybendygrad/viz/serve.bend:1868` hard-codes `65`.
                           Upstream's `len(uops_colors)` is **64** at
                           `refs/remotes/upstream/master` (MEASURED), because `Ops.FLIP` was
                           deleted from `GroupOp.Movement` after the port was written.
                           The port's own ladder MEASURED against upstream's dict gives 64
                           for all 75 of its ops with ZERO colour mismatches, so the row
                           would read `64|65` and disagree with any oracle.

  `f32.wall_claim`         `tinybendygrad/viz/serve.bend:102-112` calls the float's four
                           bytes a Bend wall ("base has NO `F32.to_bits`"). IT IS NOT A WALL.
                           `F32.bits` is a `law` in `references/bend/bend2/base.bend:1785`
                           and a COMPILER INTRINSIC (`comp.ts:227` -> `f32_bits: { C: "$0",
                           JS: "f32_bits($0)" }`, `comp.ts:493` -> `new Uint32Array(new
                           Float32Array([x]).buffer)[0]`), and the PORT ALREADY CALLS IT in
                           `tinybendygrad/dtype.bend:758`, `helpers.bend:909`,
                           `renderer/tc_ptx.bend:299` and three more files. `F32.from_bits`
                           is defined port-locally at `tinybendygrad/base.bend:54`.

A GATE THAT CANNOT PASS TEACHES NOTHING, so note what the RED is and is not: the
CAPABILITY-TABLE lane -- the lane this gate exists for -- is GREEN, and it is green because
the re-derived table equals the pin. The two red rows are the two REAL defects this
investigation found, and both are named above with their fix.

THE ORACLE IS ABSENT, AND THAT IS A ROW. `checks/vz_gate.py` is the port's own gate for
`tinybendygrad/viz/serve.bend`; it REFUSES (exit 3) because its CPython oracle
`checks/viz_oracle.py` is not on disk and has never been committed (MEASURED: 0 commits
touch it; `.agents/slop/vz/` is absent too). So the port's viz rows have NO ORACLE today,
and this gate is the instrument that replaces the missing one for the question it can
answer -- which is the SHAPE OF THE GAP, not the VALUES.

THE EXITS ARE `gatekit`'s. `REFUSED` (3) when upstream or the port tree is absent -- an
absent input is not a pass. `DEAD` (5) when no row was emitted. `FAIL` (1) when a lane is
red.
"""

from __future__ import annotations

import ast
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

ROOT = HERE.parent
PORT_REL = "tinybendygrad"
UPSTREAM = "refs/remotes/upstream/master"
UPSTREAM_FILE = "tinygrad/viz/serve.py"
PINS = HERE / "viz-wall-pins.rows"

# ---------------------------------------------------------------------------
# THE THREE ADMITTED TABLES. None of them is a POPULATION: the populations are
# discovered (upstream by `ast`, the port by `os.walk`), and these three say how the two
# discovered sets are RELATED.
# ---------------------------------------------------------------------------

# UPSTREAM NAME -> PORT NAME, for the capabilities the port renamed. Three, and each is a
# rename rather than a port of a DIFFERENT function: `parse_branch_row` computes
# `parse_branch`'s answer, `get_int_row` reads `get_int`'s answer out of a query, and
# `canonicalize_ast_is` answers `canonicalize_ast`'s QUESTION without doing its rewrite.
ALIAS = {
  "parse_branch": "parse_branch_row",
  "get_int": "get_int_row",
  "canonicalize_ast": "canonicalize_ast_is",
}

# CAPABILITY -> WHY IT IS PARTIAL. The port has a def for the capability and does not do the
# whole thing of it. The reason IS the finding.
PARTIAL = {
  "canonicalize_ast": "the port answers the IS-question (`canonicalize_ast_is`); upstream "
                      "REWRITES the UOp (`u.replace(arg=KernelInfo())`)",
  "parse_branch": "the port computes the offset from an (op_name, simm16) PAIR; upstream "
                  "reads it off an `Inst`",
  "get_int": "the port reads an int out of a Kv query list; upstream reads it out of a "
             "`parse_qs` dict",
  "timeline_layout": "the port packs FIVE of upstream's six `<IIIIfI` fields; the 32-bit "
                     "float is the one it cannot produce -- and the reason it gives is a "
                     "wall that is not a wall (see `f32.wall_claim`)",
  "create_step": "the port's step is a List of Kv and its `_data` is a Maybe<String>; "
                 "upstream's step is a dict whose `_data` is an arbitrary object",
  "rel_ts": "upstream RAISES on an out-of-range timestamp; the port answers a Maybe "
            "(`REFUSED`). Same value on the in-range side.",
  "encode_mem_free": "the port returns the packed bytes as a List<U32> plus the string "
                     "table; upstream returns bytes. Same layout.",
}

# The capabilities upstream serves over HTTP. Their names come from upstream's own source
# (the path comparisons in `do_GET` and the `fmt` comparisons in `get_render`), so the SET is
# discovered. A capability in this set is a ROUTE: the port must have a def that PRODUCES it,
# and the port has none, so every route is ABSENT.
ROUTE_MARKER = "route:"


def git(*args: str) -> str:
  return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def upstream_source() -> str:
  return git("show", f"{UPSTREAM}:{UPSTREAM_FILE}")


# ---------------------------------------------------------------------------
# DISCOVERY 1 -- upstream's capabilities and routes, by `ast`.
# ---------------------------------------------------------------------------

def upstream_capabilities(src: str) -> list[tuple[str, int]]:
  """(name, line) for every top-level `def`/`class`, plus the ROUTES, all from the source."""
  tree = ast.parse(src)
  out: list[tuple[str, int]] = []
  for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
      out.append((node.name, node.lineno))
  for route, line in upstream_routes(tree):
    out.append((f"{ROUTE_MARKER}{route}", line))
  return out


def _const_str(node: ast.AST) -> str | None:
  return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None


def _is_path(node: ast.AST) -> bool:
  """`url.path` or `self.path` -- the request path under dispatch."""
  return isinstance(node, ast.Attribute) and node.attr == "path"


def _is_fmt(node: ast.AST) -> bool:
  """`fmt` -- the render format local in `get_render`."""
  return isinstance(node, ast.Name) and node.id == "fmt"


def upstream_routes(tree: ast.Module) -> list[tuple[str, int]]:
  """The request paths and render formats upstream dispatches on, WITH the line that names them.

  DISCOVERED, NOT TRANSCRIBED: the paths are the string constants compared against a
  `*.path` attribute, and the formats are the constants compared against the local `fmt`.
  A PREFIX dispatch (`self.path.startswith(("/assets/", "/js/"))`, `fmt.startswith("sqtt")`)
  contributes its prefix, and the line is the call's own.
  """
  found: dict[str, int] = {}

  def add(route: str, line: int) -> None:
    if route and route not in found:
      found[route] = line

  for node in ast.walk(tree):
    if isinstance(node, ast.Compare):
      for op, comparator in zip(node.ops, node.comparators):
        if not isinstance(op, (ast.Eq, ast.In)):
          continue
        const = _const_str(comparator)
        if const is None:
          continue
        if _is_path(node.left):
          add(const, node.lineno)
        elif _is_fmt(node.left):
          add(const, node.lineno)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "startswith":
      target = node.func.value
      for arg in node.args:
        consts = [_const_str(elt) for elt in arg.elts] if isinstance(arg, ast.Tuple) else [_const_str(arg)]
        for const in consts:
          if const is None:
            continue
          if _is_path(target) or _is_fmt(target):
            add(const, node.lineno)
  return sorted(found.items())


# ---------------------------------------------------------------------------
# DISCOVERY 2 -- the port's defs, by `os.walk` + `endswith`. Never `glob`.
# ---------------------------------------------------------------------------

DEF_RE = re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)")
TYPE_RE = re.compile(r"^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)\s+is\b")


def port_defs() -> dict[str, tuple[str, int]]:
  """port capability name -> (relative path, line), over every `.bend` file in the port tree."""
  out: dict[str, tuple[str, int]] = {}
  base = ROOT / PORT_REL
  for dirpath, dirnames, filenames in os.walk(base):
    dirnames[:] = [d for d in dirnames if d != "__pycache__"]
    for name in filenames:
      if not name.endswith(".bend"):
        continue
      path = Path(dirpath) / name
      rel = path.relative_to(ROOT).as_posix()
      for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        for pattern in (DEF_RE, TYPE_RE):
          m = pattern.match(line)
          if m:
            out.setdefault(m.group(1), (rel, lineno))
            break
  return out


# ---------------------------------------------------------------------------
# THE DERIVATION. Present / Absent / Partial, per discovered capability.
# ---------------------------------------------------------------------------

def derive(caps: list[tuple[str, int]], port: dict[str, tuple[str, int]]) -> list[tuple[str, str, str, str, str]]:
  """(capability, upstream_ref, state, port_ref, note) per capability, in upstream order.

  THE CAPABILITY SET COMES FROM UPSTREAM, EVERY RUN. The pin file holds the EXPECTED STATE
  per capability, so a capability that upstream GAINS is a row with no pin, and a capability
  the PORT gains changes its derived state. Both are red.
  """
  rows = []
  for name, line in caps:
    if name.startswith(ROUTE_MARKER):
      state = "ABSENT"
      note = "upstream serves this path; the port has no server, so no route answers it"
      rows.append((name, f"{UPSTREAM_FILE}:{line}", state, "", note))
      continue
    port_name = ALIAS.get(name, name)
    hit = port.get(port_name)
    if hit is None:
      state, note = "ABSENT", "no def of this name anywhere in the port tree"
    else:
      state = "PARTIAL" if name in PARTIAL else "PRESENT"
      note = PARTIAL.get(name, "")
    rows.append((name, f"{UPSTREAM_FILE}:{line}", state, f"{hit[0]}:{hit[1]}" if hit else "", note))
  return rows


# ---------------------------------------------------------------------------
# LANE B -- the `op_color_len` literal, against upstream's measured `len(uops_colors)`.
# ---------------------------------------------------------------------------

OP_COLOR_ROW = re.compile(r'row\("op_color_len",\s*String\.concat\(\[op_color_len\(\),\s*"\|(\d+)"\]\)\)')
OP_COLOR_DEF = re.compile(r"def op_color_len\(\) -> String:")


def port_op_color_literal() -> tuple[str, int, int] | None:
  """(path, line, literal) of the hard-coded expected value in the port's `op_color_len` row."""
  path = ROOT / PORT_REL / "viz/serve.bend"
  if not path.is_file():
    return None
  for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
    m = OP_COLOR_ROW.search(line)
    if m:
      return (path.relative_to(ROOT).as_posix(), lineno, int(m.group(1)))
  return None


def upstream_uops_colors_len() -> int:
  """`len(uops_colors)` at upstream HEAD, MEASURED by asking upstream's own module."""
  code = ("import sys; sys.path.insert(0, %r)\n"
          "from tinygrad.uop.render import uops_colors\n"
          "print(len(uops_colors))\n") % str(ROOT)
  out = subprocess.run([sys.executable, "-c", code], cwd=ROOT, capture_output=True, text=True)
  if out.returncode != 0:
    raise RuntimeError(out.stderr[-400:])
  return int(out.stdout.strip().splitlines()[-1])


# ---------------------------------------------------------------------------
# LANE C -- the `F32.to_bits` wall claim, against what the port can actually do.
# ---------------------------------------------------------------------------

F32_BITS_USE = re.compile(r"F32\.bits\s*\(")
F32_FROM_BITS_DEF = re.compile(r"^\s*def\s+F32\.from_bits\s*\(")
WALL_CLAIM = re.compile(r"NO\s+`?F32\.to_bits`?")


def f32_availability() -> tuple[bool, str, str]:
  """(available, where, why). `available` means the PORT can read a float's four bytes."""
  base = ROOT / PORT_REL
  caller = ""
  for dirpath, dirnames, filenames in os.walk(base):
    dirnames[:] = [d for d in dirnames if d != "__pycache__"]
    for name in filenames:
      if not name.endswith(".bend"):
        continue
      path = Path(dirpath) / name
      rel = path.relative_to(ROOT).as_posix()
      for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
          continue
        if F32_FROM_BITS_DEF.match(line):
          return (True, f"{rel}:{lineno}", "the port defines F32.from_bits (U32 -> F32)")
        if F32_BITS_USE.search(line) and not caller:
          caller = f"{rel}:{lineno}"
  if caller:
    return (True, caller, "the port calls F32.bits (F32 -> U32) in live code")
  return (False, "", "no port .bend file reads a float's bits")


def wall_claim_site() -> tuple[str, int] | None:
  """Where the port's own header still calls the float's bytes a wall."""
  path = ROOT / PORT_REL / "viz/serve.bend"
  if not path.is_file():
    return None
  for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
    if WALL_CLAIM.search(line):
      return (path.relative_to(ROOT).as_posix(), lineno)
  return None


# ---------------------------------------------------------------------------
# THE PINS. `gates/viz-wall-pins.rows` is the EXPECTED table, in git, beside the gate.
# ---------------------------------------------------------------------------

def read_pins() -> list[tuple[str, int]]:
  if not PINS.is_file():
    return []
  out = []
  for ln in PINS.read_text(encoding="utf-8").splitlines():
    if not ln.strip() or ln.startswith("#"):
      continue
    parts = ln.split("\t")
    if len(parts) < 2:
      continue
    out.append((parts[0], int(parts[1])))
  return out


def write_pins(rows: list[tuple[str, str, str, str, str]]) -> None:
  lines = ["# viz-wall-pins.rows -- the EXPECTED capability table for `tinybendygrad/viz/serve.bend`.",
           "# capability<TAB>upstream_line<TAB>state<TAB>port_ref<TAB>note",
           "# The capability set and the upstream line numbers are DISCOVERED by `gates/viz-wall-gate.py`",
           "# (`ast` over `refs/remotes/upstream/master:tinygrad/viz/serve.py`); this file records the",
           "# STATE each one is expected to hold. A capability that appears in the port changes the",
           "# derived state and the gate goes RED until this file is refreshed.",
           "#"]
  for name, ref, state, port_ref, note in rows:
    lines.append("\t".join([name, ref.rsplit(":", 1)[-1], state, port_ref, note]))
  PINS.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# THE COMPARISON. The state of every discovered capability against the pin.
# ---------------------------------------------------------------------------

def pinned_states() -> dict[str, str]:
  """capability -> expected state, from the pin file."""
  if not PINS.is_file():
    return {}
  out = {}
  for ln in PINS.read_text(encoding="utf-8").splitlines():
    if not ln.strip() or ln.startswith("#"):
      continue
    parts = ln.split("\t")
    if len(parts) > 2:
      out[parts[0]] = parts[2]
  return out


def compare(caps: list[tuple[str, int]], port: dict[str, tuple[str, int]]) -> list[str]:
  """The differences between the re-derived table and the pin. EMPTY means they agree."""
  pinned = pinned_states()
  changed = []
  derived = {name: state for name, _, state, _, _ in derive(caps, port)}
  for name, state in derived.items():
    if name not in pinned:
      changed.append(f"{name}: upstream has a capability the pin does not describe (derived {state})")
    elif pinned[name] != state:
      changed.append(f"{name}: pinned {pinned[name]} -> derived {state}")
  for name in pinned:
    if name not in derived:
      changed.append(f"{name}: the pin describes a capability upstream no longer has")
  return changed


# ---------------------------------------------------------------------------
# MAIN.
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
  if "--refresh" in argv:
    return refresh()
  if "--plant" in argv:
    return plant()
  rows_out = argv[argv.index("--rows") + 1] if "--rows" in argv else None

  if not (ROOT / PORT_REL).is_dir():
    print(f"REFUSED  the port tree {ROOT / PORT_REL} is ABSENT", file=sys.stderr)
    return REFUSED
  try:
    src = upstream_source()
  except subprocess.CalledProcessError:
    print(f"REFUSED  {UPSTREAM} is ABSENT -- an absent input is not a pass", file=sys.stderr)
    return REFUSED

  pins = read_pins()
  if not pins:
    print(f"REFUSED  {PINS.name} is MISSING -- the expected table lives in git, beside the gate.\n"
          f"    {sys.executable} {Path(__file__).name} --refresh", file=sys.stderr)
    return REFUSED

  port = port_defs()
  caps = upstream_capabilities(src)
  derived = derive(caps, port)

  # LANE A -- the capability table, re-derived against the pin. The STATE is what is
  # compared; the upstream LINE is reported, because upstream re-vendors move lines and a
  # moved line is not a defect in the port.
  lane_a_rows = [f"{name}\t{state}\t{port_ref}" for name, _, state, port_ref, _ in derived]
  changed = compare(caps, port)

  # LANE B -- the `op_color_len` literal against upstream's measured value.
  lane_b = []
  lit = port_op_color_literal()
  if lit is None:
    lane_b.append("op_color_len.literal\tABSENT\t\tthe port's op_color_len row was not found")
    changed.append("op_color_len.literal: the row is gone")
  else:
    rel, lineno, value = lit
    measured = upstream_uops_colors_len()
    state = "AGREES" if value == measured else "DISAGREES"
    lane_b.append(f"op_color_len.literal\t{state}\t{rel}:{lineno}\tport says {value}, upstream measures {measured}")
    if state != "AGREES":
      changed.append(f"op_color_len.literal: port says {value}, upstream measures {measured}")

  # LANE C -- the `F32.to_bits` wall claim against what the port can do.
  lane_c = []
  available, where, why = f32_availability()
  claim = wall_claim_site()
  if claim is None:
    lane_c.append("f32.wall_claim\tABSENT\t\tno claim of a float-bytes wall in the port's header")
  elif available:
    lane_c.append(f"f32.wall_claim\tSTALE\t{claim[0]}:{claim[1]}\tthe claim is false: {why} ({where})")
    changed.append(f"f32.wall_claim: the port still claims a wall that is not a wall ({where})")
  else:
    lane_c.append(f"f32.wall_claim\tHOLDS\t{claim[0]}:{claim[1]}\t{why}")

  # A FACT ROW, not a verdict: the port's own viz gate has no oracle.
  oracle = ROOT / "checks/viz_oracle.py"
  lane_d = [f"oracle.present\t{'YES' if oracle.is_file() else 'NO'}\tchecks/viz_oracle.py\t"
            f"checks/vz_gate.py REFUSES without it"]

  all_rows = lane_a_rows + lane_b + lane_c + lane_d
  if not all_rows:
    print("DEAD  no rows were emitted", file=sys.stderr)
    return DEAD

  print(f"UPSTREAM   : {UPSTREAM} ({UPSTREAM_FILE})")
  print(f"POPULATION : {len(pins)} upstream capabilities "
        f"({sum(1 for n, _ in pins if n.startswith(ROUTE_MARKER))} routes, discovered by `ast`)")
  print(f"PORT       : {len(port)} defs/types over {PORT_REL}/ (os.walk + endswith('.bend'))")
  print()
  for name, ref, state, port_ref, note in derived:
    print(f"  {state:8s} {name:28s} {ref:34s} {port_ref}")
  print()
  for row in lane_b + lane_c + lane_d:
    print("  " + row)
  print()

  if changed:
    print("CHANGED:")
    for c in changed:
      print(f"  {c}")
  else:
    print("NO CHANGES against the pin.")

  if rows_out:
    Path(rows_out).write_text("row\n" + "\n".join(all_rows) + "\n", encoding="utf-8")
    print(f"ROWS       : {len(all_rows)} -> {rows_out}")

  code = FAIL if changed else PASS
  print(f"# viz-wall-gate: {VERDICT[code]}")
  return code


def plant() -> int:
  """THE PLANT: a capability APPEARS in the port, and the gate must go red.

  NOTHING ON DISK IS TOUCHED. The plant injects a synthetic def into the port's DISCOVERED
  capability map -- the same map the real run compares -- and asserts that the comparison
  notices. A wall table that cannot notice the wall coming down is a list, not an
  instrument, and this is the measurement that says which one this is.
  """
  src = upstream_source()
  caps = upstream_capabilities(src)
  port = port_defs()
  before = compare(caps, port)
  added = ["graph_layout", "get_profile"]
  for name in added:
    port[name] = (f"{PORT_REL}/viz/serve.bend", 0)
  after = compare(caps, port)
  fired = [c for c in after if c not in before]
  for name in added:
    if not any(c.startswith(f"{name}:") for c in fired):
      print(f"PLANT DID NOT FIRE for {name} -- the gate cannot see a capability appear", file=sys.stderr)
      return FAIL
  print("PLANT: the port gains two capabilities, and the gate says so:")
  for c in fired:
    print(f"  {c}")
  return PASS


def refresh() -> int:
  src = upstream_source()
  caps = upstream_capabilities(src)
  port = port_defs()
  rows = []
  for name, line in caps:
    if name.startswith(ROUTE_MARKER):
      rows.append((name, f"{UPSTREAM_FILE}:{line}", "ABSENT", "",
                   "upstream serves this path; the port has no server, so no route answers it"))
      continue
    port_name = ALIAS.get(name, name)
    hit = port.get(port_name)
    if hit is None:
      state, note = "ABSENT", "no def of this name anywhere in the port tree"
    else:
      state = "PARTIAL" if name in PARTIAL else "PRESENT"
      note = PARTIAL.get(name, "")
    rows.append((name, f"{UPSTREAM_FILE}:{line}", state, f"{hit[0]}:{hit[1]}" if hit else "", note))
  write_pins(rows)
  print(f"--refresh: {PINS.name} rewritten -- {len(rows)} capabilities")
  return PASS


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))
