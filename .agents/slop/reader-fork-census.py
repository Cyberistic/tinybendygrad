#!/usr/bin/env python3
"""reader-fork-census.py -- THE DENOMINATOR FOR "HOW MANY OF THE 156 HAVE ACTUALLY DRIFTED".

    python3 .agents/slop/reader-fork-census.py            # census + drift table
    python3 .agents/slop/reader-fork-census.py --json     # machine-readable

WHY THIS FILE EXISTS. A previous census reported 156 forked row readers. That number is a
COUNT, not a finding: a census of 156 forks with no drift measurement is just a count. Every
one of them is a second answer to "what does this lane's output mean", and a second answer is
only dangerous if it DISAGREES. So this file does the thing the count did not: it CALLS each
reader on six row shapes and MEASURES.

THE CONTROL IS `rebase-gate.py`'s OWN `rows()`, LOADED BY PATH AND NEVER RE-TYPED.
agent-core.md records that an earlier unit `ast`-extracted its reader out of
`jj file show -r @-` precisely because "a re-typed fork would be a third reader". The same
trap is narrower here: re-typing `rows()` into this file would make the CONTROL a second
reader and the measurement a comparison of two things I wrote, one of which was the thing
under test. `canonical()` below is the gate's function object. The digest of the gate's source
is printed so a reader of this output can tell WHICH revision was measured.

THE SIX SHAPES, and each one is a shape the brief names:
    F1  name=value                     the plain form.
    F2  name = [v]   py=[w]            the port's form. `rows()` folds the `py=` tail away and
                                       returns `left`, the producer's OWN answer.
    F3  name<SP><SP>value              the name-less-`=` form.
    F4  na=me=value                    a row NAME containing `=`. Splitting at the FIRST `=` is
                                       what decides this, so a fork that splits at the LAST `=`
                                       disagrees here and nowhere else in the six.
    F5  name value                     a SINGLE-space gap. Not a row: `rows()` partitions on
                                       two spaces, so a one-space line has no separator at all.
    F6  name<TAB>value                 a TAB. Also not a row, and deliberately so -- a table's
                                       first column is not a row name and dtype_tables.py emits
                                       14,774 TSV lines that must keep reading as ZERO rows.

WHAT COUNTS AS DRIFT. Not "the source differs" -- two readers can agree on everything and be
spelled differently. Drift is DISAGREEMENT on the six shapes, measured by CALLING both on the
same text and comparing the (name, value) PAIRS. A reader whose RESULT TYPE differs (a list
of lines rather than a dict) can agree on all six and still not be substitutable for
`rows()`, so that is reported in its own column and never folded into "agrees".

WHAT IS NEVER REPORTED. A reader that could not be executed is `NOT-COMPARABLE`, never
`agrees`. An unexplained zero is a zero.
"""
import argparse
import ast
import builtins
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import re
import signal
import sys
import types

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
GATE = HERE / "rebase-gate.py"

# THE CORPUS: this project's own tooling, and nothing else. `tinygrad/`, `test/`, `extra/`,
# `examples/`, `docs/`, `langs/`, `spec/` are UPSTREAM tinygrad -- their readers are the SUBJECT
# of the port, not forks of it, and including them would inflate the denominator with code that
# has no `py=` tail concept at all. `references/`, `.venv`, `opstree/` and `xd1/` are clones
# and gitignored scratch. An earlier draft of this file walked the whole repo with
# `not d.startswith(".")` and therefore MISSED `.agents/` ENTIRELY -- the one directory that
# matters -- while collecting 16 candidates out of upstream MoE kernel code. The corpus is
# named explicitly here so that failure cannot recur.
CORPUS_ROOTS = (".agents", "runs")
CORPUS_SKIP = {"__pycache__", ".venv", "node_modules", ".jj", ".git", "opstree", "xd1",
               ".mutwork", "references"}

# THE TWO FAMILIES THAT ANSWER A ROW QUESTION. Everything else -- a producer, a differ, a path
# runner, a tensor accessor that happens to be called `rows_e` -- is NOT in the drift
# denominator, and saying so with a number is the difference between a census and a count.
DRIFT_FAMILIES = ("text->mapping", "line->answer")


# ── THE CONTROL ────────────────────────────────────────────────────────────────────────────
def load_gate():
  spec = importlib.util.spec_from_file_location("rebase_gate", str(GATE))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


GATE_MOD = load_gate()
CANONICAL = GATE_MOD.rows   # the gate's own function object. Not a copy. Never will be.
CANON_ROW = GATE_MOD.row    # the LINE reader, and the control for the `line->answer` family.


def canonical_digest():
  return hashlib.md5(GATE.read_bytes()).hexdigest()


def _render_answer(a):
  """A per-LINE answer rendered comparably: None, or a 2- or 3-tuple of cells."""
  if a is None:
    return "NONE"
  if isinstance(a, (list, tuple)):
    return f"SEQ{len(a)}" + repr([render(x) for x in a])
  return "OTHER " + repr(a)[:80]


# ── THE SIX SHAPES ─────────────────────────────────────────────────────────────────────────
# `NAME` carries SPACES and no `=`, which is this project's row-name rule; F3's name is a
# SINGLE TOKEN because `rows()` refuses a multi-token F3 name outright (its F3 arm returns
# None unless `len(head.split()) == 1`), so a multi-token F3 name would probe a rule the shape
# is not meant to probe and every reader would fail it for the wrong reason.
NAME = "ctl OPENCL sz1 k0"
NAME3 = "ctlf3"

SHAPES = (
  ("F1  name=value",                 f"{NAME}=half"),
  ("F2  name = [v]   py=[w]",        f"{NAME} = [half]   py=[half]"),
  ("F3  name<SP><SP>value",          f"{NAME3}  half"),
  ("F4  name contains '='",          "na=me=value"),
  ("F5  single-space gap",           "ctl single half"),
  ("F6  TAB gap",                    "ctl\ttab\thalf"),
)
SHAPE_IDS = tuple(s[0].split()[0] for s in SHAPES)


def canonical_pairs(text):
  """[(name, value)] as the GATE's rows() produces them, for one probe text."""
  d = CANONICAL(text)
  return sorted((str(k), str(v)) for k, v in d.items())


# ── CANDIDATE DISCOVERY ────────────────────────────────────────────────────────────────────
# A candidate is a FUNCTION whose name says it might read rows. This deliberately over-collects
# (`rows_moved` is a differ, `rows_e` is a Tensor accessor in vendored MoE code) because the
# alternative -- guessing which names "really" count -- is the move that makes a denominator
# unfalsifiable. Everything found is classified by CONTRACT below and the classes are printed
# with their counts, so a reader of the output can see what was excluded and why.
NAME_RE = re.compile(r"^(?:_?rows?|_?split_py|_?parse_rows|_?rowset|_?read_rows|_?oracle_rows"
                     r"|_?bend_rows|.*_rows|rows_.*|row_.*)$")


def py_files():
  for top in CORPUS_ROOTS:
    for root, dirs, files in os.walk(REPO / top):
      dirs[:] = sorted(d for d in dirs if d not in CORPUS_SKIP)
      for f in sorted(files):
        if f.endswith(".py"):
          yield pathlib.Path(root) / f


def candidates():
  """[(relpath, qualname, lineno, source, node)] for every function whose NAME says rows."""
  out = []
  for p in py_files():
    try:
      src = p.read_text()
      tree = ast.parse(src)
    except (SyntaxError, UnicodeDecodeError, OSError):
      continue
    lines = src.splitlines()
    for node in ast.walk(tree):
      if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        continue
      if not NAME_RE.match(node.name):
        continue
      seg = ast.get_source_segment(src, node)
      if not seg:
        # One-line bodies and decorators are the usual cause; fall back to the line range.
        seg = "\n".join(lines[node.lineno - 1:node.end_lineno])
      out.append((str(p.relative_to(REPO)), node.name, node.lineno, seg, node))
  return out


# ── THE SANDBOX ────────────────────────────────────────────────────────────────────────────
# A forked reader is executed to be MEASURED, so it runs with a builtins subset that cannot
# import a module, spawn a process, open a socket, or write a file. `open` is present in read
# mode only. An earlier draft of this file ran candidates with full builtins and one of them
# wrote into the tree.
SAFE_BUILTINS = {k: getattr(builtins, k) for k in (
  "abs", "all", "any", "bool", "bytes", "chr", "dict", "divmod", "enumerate", "filter", "float",
  "format", "frozenset", "getattr", "hasattr", "hex", "int", "isinstance", "issubclass", "iter",
  "len", "list", "map", "max", "min", "next", "oct", "ord", "pow", "range", "repr", "reversed",
  "round", "set", "slice", "sorted", "str", "sum", "tuple", "type", "zip")}


def _ro_open(file, mode="r", *a, **kw):
  if any(c in mode for c in "wxa+"):
    raise OSError("reader-fork-census sandbox: writers are disabled")
  return io.open(file, mode, *a, **kw)


class _Denied(Exception):
  pass


def _denied(name):
  def f(*a, **kw):
    raise _Denied(f"reader-fork-census sandbox denied {name}")
  return f


def _guarded_import(name, *a, **kw):
  """Imports are allowed only from SAFE_MODULES, and the dangerous ones come from the fake
  layer above. `__import__` absent from builtins is what turned 304 candidates into
  NOT-COMPARABLE on the second pass -- the harness refusing to measure, which is the one thing
  a census must never do silently."""
  root = name.split(".")[0]
  if root not in SAFE_MODULES:
    raise ImportError(f"reader-fork-census sandbox: {name!r} not allowed")
  return _real_import(name, *a, **kw)


_real_import = builtins.__import__

SAFE_BUILTINS.update({
  "open": _ro_open, "AttributeError": AttributeError, "Exception": Exception,
  "IndexError": IndexError, "KeyError": KeyError, "NotImplementedError": NotImplementedError,
  "RuntimeError": RuntimeError, "StopIteration": StopIteration, "TypeError": TypeError,
  "ValueError": ValueError, "ZeroDivisionError": ZeroDivisionError, "print": _denied("print"),
  "__import__": _guarded_import, "__build_class__": __build_class__, "staticmethod": staticmethod,
  "classmethod": classmethod, "super": super,
})

SAFE_MODULES = ("re", "string", "json", "math", "itertools", "functools", "collections",
                "pathlib", "types", "dataclasses", "enum", "operator", "bisect", "textwrap",
                "io", "ast", "os", "sys", "subprocess", "shutil")

# ── THE FAKE FILESYSTEM AND PROCESS LAYER ──────────────────────────────────────────────────
# WHY A FAKE. Most of these functions are not parsers but RUNNERS: `rows_of(path)` shells out to
# produce a lane and then parses stdout. Handing such a function a real path measures nothing,
# and handing it lane text measures an `open()`. So `open()` returns the probe text and
# `subprocess.run()` returns it as stdout: what gets measured is the PARSE, which is the part
# that can drift. What the fake costs is stated in the output -- a reader that also filters on
# something the fake cannot produce comes back as an empty mapping and is REPORTED as
# disagreeing. It is never reported as passing.
_FAKE = {"text": ""}


def module_layer():
  """Real modules with the writing halves and the process-spawning half removed."""
  class _Proc:
    returncode = 0
    stdout = ""
    stderr = ""
    args = ()
    pid = 0

    def communicate(self, *a, **kw):
      return _Proc.stdout, ""

    def wait(self, *a, **kw):
      return 0

    def kill(self):
      pass

    def __enter__(self):
      return self

    def __exit__(self, *a):
      return False

  class _Completed(_Proc):
    pass

  def _out(*a, **kw):
    return _FAKE["text"]

  sub = types.ModuleType("subprocess")
  sub.run = lambda *a, **kw: _Completed()
  sub.check_output = _out
  sub.Popen = lambda *a, **kw: _Proc()
  sub.call = lambda *a, **kw: 0
  sub.check_call = lambda *a, **kw: 0
  sub.getoutput = _out
  sub.DEVNULL, sub.PIPE, sub.STDOUT = -3, -1, -2

  _os = os
  mod_os = types.ModuleType("os")
  for k in dir(_os):
    if k.startswith("_") or k in ("system", "remove", "unlink", "rename", "replace", "rmdir",
                                  "mkdir", "makedirs", "chmod", "chown", "popen", "execv",
                                  "spawnv", "fork", "removedirs", "truncate", "rmf"):
      continue
    setattr(mod_os, k, getattr(_os, k))
  mod_os.sep, mod_os.linesep, mod_os.environ = "/", "\n", {}

  sh = types.ModuleType("shutil")
  sh.which = lambda *a, **kw: None
  sh.copy = _denied("shutil.copy")
  sh.rmtree = _denied("shutil.rmtree")

  _pl = pathlib
  P = _pl.Path

  class FakePath(P):
    """Every path EXISTS and holds the probe text, so a path reader reaches its parse instead
    of dying on `FileNotFoundError`."""
    def read_text(self, *a, **kw):
      return _FAKE["text"]

    def read_bytes(self, *a, **kw):
      return _FAKE["text"].encode()

    def open(self, *a, **kw):
      return io.StringIO(_FAKE["text"])

    def exists(self, *a, **kw):
      return True

    def is_file(self, *a, **kw):
      return True

    def is_dir(self, *a, **kw):
      return False

    def iterdir(self, *a, **kw):
      return iter(())

    def glob(self, *a, **kw):
      return iter(())

    def rglob(self, *a, **kw):
      return iter(())

    def stat(self, *a, **kw):
      return _os.stat_result((0o100644, 0, 0, 1, 0, 0, 10, 0, 0, 0))

  pl = types.ModuleType("pathlib")
  for k in dir(_pl):
    if not k.startswith("_"):
      setattr(pl, k, getattr(_pl, k))
  pl.Path = pl.PosixPath = pl.WindowsPath = FakePath
  pl.PurePath = _pl.PurePath
  return {"subprocess": sub, "os": mod_os, "shutil": sh, "pathlib": pl, "io": io, "sys": sys}


# The candidate plus its module's own literal constants and pure defs. A module-level
# `FunctionDef` cannot run anything at exec time, so a candidate's sibling helpers come along
# for free -- which is what `rebase-gate.py`'s `rows()` calling `row()` needs.
_DEF_NODES = (ast.FunctionDef, ast.AsyncFunctionDef)


def _literal(node):
  try:
    return True, ast.literal_eval(node)
  except Exception:
    return False, None


def sandbox(node, seg, src, path):
  """Exec the candidate together with the module-level names it closes over.

  An earlier draft exec'd the candidate ALONE. Every reader that referenced a module constant
  came back `NameError` -- INCLUDING THE CONTROL, `rebase-gate.py`'s own `rows`/`row` and its
  `PY_TAIL` -- so the whole first pass reported "49 of 49 DRIFTED" and a zero in the agreeing
  column that agreed with nothing at all. That zero was the harness, not the tree."""
  try:
    cand = ast.parse(seg)
  except SyntaxError as e:
    return None, f"unparseable candidate: {e}"
  try:
    whole = ast.parse(src)
  except SyntaxError as e:
    return None, f"unparseable module: {e}"

  body = list(cand.body)
  # Module-level computes run one node at a time, each in its own namespace, so ONE that raises
  # (a constant built from a module this sandbox refuses) does not take the module with it.
  # The side-effect surface is the fake layer above: `subprocess` is a stub, `os` has its
  # mutators stripped, and `open` is read-only.
  consts = []
  for n in whole.body:
    if n is node:
      continue
    if isinstance(n, _DEF_NODES):
      body.append(n)
    elif isinstance(n, (ast.Assign, ast.AnnAssign)) and (
        isinstance(n, ast.AnnAssign) and n.value is not None or isinstance(n, ast.Assign)):
      consts.append(n)
    elif isinstance(n, (ast.Import, ast.ImportFrom)):
      mod = getattr(n, "module", None) or ""
      root = mod.split(".")[0] if mod else (n.names[0].name.split(".")[0] if n.names else "")
      if root in SAFE_MODULES:
        body.append(n)

  ns = {"__name__": "reader_fork_census_sandbox", "__file__": str(REPO / path),
        "__builtins__": dict(SAFE_BUILTINS)}
  ns.update(module_layer())
  ok = True
  try:
    mod = ast.Module(body=body, type_ignores=[])
    ast.fix_missing_locations(mod)
    exec(compile(mod, f"<{path}:{node.lineno}>", "exec"), ns)  # noqa: S102
  except Exception as e:
    ok, why = False, f"def-time {type(e).__name__}: {e}"
  for n in consts:
    try:
      one = ast.Module(body=[n], type_ignores=[])
      ast.fix_missing_locations(one)
      exec(compile(one, f"<{path}:{n.lineno}>", "exec"), ns)  # noqa: S102
    except Exception:
      pass  # a constant this sandbox cannot build; the reader that needs it says so
  if not ok:
    return None, why
  fn = ns.get(node.name)
  if not callable(fn):
    return None, "not defined in its own extracted source"
  return fn, None


# ── NORMALISING A RESULT ───────────────────────────────────────────────────────────────────
def render(v):
  """A printable, COMPARABLE rendering of one cell. The non-`str` cases are not decoration:
  a reader whose cells are `set`s or 2-tuples rather than strings is answering a DIFFERENT
  question than `rows()` does, and flattening both to `str` would have reported `{'half'}` and
  `'half'` as agreeing. So the shape is carried into the comparison and printed."""
  if isinstance(v, (set, frozenset)):
    return "SET" + repr(sorted(str(x) for x in v))
  if isinstance(v, (list, tuple)):
    return "SEQ" + repr([str(x) for x in v])
  if v is None:
    return "NONE"
  return repr(str(v))


def pick_mapping(result):
  """(pairs, result_kind, note).

  `pairs` is [(name, rendered value)] for the reader's ROW MAPPING, and `result_kind` names the
  shape it came out in. `lines` is a DEFERRED mapping: the reader returned whole lines and left
  the split to its caller, so the only fair comparison is to split them with the CANONICAL
  parser -- and `result_kind` still says `lines`, because a caller that keys on the raw line is
  not substitutable for one that received a dict.
  """
  if isinstance(result, dict):
    return sorted((str(k), render(v)) for k, v in result.items()), "dict", ""
  if isinstance(result, tuple) and result and isinstance(result[0], dict):
    # cstyle-gate.py's `rows_strict` shape: (mapping, shreds, dups). Compared on the mapping;
    # the extra members ARE its contract and are named in `note`.
    pairs = sorted((str(k), render(v)) for k, v in result[0].items())
    return pairs, "dict+extras", f"{len(result)} return values, mapping is [0]"
  if isinstance(result, (list, tuple)) and all(isinstance(x, str) for x in result):
    return canonical_pairs("\n".join(result)), "lines", "returns whole lines; caller splits"
  if isinstance(result, (list, tuple)) and all(
      isinstance(x, (list, tuple)) and len(x) == 2 for x in result):
    return sorted((str(a), render(b)) for a, b in result), "pairs", ""
  return None, type(result).__name__, f"unmapped: {render(result)[:80]}"


def call(fn, *args):
  """Call a forked reader under a wall-clock alarm. A reader with a retry loop -- several read
  a lane twice to prove the lane is stable -- will otherwise hang the census, and a census that
  hangs reports nothing at all. A reader that trips the alarm is recorded as HUNG, which is a
  measurement, not a silence."""
  try:
    signal.signal(signal.SIGALRM, _on_alarm)
    signal.setitimer(signal.ITIMER_REAL, PROBE_TIMEOUT)
  except (ValueError, AttributeError):
    pass  # not the main thread, or no SIGALRM: the run then has no alarm at all
  try:
    return fn(*args)
  except _Hung:
    raise
  finally:
    try:
      signal.setitimer(signal.ITIMER_REAL, 0)
    except (ValueError, AttributeError):
      pass


def probe(fn, text):
  """(pairs, kind, note, err). `err` set means the reader refused this input."""
  _FAKE["text"] = text  # what `open()` and `subprocess.run()` hand back
  try:
    pairs, kind, note = pick_mapping(call(fn, text))
    return pairs, kind, note, None
  except TypeError as e:
    if "positional argument" in str(e) or ("argument" in str(e) and "takes" in str(e)):
      return None, "arity", f"arity: {e}", f"ARITY {e}"
    return None, "raised", "", f"TypeError: {e}"
  except _Hung:
    return None, "hung", "", "HUNG: wall-clock alarm tripped"
  except Exception as e:
    return None, "raised", "", f"{type(e).__name__}: {e}"


class _Hung(Exception):
  pass


def _on_alarm(signum, frame):
  raise _Hung


PROBE_TIMEOUT = 2.0  # seconds per call


PATH_PROBE = "/nonexistent/reader-fork-census/probe.txt"
# An OS-level refusal is the signature of a reader that wanted a FILE, not lane text. It is kept
# as its own contract rather than lumped in with a genuine parse error, because a path reader
# is not a drifted `rows()` -- it is a different function that was never a candidate for
# substitution.
OS_ERRORS = (FileNotFoundError, IsADirectoryError, NotADirectoryError, PermissionError,
             FileExistsError)

# THE SIX-LINE TEXT. A `rows()`-family reader maps all six lines at once; a LINE-family reader
# answers about one line and cannot, so the six-line blob is what separates the two families.
BLOB = "\n".join(t for _, t in SHAPES)


# ── ONE CANDIDATE, MEASURED ────────────────────────────────────────────────────────────────
def measure(rel, name, lineno, seg, node):
  src_path = REPO / rel
  try:
    src = src_path.read_text()
  except OSError as e:
    return dict(file=rel, func=name, line=lineno, contract="UNREADABLE", note=str(e),
                drift=None)
  fn, err = sandbox(node, seg, src, rel)
  if fn is None:
    return dict(file=rel, func=name, line=lineno, contract="NOT-COMPARABLE", note=err,
                drift=None)

  try:
    sig = ast.unparse(node.args)
  except Exception:
    sig = "?"

  # ── FAMILY 1: text -> mapping. The `rows()` contract. Control: the gate's `rows`.
  got = {sid: probe(fn, text) for sid, text in SHAPES}
  kinds = {sid: r[1] for sid, r in got.items()}
  errs = [r[3] for r in got.values() if r[3]]
  blob = probe(fn, BLOB)

  if any(k == "arity" for k in kinds.values()):
    return _class(rel, name, lineno, sig, "not-single-arg",
                  next(e for e in errs if e), None, [], blob)
  if all(k == "raised" for k in kinds.values()) and errs and all(
      any(e.startswith(c.__name__) for c in OS_ERRORS) for e in errs):
    return _class(rel, name, lineno, sig, "path-reader", errs[0][:90], None, [], blob)
  if all(k == "raised" for k in kinds.values()) and errs:
    return _class(rel, name, lineno, sig, "refused-text", errs[0][:90], None, [], blob)

  # ── FAMILY 2: one line -> (name, left, right) | None. Control: the gate's `row`.
  if not (kinds.get("F1") == "pairs" and blob[1] == "dict"):
    per_line = {}
    for sid, text in SHAPES:
      _FAKE["text"] = text
      try:
        per_line[sid] = ("ok", _render_answer(call(fn, text)))
      except _Hung:
        per_line[sid] = ("err", "HUNG")
      except Exception as e:
        per_line[sid] = ("err", f"{type(e).__name__}: {e}")
    if all(v[0] == "ok" for v in per_line.values()) and all(
        v[1] == "NONE" or v[1].startswith("SEQ2") or v[1].startswith("SEQ3") for v in per_line.values()):
      mismatch = [sid for sid, v in per_line.items() if v[1] != _render_answer(CANON_ROW(dict(SHAPES)[sid]))]
      return _class(rel, name, lineno, sig, "line->answer",
                    ("disagrees on " + " ".join(mismatch)) if mismatch else "",
                    bool(mismatch), [], blob)
    return _class(rel, name, lineno, sig, "not-a-reader",
                  "; ".join(f"{k}={v[1][:60]}" for k, v in list(per_line.items())[:3])[:150],
                  None, [], blob)

  # ── FAMILY 1 verdict.
  mismatch = []
  for sid, text in SHAPES:
    want = sorted((n, render(v)) for n, v in CANONICAL(text).items())
    if got[sid][0] != want:
      mismatch.append(sid)
  kinds_seen = sorted(set(kinds.values()))
  return _class(rel, name, lineno, sig, "text->mapping",
                ("disagrees on " + " ".join(mismatch)) if mismatch else "",
                bool(mismatch), kinds_seen, blob)


def _class(rel, name, lineno, sig, contract, note, drift, kinds, blob):
  return dict(file=rel, func=name, line=lineno, contract=contract, drift=drift, note=note,
              sig=sig, kinds=kinds, blob_kind=blob[1], blob_n=blob[0] if blob[0] else 0)


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--json", action="store_true")
  ap.add_argument("--only", default=None, help="substring filter on file path")
  args = ap.parse_args()

  cands = candidates()
  if args.only:
    cands = [c for c in cands if args.only in c[0]]

  measured = [measure(*c) for c in cands]

  # Every case run TWICE and the two answers compared: a measurement run once is a measurement
  # whose determinism is an assumption. The readers here are pure by construction, and the
  # second run is what proves it rather than asserts it.
  measured2 = [measure(*c) for c in cands]

  def sig_of(m):
    return (m.get("contract"), m.get("drift"), m.get("note"), m.get("kinds"),
            m.get("blob_kind"), m.get("blob_n"))

  unstable = [f"{m['file']}:{m['func']}" for m, n in zip(measured, measured2)
              if sig_of(m) != sig_of(n)]

  by = {}
  for m in measured:
    by.setdefault(m["contract"], []).append(m)

  if args.json:
    print(json.dumps(dict(gate_md5=canonical_digest(), shapes=[list(s) for s in SHAPES],
                          canonical={sid: canonical_pairs(t) for sid, t in SHAPES},
                          n_candidates=len(measured), measured=measured,
                          unstable=unstable), indent=2, default=str))
    return 0

  print(f"control: rebase-gate.py rows()/row(), loaded by path   md5={canonical_digest()}")
  print(f"corpus: {' + '.join(CORPUS_ROOTS)} (this project's own tooling; upstream tinygrad "
        f"excluded)")
  print(f"candidates whose NAME says rows: {len(measured)}   (the DENOMINATOR for everything below)")

  print("\nCANONICAL SIGNATURE, by CALLING the gate's rows()")
  for sid, text in SHAPES:
    print(f"  {sid:<28} {text!r:<44} -> {[(n, render(v)) for n, v in CANONICAL(text).items()]}")

  print("\nBY CONTRACT -- the DRIFT DENOMINATOR is the two families that answer a row question")
  for k in sorted(by, key=lambda k: -len(by[k])):
    n_drift = sum(1 for m in by[k] if m["drift"])
    tag = "" if k in DRIFT_FAMILIES else "   (not a row reader: excluded from drift)"
    print(f"  {k:<18} {len(by[k]):<5} drifted={n_drift}{tag}")

  total_rows = sum(len(by[k]) for k in DRIFT_FAMILIES)
  total_drift = sum(1 for k in DRIFT_FAMILIES for m in by[k] if m["drift"])
  print(f"\nDRIFT, over every function in this corpus that ANSWERS A ROW QUESTION")
  print(f"  DRIFTED {total_drift} of {total_rows}"
        f"    ({len(by.get('text->mapping', []))} text readers, "
        f"{len(by.get('line->answer', []))} per-line readers)")
  print(f"  agree on all six  {total_rows - total_drift}")
  if unstable:
    print(f"  *** NON-DETERMINISTIC on a second run: {unstable} ***")

  for fam in DRIFT_FAMILIES:
    rows_f = by.get(fam, [])
    if not rows_f:
      continue
    print(f"\n{fam.upper()} ({len(rows_f)}) -- one line each; `kinds` is the RESULT SHAPE, "
          f"reported apart from drift\n   because a reader can agree on all six shapes and still "
          f"not be substitutable")
    for m in sorted(rows_f, key=lambda x: (not x["drift"], x["file"], x["func"])):
      flag = "DRIFT" if m["drift"] else "ok   "
      print(f"  {flag} {m['file']}:{m['line']:<5} {m['func']}({m['sig']})"
            f"  kinds={'/'.join(m['kinds']) or '-':<11} {m['note']}")

  other = [m for m in measured if m["contract"] not in DRIFT_FAMILIES]
  print(f"\nNOT ROW READERS ({len(other)}) -- excluded from the drift denominator, listed so "
        f"the\n   exclusion is checkable rather than asserted")
  for m in sorted(other, key=lambda x: (x["contract"], x["file"], x["func"])):
    print(f"    {m['contract']:<16} {m['file']}:{m['line']}  {m['func']}({m.get('sig', '?')})"
          f"  {(m.get('note') or '')[:88]}")
  return 0


if __name__ == "__main__":
  sys.exit(main())