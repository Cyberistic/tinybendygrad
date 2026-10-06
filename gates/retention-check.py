#!/usr/bin/env python3
"""The retention rule -- `runskeep`: a generated directory holds EXACTLY the files its
generator's most recent successful run declares, and nothing else.

Chosen over KEEP-LATEST-N and KEEP-ALL-IF-CHEAP because every generator here writes FIXED NAMES
into a per-gate directory: "the previous run" is the same names with older bytes, not a second
set of names. So the question is never which files to keep, it is whether the set on disk is the
set the last attempt wrote.

FOUR CLAUSES, each with its own denominator, each measured from a DIFFERENT source so that no
two of them can agree with each other by construction:

  I    the directory holds exactly the declared set              per output directory
  II   a run clears its own output before writing                 per GENERATOR, from its AST
  III  an output directory is not in the index                    per output directory, from git
  IV   a generated directory may exist only if its run was healthy per generator's OWN health fn
  V    EVERY generated directory, DISCOVERED                        per DISCOVERED directory, from
                                                                      a scan of every write site

CLAUSE V IS THE ONE THAT CLOSES THE CLASS, AND IT IS NEW BECAUSE A TWO-ITEM REGISTRY IS A LIST
THAT CANNOT BE WRONG ABOUT A THIRD ITEM. `Output("graphcmp", ...)` and `Output("gates", ...)` were
this file's entire notion of where output goes, and `checks/gen/` -- written by
`checks/abi_gate.py:616` through `bend -o`, tracked as two EMPTY BLOBS, and read back by that same
gate at `:624` -- sat outside both. Clauses I-IV still run on the REGISTRY because they need a
DECLARED SET to measure against; clause V runs on `gates/gendirs.py`'s DISCOVERY, which needs
none, and it is what makes a fourth directory visible without anyone editing this file.

THE POPULATION IS SHARED, NOT DUPLICATED. `gates/gates-pop.py` imports `gates/gendirs.py` and
reports the same `discovered()` count, because **two instruments with two lists have no authority
over each other, and the disagreement between them would be a third finding with no way to settle
it.** One module, one population, two consumers -- and a change to it moves both.

CLAUSE IV IS THE ONE THAT MATTERS, and the reason this file is a check and not an opinion is
that it does not have a health opinion: it calls `checks/differ.py`'s own `unhealthy()` and
`artefacts_ok()`. A rule that re-implemented health would be a second opinion that can disagree
with the first, and this repo has already had a figure rot through nine forms because two
instruments answered the same question. `artefacts_ok()` DELIBERATELY excludes `*.err`, because a
healthy run may hold legitimately empty stderr and *a rule that flags a correct file is a rule
that always fails*; that exclusion is inherited here, not restated.

WHAT IT GATES, AND THE DENOMINATOR. Two generator families, not "every directory that looks
generated": clause I is only decidable against a DECLARED set, so a directory whose generator
declares nothing would enter with a denominator it cannot support.

  gates/artifacts/<gate>/   8 dirs, generator gates/gatekit.py
  runs/graphcmp/D/          1 dir,  generator checks/differ.py

The other tracked directories under runs/ are NOT in the denominator and are printed as
unregistered, because a rule that grows its own denominator stops being a measurement.

EXIT: 0 when no clause is red. 1 when any clause is red. 2 when a precondition is missing (no
git, an output root that is not there), because a check that cannot measure must not report 0.
"""
import argparse
import ast
import fnmatch
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "checks"))
sys.path.insert(0, str(ROOT / "gates"))

# THE FALLBACK SETS BELOW ARE OURS, NOT THE GENERATORS', and each is used ONLY when the generator
# publishes no `declared()` of its own. `checks/differ.py:156` DOES publish one -- derived from
# `WANT`/`CONTROLS`/`PLANTS`/`STAB`, the same tables `cmd_run` builds its names from -- so its
# answer is used and the 22-line glob table that used to live here is GONE. That table was wrong
# in the exact way `differ.declared()`'s own docstring names: a typed copy of a derived set goes
# stale silently, and `.agents/slop/difftxt/` already found 4 LOST and 4 NEW artifact names between
# two runs of the SAME driver. A fallback that loses to the generator is a fallback; a fallback
# that can WIN is a second opinion, which is the thing this file exists to avoid.
#
# `gates/gatekit.py` publishes no `declared()`, so `GATEKIT_OUTPUT` is transcribed from the seven
# names `Gate.run` writes. It is the one set here this file owns, and the report SAYS SO.
GATEKIT_OUTPUT = frozenset(f"{lane}.{ext}" for lane in ("py", "bd", "bn") for ext in ("txt", "sub")) | {"gate.bin"}
# `artefacts_ok()` excludes `*.err` because a healthy run may hold legitimately empty stderr.
# The DECLARED SET must not: the `.err` beside every artifact is declared output, and a set that
# omitted it would call every correct run a residue.
STDERR = "*.err"


class Output:
    """One generated directory family: where it is, what writes it, what it may hold, who
    judges it healthy.

    declared  the file names the generator may write, as glob patterns. None means "ask the
              generator", which is what `gatekit.declared()` would answer.
    healthy   a zero-argument callable returning a list of complaints about the LAST run, or
              None when the generator publishes no health function at all -- which is itself a
              reportable state and not a pass.
    """

    def __init__(self, key, path, generator, declared, healthy, note=""):
        self.key, self.path, self.generator = key, path, generator
        self.declared, self.healthy, self.note = declared, healthy, note

    def dirs(self):
        """Every output directory this family owns. `graphcmp` names its output DIRECTORY
        (`runs/graphcmp/D`), while `gates` names the PARENT and owns the children -- so one
        family contributes 1 and the other 8, and the total is 9. Getting this wrong is how a
        denominator silently shrinks by the one directory the rule is about.
        """
        root = ROOT / self.path
        if not root.is_dir():
            return []
        if self.key == "graphcmp":
            return [root]
        return sorted(p for p in root.iterdir() if p.is_dir())


def label(path):
    """Repo-relative when it can be, absolute when it cannot.

    `--dir` points a family at a directory OUTSIDE the repo so a plant can run without touching
    the live tree, and `Path.relative_to` raises on that rather than returning anything. Four
    call sites raised it in this file's first run, which is why the plant harness found it and
    the live run did not: `--help` and a real invocation never leave the repo.
    """
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def git(*args):
    """`git` as a MEASUREMENT, not a dependency: `ls-files` reads the index, and this file's
    only git-shaped claim is about what is IN the index.

    A pathspec OUTSIDE the repository is not an error here -- it is 0 tracked entries, which is
    the truthful answer for a scratch tree, and it is what `--dir` plants need. MEASURED: `git
    ls-files -- /tmp/...` exits 128 with `is outside repository`, and letting that through would
    have made clause III raise SystemExit and take clauses I and II's verdicts down with it --
    a check that stops reporting the moment it cannot answer one question is not a check."""
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        if "outside repository" in r.stderr:
            return ""
        raise SystemExit(f"retention-check: git {' '.join(args)} failed: {r.stderr.strip()[:200]}")
    return r.stdout


def load_gendirs():
    """`gates/gendirs.py`, IMPORTED BY PATH and not by name.

    `gates/` is not a package and putting it on `sys.path` would make `gendirs` a name ANY file in
    the tree could shadow -- **AN INSTRUMENT LOADED BY A NAME ANYBODY CAN BIND IS AN INSTRUMENT
    WHOSE POPULATION SOMEBODY ELSE CAN CHOOSE.** `gates/gates-pop.py` loads it the same way, so
    both consumers share one implementation and one population.
    """
    p = ROOT / "gates" / "gendirs.py"
    if not p.is_file():
        raise SystemExit("retention-check: gates/gendirs.py is gone -- it IS the discovered "
                         "population, and a check whose population is missing must not report 0")
    spec = importlib.util.spec_from_file_location("gendirs", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---- clause I: the declared set, and only the declared set ----------------------
def residues(directory, declared):
    """Files present that the generator does not declare, and how many declared files are
    ABSENT. The absences are counted and NOT failed: a run that exits early writes fewer files,
    and that is incompleteness (clauses II and IV), not retention."""
    present = {p.name for p in directory.iterdir() if p.is_file()}
    extra = sorted(n for n in present if not any(fnmatch.fnmatch(n, pat) for pat in declared))
    missing = sorted(pat for pat in declared if not any(fnmatch.fnmatch(n, pat) for n in present))
    return extra, missing


# ---- clause II: does the generator clear its own output before it writes ---------
def writer_exits(source):
    """`(total_exits, exits_after_the_first_write, clears)` for the generator's writer.

    MEASURED ON THE `Gate.run` AST, NOT BY RUNNING IT. Two reasons, both measured rather than
    assumed: `bend` is a 1.4 GB process that must never be run twice at once, and the tree is
    not always quiescent -- while this file was being written a unit was mid-run and
    `gates/artifacts/*/` mtimes moved under the reader's feet, so a measurement taken by
    running the generator is a measurement of a moving target. The AST does not move.

    STRUCTURAL, NOT A LINE MEASURE. The number the RECOVERED report calls "5 of 17" used to be
    the count of `return`s after the line of the first `self.dir` attribute reference -- a LINE
    measure of a property that is STRUCTURAL (every exit reaches `self._settle(ok)`). It was
    invariant under deleting the `finally`, because it never looked at the `finally`. What follows
    counts an exit as COVERED iff it sits either inside a `try` whose non-empty `finalbody` runs
    cleanup, or after that `try` in the same body -- where the finally has already run by
    construction. Delete the `finally` and every exit falls to UNCOVERED.

    `clears` is the set of
    removal-shaped calls anywhere in the file -- `unlink`, `rmtree`, `remove`, `glob`,
    `iterdir`. An EMPTY set means the generator never removes anything at all, which is the
    whole of clause II: there is no clear to get wrong.
    """
    tree = ast.parse(source)
    remover = {"unlink", "rmtree", "remove", "rmdir", "glob", "iterdir", "walk"}
    clears = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            if fn in remover:
                clears.add(fn)

    def _depths(node, depth):
        """Yield the cleanup-depth of every `return` under `node`. Depth, not identity: the
        `ast.Load` nodes are INTERNED, so a set of node ids answers TRUE for returns below the
        `finally` too -- measured 13/13 on a function where 12/13 is the truth."""
        if isinstance(node, ast.Try):
            cleans = depth + 1 if (node.finalbody and any(
                isinstance(s, (ast.Expr, ast.Assign, ast.AugAssign, ast.Delete))
                for s in node.finalbody)) else depth
            for s in node.body: yield from _depths(s, cleans)
            for h in node.handlers:
                for s in h.body: yield from _depths(s, cleans)
            for s in node.orelse: yield from _depths(s, depth)
            for s in node.finalbody: yield from _depths(s, 0)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda, ast.ClassDef)):
            return                        # a nested scope has its own exits
        elif isinstance(node, ast.Return):
            yield depth
        else:
            for child in ast.iter_child_nodes(node):
                yield from _depths(child, depth)

    exits = []
    for cls in (n for n in tree.body if isinstance(n, ast.ClassDef)):
        for fn in cls.body:
            if not isinstance(fn, ast.FunctionDef) or fn.name != "run":
                continue
            covered = uncovered = 0
            seen_cleanup = False
            for stmt in fn.body:
                ds = list(_depths(stmt, 0))
                if isinstance(stmt, ast.Try) and stmt.finalbody and any(
                        isinstance(s, (ast.Expr, ast.Assign, ast.AugAssign, ast.Delete))
                        for s in stmt.finalbody):
                    covered += sum(1 for d in ds if d)
                    uncovered += sum(1 for d in ds if not d)
                    seen_cleanup = True
                elif seen_cleanup:
                    covered += len(ds)     # the finally has already run on these exits
                else:
                    uncovered += len(ds)
            if covered or uncovered:
                exits.append((fn.lineno, covered + uncovered, uncovered))
    return exits, clears


def attempts(directory, slack=600):
    """`(cluster_count, [names in the oldest cluster])`: how many runs' worth of files this
    directory holds, and the ones the EARLIEST left behind.

    NOT newest-versus-the-rest. MEASURED: a single correct run writes its seven files over 2-11
    SECONDS (`py.rows`, `bd.out`, `gate.bin`, then the `.sub`s, with the native compile in the
    middle), so "older than the newest" names six of seven files in a directory produced by one
    GOOD run -- a rule that fires on a correct file is a rule that always fails. The
    discriminator is a CLUSTER: files written within `slack` seconds of each other are one
    attempt, and a second cluster with a whole directory's worth of files in it is a run that
    did not clear what the previous one left.

    `slack=600` is measured, not chosen: the largest gap BETWEEN files of one good run across
    the 8 gate dirs is 9 seconds (`mixin-op-gate`), and the smallest gap between two DIFFERENT
    runs in `runs/graphcmp/D` is 6772 seconds. So 600 sits two orders of magnitude clear of the
    false-positive boundary and still catches the smallest true positive. MEASURED this way:
    8/8 gate dirs are ONE cluster, and `runs/graphcmp/D` is THREE over 151 files -- 15 from
    before the last attempt, including `D0-run-summary.txt`, which `checks/README.md:46` calls
    "the run's verdict".
    """
    files = sorted((p for p in directory.iterdir() if p.is_file()),
                   key=lambda p: p.stat().st_mtime)
    clusters = []
    for p in files:
        if clusters and p.stat().st_mtime - clusters[-1][-1].stat().st_mtime <= slack:
            clusters[-1].append(p)
        else:
            clusters.append([p])
    # EVERYTHING but the last cluster, not just the first: a tree left by three attempts has two
    # generations of leftovers and naming one of them understates it. The verdict asks "is the
    # directory the last run's output", so the residue is everything that is not the last run's.
    stale = [p.name for c in clusters[:-1] for p in c]
    return len(clusters), stale


# ---- clause III: is the output in the index -------------------------------------
def tracked(directory):
    """What the index holds for this directory. `git ls-files` takes a PATHSPEC, and a path
    outside the repo is not one -- so a `--dir` copy reports 0 tracked, which is the truthful
    answer for a scratch tree and is exactly what a plant wants to see."""
    return [p for p in git("ls-files", "-z", "--", label(directory)).split("\0") if p]


# ---- the registry ---------------------------------------------------------------
def unregistered(res):
    """Tracked directories under runs/ that no registered family claims, NAMED and not scored.

    They are outside the denominator because their generator declares no set, and a clause I with
    no declared set has no denominator to report against. Printing them is what keeps that from
    being SILENT -- `checks/sweep.py:145` already learned this lesson the expensive way, with a
    hand-maintained list of unit names that outlived its units and became the only belt.
    """
    claimed = {d.resolve() for o in res for d in o.dirs()}
    root, out = ROOT / "runs", []
    for p in sorted(root.rglob("*")):
        rel = p.relative_to(ROOT)
        if not p.is_dir() or p.resolve() in claimed or any(q.resolve() in claimed for q in p.parents):
            continue
        if git("ls-files", "-z", "--", str(rel)).strip("\0"):
            out.append(str(rel))
    return out


def registry(graphcmp_dir=None, gates_dir=None):
    """The two families, and the health callable each one gets.

    `graphcmp` borrows `differ.declared()`, `differ.unhealthy()` and `differ.artefacts_ok()` BY
    REFERENCE, and its `D` is rebound when `--dir` moves the corpus, so a plant exercises differ's
    real code rather than a copy of it. `gates` has NO health callable and NO declared(): the
    verdict `gatekit` computes never reaches the disk, so a gate output directory cannot say
    whether its own run was healthy. That is reported as UNMEASURABLE against a denominator of 8,
    because a missing baseline is not a passing baseline.
    """
    import differ
    if graphcmp_dir:
        differ.D = Path(graphcmp_dir)
    # `differ.declared()` lists the `.txt` artifacts; the `.err` beside each is declared output
    # too, and belongs in the SET even though `artefacts_ok()` excludes it from the SHAPE check.
    graphcmp_declared = set(differ.declared()) | {STDERR}
    return [
        Output("graphcmp", graphcmp_dir or str(Path("runs/graphcmp/D")), "checks/differ.py",
               graphcmp_declared, lambda: differ.unhealthy() + differ.artefacts_ok(),
               "declared = checks/differ.py's OWN declared(); health = its OWN "
               "unhealthy()+artefacts_ok(), whose .err exclusion is inherited so a legitimately "
               "empty stderr is not flagged here either"),
        Output("gates", gates_dir or str(Path("gates/artifacts")), "gates/gatekit.py",
               GATEKIT_OUTPUT, None,
               "declared = THIS FILE (gatekit publishes no declared()); health = NONE: it prints "
               "its verdict and never writes it, so 0 of 8 gate dirs can say whether they were "
               "healthy"),
    ]


# ---- the report ------------------------------------------------------------------
def report(res):
    """One line per clause with its own denominator, and the offenders named. The denominator is
    printed with every verdict because a verdict with no denominator is a claim nobody can check."""
    red = 0

    # I -- one measurement per directory, kept so the summary line cannot disagree with the lines
    # above it. A summary recomputed by a second expression is a second opinion about the first.
    clean, dirty, missing = 0, 0, 0
    for o in res:
        for d in o.dirs():
            extra, absent = residues(d, o.declared)
            missing += len(absent)
            if extra:
                dirty += 1
                print(f"I  RESIDUE  {label(d)}: {len(extra)} undeclared {extra[:6]}")
            else:
                clean += 1
    total = clean + dirty
    print(f"I   declared set only: {clean}/{total} dirs clean, {dirty} with residue, "
          f"{missing} declared file(s) ABSENT (reported, not failed -- that is II/IV)")
    print()
    red |= bool(dirty)

    # II -- per GENERATOR, from its AST. `gates/gatekit.py` and `checks/differ.py` share no
    # plumbing, so the two verdicts are independent measurements and neither can launder the other.
    ok_gens = measured = unmeasured = 0
    for o in res:
        source = ROOT / o.generator
        if not source.is_file():
            print(f"II UNMEASURED  {o.generator} is gone -- it is what declares the set")
            red = 1
        else:
            exits, clears = writer_exits(source.read_text())
            if not exits:
                # THE VACUOUS PASS, caught in this file's own first run and NOT left in. A
                # generator with no `class X: def run` gives an empty exit list, and `late == 0`
                # over nothing reads as "0/0 exits, clears OK" -- a green verdict with NO
                # DENOMINATOR, which is the exact defect this repo's rules exist to catch.
                # `checks/differ.py` writes from module-level functions, so it is genuinely not
                # measurable this way; the reader is told where its clear would have to live.
                unmeasured += 1
                print(f"II UNMEASURED  {o.generator}: no class-scoped `run` writes this output, so "
                      f"the exit\n               count has no denominator. It stages `.tmp.` and "
                      f"os.replace-promotes, which leaves\n               no partial file but does NOT "
                      f"clear, and it unlinks 2 hardcoded stale\n               names "
                      f"(`D9-stability-{{a,b}}.txt`) rather than the directory.")
            else:
                late = sum(l for _, _, l in exits)
                total_exits = sum(t for _, t, _ in exits)
                ok = bool(clears) and late == 0
                ok_gens, measured = ok_gens + ok, measured + 1
                print(f"II {'OK        ' if ok else 'FALSE     '} {o.generator}: "
                      f"{late}/{total_exits} exits NOT covered by a cleanup `finally`, "
                      f"clears={sorted(clears) or 'NONE'}")
                red |= not ok
        # The LEFTOVER scan reads the DIRECTORY, not the generator, so it runs either way: it is
        # the only part of clause II that still measures `runs/graphcmp/D`, whose generator has
        # no AST-measurable writer.
        for d in o.dirs():
            n, oldest = attempts(d)
            if n > 1:
                print(f"II  LEFTOVER   {label(d)}: {n} runs' worth of files, "
                      f"{len(oldest)} from the earliest, e.g. {oldest[:3]}")
    print(f"II  clears its own output: {ok_gens}/{measured} MEASURED generators "
          f"({unmeasured} unmeasurable)")
    print()
    red |= bool(measured - ok_gens)

    # III -- the index. UNSATISFIABLE BY ITSELF and reported as such; `--apply` writes the ignore
    # block and does not touch the index.
    untracked, tracked_dirs, n_tracked = 0, 0, 0
    for o in res:
        for d in o.dirs():
            t = tracked(d)
            if t:
                tracked_dirs += 1
                n_tracked += len(t)
                print(f"III TRACKED   {label(d)}: {len(t)} "
                      f"entr{'y' if len(t) == 1 else 'ies'} in the index")
            else:
                untracked += 1
    total = untracked + tracked_dirs
    print(f"III not in the index: {untracked}/{total} dirs, {n_tracked} tracked "
          f"entr{'y' if n_tracked == 1 else 'ies'} total")
    if n_tracked:
        print("III UNSATISFIABLE BY ITSELF: `.gitignore` cannot untrack, only a commit can. "
              "`--apply`\n              writes the block for NEW output and prints the "
              "`git rm --cached` line it will not run.")
        red = 1
    print()
    red |= bool(n_tracked)

    # V -- THE DISCOVERED POPULATION, AND THE CLAUSE THAT CLOSES THE CLASS. I-IV run on a
    # TWO-ITEM REGISTRY; this runs on `gates/gendirs.py`, which finds every directory in the tree
    # that something WRITES INTO by scanning write sites and resolving them through a constant-
    # propagation fixpoint. **A POPULATION DEFINED BY A LIST CANNOT BE WRONG ABOUT A FOURTH ITEM
    # BECAUSE IT NEVER LOOKS AT ONE**, so the fourth item is looked at here instead.
    print()
    gendirs = load_gendirs()
    rows = gendirs.table()
    read, present = gendirs.coverage()
    print(f"V  DISCOVERED {len(rows)} director{'y' if len(rows) == 1 else 'ies'} something in "
          f"this tree WRITES\n   INTO, from {read} of {present} source files. A LOWER BOUND: a "
          f"SUBPROCESS write is invisible\n   to a scanner that does not execute it -- "
          f"`checks/gen/` is reached through `bend -o`.")

    # V(1) -- RED, AND DECIDABLE FROM TWO GIT COMMANDS WITH NO LIST. A directory that is IN THE
    # INDEX and ALSO named by a `.gitignore` rule is the tree contradicting ITSELF in two of its
    # own files: one declares the directory is generated output that must not be tracked, the
    # other tracks it. `checks/gen/` is the live instance -- 2 entries, BOTH git's EMPTY BLOB --
    # and this is the form that would have caught `runs/` and `gates/artifacts/` before clause
    # III's 219-entry red. It needs no knowledge of which directories exist.
    contradiction = [r for r in rows if r["n_tracked"] and r["ignored"]]
    for r in contradiction:
        print(f"V  CONTRADICTS {r['dir']}: {r['n_tracked']} entr"
              f"{'y' if r['n_tracked'] == 1 else 'ies'} in the index AND a `.gitignore` rule names "
              f"it")
        print(f"V              {r['n_empty_blob']} of them at git's EMPTY BLOB "
              f"(e69de29) -- a tracked PLACEHOLDER, not a tracked artifact")
    print(f"V  IGNORED-BUT-INDEXED: {len(contradiction)}/{len(rows)} dirs -- "
          + ("none" if not contradiction else
             "the tree declares them generated and tracks them anyway"))

    # V(2) -- a CENSUS, NOT A VERDICT, AND IT IS NAMED AS A CENSUS. A directory something writes
    # into is a LOWER bound on "generated": the vendored `tinygrad/` snapshot is written into by
    # its own build and is SOURCE, and no static property separates the two. MEASURED, that is
    # exactly the shape of `unregistered()` below and of `LIVE_UNITS`: a set that cannot be
    # decided is printed with a number rather than silently scored.
    indexed = [r for r in rows if r["n_tracked"]]
    unignored = [r for r in indexed if not r["ignored"]]
    print(f"V  CENSUS      {len(indexed)}/{len(rows)} discovered dirs are in the index "
          f"({sum(r['n_tracked'] for r in indexed)} entr"
          f"{'y' if sum(r['n_tracked'] for r in indexed) == 1 else 'ies'}), of which "
          f"{len(unignored)} are\n               not `.gitignore`d. 'Something writes here' is a "
          f"LOWER bound on 'generated' -- the vendored\n               `tinygrad/` tree is written "
          f"into by its own build and is source -- so this row is\n               COUNTED, NOT "
          f"FAILED, and the names are below.")
    for r in unignored[:40]:
        blob = f", {r['n_empty_blob']} at git's EMPTY BLOB" if r["n_empty_blob"] else ""
        print(f"V    INDEXED   {r['dir']}: {r['n_tracked']} entr"
              f"{'y' if r['n_tracked'] == 1 else 'ies'}{blob}")
    if len(unignored) > 40:
        print(f"V              ... and {len(unignored) - 40} more")
    red |= bool(contradiction)

    # IV
    print()
    for o in res:
        dirs = o.dirs()
        if o.healthy is None:
            print(f"IV UNMEASURABLE {o.path}/: 0/{len(dirs)} dirs can report health -- {o.note}")
            continue
        bad = o.healthy()
        if bad:
            red = 1
            print(f"IV FIRES     {o.path}/: the directory exists and its last run was NOT healthy: "
                  f"{len(bad)} complaint(s)")
            for line in bad[:6]:
                print(f"IV              {line}")
            if len(bad) > 6:
                print(f"IV              ... and {len(bad) - 6} more")
        else:
            print(f"IV OK        {o.path}/: {len(dirs)} dir(s), last run healthy on its own measure")

    print()
    stray = unregistered(res)
    if stray:
        print(f"--  {len(stray)} tracked dir(s) under runs/ belong to no registered generator, so "
              f"they are NOT\n   in any denominator above: {', '.join(stray)}")
    print("RETENTION: RED" if red else "RETENTION: OK")
    return red


def apply_fix():
    """`--apply`: the ignore block, and nothing else. It does NOT `git rm --cached` -- that is a
    commit, and an instrument that silently rewrites the index is a second actor on the tree.

    It writes `gates/artifacts/` and NOT `runs/graphcmp/D/`, because `.gitignore:128-134`
    records a DELIBERATE decision that `runs/` is tracked ("pre-split oracle baselines"). Silently
    overturning a documented decision from inside a check is the same move as the one clause
    IV exists to prevent, so clause III reports the conflict and leaves it to the owner.
    """
    marker = "# GENERATED OUTPUT: a generated directory holds what its generator's last run"
    block = "\n".join([
        "",
        marker,
        "#   writes and nothing else, so tracking its output tracks a file set that changes on",
        "#   every run. `.gitignore` CANNOT untrack what is already tracked -- only a commit",
        "#   can -- so this block stops NEW output and leaves the tracked entries to an owner",
        "#   who can commit the untrack. `gates/retention-check.py --help` states the rule.",
        "gates/artifacts/",
    ])
    gi = ROOT / ".gitignore"
    body = gi.read_text()
    if marker in body:
        print("apply: .gitignore already carries the block")
        return 0
    gi.write_text(body.rstrip("\n") + "\n" + block + "\n")
    print("apply: appended the generated-output block to .gitignore (gates/artifacts/ only; "
          "runs/graphcmp/D/ stays tracked by .gitignore:128-134's deliberate decision)")
    return 0


def main():
    ap = argparse.ArgumentParser(
        prog="gates/retention-check.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="DENOMINATOR: 8 gate dirs + 1 graphcmp dir = 9 output directories, 2 generators. "
               "A verdict with no denominator is a claim nobody can check.")
    ap.add_argument("--dir", action="append", metavar="KEY=PATH",
                    help="point a family's output somewhere else (plant/disarm only)")
    ap.add_argument("--apply", action="store_true",
                    help="append the generated-output block to .gitignore; never touches the index")
    a = ap.parse_args()
    if a.apply:
        return apply_fix()
    over = dict(kv.split("=", 1) for kv in (a.dir or ()))
    unknown = set(over) - {"graphcmp", "gates"}
    if unknown:
        ap.error(f"unknown --dir key(s) {sorted(unknown)}; expected graphcmp or gates")
    res = registry(over.get("graphcmp"), over.get("gates"))
    return report(res)


if __name__ == "__main__":
    sys.exit(main())
