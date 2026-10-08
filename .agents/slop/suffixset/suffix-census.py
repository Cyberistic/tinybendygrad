#!/usr/bin/env python3
"""Census of the SUFFIX-SET-AS-POPULATION class, and of `gates/gates-pop.py:141 SUFFIXES`.

THREE QUESTIONS, THREE DENOMINATORS, AND NO ANSWER WITHOUT ONE.

  A  DIVERGENCE. `gates-pop.discover()` enumerates `HOMES` with `iterdir()` and drops every
     file whose suffix is not in a declared 2-item tuple. A DIRECTORY WALK sees the same
     directory. The two disagree, and the census prints the disagreement in BOTH directions:
     what the tuple admits that nothing matches, and what the walk holds that the tuple drops.

  B  THE CLASSIFIER IS A SECOND INSTANCE, ONE LAYER DOWN. Dropping is not the whole defect.
     `gates-pop.entry_reason()` routes `p.suffix == ".py"` to the AST and EVERY OTHER suffix
     to the SHELL tokenizer, so a file the walk admits is still classified as shell. Removing
     `SUFFIXES` alone would make the count move and leave the instrument wrong -- the same
     "extinction of subject" shape `artefacts_ok()` had. Measured, both, by running the real
     functions rather than reasoning about them.

  C  THE SIBLING CLASS, ACROSS THE WHOLE TREE, CLASSIFIED BY **ROLE** AND NOT BY SHAPE.
     Every module-level constant in every tracked `.py` that is a collection of string
     literals gets its USE SITES read off the AST, and the role is the CALL it is passed to:
     a set handed to `endswith`/`rglob`/`glob`/`iterdir`/`in` is STANDING IN FOR WHAT EXISTS
     (the defect); a set used as a dict key, a label, or an expected-output NAME is NAMING
     WHAT A THING IS CALLED (a declaration, and fine). **A SHAPE ALONE CANNOT TELL THE TWO
     APART** -- `__all__` in upstream `tinygrad`, `LITERALS` in `checks/differ.py` and
     `EXTS` in a slop tool all have the same word-shape and opposite roles, which is why the
     first version of this census reported 175 candidates and no verdicts.

THE CENSUS'S OWN BLIND SPOT, STATED BEFORE ITS OUTPUT BECAUSE IT IS THE SAME CLASS.
**This census is a PYTHON AST census.** It can only see a suffix set written as a Python
constant, so a suffix set spelled in `.sh`, in a `--include=` glob, or inside a regex is
INVISIBLE TO IT -- which is the failure being hunted, reproduced in the instrument hunting
it. So section D measures that second population with the one tool that CAN see it (text
over tracked shell files) and prints both denominators. **AN INSTRUMENT THAT CANNOT SEE ITS
POPULATION CANNOT BE WRONG, BECAUSE IT CANNOT BE ANYTHING.**

USAGE: .venv/bin/python .agents/slop/suffixset/suffix-census.py
"""
import argparse
import ast
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# A CALL THAT MAKES A SET DECIDE WHAT EXISTS. This list is a CLASSIFIER, not a population: a
# member of it that is never reached changes no verdict, and the count of reached members is
# printed with the verdicts so a reader can see how much of the class this census can see.
DISCOVERY_CALLS = frozenset({
    "endswith", "startswith", "rglob", "glob", "iglob", "iterdir", "listdir", "walk",
    "fnmatch", "match", "search", "subprocess", "run", "Popen", "copytree", "copy2",
})


def load_gates_pop():
    """The SUBJECT, loaded BY PATH. `gates/` is not a package and `sys.path` must be set up
    before exec, because `gates-pop.py` does its own `sys.path.insert` at import."""
    import importlib.util
    p = ROOT / "gates" / "gates-pop.py"
    sys.path.insert(0, str(p.parent))
    spec = importlib.util.spec_from_file_location("gatespop_subject", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def suffix_of(p):
    """A file's suffix, or `(none)`. **HAND-WRITTEN, AND NOT `Path.suffix`.** MEASURED: on this
    tree `Path('.err').suffix` is `''` -- a LEADING DOT STARTS NO SUFFIX -- so `Path.suffix`
    buckets `checks/.err` and `checks/.out` in with `checks/bend`, one extensionless EXECUTABLE
    SHELL SHIM and two dotfiles of build output. The first census read 3 files in its `(none)`
    bucket and 1 of them tracked, and would have reported "1 tracked no-extension file" as if the
    extensionless case were the whole of it. **A COMPARISON THAT CANNOT SUCCEED LOOKS EXACTLY
    LIKE A COMPARISON THAT FOUND NOTHING**, and so does a suffix function that returns one
    answer for three different questions."""
    n = p.name
    i = n.rfind(".")
    return n[i:] if i > 0 else "(none)"


def walk_regular(d):
    """Every REGULAR file directly under `d`, symlinks refused. `os.lstat` because both
    `Path.is_file()` and `Path.exists()` FOLLOW SYMLINKS, and `gates-pop.py:330-338` measures
    exactly that hazard. Byte-for-byte the subject's own predicate, so the two populations
    differ ONLY by the suffix filter -- which is the whole point of question A."""
    if not os.path.isdir(d):
        return []
    return [p for p in sorted(d.iterdir()) if stat.S_ISREG(os.lstat(p).st_mode)]


def tracked_set():
    """Tracked paths from `git ls-tree -r HEAD`, NOT `git ls-files`. MEASURED TWICE IN THIS
    SESSION, AND THE TWO READINGS DIFFER, which is the finding: at 1st reading `ls-files` held
    7095 against a tree of 6680, and at 2nd reading -- four commands later, no edit by me --
    both read 6680. **A SINGLE READING OF A TREE UNDER CONCURRENT AGENTS IS NOT A PROPERTY.**
    The index is armed and disarmed while this census runs, so the index count is reported as
    an observation with no verdict attached, and every other number here comes from `ls-tree`
    or from the filesystem, which do not move."""
    r = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                       capture_output=True, text=True, check=True)
    tree = set(r.stdout.splitlines())
    idx = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True,
                         check=True).stdout.splitlines()
    return tree, len(idx)


# ---- AST: the constants, and what they are USED FOR ----------------------------------------
def collections_and_roles(path):
    """`({name: values}, {name: role})` for one module, by AST.

    ROLE is read from the CALL each use site passes the constant to, or from a `Compare` that
    tests membership with `in`. A name never used as a call argument and never tested with `in`
    is NAMING (or dead), because those are the two positions that decide membership.
    """
    tree = ast.parse(path.read_text())
    consts, roles = {}, {}
    for node in tree.body:
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        val = node.value
        tgt = node.targets[0] if isinstance(node, ast.Assign) else node.target
        if val is None or not isinstance(tgt, ast.Name):
            continue
        try:
            v = ast.literal_eval(val)
        except (ValueError, SyntaxError, TypeError):
            continue
        if isinstance(v, (tuple, list, set, frozenset)) and v and all(isinstance(x, str) for x in v):
            consts[tgt.id] = tuple(sorted(v))

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            fn = ast.unparse(node.func).rsplit(".", 1)[-1]
            for a in list(node.args) + [k.value for k in node.keywords]:
                for nm in _names(a):
                    if nm in consts:
                        roles[nm] = "STANDING-IN" if fn in DISCOVERY_CALLS else roles.get(nm, "NAMING")
        elif isinstance(node, ast.Compare):
            ops = [type(o).__name__ for o in node.ops]
            for side in (node.left, node.comparators):
                for nm in _names(side):
                    if nm in consts and "In" in " ".join(ops) or (
                            nm in consts and "In" in " ".join(ops)):
                        roles[nm] = "STANDING-IN"
    return consts, roles


def _names(node):
    if isinstance(node, ast.Name):
        return [node.id]
    if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
        return [n for e in node.elts for n in _names(e)]
    if isinstance(node, ast.Starred):
        return _names(node.value)
    return []


def looks_like_extension_set(values):
    """Does the SHAPE look like a set of file extensions or a basename word-shape? A SHAPE
    FILTER ONLY -- it decides what this census READS, never what this census CONCLUDES. The
    verdict is the role."""
    if all(v.startswith(".") and "/" not in v and len(v) <= 8 for v in values):
        return "suffix-set"
    if all(("*" in v or "?" in v or v.endswith((".sh", ".py", ".js", ".mjs", ".ts")))
           for v in values):
        return "glob-set"
    return "word-shape"


def historical_suffixes():
    """`SUFFIXES` AS IT WAS, read out of `git show HEAD:gates/gates-pop.py` BY PATH and parsed
    with `ast`. **NOT TRANSCRIBED AND NOT READ OFF THE LIVE SUBJECT**, for two reasons: a
    transcription is a second copy of the very population this census measures, and the live
    subject no longer HAS the constant -- the fix removed it, so a census that read the running
    module would now report a divergence of zero and call the defect repaired when it is only
    unmeasured. `git show` is a generator's own declaration, read at the revision that held it.
    """
    r = subprocess.run(["git", "show", "HEAD:gates/gates-pop.py"], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, "git show failed"
    for node in ast.parse(r.stdout).body:
        if isinstance(node, ast.Assign) and all(
                isinstance(t, ast.Name) and t.id == "SUFFIXES" for t in node.targets):
            return tuple(ast.literal_eval(node.value)), "git show HEAD:gates/gates-pop.py"
    return None, "SUFFIXES is not in HEAD either"


# ---- A / B / C / D ---------------------------------------------------------------------------
def question_a(gp, tree, suffixes):
    rows = []
    for home in gp.HOMES:
        by = {}
        for p in walk_regular(ROOT / home):
            by.setdefault(suffix_of(p), []).append(p)
        for suf in sorted(set(by) | set(suffixes)):
            files = by.get(suf, [])
            rows.append((home, suf, len(files),
                         "IN-SUFFIXES" if suf in suffixes else "DROPPED",
                         sum(1 for f in files if str(f.relative_to(ROOT)) in tree)))
    return rows


def question_b(gp, suffixes):
    dropped = [p for home in gp.HOMES for p in walk_regular(ROOT / home)
               if suffix_of(p) not in suffixes]
    rows = [(str(p.relative_to(ROOT)), gp.entry_reason(p), suffix_of(p))
            for p in dropped]
    return rows, dropped


def question_c(tree):
    py = sorted(p for p in tree if p.endswith(".py"))
    rows, unreadable = [], 0
    for rel in py:
        p = ROOT / rel
        if not p.is_file():
            unreadable += 1
            continue
        try:
            consts, roles = collections_and_roles(p)
        except SyntaxError:
            unreadable += 1
            continue
        for name, values in consts.items():
            shape = looks_like_extension_set(values)
            if shape == "suffix-set" or roles.get(name) == "STANDING-IN":
                rows.append((rel, name, shape, roles.get(name, "UNUSED"), len(values),
                             ",".join(values[:5])))
    return rows, len(py), unreadable


GLOB_LINE = re.compile(r"\*\.[a-z]{1,5}")


def question_e(tree):
    """THE INLINE LITERALS, and this section exists because the constant-only census MISSED the
    two files the brief named. `gates/gate-surface.py:299` is `fn.endswith((".py", ".sh"))`
    written INSIDE a comprehension and `checks/differ.py:1062` is `D.glob("*.txt")` -- neither
    is a module-level constant, so a census that reads constants reports nothing about either,
    **WHICH IS THE SAME BLINDNESS ONE LEVEL DOWN THAT `checks/sweep.py`'s extension-gated rule
    had.** An inline literal is the most anonymous form of a suffix set: it has no name to grep
    for and no line to pin, so it is read off the AST at the CALL SITE instead.
    """
    rows = []
    for rel in sorted(p for p in tree if p.endswith(".py")):
        p = ROOT / rel
        if not p.is_file():
            continue
        try:
            tree_ = ast.parse(p.read_text())
        except SyntaxError:
            continue
        for node in ast.walk(tree_):
            if not isinstance(node, ast.Call):
                continue
            fn = ast.unparse(node.func).rsplit(".", 1)[-1]
            if fn in ("endswith", "startswith"):
                for a in node.args:
                    try:
                        v = ast.literal_eval(a)
                    except (ValueError, SyntaxError, TypeError):
                        continue
                    if isinstance(v, (tuple, list, set)) and v and all(isinstance(x, str) for x in v):
                        if sum(1 for x in v if x.startswith(".")) >= 2:
                            rows.append((rel, str(node.lineno), f"{fn}({','.join(sorted(v))})"))
            elif fn in ("glob", "rglob", "iglob"):
                for a in node.args:
                    try:
                        v = ast.literal_eval(a)
                    except (ValueError, SyntaxError, TypeError):
                        continue
                    if isinstance(v, str) and v.startswith("*"):
                        rows.append((rel, str(node.lineno), f"{fn}({v!r})"))
    return rows


def question_d(tree):
    """The population the Python AST census is BLIND TO: an extension shape inside a shell
    file, where `--include='*.py'` is a population with no AST behind it."""
    rows = []
    for rel in sorted(p for p in tree if p.endswith((".sh", ".bash", ".zsh"))):
        p = ROOT / rel
        if not p.is_file():
            continue
        for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
            s = line.strip()
            if s.startswith("#") or not GLOB_LINE.search(s):
                continue
            if re.search(r"(?:--include|--exclude|-name|\bcase\b|\bfor\b|\bfind\b)", s):
                rows.append((rel, str(i), s[:96]))
    return rows


def main():
    ap = argparse.ArgumentParser(prog="suffix-census.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent))
    a = ap.parse_args()
    out = Path(a.out)
    gp = load_gates_pop()
    tree, n_idx = tracked_set()
    suffixes, src = historical_suffixes()
    print(f"THE DECLARATION UNDER TEST, read by path from `{src}`: {suffixes}")
    print(f"   and read off the LIVE subject: "
          f"{'STILL PRESENT' if hasattr(gp, 'SUFFIXES') else 'ABSENT -- the fix removed it'}")
    print(f"   The live walk is what `discover()` now enumerates; the historical tuple is what it")
    print(f"   used to filter. Comparing the two over the SAME directory is the whole census.\n")

    print(f"DENOMINATOR 0  tracked blobs in HEAD, read by `git ls-tree -r HEAD`: {len(tree)}")
    print(f"DENOMINATOR 0' `git ls-files` (the INDEX) read {n_idx} at the same instant. This is an")
    print(f"   OBSERVATION and carries no verdict: MEASURED TWICE IN THIS SESSION, the index read")
    print(f"   7095 on the first reading and {n_idx} on the second, four commands apart, no edit by")
    print(f"   this unit. Every number below comes from ls-tree or the filesystem.\n")

    # A ----
    rows_a = question_a(gp, tree, suffixes)
    with (out / "divergence.rows").open("w") as fh:
        fh.write("home\tsuffix\tn_files\tsuffix_set_says\ttracked\n")
        for r in rows_a:
            fh.write("\t".join(map(str, r)) + "\n")
    tot_disk = sum(r[2] for r in rows_a)
    tot_decl = sum(r[2] for r in rows_a if r[3] == "IN-SUFFIXES")
    print(f"A  DIVERGENCE, per home, directory walk of every REGULAR file at depth 1 of "
          f"{'/'.join(gp.HOMES)}/:")
    for home in gp.HOMES:
        hr = [r for r in rows_a if r[0] == home]
        print(f"     {home + '/':8} walk sees {sum(r[2] for r in hr):4} file(s); the tuple admits "
              f"{sum(r[2] for r in hr if r[3] == 'IN-SUFFIXES'):4}; "
              f"{sum(r[2] for r in hr if r[3] == 'DROPPED'):4} DROPPED unread")
        for suf in suffixes:
            n = next((r[2] for r in hr if r[1] == suf), 0)
            if n == 0:
                print(f"       declared-but-ABSENT in {home}/: {suf} -- a tuple member that matches")
                print(f"       nothing here, so it can never be wrong about this home")
    print(f"   TOTAL across both homes: walk {tot_disk}, tuple admits {tot_decl}, "
          f"DROPPED {tot_disk - tot_decl}")
    print(f"   dropped-by-extension, WITH THE HOME ON EVERY ROW (scope and number in one line):")
    for r in sorted([r for r in rows_a if r[3] == "DROPPED" and r[2]], key=lambda x: (x[0], -x[2])):
        print(f"     {r[0] + '/*' + r[1].lstrip('.'):16} {r[2]:4} file(s)  {r[4]:4} tracked  {r[3]}")
    print("   wrote divergence.rows\n")

    # B ----
    rows_b, dropped = question_b(gp, suffixes)
    with (out / "classifier.rows").open("w") as fh:
        fh.write("dropped_file\tsuffix\tentry_reason_says\n")
        for r in rows_b:
            fh.write("\t".join(str(x) for x in r) + "\n")
    print(f"B  THE CLASSIFIER, one layer down. `entry_reason` reads `.py` with the AST and routes")
    print(f"   EVERY other suffix to the SHELL tokenizer, so admitting a file is not the same as")
    print(f"   understanding it. Denominator: {len(dropped)} file(s) the walk holds and the tuple")
    print(f"   drops. The ones whose CONTENT is a program in some language:")
    codeish = [r for r in rows_b if r[2] in ("(none)", ".mjs", ".js", ".ts", ".bend")]
    for r in codeish:
        print(f"     {r[0]:30} suffix={r[2]:7} -> entry_reason says {r[1]!r}")
    print(f"   `.mjs` in a gate home: {sum(1 for r in rows_b if r[2] == '.mjs')}; "
          f"NO-SUFFIX: {sum(1 for r in rows_b if r[2] == '(none)')}")
    print("   wrote classifier.rows\n")

    # C ----
    rows_c, n_py, unreadable = question_c(tree)
    with (out / "sibling.rows").open("w") as fh:
        fh.write("file\tname\tshape\trole\tn\tfirst_members\n")
        for r in rows_c:
            fh.write("\t".join(map(str, r)) + "\n")
    stand = [r for r in rows_c if r[3] == "STANDING-IN"]
    print(f"C  SIBLING CLASS, by AST over {n_py} tracked `.py` file(s) ({unreadable} unreadable on")
    print(f"   disk). {len(rows_c)} constant(s) are CANDIDATES (a suffix-set shape, or any shape")
    print(f"   handed to a discovery call). Of those, {len(stand)} are STANDING-IN -- the defect.")
    print(f"   THE STANDING-IN POPULATION, the class this unit was asked to census:")
    for r in sorted(stand, key=lambda x: (x[0], x[1])):
        print(f"     {r[0]:30} {r[1]:20} {r[2]:11} n={r[4]:<3} {r[5]}")
    print(f"   wrote sibling.rows\n")

    # D ----
    rows_d = question_d(tree)
    print(f"D  THE POPULATION THIS CENSUS IS BLIND TO BY CONSTRUCTION: an extension shape spelled")
    print(f"   in a shell file, over {sum(1 for p in tree if p.endswith(('.sh','.bash','.zsh')))} "
          f"tracked shell file(s). {len(rows_d)} line(s) name one:")
    for r in rows_d[:14]:
        print(f"     {r[0]}:{r[1]}  {r[2]}")
    if len(rows_d) > 14:
        print(f"     ... and {len(rows_d) - 14} more")

    rows_e = question_e(tree)
    with (out / "inline.rows").open("w") as fh:
        fh.write("file\tline\tinline_suffix_shape\n")
        for r in rows_e:
            fh.write("\t".join(r) + "\n")
    print(f"\nE  THE INLINE LITERALS section C's constant-only read CANNOT SEE -- and it is why")
    print(f"   section C reported nothing about the two files the brief named. {len(rows_e)} call")
    print(f"   site(s) pass an extension shape that was never a named constant:")
    for r in rows_e:
        print(f"     {r[0]}:{r[1]:<6} {r[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())