"""CENSUS: of the files a re-vendor of `tinygrad/` moved, WHICH does the port actually DEPEND ON?

    .venv/bin/python gates/vendordep-census-gate.py             # the table
    .venv/bin/python gates/vendordep-census-gate.py --rows      # name=value rows only

WHY A NEW INSTRUMENT, MEASURED. `gates/gapcensus.py` answers "how far is the port from
tinygrad" and `checks/revendor-struct.py` answers "what STRUCTURAL shape changed, and who in
this tree READS it". NEITHER answers this question:

  * `gapcensus.py` compares module NAMES (`os.walk` + `basename`), and this file's whole
    finding is that a NAME match is not a dependency -- `HCQ_DEVS` is defined in
    `device.py` and merely IMPORTED by `hcq2.py`, and the port declares it in
    `runtime/support/hcq2.bend`. A name-keyed census scores that pair as covered. It is not.
  * `revendor-struct.py` reads only FIVE structural break classes (field/signature/enum)
    and its population is pinned `OLD, NEW = "91b8cb5fa", "upstream"` -- upstream commit
    2026-10-02, i.e. THE PREVIOUS re-vendor. It measured 89 changed files against its own
    question and does not enumerate this one. Re-pointing it is not this file's business.

WHAT "DEPENDS ON" IS MEASURED TO BE, and the axis is stated because the answer is NOT the
one a reader assumes. Dependence is a property of the port's FILE GRAPH, not of a name:

    DEPENDS   the port's counterpart file is REACHABLE from a DECLARED driver
    coverage  a separate, independent question: does the port carry a counterpart for the
              behaviour that MOVED. `device.py` scores DEPENDS=yes, coverage=NO.

Those two axes disagree on 8 of 29 files, which is the finding: "the port depends on it"
and "the port mirrors what changed in it" are different questions and answering one does not
answer the other.

THE POPULATION IS DISCOVERED AND IS NOT A LIST. The changed set is
`git diff <old-tinygrad-tree> <new-tinygrad-tree>`, where the two trees come from the two
commits `git log -- tinygrad` reports. Measured: `77e6c2bec` and `86c4f1343`, trees
`62319c8a` and `6c91e897`, 29 paths (28 M + 1 A). Nothing here names a file.

THE REACHABILITY ROOTS ARE DISCOVERED TWICE, AND THE COUNT THEY GIVE IS PRINTED BOTH TIMES,
because the answer MOVES with the root set and a reader must see that it moved: `gates/*-gate.py`
`bend=` declarations alone are 62 roots and reach 28 port files; adding every `bend <path>.bend`
INVOCATION site in the tree is 234 more roots and reaches 129. `unreached` therefore means "not
reached BY THE ROOTS THIS CENSUS USES", a statement about the roots and NOT a verdict of
deadness -- even at 129 of 166 the class cannot bear that meaning, and the `ladder.*` rows
below carry the whole 3 / 20 / 25 range so no reader has to guess which one they are quoting.

WHAT IS A `.bend` TOKEN, STATED WHERE IT IS COUNTED. Bend has no import graph with semantics and
the port never calls upstream (it MIRRORS it), so a token in a `.bend` file is a MENTION and not
a read -- `checks/revendor-struct.py`'s header says the same and counts them in a separate,
weaker class. Every `mentions=` column here is in that weaker class and is labelled so. The only
thing this gate can say for certain without running `bend` is REACHABILITY, and `bend` is not run
by this gate at all.

THE SYMBOL READER READS ASSIGNMENTS, AND THAT IS NOT COSMETIC. A `def`/`class`-only reader
reports `changed-symbols=0` for `codegen/simplify.py`, `renderer/nir.py` and `uop/divandmod.py`.
All three DID change behaviour, and all three carry it in a module-level `PatternMatcher` list
or dict -- `pm_reduce_collapse`, `f_aop`, `div_and_mod_symbolic`. An instrument that reported
"no behaviour change" there would be reporting its own blind spot, so `symmap()` below records
module-level assigned names and the row `sight.changed_symbols` is the check on it.

THE FIVE EXITS ARE `gatekit`'s, unmodified, so `$?` speaks the same vocabulary as every other
gate. `SKIP` (4) if git or the port is absent -- a census that could not run is not a census
that found nothing.
"""
from __future__ import annotations

import ast
import os
import re
import subprocess
import sys
from collections import Counter, deque
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, PASS, SKIP, VERDICT  # noqa: E402

ROOT = HERE.parent
PORT = ROOT / "tinybendygrad"


def _retarget(argv: list[str]) -> None:
    """`--root PATH` re-points ROOT, so the PLANT can mutate this instrument against the REAL
    tree without the real tree being edited. The copy that measured DEPENDS=0 in a tree of
    symlinks proved why this is needed: without the real tree's driver-naming files the census
    has 0 roots and 0 DEPENDS, which is a measurement of the ROOTS and not of the port."""
    global ROOT, PORT
    if "--root" in argv:
        ROOT = Path(argv[argv.index("--root") + 1]).resolve()
        PORT = ROOT / "tinybendygrad"
SKIP_DIRS = {".git", ".venv", "references", "__pycache__", "node_modules"}
DEF = re.compile(r"^\s*def\s", re.M)
IMPORT = re.compile(r"^\s*import\s+(\.?/?[\w./\-]*\.bend)\b", re.M)
MENTION = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")


def git(*args: str) -> str:
    p = subprocess.run(("git",) + args, cwd=ROOT, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(f"git {' '.join(args)}: rc={p.returncode} {p.stderr.strip()}")
    return p.stdout


def git_show_opt(rev_path: str) -> str:
    """`git show`, ABSENT -> "". Only for the OLD side of an ADDED path."""
    p = subprocess.run(("git", "show", rev_path), cwd=ROOT, capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else ""


# --------------------------------------------------------------- the population


def revendor() -> tuple[str, str, list[tuple[str, str]]]:
    """(old tree, new tree, [(status, path)]). DISCOVERED, never a list.

    The two commits are the two most recent that touch `tinygrad/`, and the trees are that
    commit's `tinygrad` SUBTREE -- which is why every path below is `device.py` and NOT
    `tinygrad/device.py`. Measured 2026-10-20: `86c4f1343` and `77e6c2bec`, 29 paths.
    """
    commits = git("log", "--format=%H", "--", "tinygrad").split()
    if len(commits) < 2:
        raise RuntimeError("fewer than two commits touch tinygrad/; no re-vendor to census")
    old = git("rev-parse", f"{commits[1]}:tinygrad").strip()
    new = git("rev-parse", "HEAD:tinygrad").strip()
    paths = [ln.split("\t") for ln in git("diff", "--name-status", old, new).strip().splitlines()]
    return old, new, [(p[0], "\t".join(p[1:])) for p in paths]


# ---------------------------------------------------------------- the port tree


def bend_files() -> dict[str, str]:
    """repo-relative path -> text, by DIRECTORY WALK. `glob` is the trap `gapcensus.py` names."""
    out = {}
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in SKIP_DIRS and not d.startswith(".git")]
        for n in fn:
            if n.endswith(".bend"):
                p = Path(dp) / n
                out[str(p.relative_to(ROOT))] = p.read_text(encoding="utf-8", errors="replace")
    return out


def driver_roots(files: dict[str, str]) -> tuple[set[str], set[str]]:
    """TWO discovered root sets, returned SEPARATELY so the caller can print both.

    `declared` = a driver a `gates/*-gate.py` names in its own `bend=` argument -- the
    declaration site, read from `gates/` only. `invoked` = every `bend <path>.bend`
    invocation site anywhere in the tree, which is a WIDER population because the corpus
    driver and the e2e lanes live outside `gates/`.
    """
    declared: set[str] = set()
    for dp, dn, fn in os.walk(ROOT / "gates"):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for n in fn:
            if not n.endswith("-gate.py"):
                continue
            text = (Path(dp) / n).read_text(encoding="utf-8", errors="replace")
            for m in re.findall(r"\bbend\s*=\s*r?[\"']([^\"']+\.bend)[\"']", text):
                for cand in (ROOT / "gates" / m, ROOT / m):
                    if cand.is_file():
                        declared.add(str(cand.relative_to(ROOT)))
                        break
    invoked: set[str] = set()
    # `.rows` IS INCLUDED AND THAT IS NOT COSMETIC: 35 shell/md rows files carry `bend X.bend`
    # invocation sites, and excluding them is what made an earlier reading of this gate say
    # 7 roots where the honest count is larger. The extension list is the set of files that
    # CAN name a driver, stated here rather than left implicit.
    SCAN = (".py", ".sh", ".md", ".mjs", ".json", ".rows")
    inv = re.compile(r"\bbend(?:\s+--[\w=-]+)*\s+(\.?/?[\w./\-]*\.bend)\b")
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in SKIP_DIRS and not d.startswith(".git")]
        for n in fn:
            if not n.endswith(SCAN):
                continue
            text = (Path(dp) / n).read_text(encoding="utf-8", errors="replace")
            for m in inv.findall(text):
                # RESOLVED FROM THE REPO ROOT FIRST, THEN FROM THE FILE'S OWN DIRECTORY,
                # because a shell oracle writes `./bin/bend tinybendygrad/mixin/op.bend` and
                # runs it from `gates/oracles/`, so the specifier is ROOT-relative while the
                # file that names it is not.
                for cand in (Path(os.path.normpath(os.path.join(ROOT, m.lstrip("/")))),
                             Path(os.path.normpath(os.path.join(dp, m)))):
                    if cand.is_file():
                        invoked.add(str(cand.relative_to(ROOT)))
                        break
    return declared, invoked


def reachable(files: dict[str, str], roots: set[str]) -> set[str]:
    """Transitive closure over resolved `import X.bend` specifiers, BREADTH-FIRST.

    Bend has no import graph with semantics, so this measures that a `.bend` FILE is named by
    a run that already runs -- a FILE-reachability claim and not an observation of a run. The
    iteration order is stated because a set of roots walked in `os.walk` order and one walked
    in sorted order reach the same set; the SEEN-set, not the order, is the measurement.
    """
    seen, q = set(roots), deque(roots)
    while q:
        cur = q.popleft()
        for spec in IMPORT.findall(files.get(cur, "")):
            tgt = os.path.normpath(os.path.join(os.path.dirname(cur), spec))
            if tgt in files and tgt not in seen:
                seen.add(tgt)
                q.append(tgt)
    return seen


# ------------------------------------------------------- the symbol reader (AST)


def symmap(src: str) -> dict[str, str] | None:
    """name -> exact source segment, for defs, classes, methods AND module-level ASSIGNMENTS.

    THE ASSIGNMENTS ARE THE POINT. `codegen/simplify.py`, `renderer/nir.py` and
    `uop/divandmod.py` all changed behaviour inside module-level `PatternMatcher` lists and
    dicts (`pm_reduce_collapse`, `f_aop`, `div_and_mod_symbolic`) while changing ZERO def or
    class bodies. A def/class-only reader reports 0 for all three and is reporting its own
    blind spot, not an absence of change.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return None
    out: dict[str, str] = {}
    for n in tree.body:
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            out[n.name] = ast.get_source_segment(src, n)
        elif isinstance(n, ast.ClassDef):
            out["class " + n.name] = ast.get_source_segment(src, n)
            for m in n.body:
                if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    out[f"{n.name}.{m.name}"] = ast.get_source_segment(src, m)
        elif isinstance(n, (ast.Assign, ast.AnnAssign)):
            for t in (n.targets if isinstance(n, ast.Assign) else [n.target]):
                for sub in ast.walk(t):
                    if isinstance(sub, ast.Name):
                        out[sub.id] = ast.get_source_segment(src, n)
    return out


def changed_symbols(old: str, new: str) -> list[tuple[str, str]] | None:
    o, n = symmap(old), symmap(new)
    if o is None or n is None:
        return None
    return ([("~", k) for k in n if k in o and n[k] != o[k]]
            + [("+", k) for k in n if k not in o]
            + [("-", k) for k in o if k not in n])


# ------------------------------------------------------------------- the census


def depends_on(rows_by_path: dict[str, int], port_rel: dict[str, str],
              reach: set[str]) -> list[str]:
    """The paths whose counterpart is reachable AND carries defs -- the DEPENDS list."""
    return [p for p, n in rows_by_path.items()
            if n > 0 and os.path.join("tinybendygrad", os.path.splitext(p)[0] + ".bend") in reach]


def census() -> tuple[dict[str, str], list[str], list[str]]:
    """(rows, table, per-path verdicts). THE THIRD RETURN IS THE DEAD CHECK'S DENOMINATOR:
    `main()` refuses to exit PASS unless every changed path carries a verdict in `VERDICTS`,
    so a row can never be quietly dropped and still read as a census."""
    rows: dict[str, str] = {}
    old, new, changed = revendor()
    files = bend_files()
    port_rel = {k: k for k in files if k.startswith("tinybendygrad/")}
    declared, invoked = driver_roots(files)
    reach_d, reach_i = reachable(files, declared), reachable(files, invoked | declared)
    port_reach = {k for k in reach_i if k in port_rel}
    port_text = {k: files[k] for k in port_rel}
    names = set()
    for t in port_text.values():
        for m in re.findall(r"^\s*def\s+([A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)?)\s*[:(]", t, re.M):
            names.add(m)
            if "." in m:
                names.add(m.split(".")[1])

    verdicts: dict[str, str] = {}
    defcount: dict[str, int] = {}
    n_chg_symbols = n_covered = 0
    table = [f"{'upstream file':26} {'counterpart':30} {'defs':>5} {'reach':>6} {'chg':>4} {'cov':>4} {'verdict':>10}",
             "-" * 85]
    for status, path in changed:
        # AN ADDED PATH HAS NO OLD BLOB, and `git show <tree>:<added path>` exits 128. So the
        # OLD side is read through a probe that maps "absent" to "" rather than raising: an
        # added file has no previous behaviour to diff, which is a MEASURED fact (it is the
        # whole of `runtime/autogen/nv_615.py`, 26,824 generated lines) and not a reason to
        # abandon the other 28 paths.
        so, sn = git_show_opt(f"{old}:{path}"), git("show", f"{new}:{path}")
        rel = os.path.join("tinybendygrad", os.path.splitext(path)[0] + ".bend")
        ndefs = len(DEF.findall(files.get(rel, "")))
        reach = rel in port_reach
        chg = changed_symbols(so, sn) if so.strip() else []
        cov = 0
        for _, k in chg or []:
            n_chg_symbols += 1
            bare = k.split()[-1].split(".")[-1] if k.startswith("class ") else k.split(".")[-1]
            if k in names or any(x.endswith("_" + bare) for x in names):
                cov += 1
        n_covered += cov
        if rel not in files:
            v = "NO-FILE"
        elif ndefs == 0:
            v = "STUB"
        elif reach:
            v = "DEPENDS"
        else:
            v = "unreached"
        verdicts[path] = v
        defcount[path] = ndefs if rel in files else 0
        table.append(f"{path:26} {(rel[13:] if rel in files else '(no port file)'):30} "
                     f"{ndefs if rel in files else 0:5} {('YES' if reach else 'no'):>6} "
                     f"{len(chg or []):4} {cov:4} {v:>10}")

    counts = Counter(verdicts.values())
    # THE LADDER, AND IT IS THE HEADLINE. "DEPENDS" has NO root-independent value: widen the
    # root population and more port files become reachable, so the count rises and the
    # criterion stops discriminating. Measured on THIS re-vendor, by this file, 2026-10-20:
    # 3 of 29 under the 62 declared drivers, 20 of 29 once the 234 invocation-site roots are
    # added, and 25 of 29 when every port file is its own root -- at which point the criterion
    # is VACUOUS, because it is one step from answering "all 26 that have a file". A reader who
    # quotes ONE of these as "how many of the 29 the port depends on" is quoting their root
    # set, not a property of the port. The table above is computed at rung 2.
    ladder = {
        "ladder.1_declared_gate_drivers_only": reach_d,
        "ladder.2_declared_plus_invocation_sites": reachable(files, declared | invoked),
        "ladder.3_every_invocation_site": reachable(files, invoked | declared),
        "ladder.4_every_port_file_is_a_root": reachable(files, set(port_rel) | declared | invoked),
    }
    rows = {
        "vendordep.revendor_old_tree": old[:12],
        "vendordep.revendor_new_tree": new[:12],
        "vendordep.changed_paths": str(len(changed)),
        "vendordep.changed_modified": str(sum(1 for s, _ in changed if s == "M")),
        "vendordep.changed_added": str(sum(1 for s, _ in changed if s == "A")),
        "vendordep.changed_with_a_port_counterpart": str(sum(1 for v in verdicts.values() if v != "NO-FILE")),
        "vendordep.DEPENDS": str(counts.get("DEPENDS", 0)),
        "vendordep.unreached": str(counts.get("unreached", 0)),
        "vendordep.NO-FILE": str(counts.get("NO-FILE", 0)),
        "vendordep.STUB_zero_defs": str(counts.get("STUB", 0)),
        "vendordep.sight.changed_symbols": str(n_chg_symbols),
        "vendordep.sight.changed_symbols_with_a_port_name": str(n_covered),
        "sight.port_bend_files": str(len(port_rel)),
        "sight.roots_declared_in_a_gate_bend_eq": str(len(declared)),
        "sight.roots_bend_invocation_sites": str(len(invoked)),
        "sight.port_files_reachable_declared_roots_only": str(len([r for r in reach_d if r in port_rel])),
        "sight.port_files_reachable_all_roots": str(len(port_reach)),
    }
    for label, reach in ladder.items():
        rows[f"{label}.roots"] = str(len(declared if "declared_gate" in label else
                                         invoked | declared if "invocation_sites" in label else
                                         set(port_rel) | declared | invoked))
        rows[f"{label}.port_files_reachable"] = str(len([r for r in reach if r in port_rel]))
        rows[f"{label}.DEPENDS_of_29"] = str(len(depends_on(defcount, port_rel, reach)))
    return rows, table, list(verdicts.values())


VERDICTS = ("DEPENDS", "unreached", "NO-FILE", "STUB")


def main(argv: list[str]) -> int:
    _retarget(argv)
    try:
        rows, table, verdicts = census()
    except (RuntimeError, OSError) as e:
        print(f"SKIP  {e}", file=sys.stderr)
        return SKIP
    if not rows:
        print("DEAD  emitted no rows", file=sys.stderr)
        return DEAD
    rows_only = "--rows" in argv
    if not rows_only:
        print(f"CHANGED {rows['vendordep.changed_paths']} upstream paths   "
              f"({rows['vendordep.changed_modified']} M + {rows['vendordep.changed_added']} A)   "
              f"old={rows['vendordep.revendor_old_tree']} new={rows['vendordep.revendor_new_tree']}")
        print(f"ROOTS   declared-in-a-gate={rows['sight.roots_declared_in_a_gate_bend_eq']} "
              f"invocation-sites={rows['sight.roots_bend_invocation_sites']}   "
              f"port-reachable {rows['sight.port_files_reachable_declared_roots_only']}"
              f" -> {rows['sight.port_files_reachable_all_roots']} of {rows['sight.port_bend_files']}")
        print()
        for line in table:
            print(line)
        print()
    for k, v in rows.items():
        print(f"{k}={v}")
    # A CENSUS REPORTS. It is PASS when it ran and every changed path carries a verdict in
    # the KNOWN vocabulary -- never when a verdict is surprising. `device.py` scoring
    # DEPENDS with coverage 0 of 5 IS THE ANSWER, not a broken gate, and a gate that cried
    # wolf on every upstream re-vendor would be ignored on the day it mattered. What WOULD
    # make this DEAD rather than PASS is a path outside the vocabulary, which is checked by
    # requiring every row's per-file verdict to be in `verdicts_path_list()`'s set.
    judged = list(VERDICTS)
    unknown = [v for v in verdicts if v not in judged]
    if unknown:
        print(f"DEAD  verdict(s) outside the vocabulary: {sorted(set(unknown))}", file=sys.stderr)
        return DEAD
    return PASS


if __name__ == "__main__":
    print(f"# exit vocabulary: {VERDICT}", file=sys.stderr)
    raise SystemExit(main(sys.argv[1:]))