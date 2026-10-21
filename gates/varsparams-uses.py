#!/usr/bin/env python3
"""varsparams-uses.py -- the use-site census behind the `vars`/`params` rename.

    .venv/bin/python gates/varsparams-uses.py            # print the census
    .venv/bin/python gates/varsparams-uses.py --write    # rewrite gates/varsparams-uses.rows

WHAT THIS IS FOR. `gates/varsparams-gate.py` compares the port's `ProgramInfo` record
against upstream's `class ProgramInfo` and names three differences. It says WHICH NAMES
differ. It cannot say WHERE a name is used, and so it cannot tell a RENAME (one field,
two spellings) from a MISSING FIELD (a field with no counterpart at all). This file
answers that, and its rows are the evidence for the edit.

THE POPULATION IS DISCOVERED, TWICE, AND NEITHER DISCOVERY IS A LIST.
  the port's record   the ONE `type ProgramInfo is Data` under `tinybendygrad/`, found by
                      `os.walk` + `endswith(".bend")` -- never `glob`
  upstream's class    the ONE top-level `class ProgramInfo` under `tinygrad/`, found by
                      walking `tinygrad/**/*.py` and reading each with `ast`
Both are COUNTED, and the count is printed: a population of one that turned out to be two
must not be reported as one.

THE RECORD PARSER IS THE GATE'S, LOADED BY PATH. `gates/varsparams-gate.py` cannot be
imported by name -- the hyphen -- so it is loaded with `importlib` from `HERE`, the same
shape `gates/gates-pop.py` uses for `gates/gendirs.py`. **A SECOND COPY OF THE RECORD
PARSER IS A SECOND COPY OF THE POPULATION**, and this census would then be able to
disagree with the gate it is evidence for.

THE PAIRING IS BY POSITION, NOT BY NAME. Both records declare their fields in the same
order, so the third field on each side is the same field whatever it is called. That is
what makes `vars` and `params` a rename rather than two unrelated names, and it is a
mechanical fact rather than a reading of a diff. The TYPES are carried on the row so a
reader can judge the pairing and not take it on trust.
"""
from __future__ import annotations

import ast
import importlib.util
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

PORT_ROOT = ROOT / "tinybendygrad"
UPSTREAM_ROOT = ROOT / "tinygrad"
OUT = HERE / "varsparams-uses.rows"

PORT_FIELD = "vars"
UPSTREAM_FIELD = "params"
#: The upstream file is DISCOVERED, so this is a cross-check and not the input.
EXPECTED_UPSTREAM = "tinygrad/uop/ops.py"
#: `type X is Data:` / `type X is Type:` -- the port's record names, DISCOVERED.
RECORD_DECL = re.compile(r"^type\s+([A-Za-z_][A-Za-z0-9_]*)\s+is\s+(?:Data|Type)\b", re.M)
#: A record name in a RECORD POSITION: `case X{`, `X{...}`, `def X.`.
RECORD_USE = re.compile(r"\b(?:case\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\{|\bdef\s+([A-Za-z_][A-Za-z0-9_]*)\.")


def load_gate():
  """`gates/varsparams-gate.py` by path. Its parser, not a second one."""
  path = HERE / "varsparams-gate.py"
  spec = importlib.util.spec_from_file_location("varsparams_gate", path)
  if spec is None or spec.loader is None:
    raise LookupError(f"cannot load {path}")
  mod = importlib.util.module_from_spec(spec)
  sys.modules[spec.name] = mod
  spec.loader.exec_module(mod)
  return mod


VP = load_gate()


def walk_py(root: Path) -> list[Path]:
  """Every `.py` file under `root`. A directory walk, not a glob."""
  found: list[Path] = []
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for filename in sorted(filenames):
      if filename.endswith(".py"):
        found.append(Path(dirpath) / filename)
  return found


def upstream_class(root: Path) -> tuple[Path, list[str], int, int]:
  """The one file with a top-level `class ProgramInfo`, its fields, its line, and the count.

  The count is of FILES that declare the class, because a class declared twice is a
  different question from a class declared once.
  """
  hits: list[tuple[Path, list[str], int]] = []
  for path in walk_py(root):
    try:
      text = path.read_text()
    except OSError:
      continue
    if "class ProgramInfo" not in text:
      continue
    try:
      names, line = VP.class_fields(text, str(path))
    except LookupError:
      continue
    hits.append((path, names, line))
  if len(hits) != 1:
    raise LookupError(f"expected one `class ProgramInfo` under {root}, found {len(hits)}")
  path, names, line = hits[0]
  return path, names, line, len(hits)


def port_record(root: Path) -> tuple[Path, list[str], int]:
  """The one `type ProgramInfo is Data` under `root`, its fields, and the header's line."""
  hits: list[tuple[Path, list[str], int]] = []
  for path in VP.walk_bend(root):
    text = path.read_text()
    if not VP.declares_record(text):
      continue
    names = VP.record_fields(text)
    _start, _end, header_at = VP.constructor_interior(text)
    hits.append((path, names, VP.line_of(text, header_at)))
  if len(hits) != 1:
    raise LookupError(f"expected one `type ProgramInfo is Data` under {root}, found {len(hits)}")
  return hits[0]


def field_types_port(text: str) -> dict[str, str]:
  """`{field: type}` of the port's record, from the constructor's own text."""
  start, end, _header = VP.constructor_interior(text)
  out: dict[str, str] = {}
  for a, b in VP.split_top(text[start:end]):
    part = text[start + a:start + b]
    match = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)", part)
    if match is not None:
      out[match.group(1)] = match.group(2).strip()
  return out


def field_types_upstream(tree: ast.Module, cls: ast.ClassDef) -> dict[str, str]:
  """`{field: annotation}` of upstream's class, from the AST."""
  out: dict[str, str] = {}
  for stmt in cls.body:
    if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
      out[stmt.target.id] = ast.unparse(stmt.annotation)
    elif isinstance(stmt, ast.Assign):
      for item in stmt.targets:
        if isinstance(item, ast.Name) and stmt.value is not None:
          out[item.id] = ast.unparse(stmt.value)
  return out


def record_names(root: Path) -> set[str]:
  """Every `type X is Data:` / `type X is Type:` name under `root`, DISCOVERED.

  A name is a record's name because the tree says so, not because a line that mentions
  `vars` happens to contain it. `InInfo` is in this set and `q` is not, which is what
  separates `engine/jit.bend`'s `InInfo.vars` from `runtime/ops_metal.bend`'s local
  parameter named `vars`.
  """
  names: set[str] = set()
  for path in VP.walk_bend(root):
    names.update(RECORD_DECL.findall(path.read_text()))
  return names


def names_a_record(line: str, records: set[str]) -> bool:
  """Does this line name a DISCOVERED record other than `ProgramInfo`?"""
  for m in RECORD_USE.finditer(line):
    name = m.group(1) or m.group(2)
    if name and name != "ProgramInfo" and name in records:
      return True
  return False


def classify_port(line: str, in_constructor: bool, records: set[str]) -> str:
  """What a port line that mentions `vars` IS, by shape.

  The order IS the taxonomy: the first shape that matches wins, and each shape is
  checked against the line's own text rather than against a list of lines.
  """
  if line.lstrip().startswith("#"):
    return "comment"
  if in_constructor:
    return "field-decl"
  if re.search(r"\bdef\s+ProgramInfo\.vars\b", line):
    return "accessor-def"
  if re.search(r"\bProgramInfo\.vars\s*\(", line):
    return "accessor-call"
  if "ProgramInfo{" in line:
    return "pattern-bind" if "case " in line else "ctor-arg"
  if re.search(r'"[^"]*\bvars\b[^"]*"', line):
    return "string-label"
  if names_a_record(line, records):
    return "other-record"
  return "local"


def classify_upstream(line: str) -> str:
  """What an upstream line that mentions `params` IS, by shape."""
  if line.lstrip().startswith("#"):
    return "comment"
  if re.search(r"(?<![\w_])params\s*:", line):
    return "field-decl"
  if re.search(r"\bself\.arg\.params\b", line):
    return "attr-read"
  if re.search(r"\b_params\b", line):
    return "local"
  if re.search(r"\bkernel_params\b", line):
    return "other"
  return "other"


def census() -> list[str]:
  """The rows. One TAB-separated row per fact, with the line's own text last."""
  rows: list[str] = []
  ppath, pnames, pline = port_record(PORT_ROOT)
  upath, unames, uline, upcount = upstream_class(UPSTREAM_ROOT)
  ptypes = field_types_port(ppath.read_text())
  tree = ast.parse(upath.read_text())
  cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "ProgramInfo")
  utypes = field_types_upstream(tree, cls)

  rows.append(f"population\tport\t{ppath.relative_to(ROOT).as_posix()}\t{pline}\t{len(pnames)} fields")
  rows.append(f"population\tupstream\t{upath.relative_to(ROOT).as_posix()}\t{uline}\t{len(unames)} fields, {upcount} declaring file(s)")
  if upath.relative_to(ROOT).as_posix() != EXPECTED_UPSTREAM:
    rows.append(f"population-note\tupstream\t{upath.relative_to(ROOT).as_posix()}\t0\tdiscovered, NOT the path the gate names")

  for name in pnames:
    rows.append(f"port-field\t{ppath.relative_to(ROOT).as_posix()}\t{pline}\t{name}: {ptypes.get(name, '?')}")
  for name in unames:
    rows.append(f"upstream-field\t{upath.relative_to(ROOT).as_posix()}\t{uline}\t{name}: {utypes.get(name, '?')}")

  # THE PAIRING, BY POSITION.
  for i in range(max(len(pnames), len(unames))):
    p = pnames[i] if i < len(pnames) else "-"
    u = unames[i] if i < len(unames) else "-"
    kind = "pair" if p != "-" and u != "-" else ("unpaired-port" if p != "-" else "unpaired-upstream")
    rows.append(f"{kind}\tposition {i}\t{p}\t{u}\t{ptypes.get(p, '-')} | {utypes.get(u, '-')}")

  # THE PORT'S USE SITES.
  ptext = ppath.read_text()
  pstart, pend, _header = VP.constructor_interior(ptext)
  records = record_names(PORT_ROOT)
  lines_of = ptext.splitlines()
  for path in VP.walk_bend(PORT_ROOT):
    text = path.read_text()
    for i, line in enumerate(text.splitlines(), 1):
      if not re.search(r"\bvars\b", line):
        continue
      in_ctor = path == ppath and pstart <= len("\n".join(lines_of[:i - 1])) + 1 <= pend
      kind = classify_port(line, in_ctor, records)
      rows.append(f"port-use\t{kind}\t{path.relative_to(ROOT).as_posix()}\t{i}\t{line.strip()}")

  # UPSTREAM'S USE SITES, in the DISCOVERED file. `_params` COUNTS: the underscore is the
  # local's spelling of the same name, and a census that dropped it would hide the
  # `from_sink` half of the rename.
  for i, line in enumerate(upath.read_text().splitlines(), 1):
    if not re.search(r"\b_?params\b", line):
      continue
    kind = classify_upstream(line)
    rows.append(f"upstream-use\t{kind}\t{upath.relative_to(ROOT).as_posix()}\t{i}\t{line.strip()}")
  return rows


HEADER = [
  "# varsparams-uses.rows -- GENERATED by `gates/varsparams-uses.py --write`. THE ONLY WRITER.",
  "# THE USE-SITE CENSUS for the port's `ProgramInfo.vars` and upstream's `ProgramInfo.params`.",
  "# TAB-separated: `kind`, then a locator, then the line's own text. A `pair` row is the",
  "# correspondence BY POSITION -- the third field on each side is the third field on each",
  "# side, whatever it is called. Re-derive with `.venv/bin/python gates/varsparams-uses.py`.",
]


def main(argv: list[str] | None = None) -> int:
  args = sys.argv[1:] if argv is None else argv
  rows = census()
  body = "\n".join(HEADER + rows) + "\n"
  if "--write" in args:
    OUT.write_text(body)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(rows)} rows)")
  else:
    print(body, end="")
  return 0


if __name__ == "__main__":
  sys.exit(main())
