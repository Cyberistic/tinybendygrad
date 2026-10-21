#!/usr/bin/env python3
"""varsparams-gate.py -- ProgramInfo field names, port record against upstream class.

    .venv/bin/python gates/varsparams-gate.py
    .venv/bin/python gates/varsparams-gate.py --plant

THIS GATE MEASURES. It does not port, and it does not run bend.

THE PORT SIDE is `record_fields`: the `type ProgramInfo is Data` constructor,
brace-balanced, split on top-level commas. A count of the word `vars` is not a
field list. THE UPSTREAM SIDE is `ast` of `class ProgramInfo` in
`tinygrad/uop/ops.py`: AnnAssign and Assign names, not methods.

THE POPULATION is those field names except `vals`. `vals` is printed
`OWNED-BY valsdiv-gate` and is not a verdict of this gate. Every other port
field with no upstream counterpart, and every other upstream field with no
port counterpart, is a mismatch. FAIL while any remain. A missing file, a
missing class, or a missing record is REFUSED, not PASS.

If the only mismatch is port `vars` against upstream `params`, the finding
says so. Any other name is named. None is dropped.

`target` is not dropped. The comment block immediately before the record
says `target` is not ported. That block is prose, not an assignment, so the
mismatch row names `PROSE-UNPORTED` and the gate is still FAIL. Delete that
block and the row is a bare mismatch. `vars`/`params` has no such comment
and is not that class.

THE PLANT IS ON COPIES. A port record with `vars` and an upstream class with
`params` is FAIL. A copy whose preamble says `target` is not ported is FAIL,
and that row says `PROSE-UNPORTED`. The same copy with that comment deleted
is FAIL, and the row is a bare mismatch. A copy whose record field was
renamed to `params`, with no other mismatch left, is PASS. Inserting `vals`
into upstream does not make a FAIL into a PASS and does not make an aligned
copy FAIL. The live files are hashed before and after.
"""
from __future__ import annotations

import ast
import hashlib
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED, verdict_of  # noqa: E402

UPSTREAM = ROOT / "tinygrad" / "uop" / "ops.py"
PORT = ROOT / "tinybendygrad"

# Reporting labels, not a field list. The population is whatever the two parses return.
OWNED = "vals"
PAIR_PORT = "vars"
PAIR_UPSTREAM = "params"
TARGET = "target"
CLASS_PROSE = "PROSE-UNPORTED"
# `` `target: Target` is NOT PORTED `` is the live sentence. A comment is not an assignment.
UNPORTED_CLAIM = re.compile(
  r"`target\s*:[^`]*`\s+is\s+NOT\s+PORTED\b"
  r"|\btarget\s+is\s+(?:NOT\s+PORTED|not\s+ported|unported)\b"
)
HEADER = re.compile(r"^type ProgramInfo is Data:", re.M)
CTOR = re.compile(r"\bProgramInfo\{")
NEXT_DECL = re.compile(r"\n(?=(?:type |def ))")
PAIRS = {"(": ")", "[": "]", "{": "}", "<": ">"}
CLOSERS = set(PAIRS.values())


def walk_bend(root: Path) -> list[Path]:
  """Every `.bend` file under `root`. A directory walk, not a glob."""
  found: list[Path] = []
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for filename in sorted(filenames):
      if filename.endswith(".bend"):
        found.append(Path(dirpath) / filename)
  return found


def blank_noncode(text: str) -> str:
  """Comments and string contents become spaces. Offsets stay valid."""
  chars = list(text)
  i, n = 0, len(chars)
  while i < n:
    c = chars[i]
    if c in "\"'":
      quote = c
      i += 1
      while i < n and chars[i] != "\n":
        if chars[i] == "\\" and i + 1 < n and chars[i + 1] != "\n":
          chars[i] = " "
          chars[i + 1] = " "
          i += 2
          continue
        if chars[i] == quote:
          i += 1
          break
        chars[i] = " "
        i += 1
      continue
    if c == "#":
      while i < n and chars[i] != "\n":
        chars[i] = " "
        i += 1
      continue
    i += 1
  return "".join(chars)


def line_of(text: str, offset: int) -> int:
  return text.count("\n", 0, offset) + 1


def rel(path: Path) -> str:
  try:
    return str(path.relative_to(ROOT))
  except ValueError:
    return str(path)


def joined(names: list[str]) -> str:
  return ", ".join(names) if names else "-"


def split_top(body: str) -> list[tuple[int, int]]:
  """Spans of top-level comma-separated parts. `<>` nests, so a type's comma is not a field."""
  spans: list[tuple[int, int]] = []
  start = 0
  stack: list[str] = []
  for i, ch in enumerate(body):
    if ch in PAIRS:
      stack.append(PAIRS[ch])
    elif ch in CLOSERS and stack and ch == stack[-1]:
      stack.pop()
    if ch == "," and not stack:
      spans.append((start, i))
      start = i + 1
  spans.append((start, len(body)))
  return [(a, b) for a, b in spans if body[a:b].strip()]


def constructor_interior(text: str) -> tuple[int, int, int]:
  """`(body_start, body_end, header_offset)` of the one `type ProgramInfo is Data` constructor.

  `body_end` is the index of the closing brace. Raises LookupError if the record is
  absent, repeated, or not a single brace-balanced constructor. Returns nothing for
  a file that simply does not declare the type -- the caller distinguishes absence.
  """
  code = blank_noncode(text)
  headers = list(HEADER.finditer(code))
  if len(headers) != 1:
    raise LookupError(f"expected one `type ProgramInfo is Data`, found {len(headers)}")
  header = headers[0]
  rest = code[header.end():]
  nxt = NEXT_DECL.search(rest)
  block_end = header.end() + nxt.start() if nxt else len(code)
  block = code[header.end():block_end]
  ctors = list(CTOR.finditer(block))
  if len(ctors) != 1:
    raise LookupError(f"expected one ProgramInfo constructor in the type block, found {len(ctors)}")
  open_at = header.end() + ctors[0].end() - 1
  depth = 0
  i = open_at
  while i < len(code):
    if code[i] == "{":
      depth += 1
    elif code[i] == "}":
      depth -= 1
      if depth == 0:
        return open_at + 1, i, header.start()
    i += 1
  raise LookupError("ProgramInfo constructor braces did not close")


def record_fields(text: str) -> list[str]:
  """Field names of the ProgramInfo record, in declaration order.

  Brace-balanced constructor, split on top-level commas. Not a count of the word `vars`.
  """
  start, end, _header = constructor_interior(text)
  names: list[str] = []
  for a, b in split_top(text[start:end]):
    part = text[start + a:start + b]
    match = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", part)
    if match is None:
      raise LookupError(f"record field has no `name:` type: {part.strip()!r}")
    names.append(match.group(1))
  if len(names) != len(set(names)):
    raise LookupError("ProgramInfo record repeats a field name")
  return names


def declares_record(text: str) -> bool:
  return bool(HEADER.search(blank_noncode(text)))


def preamble_span(text: str) -> tuple[int, int] | None:
  """Span of the comment block immediately before `type ProgramInfo is Data`.

  Blank lines between the block and the header are not included. None if the
  header is missing, repeated, or has no comment block in front of it.
  """
  code = blank_noncode(text)
  headers = list(HEADER.finditer(code))
  if len(headers) != 1:
    return None
  end = headers[0].start()
  while end > 0 and text[end - 1] in " \t\n":
    end -= 1
  if end == 0:
    return None
  line_start = text.rfind("\n", 0, end) + 1
  if not text[line_start:end].lstrip().startswith("#"):
    return None
  start = line_start
  while start > 0:
    prev_nl = text.rfind("\n", 0, start - 1)
    prev_start = 0 if prev_nl < 0 else prev_nl + 1
    if text[prev_start:start - 1].strip().startswith("#"):
      start = prev_start
      continue
    break
  return start, end


def target_class(text: str) -> str | None:
  """`PROSE-UNPORTED` when the record preamble says `target` is not ported.

  The preamble is a comment. A comment names a class; it does not remove the
  mismatch and it does not pass. No such comment means no class.
  """
  span = preamble_span(text)
  if span is None:
    return None
  if UNPORTED_CLAIM.search(text[span[0]:span[1]]) is None:
    return None
  return CLASS_PROSE


def without_preamble(text: str) -> str:
  span = preamble_span(text)
  if span is None:
    raise LookupError("record preamble has no comment")
  start, end = span
  return text[:start] + text[end:]


def mismatch_line(side: str, name: str, klass: str | None = None) -> str:
  row = f"varsparams-gate: mismatch: {side} {name}"
  if klass:
    return f"{row} {klass}"
  return row


def read_port(root: Path) -> tuple[list[str], Path, int, str]:
  """The one record under `root`, its path, the header line, and the file text."""
  if not root.is_dir():
    raise LookupError(f"port root absent: {root}")
  files = walk_bend(root)
  if not files:
    raise LookupError(f"no .bend file under {root}")
  hits: list[tuple[list[str], Path, int, str]] = []
  for path in files:
    try:
      text = path.read_text()
    except OSError as exc:
      raise LookupError(f"unreadable {path}: {exc}") from exc
    if not declares_record(text):
      continue
    names = record_fields(text)
    _start, _end, header_at = constructor_interior(text)
    hits.append((names, path, line_of(text, header_at), text))
  if len(hits) != 1:
    raise LookupError(f"expected one `type ProgramInfo is Data` under {root}, found {len(hits)}")
  return hits[0]


def class_fields(text: str, where: str) -> tuple[list[str], int]:
  """AnnAssign and Assign names of the top-level `class ProgramInfo`, plus its line.

  Methods are not fields. `ast`, not an import of the class, so a copy is readable.
  """
  try:
    tree = ast.parse(text)
  except SyntaxError as exc:
    raise LookupError(f"upstream does not parse: {where}: {exc}") from exc
  found = [node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "ProgramInfo"]
  if len(found) != 1:
    raise LookupError(f"expected one class ProgramInfo in {where}, found {len(found)}")
  names: list[str] = []
  for stmt in found[0].body:
    if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
      names.append(stmt.target.id)
    elif isinstance(stmt, ast.Assign):
      names.extend(item.id for item in stmt.targets if isinstance(item, ast.Name))
  if len(names) != len(set(names)):
    raise LookupError(f"class ProgramInfo repeats a field in {where}")
  return names, found[0].lineno


def upstream_fields(path: Path) -> tuple[list[str], int]:
  if not path.is_file():
    raise LookupError(f"upstream file absent: {path}")
  try:
    text = path.read_text()
  except OSError as exc:
    raise LookupError(f"unreadable {path}: {exc}") from exc
  return class_fields(text, str(path))


def population(port_names: list[str], up_names: list[str]) -> tuple[list[str], list[str]]:
  """Sided difference with `vals` removed. Order is declaration order. Nothing else is removed."""
  port_only = [name for name in port_names if name not in up_names and name != OWNED]
  up_only = [name for name in up_names if name not in port_names and name != OWNED]
  return port_only, up_only


def vals_where(port_names: list[str], up_names: list[str]) -> str:
  where = []
  if OWNED in port_names:
    where.append("port field")
  if OWNED in up_names:
    where.append("upstream field")
  if not where:
    return "OWNED-BY valsdiv-gate (not a field on either side; not re-verdicted)"
  return "OWNED-BY valsdiv-gate (" + ", ".join(where) + "; excluded from this verdict)"


def finding(port_only: list[str], up_only: list[str]) -> str:
  port_set, up_set = set(port_only), set(up_only)
  if not port_set and not up_set:
    return "aligned"
  if port_set == {PAIR_PORT} and up_set == {PAIR_UPSTREAM}:
    return "vars/params is the only mismatch"
  if PAIR_PORT in port_set and PAIR_UPSTREAM in up_set:
    extra = [name for name in port_only if name != PAIR_PORT]
    extra.extend(name for name in up_only if name != PAIR_UPSTREAM)
    return "vars/params is not the only mismatch; also: " + ", ".join(extra)
  return "other field mismatches"


def measure(upstream: Path, port_root: Path) -> tuple[int, list[str]]:
  """Verdict and the lines that justify it. Paths are arguments so a plant can point them at copies."""
  when = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
  lines = [f"varsparams-gate: when={when}"]
  if not upstream.is_file():
    lines.append(f"varsparams-gate: REFUSED -- upstream file absent: {upstream}")
    return REFUSED, lines
  if not port_root.is_dir():
    lines.append(f"varsparams-gate: REFUSED -- port root absent: {port_root}")
    return REFUSED, lines
  try:
    port_names, port_path, port_line, port_text = read_port(port_root)
    up_names, up_line = upstream_fields(upstream)
  except LookupError as exc:
    lines.append(f"varsparams-gate: REFUSED -- {exc}")
    return REFUSED, lines
  klass = target_class(port_text)
  lines.append("varsparams-gate: port-parse: record_fields")
  lines.append(f"varsparams-gate: port-record: {rel(port_path)}:{port_line}")
  lines.append(f"varsparams-gate: port-fields: {joined(port_names)}")
  lines.append("varsparams-gate: upstream-parse: ast")
  lines.append(f"varsparams-gate: upstream-class: {rel(upstream)}:{up_line}")
  lines.append(f"varsparams-gate: upstream-fields: {joined(up_names)}")
  lines.append(f"varsparams-gate: vals: {vals_where(port_names, up_names)}")
  port_only, up_only = population(port_names, up_names)
  lines.append(f"varsparams-gate: port-only: {joined(port_only)}")
  lines.append(f"varsparams-gate: upstream-only: {joined(up_only)}")
  diff = sorted([*port_only, *up_only])
  lines.append(f"varsparams-gate: symmetric-difference: {joined(diff)}")
  lines.append(f"varsparams-gate: finding: {finding(port_only, up_only)}")
  for name in port_only:
    lines.append(mismatch_line("port-only", name))
  for name in up_only:
    lines.append(mismatch_line("upstream-only", name, klass if name == TARGET else None))
  n = len(port_only) + len(up_only)
  if n:
    why = "1 field mismatch" if n == 1 else f"{n} field mismatches"
    lines.append(f"varsparams-gate: {verdict_of(FAIL)} -- {why}")
    return FAIL, lines
  lines.append(f"varsparams-gate: {verdict_of(PASS)} -- no field mismatch in this gate's population")
  return PASS, lines


def rename_record_field(text: str, old: str, new: str) -> str:
  """Rename one field inside the constructor. A `def ProgramInfo.vars` outside it is left alone."""
  start, end, _header = constructor_interior(text)
  interior = text[start:end]
  names = record_fields(text)
  if old not in names:
    raise LookupError(f"{old} is not a record field")
  replaced, count = re.subn(rf"\b{re.escape(old)}\b(?=\s*:)", new, interior, count=1)
  if count != 1:
    raise LookupError(f"rename of {old} did not hit exactly one field")
  out = text[:start] + replaced + text[end:]
  got = record_fields(out)
  if old in got or new not in got:
    raise LookupError(f"rename of {old} to {new} did not land in the record")
  return out


def add_record_field(text: str, name: str) -> str:
  """Append one `name: String` field before the constructor's closing brace."""
  _start, end, _header = constructor_interior(text)
  if name in record_fields(text):
    return text
  return text[:end] + f", {name}: String" + text[end:]


def insert_upstream_vals(text: str) -> str:
  """Insert a `vals` field and a `vals` method into `class ProgramInfo`. Neither is this gate's verdict."""
  tree = ast.parse(text)
  found = [node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "ProgramInfo"]
  if len(found) != 1:
    raise LookupError("class ProgramInfo not unique in the upstream copy")
  lines = text.splitlines(keepends=True)
  at = found[0].lineno
  lines.insert(at, "  def vals(self):\n    return ()\n")
  lines.insert(at, "  vals: tuple = ()\n")
  out = "".join(lines)
  names, _line = class_fields(out, "upstream copy")
  if OWNED not in names:
    raise LookupError("inserted vals is not an upstream field")
  return out


def digest(paths: list[Path]) -> dict[str, str]:
  return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def put_port(directory: Path, text: str) -> Path:
  directory.mkdir(parents=True)
  (directory / "ops.bend").write_text(text)
  return directory


def row_value(rows: list[str], key: str) -> str:
  prefix = f"varsparams-gate: {key}: "
  for row in rows:
    if row.startswith(prefix):
      return row[len(prefix):]
  raise LookupError(f"no {key} row")


def mismatch_names(rows: list[str]) -> list[str]:
  """Field name of each mismatch row. A class token after the name is not a field."""
  names = []
  prefix = "varsparams-gate: mismatch: "
  for row in rows:
    if row.startswith(prefix):
      parts = row[len(prefix):].split()
      if len(parts) < 2:
        raise LookupError(f"malformed mismatch row: {row}")
      names.append(parts[1])
  return names


def mismatch_rows(rows: list[str]) -> list[str]:
  return [row for row in rows if row.startswith("varsparams-gate: mismatch: ")]


def same_mismatches(bad: list[str], rows: list[str], want: list[str], label: str) -> None:
  got = mismatch_rows(rows)
  if got != want:
    bad.append(f"{label}: mismatches {got} != {want}")


def check(bad: list[str], code: int, rows: list[str], want: int, label: str) -> None:
  print("\n".join(rows))
  if code != want:
    bad.append(f"{label} was {verdict_of(code)}, wanted {verdict_of(want)}")


# A comment and a decoy def both say `vars`. Neither is a record field.
DECOY = "\n# vars: U32\ndef ProgramInfo.vars(x: ProgramInfo) -> U32:\n  0\n"
FAIL_PORT = (
  "# vars: U32\n"
  "type ProgramInfo is Data:\n"
  "  # vars: U32\n"
  "  ProgramInfo{global_size: U32, local_size: U32, vars: List<&2, U32>, globals: U32, outs: U32, ins: U32, target: U32}\n"
  + DECOY
)
FAIL_UP = (
  "class ProgramInfo:\n"
  "  global_size: tuple = ()\n"
  "  local_size: tuple = ()\n"
  "  params: tuple = ()\n"
  "  globals: tuple = ()\n"
  "  outs: tuple = ()\n"
  "  ins: tuple = ()\n"
  "  target: tuple = ()\n"
)
PASS_PORT = FAIL_PORT.replace("vars: List<&2, U32>", "params: List<&2, U32>", 1)
EXTRA_UP = FAIL_UP.replace("  target: tuple = ()\n", "  target: tuple = ()\n  other: tuple = ()\n", 1)
MULTI_PORT = (
  "type ProgramInfo is Data:\n"
  "  ProgramInfo{\n"
  "    global_size: U32,\n"
  "    vars: U32,\n"
  "    target: U32\n"
  "  }\n"
)
MULTI_UP = (
  "class ProgramInfo:\n"
  "  global_size: tuple = ()\n"
  "  params: tuple = ()\n"
  "  target: tuple = ()\n"
)


def plant() -> int:
  """Copies only. A plant that cannot be made to move is FAIL, not a skipped check."""
  if not UPSTREAM.is_file() or not PORT.is_dir():
    print("varsparams-gate --plant: REFUSED -- live files are absent, so the plant measured nothing")
    return REFUSED
  live = [UPSTREAM, *walk_bend(PORT)]
  before = digest(live)
  bad: list[str] = []
  with tempfile.TemporaryDirectory(prefix="varsparams-plant-") as tmp:
    root = Path(tmp)
    try:
      run_plants(root, bad)
    except (OSError, LookupError, SyntaxError) as exc:
      bad.append(f"plant could not be built: {exc}")
  after = digest(live)
  moved = [path for path, old in before.items() if after.get(path) != old]
  if moved:
    bad.append(f"live files moved: {', '.join(moved)}")
  if bad:
    print(f"varsparams-gate --plant: {verdict_of(FAIL)} -- {'; '.join(bad)}")
    return FAIL
  print(f"varsparams-gate --plant: {verdict_of(PASS)} -- copies moved, live files did not")
  return PASS


def run_plants(root: Path, bad: list[str]) -> None:
  port_text = (PORT / "uop" / "ops.bend").read_text()
  up_text = UPSTREAM.read_text()
  witness = re.findall(
    r"\b([A-Za-z_][A-Za-z0-9_]*)\s*:",
    port_text.split("type ProgramInfo is Data:", 1)[1].split("\n", 2)[1],
  )
  if record_fields(port_text) != witness:
    bad.append(f"record_fields {record_fields(port_text)} != record-line witness {witness}")

  fail_port = put_port(root / "fail-port", FAIL_PORT)
  fail_up = root / "fail-up.py"
  fail_up.write_text(FAIL_UP)
  code, rows = measure(fail_up, fail_port)
  check(bad, code, rows, FAIL, "vars-vs-params copy")
  if row_value(rows, "finding") != "vars/params is the only mismatch":
    bad.append(f"vars-vs-params finding was {row_value(rows, 'finding')!r}")
  if row_value(rows, "port-only") != PAIR_PORT or row_value(rows, "upstream-only") != PAIR_UPSTREAM:
    bad.append("vars-vs-params sided difference was not exactly vars / params")
  if row_value(rows, "port-fields").count(PAIR_PORT) != 1:
    bad.append("comment and decoy def were counted as record fields")

  extra_up = root / "extra-up.py"
  extra_up.write_text(EXTRA_UP)
  code, rows = measure(extra_up, fail_port)
  check(bad, code, rows, FAIL, "extra-field copy")
  if row_value(rows, "finding") != "vars/params is not the only mismatch; also: other":
    bad.append(f"extra-field finding was {row_value(rows, 'finding')!r}")
  if "other" not in mismatch_names(rows):
    bad.append("extra field `other` was dropped")

  (root / "multi-up.py").write_text(MULTI_UP)
  code, rows = measure(root / "multi-up.py", put_port(root / "multi-port", MULTI_PORT))
  check(bad, code, rows, FAIL, "multiline vars-vs-params copy")
  if row_value(rows, "port-fields") != "global_size, vars, target":
    bad.append(f"multiline port-fields was {row_value(rows, 'port-fields')!r}")

  pass_port = put_port(root / "pass-port", PASS_PORT)
  code, rows = measure(fail_up, pass_port)
  check(bad, code, rows, PASS, "renamed-to-params copy")
  if PAIR_PORT in row_value(rows, "port-fields").split(", "):
    bad.append("renamed copy still reports vars as a record field")
  if "def ProgramInfo.vars" not in PASS_PORT:
    bad.append("renamed copy has no decoy def, so a word-count would not have been tested")
  if row_value(rows, "finding") != "aligned":
    bad.append(f"renamed finding was {row_value(rows, 'finding')!r}")

  vals_up = root / "vals-up.py"
  vals_up.write_text(insert_upstream_vals(FAIL_UP))
  code, rows = measure(vals_up, fail_port)
  check(bad, code, rows, FAIL, "vals inserted into a failing upstream")
  if "OWNED-BY valsdiv-gate" not in "\n".join(rows):
    bad.append("vals insertion was not printed OWNED-BY valsdiv-gate")
  if OWNED in mismatch_names(rows):
    bad.append("vals was verdicted as a mismatch of this gate")
  if code == PASS:
    bad.append("inserting vals made a failing copy PASS")

  aligned_vals = root / "aligned-vals-up.py"
  aligned_vals.write_text(insert_upstream_vals(FAIL_UP))
  code, rows = measure(aligned_vals, pass_port)
  check(bad, code, rows, PASS, "vals inserted into an aligned upstream")
  if OWNED in mismatch_names(rows):
    bad.append("vals on an aligned copy was a failure of this gate")
  if "OWNED-BY valsdiv-gate" not in "\n".join(rows):
    bad.append("aligned vals insertion was not printed OWNED-BY valsdiv-gate")
  if OWNED not in row_value(rows, "upstream-fields"):
    bad.append("inserted vals was not read as an upstream field")

  code, rows = measure(root / "missing.py", fail_port)
  check(bad, code, rows, REFUSED, "missing upstream")
  code, rows = measure(fail_up, root / "missing-port")
  check(bad, code, rows, REFUSED, "missing port root")
  code, rows = measure(fail_up, put_port(root / "no-record", "type Other is Data:\n  Other{a: U32}\n"))
  check(bad, code, rows, REFUSED, "port with no ProgramInfo record")
  (root / "noclass.py").write_text("x = 1\n")
  code, rows = measure(root / "noclass.py", fail_port)
  check(bad, code, rows, REFUSED, "upstream with no ProgramInfo class")

  if PAIR_PORT in record_fields(port_text):
    renamed = rename_record_field(port_text, PAIR_PORT, PAIR_UPSTREAM)
    up_names, _line = upstream_fields(UPSTREAM)
    for name in up_names:
      if name != OWNED and name not in record_fields(renamed):
        renamed = add_record_field(renamed, name)
    renamed += DECOY
    if "def ProgramInfo.vars" not in renamed:
      bad.append("live-record rename lost the decoy that proves this is not a word count")
    live_port = put_port(root / "live-aligned", renamed)
    live_up = root / "live-up.py"
    live_up.write_text(up_text)
    code, rows = measure(live_up, live_port)
    check(bad, code, rows, PASS, "live record renamed to params with no other mismatch")
    if PAIR_PORT in row_value(rows, "port-fields"):
      bad.append("live-record rename still reports vars")
    if CLASS_PROSE in "\n".join(rows):
      bad.append("aligned copy named PROSE-UNPORTED though target is present")
  else:
    print("varsparams-gate --plant: live record has no vars field; aligned live copy was not built")

  plant_prose(root, bad, port_text, up_text)


def plant_prose(root: Path, bad: list[str], port_text: str, up_text: str) -> None:
  """Copies of the live record. The comment names a class; it does not pass."""
  if target_class(port_text) != CLASS_PROSE:
    bad.append("live preamble is not PROSE-UNPORTED, so the class plant measured nothing")
    return
  prose_up = root / "prose-up.py"
  prose_up.write_text(up_text)
  prose_port = put_port(root / "prose-port", port_text)
  three = [
    mismatch_line("port-only", PAIR_PORT),
    mismatch_line("upstream-only", PAIR_UPSTREAM),
    mismatch_line("upstream-only", TARGET, CLASS_PROSE),
  ]
  bare_three = [
    mismatch_line("port-only", PAIR_PORT),
    mismatch_line("upstream-only", PAIR_UPSTREAM),
    mismatch_line("upstream-only", TARGET),
  ]
  code, rows = measure(prose_up, prose_port)
  check(bad, code, rows, FAIL, "preamble says target is unported")
  same_mismatches(bad, rows, three, "preamble")

  stripped = without_preamble(port_text)
  if "type ProgramInfo is Data:" not in stripped:
    bad.append("comment deletion removed the record")
    return
  if "`Target` in `ProgramInfo`" not in stripped:
    bad.append("comment deletion removed more than the preamble")
  if target_class(stripped) is not None:
    bad.append("deleting the preamble did not clear the class")
  code, rows = measure(prose_up, put_port(root / "bare-port", stripped))
  check(bad, code, rows, FAIL, "preamble comment deleted")
  same_mismatches(bad, rows, bare_three, "comment deleted")

  # vars renamed, target still absent: the comment must not turn this into PASS.
  only = rename_record_field(port_text, PAIR_PORT, PAIR_UPSTREAM)
  code, rows = measure(prose_up, put_port(root / "only-port", only))
  check(bad, code, rows, FAIL, "only mismatch is prose-unported target")
  same_mismatches(bad, rows, [mismatch_line("upstream-only", TARGET, CLASS_PROSE)], "only-target")

  code, rows = measure(prose_up, put_port(root / "only-bare", without_preamble(only)))
  check(bad, code, rows, FAIL, "only-target comment deleted")
  same_mismatches(bad, rows, [mismatch_line("upstream-only", TARGET)], "only-target bare")

  vals_up = root / "vals-prose-up.py"
  vals_up.write_text(insert_upstream_vals(up_text))
  code, rows = measure(vals_up, prose_port)
  check(bad, code, rows, FAIL, "vals inserted beside prose-unported target")
  same_mismatches(bad, rows, three, "vals beside prose")
  if OWNED in mismatch_names(rows):
    bad.append("vals was verdicted beside the prose class")


def main(argv: list[str] | None = None) -> int:
  args = sys.argv[1:] if argv is None else argv
  if "--plant" in args:
    planted = plant()
    print("--- live ---")
    code, rows = measure(UPSTREAM, PORT)
    print("\n".join(rows))
    if planted != PASS:
      return planted
    return code
  code, rows = measure(UPSTREAM, PORT)
  print("\n".join(rows))
  return code


if __name__ == "__main__":
  sys.exit(main())
