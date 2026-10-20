#!/usr/bin/env python3
"""valsdiv-gate.py -- does the port still define `ProgramInfo.vals` after upstream deleted it?

    .venv/bin/python gates/valsdiv-gate.py
    .venv/bin/python gates/valsdiv-gate.py --plant

THIS GATE MEASURES. It does not port, and it does not run `bend`.

THE DIVERGENCE. Upstream's `ProgramInfo` is read from `tinygrad/uop/ops.py` with `ast`,
not from a list in this file. The port side is a walk of `tinybendygrad/` (`os.walk` +
`endswith(".bend")`, never `glob`). A `def ProgramInfo.vals` is a definition. A
`ProgramInfo.vals(` that is not that definition and not inside a `#` comment is a call
site. Comments are counted and are not callers.

TWO FINDINGS, ONE EXIT WHILE THE DIVERGENCE HOLDS. A definition with a call site is a
divergence. A definition whose only other mentions are comments is dead code that still
claims an upstream API. Both are FAIL. They are not the same finding, and this file
deletes neither.

EXIT, re-derived on every run:
  PASS     upstream's class has `vals` again, or the port definition is absent
  FAIL     upstream has no `vals` and the port definition exists
  REFUSED  a file this run must read is missing, the class is absent, or the walk
           found no `.bend` file -- a missing file is not "the def disappeared"

A call is REACHABLE when its enclosing `def` is reached from that file's `main` or from
top-level code, by same-file name. A call site that exists but is not on that path is
still a caller, and the finding says so.

THE PLANT IS ON COPIES. `--plant` strips the definition and the call sites from a copy
and requires that copy not FAIL for "def exists"; a copy that still has the definition
must FAIL; a copy of upstream with a `vals` method inserted must PASS; a missing path
must REFUSE. The live files are hashed before and after. A plant that does not move is
FAIL, because a constant exit measured nothing.
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
NAME = "ProgramInfo.vals"

DEF_RE = re.compile(r"^def\s+ProgramInfo\.vals\b", re.M)
CALL_RE = re.compile(r"(?<![\w.])ProgramInfo\.vals\s*\(")
FUNC_RE = re.compile(r"^def\s+([A-Za-z_][A-Za-z0-9_.]*)", re.M)
CALLEE_RE = re.compile(r"(?<![\w.])([A-Za-z_][A-Za-z0-9_.]*)\s*\(")
CLASS_RE = re.compile(r"^class ProgramInfo\b[^\n]*:", re.M)


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
  """Comments and string contents become spaces. Newlines stay, so offsets are lines."""
  chars = list(text)
  i, n = 0, len(chars)
  while i < n:
    c = chars[i]
    if c == '"':
      i += 1
      while i < n and chars[i] != "\n":
        if chars[i] == "\\" and i + 1 < n and chars[i + 1] != "\n":
          chars[i] = " "
          chars[i + 1] = " "
          i += 2
          continue
        if chars[i] == '"':
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


def split_comment(line: str) -> tuple[str, str]:
  """Code, then the `#` comment. A `#` inside a `"` string is not a comment."""
  i, n = 0, len(line)
  while i < n:
    c = line[i]
    if c == '"':
      i += 1
      while i < n and line[i] != "\n":
        if line[i] == "\\" and i + 1 < n:
          i += 2
          continue
        if line[i] == '"':
          i += 1
          break
        i += 1
      continue
    if c == "#":
      return line[:i], line[i:]
    i += 1
  return line, ""


def class_members(node: ast.ClassDef) -> tuple[tuple[str, ...], tuple[str, ...]]:
  fields: list[str] = []
  methods: list[str] = []
  for stmt in node.body:
    if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
      fields.append(stmt.target.id)
    elif isinstance(stmt, ast.Assign):
      fields.extend(t.id for t in stmt.targets if isinstance(t, ast.Name))
    elif isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
      methods.append(stmt.name)
  return tuple(fields), tuple(methods)


def read_upstream(path: Path) -> tuple[tuple[str, ...], tuple[str, ...]] | None:
  """`(fields, methods)` of the top-level `ProgramInfo`, or None if it cannot be read."""
  try:
    tree = ast.parse(path.read_text())
  except (OSError, SyntaxError):
    return None
  for node in tree.body:
    if isinstance(node, ast.ClassDef) and node.name == "ProgramInfo":
      return class_members(node)
  return None


def has_vals(fields: tuple[str, ...], methods: tuple[str, ...]) -> bool:
  return "vals" in fields or "vals" in methods


def rel(path: Path, root: Path) -> str:
  try:
    return str(path.relative_to(root))
  except ValueError:
    return str(path)


def comment_mentions(text: str) -> list[int]:
  lines = []
  for n, line in enumerate(text.splitlines(), 1):
    _code, comment = split_comment(line)
    if NAME in comment:
      lines.append(n)
  return lines


def function_spans(code: str) -> list[tuple[str, int, int]]:
  matches = list(FUNC_RE.finditer(code))
  spans = []
  for i, match in enumerate(matches):
    end = matches[i + 1].start() if i + 1 < len(matches) else len(code)
    spans.append((match.group(1), match.start(), end))
  return spans


def enclosing(spans: list[tuple[str, int, int]], offset: int) -> str:
  for func_name, start, end in spans:
    if start <= offset < end:
      return func_name
  return ""


def body_callees(span: str) -> set[str]:
  body = span.split("\n", 1)[1] if "\n" in span else ""
  return {m.group(1) for m in CALLEE_RE.finditer(body)}


def reach(code: str) -> tuple[set[str], dict[str, str | None]]:
  """Functions reached from `main` or from a call outside any `def`, same file."""
  spans = function_spans(code)
  by_name = {func_name: (start, end) for func_name, start, end in spans}
  parent: dict[str, str | None] = {}
  queue: list[str] = []
  for func_name in by_name:
    if func_name == "main":
      parent[func_name] = None
      queue.append(func_name)
  covered = []
  for func_name, start, end in spans:
    covered.append((start, end))
  for match in CALLEE_RE.finditer(code):
    if any(start <= match.start() < end for start, end in covered):
      continue
    callee = match.group(1)
    if callee in by_name and callee not in parent:
      parent[callee] = None
      queue.append(callee)
  while queue:
    func_name = queue.pop(0)
    start, end = by_name[func_name]
    for callee in body_callees(code[start:end]):
      if callee in by_name and callee not in parent:
        parent[callee] = func_name
        queue.append(callee)
  return set(parent), parent


def witness(parent: dict[str, str | None], func_name: str) -> str:
  chain: list[str] = []
  seen: set[str] = set()
  cur: str | None = func_name
  while cur is not None and cur not in seen:
    seen.add(cur)
    chain.append(cur)
    cur = parent.get(cur)
  chain.reverse()
  return " -> ".join([*chain, NAME])


def scan_port(root: Path, display: Path) -> tuple[list[str], list[str], list[str], list[str]] | str:
  """Defs, calls, comment sites, and a reachability witness. A string is a refusal."""
  if not root.is_dir():
    return f"port root absent: {root}"
  files = walk_bend(root)
  if not files:
    return f"no .bend file under {root}"
  defs: list[str] = []
  calls: list[str] = []
  comments: list[str] = []
  witnesses: list[str] = []
  for path in files:
    try:
      text = path.read_text()
    except OSError as exc:
      return f"unreadable {path}: {exc}"
    shown = rel(path, display)
    code = blank_noncode(text)
    def_spans = [(m.start(), m.end()) for m in DEF_RE.finditer(code)]
    spans = function_spans(code)
    reached, parent = reach(code)
    for match in DEF_RE.finditer(code):
      defs.append(f"{shown}:{line_of(code, match.start())}")
    for match in CALL_RE.finditer(code):
      if any(start <= match.start() < end for start, end in def_spans):
        continue
      site = f"{shown}:{line_of(code, match.start())}"
      calls.append(site)
      owner = enclosing(spans, match.start())
      if owner == "" or owner in reached:
        path_s = witness(parent, owner) if owner else NAME
        witnesses.append(f"{site} via {path_s}")
    for n in comment_mentions(text):
      comments.append(f"{shown}:{n}")
  return defs, calls, comments, witnesses


def digest(paths: list[Path]) -> dict[str, str]:
  out = {}
  for path in paths:
    out[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
  return out


def measure(upstream: Path, port_root: Path, display: Path | None = None) -> tuple[int, list[str]]:
  """The verdict and the lines that justify it. Paths are arguments so a plant can point
  them at copies. Nothing here is a constant answer."""
  show = display or port_root
  lines = [f"valsdiv-gate: when={datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}"]
  if not upstream.is_file():
    lines.append(f"valsdiv-gate: REFUSED -- upstream file absent: {upstream}")
    return REFUSED, lines
  if not port_root.is_dir():
    lines.append(f"valsdiv-gate: REFUSED -- port root absent: {port_root}")
    return REFUSED, lines
  info = read_upstream(upstream)
  if info is None:
    lines.append(f"valsdiv-gate: REFUSED -- ProgramInfo not readable in {upstream}")
    return REFUSED, lines
  fields, methods = info
  scanned = scan_port(port_root, show)
  if isinstance(scanned, str):
    lines.append(f"valsdiv-gate: REFUSED -- {scanned}")
    return REFUSED, lines
  defs, calls, comments, witnesses = scanned
  lines.append(f"valsdiv-gate: upstream-fields: {', '.join(fields)}")
  lines.append(f"valsdiv-gate: upstream-methods: {', '.join(methods)}")
  lines.append(f"valsdiv-gate: upstream-vals: {'present' if has_vals(fields, methods) else 'absent'}")
  lines.append(f"valsdiv-gate: port-defs: {len(defs)}" + (f" ({', '.join(defs)})" if defs else ""))
  lines.append(f"valsdiv-gate: port-calls: {len(calls)}" + (f" ({', '.join(calls)})" if calls else ""))
  lines.append(f"valsdiv-gate: port-comments: {len(comments)} (not callers)")
  if has_vals(fields, methods):
    lines.append("valsdiv-gate: finding: aligned -- upstream ProgramInfo has vals")
    lines.append(f"valsdiv-gate: {verdict_of(PASS)} -- upstream grew vals; def-exists is not the failure")
    return PASS, lines
  if not defs:
    lines.append("valsdiv-gate: finding: absent -- no def ProgramInfo.vals")
    lines.append(f"valsdiv-gate: {verdict_of(PASS)} -- port def disappeared; not FAIL for def-exists")
    return PASS, lines
  if witnesses:
    lines.append(f"valsdiv-gate: finding: reachable -- {witnesses[0]}")
    why = "divergence: port def is reachable from a live caller, upstream has no vals"
  elif calls:
    lines.append(f"valsdiv-gate: finding: callers -- {calls[0]} is not reached from main")
    why = "divergence: port def has a caller that main does not reach, upstream has no vals"
  else:
    lines.append("valsdiv-gate: finding: dead-claim -- def exists, callers are only comments")
    why = "dead code claiming an upstream API: port def exists, no call site, upstream has no vals"
  lines.append(f"valsdiv-gate: {verdict_of(FAIL)} -- {why}")
  return FAIL, lines


def rewrite_code(text: str, drop_def: bool, drop_call: bool) -> str:
  """Rename `ProgramInfo.vals` in code only. Comments stay, so a comment cannot become a caller
  and cannot hide one."""
  out = []
  for line in text.splitlines(keepends=True):
    nl = "\n" if line.endswith("\n") else ""
    body = line[:-len(nl)] if nl else line
    code, comment = split_comment(body)
    is_def = bool(re.search(r"\bdef\s+ProgramInfo\.vals\b", code))
    if drop_def and is_def:
      code = re.sub(r"\bdef\s+ProgramInfo\.vals\b", "def ProgramInfo.gone", code)
    if drop_call and not is_def:
      code = re.sub(r"(?<![\w.])ProgramInfo\.vals\b", "ProgramInfo.gone", code)
    out.append(code + comment + nl)
  return "".join(out)


def ensure_def(text: str) -> str:
  if DEF_RE.search(blank_noncode(text)):
    return text
  return text + "\ndef ProgramInfo.vals(+ar: Arena, v: VarVals, x: ProgramInfo) -> Maybe<&2, List<&2, H.I64>>:\n  Nil{}\n"


def grow_vals(text: str) -> str:
  match = CLASS_RE.search(text)
  if match is None:
    raise LookupError("class ProgramInfo not in the upstream copy")
  nl = text.find("\n", match.end())
  if nl < 0:
    raise LookupError("class ProgramInfo has no body")
  method = "\n  def vals(self, var_vals):\n    return ()\n"
  return text[:nl] + method + text[nl:]


def plant() -> int:
  """Copies only. A plant that cannot be made to move is FAIL, not a skipped check."""
  if not UPSTREAM.is_file() or not PORT.is_dir():
    print("valsdiv-gate --plant: REFUSED -- live files are absent, so the plant measured nothing")
    return REFUSED
  live = [UPSTREAM, *walk_bend(PORT)]
  before = digest(live)
  bad: list[str] = []
  with tempfile.TemporaryDirectory(prefix="valsdiv-plant-") as tmp:
    root = Path(tmp)
    port_text = (PORT / "uop" / "ops.bend").read_text()
    up_text = UPSTREAM.read_text()

    gone = root / "gone"
    gone.mkdir()
    (gone / "ops.bend").write_text(rewrite_code(port_text, drop_def=True, drop_call=True))
    code, rows = measure(UPSTREAM, gone, gone)
    print("\n".join(rows))
    if code == FAIL:
      bad.append("def-removed copy FAILed for def-exists")

    still = root / "still"
    still.mkdir()
    (still / "ops.bend").write_text(ensure_def(port_text))
    code, rows = measure(UPSTREAM, still, still)
    print("\n".join(rows))
    if code != FAIL:
      bad.append(f"def-present copy was {verdict_of(code)}, wanted FAIL")

    dead = root / "dead"
    dead.mkdir()
    (dead / "ops.bend").write_text(rewrite_code(ensure_def(port_text), drop_def=False, drop_call=True))
    code, rows = measure(UPSTREAM, dead, dead)
    print("\n".join(rows))
    if code != FAIL or not any("finding: dead-claim" in row for row in rows):
      bad.append("call-stripped copy did not FAIL as dead-claim")

    grew_up = root / "grew.py"
    grew_up.write_text(grow_vals(up_text))
    code, rows = measure(grew_up, still, still)
    print("\n".join(rows))
    if code != PASS or not any("upstream-vals: present" in row for row in rows):
      bad.append("upstream-grew-vals copy did not PASS from the file")

    code, rows = measure(root / "missing.py", still, still)
    print("\n".join(rows))
    if code != REFUSED:
      bad.append(f"missing upstream was {verdict_of(code)}, wanted REFUSED")

    code, rows = measure(UPSTREAM, root / "missing-port", root / "missing-port")
    print("\n".join(rows))
    if code != REFUSED:
      bad.append(f"missing port root was {verdict_of(code)}, wanted REFUSED")

  after = digest(live)
  moved = [path for path, old in before.items() if after.get(path) != old]
  if moved:
    bad.append(f"live files moved: {', '.join(moved)}")
  if bad:
    print(f"valsdiv-gate --plant: {verdict_of(FAIL)} -- {'; '.join(bad)}")
    return FAIL
  print(f"valsdiv-gate --plant: {verdict_of(PASS)} -- copies moved, live files did not")
  return PASS


def main(argv: list[str] | None = None) -> int:
  args = sys.argv[1:] if argv is None else argv
  if "--plant" in args:
    planted = plant()
    print("--- live ---")
    code, rows = measure(UPSTREAM, PORT, ROOT)
    print("\n".join(rows))
    if planted != PASS:
      return FAIL if planted == FAIL else planted
    return code
  code, rows = measure(UPSTREAM, PORT, ROOT)
  print("\n".join(rows))
  return code


if __name__ == "__main__":
  sys.exit(main())
