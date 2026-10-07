#!/usr/bin/env python3
"""Every tracked `.agents/slop/*/` directory, and whether it DECLARES ITSELF.

    .venv/bin/python checks/slop-declare.py            # the report + the rows
    .venv/bin/python checks/slop-declare.py --quiet    # the exit status only

WHAT IT CLAIMS, IN THE FIVE VERDICTS' WORDS (`AGENTS.md`):

    PASS     no tracked `.agents/slop/*/` directory is STALE-undeclared-and-unread beyond the
             baseline taken 2026-10-07 (`BASELINE.tsv`, beside this file, loaded by path)
    FAIL     one is -- a unit left a directory that declares nothing and that nothing opens
    REFUSED  the walk could not measure: `git ls-files` did not answer
    DEAD     it answered a population of 0 -- the shape `checks/sweep.py`'s `LIVE_UNITS` had

WHAT IT CANNOT SEE, AND MUST NOT BE READ AS SEEING. This is the ceiling, and it is why the gate
is a RATCHET and not an audit:

  * IT DETECTS ABSENCE. It cannot tell an ABSENT declaration from an UNWRITTEN one, and it
    cannot author either -- **a `REPORT.md` is a human artifact and no walk can write one.**
  * IT CANNOT JUDGE WHETHER A DECLARATION IS TRUE. `.agents/slop/citeresolve/` measured
    **2 448 committed prose `<path>:<N>` claims, 165 unresolved and 1 777 never positively
    checked, including essentially every `REPORT.md` written that night.** So a `REPORT.md` is
    not a checked claim: it is an UNCHECKED ONE THAT HAS A FILENAME, and this walk counting it
    as "declared" is counting a filename, not a fact.
  * A `MANIFEST.tsv` IS NOT A DECLARATION BY PRESENCE. `.agents/slop/strays/MANIFEST.tsv`
    (53 rows of `verdict`/`why`/`restore`) is what let `prune3` audit a directory with no
    report; `.agents/slop/oracles259/MANIFEST.tsv` (259 rows) is the same shape. That is the
    precedent, and it is also the limit: this walk checks that a manifest EXISTS and never
    opens one, because only the unit that wrote it knows what its rows mean.

THE POPULATION IS A WALK, NOT A LIST. Every directory is discovered from `git ls-files` and
nothing here names a `.agents/slop/*/` directory. An instrument that cannot see its population
cannot be wrong, because it cannot be anything (`AGENTS.md` doctrine 1) -- and the alternative
was demonstrated this session: `checks/sweep.py`'s `LIVE_UNITS` was 14 literal names, and the
six FINISHED units they omitted held 2 353 files, 53% of `.agents/slop`, tracked and unnamed.

READERS ARE FOUND BY FULL PATH, AND PROSE IS COUNTED IN ITS OWN COLUMN. `census.json` is a
dozen strings to a basename join; so is `plants.py`. So a reader is a tracked CODE file outside
the directory whose bytes contain `.agents/slop/<dir>/`. A `.md` that merely NAMES the
directory is not a reader, it is prose about one -- and letting prose silence the walk is how a
report about a directory becomes the directory's liveness.

THE PLANT EXCLUDES ITSELF, LOADED BY PATH. This file's evidence directory holds a plant whose
fixture bytes ARE `.agents/slop/<dir>/` paths, and a plant that names the population under test
is a plant that moves the answer it measures. `plant_exclusions()` loads
`.agents/slop/declare/plant.py:excluded()` by path -- the same shape as
`checks/oracle-txt-census.py` loading `.agents/slop/oracletxt/plant.py:excluded()` -- so the
exclusion follows the plant if it moves, and there is no second copy here to rot.

THE RATCHET, AND WHY IT IS NOT RED AT REST. A walk that REQUIRES a declaration is a gate that
is red from birth: 107 of 257 tracked directories declare nothing today, and turning that into
green is 107 human decisions no walk can make. `AGENTS.md`: "A PRE-COMMIT GATE THAT CANNOT
PASS TEACHES NOTHING AND WILL BE SKIPPED." So this gate keeps the claim it can actually keep --
**the set did not GROW** -- against `BASELINE.tsv`. A baseline name LEAVING is the gate
working, so shrinkage is reported and never punished; a new name appearing and ageing out is a
FAIL.

FRESHNESS IS A COUNT, NOT A VERDICT, AND IT IS ALWAYS PRINTED BESIDE IT. A directory whose
newest commit is younger than `GRACE_HOURS` is IN PROGRESS: named, counted, printed, and never
a FAIL -- because a unit's first minute IS a directory with no report yet, and a gate that goes
red there flags every unit that ever runs. `SKIP IS NOT PASS`, so `IN PROGRESS n` is printed
next to `UNDECIDED n` and is never summed into it.

THE CLOCK IS MTIME, AND MEASURED, NOT ASSUMED. Two clocks exist and they disagree here:

  * COMMIT age (`git log -1 -- <dir>`) is durable and is kept as the cross-check column -- but
    `813bbec3e` (2026-10-07 00:45, "RESTORE 6141 FILES DELETED BY THE JJ INDEX WIPE") touched
    **every** `.agents/slop/*/` directory in one commit, so on this tree today commit age has
    **ONE distinct value (5.3 h) across all 48 undeclared-and-unread directories.** An axis with
    one value is not an axis: it would call every one of them fresh and the gate would be green
    for the wrong reason. `commit_age_h` exists so that degeneracy stays visible.
  * MTIME has **46 distinct values spanning 5.7 h to 108 h** on the same 48, so it discriminates.

mtime's weakness is the mirror image: `git clone` and `git checkout` stamp every file with the
checkout instant, so on a fresh clone all 257 would read as fresh. So the clock is guarded too --
if the mtimes of the gated population span less than `MIN_SPREAD_MIN`, the ruler has been reset
and the walk **REFUSES** rather than reporting everything in progress.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SLOP = ".agents/slop"
HERE = ROOT / SLOP / "declare"

# A declaration is a FILE WHOSE NAME SAYS SO. This is a name set, not a population: the
# population is the walk below, and this only asks whether any directory carries one.
DECLARATIONS = ("report.md", "readme.md", "findings.md", "manifest.tsv", "manifest.rows")

# A reader is CODE. `.md` is prose about a directory; `.rows`/`.tsv`/`.json`/`.out` are
# snapshots of one, and a snapshot that lists every path is `sweep.py`'s `ORACLE_WORD` failure
# at a larger scale: 670 of 675 oracle files classified by NAME.
CODE = (".py", ".sh", ".bend", ".mjs", ".ts", ".js", ".rs")
PROSE = (".md", ".rows", ".tsv", ".json", ".out", ".err")

# MEASURED 2026-10-07 on the 48 undeclared-and-unread directories: 13 are inside 24 h and 35
# are outside, spread 5.7 h to 108 h. 24 h is one working day -- long enough that a unit which is
# going to write a report has, short enough that a unit which crashed does not sit inside the
# window for a week. Both numbers move while the session runs; re-measure with `--baseline`.
GRACE_HOURS = 24

# The ruler's own check. A checkout stamps every mtime with one instant, so a population whose
# mtimes span less than an hour is a population measured by a clock that was reset. MEASURED:
# 102 h of spread today, and 0 on a fresh clone.
MIN_SPREAD_MIN = 60

DIR_TOKEN = re.compile(re.escape(SLOP) + r"/([\w.+-]+)/")
COLUMNS = ("dir", "files", "declared", "code_readers", "prose_mentions", "age_h", "commit_age_h")


def git(root: Path, *args: str) -> subprocess.CompletedProcess:
    """`git` in `root`, inheriting the environment -- so an exported `GIT_INDEX_FILE` is
    honoured by construction rather than by a parameter a caller has to remember to pass."""
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True)


def plant_exclusions() -> frozenset[str]:
    """The directory prefixes this walk's OWN evidence must not be able to cite, loaded by path."""
    plant = HERE / "plant.py"
    if not plant.is_file():
        return frozenset()
    spec = importlib.util.spec_from_file_location("slop_declare_plant", plant)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return frozenset(mod.excluded())


def tracked(root: Path) -> list[str] | None:
    """Every tracked path, or None if git did not answer. `-z`, so a space in a name is data."""
    p = git(root, "ls-files", "-z")
    if p.returncode != 0:
        return None
    return [f for f in p.stdout.split("\0") if f]


def walk(paths: list[str]) -> dict[str, list[str]]:
    """`.agents/slop/<dir>/` -> its tracked files. A WALK: no directory is named anywhere here."""
    dirs: dict[str, list[str]] = {}
    for f in paths:
        parts = f.split("/")
        if len(parts) >= 4 and parts[:2] == SLOP.split("/"):
            dirs.setdefault(parts[2], []).append(f)
    return dirs


def mentions(root: Path, dirs: dict[str, list[str]], suffixes: tuple[str, ...],
             skip: frozenset[str]) -> dict[str, set[str]]:
    """dir -> the tracked files of these suffixes that NAME it by full path, minus the ones
    inside it. A directory citing itself is not externally referenced, and the suffix set
    decides whether a mention counts as a reader or as prose -- never whether a directory is
    part of the population."""
    out: dict[str, set[str]] = {}
    for f in tracked(root) or []:
        if not f.endswith(suffixes) or any(f.startswith(s) for s in skip):
            continue
        try:
            text = (root / f).read_text(errors="ignore")
        except OSError:
            continue  # tracked but absent from the worktree: it opens nothing
        owner = f.split("/")[2] if f.startswith(SLOP + "/") and len(f.split("/")) > 2 else ""
        for d in set(DIR_TOKEN.findall(text)):
            if d in dirs and d != owner:
                out.setdefault(d, set()).add(f)
    return out


def commit_age_hours(root: Path, name: str) -> float:
    """Hours since the newest commit that touched this directory. git dates nothing -> 0.0, the
    SAFE end of the grace window: a directory git cannot date must not buy itself time. This is
    the CROSS-CHECK column, not the deciding one -- see the header on `813bbec3e`."""
    p = git(root, "log", "-1", "--format=%ct", "--", f"{SLOP}/{name}/")
    try:
        return round((time.time() - int(p.stdout.strip())) / 3600, 1)
    except ValueError:
        return 0.0


def age_hours(root: Path, name: str) -> float:
    """Hours since the newest FILE in this directory was written. `os.walk`, not `stat` on the
    directory: a directory's own mtime moves when an entry is added or removed, and a unit that
    only writes is not the shape that matters."""
    newest = 0.0
    for base, _, files in os.walk(root / SLOP / name):
        for f in files:
            try:
                newest = max(newest, os.path.getmtime(os.path.join(base, f)))
            except OSError:
                continue
    return round((time.time() - newest) / 3600, 1) if newest else 0.0


def baseline() -> set[str]:
    """The names this gate is on the hook for, loaded BY PATH from the rows beside it. A second
    copy typed into this module would be `differ.declared()` inverted: a population this file
    OWNS instead of one it MEASURES. Absent baseline = every stale name is a FAIL, which is the
    honest reading of "no baseline, no claim"."""
    rows = HERE / "BASELINE.tsv"
    if not rows.is_file():
        return set()
    return {l.split("\t")[0] for l in rows.read_text().splitlines()
            if l.strip() and not l.startswith("dir\t")}


def survey(root: Path) -> dict:
    """Every measurement this file makes."""
    paths = tracked(root)
    if paths is None:
        return {"error": "`git ls-files` did not answer"}
    dirs = walk(paths)
    if not dirs:
        return {"error": "the walk found 0 tracked `.agents/slop/*/` directories"}
    skip = plant_exclusions()
    code = mentions(root, dirs, CODE, skip)
    prose = mentions(root, dirs, PROSE, skip)
    rows = []
    for name, files in sorted(dirs.items()):
        declared = sorted(f.rsplit("/", 1)[-1] for f in files
                          if f.rsplit("/", 1)[-1].lower() in DECLARATIONS)
        age = age_hours(root, name)
        rows.append({"dir": name, "files": len(files),
                     "declared": declared[0] if declared else "-",
                     "declares": bool(declared),
                     "code_readers": len(code.get(name, ())),
                     "prose_mentions": len(prose.get(name, ())),
                     "age_h": age, "commit_age_h": commit_age_hours(root, name),
                     "fresh": age < GRACE_HOURS})
    return {"rows": rows, "dirs": len(dirs), "skip": skip}


def write_rows(surveyed: dict) -> None:
    """The per-directory table beside this file's evidence, so a number in the report has a row."""
    HERE.mkdir(parents=True, exist_ok=True)
    lines = ["\t".join(COLUMNS)]
    lines += ["\t".join(str(r[c]) for c in COLUMNS) for r in surveyed["rows"]]
    (HERE / "declare.tsv").write_text("\n".join(lines) + "\n")


def classify(surveyed: dict) -> dict[str, list[dict]]:
    """The three sets, named. A directory is UNDECLARED when no file in it has a declaring
    NAME; UNREAD among those when no tracked code file outside it opens it by full path; and of
    the unread, FRESH or STALE on the grace window. `declares` is the boolean and `declared` the
    name: asking `not row["declared"]` is `not "-"`, which is `False` -- MEASURED, that made
    `undeclared` empty and PLANT 3b passed VACUOUSLY until PLANT 4b failed."""
    undeclared = [r for r in surveyed["rows"] if not r["declares"]]
    unread = [r for r in undeclared if not r["code_readers"]]
    return {"declared": [r for r in surveyed["rows"] if r["declares"]],
            "undeclared": undeclared,
            "unread_stale": [r for r in unread if not r["fresh"]],
            "unread_fresh": [r for r in unread if r["fresh"]]}


def verdict(surveyed: dict) -> int:
    """THE EXIT. 3 = REFUSED, 5 = DEAD (a population of 0 is a blind walk, and it is DEAD and
    not PASS precisely because it emitted rows), 1 = FAIL, 0 = PASS. Shrinkage is free: a
    baseline name leaving the set is this gate working, so only GROWTH is a failure."""
    if "error" in surveyed:
        dead = "0 tracked" in surveyed["error"]
        print(f"{'DEAD' if dead else 'REFUSED'}: {surveyed['error']}")
        return 5 if dead else 3
    sets = classify(surveyed)
    known = baseline()
    stale = sets["unread_stale"]
    # THE RULER'S CHECK, AND IT IS TAKEN OVER THE WHOLE POPULATION, NOT OVER THE GATED SUBSET.
    # MEASURED, both ways: gating on the subset left a hole -- a fresh clone makes every
    # undeclared directory FRESH, so the gated set is EMPTY, the guard's `if stale` never fires,
    # and the walk answers PASS on a clock that was reset 60 seconds ago. A checkout stamps
    # everything in the tree, so the whole population is where the signature is visible.
    ages = [r["age_h"] for r in surveyed["rows"]]
    if len(ages) > 2 and max(ages) - min(ages) < MIN_SPREAD_MIN / 60:
        print(f"REFUSED: all {len(ages)} directories' mtimes span "
              f"{round(max(ages) - min(ages), 2)} h -- the whole tree carries ONE stamp, so the "
              f"clock is a checkout and every name would read IN PROGRESS. "
              f"`git ls-files` answered, so this is not DEAD; the RULER is what is missing.")
        return 3
    grew = [r for r in stale if r["dir"] not in known and r["dir"] not in surveyed["skip"]]
    print(f"tracked `{SLOP}/*/` directories : {surveyed['dirs']}")
    print(f"  DECLARED (report or manifest)  : {len(sets['declared'])}")
    print(f"  UNDECLARED                     : {len(sets['undeclared'])}"
          f"   -- no full-path CODE reader: "
          f"{len(sets['unread_stale']) + len(sets['unread_fresh'])}")
    print(f"    IN PROGRESS (<{GRACE_HOURS}h mtime, counted, never a verdict) : "
          f"{len(sets['unread_fresh'])}")
    print(f"    STALE (gated)                 : {len(stale)}"
          f"   -- {len(stale) - len(grew)} already in the {len(known)}-name baseline")
    commit_clock = len(set(r["commit_age_h"] for r in stale))
    print(f"  mtimes, whole population         : {round(max(ages) - min(ages), 1)} h span"
          f"   (commit age of the gated set: {commit_clock} distinct value"
          f"{'' if commit_clock == 1 else 's'}"
          f"{' -- DEGENERATE, so the mtime column is the one that decided' if commit_clock == 1 else ''})")
    for r in sets["unread_fresh"]:
        print(f"    ~ {r['dir']:<20} {r['files']:>3} files  {r['age_h']:>6}h mtime  IN PROGRESS")
    if grew:
        print(f"  FAIL  {len(grew)} stale undeclared-and-unread beyond the baseline:")
        for r in grew:
            print(f"    ! {r['dir']:<20} {r['files']:>3} files  {r['age_h']:>6}h mtime")
    else:
        print("  PASS  no stale undeclared-and-unread directory beyond the baseline")
    return 1 if grew else 0


def baseline_rows(surveyed: dict) -> str:
    """The baseline AS TEXT, for `--baseline`. It is never written by this file: a gate that
    rewrites its own baseline can bless whatever it is looking at, which is the same fault as
    `sweep.py`'s `LIVE_UNITS` and as a plant that mutates the population under test. Refreshing
    it is a MEASURED act -- run this, read the output, and commit the diff as a human decision."""
    sets = classify(surveyed)
    rows = sorted(sets["unread_stale"] + sets["unread_fresh"], key=lambda r: r["dir"])
    head = "dir\tage_h_at_baseline\tfiles_at_baseline"
    return "\n".join([head] + [f"{r['dir']}\t{r['age_h']}\t{r['files']}" for r in rows]) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="census of tracked `.agents/slop/*/` declarations")
    ap.add_argument("--quiet", action="store_true", help="the exit status only")
    ap.add_argument("--baseline", action="store_true",
                    help="print the baseline TSV to stdout; this file never writes it")
    ap.add_argument("--root", default=str(ROOT), help="the repository to walk")
    args = ap.parse_args(argv)
    surveyed = survey(Path(args.root).resolve())
    if "error" in surveyed:
        return verdict(surveyed)
    if args.baseline:
        sys.stdout.write(baseline_rows(surveyed))
        return 0
    if not args.quiet:
        write_rows(surveyed)
    return verdict(surveyed)


if __name__ == "__main__":
    sys.exit(main())