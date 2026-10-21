#!/usr/bin/env python3
"""shared-writable-gate.py -- NAME THE SHARED WRITABLE PATHS AND THEIR WRITERS, BY DISCOVERY.

    usage: .venv/bin/python checks/shared-writable-gate.py
           .venv/bin/python checks/shared-writable-gate.py --json
           .venv/bin/python checks/shared-writable-gate.py --plant

EXIT: 0 no tracked path has two writers  ·  1 a tracked path has two or more writers
(ONE PATH, TWO PRODUCERS, NO OWNER)  ·  3 REFUSED, not a verdict, the scan could not
read its own population.

WHAT THIS IS FOR.  `AGENTS.md` names the class: "A CLASS IS A SHARED WRITABLE PATH NAMED IN
AN INSTRUCTION, AND THE INDEX IS ONE INSTANCE."  A gate that writes its own output IN PLACE
is one instance of it -- the path is named in an instruction (the gate's own header), and
every unit that runs the gate writes the same bytes.  MEASURED on this tree, 2026-10-21:
`checks/rows/rows-<graph>-<side>.rows` has TWO writers (`checks/hermetic-census.py:134`
publishes it, `checks/census.py:277` caches it) and the two instruments disagree about
what the path even IS -- one calls it a PUBLISHED ARTIFACT, the other calls it a CACHE --
and NEITHER OWNS IT.  A third instrument, `checks/census.py:234`, writes an INDEX of it
(`checks/rows/keys.rows`), and the index is a THIRD writer of the same directory that
nobody refreshes when the first two move.  MEASURED: the index recorded 68 hashes, and
after one regeneration it matched HEAD's rows on 68 of 68 and the WORKTREE's rows on 0 of
68 -- an index that names an artifact it no longer describes.

WHY A GATE AND NOT A LIST.  The population is DISCOVERED, twice over, by two DIFFERENT
routes, and the two are reported against each other rather than one being trusted:

  POPULATION OF PATHS   `git ls-tree -r HEAD` -- THE TREE, never the index.  `git ls-files`
                        reads the INDEX, which on this tree holds `e69de29b` intent-to-add
                        placeholders for untracked files, so the index answers about the
                        index and moves with `GIT_INDEX_FILE`.
  POPULATION OF WRITERS `gates/gendirs.py`'s own source walk, IMPORTED BY PATH and not
                        re-implemented: a second scanner is a second opinion, and this tree
                        has already had one write-site figure rot through nine forms.
                        `gendirs.coverage()` supplies the DENOMINATOR, and it is printed.

WHY THIS FILE SCANS ITSELF RATHER THAN CALLING `gendirs.discovered()`.  MEASURED: that
function answers a DIFFERENT question -- "which DIRECTORY does this tree write into" -- and
it resolves the target by constant propagation, which cannot see the shape that matters
here.  `checks/hermetic-census.py:134` writes `(out / f"rows-{name}-{which}.rows")`: the
target is an f-string over two NAMES, so there is no constant to propagate, and
`gendirs._write_sites` returns an EMPTY target for it.  `checks/citation-gate.py:47` is
`os.path.join(ROOT, "checks/citation-gate.ledger.tsv")`: a CALL, so the same.  A scanner
that cannot resolve the shape cannot find the subject, and the subject is the whole
question.  SO THIS FILE TAKES THE OTHER ROUTE: it evaluates the PATH EXPRESSION'S OWN
STRUCTURE and matches the result against the tracked paths.  The two routes disagree --
that is the POINT, and `AGENTS.md` is explicit that two instruments derived from the same
table cannot audit that table, so this one is derived from a DIFFERENT one.

THE THREE SHAPES THIS FILE RESOLVES, and each of them was MEASURED against a real writer
before it was believed:
  (a) A DIRECTORY BASE, from the writer's OWN `__file__` chain
      (`Path(__file__).resolve().parent`, `.parents[N]`, and a NAME bound to either).
      MEASURED: matching a bare basename instead claimed 2442 tracked paths and called 122
      of them shared, most of them by writers that had nothing to do with them.
  (b) A TEMPLATE, e.g. f"rows-{name}-{which}.rows": each f-string HOLE becomes `[^/]+`,
      because a hole is one path SEGMENT.
  (c) AN ARGPARSE DEFAULT, e.g. `ap.add_argument("--out", default=str(HERE / "rows"))`.
      MEASURED: `checks/hermetic-census.py:169` names its published set through one, and
      that writer is ONE OF THE TWO that makes `checks/rows/rows-*.rows` shared.  A gate
      that cannot see one of its own subject's two writers is a printer.

THE COMPOSITION IS AT THE FILESYSTEM LEVEL, not at the string level, and this is the third
measured correction.  `ROOT / "checks/compile-census.rows"` is `checks/compile-census.rows`,
NOT `checks/checks/compile-census.rows`: the base is a DIRECTORY and the string is APPENDED
to it, and the base's own repo-relative prefix is NOT re-applied to the string.  Composing
the two as strings produced `checks/checks/...` and lost the writer.

THE REJECTION RULE, and it is the whole difference between a census and a printer.  A
pattern with NO resolved base is only a path if it NAMES one: its FIRST fragment must begin
with a literal, and its literal text must have a stem.  MEASURED: without this rule
`Path(td, f"{name}.py")` -- a plant writing into a TEMPORARY DIRECTORY -- produced the
pattern `[^/]+\\.py`, which matched every tracked `.py` in the tree and called 4167 of them
shared.  `[^/]+\\.py` IS NOT A PATH.  IT IS A SHAPE.

THE ADMITTED LIMITS, MEASURED NOT ASSUMED, and printed rather than absorbed:
  * A SUBPROCESS WRITE is invisible: the target is named on a command line, not by a write
    call.  `checks/compile-census.py:228` hands `bend -o` its output and
    `checks/abi_gate.py:616` does the same.  `gendirs.py` records this limit in its own
    header and this file does not pretend to have closed it.
  * A WRITE THROUGH A FILE OBJECT (`fh.write(...)` where `fh` came from an `open()`) names
    the path in the `open()`, and this file resolves the `open()` site.
  * THE SCAN IS A LOWER BOUND, and `gendirs.coverage()`'s denominator is printed next to
    the count so a narrowed population can never read as the whole one.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
HOLE = "\x00"          # the sentinel for one f-string hole: ONE path SEGMENT
CASTS = ("str", "fspath", "abspath", "realpath")
WRITE_METHODS = ("write_text", "write_bytes")


def _load_gendirs():
  """`gates/gendirs.py` BY PATH.  A gate that crashes where it should refuse cannot tell
  "the input is absent" from "I am broken"."""
  import importlib.util
  spec = importlib.util.spec_from_file_location("gendirs", ROOT / "gates" / "gendirs.py")
  mod = importlib.util.module_from_spec(spec)
  sys.modules["gendirs"] = mod
  spec.loader.exec_module(mod)
  return mod


def _base(node: ast.AST, writer: pathlib.Path, binds: dict[str, list[ast.AST]]) -> pathlib.Path | None:
  """The ABSOLUTE DIRECTORY a path expression is anchored at, or None.

  Only ONE family is resolved -- the writer's OWN `__file__` chain -- and it is resolved by
  EVALUATING it against the writer's real path.  A base that is not the writer's own tree
  (a config value, a command-line argument, an environment variable) resolves to None, and
  the site is then REJECTED rather than guessed at.  Guessing would be a claim without a
  measurement, and a guess here matched every file in the tree.
  """
  if isinstance(node, ast.Name):
    for cand in binds.get(node.id, []):
      b = _base(cand, writer, binds)
      if b is not None:
        return b
    return None
  if isinstance(node, ast.Subscript):
    # `X.parents[N]` IS A SUBSCRIPT, not an Attribute: `ast.parse("p.parents[1]")` is
    # Subscript(value=Attribute(value=Name('p'), attr='parents'), slice=Constant(1)).
    # MEASURED: with no Subscript branch, `checks/compile-census.py`'s
    # `ROOT = Path(__file__).resolve().parents[1]` resolved to NOTHING and that gate's one
    # writer of `checks/compile-census.rows` was invisible.
    val = node.value
    if isinstance(val, ast.Attribute) and val.attr == "parents":
      idx = node.slice
      if isinstance(idx, ast.Constant) and isinstance(idx.value, int):
        b = _base(val.value, writer, binds)
        return b.parents[idx.value] if b else None
    return None
  if isinstance(node, ast.Attribute):
    if node.attr == "parent":
      b = _base(node.value, writer, binds)
      return b.parent if b else None
    return None
  if isinstance(node, ast.Call):
    f = node.func
    name = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
    if name == "resolve" and not node.args:
      return _base(f.value, writer, binds)
    if name in ("Path", "PurePath") and node.args:
      arg = node.args[0]
      if isinstance(arg, ast.Name) and arg.id == "__file__":
        # THE FILE, not the directory: `Path(__file__).resolve().parent` is the DIRECTORY and
        # the `.parent` attribute is what says so.  MEASURED: returning the directory here
        # applied `.parent` TWICE, so `checks/hermetic-census.py`'s `HERE` resolved to the
        # REPO ROOT and its one writer of `checks/rows/rows-*.rows` was invisible.
        return writer.resolve()
    return None
  if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
    return _base(node.left, writer, binds)
  return None


def _eval(node: ast.AST, writer: pathlib.Path, binds: dict[str, list[ast.AST]],
          defaults: dict[str, ast.AST], namespaces: set[str],
          depth: int = 0) -> tuple[pathlib.Path | None, list[str]] | None:
  """`(base, frags)` for a path expression.  The fragments are joined with `/`.

  None means the expression names no path this file can follow.
  """
  if depth > 12:
    return None
  if isinstance(node, ast.Constant) and isinstance(node.value, str):
    return (None, [node.value])
  if isinstance(node, ast.JoinedStr):
    base: pathlib.Path | None = None
    frag = ""
    for v in node.values:
      if isinstance(v, ast.Constant) and isinstance(v.value, str):
        frag += v.value
      elif isinstance(v, ast.FormattedValue):
        # A formatted BASE is a base, not a hole: `{REPORTS_DIR}/{name}` names a DIRECTORY and
        # a file inside it, and calling it a hole made the pattern `[^/]+/[^/]+`, which matches
        # every two-segment path in the tree.
        ev = _eval(v.value, writer, binds, defaults, namespaces, depth + 1)
        if ev and ev[0] is not None:
          base = ev[0]
          frag += "/".join(ev[1])
        elif ev and ev[1]:
          frag += "/".join(ev[1])
        else:
          frag += HOLE
      else:
        return None
    # ONE fragment, not several: the literal parts of an f-string are CONCATENATED, and
    # joining them with `/` turned f"rows-{name}-{which}.rows" into the path
    # "rows/name/which.rows" -- a directory that does not exist.
    return (base, [frag])
  if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
    lb = _eval(node.left, writer, binds, defaults, namespaces, depth + 1)
    rb = _eval(node.right, writer, binds, defaults, namespaces, depth + 1)
    if not lb or not rb:
      return None
    base = lb[0] or rb[0]
    return (base, lb[1] + rb[1])
  if isinstance(node, ast.Call):
    f = node.func
    name = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
    if name in CASTS:
      # A CAST OF A PATH IS STILL A PATH.  `str(HERE / "rows")` is the default of
      # `checks/hermetic-census.py:169`'s `--out`, and skipping the cast lost the ONE writer
      # that makes `checks/rows/rows-*.rows` shared.
      return _eval(node.args[0], writer, binds, defaults, namespaces, depth + 1) if node.args else None
    if name in ("join", "Path", "PurePath"):
      base: pathlib.Path | None = None
      frags: list[str] = []
      for i, a in enumerate(node.args):
        ev = _eval(a, writer, binds, defaults, namespaces, depth + 1)
        if ev is None:
          continue
        b, fs = ev
        if name in ("Path", "PurePath") and i == 0:
          base = b if b is not None else base
          frags += fs
          continue
        if b is not None and base is None:
          base = b
        frags += fs
      return (base, frags) if frags else None
    return None
  if isinstance(node, ast.Name):
    for cand in binds.get(node.id, []):
      ev = _eval(cand, writer, binds, defaults, namespaces, depth + 1)
      if ev is not None:
        return ev
    return None
  if isinstance(node, ast.Subscript):
    b = _base(node, writer, binds)
    return (b, []) if b is not None else None
  if isinstance(node, ast.Attribute):
    b = _base(node, writer, binds)
    if b is not None:
      return (b, [])
    # AN ARGPARSE ATTRIBUTE: `a.out` where `a` is a parse_args() namespace.
    if isinstance(node.value, ast.Name) and node.value.id in namespaces:
      default = defaults.get(node.attr)
      if default is not None:
        return _eval(default, writer, binds, defaults, namespaces, depth + 1)
    return None
  return None


def _bindings(tree: ast.Module) -> dict[str, list[ast.AST]]:
  """`{name: [value-expression, ...]}` -- EVERY assignment to that name, not just the first.

  MEASURED WHY THE LIST AND NOT ONE VALUE.  `checks/bend-health.py` assigns `out` TWICE: at
  `:114` to `run([...]).stdout` (an unrelated use of the word) and at `:403` to
  `HERE / "bend-health.rows"` (the write target).  A binding table that keeps the FIRST
  assignment resolves `out` to a subprocess pipe and the gate never sees
  `checks/bend-health.rows` at all.  `checks/exitcode-census.py:425,427` is the same shape.
  So the table is a LIST and the resolver tries each candidate until one names a path.
  """
  out: dict[str, list[ast.AST]] = {}
  for n in ast.walk(tree):
    if isinstance(n, (ast.Assign, ast.AnnAssign)):
      targets = n.targets if isinstance(n, ast.Assign) else [n.target]
      if n.value is None:
        continue
      for t in targets:
        if isinstance(t, ast.Name):
          out.setdefault(t.id, []).append(n.value)
  return out


def _argparse(tree: ast.Module) -> tuple[dict[str, ast.AST], set[str]]:
  """`({dest: default-expression}, {names bound to a parse_args() namespace})`.

  The DEFAULT is used, never the parsed value: the default is what the code declares, and a
  command line is a run-time choice that this static scan does not make.
  """
  defaults: dict[str, ast.AST] = {}
  namespaces: set[str] = set()
  for n in ast.walk(tree):
    if not isinstance(n, ast.Call):
      continue
    f = n.func
    name = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
    if name == "add_argument":
      dest = None
      for kw in n.keywords:
        if kw.arg == "dest" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
          dest = kw.value.value
      if dest is None and n.args and isinstance(n.args[0], ast.Constant) \
         and isinstance(n.args[0].value, str):
        dest = n.args[0].value.lstrip("-").replace("-", "_")
      default = next((kw.value for kw in n.keywords if kw.arg == "default"), None)
      if dest and default is not None:
        defaults.setdefault(dest, default)
    elif name == "parse_args":
      for parent in ast.walk(tree):
        if isinstance(parent, ast.Assign) and parent.value is n:
          for t in parent.targets:
            if isinstance(t, ast.Name):
              namespaces.add(t.id)
  return defaults, namespaces


def _regex(base: pathlib.Path | None, frags: list[str], root: pathlib.Path) -> str | None:
  """The regex for one write site's target, or None when the site does not name a path."""
  if not frags:
    return None
  body = "/".join(re.escape(f).replace(re.escape(HOLE), "[^/]+") for f in frags)
  body = re.sub(r"/+", "/", body)
  if base is None:
    # No anchor: the FIRST fragment must begin with a literal, and there must be a stem.
    first = frags[0]
    if not first or HOLE in first[:1]:
      return None
    lit = "".join(f for f in frags if HOLE not in f)
    stem = re.sub(r"\.[A-Za-z0-9_+-]+$", "", lit)
    if not stem.strip(". "):
      return None
    return "(?:^|/)" + body
  try:
    rel = os.path.relpath(base, root)
  except ValueError:
    return None
  if rel.startswith(".."):
    return None
  if rel == ".":
    rel = ""
  # NO LEADING SLASH when the base IS the repo root: the tracked path is "checks/x.rows",
  # not "/checks/x.rows", and the leading slash matched nothing.  MEASURED: it hid
  # `checks/compile-census.rows` and `gates/edge-oracle-pin.rows` -- both real writers.
  return (re.escape(rel) + "/" if rel else "") + body


def _sites(path: pathlib.Path, root: pathlib.Path) -> tuple[list[tuple[int, str]], list[tuple[int, str]]]:
  """`[(line, pattern-regex)]` for the write sites of ONE source, and the UNRESOLVED ones."""
  try:
    src = path.read_text(errors="replace")
    tree = ast.parse(src)
  except (OSError, SyntaxError):
    return [], []
  binds = _bindings(tree)
  defaults, namespaces = _argparse(tree)
  found: list[tuple[int, str]] = []
  unresolved: list[tuple[int, str]] = []

  def add(node: ast.AST, line: int, shape: str) -> None:
    ev = _eval(node, path, binds, defaults, namespaces)
    rx = _regex(ev[0], ev[1], root) if ev else None
    if rx is None:
      unresolved.append((line, shape))
      return
    found.append((line, rx))

  # THE CALLS TO EACH FUNCTION, for the parameter-to-argument step below.
  calls_to: dict[str, list[ast.Call]] = {}
  for n in ast.walk(tree):
    if isinstance(n, ast.Call):
      f = n.func
      nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
      calls_to.setdefault(nm, []).append(n)

  def scan(fn: ast.AST, params: list[str]) -> None:
    """Scan ONE function body.  `params` are its positional parameter names."""
    for node in ast.walk(fn):
      if not isinstance(node, ast.Call):
        continue
      f = node.func
      nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
      target: ast.AST | None = None
      if nm in WRITE_METHODS and isinstance(f, ast.Attribute):
        target = f.value
      elif nm == "open" and len(node.args) >= 2:
        mode = node.args[1]
        if isinstance(mode, ast.Constant) and isinstance(mode.value, str) \
           and not ("w" in mode.value or "a" in mode.value):
          continue
        target = node.args[0]
      elif nm == "open" and isinstance(f, ast.Attribute):
        mode = node.args[0] if node.args else None
        if isinstance(mode, ast.Constant) and isinstance(mode.value, str) \
           and not ("w" in mode.value or "a" in mode.value):
          continue
        target = f.value
      if target is None:
        continue
      ev = _eval(target, path, binds, defaults, namespaces)
      if ev is not None:
        rx = _regex(ev[0], ev[1], root)
        if rx is not None:
          found.append((node.lineno, rx))
          continue
      # THE TARGET CAME IN AS A PARAMETER.  `gates/edge-fixture-census.py:836` writes
      # `dest.open("w")` where `dest` is a parameter of `write_rows(c, dest)`, and the CALLER
      # supplies it from `--rows` whose default is the module's `LEDGER` constant.  So the
      # parameter is bound to the ARGUMENT at the call site, and the argument is what names
      # the path.  MEASURED: without this step `gates/edge-fixture.rows` had NO writer at all.
      if isinstance(target, ast.Name) and target.id in params:
        idx = params.index(target.id)
        for call in calls_to.get(fn.__class__ and getattr(fn, "name", ""), []):
          if idx < len(call.args):
            ev2 = _eval(call.args[idx], path, binds, defaults, namespaces)
            rx2 = _regex(ev2[0], ev2[1], root) if ev2 else None
            if rx2 is not None:
              found.append((node.lineno, rx2))
              break
        else:
          unresolved.append((node.lineno, nm))
      else:
        unresolved.append((node.lineno, nm))

  # The MODULE's own statements, and then each FUNCTION's body: the module scan walks into
  # functions too, so a site inside one would be counted TWICE and the unresolved count would
  # be a count of scans rather than of sites.
  for stmt in tree.body:
    scan(stmt, [])
  for fn in ast.walk(tree):
    if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
      names = [a.arg for a in fn.args.posonlyargs] + [a.arg for a in fn.args.args]
      for stmt in fn.body:
        scan(stmt, names)
  return found, unresolved


def _tracked(root: pathlib.Path) -> dict[str, str]:
  """`{path: blob}` from HEAD's TREE.  `git ls-files` reads the INDEX; this reads the tree."""
  r = subprocess.run(["git", "ls-tree", "-r", "HEAD"], cwd=root, capture_output=True, text=True,
                     check=True)
  out: dict[str, str] = {}
  for ln in r.stdout.splitlines():
    meta, path = ln.split("\t", 1)
    mode, otype, oid = meta.split()
    if otype == "blob":
      out[path] = oid
  return out


def _blob_of(path: pathlib.Path) -> str | None:
  """The git blob id of a WORKTREE file, computed here so the INDEX is never consulted."""
  try:
    data = path.read_bytes()
  except OSError:
    return None
  h = hashlib.sha1()
  h.update(b"blob %d\0" % len(data))
  h.update(data)
  return h.hexdigest()


def census(root: pathlib.Path = ROOT) -> dict:
  # BOTH SIDES OF EVERY COMPARISON MUST BE RESOLVED, or the instrument answers about a
  # DIFFERENT POPULATION than the one it reports on.  MEASURED: on macOS a temporary
  # directory is `/var/folders/...` and `Path.resolve()` hands back `/private/var/folders/...`,
  # so the writer's resolved base was NOT under the unresolved root and EVERY plant was RED.
  # `gates/gendirs.py:385` records the same measurement for the same reason.
  root = pathlib.Path(root).resolve()
  gendirs = _load_gendirs()
  tracked = _tracked(root)
  sources = gendirs.sources(root)
  read, present = gendirs.coverage(root)

  writers: dict[str, set[tuple[str, int]]] = {}
  unresolved_total = 0
  for src in sources:
    rel = os.path.relpath(src, root)
    sites, unresolved = _sites(src, root)
    unresolved_total += len(unresolved)
    for line, pat in sites:
      rx = re.compile(pat + r"\Z")
      for tpath in tracked:
        if rx.search(tpath):
          writers.setdefault(tpath, set()).add((rel, line))

  rows = []
  for p in sorted(writers):
    ws = sorted(writers[p])
    wt = _blob_of(root / p)
    rows.append({
      "path": p,
      "writers": [{"file": f, "line": l} for f, l in ws],
      "n_writers": len({f for f, _ in ws}),
      "drifted_from_head": (wt is not None and wt != tracked[p]),
      "deleted": wt is None,
    })
  shared = [r for r in rows if r["n_writers"] >= 2]
  return {
    "root": str(root),
    "tracked_paths": len(tracked),
    "sources_scanned": len(sources),
    "sources_present": present,
    "sources_read": read,
    "unresolved_write_sites": unresolved_total,
    "write_targets": len(rows),
    "shared": shared,
    "rows": rows,
  }


def _print(report: dict) -> None:
  print(f"tracked paths (HEAD tree)   : {report['tracked_paths']}")
  print(f"sources scanned             : {report['sources_scanned']}"
        f"   (read {report['sources_read']} / present {report['sources_present']}"
        f" -- gendirs.coverage(), the DENOMINATOR)")
  print(f"unresolved write sites      : {report['unresolved_write_sites']}"
        f"   (named, not absorbed: a subprocess write and a name-built path are both invisible here)")
  print(f"tracked paths with a writer : {report['write_targets']}")
  print(f"SHARED (2+ writers)         : {len(report['shared'])}")
  print()
  for r in report["shared"]:
    flag = "DRIFTED-FROM-HEAD" if r["drifted_from_head"] else (
      "DELETED" if r["deleted"] else "matches-HEAD")
    print(f"  SHARED  {r['path']}   [{flag}]")
    for w in r["writers"]:
      print(f"            {w['file']}:{w['line']}")
  others = [r for r in report["rows"] if r["n_writers"] < 2]
  print(f"\nsingle-writer tracked write targets ({len(others)}):")
  for r in others:
    flag = "DRIFTED-FROM-HEAD" if r["drifted_from_head"] else (
      "DELETED" if r["deleted"] else "matches-HEAD")
    w = r["writers"][0]
    print(f"  {r['path']}   <- {w['file']}:{w['line']}   [{flag}]")


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--json", action="store_true", help="the census as JSON")
  ap.add_argument("--plant", action="store_true", help="plants on SYNTHETIC trees; never the live one")
  a = ap.parse_args()
  if a.plant:
    return _plants()
  try:
    report = census(ROOT)
  except FileNotFoundError as e:
    print(f"== REFUSED, NOT A VERDICT: {e}", file=sys.stderr)
    return 3
  if a.json:
    print(json.dumps(report, indent=2, sort_keys=True))
  else:
    _print(report)
  if report["shared"]:
    # The verdict goes to STDERR so `--json` emits parseable JSON on stdout and nothing else.
    print("RED: a tracked path has two or more writers.  ONE PATH, TWO PRODUCERS, NO OWNER.",
          file=sys.stderr)
    for r in report["shared"]:
      print(f"  {r['path']}  <- "
            + ", ".join(f"{w['file']}:{w['line']}" for w in r["writers"]), file=sys.stderr)
    return 1
  return 0


def _plant_tree(root: pathlib.Path, *files: tuple[str, str]) -> None:
  for rel, body in files:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)


def _plants() -> int:
  """PLANTS ON SYNTHETIC TREES.  The live tree is NEVER written by a plant."""
  import shutil
  import tempfile
  bad = 0
  with tempfile.TemporaryDirectory() as td:
    tmp = pathlib.Path(td) / "tree"
    (tmp / "checks").mkdir(parents=True)
    (tmp / "gates").mkdir(parents=True)
    shutil.copy(ROOT / "checks" / "shared-writable-gate.py",
                tmp / "checks" / "shared-writable-gate.py")
    _plant_tree(tmp,
                ("checks/w1.py", "from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
                                "(HERE / 'rows-a.rows').write_text('x')\n"),
                ("checks/w2.py", "from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
                                "(HERE / 'rows-a.rows').write_text('y')\n"),
                ("checks/w3.py", "from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
                                "(HERE / 'rows-a.rows').write_text('z')\n"),
                ("gates/w4.py", "from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
                                "(HERE / 'rows-a.rows').write_text('w')\n"),
                # THE TARGET MUST EXIST AND BE TRACKED: the gate's population is the TRACKED
                # paths, so a writer of a path nobody tracks is not a shared TRACKED path.
                ("checks/rows-a.rows", "a\n"),
                ("gates/rows-a.rows", "g\n"),
                ("checks/rows-1.rows", "b\n"))
    subprocess.run(["git", "init", "-q"], cwd=tmp, check=True)
    subprocess.run(["git", "add", "-A"], cwd=tmp, check=True)
    subprocess.run(["git", "-c", "user.email=a@b", "-c", "user.name=c", "commit", "-qm", "plant"],
                   cwd=tmp, check=True)
    r = census(tmp)
    hit = [x for x in r["rows"] if x["path"] == "checks/rows-a.rows"]
    if not hit or hit[0]["n_writers"] != 3:
      print(f"PLANT 1 RED: three writers on one path were NOT found ({hit})")
      bad += 1
    else:
      print("PLANT 1 OK: three writers on one path found")
    # PLANT 2: a writer in gates/ claims gates/rows-a.rows and NOT checks/rows-a.rows.
    gates_hit = [x for x in r["rows"] if x["path"] == "gates/rows-a.rows"]
    if not gates_hit or gates_hit[0]["n_writers"] != 1:
      print(f"PLANT 2 RED-BROKEN: a writer in gates/ did not claim exactly its own directory ({gates_hit})")
      bad += 1
    elif any(w["file"] == "checks/w1.py" for w in gates_hit[0]["writers"]):
      print("PLANT 2 RED-BROKEN: a writer in checks/ claimed gates/rows-a.rows")
      bad += 1
    else:
      print("PLANT 2 OK: a writer claims only its own directory")
    # PLANT 3: an f-string TEMPLATE is a path.
    _plant_tree(tmp, ("checks/w4.py", "from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
                                      "(HERE / f'rows-{n}.rows').write_text('x')\n"))
    subprocess.run(["git", "add", "-A"], cwd=tmp, check=True)
    subprocess.run(["git", "-c", "user.email=a@b", "-c", "user.name=c", "commit", "-qm", "plant2"],
                   cwd=tmp, check=True)
    r = census(tmp)
    if not any(x["path"].startswith("checks/rows-") for x in r["rows"]):
      print("PLANT 3 RED: a TEMPLATE writer was not matched")
      bad += 1
    else:
      print("PLANT 3 OK: a template writer was matched")
    # PLANT 4: a hole must not span a DIRECTORY SEPARATOR.
    _plant_tree(tmp, ("checks/w5.py", "from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
                                      "(HERE / f'{a}/{b}.rows').write_text('x')\n"))
    subprocess.run(["git", "add", "-A"], cwd=tmp, check=True)
    subprocess.run(["git", "-c", "user.email=a@b", "-c", "user.name=c", "commit", "-qm", "plant3"],
                   cwd=tmp, check=True)
    r = census(tmp)
    if any(x["n_writers"] >= 2 and x["path"].count("/") > 1 for x in r["rows"]):
      print("PLANT 4 RED-BROKEN: a hole spanned a directory separator")
      bad += 1
    else:
      print("PLANT 4 OK: a hole did not span a directory separator")
    # PLANT 5: a TEMPORARY DIRECTORY is not a tracked path, and a shape is not a path.
    _plant_tree(tmp, ("checks/w6.py", "from pathlib import Path\nimport tempfile\n"
                                      "def f(td):\n    Path(td, f'{name}.py').write_text('x')\n"))
    subprocess.run(["git", "add", "-A"], cwd=tmp, check=True)
    subprocess.run(["git", "-c", "user.email=a@b", "-c", "user.name=c", "commit", "-qm", "plant4"],
                   cwd=tmp, check=True)
    r = census(tmp)
    if any(x["n_writers"] >= 2 and x["path"].endswith(".py") for x in r["rows"]):
      print("PLANT 5 RED-BROKEN: a temporary-directory shape claimed tracked .py files")
      bad += 1
    else:
      print("PLANT 5 OK: a temporary-directory shape claimed nothing")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
