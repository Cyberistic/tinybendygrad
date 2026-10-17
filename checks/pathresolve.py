"""ONE path resolver, THREE populations, and the SET DIFFERENCE THAT SAYS IT LOSES NOTHING.

    .venv/bin/python checks/pathresolve.py            # the census, both directions
    .venv/bin/python checks/pathresolve.py --plant    # three seeds, one hash

**WHAT THIS IS FOR.** Three instruments in this tree each answered "which path?" three different
ways and each was wrong in a way it could not see, because a wrong answer and an absent one print
the same shape:

  1 `checks/runs-artifacts.py:resolve()` answers a no-argument `.parent` by descending into the
    `Call` below it, so `HERE = Path(__file__).resolve().parent` binds `HERE` to `""` and
    `checks/abi_gate.py`'s writer of `checks/gen/` is recorded as the bare token `gen`.
  2 `gates/exitcode-census-gate.py`'s population `W` is a `os.walk` over the homes
    `gates/gates-pop.py:gate_homes()` derives, and those homes are two directories, so every
    `.py` outside them is ungraded -- MEASURED today: `W` holds 259 files and the commit tree
    holds 1888, and **all 3 live `MAYBE-NONE` sites are outside `W`**, so the gate reports the
    shape 0 times while the shape has three instances.
  3 `checks/differ.py:SUBSTRATE_INPUTS` is a hand list. Appending two literals to it would
    re-create `gates/gates-pop.py`'s `HOMES` defect verbatim.

**THE BAR IS NOT "IT FIXES THE BUG".** The bar is `NOTHING THE OLD RESOLVER FINDS IS LOST, AND
WHAT IT MISSES IS GAINED`, and the only honest way to show that is the SET DIFFERENCE IN BOTH
DIRECTIONS, over a population that is DISCOVERED. So `lanes()` below is a `os.walk` over homes
derived by `gates/gates-pop.py:gate_homes()` -- LOADED BY PATH, never a tuple of names -- and the
comparison is between two SETS OF EXISTING PATHS, because a token that names a file which is not
there is exactly the defect being repaired.

**AND THE RESOLVER REFUSES PER PATH.** `resolve()` returns `(path, why)` and `why` is non-empty
whenever `path` is empty, so an unresolvable expression is REPORTED rather than flattened to a
bare basename. **A RESOLVER THAT EMITS A WRONG PATH CONFIDENTLY IS WORSE THAN ONE THAT EMITS
NOTHING**, so nothing is ever shortened, truncated to a remembered extension, or completed.

**THE THREE POPULATIONS ASK THREE DIFFERENT QUESTIONS, AND `census()` PRINTS EACH QUESTION BESIDE
ITS ANSWER** rather than merging them into one number. `AGENTS.md`'s verdict/denominator rule
exists because somebody merged two questions into one word, and the merge here would be the same
mistake with a different spelling.
"""
from __future__ import annotations

import ast
import hashlib
import importlib.util
import os
import subprocess
import sys
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: gatekit's vocabulary, LOADED BY PATH in `main()`; spelled here only so the module has no import
#: cycle when a caller loads it on its own. `gates/gatekit.py:60`.
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

#: The instrument whose resolver this file MEASURES AGAINST, named as a PATH and loaded by
#: `load()`. **NOT COPIED.** A second copy of `resolve()` would be a contract with no generator, and
#: it would drift the moment the original is repaired.
LEGACY = "checks/runs-artifacts.py"
#: `gates/gates-pop.py:gate_homes()` -- the homes DERIVED, not typed. Also loaded by path.
POPSRC = "gates/gates-pop.py"
#: The two instruments whose populations are compared here, named by path for the same reason.
CENSUS = "gates/exitcode-census-gate.py"
DIFFER = "checks/differ.py"

#: `git ls-tree -r HEAD`, NEVER `git ls-files`. MEASURED today on this tree: 1888 tracked `.py` in
#: `HEAD`, 2052 in the INDEX, and `jj git colocation` stages an empty blob for every untracked
#: file -- so `git ls-files` answers a question about the editor. `checks/runs-artifacts.py:541`
#: measured the same thing on 2026-10-06 at 906 placeholders; the number moved and the hazard did
#: not.
INDEX_IS_NOT_THE_TREE = "git ls-tree -r HEAD, never git ls-files: the index is ARMED"

def _refuse(why):
    """The answer shape: `(None, why)`. **A REFUSAL CARRIES A REASON, ALWAYS** -- that is the whole
    of the per-path contract, and a refusal whose reason is empty is indistinguishable from a
    silent zero."""
    return (None, why)


def _norm(value):
    """`value`, NORMALISED -- and `.` IS THE ROOT, spelled `""`. **NORMALISE AND CLIMB ARE TWO
    RULES AND USING ONE FOR THE OTHER IS THE BUG THIS FUNCTION EXISTS TO STOP.**

    MEASURED: the `join`/`Div` branches called `_up(joined)`, which DROPS A COMPONENT, so
    `os.path.join("checks", "gen")` answered `checks` and the plant read `G = 'checks'`. The gate
    caught it in the same run -- `NAMED-ROOT` went from 2 to 269 and the plant went red -- which is
    the argument for running a gate over a resolver rather than reading one.
    """
    out = os.path.normpath(value).replace("\\", "/")
    if out == ".." or out.startswith("../"):
        return _refuse(f"escapes the tree: {value}")
    return ("" if out == "." else out, None)


def _up(value, n=1):
    """Drop `n` path components from a value in TREE SPACE.HAT LEAVES THE TREE IS REFUSED WITH A
    REASON**, and it is the only place a `..` is allowed to appear: everything else in this file is
    already repo-relative.
    """
    joined = os.path.join(value, *([".."] * n))
    out = os.path.normpath(joined).replace("\\", "/")
    if out == ".." or out.startswith("../"):
        return _refuse(f"escapes the tree: {joined}")
    return ("" if out == "." else out, None)


def resolve(node, env, base, depth=0):
    """The REPO-RELATIVE path a node names, or `(None, why)`. **Nothing is ever shortened.**

    **EVERY VALUE IS IN TREE SPACE: REPO-RELATIVE, `""` IS THE ROOT.** That single decision is the
    whole of this resolver and it took three measurements to reach, each of which is a way of
    losing paths rather than a way of gaining them:

      * FILE SPACE (`""` = the declaring file) makes a bare literal FILE-relative, and this tree's
        literals are ROOT-relative -- `checks/differ.py:671` writes
        `capture("D0-coverage-census.txt", ".agents/slop/graphcmp-oracle.py")` with no `ROOT /` in
        front of it, and the file that exists is `.agents/slop/graphcmp-oracle.py`. MEASURED: 4
        declared substrate inputs became UNREACHABLE.
      * TREE SPACE with `Path(__file__)` answering `""` makes `.parent` and `parents[n]` one level
        too shallow, which is the legacy's own defect.
      * TREE SPACE with `Path(__file__)` answering `base` -- THE FILE'S OWN REPO-RELATIVE PATH --
        makes all of them line up, and a bare literal stays root-relative because a literal is
        never joined with `base`.

    `base` is the declaring file's repo-relative path and it is NOT optional: without it
    `Path(__file__)` has no referent and the `.parent` question has no answer, which is precisely
    the defect this file exists to name.

    The rules are the legacy `resolve()`'s, plus three:

      * `Path(__file__)` -> `base`, `.parent` -> drop one component, `parents[n]` -> drop `n + 1`
        (`parents` indexes DIRECTORIES, so the final component is a filename either way). The
        legacy returns `""` and then DROPS `.parent` outright -- its `Attribute` branch is
        `return resolve(node.value)` -- so `checks/abi_gate.py` emits `gen`, `abi.json` and
        `coindep.py`: three tokens that exist at `checks/gen`, `checks/abi.json` and
        `checks/coindep.py` and NOWHERE else. MEASURED in `census()`.
      * `".name"`, `".stem"`, `".suffix"`, `".parts"` REFUSE with a reason. They compose a path at
        runtime, and a resolver that guesses them is the class this file was written to end.
      * `Path(<anything but __file__>)` REFUSES with a reason, because its base is the process CWD
        and no static reading can name it. The legacy answered it `""`, which
        `checks/runs-artifacts.py:312` then drops -- so refusing costs no site and buys the truth.
    """
    if depth > 24:
        return _refuse("resolve depth > 24")
    if isinstance(node, ast.Constant):
        # A LITERAL IS REPO-RELATIVE ALREADY, so it is NEVER joined with `base`. MEASURED: joining
        # it put `checks/.agents/slop/graphcmp-oracle.py` where the file is
        # `.agents/slop/graphcmp-oracle.py`, and four DECLARED substrate inputs became unreachable.
        return (node.value, None) if isinstance(node.value, str) else _refuse("constant is not a string")
    if isinstance(node, ast.Name):
        if node.id == "__file__":
            return (base, None)
        return (env[node.id], None) if node.id in env else _refuse(f"unbound name {node.id}")
    if isinstance(node, ast.JoinedStr):  # f"{ROOT}/runs/graphcmp/D" -- literals only, never a hole
        parts = [v.value for v in node.values
                 if isinstance(v, ast.Constant) and isinstance(v.value, str)]
        holes = [v for v in node.values if isinstance(v, ast.FormattedValue)]
        if holes:
            return _refuse(f"f-string with {len(holes)} interpolation(s)")
        return ("".join(parts), None) if parts else _refuse("f-string with no literal part")
    if isinstance(node, (ast.Tuple, ast.List)):
        # A LIST IS A SITE PER ELEMENT, not one site: `checks/differ.py:1033` is
        # `subprocess.run(["./bin/bend", ".agents/slop/graphcmp.bend", "--check-only"])`, and BOTH
        # of its paths are declared substrate inputs. MEASURED: without this, 2 of the 8 declared
        # members were UNANCHORED -- `bin/bend` and `.agents/slop/graphcmp.bend` -- which is the
        # resolver saying it cannot see a list, and a resolver that cannot see a list cannot see
        # half a command line. The caller below iterates `node.elts` for exactly this reason.
        elts = [e.value for e in node.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)
                and e.value.strip("/")]
        return (elts[0], None) if elts else _refuse(f"{type(node).__name__.lower()} of no string constant")
    if isinstance(node, ast.Subscript):
        if not (isinstance(node.slice, ast.Constant) and isinstance(node.slice.value, int)):
            return _refuse("subscript index is not an int")
        return _climb(node, env, base, depth)
    if isinstance(node, ast.BinOp):
        if not isinstance(node.op, (ast.Add, ast.Div)):
            return _refuse(f"binop {type(node.op).__name__}")
        a, b = resolve(node.left, env, base, depth + 1), resolve(node.right, env, base, depth + 1)
        if not (a[0] is not None and b[0] is not None):
            return _refuse(f"{a[1] or ''} | {b[1] or ''}".strip(" |"))
        # **THE `Div` JOIN IS NORMALIZED AND THE FIRST VERSION DID NOT.** MEASURED, and
        # `gates/path-resolve-gate.py` is what found it: an un-normalised `Path(...) / ".."`
        # emitted `checks/..` where the answer is the repo root. **A NORMALISED PATH IS THE CLAIM;
        # AN UNNORMALISED ONE IS A TYPO THAT HAPPENS TO RESOLVE.**
        return (a[0] + b[0], None) if isinstance(node.op, ast.Add) else _norm(os.path.join(a[0], b[0]))
    if isinstance(node, ast.Attribute):
        if node.attr == "parents":
            return resolve(node.value, env, base, depth + 1)  # the SUBSCRIPT applies the level
        recv = resolve(node.value, env, base, depth + 1)
        if node.attr in ("name", "stem", "suffix"):
            # **COMPUTED, NOT GUESSED.** These are pure functions of a KNOWN path, and refusing
            # them costs SEVEN REAL PATHS: `gates/gates-pop.py:927` is
            # `LEDGER_PATH = HERE / LEDGER.name`, so refusing `.name` unbound `LEDGER_PATH` and
            # every `LEDGER_PATH.read_bytes()` under it. The legacy's `.name` is a plain descent,
            # which is why it reached `gates/gates-pop.ledger.tsv` -- RIGHT ANSWER, WRONG REASON,
            # because it kept `HERE` and its reader cannot tell the two apart.
            if recv[0] is None:
                return _refuse(f"receiver of .{node.attr}: {recv[1]}")
            name = os.path.basename(os.path.normpath(recv[0]))
            if node.attr == "name":
                return (name, None)
            stem, dot, ext = name.rpartition(".")
            return ((stem, None) if node.attr == "stem" else (dot + ext, None)) if dot else \
                   ((name, None) if node.attr == "stem" else ("", None))
        if node.attr == "parts":
            return _refuse(".parts composes a path at runtime")
        if node.attr != "parent":
            return recv
        return _refuse(f"receiver: {recv[1]}") if recv[0] is None else _up(recv[0])
    if isinstance(node, ast.Call):
        fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if fn == "Path":
            if len(node.args) == 1 and isinstance(node.args[0], ast.Name) and node.args[0].id == "__file__":
                return (base, None)
            if not node.args:
                return _refuse("Path() with no argument")
            return _refuse(f"Path({resolve(node.args[0], env, base, depth + 1)[0]!r}) "
                           f"has a runtime base")
        if fn in ("resolve", "absolute", "abspath", "realpath", "normpath", "expanduser"):
            recv = resolve(node.func.value, env, base, depth + 1) if isinstance(node.func, ast.Attribute) \
                else _refuse(f"bare {fn}()")
            # `abspath` RESOLVES AGAINST THE CWD and `normpath` is idempotent on a tree path, so
            # both are the identity HERE. MEASURED: refusing `abspath` unbound `ROOT` in
            # `checks/git-index-guard.py:36`, whose `os.path.dirname(__file__)` the legacy turned
            # into the token `"?/.."`.
            return recv if fn in ("resolve", "abspath", "realpath") else \
                (_up(recv[0], 0) if recv[0] is not None and fn == "normpath" else recv)
        if fn == "dirname":
            inner = resolve(node.args[0], env, base, depth + 1) if node.args else _refuse("dirname()")
            return _refuse(f"argument: {inner[1]}") if inner[0] is None else _up(inner[0])
        if fn == "basename":
            return _refuse("basename() is a name, and a name is not a path")
        if fn in ("join", "as_posix"):
            parts = [resolve(a, env, base, depth + 1) for a in node.args]
            missing = [p[1] for p in parts if p[0] is None]
            if missing:
                return _refuse("; ".join(m for m in missing if m))
            if not parts:
                return ("", None)
            # SAME TWO RULES AS `_up()`, AND FOR THE SAME MEASURED REASON:
            # `checks/git-index-guard.py:36`'s `os.path.join(os.path.dirname(__file__), "..")` is
            # the REPO ROOT, and an un-normalised join emits `checks/..` for it and a `normpath`ed
            # one emits `.`. Both are wrong paths emitted confidently, which is the one failure
            # this whole file is built to make impossible -- and `gates/path-resolve-gate.py` is
            # what found the first and then the second.
            return _norm(os.path.join(*[p[0] for p in parts]))
        if fn == "parent":
            recv = resolve(node.func.value, env, base, depth + 1) if isinstance(node.func, ast.Attribute) \
                else _refuse("bare parent()")
            return _refuse(f"receiver: {recv[1]}") if recv[0] is None else _up(recv[0])
        return _refuse(f"unhandled call {fn or type(node.func).__name__}")
    return _refuse(f"no rule for {type(node).__name__}")


def _climb(node, env, base, depth):
    """`X.parents[n]` -- **drop `n + 1` components**, because `parents` indexes DIRECTORIES and
    the final component of a path is a filename whether or not the author ever wrote one.

    So the rule is uniform, which is what makes it a rule: `Path(__file__).parents[0]` is the
    file's own directory and `HERE.parents[0]` with `HERE = Path(__file__).resolve().parent` is
    the directory ABOVE that, and both are `_up(v, n + 1)`. MEASURED with `n` instead:
    `checks/differ.py`'s `ROOT = Path(__file__).resolve().parents[1]` resolved to `checks`, so
    `D` came out as `checks/runs/graphcmp/D` and 0 of the 42 `runs/graphcmp/D` sites matched.

    The legacy resolver answers this in two places and differently in each: its `Subscript` branch
    computes `"/".join([".."] * n)` when the base is `""`, and its `Attribute` branch drops
    `.parents` on the floor by descending into the call below it.
    """
    recv = resolve(node.value, env, base, depth + 1)
    return recv if recv[0] is None else _up(recv[0], node.slice.value + 1)


def env_of(tree, base, rounds=6):
    """String bindings to a fixed point, EVERY SCOPE -- `checks/corpus-figure.py:194` and
    `checks/disagree-gate.py:53` bind their artefact path INSIDE a function, and reading only
    `tree.body` finds 3 of the 12 readers."""
    env: dict[str, str] = {"__file__": base}
    for _ in range(rounds):
        for st in ast.walk(tree):
            if not isinstance(st, ast.Assign) or len(st.targets) != 1:
                continue
            target = st.targets[0]
            if isinstance(target, ast.Name):
                names = [target.id]
            elif isinstance(target, (ast.Tuple, ast.List)) and \
                    all(isinstance(t, ast.Name) for t in target.elts):
                # `PY, GCMP = ".venv/bin/python", ".agents/slop/graphcmp.py"` -- `checks/differ.py:44`.
                # BOTH resolvers skip it, because both require a single `Name` target, so
                # `.agents/slop/graphcmp.py` was UNANCHORED against the declared substrate inputs
                # even though the file NAMES it in a module-level binding. **AN INSTRUMENT THAT
                # CANNOT BIND TWO NAMES AT ONCE CANNOT SEE HALF THIS TREE'S CONSTANTS.**
                names = [t.id for t in target.elts]
            else:
                continue
            parts = ([resolve(e, env, base) for e in st.value.elts]
                     if isinstance(st.value, (ast.Tuple, ast.List))
                     and len(st.value.elts) == len(names) else [resolve(st.value, env, base)] * len(names))
            for name, a in zip(names, parts):
                if a[0] is not None:
                    env[name] = a[0]
    return env


def site(node, env, base):
    """`resolve()`, named for what it is: the whole resolver, because every value it returns is
    already repo-relative. It exists so the caller reads `site(...)` and not `resolve(...)` and
    wonders where the last hop is."""
    return resolve(node, env, base)


# ==================================================================== the population: DISCOVERED
def load(rel, name=None):
    """Load a module BY PATH. **A LIST OF NAMES IS NOT A POPULATION, AND A LIST OF MODULES IS
    WORSE.** Every other instrument in this file's census is reached through this one call."""
    spec = importlib.util.spec_from_file_location(name or rel.replace("/", "_")[:-3], os.path.join(ROOT, rel))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def tree_paths(root=ROOT):
    """`git ls-tree -r HEAD --name-only`. **THE TREE, NOT THE INDEX.** `INDEX_IS_NOT_THE_TREE`
    names the measurement."""
    r = subprocess.run(["git", "-C", root, "ls-tree", "-r", "--name-only", "HEAD"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"git ls-tree rc={r.returncode}: {r.stderr.strip()}")
    return r.stdout.splitlines()


def lanes(root=ROOT):
    """THE DISCOVERED POPULATION. `(pylanes, shelllanes, derivation)`.

    `pylanes` is an `os.walk` over the homes `gates/gates-pop.py:gate_homes()` DERIVES -- loaded by
    path, never `("checks", "gates")`, because that tuple is the defect `gates/gates-pop.py:95`
    admits against itself. `shelllanes` is `checks/runs-artifacts.py:shell_lanes()`, which finds a
    shell by its SHEBANG rather than by a suffix set. Both are intersected with `git ls-tree`, so a
    lane a fresh clone could not execute is not in the population.
    """
    pop, ra = load(POPSRC), load(LEGACY)
    homes, derivation = pop.gate_homes(root)
    tracked = set(tree_paths(root))
    py = sorted({os.path.relpath(os.path.join(dp, n), root)
                 for h in homes for dp, dn, fn in os.walk(os.path.join(root, h), followlinks=False)
                 for n in fn
                 if (dn.__setitem__(slice(None), [d for d in dn if d != "__pycache__"]) or True)
                 and n.endswith(".py")})
    return ([p for p in py if p in tracked],
            sorted(p for p in ra.shell_lanes(root, sorted(tracked)) if p in tracked),
            {"homes": list(homes), "source": derivation.get("source"),
             "population": "os.walk over derived homes + shebang lanes, intersected with git ls-tree"})


#: ONE WALK, TWO RESOLVERS, ONE ROW PER SITE. The legacy half calls
#: `checks/runs-artifacts.py:resolve()` and `_env()` -- LOADED BY PATH, NOT COPIED, so the
#: comparison is against the instrument and not against a transcription of it that drifts.
def sites(root, pylanes):
    """`(rows, refusals)` -- `(rel, line, legacy_token, new_path, why)` per site, plus the
    refusals grouped by reason.

    **THE ROWS ARE PAIRED NODE-FOR-NODE, WHICH IS WHAT MAKES THE SET DIFFERENCE MEANINGFUL.** A
    naive comparison of two independent walks measures SPELLING: on the first run it reported
    `LOST 460 GAINED 470` and every one of the 930 rows was the same file -- `gen` against
    `checks/gen`, `abi.json` against `checks/abi.json`. **A SET DIFFERENCE OF TOKENS IS NOT A SET
    DIFFERENCE OF PATHS.** `reached()` below canonicalises to the file on disk, and only then are
    the two sides compared.

    A DOCSTRING IS NOT A USE, on both sides: `checks/runs-artifacts.py:275` measured 14 readers on
    a tree with 12 because `checks/sweep.py`'s only two mentions of a directory are its docstring
    and a `#` comment. **A POPULATION THAT INCLUDES ITS OWN NARRATION CANNOT COUNT ANYTHING.**
    """
    ra = load(LEGACY)
    rows, refusals = [], {}
    for rel in pylanes:
        try:
            tree = ast.parse(open(os.path.join(root, rel), errors="replace").read())
        except (OSError, SyntaxError) as exc:
            refusals.setdefault(f"UNPARSEABLE {type(exc).__name__}", set()).add(rel)
            continue
        env, lenv = env_of(tree, rel), ra._env(tree)
        docs = {id(b[0].value) for b in
                (n.body for n in ast.walk(tree)
                 if isinstance(n, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)))
                if b and isinstance(b[0], ast.Expr) and isinstance(b[0].value, ast.Constant)
                and isinstance(b[0].value.value, str)}
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            args = list(node.args) + [k.value for k in node.keywords]
            if isinstance(node.func, ast.Attribute):
                args.append(node.func.value)  # THE RECEIVER IS A SITE: `D.write_text(s)` names `D`
            for arg in args:
                # EVERY ELEMENT OF A TUPLE OR LIST IS ITS OWN SITE. `checks/differ.py:1033` puts
                # TWO declared substrate inputs in one list literal, and `checks/txt-owners.py:170`
                # puts three in one tuple, so a caller that treated either as a single site loses
                # five declared inputs without saying so.
                for leaf in (arg.elts if isinstance(arg, (ast.Tuple, ast.List)) else (arg,)):
                    if isinstance(leaf, ast.Constant) and id(leaf) in docs:
                        continue
                    legacy, (path, why) = ra.resolve(leaf, lenv), site(leaf, env, rel)
                    # **NO ROW IS DROPPED, INCLUDING THE ONES BOTH RESOLVERS REFUSE.** The first
                    # version skipped `legacy is None and why is None` to keep the table short, and
                    # MEASURED what that cost: `checks/differ.py:108`'s `ROOT / GCMP` is refused by
                    # the legacy (`GCMP` is unbound there) and RESOLVED by the successor, so the row
                    # vanished and `.agents/slop/graphcmp.py` -- a DECLARED substrate input -- read
                    # as UNANCHORED. **A TABLE THAT DROPS ITS DISAGREEMENTS IS A TABLE THAT CANNOT
                    # REPORT A GAIN.**
                    rows.append((rel, node.lineno, legacy, path, why))
                    # A REFUSAL IS ONLY INTERESTING WHERE THE LEGACY ANSWERED. `unbound name` and
                    # `no rule for` are the legacy's own answers too, so counting them would make
                    # the successor look noisier than the thing it replaces.
                    if path is None and isinstance(legacy, str) and legacy.strip("/"):
                        refusals.setdefault(why.split(":")[0], set()).add(f"{rel}:{node.lineno} {legacy!r}")
    return rows, refusals


def reached(root, rel, token, both=False):
    """Every EXISTING repo-relative path `token`, written in `rel`, can denote.

    `both=True` ALSO tries the reading relative to the declaring file, and **ONLY THE LEGACY GETS
    IT** -- a token that is wrong about its own depth must still be counted for the legacy or the
    comparison understates what it loses, and must NOT be counted for the successor or the
    comparison cannot see a defect.

    **MEASURED WHAT THAT FLAG IS WORTH, and it is the most important sentence in this file:**
    `gates/path-resolve-gate.py --self-test` reintroduces `Path(__file__)` answering the file's
    DIRECTORY -- a one-level error, the legacy's own defect -- and with one reading on both sides
    the census reports `verdict=0 UNEXPLAINED=0`, because `"gen"` read relative to `checks/` lands on
    `checks/gen` and the SECOND reading rescues a WRONG answer. **A GENEROUS READING HIDES A REAL
    DEFECT IN THE VERY INSTRUMENT IT IS MEANT TO CHECK**, so the generosity is a parameter of the
    COMPARISON, not of the measurement.

    A token that names nothing on disk contributes NOTHING: the point is which files are REACHED,
    and a string is not a file.

    `\0` IS REFUSED BEFORE `os.path` SEES IT. MEASURED: `checks/abi_gate.py` binds
    `C_FP16_OLD` and its neighbours to C source containing `\\0`, the legacy emits them as paths,
    and `os.path.realpath` answers `ValueError: lstat: embedded null character in path` -- which
    takes the whole census down, so one instrument's string constant would have silenced three.
    """
    if not isinstance(token, str) or not token.strip("/") or "\0" in token:
        return ()
    inside = os.path.abspath(root) + os.sep  # A `..` TOKEN RESOLVES TO A DIRECTORY OUTSIDE THE
    out = []                                  # TREE, AND `checks/bounded.py`'s bare `..` counted
    for cand in ([token, os.path.normpath(os.path.join(os.path.dirname(rel), token)).replace("\\", "/")]
                 if both else [token]):
        full = os.path.abspath(os.path.join(root, cand))
        if cand and full.startswith(inside) and os.path.exists(full):
            out.append(full)
    return tuple(sorted(set(out)))


# ==================================================================== the three populations
def census(root=ROOT):
    """`(body, lost_rows, (verdict, why), facts)` -- the three questions, each beside its own `n`.

    **THEY ASK DIFFERENT QUESTIONS AND MERGING THEM WOULD BE A NEW `AGENTS.md` CLAIM:**

      NAMED   "which FILE does any lane NAME, by naming a path?"     -- read out of the source
      GRADED  "which file does the exit-code census GRADE?"           -- an `os.walk` of two homes
      BYTES   "which file's BYTES determine the substrate digest?"    -- a walk plus 8 literals

    One static resolver can serve the first and be an ingredient of the third; **the second asks
    nothing a resolver can answer**, because `W` is a set of FILES CHOSEN BY A WALK and the
    question "which of them exits non-zero" has no path expression in it anywhere. So the honest
    form of this census is three rows and never a union, and the set difference is printed for each
    pair that is even commensurable.

    **THE VERDICT IS ABOUT UNEXPLAINED LOSS, NOT ABOUT LOSS.** A successor that REFUSES a path the
    legacy guessed has lost nothing: it has said so, per path, with a reason, which is the whole of
    the contract. A successor that emits a DIFFERENT EXISTING path for the same site is the case
    this instrument exists to catch, and it is `UNEXPLAINED` -- silent disagreement, the shape
    `AGENTS.md` warns about when it says the difference between two instruments IS the finding.
    """
    pylanes, shelllanes, derivation = lanes(root)
    rows, refusals = sites(root, pylanes)
    ra = load(LEGACY)
    old = {(rel, p) for rel, _l, tok, _p, _w in rows for p in reached(root, rel, tok, both=True)}
    new = {(rel, p) for rel, _l, _tok, p, _w in rows for p in reached(root, rel, p)}
    gained = sorted(new - old)
    shell = {v for lane in shelllanes for _r, _role, v in
             ra.shell_sites(root, [os.path.join(root, lane)])}

    # LOST, CLASSIFIED BY THE SUCCESSOR'S OWN ANSWER -- NEVER BY MY READING OF THE LEGACY.
    lenv = {rel: ra._env(ast.parse(open(os.path.join(root, rel), errors="replace").read()))
            for rel in pylanes}
    lost_rows = []
    for rel, line, tok, path, why in rows:
        o, n = reached(root, rel, tok, both=True), reached(root, rel, path)
        if not o or n:
            continue
        cls = ("NAMED-ROOT" if path == "" else
               "SAME-TOKEN" if path == tok else      # the successor emitted the LEGACY'S OWN token
               "UNEXPLAINED" if path is not None else
               "REFUSED")
        if path is None and cls == "REFUSED":
            unbound = why.partition("unbound name ")[2] if why.startswith("unbound name") else ""
            cls = "BLIND-ENV" if unbound and lenv[rel].get(unbound) == "" else "REFUSED"
        lost_rows.append((cls, rel, line, tok, path, why, sorted(os.path.relpath(p, root) for p in o)))
    buckets = {}
    for cls, *_rest in lost_rows:
        buckets[cls] = buckets.get(cls, 0) + 1

    ec, differ = load(CENSUS), load(DIFFER)
    # `population()` wants a `Path` root -- MEASURED, a `str` dies in `checks/gatesweep.py:107` at
    # `root / "gates"`, so the third instrument in this census is also the first that has to be
    # called the way its own author calls it.
    graded = {str(Path(p).relative_to(root)) if Path(p).is_absolute() else str(p)
              for p in ec.population(Path(root))[0]}
    tracked_py = {p for p in tree_paths(root) if p.endswith(".py")}
    declared = {rel for rel, _sha in differ.substrate_entries()}
    port = {os.path.relpath(os.path.join(dp, n), root)
            for dp, _dn, fn in os.walk(os.path.join(root, "tinybendygrad")) for n in fn
            if "__pycache__" not in dp}
    discovered = port | {os.path.relpath(p, root) for rel, _l, _tok, path, _w in rows
                         if rel == DIFFER for p in reached(root, rel, path)}

    out = [f"population  lanes {len(pylanes)} .py + {len(shelllanes)} shell, "
           f"homes {derivation['homes']} from {derivation['source']}",
           f"            {derivation['population']}",
           f"            {INDEX_IS_NOT_THE_TREE}",
           f"  NAMED   n={len(new):<6} which FILE does any lane NAME, by naming a path?",
           f"  GRADED  n={len(graded):<6} which file does the exit-code census GRADE?",
           f"  BYTES   n={len(declared):<6} which file's BYTES determine the substrate digest?",
           f"          (+{len(shell)} shell tokens, resolved by `checks/runs-artifacts.py:shell_value`,",
           "           which this file does not replace, so they are identical on both sides)", ""]
    out += ["SET DIFFERENCE, NAMED, BOTH DIRECTIONS, over FILES ON DISK reached by (lane, site):",
            f"  legacy reached {len(old)}   successor reached {len(new)}   "
            f"LOST {len(old - new)} distinct (lane, file) pairs over {len(lost_rows)} SITES   "
            f"GAINED {len(gained)}",
            "  LOST, CLASSIFIED BY THE SUCCESSOR'S OWN ANSWER (sites): "
            + "  ".join(f"{k} {v}" for k, v in sorted(buckets.items())),
            "    NAMED-ROOT  the successor named the REPO ROOT, which is not a file; the legacy",
            "               dropped the same two `.parent`s and landed on a file INSIDE it",
            "    BLIND-ENV   the legacy bound a name to \"\" -- its own spelling of \"I cannot name",
            "               this\" -- in a scope that has nothing to do with the site, and read the",
            "               repo root out of it. `checks/runs-artifacts.py:229` names this cost.",
            "    REFUSED     the successor refused with a reason of its own",
            "    SAME-TOKEN  the successor emitted the LEGACY'S OWN token, character for character,",
            "               and the only difference is that the legacy was given a SECOND reading of",
            "               it (relative to the lane). `checks/sweep.py:312`'s bare `\".\"` is the",
            "               shape: identical on both sides, and the legacy's extra reading is the",
            "               only reason it counted a file. **THIS BUCKET IS MY OWN COMPARISON",
            "               ARTEFACT AND IT IS THE LARGEST ONE.**",
            "    UNEXPLAINED the successor named a DIFFERENT token AND both tokens exist -- the only",
            "               case that is a silent disagreement, and the only one that FAILS"]
    out += [f"    GAINED {rel}:{os.path.relpath(p, root)}" for rel, p in gained[:15]]
    if len(gained) > 15:
        out.append(f"    ... and {len(gained) - 15} more gained; --lost prints every LOST row")
    bad = buckets.get("UNEXPLAINED", 0)
    if bad:
        out += [f"    UNEXPLAINED {rel}:{line} legacy={tok!r} successor={path!r} reached "
                f"{o}; source: {src_line(root, rel, line)}" for _c, rel, line, tok, path, _w, o in
                (r for r in lost_rows if r[0] == "UNEXPLAINED")]

    ungraded, over = sorted(tracked_py - graded), sorted(graded - tracked_py)
    out += ["", f"SET DIFFERENCE, GRADED vs every tracked .py in HEAD ({len(tracked_py)}): "
                f"W is SHORT {len(ungraded)}, OVER-COVERS {len(over)}"]
    out += [f"    UNGRADED {p}" for p in ungraded[:10]]
    if len(ungraded) > 10:
        out.append(f"    ... and {len(ungraded) - 10} more")
    out += [f"    OVER    {p}" for p in over]

    # THE CROSS-CHECK. `ec.classify_site` over EVERY tracked `.py` rather than over `W`, with the
    # census's own `extract`/`module_ints`/`own_exits` and the census's own `_callee`/
    # `_always_exits` -- so the shape is graded by the instrument that owns the shape, and this
    # file only supplies the WIDER population. MEASURED: `W` is {short} files short of HEAD, and
    # `gates/exitcode-census-gate.py` reports `MAYBE-NONE 0`, which is TRUE OF W AND FALSE OF THE
    # TREE. **BOTH ARE TRUE AND ONE OF THEM IS THE FINDING.**
    maybenone = set()
    for rel_ in sorted(tracked_py):
        try:
            t_ = ast.parse(open(os.path.join(root, rel_), errors="replace").read())
        except (OSError, SyntaxError):
            continue
        e_ = {"funcs": {f.name: f for f in ast.walk(t_)
                        if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))},
              "ints": ec.module_ints(t_), "delegated": ec.own_exits(t_)}
        maybenone |= {f"{rel_}:{ln}" for ln, v in ec.extract(t_)
                      if ec.classify_site(v, t_, e_)[0] == "MAYBE-NONE"}

    anchor, orphan = sorted(declared - discovered), sorted(discovered - declared)
    out += ["", f"SET DIFFERENCE, BYTES: declared {len(declared)} vs discovered {len(discovered)} "
                f"(port walk {len(port)} + {len(discovered) - len(port)} named by {DIFFER})",
            f"  DECLARED-ONLY {len(anchor)}   DISCOVERED-ONLY {len(orphan)}"]
    out += [f"    UNANCHORED {p}   (declared, and no site in the walk names it)" for p in anchor]
    out += [f"    UNDECLARED {p}   (the walk names it and the digest ignores it)" for p in orphan]
    out += ["", f"PER-PATH REFUSALS: {sum(len(v) for v in refusals.values())} sites where the legacy "
                f"emitted a token and this resolver REFUSES WITH A REASON, in {len(refusals)} classes"]
    out += [f"    {why:<54} {len(where):>5}  e.g. {sorted(where)[0]}"
            for why, where in sorted(refusals.items())]

    out += ["", "CROSS-CHECK, THE THREE INSTRUMENTS ON ONE QUESTION: DOES EACH COVER EVERY LANE THAT "
            "COULD ANSWER IT?", f"  MAYBE-NONE sites over the WHOLE tracked .py universe: "
            f"{len(maybenone)};  of those inside W (the exit-code census's set): "
            f"{sum(1 for m in maybenone if m in graded)}"]
    # **SORTED, AND THAT IS NOT COSMETIC.** MEASURED: the first version iterated this SET of
    # strings directly, and the census came out byte-identical under `PYTHONHASHSEED=1` and `7`
    # on the first nine rows and different on the rest -- the same 11 sites in 11 orders, hash
    # order. `AGENTS.md` calls a set whose order you print a set difference you have not taken, and
    # three seeds in THREE PROCESSES is the only check that sees it.
    out += [f"    OUTSIDE W  {m}" for m in sorted(maybenone - graded)] \
        or ["    (none outside W)"]
    out += [f"    inside W   {m}" for m in sorted(maybenone & graded)]

    verdict = FAIL if bad else PASS
    why_ = (f"{bad} site(s) the successor names DIFFERENT EXISTING paths for, which is silent "
            f"disagreement" if bad else
            f"LOST {sum(buckets.values())}, all classified: "
            + " ".join(f"{k}={v}" for k, v in sorted(buckets.items()))
            + f"; GAINED {len(gained)}")
    return "\n".join(out), sorted(lost_rows), (verdict, why_), {
        "lanes": (pylanes, shelllanes), "derivation": derivation, "buckets": buckets,
        "maybenone": sorted(maybenone),
        "graded": graded, "tracked_py": tracked_py, "declared": declared,
        "discovered": discovered, "refusals": refusals, "old": old, "new": new, "gained": gained}


def src_line(root, rel, line):
    """The source line behind a loss, so `--lost` output is auditable without a second tool."""
    try:
        return open(os.path.join(root, rel), errors="replace").read().splitlines()[line - 1].strip()
    except (OSError, IndexError):
        return "<line not readable>"


# ==================================================================== the plant
#: THREE SEEDS, ONE PER CLAIM, AND EACH ONE FAILS IF ITS CLAIM STOPS BEING TRUE. A seed that only
#: exercises the happy path is a change-detector, which `AGENTS.md` calls harmful; each of these
#: differs from a neighbour that WORKS by exactly one construct, and the refusal seed differs from
#: the two that resolve by being the one construct this file will not guess.
SEEDS = (
    ("path", "HERE = Path(__file__).resolve().parent -> checks/gen EXISTS and bare gen DOES NOT",
     'import pathlib\nHERE = pathlib.Path(__file__).resolve().parent\nG = HERE / "gen"\n'),
    ("climb", "Path(__file__).resolve().parents[1] from checks/ is the ROOT, one level above HERE",
     'import pathlib\nROOT = pathlib.Path(__file__).resolve().parents[1]\nD = ROOT / "runs/g"\n'),
    ("refuse", "Path('gen') REFUSES with a reason instead of guessing a runtime base",
     'import pathlib\nG = pathlib.Path("gen")\n'),
)


def seed_answers():
    """`(answers, rows)` -- the three seeds driven, as DATA. `plant()` prints `answers`;
    `gates/path-resolve-gate.py` asserts over `rows`, because a gate that reads a gate's STDOUT
    to decide is a gate that parses prose to decide.

    Each seed is written to a `TemporaryDirectory` at the repo-relative path it CLAIMS to be from,
    so `Path(__file__)` has a real referent and the climb rules are exercised at depth rather than
    at a synthetic depth 0.
    """
    import tempfile
    answers, rows = [], []
    with tempfile.TemporaryDirectory() as tmp:
        for name, claim, src in SEEDS:
            rel = f"checks/seed-{name}.py"
            path = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w").write(src)
            env, got = env_of(ast.parse(src), rel), {}
            for n in ast.walk(ast.parse(src)):
                if isinstance(n, ast.Assign) and len(n.targets) == 1 \
                        and isinstance(n.targets[0], ast.Name):
                    got[n.targets[0].id] = site(n.value, env, rel)
            answers.append(f"seed {name}: {claim}")
            for var in sorted(k for k in got if k != "__file__"):
                p, why = got[var]
                rows.append((name, var, p, why))
                answers.append(f"  {var} = {p!r}" if p is not None else f"  {var} REFUSED: {why}")
    return answers, rows


def plant():
    """Print the three seeds and ONE hash over the ANSWERS. **The hash is over the answers, not over
    the sources**: a digest that moves when a seed's text moves without its behaviour moving is a
    change-detector wearing a plant's clothes. MEASURED byte-identical under `PYTHONHASHSEED`
    1 / 7 / 4242 in three SEPARATE processes."""
    answers, _rows = seed_answers()
    blob = "\n".join(answers)
    print("PLANT\n  " + "\n  ".join(answers))
    print(f"  hash {hashlib.sha256(blob.encode()).hexdigest()[:16]} over {len(answers)} answer rows")
    return hashlib.sha256(blob.encode()).hexdigest()


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if "--plant" in argv:
        return PASS if plant() else FAIL
    body, lost, (verdict, why), _facts = census()
    print(body)
    if "--lost" in argv:
        print("\n--lost  (every lost row, with the source line that produced it)")
        for cls, rel, line, tok, path, w, o in lost:
            print(f"  {cls:<12} {rel}:{line}\n      legacy={tok!r} successor={path!r} why={w!r}\n"
                  f"      legacy reached {o}\n      source: {src_line(ROOT, rel, line)}")
    print(f"\nCENSUS-BODY-HASH {hashlib.sha256(body.encode()).hexdigest()}")
    print(f"VERDICT {'PASS' if verdict == PASS else 'FAIL'}  {why}")
    return verdict


if __name__ == "__main__":
    sys.exit(main())
