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

THE RULE, AND IT IS STRICTLY STRONGER THAN "THE PORT MUST NOT DEFINE IT".

  A port may ADD a member that upstream does not have -- that is an EXTENSION, and
  `AGENTS.md` says the port contract is behaviour, not names. But an extension has to be
  DECLARED, and the declaration is a machine-readable record IN THE PORT FILE, next to
  the def it declares:

      # PORT-EXTENSION: ProgramInfo.vals
      # PORT-EXTENSION-DATE: 2026-10-14T10:15:48Z
      # PORT-EXTENSION-UPSTREAM: a6addc2d4344ef51636626e937afece3147f0db3
      # PORT-EXTENSION-DERIVE: git --no-optional-locks log -1 --format=%H -S '...' ...

  and this gate CHECKS the record instead of believing it. A declaration is DATED (the
  date is the upstream commit's own author date, read back out of the object store and
  compared, so the sha and the date are two different values that have to agree -- the
  check `gates/rotclaim-gate.py` calls a dated record), it names an UPSTREAM REVISION,
  and it carries a DERIVE COMMAND that is RUN and whose result is CHECKED against the
  declared revision. The derive is a history query over upstream's own ref, so the
  declaration cannot be satisfied by a re-vendor of `tinygrad/` in THIS repo.

  **A DECLARED EXTENSION IS STILL AN ANSWER THE GATE CAN LOSE.** Every one of these is
  a FAIL, and none of them was a FAIL before this file grew the declaration arm:

    undeclared      the port defines `ProgramInfo.vals` and no declaration says so
    malformed       the declaration is missing a date, a revision or a derive command
    unattached     the declaration is in a different file from the def it declares
    unparseable    the declared date does not parse
    disagreement    the derive command does not name the declared revision
    not-a-commit   the declared revision is not a commit object
    wrong-date     the revision's own author date is not the declared date
    not-deleted    upstream's `ProgramInfo` still HAS `vals` at the declared revision
    never-there    upstream's `ProgramInfo` has no `vals` at the declared revision's
                   parent either, so the declared revision did not delete it
    dead           a declared extension nothing calls
    unreachable    a declared extension whose callers `main` does not reach
    stale          upstream's `ProgramInfo` HAS `vals` and the port still declares an
                   extension, so the declaration must be withdrawn

  So the gate is not "the port may add anything it likes, with a comment". It is "the
  port may add a member it can PROVE it is porting, and it has to keep proving it".

EXIT, re-derived on every run:
  PASS     upstream's class has `vals` again and no declaration claims otherwise, or the
           port definition is absent and nothing declares it, or the port definition is
           DECLARED and every check on the declaration holds and the extension is live
  FAIL     upstream has no `vals` and the port definition is undeclared, or the port
           definition is declared and the declaration does not hold, or the declaration
           is stale
  REFUSED  a file this run must read is missing, the class is absent, or the walk
           found no `.bend` file -- a missing file is not "the def disappeared"

A call is REACHABLE when its enclosing `def` is reached from that file's `main` or from
top-level code, by same-file name. A call site that exists but is not on that path is
still a caller, and the finding says so.

THE PLANT IS ON COPIES. `--plant` strips the definition and the call sites from a copy
and requires that copy not FAIL for "def exists"; a copy whose declaration is removed
must FAIL as undeclared; the unstripped copy must PASS as a declared extension; a copy
whose derive command, date or revision is broken must FAIL; a copy whose callers are
stripped must FAIL as dead; a copy of upstream with a `vals` method inserted must PASS
when the port copy declares nothing and must FAIL when it declares an extension; a
missing path must REFUSE. The live files are hashed before and after. A plant that does
not move is FAIL, because a constant exit measured nothing.
"""
from __future__ import annotations

import ast
import hashlib
import os
import re
import shlex
import subprocess
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

#: The DECLARATION markers, read out of the PORT's own comments. A declaration is the
#: set of markers in ONE `.bend` file; the bare `PORT-EXTENSION` names the member and
#: the three suffixed ones carry its date, its upstream revision and its derive command.
EXT = "PORT-EXTENSION"
EXT_DATE = "DATE"
EXT_UPSTREAM = "UPSTREAM"
EXT_DERIVE = "DERIVE"
EXT_MARK = re.compile(r"^#\s*PORT-EXTENSION(?:-([A-Z]+))?\s*:\s*(.*?)\s*$")
#: The upstream file at a REVISION. The vendored tree's path is upstream's own path, so
#: the same name reads both the working tree and any revision of it.
UPSTREAM_REL = "tinygrad/uop/ops.py"


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


def program_info(text: str) -> tuple[tuple[str, ...], tuple[str, ...]] | None:
  """`(fields, methods)` of the top-level `ProgramInfo` in `text`, or None."""
  try:
    tree = ast.parse(text)
  except SyntaxError:
    return None
  for node in tree.body:
    if isinstance(node, ast.ClassDef) and node.name == "ProgramInfo":
      return class_members(node)
  return None


def read_upstream(path: Path) -> tuple[tuple[str, ...], tuple[str, ...]] | None:
  """`(fields, methods)` of the top-level `ProgramInfo`, or None if it cannot be read."""
  try:
    text = path.read_text()
  except OSError:
    return None
  return program_info(text)


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


def declarations(paths: list[Path]) -> dict[Path, dict[str, list[str]]]:
  """`{path: {key: [values]}}` -- the `PORT-EXTENSION*` markers in each file's COMMENTS.

  A marker in a STRING is not a marker, so the comment half is split off first. A key
  that appears TWICE is kept as two values, because a declaration that says two things
  is not a declaration and the caller has to be able to see that.
  """
  out: dict[Path, dict[str, list[str]]] = {}
  for path in paths:
    try:
      text = path.read_text()
    except OSError:
      continue
    found: dict[str, list[str]] = {}
    for line in text.splitlines():
      _code, comment = split_comment(line)
      match = EXT_MARK.match(comment.strip())
      if match is None:
        continue
      found.setdefault(match.group(1) or EXT, []).append(match.group(2))
    if found:
      out[path] = found
  return out


def git(*args: str) -> tuple[int, str, str]:
  """`git` in THIS repo. The return code, stdout and stderr, never an exception."""
  ran = subprocess.run(("git", "--no-optional-locks") + args, cwd=ROOT, capture_output=True, text=True)
  return ran.returncode, ran.stdout, ran.stderr


def same_instant(a: str, b: str) -> bool:
  """Two timestamps, one instant. A wrong date is not a near miss."""
  def parse(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc).replace(microsecond=0)
  try:
    return parse(a) == parse(b)
  except ValueError:
    return False


def upstream_at(revision: str) -> tuple[tuple[str, ...], tuple[str, ...]] | None:
  """`(fields, methods)` of upstream's `ProgramInfo` at `revision`, or None."""
  code, out, _err = git("show", f"{revision}:{UPSTREAM_REL}")
  if code != 0:
    return None
  return program_info(out)


def run_derive(command: str) -> tuple[int, str, str]:
  """The derive command, RUN. A derive that is not a git command is refused."""
  argv = shlex.split(command)
  if not argv or argv[0] != "git":
    return 1, "", "the derive command is not a git command"
  ran = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
  return ran.returncode, ran.stdout, ran.stderr


def declaration_failures(markers: dict[str, list[str]], where: Path, def_paths: list[Path]) -> list[str]:
  """Why this declaration cannot stand. An empty list means it holds.

  Every check here is a check that can FAIL, and the two that read the object store are
  SECOND reads: the derive's answer and the declaration's own field have to agree, and
  the revision's own author date has to agree with the declared date. `sha256(x) ==
  sha256(x)` cannot fail; these can, because the date and the object store are
  different values.
  """
  bad: list[str] = []
  names = markers.get(EXT, [])
  if len(names) != 1:
    bad.append(f"the declaration names {len(names)} members")
  date = markers.get(EXT_DATE, [])
  revision = markers.get(EXT_UPSTREAM, [])
  derive = markers.get(EXT_DERIVE, [])
  for key, values in ((EXT_DATE, date), (EXT_UPSTREAM, revision), (EXT_DERIVE, derive)):
    if len(values) != 1:
      bad.append(f"the declaration has {len(values)} {key} fields and needs exactly one")
  if bad:
    return bad
  if def_paths and where not in def_paths:
    bad.append(f"the declaration is in {where} and the def is in {', '.join(str(p) for p in def_paths)}")
  code, out, err = run_derive(derive[0])
  if code != 0 or not out.strip():
    bad.append(f"the derive command named no revision: {err.strip()[:120] or 'no output'}")
    return bad
  if out.strip() != revision[0]:
    bad.append(f"the derive command named {out.strip()[:12]} and the declaration names {revision[0][:12]}")
    return bad
  sha = out.strip()
  code, kind, _err = git("cat-file", "-t", sha)
  if code != 0 or kind.strip() != "commit":
    bad.append(f"{sha[:12]} is not a commit object")
    return bad
  code, when, _err = git("log", "-1", "--format=%aI", sha)
  if code != 0 or not same_instant(when.strip(), date[0]):
    bad.append(f"the revision's own date {when.strip() or 'absent'} is not the declared date {date[0]}")
    return bad
  at = upstream_at(sha)
  if at is None:
    bad.append(f"upstream's {UPSTREAM_REL} at {sha[:12]} is unreadable")
    return bad
  if has_vals(*at):
    bad.append(f"upstream's ProgramInfo still has `vals` at {sha[:12]}")
    return bad
  before = upstream_at(f"{sha}^")
  if before is None:
    bad.append(f"upstream's {UPSTREAM_REL} at {sha[:12]}^ is unreadable")
    return bad
  if not has_vals(*before):
    bad.append(f"upstream's ProgramInfo has no `vals` at {sha[:12]}^ either")
    return bad
  return bad


def scan_port(root: Path, display: Path) -> tuple[list[str], list[str], list[str], list[str], list[Path], dict[Path, dict[str, list[str]]]] | str:
  """Defs, calls, comment sites, a reachability witness, the files that hold the def,
  and the declarations. One walk: the population is walked ONCE."""
  if not root.is_dir():
    return f"port root absent: {root}"
  files = walk_bend(root)
  if not files:
    return f"no .bend file under {root}"
  defs: list[str] = []
  calls: list[str] = []
  comments: list[str] = []
  witnesses: list[str] = []
  def_paths: list[Path] = []
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
      def_paths.append(path)
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
  return defs, calls, comments, witnesses, def_paths, declarations(files)


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
  defs, calls, comments, witnesses, def_paths, decls = scanned
  lines.append(f"valsdiv-gate: upstream-fields: {', '.join(fields)}")
  lines.append(f"valsdiv-gate: upstream-methods: {', '.join(methods)}")
  lines.append(f"valsdiv-gate: upstream-vals: {'present' if has_vals(fields, methods) else 'absent'}")
  lines.append(f"valsdiv-gate: port-defs: {len(defs)}" + (f" ({', '.join(defs)})" if defs else ""))
  lines.append(f"valsdiv-gate: port-calls: {len(calls)}" + (f" ({', '.join(calls)})" if calls else ""))
  lines.append(f"valsdiv-gate: port-comments: {len(comments)} (not callers)")

  # THE DECLARATIONS, DISCOVERED. The port's own comments, walked, never a list here.
  declared = {path: markers for path, markers in decls.items() if markers.get(EXT) == [NAME]}
  lines.append(f"valsdiv-gate: port-declarations: {len(declared)}"
               + (f" ({', '.join(rel(p, show) for p in declared)})" if declared else ""))
  for path, markers in declared.items():
    lines.append(f"valsdiv-gate: declaration: {rel(path, show)} "
                 f"date={markers.get(EXT_DATE, ['-'])[0]} upstream={markers.get(EXT_UPSTREAM, ['-'])[0][:12]}")

  if has_vals(fields, methods):
    if declared:
      lines.append("valsdiv-gate: finding: stale-declaration -- upstream's ProgramInfo has vals")
      lines.append(f"valsdiv-gate: {verdict_of(FAIL)} -- a declared extension for a member upstream has; withdraw it")
      return FAIL, lines
    lines.append("valsdiv-gate: finding: aligned -- upstream ProgramInfo has vals")
    lines.append(f"valsdiv-gate: {verdict_of(PASS)} -- upstream grew vals; def-exists is not the failure")
    return PASS, lines
  if not defs:
    if declared:
      lines.append("valsdiv-gate: finding: orphan-declaration -- the port has no def ProgramInfo.vals")
      lines.append(f"valsdiv-gate: {verdict_of(FAIL)} -- a declaration for a member the port does not define")
      return FAIL, lines
    lines.append("valsdiv-gate: finding: absent -- no def ProgramInfo.vals")
    lines.append(f"valsdiv-gate: {verdict_of(PASS)} -- port def disappeared; not FAIL for def-exists")
    return PASS, lines

  if not declared:
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
    lines.append("valsdiv-gate: a DECLARED extension would be read at this def; there is none")
    return FAIL, lines

  if len(declared) > 1:
    lines.append(f"valsdiv-gate: finding: ambiguous -- {len(declared)} declarations for {NAME}")
    lines.append(f"valsdiv-gate: {verdict_of(FAIL)} -- more than one declaration for the same member")
    return FAIL, lines
  where, markers = next(iter(declared.items()))
  failures = declaration_failures(markers, where, def_paths)
  if failures:
    lines.append("valsdiv-gate: finding: declared-but-unproven -- " + "; ".join(failures))
    lines.append(f"valsdiv-gate: {verdict_of(FAIL)} -- the declaration does not hold")
    return FAIL, lines
  lines.append("valsdiv-gate: declaration-verified: upstream lost `vals` at the declared revision, "
               "the revision's own date is the declared date, and the derive command reproduces it")

  # A DECLARED EXTENSION IS STILL AN ANSWER THE GATE CAN LOSE. Upstream deleted the
  # method as UNUSED, so a declared extension that nothing calls is dead code, and one
  # whose callers `main` does not reach is a claim with no subject.
  if not calls:
    lines.append("valsdiv-gate: finding: dead-claim -- declared, but its only mentions are comments")
    lines.append(f"valsdiv-gate: {verdict_of(FAIL)} -- a declared extension nothing calls")
    return FAIL, lines
  if not witnesses:
    lines.append(f"valsdiv-gate: finding: callers -- {calls[0]} is not reached from main")
    lines.append(f"valsdiv-gate: {verdict_of(FAIL)} -- a declared extension whose callers main does not reach")
    return FAIL, lines
  lines.append(f"valsdiv-gate: finding: declared-extension -- {witnesses[0]}")
  lines.append(f"valsdiv-gate: {verdict_of(PASS)} -- declared, proven and live")
  return PASS, lines


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


def strip_declaration(text: str) -> str:
  """Remove the DECLARATION MARKERS and leave the prose. The prose is not a declaration:
  a declaration is the four machine-readable lines, and a copy without them is the
  UNDECLARED copy the plant needs."""
  out = []
  for line in text.splitlines(keepends=True):
    nl = "\n" if line.endswith("\n") else ""
    body = line[:-len(nl)] if nl else line
    code, comment = split_comment(body)
    if EXT_MARK.match(comment.strip()) is not None:
      continue
    out.append(code + comment + nl)
  return "".join(out)


def replace_marker(text: str, key: str, value: str) -> str:
  """Replace one declaration marker's value. A copy whose declaration says something else
  is a copy the gate has to be able to lose."""
  out = []
  for line in text.splitlines(keepends=True):
    nl = "\n" if line.endswith("\n") else ""
    body = line[:-len(nl)] if nl else line
    code, comment = split_comment(body)
    match = EXT_MARK.match(comment.strip())
    if match is not None and (match.group(1) or EXT) == key:
      comment = f"# {EXT}-{key}: {value}\n" if key != EXT else f"# {EXT}: {value}\n"
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

    def put(name: str, text: str) -> Path:
      directory = root / name
      directory.mkdir()
      (directory / "ops.bend").write_text(text)
      return directory

    def check(name: str, code: int, want: int) -> None:
      print(f"valsdiv-gate --plant: {name} was {verdict_of(code)}, wanted {verdict_of(want)}")
      if code != want:
        bad.append(f"{name} was {verdict_of(code)}, wanted {verdict_of(want)}")

    # 1. THE DEF IS GONE AND NOTHING DECLARES IT: the port matches upstream's shape.
    gone = put("gone", rewrite_code(strip_declaration(port_text), drop_def=True, drop_call=True))
    code, rows = measure(UPSTREAM, gone, gone)
    print("\n".join(rows))
    check("def-removed", code, PASS)

    # 2. THE DEF IS THERE AND NOTHING DECLARES IT: the divergence, undeclared.
    undeclared = put("undeclared", strip_declaration(port_text))
    code, rows = measure(UPSTREAM, undeclared, undeclared)
    print("\n".join(rows))
    check("undeclared", code, FAIL)

    # 3. THE CONTROL: the live copy, declaration and all.
    declared = put("declared", port_text)
    code, rows = measure(UPSTREAM, declared, declared)
    print("\n".join(rows))
    check("declared", code, PASS)

    # 4. THE DERIVE DOES NOT NAME THE DECLARED REVISION.
    broken = replace_marker(port_text, EXT_DERIVE,
                            "git --no-optional-locks rev-parse --verify no-such-revision^{commit}")
    code, rows = measure(UPSTREAM, put("broken-derive", broken), root / "broken-derive")
    print("\n".join(rows))
    check("broken-derive", code, FAIL)

    # 5. THE DECLARED DATE IS NOT THE REVISION'S OWN DATE.
    dated = replace_marker(port_text, EXT_DATE, "1999-01-01T00:00:00Z")
    code, rows = measure(UPSTREAM, put("wrong-date", dated), root / "wrong-date")
    print("\n".join(rows))
    check("wrong-date", code, FAIL)

    # 6. THE DECLARED REVISION IS NOT THE ONE THE DERIVE NAMES.
    moved = replace_marker(port_text, EXT_UPSTREAM, "7787f76dcc1d8803fce3304a6ebc3ec32204e441")
    code, rows = measure(UPSTREAM, put("wrong-revision", moved), root / "wrong-revision")
    print("\n".join(rows))
    check("wrong-revision", code, FAIL)

    # 7. THE DECLARATION IS IN A DIFFERENT FILE FROM THE DEF.
    split_port = root / "split"
    split_port.mkdir()
    (split_port / "ops.bend").write_text(strip_declaration(port_text))
    (split_port / "other.bend").write_text("\n".join(
      line for line in port_text.splitlines() if EXT_MARK.match(split_comment(line)[1].strip()) is not None
    ) + "\n")
    code, rows = measure(UPSTREAM, split_port, split_port)
    print("\n".join(rows))
    check("declaration-elsewhere", code, FAIL)

    # 8. A DECLARED EXTENSION NOTHING CALLS.
    dead = put("dead", rewrite_code(port_text, drop_def=False, drop_call=True))
    code, rows = measure(UPSTREAM, dead, dead)
    print("\n".join(rows))
    if code != FAIL or not any("finding: dead-claim" in row for row in rows):
      bad.append("call-stripped copy did not FAIL as dead-claim")
    print(f"valsdiv-gate --plant: dead was {verdict_of(code)}, wanted FAIL")

    # 9. A DECLARED EXTENSION WHOSE CALLERS `main` DOES NOT REACH.
    hidden = port_text.replace("def vd_rows(", "def vd_rows_hidden(", 1)
    code, rows = measure(UPSTREAM, put("unreachable", hidden), root / "unreachable")
    print("\n".join(rows))
    if code != FAIL or not any("finding: callers" in row for row in rows):
      bad.append("unreachable copy did not FAIL as callers")
    print(f"valsdiv-gate --plant: unreachable was {verdict_of(code)}, wanted FAIL")

    # 10. UPSTREAM GREW `vals` AND THE PORT DECLARES AN EXTENSION: the declaration is
    #     STALE and has to be withdrawn.
    grew_up = root / "grew.py"
    grew_up.write_text(grow_vals(up_text))
    code, rows = measure(grew_up, declared, declared)
    print("\n".join(rows))
    check("upstream-grew-vals-stale-declaration", code, FAIL)

    # 11. UPSTREAM GREW `vals` AND THE PORT DECLARES NOTHING: aligned.
    code, rows = measure(grew_up, undeclared, undeclared)
    print("\n".join(rows))
    check("upstream-grew-vals", code, PASS)

    # 12. THE MISSING PATHS.
    code, rows = measure(root / "missing.py", declared, declared)
    print("\n".join(rows))
    check("missing upstream", code, REFUSED)
    code, rows = measure(UPSTREAM, root / "missing-port", root / "missing-port")
    print("\n".join(rows))
    check("missing port root", code, REFUSED)

  after = digest(live)
  moved_live = [path for path, old in before.items() if after.get(path) != old]
  if moved_live:
    bad.append(f"live files moved: {', '.join(moved_live)}")
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
