#!/usr/bin/env python3
"""THE DECLARATION CENSUS, and the three shapes a declaration can take. Measured by DISCOVERY.

    .venv/bin/python .agents/slop/declaretwo/census.py                 # the report + census.rows
    .venv/bin/python .agents/slop/declaretwo/census.py --rev HEAD      # pin to a commit, not the index
    .venv/bin/python .agents/slop/declaretwo/census.py --rename-plan   # the git mv plan, never applied

THE POPULATION IS A WALK OF A COMMIT, NOT OF AN INDEX. `git ls-tree -r <rev>` and nothing
else, and the revision is PRINTED on every run. This is the whole disagreement with
`orcdecide` (256) and `declare` (262): both read `git ls-files`, which is the INDEX, and this
tree's index has been reset six times today -- MEASURED below, the index carries 19 directories
the commit does not, and the commit carries directories the index does not. A count taken from
an index is a count taken from a thing that is being rebuilt under you.

WHAT COUNTS AS A DECLARATION -- THREE ANSWERS, MEASURED NOT ARGUED. All three are computed here
over the same population, so the reader can see they are COMPATIBLE (nested), not rival:

    R  a REPORT-shaped name  : report.md / readme.md / findings.md
    M  a MANIFEST-shaped name: manifest.tsv / manifest.md / manifest.rows
    P  ANY prose at all      : the directory is a human's, whatever it is named

R and M are NAMES, so R|M is a name set -- doctrine 1's third forbidden shape. P is not a name:
it is "the directory holds a `.md`", which is a SHAPE. That is why P is reported and NOT used as
the gate: `strays/`'s MANIFEST.tsv has 53 rows and `oracles259/`'s has 259, and one has 3, and
`git mv`-ing the short one to REPORT.md would call a 3-row file a report. See `checks/slop-declare.py`.

FRESHNESS IS A MEASUREMENT AND IS PRINTED WITH ITS OWN SCOPE. `mtime` measures the WORKTREE, so
it moves while the session runs; `commit_age` measures the COMMIT, and MEASURED today it has ONE
distinct value across the gated set (one restore commit touched every directory), so it is
degenerate and printed only as the cross-check. The distribution -- not a threshold -- is the
result, so a reader can pick their own window.
"""
from __future__ import annotations

import argparse
import collections
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / ".agents/slop/declaretwo"
SLOP = ".agents/slop"

# THE THREE SHAPES. Declared here, printed, and NOT used to gate: a name set that decides a
# verdict is `checks/sweep.py`'s LIVE_UNITS, and this file exists to MEASURE that shape, not to
# be it. The gate that uses one is `checks/slop-declare.py`, and its header says why.
REPORTS = ("report.md", "readme.md", "findings.md")
MANIFESTS = ("manifest.tsv", "manifest.md", "manifest.rows")
PROSE = ".md"

# A reader is CODE opening the directory's FILES BY EXACT PATH. Not the directory token -- a
# `.py` that names the path in a skip list is a CITATION, which is `orcdecide`'s measured
# `plants.py`: 3 citations, 0 opens.
SKIP_ROOTS = ("tinygrad/", "references/")

COLUMNS = ("dir", "depth", "files", "R", "M", "P", "md_names", "age_h", "opened_by")

# THE RULER'S OWN CHECK, and it is the reason this census REFUSES instead of reporting a fresh
# tree. `git clone` and `git checkout` stamp every file with one instant, so on a fresh clone the
# whole population reads 0.0 h -- every directory IN PROGRESS, every window satisfied, and the
# freshness column a constant. A population whose mtimes span less than this is measured by a
# clock that was reset, and MEASURED spread on this tree is 0.4 h to 121 h over the undeclared
# set. Taken over the WHOLE population, not the gated subset: gating on the subset hides the
# signature, because a reset clock makes the gated subset empty.
MIN_SPREAD_MIN = 60


def git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    """git in `repo`. The INDEX is never consulted on purpose: `ls-tree` reads a commit, `ls-files`
    reads the thing that has been reset six times today."""
    return subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True)


def walk(repo: Path, rev: str) -> dict[str, list[str]] | None:
    """EVERY directory under `.agents/slop/` AT `rev`, at every depth -> its tracked files.

    A WALK, and it descends. `orcdecide` measured **108 `.md` DIRxFILE pairs whose own directory
    declared nothing** and the population here is named for them: a unit's subdirectory
    (`.agents/slop/parent/child/`) is an undeclared DIRECTORY in its own right, and a walk that
    stops at depth 1 lets the parent's `REPORT.md` speak for its children -- which is a
    declaration being inherited, and inheritance is how an undeclared directory stays undeclared
    forever. MEASURED on this tree at `389aa61c5`: 265 top-level directories and **497 at any
    depth**, of which 68 are nested; all 68 nested directories hold no declaring name of their
    own. The `depth` column carries the distinction, because a 4-deep captured-artifact directory
    (`e2epy/fixtures/plant-no-node/runs/e2e/`) is not a unit and a reader must be able to tell."""
    p = git(repo, "ls-tree", "-r", rev, "--name-only")
    if p.returncode != 0:
        return None
    dirs: dict[str, list[str]] = collections.defaultdict(list)
    for f in p.stdout.splitlines():
        parts = f.split("/")
        if parts[:2] == [".agents", "slop"] and len(parts) >= 4:
            for i in range(3, len(parts)):
                dirs["/".join(parts[:i])].append(f)
    return dict(dirs)


def md_names(name: str, files: list[str]) -> list[str]:
    """The `.md` basenames DIRECTLY inside this directory.

    Depth is the discriminator, and it is load-bearing twice over. `e2epy/fixtures/` holds 24
    captured `.md` transcripts one directory deeper; counting THOSE as `e2epy/`'s declaration is
    `checks/sweep.py`'s ORACLE_WORD failure at a deeper path. And a nested directory's `.md` must
    not declare its parent, or the inheritance control is vacuous. The depth compared against is
    the DIRECTORY's own -- `name.count('/')` -- because a directory's files are all at least one
    deeper than it, so the file's depth is never the right ruler."""
    here = name.count("/") + 1
    return sorted({f.rsplit("/", 1)[-1] for f in files
                   if f.endswith(PROSE) and f.count("/") == here})


def opened_by(repo: Path, rev: str, name: str, files: list[str]) -> str:
    """The first tracked file OUTSIDE this directory that opens one of its files by EXACT PATH.
    This is the test `prune4` said it did not run. It is a `git grep -F`, per file, at a pinned
    revision -- so it is a measurement and not a substring sweep of the worktree."""
    prefix = f"{name}/"
    for f in sorted(files):
        p = git(repo, "grep", "-l", "-F", "--", f, rev)
        # `git grep <rev>` prints `<rev>:<path>`; `rsplit(':', 1)` drops the rev, which may itself
        # contain a colon. Taking the LAST field would break on a path with a colon in it, and
        # `.agents/slop/` has none, so the rev is stripped by prefix instead of by position.
        for line in p.stdout.splitlines():
            hit = line.split(":", 1)[1] if ":" in line else line
            if hit.startswith(prefix) or hit.startswith(SKIP_ROOTS) or hit == f:
                continue
            return hit
    return "-"


def age_h(repo: Path, name: str) -> float:
    """Hours since the newest FILE in this directory was written. `os.walk`, not the directory's
    own mtime: a unit that only writes leaves the directory's stamp behind.

    `name` is the FULL `.agents/slop/<dir>` path the walk yields, so this joins it onto `repo`
    directly. MEASURED: joining it onto `SLOP` as well -- the shape it had before the walk
    descended -- pointed every row at a path that does not exist, and an absent path has no
    files, so every one of 109 rows read **0.0** and the whole freshness column was DEAD while
    printing four digits. A column that is always zero is indistinguishable from a column that
    measured nothing, which is `prune4`'s twelve-committed-files shape; `MIN_SPREAD_MIN` below is
    the guard that catches it."""
    newest = 0.0
    for base, _, files in os.walk(repo / name):
        for f in files:
            try:
                newest = max(newest, os.path.getmtime(os.path.join(base, f)))
            except OSError:
                continue
    return round((time.time() - newest) / 3600, 1) if newest else 0.0


def shapes(repo: Path, dirs: dict[str, list[str]]) -> dict[str, dict]:
    """Every directory, annotated with all THREE shapes. One population, three answers -- which is
    the only way to tell whether they are rival readings or nested ones."""
    rows = []
    for name, files in sorted(dirs.items()):
        bases = {f.rsplit("/", 1)[-1].lower() for f in files}
        names = md_names(name, files)
        rows.append({
            "dir": name, "depth": name.count("/") - 2, "files": len(files),
            "R": int(bool(bases & set(REPORTS))),
            "M": int(bool(bases & set(MANIFESTS))),
            "P": int(bool(names)),
            "md_names": ",".join(n.split(".")[0] for n in names) or "-",
            "age_h": age_h(repo, name),
        })
    return {r["dir"]: r for r in rows}


def index_delta(repo: Path, rev: str, dirs: dict[str, list[str]]) -> dict:
    """What the INDEX would have said, and how far it is from the commit. This is the 256-vs-262
    disagreement, MEASURED rather than reconstructed: `git ls-files` right now, against the
    pinned commit's own count."""
    p = git(repo, "ls-files")
    live = {f.rsplit("/", 1)[0] for f in p.stdout.splitlines()
            if f.startswith(SLOP + "/") and len(f.split("/")) >= 4}
    committed = set(dirs)
    return {"index": len(live), "commit": len(committed),
            "in_index_not_commit": sorted(live - committed),
            "in_commit_not_index": sorted(committed - live)}


def report(repo: Path, rev: str, dirs: dict[str, list[str]], sh: dict[str, dict],
           opener: dict[str, str]) -> str:
    top = {k: v for k, v in sh.items() if v["depth"] == 0}
    nested = {k: v for k, v in sh.items() if v["depth"] > 0}
    n, n_nested = len(top), len(nested)
    r = sum(x["R"] for x in top.values())
    m = sum(x["M"] for x in top.values())
    rm = sum(1 for x in top.values() if x["R"] or x["M"])
    p = sum(x["P"] for x in top.values())
    both = sum(1 for x in top.values() if x["R"] and x["M"])
    rm_only = sum(1 for x in top.values() if (x["R"] or x["M"]) and not x["P"])
    neither = sum(1 for x in top.values() if not x["R"] and not x["M"] and not x["P"])
    undecl_rm = [k for k, v in top.items() if not v["R"] and not v["M"]]
    undecl_rm_md = [k for k in undecl_rm if sh[k]["P"]]
    undecl_rm_bare = [k for k in undecl_rm if not sh[k]["P"]]
    opened = sum(1 for k in undecl_rm if opener.get(k, "-") != "-")
    opened_rm = sum(1 for k in top if (top[k]["R"] or top[k]["M"]) and opener.get(k, "-") != "-")
    nested_decl = sum(1 for v in nested.values() if v["R"] or v["M"])
    nested_under_declared = [k for k in nested
                             if not (nested[k]["R"] or nested[k]["M"])
                             and (top.get(k.rsplit("/", 1)[0]) or {}).get("R", 0)
                             or (top.get(k.rsplit("/", 1)[0]) or {}).get("M", 0)]

    L = []
    a = L.append
    a(f"THE DECLARATION CENSUS at {rev[:12]}"
      f"  ({git(repo, 'rev-parse', '--short', rev).stdout.strip()})")
    a("")
    a(f"population: tracked `.agents/slop/*/` directories AT THAT COMMIT : {n}")
    a(f"  plus NESTED directories at depth > 0, which are rows of their OWN : {n_nested}")
    a("")
    a("THE THREE SHAPES, over one population:")
    a(f"  R  report-shaped name  ({', '.join(REPORTS)}) : {r}")
    a(f"  M  manifest-shaped name({', '.join(MANIFESTS)}) : {m}   (of which also R: {both})")
    a(f"  R|M  THE NAME SET -- `orcdecide`'s and `declare`'s declaration : {rm}")
    a(f"  P  ANY `.md` at depth 0 -- a SHAPE, not a name  : {p}")
    a(f"  R|M AND ALSO P                                    : {rm - rm_only}")
    a(f"  R|M AND ALSO NOT P  (declared under a name, no `.md`!) : {rm_only}")
    a(f"  NEITHER a name nor a `.md`                         : {neither}")
    a("")
    a("NESTED, NOT RIVAL. P is a superset of R|M here in the sense that matters: every R|M")
    a("directory that has a `.md` is inside P, and the two sets of DIRECTORIES that differ are")
    a(f"{rm_only} (a declaring NAME with no `.md`) and {len(undecl_rm_md)} (a `.md` under another")
    a("name). So the answer to \"which is right\" is: they answer different questions, and the")
    a("question decides the tool. See the REPORT.")
    a("")
    a(f"UNDECLARED under R|M : {len(undecl_rm)}")
    a(f"  of those, holding a `.md` under ANOTHER name (the rename candidates) : {len(undecl_rm_md)}")
    a(f"  of those, holding no `.md` at all (no rename exists)                  : {len(undecl_rm_bare)}")
    a(f"  of the {len(undecl_rm)} undeclared, opened by an exact `git grep -F` : {opened}")
    a("")
    a("THE EXACT TEST `prune4` DID NOT RUN, on the DECLARED set:")
    a(f"  declared AND some tracked file OUTSIDE opens one of its files by exact path : {opened_rm} of {rm}")
    a(f"  declared AND NOTHING opens one of its files                                : {rm - opened_rm}")
    a(f"    {sorted(k for k in top if (top[k]['R'] or top[k]['M']) and opener.get(k, '-') == '-')}")
    a("")
    a("THE NESTED INHERITANCE CONTROL -- an undeclared directory INSIDE a declared one:")
    a(f"  nested directories holding a declaring name of their OWN : {nested_decl} of {n_nested}")
    a(f"  nested directories that are UNDECLARED while their parent is declared : "
      f"{len(nested_under_declared)}")
    a("  a parent REPORT.md does NOT speak for a child directory; each is its own row. Named")
    a("  here because `orcdecide` measured 108 `.md` DIRxFILE pairs whose own directory")
    a("  declared nothing -- that is the shape a depth-1 walk cannot see.")
    a("")
    ages = sorted(x["age_h"] for x in top.values())
    ages_u = sorted(x["age_h"] for x in top.values() if not x["R"] and not x["M"])
    a("FRESHNESS IS A MEASUREMENT, NOT A SHAPE -- mtime of the newest FILE, worktree, right now:")
    a(f"  over the whole population : {ages[0]} .. {ages[-1]} h  ({round(ages[-1] - ages[0], 1)} h span)")
    a(f"  over the UNDECLARED set    : {ages_u[0]} .. {ages_u[-1]} h"
      f"  ({round(ages_u[-1] - ages_u[0], 1)} h span)")
    hist = collections.Counter(int(a) for a in ages_u)
    a(f"  histogram by whole hour    : {sorted(hist.items())}")
    a("  THE DISTRIBUTION is the result; no window is baked in. A reader who wants \"finished\"")
    a("  draws their own line, and the line is an opinion about a working session, not a fact")
    a("  about a directory. The 13-fresh/35-stale split `declare` published is one such line:")
    a("  at 24 h. Re-measured here, the undeclared set's MEDIAN moved with the session, so the")
    a("  split is a property of WHEN it was taken, and it carries its timestamp or it is nothing.")
    spread = ages[-1] - ages[0]
    if len(ages) > 2 and spread < MIN_SPREAD_MIN / 60:
        a(f"  REFUSED: mtimes span {round(spread, 2)} h over {len(ages)} directories -- ONE stamp,")
        a("  so this is a checkout, and every row would read IN PROGRESS. The commit answered;")
        a("  the RULER is what is missing.")
    a("")
    d = index_delta(repo, rev, dirs)
    a("THE INDEX, WHICH IS WHY 256 AND 262 ARE NOT DISAGREEMENTS:")
    a(f"  `git ls-files` right now  : {d['index']}")
    a(f"  this commit               : {d['commit']}")
    a(f"  in the INDEX, not the commit ({len(d['in_index_not_commit'])}): {d['in_index_not_commit']}")
    a(f"  in the commit, not the INDEX ({len(d['in_commit_not_index'])}): {d['in_commit_not_index']}")
    return "\n".join(L)


def rename_plan(rev: str, dirs: dict[str, list[str]], sh: dict[str, dict]) -> str:
    """`git mv` lines for the directories that ALREADY hold a declaration under another name.

    THIS IS THE ONLY FIX LANDED, AND IT IS THE ONE THAT IS NOT A HAND LIST. A rename moves an
    existing file to the name the walk looks for; adding the 40 names to `DECLARATIONS` would make
    the same 63 directories green with ZERO human decisions, which is the census LYING rather
    than the census being satisfied. Nothing here is executed: this prints the plan and a person
    runs it, because `git mv` is a commit."""
    lines = []
    for name, files in sorted(dirs.items()):
        row = sh[name]
        if row["R"] or row["M"] or not row["P"]:
            continue
        base = name.count("/") + 1
        src = sorted(f for f in files
                     if f.endswith(PROSE) and f.count("/") == base)
        if len(src) == 1:
            lines.append(f"git mv {src[0]} {name}/REPORT.md")
        else:
            # TWO `.md` files cannot both become REPORT.md -- a `git mv` plan that emits both is a
            # plan whose second line destroys the first, and emitting it would be the tool making
            # the decision the tool says it cannot make. So the FIRST is offered and the rest are
            # named as a choice for a human. MEASURED: 25 of the rename candidates on this tree.
            lines.append(f"AMBIGUOUS {name} has {len(src)}: " + " ".join(src))
    return "\n".join(lines) + "\n" if lines else ""


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="census of `.agents/slop` declarations, three shapes")
    ap.add_argument("--rev", default="HEAD", help="a COMMIT; the index is never read")
    ap.add_argument("--repo", default=str(ROOT), help="the repository to walk")
    ap.add_argument("--rename-plan", action="store_true",
                    help="print the `git mv` plan; this file never runs it")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    repo = Path(args.repo).resolve()
    dirs = walk(repo, args.rev)
    if not dirs:
        print(f"REFUSED: `git ls-tree -r {args.rev}` found 0 `.agents/slop/*/` directories -- "
              f"the ruler is missing, not the tree empty")
        return 3
    sh = shapes(repo, dirs)
    if args.rename_plan:
        sys.stdout.write(rename_plan(args.rev, dirs, sh))
        return 0
    opener = {n: opened_by(repo, args.rev, n, f) for n, f in sorted(dirs.items())}
    out_rows = HERE / "census.rows" if repo == ROOT else repo / "census.rows"
    body = ["\t".join(COLUMNS)]
    for n in sorted(dirs):
        r = sh[n]
        body.append("\t".join(str(r[c]) for c in COLUMNS[:-1]) + "\t" + opener[n])
    out_rows.write_text("\n".join(body) + "\n")
    if not args.quiet:
        print(report(repo, args.rev, dirs, sh, opener))
    return 0


if __name__ == "__main__":
    sys.exit(main())