#!/usr/bin/env python3
"""DIARY CENSUS -- which generated directories have READERS but no AUTHOR, and which of the
tree's cache directories are that.  Both populations by DISCOVERY; every count carries a
denominator and a timestamp.

    usage: .venv/bin/python checks/diary-census.py
           .venv/bin/python checks/diary-census.py --json
           .venv/bin/python checks/diary-census.py --readers-of runs/graphcmp/D
           .venv/bin/python checks/diary-census.py --plant

EXIT: 0 every named directory HAS an author  ·  1 one has readers and no author  ·
3 REFUSED, not a verdict, the scan could not read its own population.

WHAT A DIARY IS, AND WHY IT IS A FOURTH KIND OF POPULATION.  Doctrine 1 gives three: a
generator's own declaration loaded by path, a directory walk, and a regex over write sites.
`checks/census.py` added the cache, and a CACHE IS WHAT THE LAST RUN WROTE.  A cache without
a generator beside it is a diary: it has readers and no author.

THE MEASUREMENT, IN THREE PARTS, EACH WITH ITS OWN POPULATION:
  AUTHOR    a WRITE SITE, discovered.  Reuses `gates/gendirs.py`'s own constant-propagation
            scanner, IMPORTED BY PATH and not re-implemented, because a second scanner is a
            second opinion and the tree has already had one figure rot through nine forms.
  READER    a path literal or a REBINDING, discovered by AST.  Two shapes, and the second is
            the one that is easy to miss: `checks/differ.py` READS `runs/graphcmp/D` through a
            module global `D` that other modules OVERWRITE (`gates/retention-check.py:340`
            does `differ.D = ...`), so a scan that reads only path literals misses every
            reader that goes through the author's own global.  MEASURED both ways; the delta
            is printed.
  TRACKED   `git ls-tree -r HEAD`, never `git ls-files`, which reads the INDEX.

WHAT THIS IS NOT.  It is not a list of directories somebody decided are diaries.  If a
directory is added, it appears without anyone editing this file -- which is the only property
that keeps the class closed, and the reason `gates/gendirs.py` exists at all.

THE ADMITTED LIMIT, MEASURED NOT ASSUMED.  A static scan is a LOWER BOUND.  `gendirs.py`
measures and prints its own coverage (`sources read` / `sources present`) and this file prints
it too rather than reporting a narrowed population as the whole one.  A subprocess write is
invisible to a scanner that does not execute it; so is a path built from a value that never
appears as a literal.  Both are named where they happen rather than absorbed here.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

#: The write-site scanner, LOADED BY PATH.  A `gendirs` name that resolves only when
#: `gates/` happens to be `sys.path[0]` is a population chosen by a bindable name, which is
#: `gates/gates-pop.py:99-101`'s own complaint about itself.
GENDIRS = "gates/gendirs.py"


def gendirs():
    spec = importlib.util.spec_from_file_location("diary_census_gendirs", ROOT / GENDIRS)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


import importlib.util  # noqa: E402  -- used by `gendirs()`; placed after ROOT for clarity


# ---- READERS: discovered by AST, two shapes ---------------------------------------------------
#: A read is a call whose FUNCTION is in here, or whose RECEIVER is the directory under study.
#: `write_text`/`mkdir` are excluded on purpose: they are authors, and mixing the two
#: populations is how a census reports "read but never written" about a directory it is itself
#: writing into.
READ_CALLS = frozenset({
    "read_text", "read_bytes", "open", "glob", "rglob", "iterdir", "listdir", "walk",
    "scandir", "exists", "is_file", "is_dir", "stat", "lstat", "readlink",
})
#: A rebinding of ANOTHER module's attribute: `differ.D = Path(...)`.  These are the readers
#: that a path-literal scan cannot see, and they are counted separately.
REBIND_TARGETS = frozenset({"D", "ROOT", "HERE", "TREE", "DIR"})

#: A path literal that NAMES the directory under study.  A BASENAME IS NOT A PATH: `D0-run-summary.txt`
#: alone does not place a file in `runs/graphcmp/D`, and a scan that matched it would report
#: every reader of a file that never existed.
#: THE DIRECTORY GLOBALS a reader can REBIND.  Named, not derived, because the signal is the
#: ATTRIBUTE and not the value: `gates/retention-check.py:340` is `differ.D = Path(graphcmp_dir)`
#: -- a runtime parameter no amount of constant propagation reaches -- and the fact that it
#: POINTS THE AUTHOR AT A DIFFERENT DIRECTORY is the whole of why it reads.
REBIND_ATTRS = frozenset({"D"})

#: Calls that LOAD another module by path.  A reader that does this and then calls the loaded
#: module's functions reads the subject through the AUTHOR'S OWN CLOSURES, and carries no path
#: literal at all: `checks/corpus-figure.py` reads `runs/graphcmp/D` only because it loads
#: `checks/differ.py` and calls `unhealthy()`.  **A SCAN THAT SEES ONLY LITERALS REPORTS THE
#: TREE'S MOST IMPORTANT READER AS ABSENT, WHICH IS A CLEAN NUMBER FROM A HALF-POPULATION.**
LOAD_CALLS = frozenset({"spec_from_file_location", "SourceFileLoader"})


def _literal_paths(node):
    """Every string-constant literal containing a `/`.  A citation is a LOWER BOUND and the
    caller labels it one; it is never counted as a read."""
    return [s.value for s in ast.walk(node)
            if isinstance(s, ast.Constant) and isinstance(s.value, str) and "/" in s.value]


def _author_stems(rel_dir: str, root: Path) -> set[str]:
    """The MODULE STEMS of every file that writes into `rel_dir`, DISCOVERED by write site.

    This is what makes the two-hop read shapes decidable: such a reader names the AUTHOR, not
    the directory.  `checks/differ.py` authors `runs/graphcmp/D`, so both `differ.D = ...` and
    `spec_from_file_location(..., "checks/differ.py")` are reads of that directory, and NEITHER
    contains the string `runs/graphcmp/D`."""
    gd = gendirs()
    if gd is None:
        return set()
    want = rel_dir.rstrip("/")
    out = set()
    for src in gd.sources(root):
        found, _un = gd._write_sites(src)
        for target, _line, _shape in found:
            if not target:
                continue
            absolute = (target if os.path.isabs(target)
                        else os.path.normpath(str(src.parent / target)))
            rel = os.path.relpath(absolute, root).rstrip("/")
            if rel == want or rel.startswith(want + "/"):
                out.add(src.stem)
                break
    return out


def readers_of(rel_dir: str, root: Path = ROOT) -> dict:
    """Every source file that reads `rel_dir`, by AST, with the shape each read took.

    FOUR shapes, and each is counted before it is believed:

      literal   a string literal naming the directory or something under it.  A CITATION is a
                lower bound -- prose in a docstring names a directory without reading it -- so
                these are labelled and counted apart from the other three.
      call      a read call whose RESOLVED argument lives under the directory
      rebind    `differ.D = ...`: the author module's directory global pointed elsewhere
      load      the author module loaded by path, after which its functions read the
                directory through their own closures.  The tree's most important reader of
                `runs/graphcmp/D` is this shape and carries no path literal at all.

    **`root` IS A PARAMETER, AND THE PLANT IS WHY.**  MEASURED while writing the plant: with
    the root pinned to the module global, `--plant` cases 3 and 4 silently measured the LIVE
    TREE and reported 73 reader files for a four-line synthetic fixture -- **a plant that
    measures the tree it is not testing is a plant that cannot fail.**  The same shape as
    `gendirs.discovered(root)`, whose own docstring records `root` being resolved because a
    synthetic tree compared against an unresolved live one discovered nothing.
    """
    root = Path(root).resolve()
    want = rel_dir.rstrip("/")
    found: dict[str, list[tuple[str, int, str]]] = {}
    gd = gendirs()
    if gd is None:
        return found
    authors = _author_stems(want, root)
    for src in gd.sources(root):
        try:
            tree = ast.parse(src.read_text(errors="replace"))
        except (SyntaxError, OSError):
            continue
        rel_src = os.path.relpath(src, root)
        env = {"__file__": str(src.resolve())}
        for _ in range(8):
            before = len(env)
            gd._bind(tree, env)
            if len(env) == before:
                break
        hits: list[tuple[str, int, str]] = []
        # SHAPE `anchor` -- A NAMED HANDLE ON THE DIRECTORY.  A module-level binding whose
        # resolved value IS the directory, or a file inside it, is a reader: the file has
        # committed to that path and every use of the name goes there.  MEASURED: this is the
        # shape BOTH `checks/disagree-gate.py` (`:53 D = ROOT / "runs" / "graphcmp" / "D"`)
        # and `checks/substrate-id.py` (`:88 SUMMARY = ROOT / "runs/graphcmp/D/D0-run-summary.txt"`)
        # use, and a scan that looks only at READ CALLS finds NEITHER -- because the read
        # happens through the NAME (`(tree / "D0-run-summary.txt").read_text()`, where `tree`
        # is a function parameter).  **A READER THAT NAMES THE DIRECTORY AND THEN PASSES IT AS
        # AN ARGUMENT IS INVISIBLE TO A SCAN THAT ONLY INSPECTS CALL ARGUMENTS.**  Asking the
        # fixpoint what every name in the module resolved to costs nothing extra -- the
        # environment is already built for the `call` shape below.
        for name, val in sorted(env.items()):
            if name == "__file__" or not isinstance(val, str) or not val.startswith("/"):
                continue
            try:
                r = pathlib.Path(val).resolve().relative_to(root)
            except (ValueError, OSError):
                continue
            r = r.as_posix().rstrip("/")
            if r == want or r.startswith(want + "/"):
                kind = "dir" if r == want else "file"
                line = next((n.lineno for n in ast.walk(tree)
                             if isinstance(n, ast.Assign)
                             and any(isinstance(t, ast.Name) and t.id == name
                                     for t in n.targets)), 0)
                hits.append((rel_src, line, f"anchor ({name} -> {r}, a {kind})"))
        for node in ast.walk(tree):
            # SHAPE `rebind` -- the author's directory global pointed at another tree.  The
            # VALUE is a runtime parameter in the live tree, so the ATTRIBUTE is the signal.
            if isinstance(node, ast.Assign):
                for t in node.targets:
                    if isinstance(t, ast.Attribute) and t.attr in REBIND_ATTRS \
                            and isinstance(t.value, ast.Name) and t.value.id in authors:
                        v = gd.expr(node.value, env) or gd.prefix(node.value, env) or "?"
                        hits.append((rel_src, node.lineno,
                                     f"rebind ({t.value.id}.{t.attr}={v})"))
            if not isinstance(node, ast.Call):
                continue
            f = node.func
            nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
            # SHAPE `load` -- the author module, by path.  Everything it closes over.
            #
            # **THE PATH IS AN ARGUMENT, NOT ANY ARGUMENT, AND THAT IS A MEASURED BUG IN THIS
            # FILE.**  `spec_from_file_location(name, location)` takes the module's NAME first,
            # and the first version of this loop read EVERY argument -- so it matched on the
            # name.  MEASURED: it reported `checks/oracle-txt-census.py:215 load (... plant)`
            # and `checks/slop-declare.py:130 load (... plant.py)` as readers of
            # `runs/graphcmp/D`, because two `.agents/slop/` scripts named `plant.py` DO have
            # write sites there and share a STEM with nothing.  **A STEM IS NOT A PATH**, which
            # is the same rule as "a basename is not a path" and the same class of error: the
            # before-value was 21 reader files / 35 sites, and 3 of those files were fiction.
            # The location is the LAST argument for both call shapes, and it is resolved
            # against the tree before it is compared -- so a bare `differ` is resolved by
            # finding `differ.py` in this tree rather than by matching four characters.
            if nm in LOAD_CALLS and len(node.args) >= 2:
                a = node.args[-1]
                lit = a.value if isinstance(a, ast.Constant) and isinstance(a.value, str) else None
                # **AND THE PATH IS USUALLY NOT A LITERAL.**  MEASURED: fixing the
                # module-name bug by demanding a `Constant` dropped the count from 21 files to
                # 5 and lost `checks/corpus-figure.py`, `checks/sweep.py` and the rest -- because
                # the real shape is `spec_from_file_location("differ_pins", ROOT / "checks/differ.py")`,
                # a BINOP.  Both bugs are the same one, seen from two sides: a static scan that
                # cannot resolve an expression reports NOTHING, and a reader nobody counted is
                # indistinguishable from a reader that does not exist.  So the constant-propagation
                # fixpoint is asked, exactly as the `call` shape below asks it.
                if lit is None:
                    lit = gd.expr(a, env)
                if lit is not None and "/" not in lit:      # a bare module name
                    cand = root / f"{lit}.py"
                    lit = str(cand.relative_to(root)) if cand.is_file() else None
                elif lit is not None:
                    cand = Path(lit)
                    cand = cand if cand.is_absolute() else (root / cand)
                    try:
                        cand = cand.resolve()
                    except OSError:
                        cand = None
                    lit = (str(cand.relative_to(root))
                           if cand is not None and cand.is_file()
                           and cand.is_relative_to(root) else None)
                if lit and Path(lit).stem in authors:
                    hits.append((rel_src, node.lineno, f"load ({nm} {lit})"))
            # SHAPE `call` -- a read call whose RESOLVED argument is under the directory.
            if nm in READ_CALLS and node.args:
                a = gd.expr(node.args[0], env) or gd.prefix(node.args[0], env)
                if a and want in a:
                    hits.append((rel_src, node.lineno, f"{nm}({a})"))
        # SHAPE `literal` -- INCLUDING docstrings.  Prose that names the directory is a
        # CITATION, a lower bound, never a read: `checks/README.md` naming the run directory
        # is not an instrument reading it.  Labelled `line 0` and counted apart by the caller.
        for lit in _literal_paths(tree):
            if want in lit:
                hits.append((rel_src, 0, f"CITATION {lit!r}"))
        if hits:
            found[rel_src] = hits
    return found


# ---- TRACKED: the git half, independent of every source file --------------------------------
def tracked_has(rel: str) -> tuple[int, int]:
    """`(entries under rel in the COMMITTED tree, entries that are git's EMPTY BLOB)`."""
    empty = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
    r = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--", rel],
                       cwd=ROOT, capture_output=True, text=True)
    n = e = 0
    for line in r.stdout.splitlines():
        meta, _, _path = line.partition("\t")
        parts = meta.split()
        if len(parts) >= 3 and parts[1] == "blob":
            n += 1
            e += parts[2] == empty
    return n, e


def ignored(rel: str) -> tuple[bool, str]:
    """`(ignored, the rule)`, asked with `--no-index` -- see `gendirs.ignored()` for why."""
    r = subprocess.run(["git", "check-ignore", "--no-index", "-v", "--", rel],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        return False, ""
    return True, r.stdout.split(":", 2)[1].strip() if ":" in r.stdout else r.stdout.strip()


# ---- the class census ------------------------------------------------------------------------
def census() -> dict:
    gd = gendirs()
    if gd is None:
        return {"error": "GENDIRS ABSENT"}
    authors = gd.discovered()                      # {dir: {"sites": [...]}}
    read, present = gd.coverage()
    rows = []
    for d in sorted(authors):
        rel = d if d else "."
        n_trk, n_empty = tracked_has(rel if rel != "." else "")
        ign, rule = ignored(rel if rel != "." else ".")
        rd = readers_of(rel) if rel != "." else {}
        # THE THREE VERDICTS, and NONE OF THEM IS "PASS" BY ABSENCE OF EVIDENCE.
        if not (ROOT / rel).is_dir():
            verdict = "DECLARED-BUT-ABSENT"           # something writes into a dir that is not there
        elif rd and not authors[d]["sites"]:
            verdict = "DIARY"                         # read, never written
        elif authors[d]["sites"]:
            verdict = "AUTHORED"
        else:
            verdict = "NEITHER"
        rows.append({"dir": rel, "verdict": verdict, "authors": len(authors[d]["sites"]),
                     "reader_files": len(rd), "tracked": n_trk, "empty_blob": n_empty,
                     "ignored": ign, "ignore_rule": rule,
                     "reader_sites": {k: v[:3] for k, v in list(rd.items())[:6]}})
    return {"read": read, "present": present, "authors": len(authors), "rows": rows}


def main() -> int:
    ap = argparse.ArgumentParser(prog="checks/diary-census.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--readers-of", metavar="DIR",
                    help="every AST reader of one directory, with its line and shape")
    ap.add_argument("--plant", action="store_true")
    a = ap.parse_args()
    if a.plant:
        return plant()
    stamp = time.strftime("%Y-%m-%dT%H:%M")

    if a.readers_of:
        rel = a.readers_of.rstrip("/")
        rd = readers_of(rel)
        # A CITATION IS NOT A READ.  Prose in a docstring names the directory -- in this tree
        # ~20 files do -- and a citation cannot distinguish an instrument from a paragraph
        # ABOUT one.  MEASURED while writing this output: printing the two together gave 218
        # sites of which the reader-facing ones were a dozen, **which is how a report about
        # readers becomes a report about prose.**  `checks/diary-census.py` is itself in the
        # citation set -- it names the directory in this very docstring -- and a census that
        # counted itself as a reader would be a census that can always confirm itself.
        reads, cites = {}, {}
        for src, sites in rd.items():
            real = [s for s in sites if not s[2].startswith("CITATION")]
            if real:
                reads[src] = real
            if len(real) != len(sites):
                cites[src] = len(sites) - len(real)
        n_read_sites = sum(len(v) for v in reads.values())
        shapes: dict[str, int] = {}
        for v in reads.values():
            for s in v:
                k = s[2].split("(")[0].strip()
                shapes[k] = shapes.get(k, 0) + 1
        gd = gendirs()
        print(f"READERS OF {rel}")
        print(f"  census taken : {stamp}")
        print(f"  scope        : every source file in the tree "
              f"(SKIP_TOP={','.join(gd.SKIP_TOP) if gd else '?'} excluded). AST only, no regex.")
        print(f"  READER files : {len(reads)}    READ sites: {n_read_sites}")
        print(f"  CITATION only: {len(cites)} file(s) -- prose that NAMES the directory and is not "
              f"an instrument reading it (a lower bound, counted apart)")
        print(f"  by shape     : " + ", ".join(f"{k}={v}" for k, v in sorted(shapes.items())))
        print()
        for src in sorted(reads):
            print(f"  {src}")
            for _s, line, shape in reads[src][:6]:
                print(f"      :{line:<5} {shape}")
        print("\n  EVERY SITE IS A LOWER BOUND: a reader reached through a value that never "
              "appears as a\n  literal is invisible here, and so is a subprocess that opens "
              "the directory itself.")
        return 0

    c = census()
    if "error" in c:
        print(f"REFUSED, NOT A VERDICT: {c['error']} -- the scan cannot read its own population, "
              f"and an instrument that cannot see its population cannot be anything")
        return 3
    if a.json:
        print(json.dumps(c, indent=1, sort_keys=True))
        return 0
    rows = c["rows"]
    authored = [r for r in rows if r["verdict"] == "AUTHORED"]
    diary = [r for r in rows if r["verdict"] == "DIARY"]
    absent = [r for r in rows if r["verdict"] == "DECLARED-BUT-ABSENT"]
    print(f"DIARY CENSUS -- taken {stamp}")
    print(f"  scan coverage : {c['read']} of {c['present']} source files read "
          f"(SKIP_TOP excluded; the remainder are NOT in the population)")
    print(f"  authors found : {c['authors']} director(ies) have >=1 write site")
    print(f"  AUTHORED      : {len(authored)}")
    print(f"  DIARY         : {len(diary)}   <- read, never written by anything in the tree")
    print(f"  DECLARED-ABSENT: {len(absent)}  <- a write site names a directory that is not there")
    print()
    hdr = f"{'directory':48} {'authors':>7} {'rdr':>4} {'trk':>5} {'ign':>4}  verdict"
    print(hdr)
    print("-" * len(hdr))
    show = diary + absent
    for r in sorted(show, key=lambda r: r["dir"]):
        print(f"{r['dir']:48} {r['authors']:7} {r['reader_files']:4} {r['tracked']:5} "
              f"{'yes' if r['ignored'] else 'NO':>4}  {r['verdict']}")
    if not show:
        print("  (none -- every directory with a write site also has readers)")
    print()
    for r in sorted(diary, key=lambda r: r["dir"]):
        print(f"  DIARY {r['dir']}: readers={r['reader_files']} authors={r['authors']} "
              f"tracked={r['tracked']} ignored={r['ignored']} ({r['ignore_rule']})")
        for src, sites in list(r["reader_sites"].items())[:5]:
            print(f"      read by {src}: {sites[0][1]}")
    return 1 if diary or absent else 0


# ---- the plant: a meta-instrument's own blind spot is the one nobody else checks -------------
MAIN = 'if __name__ == "__main__":\n    raise SystemExit(0)\n'


def plant() -> int:
    """FIVE directions, on SYNTHETIC trees.  Two of them assert OPPOSITE directions
    (must-notice / must-not-pick-up), because a check that cannot say NO is a printer."""
    import tempfile
    bad = 0
    gd = gendirs()

    def expect(name, ok, got):
        nonlocal bad
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        bad += 0 if ok else 1

    def scratch() -> Path:
        """A FRESH tree per case.  MEASURED while writing this suite: cases 1 and 2 shared one
        directory, so case 1's writer was still on disk during case 2 and case 2 -- which
        asserts the OPPOSITE direction -- reported the same discovery and went RED for the
        wrong reason.  **A PLANT THAT SHARES ITS FIXTURE WITH THE CASE BEFORE IT IS NOT
        INDEPENDENT, AND THE FAILURE IT PRODUCES LOOKS LIKE A FINDING ABOUT THE CODE.**"""
        d = Path(tempfile.mkdtemp()).resolve()
        (d / "checks").mkdir()
        (d / "pyproject.toml").write_text("[project]\n")
        (d / "bin").mkdir()
        return d

    # 1 -- A NEW generated directory nobody declared IS discovered, and it has an author.
    t1 = scratch()
    (t1 / "checks/w.py").write_text(
        "from pathlib import Path\n"
        "HERE = Path(__file__).resolve().parent\n"
        "D = HERE / 'newdir'\n"
        "D.mkdir(parents=True, exist_ok=True)\n" + MAIN)
    got = gd.discovered(t1)
    expect("1: a NEW generated directory nobody declared IS discovered",
           "checks/newdir" in got, f"discovered={sorted(got)}")

    # 2 -- AND ITS OPPOSITE, ON A CLEAN TREE: a tree that only READS yields no generated
    # directory, so the scan can say NO.  A check that cannot say NO is a printer.
    t2 = scratch()
    (t2 / "checks/r.py").write_text(
        "import pathlib\n"
        "def read(p):\n"
        "    return pathlib.Path(p).read_text()\n" + MAIN)
    got2 = gd.discovered(t2)
    expect("2: a tree that only READS yields NO generated directory -- the check can say NO",
           got2 == {}, f"discovered={sorted(got2)} sources_read={gd.coverage(t2)[0]}")

    # 3 -- THE TWO-HOP SHAPES, which are the reason this file exists at all and which carry NO
    # path literal of their own.  `checks/differ.py` authors `runs/graphcmp/D`; a reader that
    # rebinds `differ.D`, or LOADS `checks/differ.py` and calls what it closes over, reads the
    # directory while never naming it.  A literal-only scan reports the tree's most important
    # reader as absent, which is a clean number from a half-population.
    t3 = scratch()
    # THE AUTHOR MUST ACTUALLY WRITE, OR THERE IS NO AUTHOR.  MEASURED while writing this
    # fixture: the first version of `checks/differ.py` below only READ, and cases 3 and 3b
    # then agreed with each other for the wrong reason -- `_author_stems()` returned `set()`,
    # so nothing was a reader because nothing was an author, and case 3 failed on a fixture
    # bug while looking exactly like a finding about the two-hop reader.  A plant whose
    # fixtures can silently stop being their own subject tests nothing.
    (t3 / "checks/differ.py").write_text(
        "from pathlib import Path\n"
        "ROOT = Path(__file__).resolve().parents[1]\n"
        "D = ROOT / 'runs/graphcmp/D'\n"
        "def cmd_run():\n"
        "    D.mkdir(parents=True, exist_ok=True)\n"
        "    (D / 'D0-run-summary.txt').write_text('graphs=0\\n')\n"
        "def unhealthy():\n"
        "    return (D / 'D0-run-summary.txt').read_text()\n" + MAIN)
    (t3 / "checks/b.py").write_text(
        "import differ\n"
        "def rebind(p):\n"
        "    differ.D = p\n" + MAIN)
    (t3 / "checks/c.py").write_text(
        "import importlib.util\n"
        "def load():\n"
        "    s = importlib.util.spec_from_file_location('d', 'checks/differ.py')\n"
        "    return s\n" + MAIN)
    rd = readers_of("runs/graphcmp/D", t3)
    # THE SHAPE IS THE PARENTHESIZED TOKEN, and the first version of this split on `(` and `=`
    # in the wrong order and read `load spec_from_file_location` as a shape name -- so the
    # assertion was made against strings the instrument never emits and could only ever fail.
    shapes = {s[2].split("(")[0].strip() for v in rd.values() for s in v}
    expect("3: BOTH two-hop shapes are seen -- `differ.D = ...` (rebind) and loading the AUTHOR "
           "by path (load) -- neither of which contains the directory's name",
           "checks/b.py" in rd and "checks/c.py" in rd
           and {"rebind", "load"} <= shapes,
           f"readers={sorted(rd)} shapes={sorted(shapes)}")

    # 3b -- THE CONTROL THAT PROVES 3 IS NOT VACUOUS: on a tree with NO author of that
    # directory, the same two files are NOT readers.  Without this, a scan that called
    # everything a reader would pass case 3 too.
    t3b = scratch()
    (t3b / "checks/b.py").write_text(
        "import differ\n"
        "def rebind(p):\n"
        "    differ.D = p\n" + MAIN)
    rd3b = readers_of("runs/graphcmp/D", t3b)
    expect("3b: CONTROL -- with no author of the directory, the same rebinding is NOT a reader "
           "(a scan that says YES to everything would pass case 3 too)",
           rd3b == {}, f"readers={sorted(rd3b)}")

    # 4 -- A BASENAME IS NOT A PATH.  `D0-run-summary.txt` alone names no directory; a scan
    # that matched it would report every reader of a file that never existed.
    t4 = scratch()
    (t4 / "checks/c.py").write_text(
        "NAME = 'D0-run-summary.txt'\n"
        "OTHER = 'D0-selfcheck'\n" + MAIN)
    rd2 = readers_of("runs/graphcmp/D", t4)
    expect("4: a BASENAME IS NOT A PATH -- a literal with no directory in it does not register "
           "a reader of that directory",
           rd2 == {}, f"readers={sorted(rd2)}")

    # 5 -- THE EMPTY POPULATION IS REFUSED, NEVER GREEN, and the denominator travels with it.
    bare = Path(tempfile.mkdtemp()).resolve()
    read_b, present_b = gd.coverage(bare)
    expect("5: an EMPTY discovery is EMPTY WITH ITS DENOMINATOR -- it must not read as healthy",
           gd.discovered(bare) == {} and present_b == 0 and read_b == 0,
           f"discovered={gd.discovered(bare)} read={read_b} present={present_b}")

    print(f"PLANTS: {'GREEN' if not bad else f'RED ({bad} MISMATCH)'}")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
