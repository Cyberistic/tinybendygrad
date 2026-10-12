"""ONE helper every reader of an UNTRACKED artefact set calls, so ABSENCE IS A VERDICT.

    .venv/bin/python checks/runs-artifacts.py           # the census, by AST
    .venv/bin/python checks/runs-artifacts.py --plant   # drive all four branches

WHAT THIS IS FOR. `runs/graphcmp/D/` is 241 files, **0 of them in git**, produced by
`checks/differ.py` (`differ.py:42`, `D = ROOT / "runs/graphcmp/D"`), and read by 12 instruments.
`checks/sweep.py:72` puts `runs` in `RESIDUE_ROOTS`, so a sweep is allowed to delete it, and
`git ls-tree -r HEAD` cannot restore a single byte of it. MEASURED 2026-10-12 16:04: the newest
artefact is `2026-10-07 23:50`, **112.2 hours old**, and `gates/retention-check.py` answers
`rc=1` with `IV FIRES runs/graphcmp/D/: the directory exists and its last run was NOT healthy:
102 complaint(s)`. Nothing acts on it. A reader that cannot tell ABSENT from STALE reports the
same number in both cases, and that number is 0 comparisons.

**FOUR STATES, FOUR TOKENS, THREE EXITS. THE ABSENT CASE IS `REFUSED`, NOT `DEAD`, AND THAT IS A
DISAGREEMENT WITH THE TASK BRIEF WHICH IS ARGUED AT `LENGTH` BELOW.**

    state                       exit  token                 what it means
    --------------------------------------------------------------------------------------
    absent                         3   ARTIFACTS-ABSENT      a precondition is missing
    present, zero files            5   ARTIFACTS-EMPTY       it ran and emitted nothing
    present, older than max_age    3   ARTIFACTS-STALE       it read something TRUE ONCE
    present, fresh                 0   ARTIFACTS-FRESH       it read something current

THE VOCABULARY IS NOT INVENTED HERE. `gates/gatekit.py:60` already spells
`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` and `checks/substrate-id.py:95` re-declares the
four it can reach, naming gatekit as the source. So `DEAD = 5` is the tree's own exit for "it ran
and emitted nothing", and an EMPTY directory is exactly that. SKIP (4) is deliberately unused:
this file always measures or refuses.

    THE ABSENT CASE IS REFUSED, NOT DEAD. THE BRIEF ASKED FOR DEAD AND THE TREE FORBIDS IT, IN
    WRITING, AT `checks/substrate-id.py:65`:

        "A gate whose DEAD is reached by the wrong cause is still a gate that cannot say why."

    and at `:70`, of a gate that had it right by accident:

        "`judge()` was `DEAD` on that tree BY ACCIDENT -- `runs/` is gitignored OUTPUT, so the
         summary was absent for a reason that has nothing to do with the population."

    An ABSENT artefact directory is a missing PRECONDITION, which is what this tree has always
    called `REFUSED` -- `checks/env-precond.py:6` and `gates/gatekit.py:60` both. Putting `DEAD`
    on it would repeat the exact defect `substrate-id.py` documents: the exit would be right and
    the REASON would be unreadable, and the reason is the only part that tells an operator whether
    to run the generator or to look for a sweep. `DEAD` is spent on PRESENT-BUT-EMPTY instead,
    which is the one case where the gate ran, reached its reader, and got nothing back.

    STALE AND ABSENT MUST NOT COLLAPSE. They share an exit (3) on purpose -- both are a missing
    precondition, a current one -- and they are separated by TOKEN and by the printed remedy,
    because the operator's next action differs: absent means "regenerate", stale means "the
    green you are reading is old". Folding them into one verdict is the `deadcache`/`stub` class
    the tree already has a name for.

    A POPULATION IS DISCOVERED, NEVER LISTED. `readers()` is a directory walk plus an AST walk
    over `checks/*.py` and `gates/*.py`, and it resolves paths through `resolve()` below. There
    is no tuple of 12 names here, and adding a thirteenth reader requires editing nothing. The
    twelve names in `.agents/slop/deadwhenabsent/REPORT.md` are that function's OUTPUT, and they
    are dated, because a hand list is a list.
"""
from __future__ import annotations

import ast
import glob
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: gatekit's vocabulary, `gates/gatekit.py:60`: PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5.
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
NAMES = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}

#: The artefact set, named ONCE, and it is a GENERATOR'S OWN PATH (`checks/differ.py:42`), not a
#: directory somebody typed into a tuple. `readers()` takes a prefix so the same walk finds every
#: other generated set without a second constant.
GRAPH_D = "runs/graphcmp/D"

#: This file. MEASURED: without it the census reported 10 readers INCLUDING `checks/runs-artifacts.py`,
#: so the count grew by one the moment the census was added to the tree it counts.
SELF = "checks/runs-artifacts.py"

#: How old the newest artefact may be before the readers may treat it as current.
#: MEASURED 2026-10-12 16:04: the live set was 112.2 h old and 12 instruments were reading it.
#: 24 h is a day, not a measurement -- it is a THRESHOLD, and it is named here so that raising it
#: is a visible edit rather than a number that drifts inside somebody else's `main()`.
MAX_AGE_S = 24 * 3600

#: A `pathlib` write site puts the path in the RECEIVER (`D.write_text`), never in an argument.
#: MEASURED: `checks/sweep.py:182` iterates `node.args` + keywords only, so it cannot see one.
WRITES = {"makedirs", "mkdir", "write_text", "write_bytes", "open", "touch",
          "mkstemp", "NamedTemporaryFile", "symlink_to", "hardlink_to"}
#: The same shape for a READ, so `readers()` is not "any use" -- which would count `gendirs.py`'s
#: PLANT, where the string is the CONTENT of a file written into a TemporaryDirectory.
READS = {"read_text", "read_bytes", "iterdir", "glob", "rglob", "is_dir", "is_file", "exists",
         "stat", "scandir", "listdir", "readlink"}


def resolve(node, env, depth=0):
    """The path a node names, following module-level bindings.

    **FIVE SEPARATE RESOLVERS IN THIS PROJECT HAVE FAILED THIS, AND EVERY ONE OF THEM REPORTED A
    CLEAN ZERO.** The list is here because the next one will not read the report:

      1 `ast.BinOp(op=ast.Div)` -- `ROOT / "runs/graphcmp/D"` is `Path.__truediv__`, and it is
        **732** occurrences across `checks/*.py` + `gates/*.py`. A resolver that handles
        `os.path.join` and not `Div` resolves nothing.
      2 the RECEIVER of a `pathlib` call -- `D.write_text(s)` names `D`, not `s`.
      3 `Path(...).parents[1]` is a `Subscript` over a `Call`, NOT a `Call` with an `.n`.
      4 a resolved root is RELATIVE and starts with `..`, so `path.split("/")[0]` is `..` and the
        first real component is invisible.
      5 `ast.Add` on strings -- `"runs/" + name` -- assembles the same path a third way.

    **AN INSTRUMENT THAT CANNOT SEE ITS POPULATION CANNOT BE WRONG, BECAUSE IT CANNOT BE
    ANYTHING -- AND A CLEAN ZERO IS THE SHAPE IT RETURNS WHILE DOING IT.**
    """
    if depth > 8:
        return None
    if isinstance(node, ast.Constant):
        return node.value if isinstance(node.value, str) else None
    if isinstance(node, ast.Name):
        return env.get(node.id)
    if isinstance(node, ast.JoinedStr):  # f"{ROOT}/runs/graphcmp/D"
        return "".join(v.value for v in node.values
                       if isinstance(v, ast.Constant) and isinstance(v.value, str)) or None
    if isinstance(node, ast.Tuple):
        # `r.startswith(("references/", "tinygrad/", "runs/graphcmp/"))` -- ONE argument, a TUPLE.
        # MEASURED: without this, `checks/txt-owners.py` is invisible, because the call has one
        # argument and it is a tuple of three strings.
        for elt in node.elts:
            if isinstance(elt, ast.Constant) and isinstance(elt.value, str) and elt.value.strip("/"):
                return elt.value
        return None
    if isinstance(node, ast.Subscript):
        # `Path(__file__).resolve().parents[1]` is a SUBSCRIPT over a Call, NOT a Call with `.n`.
        # MEASURED TWICE IN THIS UNIT: getting this wrong leaves `ROOT` unresolvable, which makes
        # every resolved path `../<top>`, which filters to ZERO -- a clean number, from a broken
        # instrument, which is the worst way to be wrong.
        n = node.slice.value if isinstance(node.slice, ast.Constant) else None
        if isinstance(n, int):
            base = resolve(node.value, env, depth + 1)
            if base is None and isinstance(node.value, ast.Call) \
                    and isinstance(node.value.func, ast.Attribute) and node.value.func.attr == "parents":
                base = resolve(node.value.func.value, env, depth + 1)
            if base == "":
                return "/".join([".."] * n)
        return None
    if isinstance(node, ast.BinOp):
        if not isinstance(node.op, (ast.Add, ast.Div)):
            return None
        a, b = resolve(node.left, env, depth + 1), resolve(node.right, env, depth + 1)
        if isinstance(a, str) and isinstance(b, str):
            return os.path.join(a, b) if isinstance(node.op, ast.Div) else a + b
        return None
    if isinstance(node, ast.Attribute):
        return resolve(node.value, env, depth + 1)
    if isinstance(node, ast.Call):
        fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if fn == "Path":
            return ""
        if fn in ("join", "as_posix", "parent", "parents"):
            parts = [resolve(a, env, depth + 1) for a in node.args]
            if fn == "parent":
                return os.path.join(*parts) + "/.." if any(parts) else None
            if fn == "parents":
                # `parents` is reached only as `parents[n]`, which the Subscript branch above
                # handles; reaching it bare means an unsubscripted `parents`, which names nothing.
                return None
            if any(p is not None for p in parts):
                return os.path.join(*(p if p is not None else "?" for p in parts))
        if fn in ("resolve", "absolute", "realpath", "expanduser"):
            return resolve(node.func.value, env, depth + 1) if isinstance(node.func, ast.Attribute) else None
    return None


def _env(tree):
    """String bindings, to a fixed point -- `ROOT` binds before `D` uses it.

    **EVERY SCOPE, NOT ONLY THE MODULE BODY.** MEASURED: resolving only `tree.body` found **3 of
    the 12** readers, because `checks/corpus-figure.py:194` and `checks/disagree-gate.py:53` bind
    their artefact path inside a function. A binding census that reads only the top of a file is
    the `.agents/slop/xd1/pin` failure one level down -- it cannot see the row it is counting.

    THE COST IS STATED: a name bound twice in different functions resolves to whichever binding
    the fixed point reached last, so a reader that REBINDS `D` to something else may be reported
    against the wrong path. That is a false POSITIVE in the safe direction -- the census overstates
    the number of readers, and every number below is therefore an upper bound on the reader set,
    which is the direction that cannot hide a hazard.
    """
    env: dict[str, str] = {}
    for _ in range(4):
        for st in ast.walk(tree):
            if isinstance(st, ast.Assign) and len(st.targets) == 1 and isinstance(st.targets[0], ast.Name):
                if (v := resolve(st.value, env)) is not None:
                    env[st.targets[0].id] = v
    return env


def _under(value, prefix):
    """Is `value` a path at or below `prefix`? **A TRAILING SLASH IS A SUFFIX, NOT A PATH**, and
    `runs/graphcmp` is not `runs/graphcmp/D` -- so this compares components, never prefixes."""
    if not isinstance(value, str):
        return False
    parts = [p for p in value.replace("\\", "/").split("/") if p not in ("", ".", "..")]
    want = [p for p in prefix.replace("\\", "/").split("/") if p not in ("", ".", "..")]
    return parts[:len(want)] == want


def sites(root=ROOT):
    """Every call site in `checks/` or `gates/` that NAMES a filesystem path, as
    `(relpath, role, value)` with `role` in `read`, `write`.

    THE POPULATION IS A DIRECTORY WALK (`glob` over `checks/*.py` and `gates/*.py`) PLUS A
    RESOLVER OVER THE TREE'S OWN READ AND WRITE SITES. It is not a basename, not a suffix set, not
    a hand list, and not a cache.
    """
    out = []
    for path in sorted(glob.glob(os.path.join(root, "checks", "*.py"))
                       + glob.glob(os.path.join(root, "gates", "*.py"))):
        try:
            tree = ast.parse(open(path, errors="replace").read())
        except (OSError, SyntaxError):
            continue
        env = _env(tree)
        # A DOCSTRING IS NOT A USE. MEASURED: including docstrings reported 14 readers on a tree
        # that has 12, because `checks/sweep.py`'s only two mentions of the directory are a
        # function docstring and a `#` comment. **A POPULATION THAT INCLUDES ITS OWN NARRATION
        # CANNOT COUNT READERS**, and the extra two are not harmless -- they are the tree's own
        # words about a directory it never opens.
        docs = set()
        for n in ast.walk(tree):
            if not isinstance(n, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            b = getattr(n, "body", None)
            if b and isinstance(b[0], ast.Expr) and isinstance(b[0].value, ast.Constant) \
                    and isinstance(b[0].value.value, str):
                docs.add(id(b[0].value))
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            # WRITE IF IT IS A WRITE, OTHERWISE IT IS A USE. MEASURED: narrowing this to a
            # hand-listed set of read method names found **4 of the 12**, because the rest hand
            # the path to a FUNCTION -- `substrate-id.py` passes `SUMMARY` to `declared_values`,
            # `disagree-gate.py` to its locator resolver -- and a name I failed to list reads as
            # "not a reader", which is the `.agents/slop/xd1/pin` blindness again. **AN UNRECOGNISED
            # CALLEE IS A USE, NOT AN ABSENCE.**
            role = "write" if fn in WRITES else "read"
            # THE RECEIVER IS A SITE. `D.write_text(s)` and `D.iterdir()` both name `D` there.
            args = list(node.args) + [k.value for k in node.keywords]
            if isinstance(node.func, ast.Attribute):
                args.append(node.func.value)
            for arg in args:
                # EVERY TUPLE ELEMENT IS ITS OWN SITE. MEASURED: `resolve()` returned the first
                # element of `r.startswith(("references/", "tinygrad/", "runs/graphcmp/"))`, which
                # is `"references/"`, so `checks/txt-owners.py` was reported as reading something
                # else. One reader hidden by an argument shape is one reader too few.
                for leaf in (arg.elts if isinstance(arg, ast.Tuple) else (arg,)):
                    if isinstance(leaf, ast.Constant) and id(leaf) in docs:
                        continue
                    v = resolve(leaf, env)
                    if isinstance(v, str) and v.strip("/"):
                        out.append((os.path.relpath(path, root), role, v))
    return out


def _tracked_tops(root=ROOT):
    """EVERY directory prefix of every file `git ls-tree -r HEAD` names, at EVERY depth.

    **MY OWN MEASUREMENT WAS WRONG HERE AND THE BEFORE-VALUE WAS A CLEAN, CONFIDENT WRONG ANSWER.**
    The first version recorded a top-level directory as tracked only if a tracked file sat AT its
    root, which is true of `checks/` and false of `.agents/` -- so it printed `tracked=0` for a
    directory holding **4,496** tracked files, and `.agents/` came out of `unrecoverable_dirs()` as
    a deletion target. `runs/` is genuinely absent from the tree, and one level of prefix was
    enough to tell those apart by accident. A depth-1 lookup is a basename shape.

    **NOT `git ls-files`**: MEASURED 2026-10-06, `jj git colocation` stages an empty blob for every
    untracked file, so the index carries 906 `--intent-to-add` placeholders and reading it answers a
    question about the editor, not about the repository.
    """
    pref: set[str] = set()
    for line in tracked_files(root):
        parts = line.split("/")
        for i in range(1, len(parts) + 1):
            pref.add("/".join(parts[:i]))
    return pref


def unrecoverable_dirs(root=ROOT):
    """Every directory an instrument WRITES into that git cannot restore a single byte of.

    **THIS IS THE ANSWER TO `checks/sweep.py:72`, AND IT IS A DERIVATION, NOT A REVERSAL.**
    `RESIDUE_ROOTS = (".agents/slop", "runs")` is a hand list of two names, and it is the same
    defect `AGENTS.md` records for `LIVE_UNITS` -- a tuple of 14 literal directory names that held
    53% of `.slop`. The question a sweep must answer is not "which directories are outputs" but
    **"where is a deletion IRREVERSIBLE"**, and that has an exact instrument: `git ls-tree -r HEAD`.

    MEASURED 2026-10-12 16:04, and the two names split cleanly:

        directory                 tracked files   written into by
        runs/                             0   checks/differ.py   (`differ.py:42`, the generator)
        runs/graphcmp/                    0   checks/differ.py
        .agents/slop/                 4,491   -- RESTORABLE, so it is not in this set
        gates/artifacts/                 0   gates/*.py via gatekit
        checks/                         172   --
        oracles/                        357   --

    So the derivation finds `runs/` **because it is untracked and written into**, and it does not
    need to be told. It also finds `gates/artifacts/`, which `RESIDUE_ROOTS` correctly omits
    because `AGENTS.md` records `rm -rf gates/artifacts` as a live command -- so a bare
    "untracked and written into" is NOT the whole rule, and the difference is stated below rather
    than hidden in the set.
    """
    tracked = _tracked_tops(root)
    found: dict[str, set[str]] = {}
    for rel, role, value in sites(root):
        if role != "write":
            continue
        parts = [p for p in value.replace("\\", "/").split("/") if p not in ("", ".", "..")]
        for i in (1, 2):
            if len(parts) < i:
                continue
            cand = "/".join(parts[:i])
            if cand in tracked or not os.path.isdir(os.path.join(root, cand)):
                continue
            found.setdefault(cand, set()).add(rel)
    return found


def census(prefix=GRAPH_D, root=ROOT):
    """The readers, the writers, and the DENOMINATOR, in one object, because a citation without
    its denominator is a lower bound.

    MEASURED 2026-10-12 16:04: **10 of 188** instruments in `checks/` + `gates/` read
    `runs/graphcmp` in a code position. The task brief said "13 of 1030 scanned .py", and BOTH
    numbers were wrong. The numerator included `checks/sweep.py`, whose only two mentions are a
    function docstring and a `#` comment, and omitted `checks/diary-census.py`, which resolves it
    in four code positions. The denominator counted `.agents/slop/**/*.py` while the numerator
    counted live gates, so the ratio compared two scopes: **188** instruments, **1000** `.py` in
    the whole tree, and the 812 in between is the scope slip exactly.

    **THIS FILE EXCLUDES ITSELF.** A census that counts its own reader set grows by one every time
    it is added to the tree, and it would have reported 10 including `checks/runs-artifacts.py` --
    MEASURED, it did, before `SELF` was added. `checks/sweep.py:112-115` records the same shape for
    `SELF = ".agents/slop/slopfinal"`.
    """
    rows = [s for s in sites(root) if _under(s[2], prefix)]
    total = len(glob.glob(os.path.join(root, "checks", "*.py"))) + len(glob.glob(os.path.join(root, "gates", "*.py")))
    names = lambda role: sorted({r for r, k, _ in rows if k == role and r != SELF})
    return {"total": total, "readers": names("read"), "writers": names("write")}


def census_unrecoverable(root=ROOT):
    """The same census over EVERY unrecoverable directory, so `runs/` is not special-cased."""
    total = len(glob.glob(os.path.join(root, "checks", "*.py"))) + len(glob.glob(os.path.join(root, "gates", "*.py")))
    by_dir = {}
    for d in sorted(unrecoverable_dirs(root)):
        rows = [s for s in sites(root) if _under(s[2], d)]
        names = lambda role: sorted({r for r, k, _ in rows if k == role and r != SELF})
        by_dir[d] = {"writers": names("write"), "readers": names("read")}
    return total, by_dir


def tracked_files(root=ROOT):
    """`git ls-tree -r HEAD` -- THE TREE. **NOT `git ls-files`, WHICH READS THE INDEX**: MEASURED
    2026-10-06, `jj git colocation` stages an empty blob for every untracked file, so the index
    carries 906 `--intent-to-add` placeholders and reading it answers a question about the editor,
    not about the repository."""
    r = subprocess.run(["git", "-C", root, "ls-tree", "-r", "--name-only", "HEAD"],
                       capture_output=True, text=True)
    return r.stdout.splitlines()


def state(prefix=GRAPH_D, *, root=ROOT, max_age_s=MAX_AGE_S, now=None):
    """The four states, as `(exit, token, detail)`. Pure measurement: it reads the filesystem and
    the clock and decides NOTHING about whether the caller went on to find a disagreement."""
    d = os.path.join(root, prefix)
    now = time.time() if now is None else now
    if not os.path.isdir(d):
        return REFUSED, "ARTIFACTS-ABSENT", f"{prefix}: no such directory"
    files = [os.path.join(r, f) for r, _, fs in os.walk(d) for f in fs]
    if not files:
        return DEAD, "ARTIFACTS-EMPTY", f"{prefix}: the directory is there and holds 0 files"
    newest = max(os.path.getmtime(f) for f in files)
    age = now - newest
    if max_age_s is not None and age > max_age_s:
        return (REFUSED, "ARTIFACTS-STALE",
                f"{prefix}: newest artefact is {age / 3600:.1f} h old, over the "
                f"{max_age_s / 3600:.1f} h limit, and it is read as current")
    return PASS, "ARTIFACTS-FRESH", f"{prefix}: {len(files)} files, newest {age / 3600:.1f} h old"


def require(prefix=GRAPH_D, *, root=ROOT, max_age_s=MAX_AGE_S, label="", remedy=""):
    """`state()` plus the TOKEN on stdout and the remedy on stderr, and the exit to return.

    THIS IS THE ONE CALL. A reader that adds `require(...)` before its first read gets ABSENT,
    EMPTY and STALE as three different answers for the price of one line, and a caller that only
    reads `$?` gets 3, 5 or 0 -- never a 0 that measured nothing.
    """
    code, token, detail = state(prefix, root=root, max_age_s=max_age_s)
    who = f"{label}: " if label else ""
    print(f"{who}{token}  {detail}")
    if code is not PASS:
        print(f"{who}this is not a pass: the reader would measure nothing over an empty population",
              file=sys.stderr)
        if remedy:
            print(f"{who}remedy: {remedy}", file=sys.stderr)
    return code


REGENERATE = f".venv/bin/python checks/differ.py run   # writes {GRAPH_D}/ (0 of its files are in git)"


def plant(root=None):
    """DRIVE ALL FOUR BRANCHES ON REAL DIRECTORIES. Nothing here asserts a branch; it builds the
    state and reads back the exit, which is the only way to learn that `ARTIFACTS-EMPTY` and
    `ARTIFACTS-STALE` are distinguishable at all.

    The plant uses a `TemporaryDirectory`, so `runs/graphcmp` is never touched: **the one rule
    about this directory is that nothing may delete it, and the way to honour that is not to
    write a test that does.**
    """
    import tempfile
    bad = []
    now = 1000.0
    with tempfile.TemporaryDirectory() as td:
        fresh = os.path.join(td, "fresh")
        os.makedirs(os.path.join(fresh, GRAPH_D))
        p = os.path.join(fresh, GRAPH_D, "D0-run-summary.rows")
        open(p, "w").write("graphs=34\n")
        os.utime(p, (now, now))

        absent = os.path.join(td, "absent")           # nothing created at all
        empty = os.path.join(td, "empty")             # the directory, 0 files
        os.makedirs(os.path.join(empty, GRAPH_D))
        stale = os.path.join(td, "stale")             # one file, older than the limit
        os.makedirs(os.path.join(stale, GRAPH_D))
        q = os.path.join(stale, GRAPH_D, "D0-run-summary.rows")
        open(q, "w").write("graphs=25\n")
        os.utime(q, (now - 10 * 86400, now - 10 * 86400))

        for name, sub, want, tok in (("absent", absent, REFUSED, "ARTIFACTS-ABSENT"),
                                     ("empty", empty, DEAD, "ARTIFACTS-EMPTY"),
                                     ("stale", stale, REFUSED, "ARTIFACTS-STALE"),
                                     ("fresh", fresh, PASS, "ARTIFACTS-FRESH")):
            code, token, detail = state(GRAPH_D, root=sub, max_age_s=MAX_AGE_S, now=now)
            ok = code is want and token == tok
            bad += [] if ok else [f"{name}: got {token}/{code}, wanted {tok}/{want}"]
            print(f"  {name:<7} {token:<17} exit={code}  {'OK' if ok else 'FAILED'}  {detail}")

        # THE CONTROL THE BRIEF ASKS FOR: STALE MUST NOT READ AS ABSENT, AND NEITHER AS EMPTY.
        toks = {state(GRAPH_D, root=s, max_age_s=MAX_AGE_S, now=now)[1]
                for s in (absent, empty, stale, fresh)}
        if len(toks) != 4:
            bad.append(f"four states collapsed into {len(toks)}: {sorted(toks)}")
        print(f"  distinct tokens across the four states: {len(toks)}  "
              f"{'OK' if len(toks) == 4 else 'FAILED -- THEY COLLAPSE'}")
    print(f"--plant: {'all four states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


def main():
    if "--plant" in sys.argv:
        return plant()
    if "--all" in sys.argv:
        total, by_dir = census_unrecoverable()
        print(f"instruments scanned: {total}   (checks/*.py + gates/*.py, a directory walk)")
        print("\nEVERY DIRECTORY AN INSTRUMENT WRITES INTO THAT GIT CANNOT RESTORE -- derived, "
              "not listed:")
        for d, v in by_dir.items():
            print(f"  {d}/  tracked=0  writers={len(v['writers'])} readers={len(v['readers'])}")
            for r in v["writers"]:
                print(f"      writes  {r}")
            for r in v["readers"]:
                print(f"      reads   {r}")
        return 0
    c = census()
    on_disk = sum(len(f) for _, _, f in os.walk(os.path.join(ROOT, GRAPH_D)))
    n_tracked = len([t for t in tracked_files() if t.startswith("runs/")])
    print(f"artefact set        : {GRAPH_D}   (named by checks/differ.py:42, the generator)")
    print(f"tracked in git      : {n_tracked} of {on_disk} on disk   -- git ls-tree -r HEAD, not the index")
    print(f"instruments scanned : {c['total']}   (checks/*.py + gates/*.py, a directory walk)")
    print(f"WRITERS             : {len(c['writers'])}  {c['writers']}")
    print(f"READERS             : {len(c['readers'])}  {c['readers']}")
    code, token, detail = state()
    print(f"live state          : {token}  exit={code}  {detail}")
    print(f"remedy              : {REGENERATE}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
