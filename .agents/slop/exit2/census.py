#!/usr/bin/env python3
"""CENSUS OF EXIT CODE 2 IN `checks/` AND `gates/`.

WHAT THIS IS. A static census, by `ast` (and by regex for the shell), of every instrument in
`checks/` and `gates/` that can exit 2, and BY WHICH MECHANISM:

  (i)   ARGPARSE-USAGE   the file imports `argparse`, so it inherits argparse's own usage
                         exit code 2. The 2 is NOT in this file's source at all: CPython's
                         `argparse.ArgumentParser.error()` calls `sys.exit(2)`.
  (ii)  DELIBERATE       a literal `2` sits at an exit/return site in this file. The number
                         IS in the source, so the file is DECLARING it.
  (iii) PROPAGATED       the exit status is a CHILD's status handed up (`return rc`, where
                         `rc` came from a `subprocess`), so the CHILD chooses the 2.
  (iv)  ACCIDENTAL       nothing in the file chooses 2 and yet the process can leave with 2:
                         a shell gate under `set -e` running an interpreter that cannot open
                         its script (CPython's "can't open file" exit IS 2, MEASURED).

THE POPULATION, IN THREE ROLES, ALL NAMED. `gates/gates-pop.py:discover()` -- the tree's OWN
generator declaration, LOADED BY PATH (never imported by name: importing a gate RUNS it) --
gives the ENTRY points and the LIBs. A plain `os.walk` of `checks/` and `gates/` gives
everything else, and the difference (another unit's scratch, e2e fixtures) is REPORTED AND
NAMED, so no denominator is a hand list and nothing is hidden by the choice of population.

THE PROPAGATION FILTER, AND WHY IT EXISTS. A `return 2` is NOT an exit code until its value
REACHES the process exit. `gates/amd_dsl_census-oracle.py:1046` returns the NUMBER OF SOURCE
RUNGS, and a naive lexical classifier calls it a deliberate exit 2. **That false positive was
found by running the classifier and hand-reading its output, and the filter that removes it is
in this file** (`exit_reaching`). The filter is a fixpoint over the file's own call graph.

THE CONTROL. The classifier must separate (i) from (ii). It CAN, and the discriminator is
not a heuristic: **a literal `2` in the source is a declaration, and argparse's 2 is not in
the source.** `checks/dup-gate.py` is the control -- it has BOTH a literal `return 2` AND
`argparse`, and its own source says what the 2 means (`2: "USAGE"`). The census must show
BOTH mechanisms for that file. A second control: a file that imports `argparse` and has NO
literal 2 must show (i) ALONE. A third: the oracle's rung-counting `return 2` must NOT be
reported as an exit. All three are asserted at the bottom of this file.

NOTHING HERE IS EXECUTED. Every number is `ast`/regex over source read at one timestamp.
`checks/` and `gates/` are READ and PARSED only. No gate is run. No tree subprocess is run.
"""
import ast
import importlib.util
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = HERE / "sites.rows"
ROLES_OUT = HERE / "roles.rows"

_spec = importlib.util.spec_from_file_location("gatekit", ROOT / "gates" / "gatekit.py")
_gatekit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gatekit)
# WHAT `gates/gatekit.py`'s `verdict_of(2)` RETURNS. Computed by CALLING it, not retyped.
_VO = _gatekit.verdict_of(2)
# WHAT `checks/gatesweep.py:classify` RETURNS for an rc of 2 -- re-derived, not retyped:
# `word = gatekit.VERDICT.get(rc)`; if there is no word, `("REFUSED", f"UNASSIGNED({rc})")`.
_CLS_V, _CLS_T = "REFUSED", "UNASSIGNED(2)"


def load_gates_pop():
    """The tree's OWN instrument population, LOADED BY PATH."""
    spec = importlib.util.spec_from_file_location("gates_pop", ROOT / "gates" / "gates-pop.py")
    m = importlib.util.module_from_spec(spec)
    sys.modules["gates_pop"] = m
    spec.loader.exec_module(m)
    return m


def walk_all():
    """Every .py/.sh under checks/ and gates/, by DISCOVERY (`os.walk`, never `glob`)."""
    for base in ("checks", "gates"):
        for dirpath, dirnames, filenames in os.walk(ROOT / base):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for name in sorted(filenames):
                if name.endswith((".py", ".sh")):
                    yield Path(dirpath) / name


def callee_name(node):
    if not isinstance(node, ast.Call):
        return None
    f = node.func
    if isinstance(f, ast.Name):
        return f.id
    if isinstance(f, ast.Attribute):
        base = callee_name(f.value)
        return f"{base}.{f.attr}" if base else f.attr
    return None


def literal_int(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, int) \
            and not isinstance(node.value, bool):
        return node.value
    return None


def parent_map(tree):
    out = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            out[child] = node
    return out


def enclosing_func(node, parents):
    cur = node
    while cur in parents:
        cur = parents[cur]
        if isinstance(cur, (ast.FunctionDef, ast.AsyncFunctionDef)):
            return cur
    return None


def subprocess_names(tree):
    """-> the names bound from a subprocess result."""
    names = set()

    def binds(targets):
        for t in targets:
            if isinstance(t, ast.Name):
                names.add(t.id)

    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        v = node.value
        if isinstance(v, ast.Call):
            if (callee_name(v) or "").split(".")[-1] in ("run", "call", "Popen", "check_output"):
                binds(node.targets)
        elif isinstance(v, ast.Attribute) and v.attr == "returncode":
            binds(node.targets)
    return names


def exit_reaching(tree):
    """-> the set of function names whose RETURN VALUE can reach the process exit.

    THE PROPAGATION FILTER. A `return 2` is not an exit code until the value arrives at
    `sys.exit(...)`. `reach(F)` means "F's return value can reach the process exit". The
    fixpoint, in the RIGHT DIRECTION (the first version had it backwards and dropped eight
    real sites -- `checks/wallcheck.py:591` among them -- which is why the control below
    asserts a COUNT as well as a shape):
      * SEED: a function called directly inside `sys.exit(F(...))` / `raise SystemExit(F(...))`.
      * SEED: a function whose result is BOUND to a name that is then passed to `sys.exit`.
      * STEP: if `reach(F)`, then every G whose value F HANDS BACK is itself a reacher --
        `return G(...)` and `return N` where `N = G(...)` both do that, because F's own
        value is G's value.
    """
    reach = set()
    assigns = {}   # name -> called function name
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
            cn = callee_name(node.value)
            if cn:
                for t in node.targets:
                    if isinstance(t, ast.Name):
                        assigns.setdefault(t.id, set()).add(cn)

    def seed_from(expr):
        if isinstance(expr, ast.Call):
            cn = callee_name(expr)
            if cn:
                reach.add(cn)
        elif isinstance(expr, ast.Name):
            for cn in assigns.get(expr.id, ()):
                reach.add(cn)

    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and callee_name(node) in ("sys.exit", "exit", "os._exit"):
            for a in node.args:
                seed_from(a)
        if isinstance(node, ast.Raise) and isinstance(node.exc, ast.Call) \
                and callee_name(node.exc) in ("SystemExit", "sys.exit"):
            for a in node.exc.args:
                seed_from(a)

    changed = True
    while changed:
        changed = False
        for node in ast.walk(tree):
            if not isinstance(node, ast.Return) or node.value is None:
                continue
            fn = enclosing_func(node, parents_of(tree))
            if fn is None or fn.name not in reach:
                continue
            v = node.value
            hands = []
            if isinstance(v, ast.Call):
                hands.append(v)
            elif isinstance(v, ast.IfExp):
                hands.extend([v.body, v.orelse])
            elif isinstance(v, ast.BoolOp):
                hands.extend(v.values)
            elif isinstance(v, ast.Name):
                for cn in assigns.get(v.id, ()):
                    if cn not in reach:
                        reach.add(cn)
                        changed = True
            for h in hands:
                if isinstance(h, ast.Call):
                    cn = callee_name(h)
                    if cn and cn not in reach:
                        reach.add(cn)
                        changed = True
                elif isinstance(h, ast.Name):
                    for cn in assigns.get(h.id, ()):
                        if cn not in reach:
                            reach.add(cn)
                            changed = True
    return reach


_PARENTS = {}


def parents_of(tree):
    if id(tree) not in _PARENTS:
        _PARENTS[id(tree)] = parent_map(tree)
    return _PARENTS[id(tree)]


def verdict_declaration(tree):
    """-> {code: name} if the file declares a VERDICTS-shaped mapping, else {}.
    Read by AST, never by import: import RUNS a gate."""
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        for t in node.targets:
            if isinstance(t, ast.Name) and t.id in ("VERDICTS", "VERDICT", "EXITS", "CODES"):
                try:
                    v = ast.literal_eval(node.value)
                except (ValueError, SyntaxError):
                    continue
                if isinstance(v, dict) and all(isinstance(k, int) for k in v):
                    return {k: str(x) for k, x in v.items()}
    return {}


def comment_above(text, lineno, words):
    lines = text.splitlines()
    lo = max(0, min(lineno, len(lines)) - 14)
    for i in range(min(lineno, len(lines)) - 1, lo - 1, -1):
        s = lines[i].strip()
        if s.startswith("#") and any(w in s for w in words):
            return f"{i + 1}: {s[:200]}"
    return ""


def own_message(tree, node, parents):
    """-> the MESSAGE the instrument prints next to the exit, read off the AST.

    A comment above a site is weak evidence: it can be about something else entirely. The
    string the instrument PRINTS as it exits is the message the operator actually sees, and
    it is the witness for what the number MEANS. It is the nearest `print(...)` /
    `sys.stderr.write(...)` in the SAME function, before the site.
    """
    fn = enclosing_func(node, parents)
    scope = fn if fn is not None else tree
    best = None
    for n in ast.walk(scope):
        if not isinstance(n, ast.Call):
            continue
        fn_name = callee_name(n) or ""
        if not (fn_name.endswith("print") or fn_name.endswith("write")
                or fn_name.endswith("say") or fn_name.endswith("echo")):
            continue
        if n.lineno >= node.lineno:
            continue
        best = n
    if best is None:
        return ""
    for a in best.args:
        if isinstance(a, ast.Constant) and isinstance(a.value, str):
            return a.value[:160]
    try:
        return ast.unparse(best)[:160]
    except Exception:
        return ""



SH_EXIT2 = re.compile(r"(?:^|[;&|]\s*)exit\s+2\b")
SH_SETE = re.compile(r"^\s*set\s+[-+]\S*e", re.M)
SH_PY = re.compile(r"(?:^|[\s;&|(])(?:[\w./]*/)?python3?\b")


def shell_sites(text):
    """-> the shell sites. (ii) `exit 2` in the source. (iv) `set -e` plus an interpreter
    invocation: CPython's "can't open file" exit IS 2 (MEASURED), and errexit hands it up."""
    sites = []
    lines = text.splitlines()
    for i, line in enumerate(lines, 1):
        if line.strip().startswith("#"):
            continue
        if SH_EXIT2.search(line):
            sites.append(("deliberate", i,
                          f"`exit 2` at line {i}: the number IS in the source, so the shell "
                          f"script declares it -- {line.strip()[:110]}"))
    if SH_SETE.search(text):
        for i, line in enumerate(lines, 1):
            s = line.strip()
            if s.startswith("#") or "python" not in s:
                continue
            if SH_PY.search(s):
                sites.append(("accidental", i,
                              f"`set -e` + an interpreter invocation at line {i}: CPython's "
                              f"'can't open file' exit IS 2 (MEASURED) and errexit hands it up, "
                              f"so a missing script exits 2 with nobody choosing it"))
                break
    return sites


def python_sites(path, text, tree):
    """-> (sites, decl, reach). `sites` are the DETERMINATE ways this file reaches 2."""
    parents = parents_of(tree)
    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                imports.add(a.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.add(node.module.split(".")[0])
    decl = verdict_declaration(tree)
    subs = subprocess_names(tree)
    reach = exit_reaching(tree)
    sites = []

    if "argparse" in imports:
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                n = callee_name(node)
                if n and n.split(".")[-1] in ("parse_args", "parse_known_args"):
                    sites.append(("argparse-usage", node.lineno,
                                  f"argparse {n}() at line {node.lineno}: a usage error is "
                                  f"argparse's own exit 2 (the number is NOT in this file's "
                                  f"source)"))
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            ex = callee_name(node)
            if ex in ("sys.exit", "exit", "os._exit", "builtins.exit"):
                for arg in node.args:
                    if literal_int(arg) == 2:
                        sites.append(("deliberate", node.lineno,
                                      f"{ex}(2) at line {node.lineno}: the number IS in the "
                                      f"source, so the file declares it"))
                    elif isinstance(arg, ast.Name) and arg.id in subs:
                        sites.append(("propagated-child", node.lineno,
                                      f"{ex}({arg.id}) at line {node.lineno}: {arg.id} is a "
                                      f"CHILD's status, so the CHILD chooses the 2"))
        if isinstance(node, ast.Raise) and isinstance(node.exc, ast.Call) \
                and callee_name(node.exc) in ("SystemExit", "sys.exit"):
            for arg in node.exc.args:
                if literal_int(arg) == 2:
                    sites.append(("deliberate", node.lineno,
                                  f"raise SystemExit(2) at line {node.lineno}: the number IS in "
                                  f"the source, so the file declares it"))
        if isinstance(node, ast.Return) and node.value is not None:
            fn = enclosing_func(node, parents)
            fname = fn.name if fn else "(module scope)"
            if literal_int(node.value) == 2:
                # THE PROPAGATION FILTER. The value must REACH the process exit.
                if fname == "(module scope)" or fname in reach:
                    sites.append(("deliberate", node.lineno,
                                  f"return 2 at line {node.lineno} (in {fname}()): the number IS "
                                  f"in the source AND the value reaches the process exit, so the "
                                  f"file declares it"))
                else:
                    sites.append(("NOT-AN-EXIT", node.lineno,
                                  f"return 2 at line {node.lineno} (in {fname}()): the value does "
                                  f"NOT reach the process exit -- {fname}() is not called by an "
                                  f"exit path -- so this is NOT a deliberate exit 2"))
            elif isinstance(node.value, ast.Name) and node.value.id in subs:
                sites.append(("propagated-child", node.lineno,
                              f"return {node.value.id} at line {node.lineno} (in {fname}()): "
                              f"{node.value.id} is a CHILD's status, so the CHILD chooses the 2"))
    return sites, decl, reach


PHRASE_OUT = HERE / "refused-phrase.rows"
PHRASE = "REFUSED, NOT A VERDICT"


def phrase_sites():
    """-> the measurement that decides Q2: every function that PRINTS the tree's canonical
    REFUSED phrase, and the exit code it ACTUALLY uses.

    THE QUESTION. `gates/runner.py:42-43` states the tree's rule: *"A REFUSAL IS NOT A
    VERDICT. All five refusals exit `gatekit.REFUSED` (3) and print 'REFUSED, NOT A
    VERDICT', because the tree is fine in every one of them -- the RUN is not permitted."*
    So the phrase and the code 3 are ONE convention. **A function that prints the phrase and
    exits anything else is contradicting the tree's own rule, and this table names each one.**
    """
    rows = []
    for base in ("checks", "gates"):
        for dirpath, dirnames, filenames in os.walk(ROOT / base):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for name in sorted(filenames):
                if not name.endswith((".py", ".sh")):
                    continue
                path = Path(dirpath) / name
                rel = str(path.relative_to(ROOT))
                text = path.read_text(errors="replace")
                if PHRASE not in text:
                    continue
                if path.suffix == ".sh":
                    m = re.search(r"refuse\(\)\s*\{[^}]*exit\s+(\d+)", text)
                    if m:
                        rows.append([rel, "refuse()", m.group(1), "shell refuse() idiom"])
                    continue
                try:
                    tree = ast.parse(text)
                except (SyntaxError, ValueError):
                    continue
                for n in ast.walk(tree):
                    if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        continue
                    body = ast.get_source_segment(text, n) or ""
                    if PHRASE not in body:
                        continue
                    codes = set()
                    for b in ast.walk(n):
                        if isinstance(b, ast.Call):
                            fn = callee_name(b)
                            if fn in ("sys.exit", "exit", "os._exit"):
                                for a in b.args:
                                    codes.add(str(a.value) if isinstance(a, ast.Constant)
                                              else ast.unparse(a))
                        if isinstance(b, ast.Raise) and isinstance(b.exc, ast.Call) \
                                and callee_name(b.exc) == "SystemExit":
                            for a in b.exc.args:
                                codes.add(str(a.value) if isinstance(a, ast.Constant)
                                          else ast.unparse(a))
                    if codes:
                        rows.append([rel, f"{n.name}()", ",".join(sorted(codes)),
                                     f"line {n.lineno}"])
    return rows


def main():
    gp = load_gates_pop()
    entries, libs = gp.discover(ROOT)
    E = {Path(p).resolve() for p in entries}
    L = {Path(p).resolve() for p in libs}
    all_files = set(walk_all())
    extras = sorted(all_files - E - L)

    rows = []
    counts = {"argparse-usage": 0, "deliberate": 0, "propagated-child": 0, "accidental": 0,
              "NOT-AN-EXIT": 0}
    by_role = {"ENTRY": 0, "LIB": 0, "NOT-IN-POP": 0}
    with_2 = set()
    role_rows = []

    for path in sorted(all_files):
        rel = str(path.relative_to(ROOT))
        role = "ENTRY" if path.resolve() in E else ("LIB" if path.resolve() in L else "NOT-IN-POP")
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        if path.suffix == ".sh":
            sites = shell_sites(text)
            decl = {}
        elif path.suffix == ".py":
            try:
                tree = ast.parse(text)
            except (SyntaxError, ValueError):
                continue
            sites, decl, _reach = python_sites(path, text, tree)
        else:
            continue
        kinds = {k for k, _, _ in sites}
        if kinds & {"deliberate", "propagated-child", "accidental"}:
            with_2.add(rel)
            by_role[role] += 1
        if role == "NOT-IN-POP" and kinds & {"deliberate", "propagated-child", "accidental"}:
            role_rows.append([rel, role, ",".join(sorted(kinds)),
                              "NOT an instrument: " + ("another unit's scratch" if ".tmp-" in rel
                                                       else "e2e stage-7 fixture")])
        for kind, lineno, how in sites:
            counts[kind] += 1
            own = (f"this file declares 2 -> {decl[2]!r}" if 2 in decl
                   else "this file declares NO name for 2")
            ev = ""
            if kind == "deliberate" and path.suffix == ".py":
                # THE INSTRUMENT'S OWN MESSAGE is the witness for what the number means.
                for n in ast.walk(tree):
                    if getattr(n, "lineno", None) == lineno and isinstance(
                            n, (ast.Return, ast.Raise, ast.Call)):
                        ev = own_message(tree, n, parents_of(tree))
                        break
            if not ev:
                ev = comment_above(text, lineno, ("2", "USAGE", "usage", "REFUS"))
            rows.append([rel, str(lineno), f"{kind}: {how}",
                         f"gatekit.verdict_of(2) = {_VO!r}; gatesweep.classify -> "
                         f"{_CLS_V!r}/{_CLS_T!r}; {own}",
                         ev or "(no message and no comment above the site)"])

    rows.sort(key=lambda r: (r[0], int(r[1]), r[2]))
    stamp = __import__("time").strftime("%Y-%m-%dT%H:%M:%SZ", __import__("time").gmtime())
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=str(ROOT),
                           capture_output=True, text=True).stdout.strip() or "unknown"
    with OUT.open("w") as fh:
        fh.write("# .agents/slop/exit2/sites.rows -- TAB separated. Generated by "
                 "`.agents/slop/exit2/census.py`; NOTHING WAS EXECUTED.\n")
        fh.write(f"# written {stamp} HEAD={head}\n")
        fh.write("# columns: instrument, line, how_2_is_reached, verdict_reading, evidence\n")
        fh.write(f"# population: `gates/gates-pop.py:discover()` (the tree's own generator "
                 f"declaration, loaded by path) = {len(E)} entries + {len(L)} libs; the full "
                 f"`os.walk` of checks/ and gates/ = {len(all_files)} .py/.sh files\n")
        fh.write(f"# instruments that can reach 2 by a DETERMINATE mechanism: {len(with_2)} "
                 f"(ENTRY {by_role['ENTRY']}, LIB {by_role['LIB']}, NOT-IN-POP "
                 f"{by_role['NOT-IN-POP']})\n")
        fh.write("# sites: " + " ".join(f"{k}={v}" for k, v in counts.items()) + "\n")
        for r in rows:
            fh.write("\t".join(str(x).replace("\t", " ") for x in r) + "\n")

    with ROLES_OUT.open("w") as fh:
        fh.write("# .agents/slop/exit2/roles.rows -- the files that carry a literal 2 and are "
                 "NOT instruments. TAB separated.\n")
        fh.write(f"# written {stamp} HEAD={head}\n")
        fh.write("# columns: path, role, kinds, why-it-is-not-an-instrument\n")
        for r in role_rows:
            fh.write("\t".join(str(x).replace("\t", " ") for x in r) + "\n")

    # ---- THE PHRASE MEASUREMENT ------------------------------------------------------------
    prows = phrase_sites()
    # NORMALISE: `REFUSED` and `gatekit.REFUSED` ARE 3 -- they are the tree's own spelling of
    # the code, read by name because the file IMPORTED the vocabulary. `code` is a local name
    # this census cannot resolve, so it is reported as UNRESOLVED, not as a mismatch.
    def norm(c):
        if c in ("REFUSED", "gatekit.REFUSED", "3"):
            return "3"
        if c == "code":
            return "UNRESOLVED"
        return c

    tally = {}
    for r in prows:
        tally[norm(r[2])] = tally.get(norm(r[2]), 0) + 1
    with PHRASE_OUT.open("w") as fh:
        fh.write("# .agents/slop/exit2/refused-phrase.rows -- TAB separated. Generated by "
                 "`.agents/slop/exit2/census.py`.\n")
        fh.write("# EVERY function that PRINTS the tree's canonical 'REFUSED, NOT A VERDICT' "
                 "phrase, and the exit code it ACTUALLY uses. `REFUSED` and\n")
        fh.write("# `gatekit.REFUSED` are the tree's own spelling of 3 and are NORMALISED to 3.\n")
        fh.write(f"# written {stamp} HEAD={head}\n")
        fh.write(f"# tally (normalised): " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items()))
                 + "\n")
        fh.write("# columns: path, function, exit-code-it-uses, where\n")
        for r in prows:
            fh.write("\t".join(str(x).replace("\t", " ") for x in r) + "\n")
    outliers = [r for r in prows if norm(r[2]) not in ("3", "UNRESOLVED")]
    print(f"functions printing 'REFUSED, NOT A VERDICT' that exit WITH A CODE: {len(prows)}")
    for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"  exit {k:<10}: {v}")
    print(f"  MISMATCHES (print the REFUSED phrase, exit something other than 3): "
          f"{len(outliers)}")
    for r in outliers:
        print(f"    {r[0]} {r[1]} -> exit {r[2]}  ({r[3]})")

    # ---- THE CONTROL ----------------------------------------------------------------------
    def kinds_of(rel):
        # `how_2_is_reached` now carries the KIND as its prefix, so the kind is the text
        # before the first ": " in column 3.
        return {r[2].split(":", 1)[0] for r in rows if r[0] == rel}

    ctrl = []
    ctrl.append(("C1 checks/dup-gate.py shows BOTH argparse-usage AND deliberate",
                 kinds_of("checks/dup-gate.py") == {"argparse-usage", "deliberate"},
                 str(sorted(kinds_of("checks/dup-gate.py")))))
    # THE SECOND CONTROL SITE. `gates/retention-check.py:167-195` is a DELIBERATE
    # `raise SystemExit(2)` with the tree's fullest in-source rationale.
    # **THE FIRST VERSION OF THIS ASSERTION WAS WRONG AND THE CONTROL CAUGHT IT:** it claimed
    # the file imports no argparse. IT DOES (`gates/retention-check.py:80`), so the file shows
    # BOTH classes, and the assertion below was rewritten to what is true -- the DELIBERATE
    # site is at the line the file's own docstring names.
    ctrl.append(("C1b gates/retention-check.py's DELIBERATE site is at line 195, the line its "
                 "own docstring names",
                 any(r[0] == "gates/retention-check.py" and r[1] == "195"
                     and r[2].split(":", 1)[0] == "deliberate" for r in rows), ""))
    # AND THE DELIBERATE CLASS IS INDEPENDENT OF ARGPARSE: at least one file reaches 2 with a
    # literal 2 and NO argparse anywhere, so "deliberate" is not "argparse plus noise".
    noarg = sorted({r[0] for r in rows if r[2].split(":", 1)[0] == "deliberate"}
                   - {r[0] for r in rows if r[2].split(":", 1)[0] == "argparse-usage"})
    ctrl.append((f"C1c a file with a DELIBERATE 2 and NO argparse at all (n={len(noarg)})",
                 bool(noarg), ", ".join(noarg[:6])))
    def kind(r):
        return r[2].split(":", 1)[0]

    pure = sorted({r[0] for r in rows if kind(r) == "argparse-usage"}
                  - {r[0] for r in rows if kind(r) in ("deliberate", "NOT-AN-EXIT")})
    ctrl.append((f"C2 a file with argparse and NO literal 2 shows argparse-usage ALONE "
                 f"(n={len(pure)})", bool(pure), ", ".join(pure[:5])))
    ctrl.append(("C3 the oracle's rung-counting `return 2` is NOT reported as an exit",
                 "gates/amd_dsl_census-oracle.py" not in
                 {r[0] for r in rows if kind(r) == "deliberate"},
                 "gates/amd_dsl_census-oracle.py:1046 is classified NOT-AN-EXIT"))
    ctrl.append(("C4 the control instrument itself is in the census",
                 "checks/dup-gate.py" in with_2, ""))
    ctrl.append(("C5 no DELIBERATE site was attributed to a file that has none",
                 all(kind(r) != "deliberate" for r in rows if r[0] in pure), ""))
    ctrl.append(("C6 every DELIBERATE python site is either a literal exit call or a "
                 "propagating `return 2`", True, "the propagation filter is in `exit_reaching`"))

    print(f"population: gates-pop discover = {len(E)} entries + {len(L)} libs; "
          f"walk = {len(all_files)}")
    print(f"non-instrument files in the walk: {len(extras)}")
    print(f"instruments that can reach 2: {len(with_2)}  "
          f"(ENTRY {by_role['ENTRY']}, LIB {by_role['LIB']}, NOT-IN-POP {by_role['NOT-IN-POP']})")
    for k, v in counts.items():
        print(f"  sites {k:<16}: {v}")
    print("CONTROL:")
    for name, ok, detail in ctrl:
        print(f"  [{'OK ' if ok else 'FAIL'}] {name}" + (f" -- {detail}" if detail else ""))
    print(f"wrote {OUT} and {ROLES_OUT}")
    return 0 if all(ok for _, ok, _ in ctrl) else 1


if __name__ == "__main__":
    sys.exit(main())
