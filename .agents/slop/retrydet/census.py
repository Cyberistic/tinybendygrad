#!/usr/bin/env python3
"""census.py -- THE CLASS: every retry loop in the tree that wraps a subprocess, and whether
it can tell a CRASH from an ANSWER.

POPULATION (doctrine 1: a population is a generator's own declaration, loaded by path, or a
directory walk -- never a hand list, a basename shape, or a suffix set).  Two denominators,
stated separately because they are different populations and conflating them is how sixteen
instruments reported a clean zero:

  TRACKED  `git ls-tree -r HEAD --name-only`   -- the tree. 7154 paths at HEAD c8d543324.
  WORKTREE os.walk(REPO), hidden+ignored ON    -- everything on the disk, including the 28k
             gitignored paths `git ls-files --others --exclude-standard` cannot see.

CLASS.  A `subprocess` call inside a `for`/`while` whose body re-invokes it.  For each, the
census answers ONE question and does not guess it:

  DOES THE LOOP'S CONTINUE-CONDITION READ THE CHILD'S OUTPUT?
    A loop that keeps going because the output was EMPTY is retry-on-empty.  A loop that keeps
    going because the exit status was NON-ZERO is retry-on-status.  A loop that keeps going on
    neither (a bare bounded attempt counter) retries EVERYTHING, which is the same class as
    retry-on-empty with less information.

  CAN IT TELL A CRASH FROM AN ANSWER?
    A loop distinguishes only if its continue-condition names something the child emits on a
    crash and does NOT emit on success.  bend emits `bend: memory fault (machine stack
    overflow?)` on fd 2 and exits 1 (references/bend/bend2/comp.ts:159-167, :3415, :3642-3645,
    :6337; gates/test.ts:55 and tests/io/stack_fault_trap.bend:59-60 pin it) -- that string IS
    the distinguisher.  "the stream is empty" is not, because bend also exits 1 having written
    nothing on a legal-but-empty run, and `check()` (main.ts:187-213) prints a version notice
    on stderr on ANY run, so stderr's mere NON-EMPTINESS is worthless.

Prints `rows` so it can be diffed; the caller owns the verdict.
"""
import ast
import json
import os
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]

SPAWN = {"run", "Popen", "call", "check_call", "check_output", "run_shell"}
# The two strings bend actually prints when the machine stack overflows.  Both land on fd 2
# and both exit 1; neither is a signal death, so `rc` is 1 and never -11/139/-9.
CRASH_TOKENS = ("machine stack overflow?", "machine stack overflowed")

EMPTY_TEST = re.compile(r"\bstdout\b|\bout\b|\boutput\b|\brows\b|\bgot\b|\blines\b"
                        r"|\bres\b|\bresult\b|\bcells\b|\brecord\b")
STATUS_TEST = re.compile(r"\breturncode\b|\bexit\b|\brc\b|\bstatus\b|\bfail")


def call_name(f: ast.expr) -> str:
  """`f` as dotted text.  MEASURED 2026-10-14: the first version of this census read
  `c.func.attr` unconditionally and DIED on the first bare `run(...)` call with
  `AttributeError: 'Name' object has no attribute 'attr'` -- a run that printed NO rows, so a
  caller that swallowed the traceback would have reported `the tree has 0 retry loops`.  A
  census that dies on its first file is a census that reports a clean zero."""
  if isinstance(f, ast.Attribute):
    return ast.unparse(f)
  return getattr(f, "id", ast.unparse(f))


def subprocess_calls(node: ast.AST) -> list[ast.Call]:
  """Every `subprocess.<spawn>` / bare spawn call reachable in `node`'s subtree."""
  out = []
  for n in ast.walk(node):
    if not isinstance(n, ast.Call):
      continue
    dotted = call_name(n.func)
    head, _, leaf = dotted.rpartition(".")
    if leaf in SPAWN and head in ("subprocess", "sp", "P"):
      out.append(n)
  return out


def spawn_args_text(node: ast.AST) -> str:
  return " ".join(ast.unparse(a) for a in ast.walk(node) if isinstance(a, ast.Constant)
                  and isinstance(a.value, str))


# The CLASS, stated as a shape an AST can decide and a reader can check by eye.
#
#   1. BOUNDED ATTEMPTS.  `for _ in range(<int>)` or `range(<name matching tries|attempt|retry>)`
#      -- an attempt COUNTER, not an iteration over inputs.  `for g in GATES:` is a corpus
#      sweep: it runs each gate once and its `if` branches are about that gate, not about
#      whether to try again.  Counting it as a retry is the same error as counting a row-dump
#      a `.txt` because of its extension.
#   2. SPAWNS INSIDE.  a `subprocess.*` call in the body.
#   3. THE EVIDENCE.  every `If`/`IfExp`/`While`/`Assert` TEST in the body, unparsed whole.
#      MEASURED DEFECT IN THIS CENSUS, FIXED BEFORE ANY NUMBER WAS QUOTED: the first version
#      collected its evidence from `ast.Compare` NODES, so it could not see
#          if not rows: continue
#      which is `ast.UnaryOp(Not, Name)` under an `ast.If` and carries NO Compare at all --
#      and `if not rows:` is how the SUBJECT ITSELF is written.  The instrument was blind to
#      exactly the class it was built for.
#   4. THE VERDICT.  three independent booleans, never collapsed into one score:
#        CONTINUES_ON_EMPTY  a branch test reads the child's OUTPUT and the branch does NOT
#                            leave the loop (no return/raise/break) -- i.e. an empty stream
#                            buys another attempt.
#        CONTINUES_ON_STATUS  the same for the child's EXIT STATUS.
#        NAMES_THE_CRASH     a branch test contains a string bend prints on a machine-stack
#                            overflow (references/bend/bend2/comp.ts ERRS[7]).  THIS is the
#                            only positive distinguisher in the tree, and the count is the
#                            number that matters.
ATTEMPT_BOUND = re.compile(r"^(tries|tries_|attempt|attempts|retries|retry|n|reps|runs|"
                           r"wait|MAX|RETRY|TRIES)$")


def attempt_bound(node: ast.For) -> tuple[bool, str]:
  """Is this `for`'s iterable an ATTEMPT COUNTER?  Returns (yes, the bound's source)."""
  it = node.iter
  if not (isinstance(it, ast.Call) and isinstance(it.func, ast.Name) and it.func.id == "range"):
    return False, ast.unparse(it)
  if not it.args:
    return False, "range()"
  a = it.args[0]
  if isinstance(a, ast.Constant) and isinstance(a.value, int) and 1 <= a.value <= 64:
    return True, ast.unparse(it)
  if isinstance(a, ast.Name) and ATTEMPT_BOUND.match(a.id):
    return True, ast.unparse(it)
  if isinstance(a, ast.BinOp):
    return True, ast.unparse(it)
  return False, ast.unparse(it)


def leaves_loop(node: ast.AST) -> bool:
  """Does this subtree leave the loop (return / raise / break / sys.exit / SystemExit)?"""
  for n in ast.walk(node):
    if isinstance(n, (ast.Return, ast.Raise, ast.Break)):
      return True
    if isinstance(n, ast.Call) and call_name(n.func) in ("sys.exit", "exit"):
      return True
    if isinstance(n, ast.ClassDef) and any(call_name(b.func) == "SystemExit" for b in n.bases):
      return True
  return False


class LoopFacts(ast.NodeVisitor):
  """Per attempt-counter loop that spawns: what it reads, what it can tell apart."""

  def __init__(self, tree: ast.Module) -> None:
    self.loops: list[dict] = []
    self.fns = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
    # THE DECLARED STRINGS, LOADED BY PATH -- which in a file means loaded from the module's
    # own assignment, not re-typed here.  MEASURED DEFECT IN THIS INSTRUMENT, the third and
    # subtlest: with call resolution in place the census STILL reported `names_the_crash=False`
    # on the fixed file, because `graphcmp.classify` writes `any(t in err for t in
    # STACK_OVERFLOW)` -- the token is in a module CONSTANT, one hop past the callee.  An
    # instrument that reads only literals inside branch tests cannot see a declared constant,
    # which is doctrine 1's rule arriving from the other direction: a population is the
    # generator's own declaration, and the token IS a declaration.
    self.consts: dict[str, tuple[str, ...]] = {}
    for n in tree.body:
      if not isinstance(n, (ast.Assign, ast.AnnAssign)):
        continue
      targets = n.targets if isinstance(n, ast.Assign) else [n.target]
      vals = self._string_tuple(getattr(n, "value", None))
      if vals:
        for t in targets:
          if isinstance(t, ast.Name):
            self.consts[t.id] = vals

  @staticmethod
  def _string_tuple(node: ast.expr | None) -> tuple[str, ...]:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
      return (node.value,)
    if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
      out = []
      for e in node.elts:
        if isinstance(e, ast.Constant) and isinstance(e.value, str):
          out.append(e.value)
      return tuple(out)
    return ()

  def expand(self, test: str) -> str:
    """`test` with every module constant it NAMES spliced in, so a declared token is seen.
    MEASURED: the first version wrote `for n in ast.walk(...) if test else []`, which parses
    as `for n in (walk(...) if test else [])` -- fine -- but the CALLER passed it the `(text,
    leaves)` TUPLES rather than the text, so `compile()` was handed a tuple.  Caught here, not
    downstream, and this sentence is the receipt."""
    extra: list[str] = []
    if test:
      try:
        for n in ast.walk(ast.parse(test, mode="eval")):
          if isinstance(n, ast.Name) and n.id in self.consts:
            extra += self.consts[n.id]
      except SyntaxError:
        pass
    return test + " ; " + " ; ".join(extra)

  def resolved_branches(self, node: ast.AST) -> list[tuple[str, bool]]:
    """The loop's branch tests PLUS the branch tests of any same-module function the loop
    CALLS, one level deep.

    MEASURED DEFECT IN THIS INSTRUMENT, and it is the one that matters: before this, the
    census answered `names_the_crash` by looking only inside the loop body.  The fix it was
    built to be able to find (`graphcmp.py`'s `classify`) puts the decision in a CALLEE, so
    the census reported `names_the_crash=False` on the file both BEFORE and AFTER the fix --
    an instrument blind to its own subject's remedy, which is doctrine 1's seventh member
    wearing a different hat.  Following one call level is enough here and is bounded; a full
    transitive walk is not needed to stop being blind to the shape that exists.
    """
    out = [(t, False) for t in self.local_branch_tests(node)]
    for call in ast.walk(node):
      if not isinstance(call, ast.Call):
        continue
      name = call_name(call.func).rpartition(".")[2]
      fn = self.fns.get(name)
      if fn is not None and fn is not node:
        out += [(t, False) for t in self.local_branch_tests(fn)]
    return out

  @staticmethod
  def local_branch_tests(node: ast.AST) -> list[str]:
    """Every `If`/`IfExp`/`While`/`Assert` test, and every comprehension filter, as source."""
    tests = []
    for t in ast.walk(node):
      if isinstance(t, (ast.If, ast.While, ast.Assert)) and getattr(t, "test", None) is not None:
        tests.append(ast.unparse(t.test))
      elif isinstance(t, ast.IfExp):
        tests.append(ast.unparse(t.test))
      elif isinstance(t, ast.comprehension):
        tests += [ast.unparse(i) for i in t.ifs]
    return tests

  def _record(self, node: ast.For) -> None:
    bounded, bound = attempt_bound(node)
    if not bounded:
      return
    calls = subprocess_calls(node)
    if not calls:
      return
    # (branch test source, does its branch LEAVE the loop).  A comprehension's `ifs` are raw
    # exprs with no body, so they enter as (text, False): a filter that does not exit is a
    # continue-condition.  MEASURED: the second version appended the comprehension's `ifs`
    # ELEMENTS as if they were branch NODES and read `.test` off them, dying with
    # `'Call' object has no attribute 'test'`.
    branches: list[tuple[str, bool]] = []
    for t in ast.walk(node):
      if isinstance(t, (ast.If, ast.While, ast.Assert)) and getattr(t, "test", None) is not None:
        # `ast.If.body` is a LIST of stmts.  MEASURED: an earlier version wrote
        # `... or ast.Pass()` as a fallback and, on an `ast.IfExp` (which has no `body`), `or`
        # fell through to the ast.Pass CLASS and `ast.walk` died with
        # `'list' object has no attribute '_fields'`.
        body = getattr(t, "body", None)
        outl = leaves_loop(ast.Module(body=body, type_ignores=[])) if isinstance(body, list) \
            else False
        branches.append((ast.unparse(t.test), outl))
      elif isinstance(t, ast.IfExp):
        branches.append((ast.unparse(t.test), False))
      elif isinstance(t, ast.comprehension):
        branches += [(ast.unparse(i), False) for i in t.ifs]
    src = ""
    try:
      src = ast.unparse(node)
    except Exception:
      src = ""
    # `branches_on_output` is POLARITY-FREE: some test inside the loop mentions the child's
    # output.  `empty_buys_another_attempt` records WHICH WAY the branch points, because
    # MEASURED the first version had the polarity backwards: it skipped every branch whose
    # body left the loop, so `if rows: return rows, notes` -- THE SUBJECT'S OWN SHAPE, where
    # the empty case is the FALL-THROUGH -- was scored `continues_on_empty=False`.  The
    # sentence the census has to support is "an empty stream buys another attempt", and that
    # is true for a branch that leaves the loop exactly as much as for one that does not: the
    # loop's CONTINUE path is the side that does not leave.
    # LOCAL: the loop body's own tests.  RESOLVED: those plus the tests of any same-module
    # function the loop calls (see `resolved_branches`).  Both are reported, and they are not
    # the same measurement -- after the subject's fix they disagree, and the disagreement is
    # the point: the decision moved into a callee, which the local view cannot see.
    resolved = self.resolved_branches(node)
    names_local = any(x in t for t, _ in branches for x in CRASH_TOKENS)
    names = any(x in self.expand(t) for t, _ in resolved for x in CRASH_TOKENS)
    on_out = [t for t, _ in branches if EMPTY_TEST.search(t)]
    on_st = [t for t, _ in branches if STATUS_TEST.search(t)]
    empty = bool(on_out)
    status = bool(on_st)
    leaves_on_out = any(outl for t, outl in branches if EMPTY_TEST.search(t))
    self.loops.append({
      "kind": type(node).__name__,
      "line": node.lineno,
      "bound": bound,
      "spawns": [f"{call_name(c.func)}@{c.lineno}" for c in calls],
      "branches_on_output": empty,
      "branches_on_status": status,
      "output_branch_leaves_loop": leaves_on_out,
      "names_the_crash": names,
      "names_the_crash_locally": names_local,
      "tests": [t[:200] for t, _ in branches][:8],
      "has_sleep": "sleep" in src,
      "raises_at_end": bool(re.search(r"\braise\b|sys\.exit|SystemExit", src)),
      "src": src[:900],
    })

  visit_For = _record
  visit_While = lambda self, node: None  # a `while` cannot express an attempt counter


def scan_py(text: str) -> list[dict]:
  try:
    tree = ast.parse(text)
  except SyntaxError:
    return []
  v = LoopFacts(tree)
  v.visit(tree)
  return v.loops


def named_tries_sig(text: str) -> list[int]:
  """A `tries=`/`attempts=`/`retries=` parameter default, by AST.  This is the ARTEFACT of the
  census, and it is where the thirty-minute number lives."""
  out = []
  for n in ast.walk(ast.parse(text)) if text else []:
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
      for a in list(n.args.args) + list(n.args.kwonlyargs):
        if re.search(r"tries|attempts|retries", a.arg):
          d = next((x for x in n.args.defaults if x is not None), None)
          kw = [x for x in n.args.kw_defaults if x is not None]
          for dd in ([d] if d is not None else []) + kw:
            if isinstance(dd, ast.Constant) and isinstance(dd.value, int):
              out.append({"fn": n.name, "line": n.lineno, "param": a.arg, "default": dd.value})
  return out


def timeout_values(text: str) -> list[dict]:
  out = []
  for n in ast.walk(ast.parse(text)):
    if not isinstance(n, ast.Call):
      continue
    for kw in n.keywords:
      if kw.arg == "timeout" and isinstance(kw.value, ast.Constant) \
         and isinstance(kw.value.value, (int, float)):
        out.append({"line": n.lineno, "timeout": kw.value.value})
  return out


def tracked() -> list[str]:
  return subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=REPO,
                        capture_output=True, text=True, timeout=60).stdout.split("\n")


def walktree() -> list[str]:
  out = []
  for d, dns, fns in os.walk(REPO):
    dns[:] = [x for x in dns if x not in (".git", "__pycache__")]
    for fn in fns:
      out.append(os.path.relpath(os.path.join(d, fn), REPO))
  return out


def census(names: list[str], label: str) -> list[dict]:
  rows = []
  for rel in names:
    if not rel.endswith(".py"):
      continue
    p = REPO / rel
    try:
      text = p.read_text(errors="replace")
    except OSError:
      continue
    if "subprocess" not in text or "range(" not in text:
      continue
    for lp in scan_py(text):
      rows.append({"population": label, "path": rel, **lp})
  return rows


def main() -> int:
  which = sys.argv[1] if len(sys.argv) > 1 else "all"
  pools = {}
  if which in ("all", "tracked"):
    pools["TRACKED"] = census(tracked(), "TRACKED")
  if which in ("all", "worktree"):
    pools["WORKTREE"] = census(walktree(), "WORKTREE")
  # The two numeric parameters, over the TRACKED tree only, because the tree is the claim.
  sig, tmo = [], []
  for rel in tracked():
    if not rel.endswith(".py"):
      continue
    try:
      text = (REPO / rel).read_text(errors="replace")
    except OSError:
      continue
    if "tries" in text or "timeout" in text:
      sig += [{"path": rel, **s} for s in named_tries_sig(text)]
    tmo += [{"path": rel, **t} for t in timeout_values(text)]
  print(json.dumps({"loops": pools, "tries_defaults": sig, "timeouts": tmo}, indent=1))
  return 0


if __name__ == "__main__":
  sys.exit(main())
