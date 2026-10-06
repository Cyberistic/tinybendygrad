#!/usr/bin/env python3
r"""deadarm.py -- A TREE-WIDE CENSUS OF EMITTING SOURCE LINES THAT NEVER EXECUTE.

    .venv/bin/python .agents/slop/deadarm/deadarm.py                 # the census, all instruments
    .venv/bin/python .agents/slop/deadarm/deadarm.py --selftest      # the plant matrix
    .venv/bin/python .agents/slop/deadarm/deadarm.py --selftest --file F
    .venv/bin/python .agents/slop/deadarm/deadarm.py --only nv       # substring filter

WHY IT EXISTS.  `.agents/slop/nvdup/NVDUP.md:62` measured the general form of this project's
worst defect:

    D2 = a dead `try:` arm.  IT COSTS 0 -- and that is the point: A LINE THAT DOESN'T EXECUTE HAS
    NO OUTPUT LINE TO COUNT, SO IT IS INVISIBLE TO EVERY DUPLICATE INSTRUMENT IN THIS PROJECT,
    INCLUDING THE FIXER THAT WAS WRITTEN TO CLEAN UP AFTER EXACTLY THIS.

So unobservable code cannot be found by counting observable code; you have to count ABSENCE.
`nvdup-deadarm.py` does that for ONE file with a TEXTUAL selector (`^\s*row(`).  This is the same
census with the selector replaced by a SEMANTIC one, so it reaches the other 874 instruments:

  1. `ast` finds the instrument's WRITER FUNCTIONS -- the functions that reach a write primitive
     (`print`, `.write`, `os.write`, `sys.stdout.write`, ...), closed transitively over calls to
     the instrument's own functions.  That is the generalization of "the thing named `row`".
  2. `ast` then finds every CALL SITE of a writer, and maps it to the LINE OF THE ENCLOSING
     STATEMENT (`ast` stmt, not the `Call`), because `sys.settrace` line events are
     statement-granular: they fire on the statement's first line, so a `Call` node's own
     `lineno` is the wrong key whenever a call is nested in a comprehension or spans lines.
  3. The instrument is COPIED TO $TMPDIR AND RUN THERE.  The live tree is only ever read, for
     the reason `.agents/slop/portexec/run-kernel.sh:22` records: a hard-coded absolute `ROOT=`
     means a lane cannot be planted against a copy, and four plants would have been vacuous.

THE DENOMINATOR IS THE POINT.  An instrument that emits NOTHING is NOT an instrument with N dead
sites -- it is an instrument whose lane never ran, and reporting it as "all dead" is the
`Bool.pick` failure mode in a new costume (a tool that reports everything dead reports nothing).
So a census cell with zero emitted rows is printed as `NO LANE` with its reason and is EXCLUDED
from both the dead count and the denominator.  The numbers this file prints are:

    instruments examined / instruments with emitting sites / instruments that produced a lane
    / dead emitting lines

TWO CENSUSES, AND NEITHER SUBSTITUTES FOR THE OTHER (`nvdup/stage4-plants.md` §2):

    SITE census  a writer call in the SOURCE whose statement line the tracer never saw execute
    LINE census  a `name=` printed more than once in the LANE  (= `dup-gate.py`'s, re-run)

A duplicate is not a dead site.  A row emitted without the writer (a `print` at top level, a
`sys.stdout.write`, an f-string passed to a lambda) is a site the semantic selector CAN see and
`nvdup`'s textual one could not -- which is why the two selectors disagree and both are reported.
"""
import argparse, ast, atexit, collections, io, contextlib, json, os, pathlib, re, runpy, subprocess, sys
import tempfile, time

REPO = pathlib.Path(__file__).resolve().parents[3]
SLOP = REPO / ".agents/slop"
PY = sys.executable

# write primitives.  `X.write(` and `print(` cover the tree; `emit(`-shaped names are DISCOVERED,
# not guessed, because a guessed list is exactly the "textual selector" limit this file removes.
WRITE_METHODS = {"write", "writelines", "flush", "print", "write_str"}
WRITE_ATTRS = {"print", "write", "writelines"}          # module.attr  (sys.stdout.write)
WRITE_FUNCS = {"print", "write"}                        # bare name   (print, os.write)

TIMEOUT = float(os.environ.get("DEADARM_TIMEOUT", "60"))


# ---------------------------------------------------------------- writers
def _callee_name(node):
  """`row(...)` -> 'row';  `self.row(...)` -> 'row';  `sys.stdout.write(..)` -> 'write';
  `IO.print(..)` -> 'print'.  The LAST attribute is the one a reader would look for."""
  f = node.func
  if isinstance(f, ast.Name):
    return f.id
  if isinstance(f, ast.Attribute):
    return f.attr
  return None


def _calls_in(node):
  for sub in ast.walk(node):
    if isinstance(sub, ast.Call):
      yield sub


def _is_write(c):
  nm = _callee_name(c)
  return nm is not None and (nm in WRITE_METHODS or nm in WRITE_ATTRS or nm in WRITE_FUNCS)


def _writes(node):
  """Does this subtree reach a write primitive?"""
  return any(_is_write(c) for c in _calls_in(node))


# ---------------------------------------------------------------- sites
def _stmt_lines(tree):
  """{Call node -> lineno of the INNERMOST STATEMENT that contains it}.

  `sys.settrace` line events fire once per statement, on the statement's first line, so a `Call`
  node's own `lineno` is the WRONG key the moment a call sits inside a comprehension, a `with`,
  or spans several lines.  Climbing to the innermost enclosing `stmt` is what makes the tracer's
  line set and the source's site set the same set.  (`ast` has no parent pointers, so the map is
  built once by a full walk.)"""
  parent = {}
  for node in ast.walk(tree):
    for child in ast.iter_child_nodes(node):
      parent[child] = node
  out = {}
  for node in ast.walk(tree):
    if not isinstance(node, ast.Call):
      continue
    cur = parent.get(node)
    while cur is not None and not isinstance(cur, ast.stmt):
      cur = parent.get(cur)
    out[node] = cur.lineno if cur is not None else node.lineno
  return out


def emitting_sites(path):
  """({(line, text)} , {sink names}, error-or-None, {line -> enclosing def}) for one instrument.

  The fourth value is the ANSWER TO THE MOST IMPORTANT QUESTION THIS TOOL CAN ASK, and it is why
  the census has two columns instead of one.  A dead emitting line is one of two different things:

    IN-CALLED-FN    the enclosing function WAS ENTERED and the statement did not run.  That is the
                    `D2` the brief is about -- a `try:` arm, a guarded branch, a diagnostic nobody
                    reaches -- and it costs 0 measurements because it emits nothing.
    IN-UNCALLED-FN  the enclosing function was NEVER ENTERED.  That is *either* a helper nothing
                    calls (also `D2`, one level up) *or* the census's own blindness: the instrument
                    was run with NO ARGV, so every `--selftest` / `--plant` / `--verbose` branch in
                    it is unreachable.  `cstyle-gate.py` reads 43 dead sites with no arguments and
                    every one of them is inside a flag-gated report; calling those "dead code" would
                    be the `Bool.pick` failure in a new costume, so they are counted separately and
                    never in the headline."""
  src = pathlib.Path(path).read_text(errors="replace")
  try:
    tree = ast.parse(src)
  except SyntaxError as e:
    return set(), set(), f"SyntaxError: {e}", {}
  sinks, funcs, direct, indirect = writer_functions(tree)
  stmt_line = _stmt_lines(tree)
  owner = {}
  for fn in ast.walk(tree):
    if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
      for sub in ast.walk(fn):
        owner[sub] = fn
  lines = src.splitlines()
  out = set()
  for c in _calls_in(tree):
    nm = _callee_name(c)
    if nm is None:
      continue
    if not (nm in WRITE_METHODS or nm in WRITE_ATTRS or nm in WRITE_FUNCS or nm in sinks):
      continue
    ln = stmt_line.get(c, c.lineno)
    out.add((ln, lines[ln - 1].strip()[:96] if 0 < ln <= len(lines) else ""))
  encl = {}
  for c in _calls_in(tree):
    ln = stmt_line.get(c, c.lineno)
    fn = owner.get(c)
    encl[ln] = fn.lineno if fn is not None else None       # None == module level
  return out, sinks | direct, None, encl


def writer_functions(tree):
  """{name -> node} for every function that can PUT A LINE IN THE LANE, closed transitively.

  Two mechanisms, because the tree uses both and one is not enough:

  DIRECT  the function reaches a write primitive (`print`, `.write`, `os.write`, ...).

  INDIRECT it MUTATES a module-level global that some direct writer later reads.  This is the
  shape 70 of the instruments actually use -- `nv-oracle.py:27-30` is

      ROWS = []
      def row(nm, v):
          ROWS.append((nm, str(v)))

  and the printing happens once, at the end of `main`.  A selector that stops at the first hop
  finds neither `row` (it does not print) nor `main` (it does not print) and reports a
  337-emitting-line instrument as having 10 sites -- WHICH IS EXACTLY WHAT IT DID ON THE FIRST
  RUN OF THIS FILE, and the DISARM cell caught it.
  """
  funcs = {n.name: n for n in ast.walk(tree)
           if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
  globals_ = set()
  for n in tree.body:
    if isinstance(n, ast.Assign):
      globals_.update(t.id for t in n.targets if isinstance(t, ast.Name))
    elif isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name):
      globals_.add(n.target.id)

  parent = {}
  for node in ast.walk(tree):
    for child in ast.iter_child_nodes(node):
      parent[child] = node
  enclosing_fn = {}
  for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
      for sub in ast.walk(node):
        enclosing_fn[sub] = node

  write_calls = [c for c in _calls_in(tree) if _is_write(c)]
  direct = {n for n in funcs if any(_is_write(c) for c in _calls_in(funcs[n]))}
  # EVERY name a write can READ.  Module level included, which is the case that matters here:
  # `nv-oracle.py:1206-1207` prints `ROWS` from the top level, so a closure over function bodies
  # alone finds nothing and reports a 337-emitting-line instrument as having 10 sites.
  consumed = set()
  for c in write_calls:
    cur = parent.get(c)
    while cur is not None and not isinstance(cur, ast.stmt):
      cur = parent.get(cur)
    for scope in (cur, enclosing_fn.get(c)):
      if scope is not None:
        consumed |= {x.id for x in ast.walk(scope) if isinstance(x, ast.Name)}
  mutated = {n for n in funcs if _mutates_global(funcs[n], globals_)}
  indirect = {n for n in mutated
              if {x.id for x in ast.walk(funcs[n]) if isinstance(x, ast.Name)} & consumed}
  sinks = direct | indirect
  # one more closure hop: a sink that calls a sink is still a sink (`row` -> `emit` -> `print`).
  by_name = collections.defaultdict(set)
  for name, fn in funcs.items():
    for c in _calls_in(fn):
      nm = _callee_name(c)
      if nm in funcs:
        by_name[name].add(nm)
  changed = True
  while changed:
    changed = False
    for n in list(sinks):
      for callee in by_name.get(n, ()):
        if callee in funcs and callee not in sinks and (callee in direct or callee in indirect):
          sinks.add(callee)
          changed = True
  return sinks, funcs, direct, indirect


def _mutates_global(fn, globals_):
  for x in ast.walk(fn):
    if isinstance(x, ast.Call) and isinstance(x.func, ast.Attribute) \
       and x.func.attr in {"append", "extend", "insert", "add", "update", "setdefault", "pop"} \
       and isinstance(x.func.value, ast.Name) and x.func.value.id in globals_:
      return True
    if isinstance(x, ast.Assign):
      for t in x.targets:
        if isinstance(t, ast.Name) and t.id in globals_:
          return True
        if isinstance(t, ast.Subscript) and isinstance(t.value, ast.Name) \
           and t.value.id in globals_:
          return True
  return False


# ---------------------------------------------------------------- trace
RUNNER = r'''
import contextlib, io, json, os, runpy, sys
target, out = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.dirname(os.path.abspath(target)))   # the instrument's SIBLINGS, which is
                                                               # what `import patch_not_apply` in
                                                               # `dsp2-mutate.py:1` needs and what
                                                               # a bare $TMPDIR copy denied it

def once(traced):
  ex, called, lane, err = [], [], io.StringIO(), io.StringIO()
  def tr(frame, event, arg):
    if frame.f_code.co_filename != target:
      return None
    if event == "line":
      ex.append(frame.f_lineno)
    elif event == "call":
      called.append(frame.f_code.co_firstlineno)
    return tr
  old = sys.argv
  sys.argv = [target]
  if traced:
    sys.settrace(tr)
  try:
    with contextlib.redirect_stdout(lane), contextlib.redirect_stderr(err):
      runpy.run_path(target, run_name="__main__")
    kind = "lane" if lane.getvalue().strip() else "no-lane"
  except SystemExit as e:
    code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
    kind = "lane" if lane.getvalue().strip() else ("ok" if code == 0 else "crash SystemExit(%d)" % code)
  except BaseException as e:
    kind = "crash %s: %s" % (type(e).__name__, e)
  finally:
    sys.settrace(None)
    sys.argv = old
  return sorted(set(ex)), sorted(set(called)), lane.getvalue(), kind

# THE PLAIN RUN IS FIRST, and that order is a measurement: the traced run taxes every call in
# every imported file, so it costs ~20s against ~7s, and running it cold also pays for importing
# tinygrad.  One subprocess, two runs, and the comparison between them is the CONTROL -- a census
# whose traced lane prints something other than the instrument's own lane is measuring a different
# program, which is the `py=`-column plant shape (`NVDUP.md:110`).
p_ex, p_called, p_lane, p_kind = once(False)
t_ex, t_called, t_lane, t_kind = once(True)
json.dump({"executed": t_ex, "called": t_called, "lane": t_lane, "kind": t_kind,
           "plain_lane": p_lane, "plain_kind": p_kind,
           "control": "same" if p_lane == t_lane else "CONTROL FAILED"}, open(out, "w"))
'''


def trace_run(path, out, cwd=REPO, timeout=TIMEOUT):
  """Run `path` in a CHILD PROCESS -- twice, plain then traced -- and return the census.

  ⚠ WHY A CHILD PROCESS AND NOT `signal.alarm`.  The first version ran the trace IN-PROCESS with
  `signal.alarm` as the timeout, and five of eight shards died with rc 139 (SIGSEGV): the alarm
  raises a Python exception at an arbitrary bytecode boundary and several of these instruments are
  inside ctypes/numpy when it lands.  A harness that segfaults reports nothing, so the census is
  reported as `crash`, which is a WRONG answer rather than a missing one.  The parent now owns the
  deadline and SIGKILLs, which is the only timeout that cannot corrupt the measurement.
  """
  env = dict(os.environ, PYTHONPATH=f"{cwd}:{REPO}")
  try:
    r = subprocess.run([PY, "-c", RUNNER, str(path), str(out)], cwd=str(cwd),
                       capture_output=True, text=True, timeout=timeout, env=env,
                       stdin=subprocess.DEVNULL)
  except subprocess.TimeoutExpired:
    return set(), set(), "", "hang", f"timeout {timeout}s", "n/a"
  if not out.exists():
    return set(), set(), "", "crash", f"child rc={r.returncode}: {(r.stderr or '')[-160:]}", "n/a"
  try:
    d = json.loads(out.read_text())
  except ValueError as e:
    return set(), set(), "", "crash", f"runner wrote unreadable json: {e}", "n/a"
  kind, detail = d["kind"], ""
  if d["control"] != "same" and d["plain_lane"].strip():
    kind, detail = "harness", "the traced lane differs from the instrument's own lane"
  return set(d["executed"]), set(d["called"]), d["lane"], kind, detail, d["control"]


def run_once(path, timeout=TIMEOUT):
  """A SUBPROCESS run first: it proves the file executes AT ALL, and it is how a lane whose
  in-process import order differs from the shell's still gets censused.  Returns (rc, text)."""
  env = dict(os.environ, PYTHONPATH=str(REPO))
  try:
    r = subprocess.run([PY, str(path)], cwd=str(REPO), capture_output=True, text=True,
                       timeout=timeout, env=env, stdin=subprocess.DEVNULL)
  except subprocess.TimeoutExpired:
    return None, ""
  return r.returncode, (r.stdout or "")


_SHADOW = []


def shadow_root():
  r"""A `$TMPDIR` tree with the REPO'S SHAPE, every file a symlink, so an instrument that resolves
  paths from `__file__` still finds them -- and so a file it WRITES lands in the shadow.

  ⚠ THIS WAS THE FIRST SWEEP'S BIGGEST BLIND SPOT, and it was the HARNESS's, not the tree's.  The
  first version copied each instrument to `$TMPDIR/tmpXXXX/<name>.py` and ran it there, which is
  what `nvdup-deadarm.py` does and what `run-kernel.sh:22` says to do -- and 1,396 of the 1,714
  instruments with emitting sites came back `crash`, most of them with a path in the message:

      FileNotFoundError: '.../tmp29vv0soh/tinybendygrad/codegen/kernel.bend'

  because an instrument that walks up from `__file__` finds a $TMPDIR directory that has none of
  the tree in it.  **A census whose harness breaks the instrument reports a COVERAGE number as a
  DEADNESS number**, which is the `Bool.pick` failure wearing a different hat.  MEASURED on the
  three cells that decided it: `kn-ops-mutate.py` went `crash` -> `lane` with **21 dead sites**,
  `elf_reloc_probe.py` `crash` -> `lane` with 4, `dsp2-mutate.py` `crash` -> `crash` (it wants
  argv, honestly).  It is the general form of `run-kernel.sh:22`'s lesson: an instrument must be
  RUNNABLE against a copy before anything can be planted at it, and it must be runnable against a
  copy that still LOOKS like the tree.

  ONE shadow per PROCESS, not per instrument: the mirror is ~15k symlinks and building it per
  instrument cost 4s of a 4s cell.  The instrument's own file is replaced by a real copy each
  time, and every other file stays a symlink into the live tree, which is never written."""
  if _SHADOW:
    return _SHADOW[0]
  root = pathlib.Path(tempfile.gettempdir()) / f"deadarm-shadow-{os.getpid()}"
  if root.exists():
    import shutil
    shutil.rmtree(root, ignore_errors=True)
  root.mkdir(parents=True, exist_ok=True)
  for p in sorted(REPO.iterdir()):
    if p.name in (".git", ".jj", "__pycache__", ".venv", "references", "runs"):
      continue
    if p.is_dir() and not p.is_symlink() and p.name in (".agents", "tinybendygrad"):
      _mirror(p, root / p.name)
    else:
      os.symlink(p, root / p.name)
  _SHADOW.append(root)
  atexit.register(lambda: __import__("shutil").rmtree(root, ignore_errors=True))
  return root


def _mirror(src, dst):
  dst.mkdir(parents=True, exist_ok=True)
  for p in sorted(src.iterdir()):
    if p.name in ("__pycache__", ".git"):
      continue
    if p.is_dir() and not p.is_symlink():
      _mirror(p, dst / p.name)
    else:
      os.symlink(p, dst / p.name)


def census_one(path, label=None):
  sites, writers, err, encl = emitting_sites(path)
  rec = {"label": label or pathlib.Path(path).name, "path": str(path), "sites": sites,
         "writers": sorted(writers), "error": err, "kind": None, "detail": "",
         "dead": set(), "dead_in_called": set(), "live": set(), "rows": 0, "dup": {},
         "lane": "", "control": "n/a"}
  if err or not sites:
    rec["kind"] = "no-sites" if not err else "unparsable"
    rec["detail"] = err or ""
    return rec
  root = shadow_root()
  with tempfile.TemporaryDirectory() as td:
    work = pathlib.Path(td)
    src = pathlib.Path(path).resolve()
    # A PLANT is not in the repo -- it is a $TMPDIR file -- and `relative_to(REPO)` would raise.
    # It goes in a synthetic folder INSIDE the shadow instead, so it still sees a tree.
    rel = src.relative_to(REPO) if REPO in src.parents \
        else pathlib.Path(".deadarm-synthetic") / src.name
    tmp = root / rel
    tmp.parent.mkdir(parents=True, exist_ok=True)
    if tmp.is_symlink() or tmp.exists():
      tmp.unlink()
    tmp.write_text(pathlib.Path(path).read_text(errors="replace"))
    out = work / "trace.json"
    executed, called, text, kind, detail, control = trace_run(tmp, out, root)
    rec["kind"], rec["detail"], rec["control"] = kind, detail, control
    if kind != "lane":
      return rec
    rec["dead"] = {s for s in sites if s[0] not in executed}
    # THE SPLIT.  `encl[line]` is the enclosing def's own `def` line, or None at module level; the
    # tracer recorded every `def` line it ENTERED, so membership is an observation, not a guess.
    rec["dead_in_called"] = {s for s in rec["dead"]
                             if encl.get(s[0]) is None or encl[s[0]] in called}
    rec["live"] = {s for s in sites if s[0] in executed}
    names = [l.split("=", 1)[0] for l in text.splitlines() if "=" in l]
    c = collections.Counter(names)
    rec["rows"] = len(names)
    rec["dup"] = {k: v for k, v in c.items() if v > 1}
    rec["lane"] = text
    # INVARIANT, checked every run and not assumed: a line the tracer SAW execute can never be in
    # the dead set.  A violation here is the `Bool.pick` failure: the tool claiming a live line is
    # dead.  Printed, never swallowed.
    bad = rec["dead"] & rec["live"]
    if bad:
      rec["detail"] = f"INVARIANT VIOLATION {len(bad)} site(s) both live and dead"
  return rec


# ---------------------------------------------------------------- census
def instruments(pattern=None):
  """Every `.py` under `.agents/slop` -- the whole instrument population, not just the 70 that
  happen to use the name `row`.  `.sh` gates are counted separately: `sys.settrace` cannot see a
  bash process, so they are NOT TRACEABLE and pretending otherwise is how a denominator rots."""
  out = []
  for p in sorted(SLOP.rglob("*.py")):
    if "__pycache__" in p.parts:
      continue
    if pattern and pattern not in str(p):
      continue
    out.append(p)
  return out


def report(rec, verbose=False):
  print(f"  {rec['label']:<34} sites={len(rec['sites']):>4}  {rec['kind']:<11} "
        f"rows={rec['rows']:>5}  DEAD={len(rec['dead']):>3}"
        f" (of which in a CALLED fn: {len(rec['dead_in_called']):>3})"
        f"  dup={len(rec['dup']):>3}  ctl={rec.get('control', 'n/a'):<4}"
        + (f"  {rec['detail']}" if rec["detail"] else ""))
  if verbose or rec["dead"]:
    for ln, txt in sorted(rec["dead"]):
      print(f"        DEAD SITE  line {ln:<5} {txt}")


def census(paths, verbose=False):
  recs = []
  for p in paths:
    t0 = time.time()
    r = census_one(p)
    r["secs"] = round(time.time() - t0, 1)
    recs.append(r)
    report(r, verbose)
  return recs


def tally(recs):
  traced = [r for r in recs if r["kind"] == "lane"]
  kinds = collections.Counter(r["kind"].split(" ")[0] for r in recs)
  return {"examined": len(recs), "with_sites": sum(1 for r in recs if r["sites"]),
          "traced": len(traced),
          "dead_sites": sum(len(r["dead"]) for r in traced),
          "dead_in_called": sum(len(r["dead_in_called"]) for r in traced),
          "dead_instruments": sum(1 for r in traced if r["dead"]),
          "dead_in_called_instruments": sum(1 for r in traced if r["dead_in_called"]),
          "sites_in_traced": sum(len(r["sites"]) for r in traced),
          "dup_sites": sum(len(r["dup"]) for r in traced), "kinds": kinds}


# ---------------------------------------------------------------- selftest
PLANT_ANCHOR = '\nif __name__ == "__main__":\n'


def selftest(src, label):
  r"""FIVE CELLS, each with its EXPECTATION printed beside its MEASUREMENT.  The DISARM is the
  first one and it is MEASURED, never typed: a control whose base is a hardcoded 0 cannot prove it
  would have fired, and three controls on this project were found disarmed."""
  base = census_one_from_text(src, label, "clean")
  # The duplicate plants REUSE A NAME THE CLEAN LANE ALREADY PRINTS, read out of that lane's own
  # output.  A plant that invents its own name (`deadarm_plant_dup`) measures nothing: the line
  # census is a MULTIPLICITY census and a name of multiplicity 1 is not a duplicate.  That is the
  # first version's FAIL, and the way it failed is the `Bool.pick` shape -- a check that returns
  # the right answer for the wrong reason and looks green for it.
  seen = [l.split("=", 1)[0] for l in _lane_of(base).splitlines() if "=" in l]
  dupname = seen[0] if seen else "row"
  dead_plant = ('try:\n'
                '    1 / 0\n'
                '    row("deadarm_plant_dead", "unreached")\n'
                'except ZeroDivisionError:\n'
                f'    row("{dupname}", "reached")\n')
  live_plant = f'row("{dupname}", "reached_again")\n'
  dup_plant = f'row("{dupname}", "reached_again")\n'
  longhand = f'print("{dupname}=longhand")\n'
  if src.count(PLANT_ANCHOR) != 1:
    raise SystemExit(f"plant anchor matched {src.count(PLANT_ANCHOR)} times, expected 1")
  cells = {}
  for nm, plant in (("dead", dead_plant), ("live", live_plant), ("dup", dup_plant),
                    ("longhand", longhand)):
    # ⚠ BEFORE THE ANCHOR, NOT AFTER IT: the anchor carries the `if __name__` line itself, so
    # appending drops the plant INSIDE that block (nvdup/stage4-plants.md §4.2).
    cells[nm] = census_one_from_text(src.replace(PLANT_ANCHOR, plant + PLANT_ANCHOR, 1), label, nm)
  print("[selftest] DISARM first: the UNPLANTED real file.  A control whose base is typed 0 is a")
  print("           control that cannot fire, so the base is measured and printed with the cells.")
  for r in (base, *cells.values()):
    report(r)
  b, bd = len(base["dead"]), len(base["dup"])
  checks = [
    ("DISARM: the unplanted real file is censusable and has NO dead site",
     base["kind"] == "lane" and len(base["dead"]) == 0),
    ("DEAD: a row() in an unreachable try-arm IS seen (0 -> 1)",
     len(cells["dead"]["dead"]) == b + 1),
    ("LIVE: a row() that DOES execute is not called dead (stays 0)",
     len(cells["live"]["dead"]) == b and len(cells["live"]["live"]) > b),
    ("DUP: a duplicate is NOT a dead site -- site census stays, LINE census rises",
     len(cells["dup"]["dead"]) == b and len(cells["dup"]["dup"]) == bd + 1),
    ("LONGHAND: a row emitted by `print`, NOT by the writer fn, IS a site the semantic selector "
     "sees and nvdup's textual one could not",
     len(cells["longhand"]["dead"]) == b and len(cells["longhand"]["dup"]) == bd + 1),
  ]
  print()
  print("  NOTE the `dead` cell's dup=1: the unreachable row costs 0 DEAD measurements and its")
  print("  except-arm sibling simultaneously creates a live duplicate.  The two censuses see")
  print("  different things in one cell, which is why neither replaces the other.")
  ok = True
  for desc, got in checks:
    print(f"  [{'PASS' if got else 'FAIL'}] {desc}: {got}")
    ok = ok and got
  print(f"DEADARM SELFTEST {'OK' if ok else 'FAILED'}")
  return ok


def _lane_of(rec):
  """The lane text of a censused record.  Kept on the record so the plants can READ the name the
  real lane already prints instead of inventing one."""
  return rec.get("lane", "")


def census_one_from_text(text, label, tag):
  with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
    f.write(text)
    tmp = pathlib.Path(f.name)
  try:
    r = census_one(tmp, label=f"{label}:{tag}")
  finally:
    tmp.unlink()
  return r


# ---------------------------------------------------------------- main
def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--file", help="census ONE instrument, read-only; with --selftest, the HOST "
                                 "whose body the plants are grafted onto")
  ap.add_argument("--only", help="substring filter on the path")
  ap.add_argument("--verbose", action="store_true")
  ap.add_argument("--report", help="write the full table here (TSV)")
  ap.add_argument("--shard", default="0/1", help="K/N -- the census is 875 instruments and one "
                                                 "process traces one at a time, so the sweep is "
                                                 "sharded and the tables merged")
  a = ap.parse_args()
  if a.file:
    rec = census_one(pathlib.Path(a.file))
    report(rec, True)
    return 1 if rec["dead"] else 0
  if a.selftest:
    host = pathlib.Path(a.file) if a.file else SLOP / "nv-oracle.py"
    return 0 if selftest(host.read_text(), host.name) else 1
  k, n = (int(x) for x in a.shard.split("/"))
  paths = [p for i, p in enumerate(instruments(a.only)) if i % n == k]
  print(f"DEAD-ARM CENSUS -- shard {k}/{n}, {len(paths)} instrument(s) under "
        f"{SLOP.relative_to(REPO)}")
  recs = census(paths, a.verbose)
  t = tally(recs)
  print(f"\n  shard {k}/{n}: instruments examined {t['examined']}"
        f"   with emitting sites {t['with_sites']}"
        f"   TRACEABLE {t['traced']}")
  print(f"    dead emitting lines        {t['dead_sites']} in {t['dead_instruments']} instrument(s)"
        f"   out of {t['sites_in_traced']} sites in those lanes")
  print(f"    of which IN A CALLED def   {t['dead_in_called']} in "
        f"{t['dead_in_called_instruments']} instrument(s)"
        f"   <- the D2 class; the rest sit in defs the no-argv lane never entered")
  print(f"    duplicate names in the same lanes {t['dup_sites']}"
        f"   <- the OTHER census, not a substitute")
  print("  outcome kinds: " + ", ".join(f"{k}={v}" for k, v in sorted(t["kinds"].items())))
  if a.report:
    # ⚠ THE DETAIL IS COLLAPSED TO ONE LINE, and the first version did not, so a crash message
    # carrying a compiler diagnostic -- which is most of them -- wrote a MULTI-LINE row into a
    # TSV.  1,387 of 3,424 rows were malformed, `csv.DictReader` silently produced `None` fields,
    # and the merge reported a plausible total over a corrupted table.  A newline in a
    # tab-separated field is the same species as the hand-typed `py=` column: it does not fail, it
    # just makes the reader's numbers mean something else.
    flat = lambda s: " ".join(str(s).split())
    with open(a.report, "w") as fh:
      fh.write("instrument\tsites\tkind\trows\tdead\tdead_in_called\tdup\tdetail\n")
      for r in recs:
        fh.write(f"{r['path']}\t{len(r['sites'])}\t{flat(r['kind'])}\t{r['rows']}\t"
                 f"{len(r['dead'])}\t{len(r['dead_in_called'])}\t{len(r['dup'])}\t"
                 f"{flat(r['detail'])}\n")
      for r in recs:
        for ln, txt in sorted(r["dead"]):
          fh.write(f"DEAD\t{r['path']}:{ln}\t{flat(txt)}\n")
    print(f"  wrote {a.report}")
  return 1 if t["dead_sites"] else 0


if __name__ == "__main__":
  sys.exit(main())