#!/usr/bin/env python3
"""noblob-census -- the subjects recover() was asked for and did not answer.

    .venv/bin/python gates/noblob-census.py
    .venv/bin/python gates/noblob-census.py --plant

`gates/oracle-dangling-gate.py` is LOADED BY PATH. `census()` and `recover()` are the
generator. A no-blob subject is a dangling subject of a kind `census()` passes to
`recover()`, absent from `recover()`'s answer. The prior reading was 40. The count is
re-derived; if it is not 40 the tree moved, and a path is not dropped to keep 40.

TWO CLAIMS, AND THEY ARE NOT THE SAME. `git log --all -- <path>` empty is
NEVER-IN-HISTORY: no commit has ever carried the path. That is not "the blob was
garbage-collected". A non-empty log whose blob `recover()` did not return is
BLOB-GONE-BUT-LOGGED. The question is asked by path. `git rev-list --all` is not a
path index and is not used.

CITERS ARE DISCOVERED from the same namer bodies, through the same `tokens()`, at
file:line. Not a hand list. Each citer is then classed by the citer's own structure.
The rule is `RULE`, printed by the report. A path is PLANT-CITATION when every citer
is plant-class, LOAD-BEARING when any citer is not, and NO-CITER when it has none.
NO-CITER is printed. It is not a skip, and a path is not dropped to keep a count.

THE FINDING IS REPORTED, NOT CHARGED. PASS is every no-blob subject carrying exactly
one history class and exactly one citation class. The plant is what can fail: a
never-committed citation is NEVER-IN-HISTORY; a citation whose blob was removed from
a copy of the index, but which `git log` still has, is not; an existing file is in
neither citation class. A citation added inside `_synthetic()` is PLANT-CITATION; the
same path cited from a non-plant function is LOAD-BEARING. A plant that emits nothing
while scoring success is not a plant.

`recover()`'s walk is read from the module loaded by path (`WALK_DEPTH`), not from
the wiped-parent string. Depth 2 is the grandparent; depth 3 is not walked. This file
does not fix the walk.
"""
from __future__ import annotations

import argparse
import ast
import importlib.util
import inspect
import os
import subprocess
import sys
import time
import warnings
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

DANGLING = HERE / "oracle-dangling-gate.py"
# The reading this gate was asked to chase. A comparison, not a population: the count
# below is re-derived, and a path is never dropped to keep this number.
PRIOR = 40
# The filter `census()` applies before it calls `recover()`. Loaded from that source
# at run time (`filter_loaded`); this tuple is the expected text, not a second rule.
FILTER = ("ORACLE", "EV", "SWEPT")
NEVER = "NEVER-IN-HISTORY"
LOGGED = "BLOB-GONE-BUT-LOGGED"
CLASSES = (NEVER, LOGGED)
PLANT_CITE = "PLANT-CITATION"
LOAD = "LOAD-BEARING"
NO_CITER = "NO-CITER"
CITE_CLASSES = (PLANT_CITE, LOAD, NO_CITER)
# Exact names. `plants` and `_plant` are different functions and are not this class.
PLANT_FUNCS = frozenset({"_synthetic", "plant"})
# One string. report() prints it and cite_of() applies it. A second wording is a second rule.
RULE = (
    "A citer is plant-class when its line lies inside a function whose name is exactly "
    "_synthetic or plant (lineno through end_lineno), or the token's span lies inside a "
    "backtick-delimited example inside a docstring string. A docstring string is the first "
    "statement of a module, class, or function body when that statement is a string constant. "
    "A backtick span in that string is an example; a prose mention in the same docstring is not. "
    "A path is PLANT-CITATION when it has at least one citer and every citer is plant-class, "
    "LOAD-BEARING when any citer is not, and NO-CITER when it has none. NO-CITER is printed; "
    "it is not a skip."
)


def git(args: list[str], env: dict | None = None, stdin: str | None = None) -> subprocess.CompletedProcess:
  """`git` in ROOT. `env` is merged over the process environment so a plant can point
  `GIT_INDEX_FILE` at a copy index without the caller exporting it."""
  run_env = os.environ.copy()
  if env:
    run_env.update(env)
  return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, input=stdin, env=run_env)


def load_dangling(path: Path | None = None, name: str = "oracle_dangling_noblob"):
  """Import the generator by path. `gates/` is not a package. A plant passes a copy."""
  src = DANGLING if path is None else path
  if not src.is_file():
    return None
  spec = importlib.util.spec_from_file_location(name, src)
  if spec is None or spec.loader is None:
    return None
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  if not callable(getattr(mod, "census", None)) or not callable(getattr(mod, "recover", None)):
    return None
  if not callable(getattr(mod, "kind_of", None)) or not callable(getattr(mod, "tokens", None)):
    return None
  if not callable(getattr(mod, "namer_population", None)):
    return None
  return mod


def filter_loaded(mod) -> bool:
  """The asked-kinds rule is `census()`'s own text. A missing string is a REFUSAL, not a guess.

  The source spells the tuple with double quotes. `FILTER!r` would look for single quotes
  and refuse a rule that is there.
  """
  src = inspect.getsource(mod.census)
  return 'in ("ORACLE", "EV", "SWEPT")' in src and "recover(" in src


# One wording each. walk_claim() returns these; the plant matches them. A second sentence is a second rule.
WALK_DEPTH2 = (
  "CONFIRMED at grandparent: WALK_DEPTH = 2; the chain loop is range(WALK_DEPTH), "
  "so depth 3 (great-grandparent) is not walked"
)
WALK_WIPE = (
  "CONFIRMED, the wipe is back: recover() assigns cur_parents = [] after "
  "appending one parent, so the chain is the touching commit and its parent"
)
WALK_NEITHER = (
  "NOT CONFIRMED: recover() claims a grandparent and has neither WALK_DEPTH nor the wipe"
)


def _file_depth(path: Path) -> int | None:
  """The module-level `WALK_DEPTH = <int>` in the file the module was loaded from. Last assignment wins."""
  try:
    tree = ast.parse(path.read_text())
  except (OSError, SyntaxError):
    return None
  found = None
  for node in ast.iter_child_nodes(tree):
    if not isinstance(node, ast.Assign) or len(node.targets) != 1:
      continue
    target = node.targets[0]
    if not (isinstance(target, ast.Name) and target.id == "WALK_DEPTH"):
      continue
    value = node.value
    found = value.value if isinstance(value, ast.Constant) and type(value.value) is int else None
  return found


def _pos(node: ast.AST) -> tuple[int, int]:
  return (getattr(node, "lineno", 0), getattr(node, "col_offset", 0))


def _is_append_cur0(node: ast.AST) -> bool:
  """`chain.append(cur_parents[0])`, the one append the old wipe follows. Not a comment."""
  call = node.value if isinstance(node, ast.Expr) else node
  if not isinstance(call, ast.Call) or len(call.args) != 1:
    return False
  func, arg = call.func, call.args[0]
  if not (isinstance(func, ast.Attribute) and func.attr == "append"
          and isinstance(func.value, ast.Name) and func.value.id == "chain"):
    return False
  return (isinstance(arg, ast.Subscript) and isinstance(arg.value, ast.Name)
          and arg.value.id == "cur_parents" and isinstance(arg.slice, ast.Constant)
          and arg.slice.value == 0)


def _is_wipe(node: ast.AST) -> bool:
  """`cur_parents = []`. The assignment that throws away every parent after the first."""
  if not isinstance(node, ast.Assign) or len(node.targets) != 1:
    return False
  target = node.targets[0]
  return (isinstance(target, ast.Name) and target.id == "cur_parents"
          and isinstance(node.value, ast.List) and not node.value.elts)


def _wipe_back(src: str) -> bool:
  """The old bug: append `cur_parents[0]`, then assign `cur_parents = []`."""
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return False
  append_at = None
  wipe_at = None
  for node in ast.walk(tree):
    if _is_append_cur0(node):
      pos = _pos(node)
      if append_at is None or pos < append_at:
        append_at = pos
    if _is_wipe(node):
      pos = _pos(node)
      if wipe_at is None or pos < wipe_at:
        wipe_at = pos
  return append_at is not None and wipe_at is not None and append_at < wipe_at


def _appends_chain(node: ast.AST) -> bool:
  return any(isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute)
             and sub.func.attr == "append" and isinstance(sub.func.value, ast.Name)
             and sub.func.value.id == "chain" for sub in ast.walk(node))


def _chain_bounds(src: str) -> list[str] | None:
  """Bound of every `range` loop that appends to `chain`. An enclosing `.items()` loop is not the walk."""
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return None
  bounds: list[str] = []
  for node in ast.walk(tree):
    if not isinstance(node, ast.For) or not _appends_chain(node):
      continue
    it = node.iter
    if not (isinstance(it, ast.Call) and isinstance(it.func, ast.Name) and it.func.id == "range"):
      continue
    name = it.args[0].id if len(it.args) == 1 and isinstance(it.args[0], ast.Name) else "other"
    bounds.append("WALK_DEPTH" if name == "WALK_DEPTH" else "other")
  return bounds


def _loaded_depth(mod) -> int | None:
  """`WALK_DEPTH` from the loaded module, and only if the file it was loaded from assigns the same int."""
  loaded = getattr(mod, "WALK_DEPTH", None)
  path = getattr(mod, "__file__", None)
  if type(loaded) is not int or not path:
    return None
  return loaded if _file_depth(Path(path)) == loaded else None


def walk_claim(mod) -> str:
  """What the loaded walk does. The constant is the module's, read from the file loaded by path. Not a fix."""
  src = inspect.getsource(mod.recover)
  if _wipe_back(src):
    return WALK_WIPE
  bounds = _chain_bounds(src)
  if _loaded_depth(mod) == 2 and bounds and all(b == "WALK_DEPTH" for b in bounds):
    return WALK_DEPTH2
  if "grandparent" in src and _loaded_depth(mod) is None and not _wipe_back(src):
    return WALK_NEITHER
  return "NOT CONFIRMED: the loaded walk is neither depth 2 nor the wipe"


def touching(paths: list[str], env: dict | None = None) -> dict[str, list[str]] | None:
  """`path -> commits` from `git log --all -- <paths>`, newest first.

  A path absent from the output has an empty log. One walk, pathspec-limited:
  `--name-only` under a pathspec names only the paths that matched (measured: a 3-file
  commit named only the pathspec). Not `git rev-list --all`. A non-zero git status is
  `None` -- an unanswered log is not an empty history.
  """
  out = {p: [] for p in paths}
  if not paths:
    return out
  p = git(["log", "--all", "--format=%x01%H", "--name-only", "--", *paths], env=env)
  if p.returncode != 0:
    return None
  wanted = set(paths)
  sha = ""
  for line in p.stdout.splitlines():
    if line.startswith("\x01"):
      sha = line[1:].strip()
      continue
    if not line or not sha:
      continue
    if line[:1] in "\"'":
      return None
    if line in wanted and sha not in out[line]:
      out[line].append(sha)
  return out


def _clean_span(raw: str, mod) -> tuple[str, int, int] | None:
  """`(cleaned, start, end)` within `raw`, or None if `tokens()` would drop the match.

  The cleaning steps are `tokens()`'s, kept attached to the match so a later span test
  can say whether that token sits inside a backtick. A divergence from `tokens()` is a
  refusal, not a second tokenizer.
  """
  if len(raw) < 3 or mod.FAMILY.search(raw):
    return None
  stripped = raw.rstrip(".")
  start = 0
  tok = stripped
  if tok.startswith("./"):
    tok = tok[2:]
    start = 2
  if len(tok) < 3 or mod.FAMILY.search(tok):
    return None
  last = tok.rsplit("/", 1)[-1]
  if "." not in last or last.index(".") == 0:
    return None
  return tok, start, len(stripped)


def _line_spans(line: str, mod) -> list[tuple[str, int, int]]:
  """`(token, col_lo, col_hi)` for every token `tokens(line)` returns, in that order."""
  found: list[tuple[str, int, int]] = []
  for m in mod.TOKEN_RUN.finditer(line):
    got = _clean_span(m.group(1), mod)
    if got is None:
      continue
    tok, a, b = got
    found.append((tok, m.start(1) + a, m.start(1) + b))
  if [t for t, _, _ in found] != mod.tokens(line):
    raise RuntimeError(f"token spans diverged from tokens() on {line!r}")
  return found


def _structure(body: str) -> tuple[set[int], list[tuple[int, int, int]]] | None:
  """`(plant-function lines, example spans)` or None if `body` does not parse.

  A plant-function line is inside a function named `_synthetic` or `plant`, lineno through
  end_lineno. An example span is `(lineno, col_lo, col_hi)`, half-open, inside both a
  docstring string and a backtick span. A body that does not parse has no such structure;
  its citers are not plant-class.
  """
  try:
    with warnings.catch_warnings():
      warnings.simplefilter("ignore", SyntaxWarning)
      tree = ast.parse(body)
  except SyntaxError:
    return None
  plant_lines: set[int] = set()
  docs: list[tuple[int, int, int, int]] = []
  for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in PLANT_FUNCS:
      if node.end_lineno is not None:
        plant_lines.update(range(node.lineno, node.end_lineno + 1))
    stmts = getattr(node, "body", None)
    if not isinstance(stmts, list) or not stmts:
      continue
    first = stmts[0]
    value = first.value if isinstance(first, ast.Expr) else None
    if not (isinstance(value, ast.Constant) and isinstance(value.value, str)
            and value.end_lineno is not None and value.end_col_offset is not None):
      continue
    docs.append((value.lineno, value.col_offset, value.end_lineno, value.end_col_offset))
  src = body.splitlines()
  examples: list[tuple[int, int, int]] = []
  for start_line, start_col, end_line, end_col in docs:
    opened = False
    for i in range(start_line - 1, min(end_line, len(src))):
      line = src[i]
      lo = start_col if i == start_line - 1 else 0
      hi = end_col if i == end_line - 1 else len(line)
      hi = min(hi, len(line))
      if lo > hi:
        continue
      seg = line[lo:hi]
      content_from = 0 if opened else None
      cursor = 0
      while True:
        j = seg.find("`", cursor)
        if j < 0:
          break
        if not opened:
          opened = True
          content_from = j + 1
        else:
          if content_from is not None and content_from < j:
            examples.append((i + 1, lo + content_from, lo + j))
          opened = False
          content_from = None
        cursor = j + 1
      if opened and content_from is not None and content_from < len(seg):
        examples.append((i + 1, lo + content_from, lo + len(seg)))
  return plant_lines, examples


def _role(n: int, hits: list[tuple[str, int, int]],
          struct: tuple[set[int], list[tuple[int, int, int]]] | None) -> str:
  """`func` | `example` | `load` for one line. A line inside `_synthetic` or `plant` is `func`
  even when the token is not in a docstring. Otherwise every hit on the line must sit in a
  backtick example, or the line is `load`."""
  if struct is None:
    return "load"
  plant_lines, examples = struct
  if n in plant_lines:
    return "func"
  def sits(a: int, b: int) -> bool:
    return any(ln == n and slo <= a and b <= shi for ln, slo, shi in examples)
  if hits and all(sits(a, b) for _, a, b in hits):
    return "example"
  return "load"


def cite_index(paths: set[str], bodies: list[tuple[str, str]], mod) -> tuple[dict[str, list[str]], dict[str, str]]:
  """`path -> ['file:line', ...]` and `'file:line' -> role`, from the generator's tokenizer.

  Not a hand list of paths. A recorded citer always has a role. A body that does not parse
  cannot be shown to be plant-class, so its citers are `load`.
  """
  citers = {p: [] for p in paths}
  roles: dict[str, str] = {}
  if not paths:
    return citers, roles
  for rel, body in bodies:
    struct = _structure(body)
    for n, line in enumerate(body.splitlines(), 1):
      hits = [s for s in _line_spans(line, mod) if s[0] in citers]
      if not hits:
        continue
      key = f"{rel}:{n}"
      roles[key] = _role(n, hits, struct)
      seen: set[str] = set()
      for tok, _, _ in hits:
        if tok not in seen:
          seen.add(tok)
          citers[tok].append(key)
  return citers, roles


def cite_of(citers: list[str], roles: dict[str, str]) -> str:
  """The path's citation class. See `RULE`. A citer with no role is not plant-class."""
  if not citers:
    return NO_CITER
  if all(roles.get(c) in ("func", "example") for c in citers):
    return PLANT_CITE
  return LOAD


def derive(mod, surveyed: dict, fs: Path) -> dict:
  """The no-blob set, re-derived, and one history class per path."""
  roles = surveyed["roles"]
  asked = [t for t in surveyed["dangling"] if mod.kind_of(t, roles) in FILTER]
  recovery = surveyed["recovery"]
  missing = [t for t in asked if t not in recovery]
  witness = sorted(mod.recover(missing))
  commits = touching(missing)
  if commits is None:
    raise RuntimeError("git log --all -- <paths> did not answer")
  bodies, _deriv = mod.namer_population(fs)
  cites, roles_of = cite_index(set(missing), bodies, mod)
  rows = []
  for path in missing:
    touched = commits.get(path, [])
    row_citers = cites.get(path, [])
    row_roles = {c: roles_of[c] for c in row_citers if c in roles_of}
    rows.append({
      "path": path,
      "kind": mod.kind_of(path, roles),
      "class": NEVER if not touched else LOGGED,
      "commits": touched,
      "citers": row_citers,
      "roles": row_roles,
      "cite": cite_of(row_citers, row_roles),
      "role_gap": [c for c in row_citers if c not in roles_of],
    })
  return {"asked": asked, "recovered": len(recovery), "rows": rows,
          "witness": witness, "walk": walk_claim(mod),
          "stamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}


def probe_beyond(rows: list[dict]) -> list[str]:
  """Grandparents `recover()` does not ask, that still name a blob. By path. Nothing is written back."""
  logged = [r for r in rows if r["class"] == LOGGED and r["commits"]]
  specs: list[tuple[str, str]] = []
  for r in logged:
    for sha in r["commits"][:4]:
      parent = git(["rev-parse", "--verify", f"{sha}^"])
      if parent.returncode != 0:
        continue
      grand = git(["rev-parse", "--verify", f"{parent.stdout.strip()}^"])
      if grand.returncode != 0:
        continue
      specs.append((r["path"], f"{grand.stdout.strip()}:{r['path']}"))
  if not specs:
    return []
  chk = git(["cat-file", "--batch-check"], stdin="\n".join(s for _, s in specs) + "\n")
  found = []
  for (path, spec), line in zip(specs, chk.stdout.splitlines()):
    fields = line.split()
    if len(fields) >= 3 and fields[1] == "blob":
      found.append(f"{path}  blob at grandparent {spec}  {fields[2]} B")
  return found


def _cite_preview(citers: list[str], roles: dict[str, str] | None = None, n: int = 6) -> str:
  def one(c: str) -> str:
    tag = "" if not roles else f" [{roles.get(c, '?')}]"
    return c + tag
  shown = [one(c) for c in citers[:n]]
  tail = "" if len(citers) <= n else f"  (+{len(citers) - n})"
  return ", ".join(shown) + tail


def report(got: dict) -> None:
  rows = got["rows"]
  n = len(rows)
  by = {k: [r for r in rows if r["class"] == k] for k in CLASSES}
  head = git(["rev-parse", "HEAD"]).stdout.strip()
  print(f"noblob-census   HEAD {head}   {got['stamp']}")
  print("  COMMAND        .venv/bin/python gates/noblob-census.py")
  print("  DERIVED        census() dangling, kind in census()'s recover() filter, absent from recover()")
  print(f"  ASKED          {len(got['asked'])}   RECOVERED {got['recovered']}   NO-BLOB {n}")
  if n == PRIOR:
    print(f"  TREE           unmoved from the prior reading {PRIOR}")
  else:
    print(f"  TREE MOVED     prior reading {PRIOR}, this reading {n}. No path was dropped to keep {PRIOR}.")
  print(f"  {NEVER:<22} {len(by[NEVER])}")
  print(f"  {LOGGED:<22} {len(by[LOGGED])}")
  cite_by = {k: [r for r in rows if r["cite"] == k] for k in CITE_CLASSES}
  print(f"  CITE RULE      {RULE}")
  for label in CITE_CLASSES:
    print(f"  {label:<22} {len(cite_by[label])}")
  print(f"  WALK           {got['walk']}")
  if got["witness"]:
    print(f"  WITNESS        a second recover() found {len(got['witness'])} blob(s); paths kept: "
          + ", ".join(got["witness"][:8]))
  else:
    print(f"  WITNESS        recover() on the {n} agreed: still no blob")
  print("  PATHS")
  for r in rows:
    tip = r["commits"][0][:12] if r["commits"] else "-"
    print(f"    {r['cite']:<16} {r['class']:<22} {r['kind']:<10} "
          f"log={len(r['commits']):<4} tip={tip}  {r['path']}")
    print(f"      citers {len(r['citers'])}: {_cite_preview(r['citers'], r['roles'])}")
  never = by[NEVER]
  print(f"  {NEVER} NAMED  {len(never)}")
  for r in never:
    print(f"    {r['path']}")
  if len(never) > 60:
    print("    (list is long; the lines above are the count's members, not a sample)")
  files = Counter(c.rsplit(":", 1)[0] for r in never for c in r["citers"])
  print(f"  TOP CITERS of {NEVER}  {len(files)} file(s)")
  for rel, k in files.most_common(8):
    print(f"    {k:>4}  {rel}")
  for label in CITE_CLASSES:
    members = cite_by[label]
    note = "  (neither: no discovered citer; not a skip)" if label == NO_CITER else ""
    print(f"  {label} NAMED  {len(members)}{note}")
    for r in members:
      print(f"    {r['path']}")
      if r["citers"]:
        print(f"      citers {len(r['citers'])}: {_cite_preview(r['citers'], r['roles'])}")
  beyond = probe_beyond(rows)
  print(f"  BEYOND RECOVER()  {len(beyond)} grandparent blob(s) asked by path, not written back")
  for line in beyond[:12]:
    print(f"    {line}")
  if len(beyond) > 12:
    print(f"    ... and {len(beyond) - 12} more")


def check(got: dict) -> tuple[int, str]:
  """Coverage only. The finding is printed above and is not an exit."""
  rows = got["rows"]
  if len(got["asked"]) != got["recovered"] + len(rows):
    return FAIL, (f"asked {len(got['asked'])} != recovered {got['recovered']} + no-blob {len(rows)}")
  bad = [r["path"] for r in rows if r["class"] not in CLASSES]
  if bad:
    return FAIL, f"{len(bad)} subject(s) carry no history class: {bad[:5]}"
  tally = Counter(r["class"] for r in rows)
  if sum(tally.values()) != len(rows):
    return FAIL, f"class counts sum to {sum(tally.values())} over {len(rows)}"
  cite_tally = Counter(r.get("cite") for r in rows)
  gap = [r["path"] for r in rows if r.get("cite") not in CITE_CLASSES or r.get("role_gap")]
  if gap:
    return FAIL, f"{len(gap)} subject(s) carry no citation class: {gap[:5]}"
  if sum(cite_tally[k] for k in CITE_CLASSES) != len(rows):
    return FAIL, f"citation classes sum to {sum(cite_tally[k] for k in CITE_CLASSES)} over {len(rows)}"
  for r in rows:
    want = cite_of(r["citers"], r["roles"])
    if r["cite"] != want:
      return FAIL, f"{r['path']} cite={r['cite']} but the rule says {want}"
    if r["cite"] == NO_CITER and r["citers"]:
      return FAIL, f"{r['path']} is NO-CITER and has citers"
    if r["cite"] != NO_CITER and not r["citers"]:
      return FAIL, f"{r['path']} is {r['cite']} and has no citer"
  cite = " ".join(f"{k}={cite_tally[k]}" for k in CITE_CLASSES)
  return PASS, (f"{len(rows)} no-blob, " + " ".join(f"{k}={tally[k]}" for k in CLASSES) + " | " + cite)


def _plant_path(leaf: str) -> str:
  """A never-committed path built by concatenation, so this file does not cite it whole."""
  return ".agents" + "/" + "slop/noblob-plant/" + leaf


def _never_path() -> str:
  """A path this source must not cite as one token. `.agents` is dropped by `tokens()`
  (dot at index 0); the remainder is not a top-level name of the commit tree."""
  return _plant_path("never-existed.rows")


def _existing(surveyed: dict, mod, skip: set[str]) -> str | None:
  roles = surveyed["roles"]
  for p in sorted(surveyed["head"]):
    if p in skip or not (ROOT / p).is_file():
      continue
    if mod.kind_of(p, roles) in FILTER:
      return p
  for p in sorted(surveyed["head"]):
    if p not in skip and (ROOT / p).is_file():
      return p
  return None


def _print_check(name: str, ok: bool, detail: str) -> bool:
  print(f"  {'OK  ' if ok else 'FAIL'}  {name}")
  print(f"        {detail}")
  return ok


def _cite_extra(syn: str, pfn: str, ex: str, prose: str, control: str, also: bool) -> str:
  """Module-level functions appended to a copy. `also` adds a non-plant citer of the same paths."""
  body = (
    "def _synthetic():\n"
    f"    return ({syn!r}, {control!r})\n"
    "def plant():\n"
    f"    return {pfn!r}\n"
    "def show(x):\n"
    f"    \"\"\"`{ex}` -> ['out'].\"\"\"\n"
    "    return x\n"
    "def prose():\n"
    f"    \"\"\"named by a report: {prose} is not an example\"\"\"\n"
    "    return 0\n"
  )
  if also:
    body += (
      "def not_a_plant():\n"
      f"    return ({syn!r}, {pfn!r}, {ex!r}, {control!r})\n"
    )
  return body


def _parsing_writer(writers: list[str]) -> str | None:
  for w in writers:
    try:
      ast.parse((ROOT / w).read_text())
    except (OSError, SyntaxError):
      continue
    return w
  return None


def _derive_appended(mod, writer: str, extra: str) -> dict | None:
  """census+derive on a copy whose one namer is `writer` plus `extra`. Does not touch the index."""
  import tempfile
  text = (ROOT / writer).read_text() + "\n" + extra
  try:
    ast.parse(text)
  except SyntaxError as exc:
    print(f"PLANT REFUSED: the copy namer does not parse: {exc}")
    return None
  with tempfile.TemporaryDirectory(prefix="noblob-cite.") as tmp:
    copy = Path(tmp) / "repo"
    dest = copy / writer
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text)
    try:
      return derive(mod, mod.census(copy), copy)
    except Exception as exc:  # noqa: BLE001 -- a plant that hides this scores success on nothing
      print(f"PLANT REFUSED: derive did not answer: {type(exc).__name__}: {exc}")
      return None


def _want(rows: dict, path: str, cite: str, role: str | None, writer: str) -> tuple[bool, str]:
  row = rows.get(path)
  if row is None:
    return False, f"absent from the no-blob rows path={path}"
  got_roles = sorted(set(row["roles"].values()))
  ok = row["cite"] == cite and all(c.startswith(writer + ":") for c in row["citers"])
  if role is not None:
    ok = ok and got_roles == [role]
  return ok, f"cite={row['cite']} roles={got_roles} citers={len(row['citers'])} path={path}"


# Names the citation plant must print. A PASS that did not emit these scored success on nothing.
CITE_REQUIRED = (
  "PLANT citation inside _synthetic() is PLANT-CITATION",
  "FALSIFY the same path cited from a non-plant function is LOAD-BEARING",
  "PLANT citation inside plant() is PLANT-CITATION",
  "FALSIFY the same plant() path cited from a non-plant function is LOAD-BEARING",
  "PLANT backtick example in a docstring is PLANT-CITATION",
  "FALSIFY the same docstring example cited from a non-plant function is LOAD-BEARING",
  "FALSIFY a prose docstring mention is not a docstring example",
  "CONTROL an existing file cited from _synthetic() is in neither",
  "CONTROL an existing file cited from a non-plant function is in neither",
)


def _cite_plant(mod, surveyed: dict, real: dict, writers: list[str], control: str) -> int:
  """The citation-class plant, on copies. Prints every check. Empty emission is FAIL, not PASS."""
  writer = _parsing_writer(writers)
  if writer is None:
    print("PLANT REFUSED: no discovered gates/*.py namer parses; the function span cannot be read")
    return REFUSED
  syn, pfn, ex, prose = (
    _plant_path("from-synthetic.rows"), _plant_path("from-plant-fn.rows"),
    _plant_path("from-example.rows"), _plant_path("from-prose.rows"))
  own = (HERE / "noblob-census.py").read_text()
  own_toks = set(mod.tokens(own))
  real_missing = {r["path"] for r in real["rows"]}
  for path in (syn, pfn, ex, prose):
    if path in own_toks or path in real_missing or (ROOT / path).exists():
      print(f"PLANT REFUSED: {path} is already a token, a subject, or a file")
      return REFUSED
  checks: list[tuple[str, bool, str]] = []
  print(f"  CITE PLANT writer={writer}  config=plant-only")
  only = _derive_appended(mod, writer, _cite_extra(syn, pfn, ex, prose, control, also=False))
  if only is None:
    return REFUSED
  only_rows = {r["path"]: r for r in only["rows"]}
  checks += [
    ("PLANT citation inside _synthetic() is PLANT-CITATION",
     *_want(only_rows, syn, PLANT_CITE, "func", writer)),
    ("PLANT citation inside plant() is PLANT-CITATION",
     *_want(only_rows, pfn, PLANT_CITE, "func", writer)),
    ("PLANT backtick example in a docstring is PLANT-CITATION",
     *_want(only_rows, ex, PLANT_CITE, "example", writer)),
    ("FALSIFY a prose docstring mention is not a docstring example",
     *_want(only_rows, prose, LOAD, "load", writer)),
    ("CONTROL an existing file cited from _synthetic() is in neither",
     control not in only_rows,
     f"in-rows={control in only_rows} path={control}"),
  ]
  for name, ok, detail in checks:
    _print_check(name, ok, detail)
  print(f"  CITE PLANT writer={writer}  config=same-path-from-non-plant")
  both = _derive_appended(mod, writer, _cite_extra(syn, pfn, ex, prose, control, also=True))
  if both is None:
    return REFUSED
  both_rows = {r["path"]: r for r in both["rows"]}
  # The falsification is the mix: the plant-class citer is still there, and the non-plant citer
  # moves the path to LOAD-BEARING. A class word alone would not show that.
  mixed = (
    ("FALSIFY the same path cited from a non-plant function is LOAD-BEARING", syn, "func"),
    ("FALSIFY the same plant() path cited from a non-plant function is LOAD-BEARING", pfn, "func"),
    ("FALSIFY the same docstring example cited from a non-plant function is LOAD-BEARING", ex, "example"),
  )
  for name, path, plant_role in mixed:
    row = both_rows.get(path)
    roles = set() if row is None else set(row["roles"].values())
    ok = (row is not None and row["cite"] == LOAD and "load" in roles and plant_role in roles
          and all(c.startswith(writer + ":") for c in row["citers"]))
    detail = f"cite={None if row is None else row['cite']} roles={sorted(roles)} path={path}"
    checks.append((name, ok, detail))
    _print_check(name, ok, detail)
  neither = control not in both_rows
  checks.append(("CONTROL an existing file cited from a non-plant function is in neither",
                 neither, f"in-rows={control in both_rows} path={control}"))
  _print_check(checks[-1][0], checks[-1][1], checks[-1][2])
  missing = [n for n in CITE_REQUIRED if n not in {c[0] for c in checks}]
  if missing:
    _print_check("citation plant emitted every required check", False, ", ".join(missing))
    return FAIL
  bad = [n for n, ok, _d in checks if not ok]
  if bad:
    return FAIL
  return PASS


# The old walk, put back into a copy. The live file is not this text.
_WIPE_BLOCK = (
  "            chain, cur_parents = [sha], parents\n"
  "            for _ in range(3):\n"
  "                if not cur_parents:\n"
  "                    break\n"
  "                chain.append(cur_parents[0])\n"
  "                cur_parents = []\n"
)
# Names the walk plant must print. A PASS that did not emit these scored success on nothing.
WALK_REQUIRED = (
  "PLANT a copy with WALK_DEPTH = 2 and no wipe is CONFIRMED at grandparent",
  "PLANT a copy with the wipe is CONFIRMED, the wipe is back",
  "PLANT a copy with neither constant nor wipe is NOT CONFIRMED",
  "CONTROL the live oracle-dangling-gate.py is unmodified and reads depth 2",
)


def _with_wipe(text: str) -> str | None:
  """The live chain loop, replaced by the wipe. Refuses a file that is not that shape."""
  anchor = "            chain = [sha]\n"
  tail = "            cands.extend"
  if text.count(anchor) != 1:
    return None
  start = text.find(anchor)
  end = text.find(tail, start)
  if end < 0:
    return None
  return text[:start] + _WIPE_BLOCK + text[end:]


def _without_depth(text: str) -> str | None:
  """The module-level assignment removed. The grandparent claim in `recover()` stays."""
  needle = "WALK_DEPTH = 2\n"
  if text.count(needle) != 1:
    return None
  return text.replace(needle, "", 1)


def _load_copy(path: Path, name: str):
  """Load a copy by path. The copy inserts its own directory on `sys.path`; that does not stay."""
  saved = sys.path.copy()
  try:
    return load_dangling(path, name)
  except Exception as exc:  # noqa: BLE001 -- a copy that does not import is a refusal, not a pass
    print(f"PLANT REFUSED: {name} did not load: {type(exc).__name__}: {exc}")
    return None
  finally:
    sys.path[:] = saved


def _walk_plant(mod) -> int:
  """Three copies of the recover module, plus the live file left byte-identical.

  Depth 2 and no wipe is the grandparent. The wipe is the wipe. Neither is not a pass.
  """
  import hashlib
  import tempfile
  before = DANGLING.read_bytes()
  text = before.decode()
  built = {
    "depth2": text,
    "wipe": _with_wipe(text),
    "neither": _without_depth(text),
  }
  if any(v is None for v in built.values()):
    print("PLANT REFUSED: the live walk is not the shape the copies are built from")
    return REFUSED
  want = {"depth2": WALK_DEPTH2, "wipe": WALK_WIPE, "neither": WALK_NEITHER}
  names = {
    "depth2": WALK_REQUIRED[0],
    "wipe": WALK_REQUIRED[1],
    "neither": WALK_REQUIRED[2],
  }
  checks: list[tuple[str, bool, str]] = []
  print(f"  WALK PLANT live sha256={hashlib.sha256(before).hexdigest()[:12]}")
  with tempfile.TemporaryDirectory(prefix="noblob-walk.") as tmp:
    root = Path(tmp)
    for kind in ("depth2", "wipe", "neither"):
      body = built[kind]
      if body is None:
        print(f"PLANT REFUSED: the {kind} copy was not built")
        return REFUSED
      try:
        ast.parse(body)
      except SyntaxError as exc:
        print(f"PLANT REFUSED: the {kind} copy does not parse: {exc}")
        return REFUSED
      dest = root / f"{kind}.py"
      dest.write_text(body)
      copy = _load_copy(dest, f"oracle_dangling_walk_{kind}")
      if copy is None or not callable(getattr(copy, "recover", None)):
        print(f"PLANT REFUSED: the {kind} copy did not load recover()")
        return REFUSED
      got = walk_claim(copy)
      src = inspect.getsource(copy.recover)
      depth = getattr(copy, "WALK_DEPTH", None)
      wipe = _wipe_back(src)
      claims = "grandparent" in src
      if kind == "depth2":
        shape = depth == 2 and not wipe and "WALK_DEPTH = 2\n" in body
      elif kind == "wipe":
        shape = wipe and "cur_parents = []" in body and "chain.append(cur_parents[0])" in body
      else:
        shape = claims and depth is None and not wipe and "WALK_DEPTH = 2\n" not in body
      checks.append((names[kind], got == want[kind] and shape,
                     f"got={got} depth={depth!r} wipe={wipe}"))
  after = DANGLING.read_bytes()
  live = walk_claim(mod)
  checks.append((
    WALK_REQUIRED[3],
    after == before and live == WALK_DEPTH2,
    f"bytes-same={after == before} walk={live}",
  ))
  for name, ok, detail in checks:
    _print_check(name, ok, detail)
  missing = [n for n in WALK_REQUIRED if n not in {c[0] for c in checks}]
  if missing:
    _print_check("walk plant emitted every required check", False, ", ".join(missing))
    return FAIL
  if any(not ok for _, ok, _ in checks):
    return FAIL
  return PASS


def plant(mod, surveyed: dict, real: dict) -> int:
  """Checks on a copy of one namer and, for the history arm, a private index. The real index is not written.

  PLANT     a citation of a path that has never existed appears as NEVER-IN-HISTORY.
  FALSIFY   a citation of a path whose blob is deleted from the copy's index, but which
            `git log --all -- <path>` still has, does not become NEVER-IN-HISTORY.
  CONTROL   an existing file is in neither citation class.
  CITE      a citation inside `_synthetic()` is PLANT-CITATION; the same path cited from a
            non-plant function is LOAD-BEARING. A plant that emits nothing is not a PASS.
  WALK      a copy of the recover module at depth 2 is the grandparent; the wipe is the wipe;
            neither is not a pass. The live file is not edited.
  """
  import tempfile
  never = _never_path()
  own = (HERE / "noblob-census.py").read_text()
  if never in mod.tokens(own):
    print("PLANT REFUSED: this file cites the never-path as a whole token")
    return REFUSED
  real_missing = {r["path"] for r in real["rows"]}
  if never in real_missing or never in surveyed["subjects"]:
    print(f"PLANT REFUSED: {never} is already a subject")
    return REFUSED
  writers = sorted({n for ns in surveyed["subjects"].values() for n in ns
                    if n.endswith(".py") and n.startswith("gates/") and (ROOT / n).is_file()})
  if not writers:
    print("PLANT REFUSED: no discovered gates/*.py namer to cite from")
    return REFUSED
  writer = writers[0]
  control = _existing(surveyed, mod, set())
  victim = _existing(surveyed, mod, {control} if control else set())
  if control is None or victim is None or victim == writer:
    print(f"PLANT REFUSED: control={control} victim={victim} writer={writer}")
    return REFUSED
  pre = touching([victim])
  if not pre or not pre.get(victim):
    print(f"PLANT REFUSED: {victim} has an empty git log; it cannot falsify NEVER-IN-HISTORY")
    return REFUSED
  real_index = ROOT / ".git" / "index"
  index_mtime = real_index.stat().st_mtime_ns if real_index.exists() else None
  with tempfile.TemporaryDirectory(prefix="noblob-plant.") as tmp:
    copy = Path(tmp) / "repo"
    dest = copy / writer
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text((ROOT / writer).read_text()
                    + f"\nPLANT_NEVER = {never!r}\nPLANT_LOGGED = {victim!r}\n")
    index = copy / "plant-index"
    env = {"GIT_INDEX_FILE": str(index)}
    rt = git(["read-tree", "HEAD"], env=env)
    rm = git(["update-index", "--force-remove", "--", victim], env=env)
    listed = git(["ls-files", "--", victim], env=env)
    if rt.returncode != 0 or rm.returncode != 0 or listed.stdout.strip():
      print("PLANT REFUSED: the copy index did not lose the blob")
      print(f"  read-tree rc={rt.returncode} update-index rc={rm.returncode} ls-files={listed.stdout.strip()!r}")
      return REFUSED
    after_log = touching([victim], env=env)
    if after_log is None:
      print("PLANT REFUSED: git log did not answer under the stripped index")
      return REFUSED
    after = mod.census(copy)
    got = derive(mod, after, copy)
  if real_index.exists() and real_index.stat().st_mtime_ns != index_mtime:
    print("PLANT REFUSED: the real index mtime moved")
    return REFUSED
  copy_rows = {r["path"]: r for r in got["rows"]}
  never_row = copy_rows.get(never)
  victim_row = copy_rows.get(victim)
  victim_class = NEVER if not after_log.get(victim) else LOGGED
  checks = [
    ("PLANT never-existed citation is NEVER-IN-HISTORY",
     never_row is not None and never_row["class"] == NEVER
     and any(c.startswith(writer + ":") for c in never_row["citers"])
     and never not in real_missing,
     f"class={None if never_row is None else never_row['class']} "
     f"citers={0 if never_row is None else len(never_row['citers'])} writer={writer}"),
    ("FALSIFY index-deleted blob that git log has is not NEVER-IN-HISTORY",
     victim_class != NEVER and (victim_row is None or victim_row["class"] != NEVER),
     f"git-log={'empty' if victim_class == NEVER else 'non-empty'} "
     f"in-noblob={victim in copy_rows} path={victim}"),
    ("FALSIFY a module-level citation is LOAD-BEARING, not PLANT-CITATION",
     never_row is not None and never_row.get("cite") == LOAD,
     f"cite={None if never_row is None else never_row.get('cite')} path={never}"),
    ("CONTROL an existing file is in neither citation class",
     control not in real_missing and control not in copy_rows,
     f"real={control in real_missing} copy={control in copy_rows} path={control}"),
  ]
  bad = [n for n, ok, _d in checks if not _print_check(n, ok, _d)]
  cite_rc = _cite_plant(mod, surveyed, real, writers, control)
  walk_rc = _walk_plant(mod)
  arms = (("citation plant", cite_rc), ("walk plant", walk_rc))
  refused = [n for n, rc in arms if rc == REFUSED]
  failed = [n for n, rc in arms if rc not in (PASS, REFUSED)]
  if not bad and not failed and refused:
    return REFUSED
  if bad or failed or refused:
    print(f"  VERDICT FAIL: {'; '.join([*bad, *failed, *refused])}")
    return FAIL
  print("  VERDICT PASS")
  return PASS


def main(argv: list[str] | None = None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
  ap.add_argument("--report", action="store_true", help="census only, rc never charged")
  ap.add_argument("--plant", action="store_true", help="the self-test, on a copy")
  args = ap.parse_args(argv)
  mod = load_dangling()
  if mod is None:
    print("REFUSED: gates/oracle-dangling-gate.py did not load census() and recover(); "
          "the 40 were not re-derived by copying the generator", file=sys.stderr)
    return REFUSED
  if not filter_loaded(mod):
    print("REFUSED: census() no longer asks recover() for the ORACLE/EV/SWEPT filter; "
          "the rule was not copied", file=sys.stderr)
    return REFUSED
  try:
    surveyed = mod.census(ROOT)
    got = derive(mod, surveyed, ROOT)
  except Exception as exc:  # noqa: BLE001 -- reported, not hidden
    print(f"REFUSED: the census could not be taken: {type(exc).__name__}: {exc}", file=sys.stderr)
    return REFUSED
  if not surveyed.get("subjects"):
    print("DEAD: census() named no subjects")
    return DEAD
  report(got)
  code, why = check(got)
  print(f"  {why}")
  if args.report:
    print(f"  --report: rc never charged ({VERDICT[code]})")
    return PASS
  if args.plant:
    return plant(mod, surveyed, got)
  return code


if __name__ == "__main__":
  sys.exit(main())
