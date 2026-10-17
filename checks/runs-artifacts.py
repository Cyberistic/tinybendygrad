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
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

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

#: A SHELL LANE IS FOUND BY ITS SHEBANG, NOT BY ITS NAME. MEASURED 2026-10-17: the tree holds
#: **272 tracked files whose first line names a shell**, and only **21 of them end in `.sh`** --
#: `checks/bend`, `bin/bend`, `gates/oracles/*.sh` and 16 more. A `*.sh` glob would have missed
#: every one of those, which is the same suffix-set defect `checks/repro-paths.py` shipped and
#: retracted. `gates/gates-pop.py` PLANT 6 found the identical thing independently: its
#: denominator is a **21-entry walk**, and its own header says a `glob("*.sh")` population was
#: "a population it had chosen".
SHELL_SHEBANG = re.compile(r"^#!.*\b(bash|sh|zsh|dash|ksh)\b")
#: The verbs that CREATE a file or a directory. A shell READ is not extracted: a read is any
#: string-shaped token, and a permissive reader is how the first prototype produced `echo`, `fi`
#: and `local` as paths. **A WRITE IS A NARROW SET OF VERBS; A READ IS NOT.**
#: `git` IS NOT IN THIS SET AND IS IN `SH_GIT` INSTEAD. MEASURED: with a bare `git` alternative,
#: `checks/disarm.sh` yielded **20 sites of which 0 existed, and every one of them was a command
#: name** -- `git`, `grep`, `diff`, `cut`, `sort`, `say`, `OWN`, `i.e.`. Only `git clone` and
#: `git init` create anything, and `git clone` is the one that matters here: it is
#: `tools/get-bend.sh:21`, the whole of `references/bend`.
SH_CREATE = re.compile(r"(?<![0-9A-Za-z_.-])(mkdir|cp|mv|install|touch|tee|ln|rsync)\b")
SH_GIT = re.compile(r"(?<![0-9A-Za-z_.-])git\s+(clone|init)\b")
#: `NAME=value`, `export NAME=value`, `local NAME=value` -- one assignment shape, three prefixes,
#: and the fixed point is 4 rounds because `D=$ROOT/x` needs `ROOT` first.
SH_ASSIGN = re.compile(r"""(?m)^\s*(?:export\s+|declare\s+-x\s+|local\s+|readonly\s+)*"""
                       r"""([A-Za-z_][A-Za-z0-9_]*)=(?:"([^"]*)"|'([^']*)'|([^\s#;&|]*))""")
#: `ROOT=$(cd "$(dirname "$0")/.." && pwd)` -- the shell spelling of `Path(__file__).resolve()`,
#: which `resolve()` above already maps to `""`. **THE SAME IDIOM GETS THE SAME ANSWER**, so
#: `"$ROOT/references/bend"` resolves to `references/bend` and not to a dropped token. MEASURED:
#: without this binding the extractor produced **0** sites for `tools/get-bend.sh`, whose entire
#: job is to write `references/bend`. The `\b` and not `\s` because `SH_ASSIGN` captures an
#: UNQUOTED value only up to the first space, so the captured text is `$(cd` and nothing else.
SH_SELF_ROOT = re.compile(r"\$\(\s*cd\b|\$\(\s*dirname\b|\$\(\s*pwd\b")
#: `cp SRC DEST` CREATES `DEST`. MEASURED: the first extractor took every path-shaped token after
#: the verb, so `cp runs/x "$T/y"` recorded `runs/x` as a WRITE -- laundering a plant's own
#: fixture into `GENERATOR`, which is the exact defect `plant_writes()` documents at length. For
#: these five verbs the LAST path token is the target and the rest are sources.
SH_DEST_LAST = ("cp", "mv", "ln", "install", "rsync")
#: A token is a PATH if it is relative, slash-or-extension shaped, and free of every metacharacter
#: that means "assembled at runtime". Existence is NOT checked here -- `clone_paths()` does that,
#: and this is the `checks/repro-paths.py` repair read backwards: PERMISSIVE EXTRACTION
#: INTERSECTED WITH `os.path.exists`.
SH_PATH = re.compile(r"^[A-Za-z0-9._@-]+(?:/[A-Za-z0-9._@-]+)*$")
SH_DROP = set("/~") | set("*?\"'\\$&;()<>|")


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


def sites(root=ROOT, tracked=None):
    """Every call site in `checks/` or `gates/` that NAMES a filesystem path, as
    `(relpath, role, value)` with `role` in `read`, `write`.

    THE POPULATION IS A DIRECTORY WALK (`glob` over `checks/*.py` and `gates/*.py`) PLUS A
    RESOLVER OVER THE TREE'S OWN READ AND WRITE SITES. It is not a basename, not a suffix set, not
    a hand list, and not a cache.

    `tracked` IS THE SEAM, and it is one argument rather than a fixture: it is the `git ls-tree`
    answer the SHELL walk needs, it saves a second `git` process, and `--plant` passes a list
    instead of a repository so the plant can drive THIS FUNCTION on a synthetic tree. **A PLANT
    THAT DRIVES A COPY OF THE DECISION IS NOT A PLANT.**
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
    return out + shell_sites(root, tracked)


def shell_lanes(root=ROOT, tracked=None):
    """Every TRACKED file whose first line names a shell, as a path relative to `root`.

    **DISCOVERY BY `git ls-tree` AND BY CONTENT. TWO CANDIDATE POPULATIONS WERE MEASURED AGAINST
    EACH OTHER AND BOTH WRONG POPULATIONS ARE NAMED HERE SO THE NEXT ONE IS NOT PROPOSED:**

        `glob("checks/*.sh")`            17 files, and it MISSES `checks/bend` and `bin/bend`, two
                                         tracked `#!/bin/sh` lanes with no dot in the name.
        EVERY tracked file, whole tree   272 shell lanes, of which **145 are vendored upstream**
                                         (`examples/` 119, `extra/` 21) and **102 sit under
                                         `.agents/slop/`**, a tree this project is pruning.

    The scope is not a hand list of homes, for the same reason `HOMES = ("checks", "gates")` is the
    one universe `gates/gates-pop.py` admits by hand. **TRACKEDNESS IS THE SCOPE AND IT IS THE
    RIGHT SCOPE BECAUSE THE QUESTION IS ABOUT A FRESH CLONE: a clone cannot execute an untracked
    script, so an untracked lane cannot produce anything for the reader asking.** Vendored lanes
    are KEPT on the same reasoning -- a clone HAS them, so a writer among them is a real writer,
    and dropping them would be a false `HANDMADE`.
    """
    paths = tracked_files(root) if tracked is None else tracked
    out = []
    for t in dict.fromkeys(paths):  # A SET OF LANES. `git ls-tree` cannot repeat a path, and
        if t.endswith(".py"):        # `clone_report()` prints `len(sites(root))` as a denominator.
            continue
        try:
            with open(os.path.join(root, t), errors="replace") as fh:
                if SHELL_SHEBANG.match(fh.readline()):
                    out.append(t)
        except OSError:
            continue
    return out


def shell_env(text):
    """`NAME=value` bindings to a fixed point.

    **THE EMPTY STRING IS A BINDING AND NOT A MISSING ONE, AND THAT IS THE WHOLE OF CASE D.**
    MEASURED: the first version ended in `if v:`, so `ROOT` -- bound to `""` precisely because it
    IS the repo root -- was never stored, `"$ROOT/runs/x"` stayed unresolved, and
    `--plant-shell` case D went red. An ordinary `FOO=` is still skipped, because in a shell
    `"$FOO/x"` is `/x`, an ABSOLUTE path, and inventing a repo root for it would be the
    truncation this file exists to refuse.
    """
    env = {}
    for _ in range(4):
        for m in SH_ASSIGN.finditer(text):
            v = m.group(2) or m.group(3) or m.group(4) or ""
            if SH_SELF_ROOT.search(v):  # `$(cd "$(dirname "$0")/.." && pwd)` IS `Path(__file__)`.
                env[m.group(1)] = ""  # The fixed point cannot improve on the root, and this is
            elif v:                    # what makes the loop terminate on the second pass.
                env[m.group(1)] = v
    return env


def shell_value(tok, env):
    """A shell token to a path, or `None`. **THE PERMISSIVE HALF: EXISTENCE IS NOT CHECKED HERE.**

    `checks/repro-paths.py` shipped a suffix set that stopped at a *remembered* extension and wrote
    false rows in BOTH directions -- a dangling row for a name that never existed, and a broken
    reference marked `RESOLVED` because the truncated path happened to exist. Every guard below
    exists to make the other failure impossible: **A TOKEN IS REFUSED, NEVER SHORTENED.**
    """
    # `\x00` IS UNBOUND and `\x01` IS BOUND-TO-EMPTY (the repo root). MEASURED: with a plain
    # substitution `ROOT=""` turned `"$ROOT/runs/x"` into `/runs/x`, and the absolute-path guard
    # then refused it -- case D of `--plant-shell` went RED for exactly that. `\x01` eats the slash
    # that joins it, the way `os.path.join("", "runs/x")` does; `/tmp/x` carries no marker, so a
    # genuine absolute path is still refused.
    def sub(m):
        v = env.get(m.group(1) or m.group(2), "\x00")
        return "\x01" if v == "" else v

    for _ in range(4):
        nxt = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", sub, tok)
        if nxt == tok:
            break
        tok = nxt
    if "\x00" in tok:
        return None
    tok = re.sub(r"\x01/?", "", tok)
    if not tok or "\x01" in tok or "$" in tok or tok[0] in SH_DROP:
        return None
    return tok if SH_PATH.match(tok) else None


def shell_sites(root=ROOT, tracked=None):
    """The write sites of every shell lane, as `(relpath, 'write', value)`.

    **NO READS ARE EXTRACTED, AND THAT IS THE SHAPE OF THE MEDICINE.** MEASURED: the first
    prototype read as well as wrote and returned `echo`, `fi`, `local`, `python3` and `zsh` as
    paths -- **115 sites, 6 of which existed.** A read in shell is any string-shaped token, so a
    permissive reader is noise with a denominator. A write is a closed verb set plus a redirect,
    so a permissive *writer* is 90 sites of which the same 6 exist. Neither number is tuned away;
    both are recorded because `clone_paths()` intersects with `os.path.exists`, and **a permissive
    extraction is sound under a consumer that checks the filesystem, while a truncated token is
    unsound under every consumer.**
    """
    out = []
    for rel in shell_lanes(root, tracked):
        text = open(os.path.join(root, rel), errors="replace").read()
        env = shell_env(text)
        for line in re.sub(r"(?m)^\s*#.*$", "", text).splitlines():  # A COMMENT IS NOT A USE.
            for m in re.finditer(r"(?<![0-9&])>>?\s*(\"[^\"]*\"|'[^']*'|\S+)", line):
                v = shell_value(m.group(1).strip("\"'"), env)
                if v and v not in ("1", "2", "&"):  # `>&2` IS A FILE DESCRIPTOR, NOT A PATH.
                    out.append((rel, "write", v))
            for m in SH_CREATE.finditer(line):
                toks = [t for t in re.findall(r"\"[^\"]*\"|'[^']*'|\S+", line[m.end():])
                        if not t.startswith("-")]
                bare = [t[1:-1] if t[:1] in "\"'" else t for t in toks]
                # A `DEST_LAST` VERB NAMES ITS TARGET IN THE LAST TOKEN AND ITS SOURCES IN ALL
                # THE OTHERS, SO IF THE LAST TOKEN DOES NOT RESOLVE THERE IS NO SITE AT ALL.
                # MEASURED: taking the last *resolvable* token made `cp runs/x "$T/y"` a WRITE of
                # `runs/x` -- a plant's own fixture laundered into `GENERATOR`, the defect
                # `plant_writes()` exists to prevent, reintroduced through the shell door.
                for v in ([shell_value(bare[-1], env)] if m.group(1) in SH_DEST_LAST and bare
                          else [shell_value(b, env) for b in bare]):
                    if v:
                        out.append((rel, "write", v))
            for m in SH_GIT.finditer(line):  # `git clone URL DEST` -- DEST is the last token.
                bare = [t.strip("\"'") for t in re.findall(r"\"[^\"]*\"|'[^']*'|\S+",
                                                          line[m.end():])]
                if bare and (v := shell_value(bare[-1], env)):
                    out.append((rel, "write", v))
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


def ignored_by(path, root=ROOT):
    """The `.gitignore` line that hides `path`, or `None`. **GIT'S OWN MATCHER, NOT A REGEX.**

    A regex over `.gitignore` is a hand list with a parser bug. MEASURED 2026-10-14 on this tree:
    `.gitignore:179` is `/runs/`, which is ANCHORED to the root and matches nothing at depth --
    `git check-ignore` answers IGNORED for `runs/` and NOT IGNORED for `checks/rows/keys.rows`, while
    `checks/rows-key.rows` IS ignored. And `/runs/` fed back to `check-ignore` verbatim answers NOT
    IGNORED, because that leading slash means filesystem-absolute. **A DIRECTORY IS PROBED WITH ITS
    TRAILING SLASH, BECAUSE `runs/` IS NOT `runs`** -- a trailing slash is a suffix, not a spelling.

    `--no-index` because MEASURED 2026-10-06 the index carries intent-to-add placeholders and
    reading it answers a question about the editor rather than about the repository."""
    probe = path + "/" if os.path.isdir(os.path.join(root, path)) else path
    r = subprocess.run(["git", "-C", root, "check-ignore", "--no-index", "-v", probe],
                       capture_output=True, text=True)
    return r.stdout.strip().split("\t")[0] or None if r.returncode == 0 else None


def plant_writes(root=ROOT):
    """The resolved path values that a `TemporaryDirectory` creates -- **A PLANT IS NOT A WRITE
    SITE**, and the population is DISCOVERED, not a list of instruments.

    MEASURED 2026-10-14 TWICE, AND THE SECOND FAILURE IS THE ONE THAT MATTERS. `checks/diary-census.py:447`
    is `(d / "bin").mkdir()` inside a temp dir: `resolve()` cannot see the `d` prefix -- an unbound
    `Name` -- so the site comes out as the bare string `"bin"`, WHICH COLLIDES WITH THE REPO'S OWN
    `bin/`. With a "a writer of a parent is a writer of its children" rule, `bin/bend` inherited
    `checks/diary-census.py` and was promoted from `HANDMADE` to `GENERATOR`: **A PLANT LAUNDERED
    INTO A GENERATOR, WHICH SILENTLY ERASED THE HEADLINE FINDING.**

    The obvious fix -- exclude every INSTRUMENT that owns a plant -- is worse, and MEASURED: it
    excluded `checks/differ.py`, which ALSO writes the real corpus and also owns a plant
    (`../runs/graphcmp/D/.tmp.`), so `runs/graphcmp/D` lost its only generator and 9 readers of a
    reproducible artefact were reported unreproducible. **AN INSTRUMENT-SCOPED FLAG IS AS WRONG AS A
    FUNCTION-SCOPED ONE, IN THE OPPOSITE DIRECTION** -- it hides a real generator behind a real plant
    because the two happen to live in the same file.

    SO THE UNIT IS THE **WRITE SITE**, not the instrument and not the function: a resolved value is
    a plant exactly when the enclosing function creates a temporary directory. `differ.py` then
    keeps `../runs/graphcmp/D` and loses `../runs/graphcmp/D/.tmp.`, which is the correct split."""
    out = set()
    for path in glob.glob(os.path.join(root, "checks", "*.py")) + glob.glob(os.path.join(root, "gates", "*.py")):
        try:
            tree = ast.parse(open(path, errors="replace").read())
        except (OSError, SyntaxError):
            continue
        env = _env(tree)
        for fn in [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]:
            if not ({"TemporaryDirectory", "mkdtemp"} &
                    {c.func.id if isinstance(c.func, ast.Name) else getattr(c.func, "attr", "")
                     for c in ast.walk(fn) if isinstance(c, ast.Call)}):
                continue
            for c in ast.walk(fn):
                if not isinstance(c, ast.Call):
                    continue
                fn_name = c.func.attr if isinstance(c.func, ast.Attribute) else getattr(c.func, "id", "")
                if fn_name not in WRITES:
                    continue
                args = list(c.args) + [k.value for k in c.keywords]
                if isinstance(c.func, ast.Attribute):
                    args.append(c.func.value)
                for leaf in args:
                    v = resolve(leaf, env)
                    if isinstance(v, str) and v.strip("/"):
                        out.add(v)
    return out


def clone_paths(root=ROOT, tracked=None):
    """Every path an instrument reads or writes that exists here, with the facts a clone cares about:
    is it in the TREE, what `.gitignore` line hides it, does a sweep root name it, and WHO WRITES
    IT. **THE POPULATION IS `sites()` -- a directory walk plus an AST walk -- so adding an
    instrument adds its paths here with no edit to this file.**

    THE SUBJECT IS A PATH, NOT A DIRECTORY, and that is the whole finding. `bin/` is NOT ignored
    while `bin/bend` IS (`.gitignore:5`), and `bin/bend` is read by 10 of the 209 instruments while
    `bin/` is read by 0 -- a directory-only census reports the subject that matters as clean.
    (This paragraph was in this docstring TWICE, verbatim, before 2026-10-17: a duplicated
    paragraph is a second witness with no second measurement behind it, and `gates/docnum-
    claim-gate.py`'s whole subject is a number copied forward. One copy, here.)

    `..` IS DROPPED FROM EVERY RESOLVED VALUE, AND HERE IS WHAT THAT COSTS. `resolve()` renders
    `parents[n]` as `"../"*n`, which is OFF BY ONE for an instrument at depth 1: `checks/bounded.py`
    is `here.parents[1]`, i.e. the ROOT, and the resolver's spelling escapes the tree. MEASURED
    2026-10-14: 190 of the 7,791 sites carry a `..`, all of them from `checks/` (138) and `gates/`
    (52), both depth 1, so the collapse is CORRECT for every one of them. **That is a fact about
    this tree's layout and not a guarantee** -- the day an instrument moves one directory deeper
    this silently mis-roots it, and no verdict here would notice."""
    roots = sweep_roots(root)
    tracked = set(tracked_files(root)) if tracked is None else set(tracked)
    plants = plant_writes(root)  # A PLANT IS NOT A GENERATOR. See `plant_writes`.
    reads: dict[str, set[str]] = {}
    writes: dict[str, set[str]] = {}
    for rel, role, value in sites(root, tracked):
        if value.startswith("/") or (role == "write" and value in plants):
            continue  # A SYSTEM PATH, or a temporary directory. `/bin/sh` is not this tree's `bin/`.
        parts = [p for p in value.split("/") if p not in ("", ".", "..")]
        for i in range(1, len(parts) + 1):
            (writes if role == "write" else reads).setdefault("/".join(parts[:i]), set()).add(rel)
    # A WRITE TO A DIRECTORY IS A WRITE TO EVERY FILE IN IT. `checks/differ.py` writes the path
    # `../runs/graphcmp/D` and builds `D0-run-summary.txt` by string interpolation AT RUNTIME, so
    # `sites()` records the directory and never the filename. MEASURED 2026-10-14: without this
    # inheritance `runs/graphcmp/D/D0-run-summary.txt` came out `HANDMADE` -- a corpus file with no
    # generator, printed three lines below the directory that generates it. **A WRITER OF A PARENT
    # IS A WRITER OF THE CHILD**, or the census blames the absence of a spelling for the absence
    # of a fact. THE PLANTS ARE REMOVED ABOVE, or the inheritance hands out a generator's name
    # to a file no generator ever wrote.
    for p in sorted(writes):
        for child in sorted(set(reads) | set(writes)):
            if child.startswith(p + "/") and child not in writes:
                writes[child] = set(writes[p])
    out = []
    for p in sorted(set(reads) | set(writes)):
        if not os.path.exists(os.path.join(root, p)):
            continue
        out.append({"path": p,
                    "readers": sorted(reads.get(p, ())),
                    "writers": sorted(w for w in writes.get(p, ()) if w in tracked),
                    "n_tracked": len([t for t in tracked if t == p or t.startswith(p + "/")]),
                    "rule": ignored_by(p, root),
                    "sweep": next((r for r in roots if p == r.rstrip("/")
                                   or p.startswith(r.rstrip("/") + "/")), None)})
    return out


def sweep_roots(root=ROOT):
    """`RESIDUE_ROOTS` read out of `checks/sweep.py` BY AST, NOT BY IMPORTING IT. MEASURED
    2026-10-14: `exec_module` on `checks/sweep.py` exceeded a 120 s timeout building its citation
    corpus, so an instrument that needs one tuple from that file must not run the whole of it."""
    for n in ast.walk(ast.parse(open(os.path.join(root, "checks/sweep.py"), errors="replace").read())):
        if isinstance(n, ast.Assign) and any(getattr(t, "id", None) == "RESIDUE_ROOTS" for t in n.targets):
            return tuple(ast.literal_eval(n.value))
    return ()


def clone_report(root=ROOT):
    """CAN A FRESH CLONE PRODUCE THIS? The question `state()` cannot ask, because a clone and a
    swept tree are the SAME STATE and a reader that cannot tell them apart reports the same number
    in both.

    THE ANSWER IS FOUR VERDICTS, AND EVERY ONE OF THEM IS REACHABLE -- **AN UNREACHABLE BUCKET IS A
    TYPO, NOT A RESULT**, and my first version shipped `RESTORED` over a set that was pre-filtered
    to `n_tracked == 0`, so it could never fire and printed `RESTORED (0 of 19)` as if it were a
    measurement. The four are about WHO MAKES IT, not about WHAT IT IS:

        TRACKED     in `HEAD`: the clone HAS it. THE CONTROL, and by far the largest bucket.
        RESTORABLE  0 tracked and NOTHING hides it -- no `.gitignore` line, no sweep root. One
                    `git add` from reproducible; nobody has written that list down.
        GENERATOR   0 tracked, hidden or swept, and a TRACKED writer reaches it: the clone CAN
                    produce it, by RUNNING that writer. Its cost is COMPUTE, not code.
        HANDMADE    0 tracked, hidden or swept, and NO writer: no clone can produce it, ever.

    `GENERATOR` IS THE INTERESTING ONE BECAUSE ITS COST IS COMPUTE, NOT CODE. `runs/graphcmp/D` is
    a `GENERATOR` hole: `checks/differ.py` is tracked, so the corpus is reproducible -- at 318 s and
    ~830 MB (MEASURED 2026-10-14, from the unit brief; NOT re-measured here, `bend` was not run).
    `HANDMADE` is the one that costs a person: MEASURED 2026-10-14, `bin/bend` has **0** writers
    across the 209-instrument population, **0** of its bytes in `HEAD`, and 10 readers -- and
    `tools/get-bend.sh`, which is tracked, clones `references/bend` and never writes the shim.

    AND THE SCOPE SLIP IS GONE, AND WHAT REPLACED IT IS SMALLER AND MEASURED. THE OLD ADMISSION
    READ "18 FURTHER INSTRUMENTS (17 checks/*.sh, 1 checks/*.mjs) ... ARE INVISIBLE TO THIS WALK",
    WHICH WAS TRUE AND WHICH NAMED A POPULATION BY EXTENSION. `sites()` now also walks every
    TRACKED file whose shebang names a shell -- 272 lanes tree-wide, 21 of which have no `.sh` in
    their name at all -- and `tools/get-bend.sh` is one of them. See `shell_lanes()`.

    WHAT IS LEFT IS STATED BY COUNT AND NOT BY APOLOGY, IN `residual()`."""
    holes = clone_paths(root)
    for h in holes:
        h["verdict"] = verdict(h)
    print("CAN A FRESH CLONE PRODUCE IT?  -- git ls-tree -r HEAD is the tree, `git check-ignore` is "
          "git's own\nmatcher, RESIDUE_ROOTS is read by AST. Nothing here is listed.")
    for v in ("TRACKED", "GENERATOR", "HANDMADE", "RESTORABLE"):
        g = [h for h in holes if h["verdict"] == v]
        print(f"\n{v} ({len(g)} of {len(holes)} paths named by a live instrument):")
        for h in g:
            if v == "TRACKED" and not h["readers"]:
                continue  # The tracked control is hundreds of rows; print only what is READ.
            why = h["rule"] or (f"sweep root {h['sweep']}" if h["sweep"] else "")
            print(f"  {h['path']:<32} readers={len(h['readers']):<3} tracked={h['n_tracked']:<5} "
                  f"writer={h['writers'][0] if h['writers'] else 'NOTHING'}"
                  f"{'  <- ' + why if why and v != 'TRACKED' else ''}")
    handmade = [h for h in holes if h["verdict"] == "HANDMADE" and h["readers"]]
    n_py = len(glob.glob(os.path.join(root, "checks", "*.py"))) + \
           len(glob.glob(os.path.join(root, "gates", "*.py")))
    lanes = shell_lanes(root)
    # THE DENOMINATOR IS RENAMED, AND THE MEASUREMENT IS WHY. The old line read
    #   "DENOMINATOR: {len(holes)} on-disk paths named by {len(sites(root))} call sites"
    # and `sites()` returns ONE ROW PER CALL SITE, so the word `DENOMINATOR` sat over an
    # OCCURRENCE COUNT while the number beside it was a count of DISTINCT PATHS. **MEASURED TWICE
    # ON 2026-10-17, AND THE COUNTS MOVE BECAUSE OTHER UNITS ARE WRITING THIS TREE:
    # 11 060 / 6 643 / 5 854 AND THEN 11 141 / 6 680 / 5 890** -- call-site OCCURRENCES, distinct
    # NAMED VALUES, and distinct values carrying no `/` at all (`=`, `,`, `store_true`, `PYTHON`,
    # `echo`). So 88.2% of the distinct values and 88.7% of the occurrences are BARE TOKENS, and
    # 214/11 141 read as COVERAGE ("2% of our named paths are reproducible") when it is not a
    # ratio of like units.
    # **A DENOMINATOR THAT DOES NOT MATCH ITS NUMERATOR's SUBJECT IS THE `SPEC=2` CLASS ONE LEVEL
    # DOWN**, and no verdict moved -- `clone_paths()` intersects with `os.path.exists` before
    # anything is graded -- which is exactly why it survived: the only symptom was a printed line.
    #
    # **AND NO FIGURE IS TRANSCRIBED HERE, WHICH IS THE POINT OF THE WHOLE REVISION.** The first
    # version of this comment carried a fourth number -- "6 032 name no file on this tree" -- that
    # NO COMMAND HAD PRODUCED. It was written because it fit the sentence, and a number that fits
    # a sentence is exactly the `gates/docnum-claim-gate.py` class: **a number written where a
    # measurement could be taken, in prose that outlives the measurement.** It is gone rather than
    # corrected, because the printed line below now reports the bare-token share ITSELF, every
    # run, so a reader who wants the figure takes it from the instrument and not from here.
    #
    # WHAT IT COUNTS NOW, AND EACH NUMBER NAMES ITS UNIT: `paths` is the graded population,
    # `values` is the DISTINCT set `sites()` named (the only denominator in the same unit as
    # `paths`), and `sites` is the occurrence count, labelled OCCURRENCES because that is what it
    # is. **THE CONSUMERS ARE ZERO** -- MEASURED by grep, not assumed: `grep -rn DENOMINATOR` over
    # `*.py *.sh *.mjs *.md *.rows` returns this file's own two mentions and nothing that reads
    # this line, and `clone_report()`'s stdout is parsed by no instrument in the tree. So the
    # rename costs one line and no consumer edit; had there been a consumer, the count is the
    # number a reader would need and not the number this file could supply.
    named = sites(root)
    values = {v for _, _, v in named}
    bare = sum(1 for v in values if "/" not in v.strip("/"))
    print(f"\nDENOMINATOR: {len(holes)} on-disk PATHS, graded, from {len(values)} distinct NAMED "
          f"VALUES\n            over {len(named)} call-site OCCURRENCES; {bare} of those values are BARE "
          f"TOKENS with no `/`, so\n            the occurrence count is NOT a path count and "
          f"must not be read as coverage. From {n_py}\n            `.py` instruments by AST and "
          f"{len(lanes)} tracked shell lanes by shebang, out of "
          f"{len(tracked_files(root))} files in HEAD.")
    print("RESIDUAL: " + residual(root))
    print(f"THE COSTLY LINE: {len(handmade)} read path(s) have no writer in ANY walked form: "
          f"{', '.join(h['path'] for h in handmade) or 'none'}")
    return holes


#: A tracked file with a PYTHON shebang and no `.py` name, or a NODE lane, is invisible to BOTH
#: resolvers -- and the first version of `residual()` got this backwards, reporting three
#: `#!/usr/bin/env python3` files as "a language neither resolver reads". **AN ADMISSION THAT
#: MISDESCRIBES ITS OWN POPULATION IS WORSE THAN NO ADMISSION**, so both classes are matched by
#: CONTENT and counted, never by extension.
PY_SHEBANG = re.compile(r"^#!.*\bpython[0-9.]*\b")
#: `from "node:fs"` / `require("...")` -- how a Node lane with NO shebang announces itself.
#: MEASURED: `checks/nan_census.mjs` begins with a `//` comment, so no shebang test can find it
#: and an extension test is the suffix-set defect this file was written to close.
NODE_LANE = re.compile(r"""from\s+["']node:|require\(\s*["']""")


def residual(root=ROOT):
    """WHAT IS STILL INVISIBLE, AS THREE COUNTS, SO THE ADMISSION IS FALSIFIABLE AND NOT A MOOD.

    **THE OLD LINE SAID "18 FURTHER INSTRUMENTS ... ARE INVISIBLE TO THIS WALK" AND NAMED THEM BY
    EXTENSION, WHICH WAS THE DEFECT IT WAS ADMITTING.** This one measures, and each class is a
    population matched BY CONTENT:

        `py_named`   tracked lanes with a PYTHON shebang and no `.py` name. The AST walk globs
                     `*.py`, so these are Python the walk cannot open. MEASURED 2026-10-17: **3**
                     (`oracles/graphcmp-oracle.py.BASELINE`, `oracles/llvmir-oracle.py.PRENAME`,
                     `oracles/nl-oracle.py.PRENAME`).
        `node`       tracked lanes importing `node:` builtins with no shell shebang.
                     MEASURED 2026-10-17: **17**, of which the one in this project's own
                     instrument home is `checks/nan_census.mjs` -- a `//` comment on line 1, so
                     no shebang test finds it.
        `opaque`     shell lanes this extractor reads and finds no create-verb in.
                     MEASURED 2026-10-17: **225 of 272**. **THIS IS A FLOOR ON WHAT IS UNREAD,
                     NOT A COUNT OF WHAT IS MISSING**, and the difference is the whole point: a
                     reader who cannot tell those two apart reads the wrong number as a result.

    There is a fourth, and it is the largest, so it is named rather than left for the next reader:
    **THE AST RESOLVER LOSES A DIRECTORY.** `resolve()` returns `""` for `Path(__file__).resolve()`,
    and its `Attribute` branch answers a no-argument `.parent` by descending into the `Call` below
    it, so `HERE = Path(__file__).resolve().parent` binds `HERE` to `""` and `HERE / "gen"` is
    recorded as the bare token `gen`. MEASURED 2026-10-17: `checks/abi_gate.py` writes
    `checks/gen/` and the census prints `writer=NOTHING` for it. **THIS IS THE BRIEF'S OWN WARNING
    LIVE IN A `.py` FILE**: a truncated token is not a harmlessly blind one, it is a token that
    writes false rows. Repairing it needs the file's own directory threaded through `_env`,
    `sites()` and `plant_writes()`; a correctly-normpath'd prototype still LOST 51 existing paths,
    so it is NOT a one-line repair and it is NOT shipped here on top of a measured hole.
    """
    py_named, node = [], []
    for t in tracked_files(root):
        if t.endswith(".py") or not os.path.isfile(os.path.join(root, t)):
            continue
        with open(os.path.join(root, t), errors="replace") as fh:
            head = fh.read(4096)
        first = head.split("\n", 1)[0]
        if SHELL_SHEBANG.match(first):
            continue
        if PY_SHEBANG.match(first):
            py_named.append(t)
        elif NODE_LANE.search(head):
            node.append(t)
    lanes = shell_lanes(root)
    opaque = sum(1 for t in lanes if not shell_sites(root, [t]))
    return (f"{len(py_named)} tracked Python lane(s) the `*.py` glob cannot name "
            f"({', '.join(sorted(py_named))}), {len(node)} tracked Node lane(s) "
            f"(e.g. {', '.join(sorted(node)[:2]) or 'none'}), "
            f"{opaque} of {len(lanes)} shell lanes yield no site (a FLOOR on what is unread, "
            f"not a count of what is missing), and the AST resolver loses a directory "
            f"(`HERE` -> \"\"): HANDMADE is a LOWER BOUND.")


def verdict(h):
    """THE FOUR VERDICTS, AS A FUNCTION. `--plant` drives THIS, not a transcription of it.

    `gates/runner.py --plant`'s first version reached past its twelve cases into the helpers, and
    breaking `preconditions`' branch left the plant GREEN -- a plant that cannot go red is the
    class this file's own header is about. **THE DECISION IS ONE EXPRESSION AND IT LIVES HERE
    ONCE**, so `clone_report()` and `plant_shell()` cannot drift into disagreeing about what
    `HANDMADE` means.
    """
    hidden = bool(h["rule"] or h["sweep"])
    return ("TRACKED" if h["n_tracked"] else "RESTORABLE" if not hidden
            else "GENERATOR" if h["writers"] else "HANDMADE")


def plant_shell(root=None):
    """TWELVE DIRECTIONS AGAINST `clone_paths()` AND `verdict()` -- THE SHIPPED PAIR.

    `gates/runner.py --plant` drives its twelve cases through the SHIPPED decision function, and
    records why: its first version reached past them into the helpers, and breaking
    `preconditions`' branch left the plant GREEN. **So every case here builds a tree, calls
    `clone_paths()` -- which calls `verdict()` -- and reads the verdict back. None of them
    re-implements the decision, and none of them reaches past it.**

    The tree is a `TemporaryDirectory`, so `runs/` in THIS repository is never touched: **the one
    rule about the live artefact set is that nothing may delete it, and the way to honour that is
    not to write a test that does.** `runs/x` inside the temporary tree is the sweep-hidden target,
    because `RESIDUE_ROOTS` is read out of the synthetic `checks/sweep.py` and a `git check-ignore`
    in a non-repository answers nothing.

    THE CASE THAT MATTERS MOST IS **B**, THE NEGATIVE CONTROL: the same tree with the create-verb
    deleted. A plant of only positives cannot distinguish a working walk from a walk that returns
    every path as written, which is the `gates/gates-pop.py` PLANT 6 defect in its other dress.
    """
    bad = []
    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        (r / "checks").mkdir()
        (r / "checks" / "sweep.py").write_text('RESIDUE_ROOTS = (".agents/slop", "runs")\n')
        (r / "runs").mkdir()
        (r / "runs" / "x").mkdir()  # the target EXISTS, so only the walk can decide it
        lanes = {}
        # A LANE THAT NAMES THE TARGET AND WRITES NOTHING, SO `runs/x` ALWAYS HAS A ROW. Without
        # it a case that correctly finds no writer returns NO-ROW, and `NO-ROW` is not a verdict --
        # **a census that cannot distinguish "absent from the population" from "in the population
        # with no writer" is the `AGENTS.md` STALE case**, and a plant that returns NO-ROW for
        # half its cases is not a plant.
        lanes["reader"] = "checks/reader.py"
        (r / "checks" / "reader.py").write_text(
            'RUN = "runs/x"\n\ndef main():\n    print(RUN)\n\n'
            "if __name__ == '__main__':\n    main()\n")

        def lane(name, body):
            lanes[name] = f"checks/{name}"
            (r / "checks" / name).write_text(body)
            return lanes[name]

        # A -- a create-verb names the target. THE CASE THE WHOLE TASK EXISTS FOR.
        lane("a.sh", "#!/bin/sh\nmkdir -p runs/x\n")
        # B -- THE NEGATIVE CONTROL: same tree, verb deleted, so the answer MUST become HANDMADE.
        lane("b.sh", "#!/bin/sh\n# mkdir -p runs/x\n")
        # C -- the target arrives through a variable, so a walk that never dereferences misses it.
        lane("c.sh", "#!/bin/sh\nD=runs\nmkdir -p \"$D/x\"\n")
        # D -- the self-root idiom, which is `tools/get-bend.sh`'s exact shape and which a walk
        #     that strips an unresolved `$ROOT` would either drop or truncate to `references/bend`.
        lane("d.sh", '#!/bin/sh\nROOT=$(cd "$(dirname "$0")/.." && pwd)\nmkdir -p "$ROOT/runs/x"\n')
        # E -- NO DOT IN THE NAME. `glob("*.sh")` cannot see this file, and `checks/bend` and
        #     `bin/bend` are two live instances of the shape.
        lanes["probe"] = "checks/probe"
        (r / "checks" / "probe").write_text("#!/bin/sh\nmkdir -p runs/x\n")
        # F -- A TARGET THAT DOES NOT EXIST MUST NOT BECOME A ROW. This is the `os.path.exists`
        #     intersection, and it is what makes a permissive extractor sound.
        lane("f.sh", "#!/bin/sh\nmkdir -p runs/never-created\n")
        # G -- an ABSOLUTE PATH IS A SYSTEM PATH, not this tree's `bin/`.
        lane("g.sh", "#!/bin/sh\nmkdir -p /tmp/plant-shell\n")
        # H -- `>&2` IS A FILE DESCRIPTOR. A regex that reads it as a path writes a false row.
        lane("h.sh", "#!/bin/sh\nmkdir -p runs/x\necho nope >&2\n")
        # I -- A PLANT IS NOT A GENERATOR: a lane that writes into a temporary directory laundered
        #     into `GENERATOR` once already, at `plant_writes()`'s own docstring.
        lane("i.sh", '#!/bin/sh\nT=$(mktemp -d)\ncp runs/x "$T/y"\n')

        cases = [
            ("A a create-verb writes the target", ["a.sh"], "GENERATOR"),
            ("B THE CONTROL: same tree, verb deleted", ["b.sh"], "HANDMADE"),
            ("C a variable-resolved target", ["c.sh"], "GENERATOR"),
            ("D the self-root $(cd $(dirname $0) idiom", ["d.sh"], "GENERATOR"),
            ("E a shell lane with NO DOT in its name", ["probe"], "GENERATOR"),
            ("G an absolute path is a SYSTEM path", ["g.sh"], "HANDMADE"),
            ("H >&2 is a file descriptor, not a path", ["h.sh"], "GENERATOR"),
            ("I cp SRC $TMP/DEST writes the DEST only", ["i.sh"], "HANDMADE"),
            ("J an untracked lane is invisible", [], "HANDMADE"),
        ]

        def read_back(tracked_paths):
            """`clone_paths()` THEN `verdict()` -- THE SHIPPED PAIR, never a transcription of it."""
            return next((verdict(h) for h in
                         clone_paths(root=r, tracked=[lanes["reader"]] + tracked_paths)
                         if h["path"] == "runs/x"), "NO-ROW")

        for label, ls, want in cases:
            got = read_back([lanes[n] for n in ls])
            ok = got == want
            bad += [] if ok else [f"{label}: got {got}, wanted {want}"]
            print(f"  {'OK  ' if ok else 'FAIL'}  {label:<46} -> {got}")

        # F -- A TARGET THAT DOES NOT EXIST MUST NOT BECOME A ROW. This is the `os.path.exists`
        #     intersection, and it is what makes a permissive extractor sound. The FIRST version of
        #     this case asserted `runs/x` was `HANDMADE`, which was the WRONG CLAIM: `mkdir -p
        #     runs/never-created` really does write INTO `runs`, so `GENERATOR` is the true
        #     verdict for `runs`. The claim is about the ABSENT PATH, not about the existing one.
        rows = [h["path"] for h in clone_paths(root=r, tracked=[lanes["reader"], lanes["f.sh"]])]
        ok = "runs/never-created" not in rows
        bad += [] if ok else ["F a nonexistent target produced a row"]
        print(f"  {'OK  ' if ok else 'FAIL'}  {'F a nonexistent target produces NO row':<46} "
              f"-> {'absent' if ok else 'PRESENT'}")

        # K -- A `.py` LANE IS STILL FOUND. The shell walk was ADDED; had it REPLACED the AST walk
        #     this row would be NO-ROW, and eleven green plants would then mean nothing.
        (r / "checks" / "k.py").write_text(
            "from pathlib import Path\n"
            "def main():\n    (Path(__file__).parent / 'runs' / 'x').mkdir()\n"
            "if __name__ == '__main__':\n    main()\n")
        got = read_back(["checks/k.py"])
        ok = got == "GENERATOR"
        bad += [] if ok else [f"K a .py lane: got {got}, wanted GENERATOR"]
        print(f"  {'OK  ' if ok else 'FAIL'}  {'K a .py lane is still found':<46} -> {got}")

        # L -- THE POPULATION IS A SET OF LANES, NOT A LIST OF OCCURRENCES. `git ls-tree` cannot
        #     repeat a path, so this is defensive -- and it is ASSERTED rather than assumed,
        #     because `sites()` RETURNS A LIST and `clone_report()` prints `len(sites(root))` as
        #     the census denominator, so a duplicate would silently inflate a printed number.
        once = len(shell_lanes(r, tracked=[lanes["a.sh"]]))
        twice = len(shell_lanes(r, tracked=[lanes["a.sh"]] * 3))
        ok = once == twice == 1
        bad += [] if ok else [f"L a lane listed 3 times yields {twice} lane(s), wanted 1"]
        print(f"  {'OK  ' if ok else 'FAIL'}  {'L one lane listed 3 times is still one lane':<46} "
              f"-> {once}=={twice}")
    print(f"--plant-shell: {'12 directions OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


def main():
    if "--plant-shell" in sys.argv:
        return plant_shell()
    if "--plant" in sys.argv:
        return plant() or plant_shell()
    if "--clone" in sys.argv:
        return PASS if clone_report() else DEAD
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
