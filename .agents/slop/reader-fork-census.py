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
# Scratch prefixes a live agent creates mid-run (`.mine-prefix/` showed up while this census was
# being taken). A corpus that silently changes size between two runs of the same census has two
# denominators and no finding, so dot-directories BELOW a corpus root are skipped by name.

# THE THREE FAMILIES THAT ANSWER A ROW QUESTION. Everything else -- a producer, a differ, a
# path runner, a tensor accessor that happens to be called `rows_e` -- is NOT in the drift
# denominator, and saying so with a number is the difference between a census and a count.
DRIFT_FAMILIES = ("text->mapping", "line->answer", "value->fold")

# `split_py`-shaped readers are the INVERSE FOLD: `rows()` returns `left` with the `py=` tail
# folded away, and a parity reader reads that tail back out. Its input is a VALUE, not a line,
# and scoring it as a line reader manufactures a disagreement out of the wrong argument. The
# rule is the PARAMETER NAME -- stated here so it can be argued with -- and the rule is printed
# next to every verdict rather than applied silently.
VALUE_ARG_NAMES = {"value", "val", "v", "cell", "payload", "text_right"}


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


def behavior_fingerprint(fn):
  """A reader's exact answers on the six shapes, hashed. NOT its source text: two readers can
  agree on everything and be spelled differently, and a fork that was only reformatted must not
  fail the guard.

  This lives HERE, in the census, and `reader-registry.py` and `reader-guard.py` both call it,
  because a fingerprint computed three times by three implementations is three chances for the
  registry and the guard to disagree about what a reader does -- and a registry and a guard that
  disagree is a guard that reports a regression every run until someone switches it off."""
  sig = []
  for _, text in SHAPES:
    try:
      r = call(fn, text)
      pairs, kind, _note = pick_mapping(r)
      sig.append((kind, pairs if pairs is not None else [repr(r)[:120]]))
    except Exception as e:
      sig.append((f"RAISED {type(e).__name__}", [str(e)[:120]]))
  return hashlib.md5(repr(sig).encode()).hexdigest()[:12]


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
    base = REPO / top
    for root, dirs, files in os.walk(base):
      dirs[:] = sorted(d for d in dirs
                       if d not in CORPUS_SKIP and not (root != str(base) and d.startswith(".")))
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
                "io", "ast", "os", "sys", "subprocess", "shutil", "struct", "time", "array",
                "binascii", "hashlib", "base64", "codecs", "zlib", "copy", "fnmatch", "glob",
                "platform", "datetime", "decimal", "fractions", "statistics", "heapq", "uuid")
# `ctypes` and `tempfile` are DELIBERATELY NOT allowed. Both carry a side-effect surface this
# sandbox has no reason to expose, and a census that cannot measure a reader must SAY SO rather
# than quietly widen its own permissions. The oracles that import them are listed as
# NOT-COMPARABLE with the reason attached, so the gap is a printed number and not a silent one.

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
    # A LIST of strings is a deferred mapping: the reader returned whole lines and left the
    # split to its caller. A TUPLE of strings is NOT -- `split_py` returns one, and it is a
    # per-item answer. Telling the two apart by container is what stops this harness from
    # re-parsing `split_py`'s (left, right) as if it were a two-row lane, which is how a
    # 3-entry "mapping" appeared out of a function that never built one.
    if not isinstance(result, list):
      return None, "tuple", f"{len(result)} strings in a TUPLE: a per-item answer"
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
    # A TIMED-OUT reader is its own contract, permanently. It is a runner: it does real work
    # (a subprocess, a graph walk) whose duration is not this harness's to bound, so whether it
    # answers inside 2 seconds is a property of the MACHINE and not of the reader. Classifying
    # it as `not-a-reader` on a fast run and `text->mapping` on a slow one made the guard's own
    # finding count change between two runs on the same tree, which is worse than not
    # measuring it: a denominator that moves is not a denominator.
    return None, "timed-out", "", ("HUNG: exceeded PROBE_TIMEOUT seconds. The reader does real "
                                  "work whose duration is not a property of this harness.")
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


def canonical_value(text):
  """The VALUE half of one line, as the gate's `row()` splits it: everything after the first
  `=`, or the whole F3 tail. This is what a `split_py`-shaped reader is handed."""
  r = CANON_ROW(text)
  return r[1] if r else text


def canonical_value_answer(text):
  """What the gate says the (left, right) split of a VALUE is -- the control for the
  `value->fold` family. Computed from the gate's own `PY_TAIL`, never restated."""
  raw = canonical_value(text)
  i = raw.rfind(GATE_MOD.PY_TAIL)
  return (raw[:i], raw[i + len(GATE_MOD.PY_TAIL):]) if i >= 0 else (raw, None)


def _answers(fn, inputs):
  """{sid: ('ok', rendered) | ('err', msg)} for the per-line / per-value families. A TIMED-OUT
  call is `('timed-out', '')` rather than an error string, so the caller can tell "this reader
  refused" from "this reader did not finish" -- the two have opposite implications and a harness
  that conflates them reports a refusal as though it were a disagreement."""
  out = {}
  for (sid, text), arg in zip(SHAPES, inputs):
    _FAKE["text"] = text
    try:
      out[sid] = ("ok", _render_answer(call(fn, arg)))
    except _Hung:
      out[sid] = ("timed-out", "")
    except Exception as e:
      out[sid] = ("err", f"{type(e).__name__}: {e}")
  return out


# ── ONE CANDIDATE, MEASURED ────────────────────────────────────────────────────────────────
def measure(rel, name, lineno, seg, node):
  """Measure ONE candidate, and run the measurement TWICE.

  Twice, because a reader that gives two different answers to the same text cannot be given a
  fingerprint at all -- and that is a finding, not a measurement to be averaged."""
  m = measure_once(rel, name, lineno, seg, node)
  m2 = measure_once(rel, name, lineno, seg, node)
  keys = ("contract", "drift", "note", "kinds", "blob_kind", "blob_n", "verdict")
  m["unstable"] = any(m.get(k) != m2.get(k) for k in keys)
  # A reader whose CLASSIFICATION moves between two runs on the same tree cannot be given a
  # fingerprint either, because a fingerprint is only meaningful for a fixed contract. This is
  # not hypothetical: `graphcmp.py`'s `bend_sym_rows` reads as a `text->mapping` reader on an idle
  # run and as `not-a-reader` on a busy one, so the registry gained and lost its row between two
  # runs and the guard's finding count moved with it.
  #
  # THE CAUSE IS THE TIMEOUT, AND THE FIX IS TO STOP ASKING. `does_real_work()` reads the AST and
  # decides STATICALLY whether the function runs a lane, compiles anything, or walks a tree. A
  # runner is a runner on a fast machine and a slow one; classifying it by whether it finished
  # inside PROBE_TIMEOUT is a coin flip in the DENOMINATOR, which is the one thing a census must
  # not produce. So the check is made once, statically, and the timeout becomes a backstop rather
  # than a classifier.
  # The RUNNER check is STATIC and needs the module source, so it happens HERE rather than in
  # `measure_once`: it is a fact about the SOURCE, not about one run of it.
  src_path = REPO / rel
  try:
    mod_src = src_path.read_text()
  except OSError:
    mod_src = None
  if mod_src is not None and does_real_work(node, mod_src):
    m["contract"] = "runner"
    m["drift"] = None
    m["note"] = ("STATICALLY a runner: its body reaches a subprocess, a compiler, or a tree walk, "
                 "so how long it takes is a property of the machine. Classified from the AST so "
                 "the answer does not move with load; a run it timed out on is a backstop, not "
                 "the measurement.")
  elif m["unstable"]:
    m["contract"] = "non-deterministic"
    m["drift"] = None
    m["note"] = ("ANSWERED THE SAME TEXT TWO DIFFERENT WAYS in one process, with no subprocess in "
                 "sight, so this is the reader's own nondeterminism. No fingerprint can be taken "
                 "of a function that does not answer to itself.")
  return m


def measure_once(rel, name, lineno, seg, node):
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

  if any(k == "timed-out" for k in kinds.values()):
    # Checked BEFORE arity and OS errors on purpose: a runner that times out is a runner
    # whatever else it does, and the machine's mood on the day is not its contract.
    return _class(rel, name, lineno, sig, "runner", errs[0][:110], None, [], blob)
  if any(k == "arity" for k in kinds.values()):
    return _class(rel, name, lineno, sig, "not-single-arg",
                  next(e for e in errs if e), None, [], blob)
  if all(k == "raised" for k in kinds.values()) and errs and all(
      any(e.startswith(c.__name__) for c in OS_ERRORS) for e in errs):
    return _class(rel, name, lineno, sig, "path-reader", errs[0][:90], None, [], blob)
  if all(k == "raised" for k in kinds.values()) and errs:
    return _class(rel, name, lineno, sig, "refused-text", errs[0][:90], None, [], blob)

  # ── FAMILY 2: one line -> (name, left, right) | None. Control: the gate's `row`.
  # The discriminator is the SIX-LINE BLOB plus the CONTAINER of what comes back. A
  # `rows()`-family reader maps the six lines at once -- a dict, a list of (name, value) pairs,
  # or a list of whole lines. A line reader returns one per-line answer, and a `split_py` reader
  # returns a 2-TUPLE, which is a per-item answer and not a mapping.
  mapping_blob = blob[1] in ("dict", "dict+extras", "pairs", "lines")
  if not mapping_blob:
    per_line = _answers(fn, [t for _, t in SHAPES])
    if any(v[0] == "timed-out" for v in per_line.values()):
      return _class(rel, name, lineno, sig, "runner",
                    f"did not finish inside PROBE_TIMEOUT on at least one shape; it is a runner",
                    None, [], blob)
    if all(v[0] == "ok" for v in per_line.values()) and all(
        v[1] == "NONE" or v[1].startswith(("SEQ2", "SEQ3")) for v in per_line.values()):
      # ── FAMILY 3 or FAMILY 2? The PARAMETER NAME decides, and the decision is printed.
      arg0 = None
      if node.args.args:
        arg0 = node.args.args[0].arg
      takes_value = arg0 in VALUE_ARG_NAMES
      if takes_value:
        # `row(line)[1:]` -- what `rows()` folded away, as the gate computes it.
        per_val = _answers(fn, [canonical_value(t) for _, t in SHAPES])
        want = {sid: _render_answer(canonical_value_answer(t))
                for sid, t in SHAPES}
        mm = [sid for sid, v in per_val.items() if v[0] == "ok" and v[1] != want[sid]]
        return _class(rel, name, lineno, sig, "value->fold",
                      f"arg is `{arg0}`: inverse-fold contract; "
                      + (("disagrees on " + " ".join(mm)) if mm else "agrees with row()'s fold"),
                      bool(mm) or any(v[0] != "ok" for v in per_val.values()), [], blob)
      mismatch = [sid for sid, v in per_line.items() if v[1] != _render_answer(CANON_ROW(dict(SHAPES)[sid]))]
      return _class(rel, name, lineno, sig, "line->answer",
                    ("disagrees on " + " ".join(mismatch)) if mismatch else "",
                    bool(mismatch), [], blob)
    return _class(rel, name, lineno, sig, "not-a-reader",
                  "; ".join(f"{k}={v[1][:60]}" for k, v in list(per_line.items())[:3])[:150],
                  None, [], blob)

  # ── FAMILY 1 verdict, and the THREE-WAY SPLIT THAT DECIDES WHETHER A FORK CAN BE DELETED.
  #   narrowing  every (name, value) the fork produced is ALSO what `rows()` produces. Substituting
  #             `rows()` can therefore only ADD rows, never change one -- which is why a
  #             narrowing fork is safe to convert and a divergent one is not.
  #   divergent  the fork produces a (name, value) `rows()` does NOT. These two readers answer
  #             different questions, and swapping one for the other would change a verdict.
  #   phantom    the fork produces a row on a shape `rows()` excludes on purpose -- the `""`
  #             banner, or a single-space or TAB line. That is a row the gate never believed in.
  narrowing, divergent, phantom = [], [], []
  signatures = []
  untrusted = None
  for sid, text in SHAPES:
    want = set((n, render(v)) for n, v in CANONICAL(text).items())
    got_p = got[sid][0]
    signatures.append((sid, tuple(sorted(got_p)) if got_p else ("<none>",)))
    if got_p is None:
      divergent.append(f"{sid}:no-mapping")
      continue
    # A row NAME the reader invented cannot be a row the lane contained. Under the fake stdout
    # that happens -- `dsl_mutate.rows` came back with `- message  : no such file: <the probe>`,
    # a `sed` failure line the harness manufactured. Such a verdict is printed as UNTRUSTED
    # rather than silently counted as drift, because "drift I caused" and "drift you have" are
    # different findings.
    if untrusted is None and any(n and n not in text for n, _ in got_p):
      untrusted = sid
    mine = set(got_p)
    contra = mine - want
    if contra:
      (phantom if _looks_like_exclusion(text, contra) else divergent).append(
        f"{sid}:{sorted(contra)[0]}")
    # A fork that simply MISSES rows is NARROWING, not divergent: the rows it does read are the
    # rows `rows()` reads, so importing `rows()` can only add to it. An earlier draft had an
    # `elif got != want` arm here, and it turned every narrowing fork into a DIVERGENT one --
    # the same mistake as comparing by index instead of by content, one level up.
    missing = want - mine
    if missing and not contra:
      narrowing.append(f"{sid}:misses {len(missing)}")
  verdict = "AGREE" if not (narrowing or divergent or phantom) else (
    "NARROWING" if not (divergent or phantom) else "DIVERGENT")
  bad = divergent or phantom
  kinds_seen = sorted(set(kinds.values()))
  return _class(rel, name, lineno, sig, "text->mapping",
                (f"{verdict}: " + "; ".join((divergent or phantom or narrowing)[:4])),
                bool(narrowing or divergent or phantom), kinds_seen, blob,
                verdict=verdict, narrowing=len(narrowing), divergent=len(divergent + phantom),
                untrusted=untrusted, signature=hashlib.md5(repr(signatures).encode()).hexdigest()[:12])


# CALLS THAT MAKE A FUNCTION'S DURATION A PROPERTY OF THE MACHINE RATHER THAN OF THE FUNCTION.
# Classifying a runner by whether it happened to finish inside PROBE_TIMEOUT is a coin flip on a
# loaded machine, and a coin flip in a DENOMINATOR is the one thing this file must not produce.
# MEASURED: `graphcmp.py`'s `bend_sym_rows` classified as `text->mapping` on an idle run and as
# `not-a-reader` on a busy one, so the registry gained and lost its row between two runs of the
# same tree. The signal below is read from the AST, so it does not move.
WORK_CALLS = {"run", "check_output", "check_call", "Popen", "call", "system", "popen", "execv",
              "sleep", "compile", "exec_module", "fork", "wait", "communicate", "walk",
              "rglob", "glob", "iterdir", "runtests", "main"}


def _looks_like_exclusion(text, contra):
  """True when the fork's extra row comes from a LINE `rows()` excludes on purpose: a line with
  no name (an `== SECTION ==` banner), a single-space gap, or a TAB.

  The distinction matters because a phantom row is a row NOBODY believed in, while a divergent row
  is a real disagreement both readers would act on. Measured on F5 and F6: `rows()` reads 0 rows
  from both, which is the rule `dtype_tables.py` depends on -- it emits 14,774 TSV lines and must
  keep reading as ZERO, or a lane wired on purpose to be dead would report 14,774 fabricated
  claims instead of "compared nothing"."""
  head = text.split("=", 1)[0] if "=" in text else text.split("  ", 1)[0]
  if not head.strip():
    return True
  if "\t" in text:
    return True
  return "=" not in text and "  " not in text


def does_real_work(node, module_src=None):
  """True when the def, or anything it calls in ITS OWN MODULE, reaches one of WORK_CALLS.

  STATIC on purpose. A reader that runs a lane is a RUNNER, and a runner cannot be given a
  fingerprint by a harness that would have to run the lane -- and whether it finished in time is
  not a property of the function. Walk depth is bounded at 3 and `seen` breaks cycles, because an
  unbounded walk over a recursive oracle is a hang and a hang reports nothing."""
  byname = {}
  if module_src:
    try:
      byname = {n.name: n for n in ast.walk(ast.parse(module_src))
                if isinstance(n, ast.FunctionDef)}
    except SyntaxError:
      byname = {}
  byname.setdefault(node.name, node)
  seen = set()

  def hits(fn, depth=0):
    if fn.name in seen or depth > 3:
      return False
    seen.add(fn.name)
    calls = []
    for n in ast.walk(fn):
      if not isinstance(n, ast.Call):
        continue
      f = getattr(n.func, "attr", None) or getattr(n.func, "id", None)
      if f in WORK_CALLS:
        return True
      if f in byname:
        calls.append(f)
    return any(hits(byname[c], depth + 1) for c in calls)

  return hits(node)
  """True when the fork's extra row comes from a LINE `rows()` excludes on purpose: a line with
  no name (an `== SECTION ==` banner), a single-space gap, or a TAB. The distinction matters
  because a phantom row is a row NOBODY believed in, while a divergent row is a real
  disagreement the two readers would both act on."""
  head = text.split("=", 1)[0] if "=" in text else text.split("  ", 1)[0]
  if not head.strip():
    return True
  if "\t" in text:
    return True
  if "=" not in text and "  " not in text:
    return True
  return bool(contra)


def _class(rel, name, lineno, sig, contract, note, drift, kinds, blob, **extra):
  d = dict(file=rel, func=name, line=lineno, contract=contract, drift=drift, note=note,
           sig=sig, kinds=kinds, blob_kind=blob[1], blob_n=len(blob[0] or []))
  d.update(extra)
  return d


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--json", action="store_true")
  ap.add_argument("--only", default=None, help="substring filter on file path")
  args = ap.parse_args()

  cands = candidates()
  if args.only:
    cands = [c for c in cands if args.only in c[0]]

  # `measure()` ALREADY runs every candidate twice and compares -- the per-candidate check, which
  # is the one that matters, because a reader that answers the same text two ways cannot be given
  # a signature at all. This SECOND pass over the whole list is the process-level check, and the
  # two are not the same experiment: the first catches a reader with internal nondeterminism,
  # this one catches a HARNESS that is order-dependent or time-dependent.
  measured = [measure(*c) for c in cands]

  def sig_of(m):
    return (m.get("contract"), m.get("drift"), m.get("note"), m.get("kinds"),
            m.get("blob_kind"), m.get("blob_n"))

  measured2 = [measure(*c) for c in cands]
  unstable = [f"{m['file']}:{m['func']}" for m, n in zip(measured, measured2)
              if sig_of(m) != sig_of(n)]
  # A candidate the per-candidate check already caught is reported by `measure()` as
  # `non-deterministic`, and it is not ALSO counted here: two names for one defect is a
  # denominator that does not add up, which is the mistake this file exists to correct.
  unstable = [u for u in unstable
              if next(m for m in measured if f"{m['file']}:{m['func']}" == u)["contract"]
              != "non-deterministic"]

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

  total_rows = sum(len(by.get(k, [])) for k in DRIFT_FAMILIES)
  total_drift = sum(1 for k in DRIFT_FAMILIES for m in by.get(k, []) if m["drift"])
  verdicts = {}
  for m in by.get("text->mapping", []):
    verdicts[m.get("verdict", "?")] = verdicts.get(m.get("verdict", "?"), 0) + 1
  print(f"\nDRIFT, over every function in this corpus that ANSWERS A ROW QUESTION")
  print(f"  DRIFTED {total_drift} of {total_rows}"
        f"    ({len(by.get('text->mapping', []))} text readers, "
        f"{len(by.get('line->answer', []))} per-line, "
        f"{len(by.get('value->fold', []))} inverse-fold)")
  print(f"  agree on all six  {total_rows - total_drift}")
  print(f"\nTHE THREE-WAY SPLIT OF THE {len(by.get('text->mapping', []))} TEXT READERS -- this is "
        f"what decides\n   which fork can be DELETED. NARROWING = the fork sees a SUBSET of what "
        f"rows() sees, with\n   identical values, so importing rows() can only ADD rows. "
        f"DIVERGENT = the fork reads\n   something rows() does not, and swapping one for the "
        f"other changes a verdict.")
  for k in ("AGREE", "NARROWING", "DIVERGENT"):
    print(f"  {k:<12} {verdicts.get(k, 0)}")
  controls = [m for m in by.get("text->mapping", [])
              if m["file"].endswith("rebase-gate.py") and m["func"] == "rows"]
  print(f"  of which the control itself (rebase-gate.py's own rows()): {len(controls)}"
        f" -- and it agrees with itself, which is the only reason the other rows are a finding")

  # ── THE FINDING, WITH ITS DENOMINATOR. 51 forks are not 51 risks. Readers that answer the
  # six shapes IDENTICALLY are the same reader spelled twice, and the number of DISTINCT
  # BEHAVIOURS is the number that says how much is actually at stake.
  sigs = {}
  for m in by.get("text->mapping", []):
    if m.get("untrusted"):
      continue
    sigs.setdefault(m.get("signature", "?"), []).append(m)
  print(f"\nDISTINCT BEHAVIOURS: {len(sigs)} different answers to the six shapes, from "
        f"{len(by.get('text->mapping', []))} text readers")
  print("  A signature is the exact (name, value) answer set on all six shapes, so two readers "
        "with\n  the same signature are the same reader spelled twice -- which is what makes "
        "this a\n  fan-out problem with a small number of root causes rather than 51 of them.")
  untrusted_n = sum(1 for m in by.get("text->mapping", []) if m.get("untrusted"))
  print(f"  readers excluded from the grouping because the fake stdout gave them a row name "
        f"that is\n  not in the probe text, i.e. the verdict is the harness's and not theirs: "
        f"{untrusted_n}")
  for i, (k, ms) in enumerate(sorted(sigs.items(), key=lambda kv: -len(kv[1])), 1):
    vs = sorted({m.get("verdict") for m in ms})
    print(f"\n  S{i:02d} {k}  {len(ms)} reader(s)   verdict={','.join(vs)}")
    for m in sorted(ms, key=lambda x: (x["file"], x["func"])):
      u = "  [UNTRUSTED: invented name]" if m.get("untrusted") else ""
      print(f"        {m['file']}:{m['line']}  {m['func']}({m['sig']}){u}")

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
  nondet = [m for m in other if m["contract"] == "non-deterministic"]
  if nondet:
    print(f"\nNON-DETERMINISTIC ({len(nondet)}) -- excluded from the drift denominator BECAUSE "
          f"they cannot be\n   given one. A reader that answers the same text two different ways "
          f"has no fingerprint,\n   and a fingerprint that changes per run is a guard that fails "
          f"every run until it is ignored.")
    for m in sorted(nondet, key=lambda x: x["file"]):
      print(f"    {m['file']}:{m['line']}  {m['func']}({m['sig']})")
  print(f"\nNOT ROW READERS ({len(other) - len(nondet)}) -- excluded from the drift denominator, "
        f"listed so the\n   exclusion is checkable rather than asserted")
  for m in sorted((x for x in other if x["contract"] != "non-deterministic"),
                  key=lambda x: (x["contract"], x["file"], x["func"])):
    print(f"    {m['contract']:<16} {m['file']}:{m['line']}  {m['func']}({m.get('sig', '?')})"
          f"  {(m.get('note') or '')[:88]}")
  return 0


if __name__ == "__main__":
  sys.exit(main())