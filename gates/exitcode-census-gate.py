#!/usr/bin/env python3
r"""exitcode-census-gate.py -- can a reader of `$?` alone tell WHICH VERDICT a gate meant?

    .venv/bin/python gates/exitcode-census-gate.py           # the census, and the verdict
    .venv/bin/python gates/exitcode-census-gate.py --rows    # the per-site table, and nothing else
    .venv/bin/python gates/exitcode-census-gate.py --plant   # 22 shapes + 4 decision states

EXIT: 0 every exit site in the census set carries a number somebody CHOSE · 1 at least one site
hands the exit something that is not a chosen number -- a string, a `bool`, nothing at all -- so
CPython decides the code instead of the author · 3 the population is empty or an instrument that
OWNS this census is gone.

    PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5      <- read from gates/gatekit.py, never retyped

THE QUESTION, WHICH IS NOT "WHICH GATES ARE WRONG". `gates/runner.py`'s fifth precondition,
`TOKEN-MISMATCH`, answers a NEIGHBOURING question: a gate whose output SAYS one of `gatekit`'s five
and EXITS another. This census asks the one under it, because the confirmed instance sits in the
hole `TOKEN-MISMATCH` cannot see:

    gates/ops_python_exec-gate.py:113   sys.exit(f"{FIXTURES} has no records")
    gates/ops_python_exec-gate.py:115   sys.exit(f"{n}: argv {a} has no gx gy gz")
    gates/ops_python_exec-gate.py:204   sys.exit(f"the oracle lane failed rc={r.returncode}: ...")
    gates/ops_python_exec-gate.py:286   sys.exit(f"the executor {exe} is absent")

`sys.exit(<str>)` PRINTS the string to stderr and exits **1**, which is `FAIL`. So an ABSENT INPUT
is tallied as a disagreement. `gates/runner.py:spoken_disagrees` does NOT catch these four, and
MEASURED, not assumed: that rule needs a vocabulary NAME in the text, and all four messages are
PROSE ("has no records", "is absent"), so `names` comes back empty and the rule returns `None`.
**A MESSAGE THAT NAMES NO STATE IS NOT A MESSAGE THAT AGREES.** The census grades the shape rather
than the sentence, which is why it is not `spoken_disagrees` with a different regex.

THE LINE IS DRAWN AT "WAS THE CODE CHOSEN", NOT AT "IS THE CODE IN THE TABLE". A site that writes
`sys.exit(3)` chose 3. A site that writes `sys.exit("absent")` chose a SENTENCE, and 1 is what
CPython does with a sentence. That is the FAIL condition and it is a boundary about AUTHORSHIP, so
it does not need an exception list, and the tree's existing `2`-is-argparse's-USAGE consensus
(`checks/wallcheck.py:692`, `checks/dup-gate.py:362-370`) stays a reported COLUMN rather than a
carve-out in the verdict: an unassigned INT is named by `gatekit.verdict_of` -- "REFUSED", by
design, `gates/gatekit.py:88-91` -- so a reader CAN name it, and this gate does not re-decide what
the tree has already decided.

WHAT A CRASH IS, BECAUSE IT IS THE SAME QUESTION. An uncaught exception exits 1, which is `FAIL`,
and `FAIL` is a disagreement. The tree's position is that a crash is `DEAD` and that the mapping is
the RUNNER's, not the gate's: `checks/gatesweep.py:classify` maps `rc 1` + `Traceback` -> `DEAD`,
and `.agents/slop/hooks/run.py:112` says "crashed, not a verdict" in as many words. So a crash IS
distinguishable -- but only by a reader holding the captured stderr, exactly like a string exit is
only readable by a reader holding the message. **THE EXIT CODE CARRIES NEITHER.** Both are ROWS here.

THE POPULATION IS DISCOVERED, THREE TIMES, AND ALL THREE COUNTS ARE PRINTED. Never a list:
  A   `checks/gatesweep.py:population()`      -- an `os.walk` for `*-gate.py` under `gates/`
  B   `gates/gates-pop.py:discover()`          -- entry points in the MEASURED gate homes
  H   `gates/gates-pop.py:gate_homes()`        -- the homes themselves, derived not written down
  W   `os.walk` over `H` for `*.py`            -- **THE CENSUS SET**, the widest of the four
A and B answer different questions and `gates/README.md` prints them side by side for that reason.
`W` is the census set because an exit shape can live in a file no name shape calls a gate: MEASURED
the gate homes hold 250 `.py` and A holds 78, so **172 of them are invisible to `*-gate.py`**. Every
count MOVES while other units write the tree; quote them with the run, never without it.

WHAT THIS DOES NOT SEE, STATED RATHER THAN HIDDEN. Same-module resolution only, depth 1: a name bound
twice is read as both bindings, a call into another module is `FOREIGN`, and a value computed over
runtime data is `OTHER`. `MAYBE-NONE` -- `sys.exit(main())` where `main` has a bare `return` or can
run off its end -- is a LEXICAL LOWER BOUND over that same shallow resolution, and is reported as
such. A census that claimed to be complete here would be claiming the one thing it did not measure.

**AND THERE IS NO `--root`, MEASURED, because one was written and removed.** `gates/runner.py:481`
offers `--root` for the same reason; here it did not work. The census SET is
`gates/gates-pop.py:gate_homes()`, and that function certifies a directory as a gate home only when
its IMMEDIATE files satisfy `_CERTIFY` (`pyproject.toml` and `__main__`) and `_CERTIFY_OR`
(`refuse(` / `exit 3` / `not at the repo root` / `REFUSED, NOT A VERDICT`) and `root_facts` says
the file's root constant RESOLVES TO THE REPO ROOT. MEASURED on four synthetic trees -- bare, with
a `pyproject.toml`, with a root constant and a `refuse()`, and `git init`-ed -- **all four returned
`homes = ()`, so `W` was 0 and this gate REFUSED (3) on every one**, which is the correct verdict
and a useless flag. `gates/README.md` says it: "a gate that cannot parse is a gate nobody reads".
THE SYNTHETIC INPUT BELONGS IN `--plant`, WHICH DRIVES THE SHIPPED DECISION FUNCTION DIRECTLY AND
NEEDS NO DERIVATION AT ALL -- AND THAT IS WHERE IT IS.
"""
import argparse
import ast
import importlib.util
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = HERE / "artifacts" / "exitcode-census"


def instrument(name, rel):
    """A module LOADED BY PATH from the repo root. Doctrine 1: a population is a generator's own
    declaration, and this file holds no copy of any of them -- `gates/gatekit.py` owns the five,
    `checks/gatesweep.py:population()` and `gates/gates-pop.py:discover(),gate_homes()` own the
    derivations, and a second copy of a mapping is one that can disagree with the first
    (`gates/gate-surface.py:240-251`)."""
    p = ROOT / rel
    spec = importlib.util.spec_from_file_location(name, p)
    if spec is None or spec.loader is None or not p.is_file():
        raise ImportError(f"{p} is gone or not loadable -- it OWNS part of this census")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# ===================================================================== the shape classifier
# THE SHAPES. A shape is WHAT THE AUTHOR HANDED THE EXIT, and the verdict column is what CPython
# does with it. `CHOSEN` is the boundary: a shape that is CHOSEN is a number the author picked, and
# `gatekit.verdict_of` can always name it (an unassigned int names itself REFUSED). A shape that is
# not CHOSEN is a number CPython picked from the TYPE, and no reader of `$?` can recover the verdict
# from it. That is the whole FAIL condition.
#
# `DELEGATED` IS IN `CHOSEN` BECAUSE IT IS NOT A SEPARATE EXIT: it is `sys.exit(f())` where `f`
# contains an exit of its own, so `f`'s site is already a row here and grading this call site as
# well would COUNT ONE DEFECT TWICE. `checks/vz_gate.py:249` `sys.exit(verify())` over
# `verify`'s own `sys.exit("LANES DISAGREE on %d rows")` at :106 is the measured case: the first
# version of this file counted it as MAYBE-NONE here AND as STR there, and a census that inflates
# its own count is not a census.
CHOSEN = frozenset({"INT", "NAME", "FOREIGN", "OTHER", "DELEGATED"})
SHAPES = ("INT", "NAME", "STR", "BOOL", "NONE", "MAYBE-NONE", "DELEGATED", "FOREIGN", "OTHER")


def own_exits(tree):
    """`{function_name}` for every function that contains an exit site of its OWN, not descending
    into nested `def`s for the same reason `returns_none` does not."""
    owners = set()
    for fn in ast.walk(tree):
        if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        stack, found = list(fn.body), False
        while stack and not found:
            node = stack.pop()
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)):
                continue
            if isinstance(node, ast.Call):
                f = node.func
                if ((isinstance(f, ast.Attribute) and f.attr == "exit"
                     and isinstance(f.value, ast.Name) and f.value.id == "sys")
                        or (isinstance(f, ast.Name) and f.id in ("exit", "quit"))):
                    found = True
                    break
            if (isinstance(node, ast.Raise) and isinstance(node.exc, ast.Call)
                    and isinstance(node.exc.func, ast.Name) and node.exc.func.id == "SystemExit"):
                found = True
                break
            stack.extend(ast.iter_child_nodes(node))
        if found:
            owners.add(fn.name)
    return owners


def module_ints(tree):
    """`{name: int}` for every module-level integer this file binds, INCLUDING the tuple unpack
    `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` that `gates/gatekit.py:60` writes. A census
    that could not read that unpack would call every `sys.exit(FAIL)` undetermined."""
    out = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(node.value, (ast.Tuple, ast.Constant)):
            vals = list(node.value.elts) if isinstance(node.value, ast.Tuple) else [node.value]
            names = node.targets[0].elts if isinstance(node.targets[0], ast.Tuple) else node.targets[0]
            names = names if isinstance(names, list) else [names]
            for nm, val in zip(names, vals):
                if (isinstance(nm, ast.Name) and isinstance(val, ast.Constant)
                        and isinstance(val.value, int) and not isinstance(val.value, bool)):
                    out[nm.id] = val.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            if (isinstance(node.value, ast.Constant) and isinstance(node.value.value, int)
                    and not isinstance(node.value.value, bool)):
                out[node.target.id] = node.value.value
    return out


def _terminates(stmts):
    """Can control NOT run off the end of this statement list? The conservative structural answer,
    because `sys.exit(main())` becomes `sys.exit(None)` -- which is 0, which is `PASS` -- exactly
    when this returns False.

    `gates/msgdiff-gate.py:593` is why the `Try` arm exists: `main`'s body is one `try:` whose
    every branch ends in `return`, so the first version's "the last statement is not a `return`"
    test called it MAYBE-NONE and that was FALSE. A `try` terminates when its body terminates and
    it has a handler to catch what would otherwise fall through; a `with` is its body; an `if`
    needs both arms. Anything else -- a loop, a bare call, a `match` -- answers False, which is
    the SAFE direction: False means MAYBE-NONE, and MAYBE-NONE fails the gate."""
    if not stmts:
        return False
    last = stmts[-1]
    if isinstance(last, (ast.Return, ast.Raise)):
        return True
    if isinstance(last, ast.Try):
        return bool(last.handlers) and _terminates(last.body)
    if isinstance(last, (ast.With, ast.AsyncWith)):
        return _terminates(last.body)
    if isinstance(last, ast.If) and last.orelse:
        return _terminates(last.body) and _terminates(last.orelse)
    return False


def returns_none(fn):
    """Can this same-module function hand back `None`? A bare `return`, or a body that can run off
    its end. LEXICAL, depth-1, and said to be: it does not follow a call, so a function that always
    returns `0` from a callee reads as MAYBE.

    NESTED `def`s ARE NOT DESCENDED INTO, and MEASURED, that is not a detail: `ast.walk` visits
    them, so the first version read `gates/msgdiff-gate.py:593` as MAYBE-NONE on the strength of a
    bare `return` inside a CLOSURE `main` defines -- while `main` itself returns `PASS` or `REFUSED`
    or `SKIP` or `DEAD` and never `None`. **A SHALLOWER-THAN-CLAIMED LOOKUP IN A GATE IS A FALSE
    POSITIVE, AND A FALSE POSITIVE IN A CENSUS IS THE SAME CLASS AS A FALSE NEGATIVE: both rows.**"""
    stack, found = list(fn.body), False
    while stack:
        node = stack.pop()
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)):
            continue
        if isinstance(node, ast.Return) and node.value is None:
            found = True
        stack.extend(ast.iter_child_nodes(node))
    return found or not _terminates(fn.body)


def _callee(name, env):
    """The shape of `sys.exit(<same-module function>())`, in the order the evidence is good."""
    fn = env["funcs"][name]
    if name in env["delegated"]:
        return ("DELEGATED", None,
                f"{name}() contains an exit of its own, counted at that site")
    if returns_none(fn):
        return ("MAYBE-NONE", None,
                f"{name}() can return None, and sys.exit(None) is 0 == PASS")
    return "FOREIGN", None, f"{name}() resolves inside this module"


def classify_site(node, tree, env):
    """`(shape, code, why)` for ONE already-extracted exit value, or `(None, None, "")` when the
    value is absent -- which is the `NONE` shape and the most dangerous one in this file, so it is
    NOT an absence.

    THE SHIPPED DECISION, and `--plant` drives THIS and nothing else. `gates/runner.py:391`'s first
    `plant()` reached past the decision functions into the helpers and MEASURED green after
    `preconditions`' branch was broken; a plant that drives a helper is not a plant of the decision.
    `node` is an AST expression, so the plant builds one with `ast.parse` and never forks.
    """
    if node is None:
        return "NONE", 0, "sys.exit() with no argument exits 0, and 0 is PASS"
    if isinstance(node, ast.Constant):
        if isinstance(node.value, bool):
            return ("BOOL", int(node.value),
                    "True is 1 == FAIL and False is 0 == PASS; `bool` is a subclass of `int`")
        if isinstance(node.value, int):
            return "INT", node.value, ""
        if isinstance(node.value, str):
            return ("STR", 1, "a string handed to sys.exit is PRINTED and exits 1 == FAIL")
    if isinstance(node, ast.JoinedStr):
        return "STR", 1, "an f-string is a string: printed, and 1 == FAIL"
    if isinstance(node, ast.Name):
        if node.id in env["ints"]:
            return "NAME", env["ints"][node.id], ""
        if node.id in env["funcs"]:
            return _callee(node.id, env)
        return "OTHER", None, f"`{node.id}` is not a module-level integer here"
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in env["funcs"]:
        return _callee(node.func.id, env)
    if isinstance(node, (ast.Attribute, ast.Call)):
        return "FOREIGN", None, "the value comes from another module's vocabulary"
    return "OTHER", None, "an expression over runtime data"


def extract(tree):
    """Every exit site in one parsed file, as `(lineno, value_node_or_None)`.

    FOUR SPELLINGS, all of them real: `sys.exit(v)`, `exit(v)`, `quit(v)`, and
    `raise SystemExit(v)`. MEASURED under `.venv/bin/python` 3.12.10, which is what every gate runs
    under: `sys.exit("m")` -> rc 1 with `m` on stderr · `sys.exit()` -> **rc 0** · `sys.exit(3)` ->
    rc 3 · `sys.exit(True)` -> rc 1 · `raise SystemExit("m")` -> rc 1 · an uncaught exception -> rc 1.
    """
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            fn = node.func
            hit = ((isinstance(fn, ast.Attribute) and fn.attr == "exit"
                    and isinstance(fn.value, ast.Name) and fn.value.id == "sys")
                   or (isinstance(fn, ast.Name) and fn.id in ("exit", "quit")))
            if hit:
                out.append((node.lineno, node.args[0] if node.args else None))
        elif (isinstance(node, ast.Raise) and isinstance(node.exc, ast.Call)
              and isinstance(node.exc.func, ast.Name) and node.exc.func.id == "SystemExit"):
            out.append((node.lineno, node.exc.args[0] if node.exc.args else None))
    return sorted(out)


# ===================================================================== the census
def census(path, env):
    """`[(lineno, shape, code, verdict, why)]` for one file, and `[]` for a file that will not
    parse -- which is `OTHER`, not a site, and is counted by the caller rather than swallowed."""
    gatekit = env["gatekit"]
    try:
        tree = ast.parse(path.read_text(errors="replace"))
    except (SyntaxError, ValueError) as exc:
        return [], f"unparseable: {exc}"
    env["funcs"] = {n.name: n for n in ast.walk(tree)
                    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    env["ints"] = module_ints(tree)
    env["delegated"] = own_exits(tree)
    rows = []
    for lineno, value in extract(tree):
        shape, code, why = classify_site(value, tree, env)
        verdict = gatekit.verdict_of(code) if isinstance(code, int) else "-"
        rows.append((lineno, shape, code, verdict, why))
    return rows, ""


def population(root):
    """`(W, facts)` -- the census SET and the three other answers, all DISCOVERED and all printed.
    `W` is the widest: an `os.walk` over the homes `gates/gates-pop.py:gate_homes()` derives."""
    facts, errs = {}, []
    sweep = instrument("ec_sweep", "checks/gatesweep.py")
    facts["A *-gate.py under gates/"] = len(sweep.population(root))
    pop = instrument("ec_pop", "gates/gates-pop.py")
    homes, derivation = pop.gate_homes(root)
    facts["H gate homes (derived)"] = len(homes)
    facts["B entry points in the homes"] = len(pop.discover(root)[0])
    walk = []
    for home in homes:
        base = root / home
        for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for name in filenames:
                if name.endswith(".py"):
                    walk.append(Path(dirpath) / name)
    facts[f"W every .py under {'+'.join(homes)}"] = len(walk)
    facts["home derivation"] = derivation.get("source", "?") if isinstance(derivation, dict) else str(derivation)
    if not walk:
        errs.append(f"W is EMPTY: no .py under {homes} -- a census with a denominator of 0 "
                    f"reports 0 defects, which is not the same answer")
    return sorted(walk), facts, errs


def decide(all_rows, facts, errs):
    """THE GATE'S OWN VERDICT. `(code, why)`. Three states, and no fourth:

      REFUSED the census could not be taken -- no population, or an owner is gone. It MEASURED
               NOTHING, and `SKIP` would claim a measurement it does not have.
      FAIL    at least one site hands the exit a value CPython, not the author, turns into a code.
               `gates/ops_python_exec-gate.py` was 4 of these.
      PASS    every site carries a number somebody chose. An int outside `VERDICT` is REPORTED,
               not failed: `gatekit.verdict_of` names it REFUSED by design, and this file does not
               re-decide what the tree has already decided -- that is `checks/wallcheck.py:692`'s
               `2: "USAGE"` consensus surviving untouched, not a carve-out added here.
    """
    gatekit = instrument("ec_gatekit", "gates/gatekit.py")
    flat = [(rel(p), row) for p, rows in all_rows for row in rows]
    if errs:
        return gatekit.REFUSED, "; ".join(errs)
    not_chosen = [(r, row) for r, row in flat if row[1] not in CHOSEN]
    unowned = [(r, row) for r, row in flat if row[1] == "INT" and row[2] not in gatekit.VERDICT]
    if not_chosen:
        counts = {}
        for _r, (_l, shape, _c, _v, _w) in not_chosen:
            counts[shape] = counts.get(shape, 0) + 1
        parts = ", ".join(f"{n} {s}" for s, n in sorted(counts.items()))
        where = ", ".join(f"{r}:{row[0]}" for r, row in not_chosen[:8])
        more = f", +{len(not_chosen) - 8} more in {OUT.name}/rows.tsv" if len(not_chosen) > 8 else ""
        return gatekit.FAIL, (f"{len(not_chosen)} exit site(s) carry a code CPYTHON chose rather "
                              f"than the author [{parts}]: {where}{more}. A caller reading `$?` "
                              f"cannot tell which verdict was meant")
    tail = ""
    if unowned:
        tail = (f" -- and {len(unowned)} site(s) carry an int outside VERDICT, which "
                f"gatekit.verdict_of names REFUSED by design and this gate REPORTS rather than "
                f"re-decides: " + ", ".join(f"{r}:{row[0]}={row[2]}" for r, row in unowned[:6]))
    return gatekit.PASS, f"every exit site carries a number somebody chose{tail}"


def rel(p):
    """`p` relative to the repo root when it is inside it, and itself when it is not. The plant's
    synthetic `g/x-gate.py` is not, and a census that raised on its own plant would be a census
    whose `--plant` cannot run -- which is the shape `gates/runner.py:518`'s two-value tuple is."""
    try:
        return str(p.relative_to(ROOT))
    except ValueError:
        return str(p)


# ===================================================================== the plant
# (label, source, want_sites, want_shape, want_code, verdict_prefix, chosen?)
PLANT_CASES = (
    # THE FIVE `STR` ROWS ALL SAY `FAIL` AND ALL ARE NOT CHOSEN, and that pairing is the finding.
    # `gatekit.verdict_of(1)` is "FAIL" -- correctly, because a string exit really does produce 1 --
    # so the exit code is NAMEABLE. What it cannot say is whether the author MEANT a failure: at
    # `gates/ops_python_exec-gate.py:286` the sentence is "the executor <path> is absent", which
    # every other line of that file grades REFUSED. So the row asserts both halves, because a plant
    # that asserted only the shape would be green on an instrument that never learned the shape is
    # not the defect -- the UNCHOSENNESS is.
    ('sys.exit("m") is a FAIL nobody chose', 'sys.exit("m")', 1, "STR", 1, "FAIL", False),
    ("an f-string exit is the same shape", 'sys.exit(f"x {1}")', 1, "STR", 1, "FAIL", False),
    ("raise SystemExit('m') is the same shape", 'raise SystemExit("m")', 1, "STR", 1, "FAIL", False),
    ("bare exit('m') is the same shape", 'exit("m")', 1, "STR", 1, "FAIL", False),
    ("quit('m') is the same shape", 'quit("m")', 1, "STR", 1, "FAIL", False),
    ("sys.exit() is the MOST dangerous", 'sys.exit()', 1, "NONE", 0, "PASS", False),
    ("sys.exit(True) is 1 by aliasing", 'sys.exit(True)', 1, "BOOL", 1, "FAIL", False),
    ("sys.exit(False) is 0 by aliasing", 'sys.exit(False)', 1, "BOOL", 0, "PASS", False),
    ("sys.exit(3) is a CHOSEN REFUSED", 'sys.exit(3)', 1, "INT", 3, "REFUSED", True),
    ("sys.exit(5) is a CHOSEN DEAD", 'sys.exit(5)', 1, "INT", 5, "DEAD", True),
    ("sys.exit(0) is a CHOSEN PASS", 'sys.exit(0)', 1, "INT", 0, "PASS", True),
    ("sys.exit(2) is CHOSEN and UNOWNED", 'sys.exit(2)', 1, "INT", 2, "UNASSIGNED", True),
    ("sys.exit(FAIL) reads the unpack", 'FAIL = 1\nsys.exit(FAIL)', 1, "NAME", 1, "FAIL", True),
    ("sys.exit(REFUSED) reads the unpack", 'REFUSED = 3\nsys.exit(REFUSED)', 1, "NAME", 3, "REFUSED", True),
    ("sys.exit(DEAD) reads the unpack", 'DEAD = 5\nsys.exit(DEAD)', 1, "NAME", 5, "DEAD", True),
    ("sys.exit(f()) when f can return None", 'def f():\n  if 1: return 0\nsys.exit(f())',
     1, "MAYBE-NONE", None, "-", False),
    # THE ONE THAT IS NOT A DEFECT, and the plant is where it is proved. `checks/vz_gate.py:249`
    # is the live shape: `sys.exit(verify())` over a `verify` that ends in `sys.exit(<str>)`.
    # Counting the call site AND the exit site would count one defect twice.
    ("a callee's own exit is DELEGATED, once",
     'def f():\n  sys.exit("x")\nsys.exit(f())', 2, "DELEGATED", None, "-", True),
    ("sys.exit(g()) across a module boundary", 'import gatekit\nsys.exit(gatekit.main())',
     1, "FOREIGN", None, "-", True),
    ("sys.exit(main()) with a real exit is safe", 'def main():\n  return 3\nsys.exit(main())',
     1, "FOREIGN", None, "-", True),
    ("a try/except main that always returns is safe",
     'def main():\n  try:\n    return 3\n  except E:\n    return 5\nsys.exit(main())',
     1, "FOREIGN", None, "-", True),
    ("a computed code is OTHER, not INT", 'sys.exit(1 if x else 3)', 1, "OTHER", None, "-", True),
    ("a runtime-bound name is OTHER, not chosen", 'sys.exit(rc)', 1, "OTHER", None, "-", True),
)


def plant():
    """Every shape in `SHAPES`, on SYNTHETIC SOURCES, through the SHIPPED classifier and the SHIPPED
    verdict function. No walk, no subprocess, no `bend`, no live file.

    Each case asserts FOUR things and not two: the NUMBER of sites `extract()` found, the shape, the
    code CPython produces from it, and whether that shape is `CHOSEN` -- because "is the shape
    right" and "does the shape's code carry a verdict" are different claims, and a plant that
    checked only the first would be green on an instrument that grades the second wrongly. THE
    `MAYBE-NONE` / `DELEGATED` PAIR IS THE POINT: two `sys.exit(f())` call sites that differ only in
    whether `f` has an exit of its own, and the census counts ONE of them once.
    """
    gatekit = instrument("ec_gatekit", "gates/gatekit.py")
    env = {"gatekit": gatekit, "funcs": {}, "ints": {}, "delegated": set()}
    bad, unowned_agreed = [], 0
    for label, src, want_sites, want_shape, want_code, want_verdict, want_chosen in PLANT_CASES:
        tree = ast.parse(src)
        site = extract(tree)
        if len(site) != want_sites:
            bad.append(f"{label}: extract() found {len(site)} sites, expected {want_sites}")
            continue
        lineno, value = site[-1]
        env["ints"] = module_ints(tree)
        env["funcs"] = {n.name: n for n in ast.walk(tree)
                        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
        env["delegated"] = own_exits(tree)
        shape, code, _why = classify_site(value, tree, env)
        verdict = gatekit.verdict_of(code) if isinstance(code, int) else "-"
        chosen = shape in CHOSEN
        ok = shape == want_shape and code == want_code and verdict.startswith(want_verdict) \
            and chosen is want_chosen
        if not ok:
            bad.append(f"{label}: shape={shape} code={code} verdict={verdict} chosen={chosen}, "
                       f"expected shape={want_shape} code={want_code} verdict~{want_verdict} "
                       f"chosen={want_chosen}")
        if shape == "INT" and code not in gatekit.VERDICT and chosen:
            unowned_agreed += 1
        print(f"  {'OK  ' if ok else 'BAD '} {label:<42} {shape:<10} code={str(code):<5} "
              f"{verdict[:44]:<44} {'CHOSEN' if chosen else 'NOT CHOSEN'}")
    # THE DECISION, not just the classifier: a tree holding one string exit FAILs, a tree whose
    # every site carries a chosen number PASSes, and an empty population REFUSES. A plant that
    # grades the shapes but never the verdict is a plant of the helper -- which is the defect
    # `gates/runner.py:391` records, measured: its first `plant()` reached past the decision
    # functions and breaking `preconditions`' branch left the plant green.
    ONE = [{"W": 1}]
    trees = (
        ("a tree holding a string exit FAILs",
         ([(Path("g/x-gate.py"), [(113, "STR", 1, "FAIL", "")])], ONE, []), gatekit.FAIL),
        ("a tree of chosen numbers PASSes",
         ([(Path("g/x-gate.py"), [(1, "INT", 3, "REFUSED", ""), (2, "NAME", 0, "PASS", "")])],
          ONE, []), gatekit.PASS),
        ("an empty population REFUSES, not PASSes",
         ([], {"W": 0}, ["W is EMPTY: nothing was measured"]), gatekit.REFUSED),
        ("a tree that only MAYBE-NONE FAILs",
         ([(Path("g/x-gate.py"), [(9, "MAYBE-NONE", None, "-", "")])], ONE, []), gatekit.FAIL),
    )
    for label, (rows, facts, errs), want in trees:
        code, why = decide(rows, facts, errs)
        ok = code == want
        bad += [] if ok else [f"{label}: rc={code} ({why}), expected {want}"]
        print(f"  {'OK  ' if ok else 'BAD '} {label:<42} rc={code} {gatekit.verdict_of(code)[:44]}")
    # AND THE FIVE EXITS ARE REACHABLE FROM THIS FILE'S OWN VERDICT FUNCTION, one state at a time.
    for code in (gatekit.PASS, gatekit.FAIL, gatekit.REFUSED, gatekit.SKIP, gatekit.DEAD):
        got = gatekit.verdict_of(code)
        if got != gatekit.VERDICT[code]:
            bad.append(f"verdict_of({code}) = {got!r}, expected {gatekit.VERDICT[code]!r}")
    if gatekit.SKIP == gatekit.FAIL or gatekit.REFUSED == gatekit.FAIL:
        bad.append("the five collapsed; DEAD(5) and REFUSED(3) must stay distinct from FAIL(1)")
    print(f"\n  {len(PLANT_CASES)} shapes + {len(trees)} decision states + 5 verdicts; "
          f"{unowned_agreed} unowned INT(s) graded CHOSEN-and-reported, which is the `2` consensus "
          f"surviving untouched")
    print(f"--plant: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return gatekit.FAIL if bad else gatekit.PASS


# ===================================================================== main
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plant", action="store_true", help="the shapes, on synthetic sources only")
    ap.add_argument("--rows", action="store_true", help="write the per-site table and stop")
    args = ap.parse_args(argv)
    if args.plant:
        return plant()
    root = ROOT

    walk, facts, errs = population(root)
    env = {"gatekit": instrument("ec_gatekit", "gates/gatekit.py"), "funcs": {}, "ints": {}}
    all_rows, unreadable = [], []
    for path in walk:
        rows, err = census(path, env)
        if err:
            unreadable.append(f"{path.name}: {err}")
        all_rows.append((path, rows))

    sites = [(p, r) for p, rows in all_rows for r in rows]
    code, why = decide(all_rows, facts, errs)
    gatekit = env["gatekit"]

    width = max((len(k) for k in facts), default=10)
    print("POPULATION")
    for k, v in facts.items():
        print(f"  {k:<{width}} {v}")
    print(f"  {'files with an exit site':<{width}} {len({p for p, _ in sites})}")
    print(f"  {'exit sites':<{width}} {len(sites)}")
    if unreadable:
        print(f"  {'unparseable (counted, not swallowed)':<{width}} {len(unreadable)}")

    by = {}
    for _p, (_l, shape, _c, _v, _w) in sites:
        by[shape] = by.get(shape, 0) + 1
    print("\nSHAPES  (a shape is WHAT THE AUTHOR HANDED THE EXIT; CHOSEN means a number the author picked)")
    for shape in SHAPES:
        if shape in by:
            print(f"  {shape:<10} {by[shape]:>4}   {'code carries the verdict' if shape in CHOSEN else 'CPYTHON decides the code'}")

    unowned = [(p, l, c, v) for p, rows in all_rows for l, s, c, v, _w in rows
               if s == "INT" and c not in gatekit.VERDICT]
    if unowned:
        print(f"\nUNOWNED INT -- reachable, named REFUSED by gatekit.verdict_of, REPORTED not failed "
              f"({len(unowned)}):")
        for p, l, c, v in unowned[:12]:
            print(f"  {p.relative_to(root) if p.is_relative_to(root) else p}:{l}  exits {c} -> {v}")

    NOT_CHOSEN = [r for r in sites if r[1][1] not in CHOSEN]
    if NOT_CHOSEN:
        print(f"\nNOT CHOSEN -- {len(NOT_CHOSEN)} site(s); CPython turns the value into the code:")
        for p, (l, shape, c, v, why_s) in NOT_CHOSEN[:24]:
            rel = p.relative_to(root) if p.is_relative_to(root) else p
            print(f"  {rel}:{l}  {shape:<10} rc={c} ({v})  {why_s}")
        if len(NOT_CHOSEN) > 24:
            print(f"  ... and {len(NOT_CHOSEN) - 24} more, in {OUT.name}/rows.tsv")

    if args.rows:
        OUT.mkdir(parents=True, exist_ok=True)
        with (OUT / "rows.tsv").open("w") as sink:
            sink.write("# path\tline\tshape\tcode\tverdict\twhy\n")
            for p, rows in all_rows:
                rel = p.relative_to(root) if p.is_relative_to(root) else p
                for l, shape, c, v, why_s in rows:
                    sink.write(f"{rel}\t{l}\t{shape}\t{c}\t{v}\t{why_s}\n")
        print(f"\nrows: {OUT / 'rows.tsv'} ({len(sites)} sites)")
        return code

    print(f"\n{why}")
    return code


if __name__ == "__main__":
    sys.exit(main())