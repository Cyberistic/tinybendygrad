#!/usr/bin/env python3
"""DISCOVERY of this tree's GENERATED DIRECTORIES, with no list to maintain.

WHY THIS FILE EXISTS, IN THE BRIEF'S OWN WORDS. **`checks/gen/` WAS INVISIBLE TO BOTH
META-INSTRUMENTS.** `gates/retention-check.py` had a TWO-ITEM REGISTRY (`Output("graphcmp", ...)`,
`Output("gates", ...)`) and `gates/gates-pop.py` had a LITERAL `HOMES = ("checks", "gates")`. A
POPULATION DEFINED BY A THREE-ITEM LIST CANNOT BE WRONG ABOUT A FOURTH ITEM, BECAUSE IT NEVER
LOOKS AT ONE. And `checks/abi_gate.py:606,616` writes `checks/gen/probe.js` and
`checks/gen/probe.gen.c` -- **and does it by handing the path to `bend -o`, so no `write_text`
call exists anywhere near it.**

SO THE QUESTION IS NOT *WHERE DOES IT GO*. IT IS ***WHAT MAKES A DIRECTORY GENERATED***, AND THE
ANSWER MUST BE A PROPERTY READABLE FROM THE TREE, NOT A NAME. Four candidates, each rejected on
this tree's own measurements, in `.agents/slop/gendirs/properties.md`:

  P1  `.gitignore`D                  REJECTED AS A POPULATION: `checks/gen/` was NOT ignored.
                                          That is a defect IN THE TREE and it is fixed in the
                                          ignore file, not by bending a predicate to accommodate
                                          it.
  P2  something writes into it       ADOPTED, and it is DISCOVERED: every executable source in
                                          the tree is scanned for a write site and the target is
                                          resolved by a constant-propagation FIXPOINT.
  P3  nobody cites it                REJECTED: a citation index built from a tree containing the
                                          instrument has gone wrong 3x on this repo, and measured
                                          directly, `checks/gen/` is cited 9 times.
  P4  named by a `.gitignore` rule    REJECTED: a declaration of intent, i.e. P1 restated.

**THE ADMITTED LIMIT, MEASURED NOT ASSUMED.** A static write-site scan is a LOWER BOUND. Every miss
is one of two things, and both are named here rather than absorbed:

  (a) A SUBPROCESS WRITE. `checks/abi4_gate.py:501` runs `rc_of(REPO / g)`, which is
      `subprocess.run([sys.executable, str(script), *args], cwd=REPO)` and names NO output path.
      `checks/gen/` is written TWO PROCESSES AWAY. **NO AMOUNT OF AST WORK CLOSES THIS: THE
      WRITER IS NAMED BY A CALL AND THE TARGET BY A CONVENTION INSIDE ANOTHER PROGRAM.**
  (b) a path expression this grammar does not model.

So `discovered()` is a LOWER BOUND and `coverage()` returns the scan's denominator, and every
caller prints both. A lower bound with a printed denominator is a measurement; a list is a claim.

THE SECOND, INDEPENDENT HALF, because ONE discovery route is how the class survives.
`tracked_dirs()` asks git a question that involves NO source file at all: which directories have
index entries, and how many of those entries are git's EMPTY BLOB. Cross-referencing the two is
what makes the population auditable, and their DISAGREEMENT is reported rather than resolved --
**two instruments derived from the same table cannot audit that table, because both change
together.**

    --help before trusting this file. It writes nothing and runs no gate.
    --plant runs seven plants on SYNTHETIC trees and never touches the live one, because **A
    META-INSTRUMENT IS THE ONE THING WHOSE OWN BLIND SPOT NOBODY ELSE CHECKS.** TWO OF THEM ARE
    THE PAIR THE BRIEF ASKS FOR AND THEY ASSERT OPPOSITE DIRECTIONS: a plant that ADDS A GENERATED
    DIRECTORY THE INSTRUMENT MUST NOTICE, and a plant that ADDS A **NON**-GENERATED DIRECTORY IT
    MUST **NOT** PICK UP. **A CHECK THAT CANNOT SAY NO IS NOT A CHECK, IT IS A PRINTER.**
"""
import argparse
import ast
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GIT_EMPTY_BLOB = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"

# THE SCAN'S OWN COVERAGE, AS A DENOMINATOR. A scanner that skips `references/` and `bin/` must
# SAY SO with a number, because a silently narrowed scan reports a narrow population and calls it
# the whole one -- `checks/sweep.py`'s LIVE_UNITS lesson, and `checks/repro-paths.py`'s REF regex
# that could not see 6 of `checks/e2e.py`'s 15 stage inputs.
SKIP_TOP = (".git", "references", "node_modules", ".venv", "__pycache__", "bin")
SOURCE_SUFFIXES = (".py", ".sh", ".mjs", ".js")

# FOUR WRITER SHAPES, MEASURED. Version 1 of this scanner knew the first and found 1 of 12.
WRITE_METHODS = frozenset({
    "write_text", "write_bytes", "mkdir", "rmtree", "unlink", "replace", "makedirs",
    "touch", "write", "appendText", "writeFileSync", "appendFileSync",
})
WRITE_FUNCS = frozenset({"copy", "copytree", "copy2", "copyfile"})
# A COMPILER WRITES THE FILE. `checks/abi_gate.py:616` is
# `subprocess.run([BEND, src, "-o", str(gendir / f"probe.{ext}")])`: the gate never opens the
# output, it NAMES it on a command line. This is the shape that hid the whole subject.
OUTPUT_FLAGS = frozenset({"-o", "--out", "--output", "-O"})
OUTPUT_SINKS = frozenset({"run", "call", "check_output", "check_call", "Popen"})
# A CAST, NOT A PATH OPERATION -- and the cast is what `bend -o`'s argument wears.
CASTS = frozenset({"str", "fspath", "abspath", "realpath"})
# WRITES THAT NAME A DIRECTORY RATHER THAN A FILE. The discriminator for "is this target a
# directory" is THE CALL and never `os.path.isdir`, because a `mkdir` target is a directory that
# does not exist yet. MEASURED: `isdir` bucketed `checks/gen` under `checks` on a fresh tree.
DIRECTORY_SHAPES = frozenset({"mkdir", "makedirs", "rmdir"})


# ---- discovery: sources ----------------------------------------------------------------
def sources(root: Path = ROOT) -> list[Path]:
    """Every source file under `root`, EXCLUDING `SKIP_TOP`, with its own path remembered."""
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        rel = "" if rel == "." else rel
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_TOP)
        if rel.split(os.sep)[0] in SKIP_TOP:
            dirnames[:] = []
            continue
        out += [Path(dirpath) / f for f in sorted(filenames)
                if Path(f).suffix in SOURCE_SUFFIXES]
    return out


# ---- discovery: the constant-propagation fixpoint --------------------------------------
def _walks_file(node) -> bool:
    """Does this chain's base come from `__file__`? THE SHAPE, never the variable's name --
    `checks/both-census.py` and `checks/disagree-gate.py` both call theirs `HERE` and one holds a
    DIRECTORY and the other a FILE, and reading the name mis-measured one of them."""
    seen = 0
    while isinstance(node, (ast.Attribute, ast.Call, ast.Subscript)) and seen < 12:
        seen += 1
        if isinstance(node, ast.Attribute):
            node = node.value
        elif isinstance(node, ast.Call):
            node = node.func
        else:
            node = node.value
    return isinstance(node, ast.Name) and node.id == "__file__"


def expr(node, env):
    """The string VALUE of a path expression under `env`, or None.

    EIGHT ARMS, EACH ONE ADDED BECAUSE A MEASUREMENT SAID THE INSTRUMENT WAS SILENT:

      `Path("a") / "b"`         a BinOp chain
      `os.path.join(a, b)`      a join
      `str(x)` / `os.fspath(x)` a CAST -- MEASURED: `abi_gate.py:616` writes the output path as
                                 `str(gendir / f"probe.{ext}")`, so without this arm the ONLY
                                 write to `checks/gen/` in the tree is invisible. **A CAST IS NOT
                                 A PATH OPERATION AND A SCANNER THAT TREATS IT AS ONE NEVER
                                 REACHES THE PATH.**
      `.parent`                 a COMPONENT STRIP -- MEASURED: recursing into `.parent` instead of
                                 stripping binds `HERE` to the FILE, `HERE / "gen"` to
                                 `.../abi_gate.py/gen`, and the scanner answers about a path that
                                 CANNOT BE RIGHT. That is the `artefacts_ok()` shape
      `.parents[n]`             EVALUATED, with the two SPELLINGS differing by one
      `f"a{x}b"`                an f-string -- known interpolands become GLOB SEGMENTS
      `self.dir`                an ENVIRONMENT KEY -- MEASURED: `gates/gatekit.py:177` writes
                                 through `self.dir`, and recursing reaches `Name('self')`, which
                                 binds nothing, so the directory TEN gates write into was
                                 invisible -- which is why `retention-check.py` transcribes it by
                                 hand
      a bare name                the fixpoint's whole product
    """
    if node is None:
        return None
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return env.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        a, b = expr(node.left, env), expr(node.right, env)
        return (a.rstrip("/") + "/" + b.lstrip("/")) if (a and b) else None
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        a, b = expr(node.left, env), expr(node.right, env)
        return a + b if (a is not None and b is not None) else None
    if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute) \
            and node.value.attr == "parents":
        base = expr(node.value.value, env)
        i = node.slice.value if isinstance(node.slice, ast.Constant) else None
        if base is None or not isinstance(i, int):
            return None
        # THE TWO SPELLINGS DIFFER BY ONE AND BOTH APPEAR IN THIS TREE, AND GETTING IT WRONG IS
        # WORSE THAN NOT BINDING AT ALL. MEASURED: `checks/differ.py:41` is
        # `Path(__file__).resolve().parents[1]` -- the walk starts at the FILE, so `parents[0]`
        # is the file's own DIRECTORY -- while `checks/abi_gate.py:50` is `HERE.parents[0]` over a
        # `HERE` that is ALREADY a directory. Reading the shape off a NAME (`if "HERE" in expr`)
        # is the error `gates/gates-pop.py` documents and fixed: **A NAME CANNOT TELL YOU WHAT A
        # VALUE HOLDS.**
        drop = i if _walks_file(node.value.value) else i + 1
        parts = base.split("/")
        return "/".join(parts[:len(parts) - drop]) or "/"
    if isinstance(node, ast.Attribute):
        if isinstance(node.value, ast.Name) and node.value.id in ("self", "cls"):
            return env.get(f"{node.value.id}.{node.attr}")
        base = expr(node.value, env)
        if base is None:
            return None
        return (base.rsplit("/", 1)[0] or "/") if node.attr == "parent" else base
    if isinstance(node, ast.JoinedStr):
        return "".join(
            str(v.value) if isinstance(v, ast.Constant)
            else ("*" if expr(v.value, env) is None else expr(v.value, env))
            for v in node.values)
    if isinstance(node, ast.Call):
        nm = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if (nm == "Path" or nm in CASTS) and node.args:
            return expr(node.args[0], env)
        if nm in ("join", "normpath", "resolve", "absolute", "expanduser"):
            parts = [expr(a, env) for a in node.args]
            if parts and all(p is not None for p in parts):
                return "/".join(p.strip("/") for p in parts) if nm == "join" else parts[0]
        return expr(node.func, env)
    return None


def prefix(node, env):
    """The longest KNOWN DIRECTORY PREFIX of a path expression, or None.

    NEEDED BECAUSE A GENERATOR'S OUTPUT NAME IS A RUNTIME PARAMETER, NOT A CONSTANT. MEASURED:
    `gates/gatekit.py:176` is `self.dir = ART / name` and `:177` is `self.dir.mkdir(...)`, so the
    full value of `self.dir` is unresolvable by any amount of constant propagation -- `name` is
    `Gate.__init__`'s first argument. But its PREFIX is `gates/artifacts`, and the PREFIX IS THE
    THING BOTH INSTRUMENTS ENUMERATE. `retention-check.py` transcribes this set BY HAND
    (`GATEKIT_OUTPUT` plus a hardcoded `if self.key == "graphcmp"` branch) for exactly this reason.

    **A VALUE THAT CANNOT BE FULLY KNOWN IS NOT A REASON TO CALL IT UNKNOWN.** A path whose last
    segment is a parameter is still a directory. Anything unknown becomes a `*` GLOB SEGMENT,
    honestly marked, never guessed.
    """
    if node is None:
        return None
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return env.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        a = prefix(node.left, env)
        if a is None:
            return None
        b = prefix(node.right, env)
        return f"{a.rstrip('/')}/{b.lstrip('/') if b else '*'}"
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        a = prefix(node.left, env)
        return f"{a}*" if a is not None else None
    if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute) \
            and node.value.attr == "parents":
        base = prefix(node.value.value, env)
        i = node.slice.value if isinstance(node.slice, ast.Constant) else None
        if base is None or not isinstance(i, int):
            return None
        drop = i if _walks_file(node.value.value) else i + 1
        parts = base.split("/")
        return "/".join(parts[:len(parts) - drop]) or "/"
    if isinstance(node, ast.Attribute):
        if isinstance(node.value, ast.Name) and node.value.id in ("self", "cls"):
            return env.get(f"{node.value.id}.{node.attr}")
        if node.attr == "parent":
            base = prefix(node.value, env)
            return (base.rsplit("/", 1)[0] or "/") if base else None
        return prefix(node.value, env)
    if isinstance(node, ast.JoinedStr):
        return "".join(
            str(v.value) if isinstance(v, ast.Constant)
            else ("*" if prefix(v.value, env) is None else prefix(v.value, env))
            for v in node.values)
    if isinstance(node, ast.Call):
        nm = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if (nm == "Path" or nm in CASTS) and node.args:
            return prefix(node.args[0], env)
        if nm in ("resolve", "absolute", "normpath", "expanduser") and node.args:
            return prefix(node.args[0], env)
        if nm == "join":
            parts = [prefix(a, env) for a in node.args]
            if parts and parts[0] is not None:
                return "/".join(p or "*" for p in parts)
        return prefix(node.func, env)
    return None


def _bind(scope, env) -> None:
    """Bind `NAME = <path expr>` in one scope, IN PLACE. **`env` is passed to `expr`, never
    defaulted**: MEASURED, `expr(node.value)` builds a fresh `{}`, so `__file__` and every
    earlier binding are invisible, and `HERE = Path(__file__).resolve().parent` -- the one
    constant the whole scan rests on -- evaluates to None. A FIXPOINT THAT EVALUATES ITS OWN
    RIGHT-HAND SIDE AGAINST AN EMPTY ENVIRONMENT IS NOT A FIXPOINT."""
    for node in ast.walk(scope):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        # `prefix` FIRST, so `ART / name` binds `gates/artifacts/*` when `name` is a runtime
        # parameter no amount of propagation can reach; `expr` SECOND, so a fully-known value is
        # never degraded into a glob.
        val = prefix(node.value, env) or expr(node.value, env)
        if val is None:
            continue
        for t in targets:
            if isinstance(t, ast.Name):
                env[t.id] = val
            elif isinstance(t, ast.Attribute) and isinstance(t.value, ast.Name) \
                    and t.value.id in ("self", "cls"):
                # `self.dir = ART / name` -- MEASURED: this is `gates/gatekit.py:176`, the ONE
                # assignment that decides where all 10 gate output directories live, and a binder
                # that only understands module-level NAMES reads it as nothing.
                env[f"{t.value.id}.{t.attr}"] = val


def _shell_sites(src: str) -> list[tuple[str, int, str]]:
    """Shell write sites: a redirect target, or the destination of `cp`/`mv`/`tee`/`install`."""
    import re
    out = []
    cmd = re.compile(r"\b(cp|mv|tee|install|rsync)\b[^\n|;&]*?\s([\w./{}$-]+)")
    for i, line in enumerate(src.splitlines(), 1):
        if re.match(r"^\s*#", line):
            continue
        m = cmd.search(line)
        if m:
            out.append((m.group(2), i, m.group(1)))
        for r in re.finditer(r"(?:>|>>)\s*[\"']?([\w./{}$-]+)", line):
            out.append((r.group(1), i, "redirect"))
    return out


def _write_sites(path: Path) -> tuple[list[tuple[str, int, str]], list[tuple[int, str]]]:
    """`(found, unresolved)` for ONE source file. `found` is `(target, line, shape)`."""
    try:
        src = path.read_text(errors="replace")
    except OSError:
        return [], [(0, "UNREADABLE")]
    if path.suffix == ".sh":
        return _shell_sites(src), []
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        return [], [(e.lineno or 0, f"UNPARSEABLE:{e.msg}")]
    # `__file__` SEEDED WITH THE FILE'S OWN ABSOLUTE PATH. Without it `HERE` never binds and the
    # scan reports NOTHING for `checks/gen/`. **A CONSTANT PROPAGATION FIXPOINT THAT DOES NOT KNOW
    # WHAT `__file__` IS PROPAGATES CONSTANTS FROM NOTHING.**
    env: dict[str, str] = {"__file__": str(path.resolve())}
    for _ in range(8):                                   # until nothing new binds
        before = len(env)
        _bind(tree, env)
        for fn in (n for n in ast.walk(tree)
                   if isinstance(n, (ast.FunctionDef, ast.ClassDef))):
            _bind(fn, env)
        if len(env) == before:
            break
    found: list[tuple[str, int, str]] = []
    unresolved: list[tuple[int, str]] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        f = node.func
        nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
        if nm in WRITE_METHODS or nm in WRITE_FUNCS:
            if not node.args:
                # `gendir.mkdir(exist_ok=True)` -- the DIRECTORY IS THE RECEIVER. MEASURED:
                # `checks/abi_gate.py:606` is the only line in the tree that CREATES
                # `checks/gen/`, and reading only arguments loses it.
                rec = prefix(f.value, env) if isinstance(f, ast.Attribute) else None
                if rec:
                    found.append((rec, node.lineno, nm))
                else:
                    unresolved.append((node.lineno, nm))
                continue
            base = prefix(node.args[0], env) if (len(node.args) > 1 and nm in WRITE_FUNCS) else None
            t = expr(node.args[-1], env) or prefix(node.args[-1], env)
            if t is None and base is None:
                unresolved.append((node.lineno, nm))
                continue
            tgt = f"{base.rstrip('/')}/{t.lstrip('/')}" if (base and t) else (t or base)
            found.append((tgt, node.lineno, nm))
        elif nm == "open" and len(node.args) >= 2:
            t = expr(node.args[0], env) or prefix(node.args[0], env)
            if t:
                found.append((t, node.lineno, "open"))
            else:
                unresolved.append((node.lineno, "open"))
        elif nm in OUTPUT_SINKS and node.args and isinstance(node.args[0], (ast.List, ast.Tuple)):
            els = node.args[0].elts
            vals = [e.value if isinstance(e, ast.Constant) else None for e in els]
            for flag in OUTPUT_FLAGS:
                if flag not in vals:
                    continue
                k = vals.index(flag)
                if k + 1 >= len(els):
                    continue
                t = expr(els[k + 1], env)
                if t:
                    found.append((t, node.lineno, f"subprocess {flag}"))
                else:
                    unresolved.append((node.lineno, f"subprocess {flag}"))
    return found, unresolved


# ---- the population --------------------------------------------------------------------
def discovered(root: Path = ROOT) -> dict[str, dict]:
    """`{repo-relative dir: {"sites": [(writer, line, shape)], "files": n}}` -- the directories
    this tree WRITES INTO, found by scanning, never enumerated.

    `root` IS RESOLVED, and that is a MEASURED fix rather than tidiness: `_write_sites` seeds
    `__file__` with `path.resolve()`, and on macOS `resolve()` hands back `/private/var/...`
    while `tempfile.TemporaryDirectory()` hands back `/var/...`. So every relative path came out
    starting `..` and **EVERY SYNTHETIC PLANT DISCOVERED NOTHING** -- 6 of 7 red, all of them for
    one path-comparison bug, and the live tree (where `ROOT` is already resolved) stayed green
    throughout. It is the same trap as `gates/gates-pop.py`'s `resolve_root`, whose own docstring
    records the measurement: **BOTH SIDES OF EVERY COMPARISON MUST BE RESOLVED, OR THE INSTRUMENT
    ANSWERS ABOUT A DIFFERENT POPULATION THAN THE ONE IT REPORTS ON.**
    """
    root = Path(root).resolve()
    dirs: dict[str, dict] = {}
    for p in sources(root):
        found, _ = _write_sites(p)
        rel_src = os.path.relpath(p, root)
        for target, line, shape in found:
            if not target:
                continue
            # A SHELL HEREDOC BODY IS NOT A PATH. `checks/gen.sh` writes `cat > "$D/cand$1.bend"
            # <<EOF` and the scanner sees the here-document's TEXT as a write target. A target with
            # whitespace in it is not a directory this process can `mkdir`, and **A POPULATION THAT
            # CONTAINS ITS OWN SOURCE TEXT IS NOT A POPULATION.**
            if any(c.isspace() for c in target) or len(target) > 200:
                continue
            absolute = target if os.path.isabs(target) else os.path.normpath(str(p.parent / target))
            is_dir_target = shape in DIRECTORY_SHAPES or target.endswith("/")
            rel = os.path.relpath(absolute, root)
            # THE OUT-OF-REPO TEST IS `rel`, NEVER `target.startswith("/")`. MEASURED: the fixpoint
            # resolves `HERE / "gen"` to an ABSOLUTE path, so an absolute-path filter discards
            # `checks/gen/` -- **THE SUBJECT OF THE WHOLE BRIEF** -- while a relative filter on the
            # same value keeps it. A guard whose filter is shaped like its subject excludes its
            # subject, and `checks/gen/` is invisible again for the fifth time.
            if rel.startswith("..") or rel.startswith(("/dev", "/proc", "/sys", "/tmp")):
                continue
            # A TRAILING `*` IS A FAMILY, NOT A NAME. MEASURED: `gates/gatekit.py:176` is
            # `self.dir = ART / name`, so the resolvable value is `gates/artifacts/*`, and
            # `retention-check.py` enumerates CHILDREN of `gates/artifacts` -- so the population key
            # must be the FAMILY, or the one directory with 10 children is filed under a glob no
            # reader can match. `*` is kept in the sites, dropped from the key.
            if rel == "*":
                rel = ""
            elif rel.endswith("/*"):
                rel = rel[:-2]
            # A `mkdir`/`rmtree` TARGET IS A DIRECTORY; a `write_text`/`-o` target is a FILE, and a
            # file belongs to its DIRECTORY. MEASURED: keying every site on its own path filed
            # `checks/gen/probe.js` as a directory called `checks/gen/probe.js`, so `checks/gen`
            # lost one of its two writer shapes and three plants went red.
            d = rel if is_dir_target else os.path.dirname(rel)
            e = dirs.setdefault(d, {"sites": [], "files": 0})
            e["sites"].append((rel_src, line, shape))
            if not is_dir_target:
                e["files"] += 1
    return dirs


def coverage(root: Path = ROOT) -> tuple[int, int]:
    """`(source files read, source files present)` -- the scan's denominator, as two numbers so a
    SKIP can never silently narrow the population without printing that it did."""
    root = Path(root).resolve()
    all_files = [p for p in _walk_all(root) if p.suffix in SOURCE_SUFFIXES]
    read = sources(root)
    return len(read), len(all_files)


def _walk_all(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(dirnames)
        for f in sorted(filenames):
            yield Path(dirpath) / f


# ---- the git half: INDEPENDENT of every source file -------------------------------------
def git(*args: str) -> str:
    """`git` as a MEASUREMENT. A pathspec outside the repository is 0 tracked entries, not an
    error -- `retention-check.py` already established that, and the reason is in its docstring."""
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0 and "outside repository" not in r.stderr:
        raise SystemExit(f"gendirs: git {' '.join(args)} failed: {r.stderr.strip()[:200]}")
    return r.stdout


def tracked_dirs(root: Path = ROOT) -> tuple[dict[str, int], dict[str, int]]:
    """`(all, empty)`: `{dir: n index entries}` and, of those, entries whose blob is git's EMPTY
    BLOB.

    `git ls-files -s` PRINTS THE MODE IN FIELD 1 AND THE SHA IN FIELD 2. Confusing them makes an
    empty blob read as a mode, which is exactly how `checks/gen/` looked like a normal file.
    """
    out: dict[str, int] = {}
    empty: dict[str, int] = {}
    for line in git("ls-files", "-s").splitlines():
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) < 2:
            continue
        mode, sha = parts[0], parts[1]
        if mode.startswith("160000"):                      # a submodule, not a blob
            continue
        d = os.path.dirname(path)
        out[d] = out.get(d, 0) + 1
        if sha == GIT_EMPTY_BLOB:
            empty[d] = empty.get(d, 0) + 1
    return ({d: n for d, n in out.items() if d and n},
            {d: n for d, n in empty.items() if n})


def ignored(dirs) -> dict[str, bool]:
    """Which of `dirs` a `.gitignore` rule names. **WITH `--no-index`, AND THAT FLAG IS THE WHOLE
    POINT.**

    MEASURED 2026-10-06, and it is a fourth named variant of the class this file exists for.
    `git check-ignore` **WITHOUT `--no-index` reports "not ignored" for every path that is IN THE
    INDEX** -- git's own documentation says tracked files are not considered ignored by default. So:

        $ git check-ignore -v -- checks/gen/                 -> rc 1, no output
        $ git check-ignore --no-index -v -- checks/gen/      -> .gitignore:153:checks/gen/

    **A GUARD WHOSE QUERY CANNOT SEE ITS OWN SUBJECT.** The population this flag governs is
    exactly the tracked-and-should-not-be population, and the default invocation returns "fine"
    for every member of it -- the same shape as `artefacts_ok()` reporting zero on a directory
    holding nothing.
    """
    out = {}
    for d in sorted(dirs):
        r = subprocess.run(["git", "check-ignore", "--no-index", "-q", "--", str(d) + "/"],
                           cwd=ROOT, capture_output=True)
        out[d] = r.returncode == 0
    return out


# ---- the report ------------------------------------------------------------------------
def table(root: Path = ROOT) -> list[dict]:
    """THE TABLE, as rows: one per directory something writes into, with `n_tracked`,
    `n_empty_blob`, `ignored`, and `writers`. Every field is a MEASUREMENT; none is a name."""
    d = discovered(root)
    tracked, empty = tracked_dirs(root)
    ign = ignored(sorted(d))
    rows = []
    for name in sorted(d):
        rows.append({
            "dir": name,
            "writers": len(d[name]["sites"]),
            "n_tracked": tracked.get(name, 0),
            "n_empty_blob": empty.get(name, 0),
            "ignored": ign.get(name, False),
            "sites": d[name]["sites"][:4],
        })
    return rows


# ---- plants ----------------------------------------------------------------------------
# A META-INSTRUMENT IS THE ONE THING WHOSE OWN BLIND SPOT NOBODY ELSE CHECKS. `gates-pop.py`
# shipped a shell tokenizer that found 2 of 17 entry points and MISSED `checks/sb-gate.sh` -- the
# gate that proves the class exists -- while every plant printed GREEN. And its `--plant`
# CLOBBERED the live ledger while printing 5/5. So this suite asserts INERTNESS around the whole
# function.
MAIN = 'if __name__ == "__main__":\n    raise SystemExit(0)\n'
# THE `checks/gen/` WRITER SHAPES, as a FIXTURE in the bytes of `checks/abi_gate.py:40,50,605,606,
# 616`. Not retyped from memory of the live file, so a fix that changes that spelling turns a
# plant RED instead of silently agreeing with the scanner.
BEND_SHAPE = (
    "from pathlib import Path\n"
    "HERE = Path(__file__).resolve().parent\n"
    "REPO = HERE.parents[0]\n"
    "BEND = REPO / 'bin' / 'bend'\n"
    "def main():\n"
    "    gendir = HERE / 'gen'\n"
    "    gendir.mkdir(exist_ok=True)\n"
    "    subprocess.run([str(BEND), 'p.bend', '-o', str(gendir / f'probe.{ext}')])\n"
) + MAIN


def plants() -> int:
    """SEVEN plants, asserting SEVEN DIFFERENT directions. Returns rc.

    INERTNESS IS ASSERTED AROUND THE WHOLE FUNCTION, and the state fingerprinted is the LIVE
    `checks/gen/` BYTES -- not a re-run of the discovery. MEASURED, and this is the brief's
    `LEFT=NOTHING`-on-both-sides shape: the first version compared two `discovered()` runs, which
    on a tree with SIX OTHER UNITS WRITING takes 40 seconds and compares two DIFFERENT moments.
    **AN INERTNESS CHECK THAT MEASURES A MOVING TARGET MEASURES THE OTHER UNITS, NOT ITSELF.**
    """
    import hashlib
    watched = [ROOT / "checks/gen/probe.js", ROOT / "checks/gen/probe.gen.c"]

    def fingerprint():
        return [(p.name, p.stat().st_mtime_ns, hashlib.sha256(p.read_bytes()).hexdigest())
                for p in watched if p.exists()]
    before = fingerprint()
    rc = _plants()
    after = fingerprint()
    inert = before == after
    print(f"  {'PASS' if inert else 'FAIL'}  inertness: --plant left the LIVE `checks/gen/` "
          f"BYTE-IDENTICAL\n          observed: "
          f"{'unchanged' if inert else 'CHANGED -- a plant wrote the live state under test'}")
    return rc | (0 if inert else 1)


def _plant_tree(root: Path, *subdirs: str) -> None:
    (root / "pyproject.toml").write_text("[project]\n")
    for d in subdirs:
        (root / d).mkdir(parents=True, exist_ok=True)


def _plants() -> int:
    import tempfile
    rc = 0
    checks = []

    # PLANT 1 -- ***THE ONE THE BRIEF ASKS FOR: A NEW GENERATED DIRECTORY THE INSTRUMENT MUST
    # NOTICE.*** A generator nobody declared, in a home nobody listed, writing through the
    # `bend -o` shape. Asserted as an ASSERTION ABOUT A DIRECTORY THAT DID NOT EXIST, not as a
    # count: a count is what `artefacts_ok()` reported over a directory holding nothing.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td).resolve()
        _plant_tree(r, "checks")
        (r / "checks" / "brandnew.py").write_text(BEND_SHAPE)
        got = discovered(r)
        one = "checks/gen" in got and len(got) == 1
        checks.append(("1: a NEW generated directory nobody declared IS discovered, through "
                       "`bend -o` AND through `mkdir`", one, f"discovered={sorted(got)}"))

    # PLANT 2 -- ***AND ITS OPPOSITE: A DIRECTORY IT MUST ***NOT*** PICK UP.*** A source tree
    # whose only writes go into a tempfile. **A CHECK THAT CANNOT SAY NO IS A PRINTER.** And this
    # is the direction the brief's own candidate P3 ("nobody cites it") fails in: a directory
    # nothing writes into is trivially uncited, so P3 would name EVERY directory in the tree.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td).resolve()
        _plant_tree(r, "checks", "tinybendygrad")
        (r / "checks" / "reader.py").write_text(
            "import tempfile\n"
            "import pathlib\n"
            "def read(p):\n"
            "    return pathlib.Path(p).read_text()\n"
            "def stage():\n"
            "    with tempfile.TemporaryDirectory() as td:\n"
            "        d = pathlib.Path(td) / 'out'\n"
            "        d.mkdir()\n"
            "        (d / 'x.rows').write_text('a\\n')\n" + MAIN)
        got = discovered(r)
        checks.append(("2: a tree that only READS and writes into a TEMPFILE yields NO generated "
                       "directory -- the check can say NO", not got, f"discovered={sorted(got)}"))

    # PLANT 3 -- THE REAL SUBJECT, REPLAYED AT ITS OWN SHAPES. The fixture is `checks/abi_gate.py`
    # rather than retyped, so it cannot agree with the scanner by construction.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td).resolve()
        _plant_tree(r, "checks", "bin")
        (r / "checks" / "abi_gate.py").write_text(BEND_SHAPE)
        sites = discovered(r).get("checks/gen", {}).get("sites", [])
        shapes = {s[2] for s in sites}
        checks.append(("3: `checks/gen/` is found by BOTH writer shapes -- `mkdir` (the RECEIVER) "
                       "and `subprocess -o` (a COMPILER writes the file)",
                       shapes == {"mkdir", "subprocess -o"},
                       f"shapes={sorted(shapes)} sites={len(sites)}"))

    # PLANT 4 -- THE RUNTIME-PARAMETER SHAPE. `gates/gatekit.py:176` is `self.dir = ART / name`
    # where `name` is a constructor ARGUMENT. A scanner that requires a fully-known path reports
    # NOTHING for the directory that 10 gates write into, and `retention-check.py` transcribes that
    # set BY HAND for exactly this reason. The plant asserts the PREFIX survives.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td).resolve()
        _plant_tree(r, "gates")
        (r / "gates" / "gatekit.py").write_text(
            "from pathlib import Path\n"
            "HERE = Path(__file__).resolve().parent\n"
            "ART = HERE / 'artifacts'\n"
            "class Gate:\n"
            "    def __init__(self, name):\n"
            "        self.dir = ART / name\n"
            "        self.dir.mkdir(parents=True, exist_ok=True)\n" + MAIN)
        got = discovered(r)
        checks.append(("4: an output name that is a RUNTIME PARAMETER still yields its DIRECTORY "
                       "prefix -- this is what replaces a hand-transcribed list",
                       "gates/artifacts" in got, f"discovered={sorted(got)}"))

    # PLANT 5 -- THE TWO `parents[n]` SPELLINGS, WHICH DIFFER BY ONE. `checks/differ.py:41` walks
    # from the FILE; `checks/abi_gate.py:50` walks from a `HERE` that is already a directory.
    # Reading the SHAPE and not the NAME is the fix `gates-pop.py` records after mis-measuring
    # `checks/disagree-gate.py`, whose `HERE` holds a FILE.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td).resolve()
        _plant_tree(r, "checks")
        (r / "checks" / "a.py").write_text(
            "from pathlib import Path\n"
            "ROOT = Path(__file__).resolve().parents[1]\n"
            "D = ROOT / 'runs/graphcmp/D'\n"
            "D.mkdir(parents=True, exist_ok=True)\n" + MAIN)
        (r / "checks" / "b.py").write_text(
            "from pathlib import Path\n"
            "HERE = Path(__file__).resolve().parent\n"
            "REPO = HERE.parents[0]\n"
            "D = REPO / 'runs/graphcmp/D'\n"
            "D.mkdir(parents=True, exist_ok=True)\n" + MAIN)
        got = discovered(r)
        checks.append(("5: BOTH `parents[n]` spellings resolve to the SAME directory -- from a "
                       "FILE and from a DIRECTORY, which differ by one",
                       "runs/graphcmp/D" in got, f"discovered={sorted(got)}"))

    # PLANT 6 -- THE GIT HALF IS INDEPENDENT OF EVERY SOURCE FILE. A directory with an index entry
    # and NO writer is the disagreement both instruments must REPORT rather than resolve, because
    # **two instruments derived from the same table cannot audit that table.** The live scan
    # happens ONCE here and is shared: MEASURED, calling `discovered()` twice on the live tree
    # inside one plant cost 40 s and **A PLANT THAT RE-MEASURES THE LIVE TREE IS A PLANT THAT
    # MEASURES THE OTHER SIX UNITS.**
    live = set(discovered())
    with tempfile.TemporaryDirectory() as td:
        r = Path(td).resolve()
        _plant_tree(r, "checks")
        (r / "checks" / "w.py").write_text(BEND_SHAPE)
        synthetic = set(discovered(r))
        # `tracked_dirs()` RETURNS A 2-TUPLE `(all, empty)`. MEASURED: plant 6 read it as a dict
        # and died with `AttributeError` -- and it died LOUDLY, inside `--plant`, which is the right
        # way for a crash to happen. An exception inside a PLANT is a plant failing; an exception
        # inside a MEASUREMENT is a check that cannot answer, which is a REFUSAL.
        live_tracked = {d for d, n in tracked_dirs()[0].items() if n}
        unwritten = sorted(d for d in live_tracked if d not in live)
        checks.append(("6: the GIT half asks a question no source file answers -- TRACKED dirs "
                       "with no discovered writer are REPORTED, not dropped; and the synthetic tree "
                       "still yields `checks/gen`",
                       bool(unwritten) and synthetic == {"checks/gen"},
                       f"{len(live_tracked)} tracked dir(s), {len(unwritten)} with no discovered "
                       f"writer (e.g. {unwritten[:2]}); synthetic={sorted(synthetic)}"))

    # PLANT 7 -- THE EMPTY POPULATION IS REFUSED, NEVER GREEN. `gates-pop.py` plant 3 and
    # `artefacts_ok()` are the same instance: a guard that reported zero on a directory holding
    # nothing.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td).resolve()
        _plant_tree(r, "checks")
        (r / "checks" / "nothing.py").write_text("X = 1\n")      # a source file, and no writes
        got = discovered(r)
        read, present = coverage(r)
        checks.append(("7: an EMPTY discovery is reported as EMPTY WITH ITS DENOMINATOR -- a tree "
                       "with a source file and no writes must not read as healthy",
                       got == {} and present > 0 and read == present,
                       f"discovered={got} read={read} present={present}"))

    print("PLANTS -- seven directions, because a meta-instrument's blind spot is the one nobody "
          "else\nchecks, and two of them assert OPPOSITE directions (notice / do-not-pick-up)")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="gates/gendirs.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="DENOMINATOR: the number of source files the scan READ and the number PRESENT, "
               "and the number of write sites resolved. A population with no denominator is a "
               "claim nobody can check.")
    ap.add_argument("--json", action="store_true", help="emit the rows as JSON")
    ap.add_argument("--dirs-only", action="store_true", help="one directory per line")
    ap.add_argument("--plant", action="store_true",
                    help="assert the seven plants on synthetic trees; never touches the live one")
    a = ap.parse_args()
    if a.plant:
        return plants()
    rows = table()
    read, present = coverage()
    if a.json:
        print(json.dumps({"read": read, "present": present, "rows": rows}, indent=1))
        return 0
    sites = sum(r["writers"] for r in rows)
    print(f"SCAN COVERAGE: {read} of {present} source files read "
          f"(SKIP_TOP={','.join(SKIP_TOP)}) -- the remainder are NOT in the population")
    print(f"WRITE SITES RESOLVED: {sites}   DIRECTORIES: {len(rows)}   "
          f"LOWER BOUND: a subprocess write is invisible to a scanner that does not execute it\n")
    if a.dirs_only:
        for r in rows:
            print(r["dir"])
        return 0
    hdr = f"{'directory':52} {'sites':>5} {'trk':>5} {'empty':>5}  {'ign':4}  writer"
    print(hdr)
    print("-" * len(hdr))
    elided = 0
    for r in rows:
        if r["dir"].startswith(".agents/slop") and r["n_tracked"] == 0 and r["ignored"]:
            elided += 1
            continue
        w = r["sites"][0][0] if r["sites"] else "-"
        print(f"{r['dir']:52} {r['writers']:5} {r['n_tracked']:5} {r['n_empty_blob']:5}  "
              f"{'yes' if r['ignored'] else 'NO':4}  {w}")
    if elided:
        print(f"\n  ({elided} `.agents/slop/**` scratch dir(s) elided: untracked AND ignored. "
              f"They are in\n   the scan and in the count, not in this listing.)")
    contradiction = [r for r in rows if r["n_tracked"] and r["ignored"]]
    print(f"\nTHE ROW THAT SAYS \"CONTRADICTION\": {len(contradiction)} director"
          f"{'y' if len(contradiction) == 1 else 'ies'} in the index AND `.gitignore`d"
          + (f" -- {', '.join(r['dir'] for r in contradiction[:6])}" if contradiction else ""))
    print("`checks/gen/` was one: 2 index entries, BOTH git's EMPTY BLOB, written by "
          "`checks/abi_gate.py:616`\nthrough `bend -o`, with 9 of the 9 citations in "
          "`checks/abi.json` resolving into it. It is now\nuntracked and ignored. See "
          "`.agents/slop/gendirs/TABLE.md`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())