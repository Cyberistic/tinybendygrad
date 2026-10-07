#!/usr/bin/env python3
"""checks/residue.py -- a SECOND OPINION on `sweep.py`'s DELETE bucket, and the fifth verdict.

    usage: checks/residue.py                 # classify, write .agents/slop/residue/, act on nothing
           checks/residue.py --plant         # build a synthetic tree, assert every verdict, touch no prod file
           checks/residue.py --disarm NAME   # plant again with one resolver OFF; a PASS here is exit 3

WHY A SECOND INSTRUMENT AND NOT A FIX. `checks/sweep.py` is another unit's unit and this file is not
allowed to edit it. But a fix nobody can run is a comment, so this CONSUMES `sweep.verdict_for()` and
reports, per row, `sweep=<its verdict>` next to `residue=<mine>`. **A SECOND INSTRUMENT THAT DISAGREES
WITH THE FIRST IS WORTH MORE THAN A REPLACEMENT THAT AGREES WITH NEITHER.** Every row where the two
disagree is in `003-disagreements.md`, and the disagreement count is the number this check exists to
publish.

THE FIFTH VERDICT IS `UNKNOWN`, AND IT IS THE MISSING ONE. `sweep.verdict_for` has four buckets and
seven escapes (`PROTECTED`, `LIVE`, `LIVE-UNIT`, `KEEP-CITED`), and **EVERY ESCAPE IS A WAY OF SAYING "I
AM NOT SURE"** -- an incident, a name in a list, an mtime. What the instrument lacks is a place to
RECORD the not-sure, so the not-sure leaks into the one bucket that acts: `return "DELETE"`.

    `verdict_for`'s last statement is `return "DELETE"`. It is the DEFAULT, reached whenever every
    escape above declined to fire. So DELETE is not a verdict; it is the ABSENCE of one, and it is the
    only bucket `--apply` destroys.

So here DELETE IS NOT A FALLOUT. Every row is put through three positive questions, all MEASURED from
the tree and none of them a hand-maintained list, and a row that no question answers is `UNKNOWN`:

    AUTHORED   a NAMING AUTHORITY outside the residue RENDERS this name. (`differ.declared()`)
    LIVE       a DIRECTORY is being written right now, measured per directory, never per name.
    DERIVED    regenerable from a tracked input BY CONSTRUCTION (`__pycache__/*.pyc`).

    and three corroborating measurements, none of which are verdicts on their own:

    COPY       sha256-identical to a file outside the residue, which the row records.
    CITED      a WHOLE-PATH TOKEN names it, from OUTSIDE the residue, per two independent belts.
    UNNAMED    every test ran and every test said no. **THIS IS A MEASUREMENT, NOT A VERDICT. It is
               the only row that is a CANDIDATE for deletion, and being a candidate is not a verdict:
               "nothing I can measure names this" and "this is junk" are different sentences.**

    UNKNOWN    a test COULD NOT BE RUN, so the row carries `needs=` -- the cheapest test that would
               resolve it. UNKNOWN IS REPORTED AND NEVER ACTED ON. It is not a bucket a deletion pass
               can be pointed at, which is the entire point of it existing.

THE MEASUREMENT THAT SAYS THE DELETE BUCKET IS NOT A COUNT OF JUNK. MEASURED 2026-10-06, on a residue
of 332 DELETE rows: **`checks/differ.py` renders 136 of them -- 100% of `runs/graphcmp/D` and 100% of
`.agents/slop/spine/art-a` -- out of `declared()`, a function that already exists for exactly this
reason and that `checks/no-txt.py` already calls.** Meanwhile the citation corpus, 3,352,246 chars,
sees **1** of those basenames as a literal token.

    THE CORPUS INDEXES LITERAL TOKENS. THE PROJECT'S NAMING AUTHORITY CONSTRUCTS NAMES. So a file
    whose reference is an f-string is invisible to the reference test, and `DELETE` is measuring
    "referenced by no literal" while being reported as "junk".

**THE RESIDUE IS A COUNT OF UNREFERENCED-BY-THE-INSTRUMENT, NOT A COUNT OF UNREFERENCED-BY-THE-PROJECT.**
`AUTHORED` is the group that proves it, and its deciding test is one function call.

THE SECOND MEASUREMENT, WHICH IS WORSE: `DELETE` IS A FUNCTION OF THE CLOCK. Same tree, same second,
`--live-minutes` off: **331**. At the 60-minute default, measured four times over twenty minutes:
**150, 14, 14, 14** -- and it drifted because seven units were writing into the tree the whole time. A
number that moves 22x while nobody edits anything is not a measurement of the tree; it is a measurement
of when you looked. `000-the-residue.md` is written with the window OFF, and says so in its own header,
so the file on disk is the one number here that does not move.

THE BELTS ARE TWO METHODS THAT SHARE NO REGEX, and the reason is in this project's own history: one
tokenizer here ate a full stop and its own belt missed the same stop, **because the belt shared the
regex's assumption**. So `belt_git` is git's own `-w -F` matcher and `belt_tokens` is a `str.translate`
table with no pattern in it at all. If they disagree on a row, the row is UNKNOWN, not decided.

A CITATION MUST BE A WHOLE PATH TOKEN AND THE CITER MUST BE OUTSIDE THE RESIDUE. `in` is not a citation
test -- `.out` drew 23 citers by substring where the whole-token answer is 2. And a citation from
INSIDE the residue does not keep a row: it is either a real dependency between two of the residue's own
tools or a shadow tree naming the files it copied, **and those two are indistinguishable from here**, so
such a row is UNKNOWN with `needs=residue-internal-citer`.

EXCLUSIONS ARE REPORTED, NOT SILENT. The house rules exclude `dd-cone-wt/`, `xd1/`, `strays/`,
`strays-root/`, `rf2root/`, `diffpy/`, `lost/`, `e2e/`, `e2e_port/`, `f64/`, `portexec/`, `gates/{oracles,
artifacts}/` and every live unit's directory from every walk. **A GROUP THAT IS EXCLUDED IS STILL A
GROUP**, so every excluded DELETE row is printed as UNKNOWN with `needs=owner-decision` and counted in
its own line of the report. Dropping them would make this file's headline smaller and its coverage a lie.

ONE THING I COULD NOT SETTLE, AND IT IS THE POINT: **the live-unit set is not recorded anywhere.** The
house rules say 21 units are running; `sweep.LIVE_UNITS` names 14; `LIVE-UNIT` currently covers 342
files, 28% of the residue, off a tuple inside a Python file that is itself one of the four
classification failures this check exists next to. I exclude `sweep.LIVE_UNITS` because that is the only
roster that exists, and I say so rather than inventing the other seven.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import importlib.util
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, ".agents/slop/residue")
SLOP, RUNS = ".agents/slop", "runs"

# THE HOUSE RULES, AS A SET OF DIRECTORY NAMES. See the header for why an excluded row is still
# counted. `gates/{oracles,artifacts}` cannot appear in a slop walk and is listed for the record.
EXCLUDED_DIRS = (
    "dd-cone-wt", "xd1", "strays", "strays-root", "rf2root", "diffpy", "lost",
    "e2e", "e2e_port", "f64", "portexec", "oracles", "artifacts",
    # THIS CHECK'S OWN OUTPUT, and it is here because the trap fired rather than because it is tidy.
    # MEASURED 2026-10-06: `000-the-residue.md` names every residue row by path, so the moment it was
    # staged -- which a concurrent unit did with a bare `git add` -- the next run found EVERY ROW CITED
    # BY THIS CHECK'S OWN REPORT, and the residue collapsed from 40 `UNNAMED` to 0. **A CLEANUP THAT
    # IMPROVES ITS OWN INSTRUMENT'S NUMBER IS NOT A CLEANUP, IT IS A SELF-DEFINING ONE**, and this is
    # the fifth time in this project that a citation index has been built out of the thing it was
    # measuring. `belt_self_cited` below is the second belt: the exclusion is the fix and the belt is
    # what notices if the fix is ever undone.
    "residue",
)

# This check's own output directory, relative to ROOT. Belt A is `git grep`, which reads the WORKING
# TREE of TRACKED files, so an untracked report is invisible to it and a STAGED one is fully visible --
# which is how an untracked output file became a citation corpus mid-session.
SELF = SLOP + "/residue/"

# THE TWO RESIDUE ROOTS. A path is "in the residue" iff its second component is one of them.
RESIDUE_ROOTS = (SLOP, RUNS)


def sweep_module():
    """`checks/sweep.py`, imported rather than copied: this file's whole claim is that it CONSUMES."""
    spec = importlib.util.spec_from_file_location("sweep", os.path.join(HERE, "sweep.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def authorities() -> dict[str, set[str]]:
    """Every name a CODE authority renders, keyed by the module that renders it.

    A REGISTRY OF CALLABLES, never a list of filenames. This project's third classification failure was
    a hand-maintained list of finished units; the fourth would be a hand-maintained list of 206 file
    names, and it would outlive its reason the same way. Ask the generator instead -- `differ.py`
    already exports `declared()` for `checks/no-txt.py`, and asking is one call.

    A module that will not import yields NO authority rather than a traceback: an authority that
    cannot be asked must make its rows UNKNOWN, not crash the census.
    """
    out: dict[str, set[str]] = {}
    for mod in ("differ",):
        try:
            spec = importlib.util.spec_from_file_location(mod, os.path.join(HERE, mod + ".py"))
            m = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(m)
            names = set(m.declared())
        except Exception:
            continue
        # The `.err` twin is written beside every artifact by the same writer, so it is part of the
        # same contract and is rendered by the same call.
        out[mod] = names | {n + ".err" for n in names}
    return out


def git_tracked(root: str) -> set[str]:
    """`git ls-files` MINUS the tracked-but-deleted. `ls-files` alone returns paths that are not on
    disk, so a count taken from it can exceed the tree and a DELETED count can come out NEGATIVE."""
    r = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, text=True)
    live = set()
    for p in r.stdout.split("\0"):
        if p and os.path.lexists(os.path.join(root, p)):
            live.add(p)
    return live


# ---------------------------------------------------------------- the two citation belts
_WORD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./"


def belt_git(root: str, name: str) -> set[str]:
    """BELT A: git's own matcher. `-w -F` is a whole-word fixed-string search, so `.error` cannot
    cite `.err` and `xgraphcmp.py` cannot cite `graphcmp.py`.

    The `:(exclude)` pathspec drops this check's own report from the search. Without it, `git grep`
    reads the working tree of TRACKED files, so an untracked report is invisible and a STAGED one is
    fully visible -- which is how this check's own output became a citation corpus mid-session. The
    exclusion is the fix; `belt_self_cited` is what notices the fix being undone.
    """
    r = subprocess.run(["git", "grep", "-l", "-w", "-F", "-e", name,
                        "--", ":(exclude)" + SELF + "**"],
                       cwd=root, capture_output=True, text=True)
    return set(r.stdout.split())


def belt_tokens(blob: str) -> set[str]:
    """BELT B: NO REGEX. Every byte that is not a path character becomes a space, then split.

    Deliberately not `re.findall`: this project's tokenizer ate a full stop because its pattern
    `[A-Za-z0-9_.-]*` could not match one, and the belt that should have caught that shared the
    pattern. A translation table has no such blind spot to share.
    """
    table = str.maketrans({chr(i): " " for i in range(128) if chr(i) not in _WORD})
    return set(blob.translate(table).split())


def belt_self_cited(citers: set[str]) -> set[str]:
    """BELT C: is any citer this check's own output? A citation from the report that enumerates the
    residue is a citation from the instrument measuring itself.

    `EXCLUDED_DIRS` stops belt B from ever seeing these paths, but belt A is `git grep` over the
    working tree of tracked files and a STAGED report is fully visible to it -- so the exclusion is
    the fix and THIS is the belt, because a fix nobody can detect being undone is a fix that will be.
    MEASURED 2026-10-06: a concurrent unit's bare `git add` staged `000-the-residue.md` and the next
    run reported all 40 `UNNAMED` rows as CITED, by this check's own report.
    """
    return {c for c in citers if c.startswith(SELF)}


def index_citations(cites: dict[str, set[str]], root: str, rel: str, blob: str) -> None:
    """Add one file's worth of citations to the index, keyed BOTH ways.

    A CITATION BY FULL PATH IS ALSO A CITATION. `sweep`'s index holds whatever token the corpus
    happens to contain and is looked up by BASENAME, so a report that names a file the way this project
    actually names files -- `.agents/slop/x/matmul.rows` -- does not cite `matmul.rows`. That is the
    same shape as every other citation bug here: the index and the lookup disagree about what a name
    is. Two keys, one pass, no regex.
    """
    for tok in belt_tokens(blob):
        if "." not in tok:
            continue
        if os.path.lexists(os.path.join(root, tok)):
            cites[tok].add(rel)
        cites[tok.rsplit("/", 1)[-1]].add(rel)


def excluded(rel: str) -> bool:
    return any(part in EXCLUDED_DIRS for part in rel.split(os.sep)[1:])


def in_residue(rel: str) -> bool:
    parts = rel.split(os.sep)
    return len(parts) > 1 and f"{parts[0]}/{parts[1]}" in RESIDUE_ROOTS


def walk(root: str) -> list[tuple[str, int]]:
    """(relpath, lstat size) for every regular file and symlink under both residue roots.

    `lstat`, NEVER `getsize`/`exists`: both follow symlinks, and this tree has 167 of them pointing
    into `.venv` and into shadow trees -- which once made a 168 MB tree report as 1,291 MB, a 7.5x
    headline on the one number the instrument exists to publish.
    """
    out = []
    for base in (SLOP, RUNS):
        top = os.path.join(root, base)
        for dirpath, _d, files in os.walk(top):
            for f in files:
                p = os.path.join(dirpath, f)
                try:
                    out.append((os.path.relpath(p, root), os.lstat(p).st_size))
                except OSError:
                    pass
    return out


def dir_ages(root: str, files: list[tuple[str, int]]) -> dict[str, float]:
    """Newest file mtime per DIRECTORY, as an age in seconds.

    `sweep.live_set` measures mtime per FILE and `sweep.LIVE_UNITS` measures it per NAME, and the two
    disagree in the direction that loses files: a unit that has not written in the last 60 minutes into
    a directory it is about to write into is protected by neither. Per-directory aggregation needs no
    roster, so it cannot go stale the way `LIVE_UNITS` did.
    """
    age: dict[str, float] = {}
    now = time.time()
    for rel, _sz in files:
        try:
            m = os.lstat(os.path.join(root, rel)).st_mtime
        except OSError:
            continue
        d = os.path.dirname(rel)
        age[d] = min(age.get(d, now), now - m)
    return age


def sha(root: str, rel: str) -> str:
    try:
        with open(os.path.join(root, rel), "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return ""


def outside_twins(root: str, tracked: set[str], rows: list[tuple[str, int]]) -> dict[str, list[str]]:
    """For each residue row, every file OUTSIDE the residue with the same bytes.

    THE INDEX SPANS THE WHOLE REPO, NOT THE RESIDUE. A twin search confined to the tree being swept
    finds only residue-to-residue duplicates and reports the 110 copies in
    `.agents/slop/slopcopies/MANIFEST.tsv` -- every one of which is byte-identical to a file tracked
    OUTSIDE `.slop/` -- as UNIQUE. The whole point of a copy is that the authority is elsewhere, so a
    copy detector that cannot see the authority is a duplicate counter.

    3,378 tracked files, 86 MB, one pass: a per-item rescan of a shared corpus is this project's worst
    performance bug and it is not an optimisation to avoid here, it is the only shape.
    """
    subjects = {r for r, *_ in rows}
    digests: dict[str, list[str]] = collections.defaultdict(list)
    for rel in sorted(tracked):
        if not os.path.islink(os.path.join(root, rel)):
            digests[sha(root, rel)].append(rel)
    out: dict[str, list[str]] = {}
    for r in subjects:
        twins = [t for t in digests[sha(root, r)] if t != r and not in_residue(t)]
        if twins:
            out[r] = twins
    return out


# ---------------------------------------------------------------- the classification
# `needs=` on an UNKNOWN row is the CHEAPEST TEST THAT WOULD RESOLVE IT. A group with no deciding test
# is a group that has been labelled, not analysed.
RESOLVERS = ("authored", "live", "derived", "copy", "cited")

# THE ONE SOURCE OF `UNKNOWN` THAT IS A CONDITION RATHER THAN A RESOLVER. It gets a name anyway, so
# that `--disarm` can prove its branch is live: an UNKNOWN that cannot be made to move is an UNKNOWN
# that is not being computed.
#
# `untracked` AND `witness` ARE GONE, AND WITH THEM THE TWO `needs=` THAT NEVER FIRED. `main()` puts
# only the rows `sweep.verdict_for` calls DELETE through `classify`, and `sweep` answers
# `UNKNOWN:commit-or-drop` and `UNKNOWN:commit-the-report-that-explains-it` for EXACTLY the rows those
# two branches named -- same `tracked` set, same `TOOL_EXT`, same witness test. So they were a SECOND
# AUTHORITY OVER A QUESTION `sweep.py` had already decided: plantable inside `classify` (1 -> 0) and
# unreachable in the pipeline that calls it, deciding 0 rows while sweep's originals fire 114 and 110.
# MEASURED 2026-10-06: deleting them changes no residue verdict on the live tree, and sweep still emits
# both tags. See `.agents/slop/deadclause/REPORT.md`.
CONDITIONS = ("excluded",)


def classify(root: str, rel: str, size: int, *, sweep_named: set[str], first_pass,
             auth: dict[str, set[str]], age: dict[str, float], window: int,
             twins: dict[str, list[str]], cites: dict[str, set[str]],
             disabled: set[str]) -> tuple[str, str, str]:
    """-> (sweep verdict, residue verdict, why/needs). Pure: takes every measurement as an argument so
    `--plant` can drive it over a synthetic tree with no production file involved."""
    first = first_pass(rel, sweep_named)
    name = os.path.basename(rel)
    d = os.path.dirname(rel)

    if "excluded" not in disabled and excluded(rel):
        return first, "UNKNOWN", "excluded from this walk by the house rules; needs=owner-decision"
    if os.path.islink(os.path.join(root, rel)):
        return first, "UNKNOWN", "symlink; needs=readlink-target (this tree has 167 and lstat is the only safe size)"
    if "authored" not in disabled:
        for mod, names in auth.items():
            if name in names:
                return first, "AUTHORED", f"{mod}.declared() renders this name"
    if "live" not in disabled and age.get(d, 1e9) <= window * 60:
        return first, "LIVE", f"directory written {age[d] / 60:.0f}m ago"
    if "derived" not in disabled and "__pycache__" in d and name.endswith(".pyc"):
        return first, "DERIVED", "byte-compiled cache; regenerated by import"
    if "copy" not in disabled:
        for t in twins.get(rel, ()):
            return first, "COPY", f"byte-identical to {t}, outside the residue"
    if "cited" not in disabled:
        # BELT B found the name somewhere. BELT A is git's own matcher over the SAME population, and
        # the two must agree before the row is decided -- one tokenizer here ate a full stop and its
        # own belt missed it BECAUSE THE BELT SHARED THE REGEX'S ASSUMPTION.
        belt_b = set(cites.get(name, ()))
        # Belt A only runs when belt B found something, so the `git grep` cost is paid on the residue
        # rows that have a citation candidate and not on the ones that have none.
        belt_a = belt_git(root, name) if belt_b else set()
        if belt_a ^ belt_b:
            only_a, only_b = sorted(belt_a - belt_b), sorted(belt_b - belt_a)
            return first, "UNKNOWN", (f"the two citation belts disagree; git sees {only_a[:1]}, "
                                      f"the scanner sees {only_b[:1]}; needs=belts-disagree")
        self_cited = belt_self_cited(belt_b)
        if self_cited:
            return first, "UNKNOWN", (f"cited by this check's own report {sorted(self_cited)[0]}; "
                                      "an instrument may not measure itself; needs=unstage-self")
        who = {c for c in belt_b if not in_residue(c)}
        internal = {c for c in belt_b if in_residue(c)}
        if who:
            return first, "CITED", f"whole-path token in {sorted(who)[0]}" + (
                f" (+{len(who) - 1} more)" if len(who) > 1 else "")
        if internal:
            return first, "UNKNOWN", (f"named only from inside the residue by {sorted(internal)[0]}; "
                                      "a tool chain or a shadow tree, indistinguishable here; "
                                      "needs=residue-internal-citer")
    # `rel not in tracked` AND the TOOL-with-no-report case never arrive here: those are `sweep`'s
    # `UNKNOWN:commit-or-drop` and `UNKNOWN:commit-the-report-that-explains-it`, and `main()` puts only
    # `sweep=DELETE` rows through here. A second branch for them decided 0 rows; it is deleted.
    return first, "UNNAMED", "every test ran; nothing renders or names it. A CANDIDATE, not a verdict"


def plant(root: str, fixture: str, disabled: set[str]) -> tuple[int, list[str]]:
    """Build the synthetic tree the fixture describes, classify it, compare to the hand-written column.

    THE FIXTURE'S `expect` COLUMN IS A LITERAL. Nothing computes it. A check that compares itself to
    itself proves only that it agrees with itself, so the oracle here is data a person typed.

    The temp tree is `git init`ed and `git add`ed so citation belt A is git's REAL `-w -F` matcher
    rather than a stand-in that shares belt B's assumptions -- and the `age` column is applied with
    `os.utime`, so the LIVE resolver has a genuinely old file beside a genuinely new one in one
    directory and cannot pass by reading either one file's mtime.

    The production residue is NEVER TOUCHED: one repro in this project read `LEFT=NOTHING` on BOTH
    sides because it `rmtree`d the state under test between beats.
    """
    import tempfile
    cases = []
    with open(fixture) as fh:
        for line in fh:
            # A COMMENT IS A LINE THAT STARTS WITH `#`, never a line that CONTAINS one: the fixture
            # has a content field that begins with `#` on purpose, because a stripper that eats it
            # would silently delete the citation this row is planting.
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 5:
                raise SystemExit(f"residue-plant.tsv: {len(parts)} columns, want 5: {line!r}")
            rel, content, expect, age_s, tracked_s = (x.strip() for x in parts)
            cases.append((rel, content, expect, int(age_s), tracked_s == "yes"))
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        for rel, content, _e, _a, _t in cases:
            p = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as fh:
                fh.write(content)
        git = lambda *a: subprocess.run(["git", *a], cwd=tmp, capture_output=True,  # noqa: E731
                                        text=True)
        git("init", "-q")
        git("add", "-A")
        for rel, _c, _e, age_s, tracked_s in cases:
            ts = time.time() - age_s
            os.utime(os.path.join(tmp, rel), (ts, ts))
            if not tracked_s:
                git("rm", "-q", "--cached", rel)
        files = walk(tmp)
        age = dir_ages(tmp, files)
        auth = authorities()
        tracked = git_tracked(tmp)
        digests: dict[str, list[str]] = collections.defaultdict(list)
        for rel in sorted(set(tracked) | {r for r, _ in files}):
            digests[sha(tmp, rel)].append(rel)
        twins = {r: [t for t in digests[sha(tmp, r)] if t != r and not in_residue(t)]
                 for r, _sz in files if digests[sha(tmp, r)]}
        cites: dict[str, set[str]] = collections.defaultdict(set)
        for rel in sorted(tracked):
            try:
                with open(os.path.join(tmp, rel), "rb") as fh:
                    blob = fh.read().decode("utf-8", "replace")
            except OSError:
                continue
            index_citations(cites, tmp, rel, blob)
        first = lambda rel, _named: "DELETE"          # noqa: E731  the plant's first pass is trivial
        for rel, _content, expect, _a, _t in cases:
            # `-` means "this row exists to be a CITER or an authority, not a residue row to assert".
            if expect == "-" or not in_residue(rel):
                continue
            _first, v, why = classify(tmp, rel, 0, sweep_named=set(), first_pass=first, auth=auth,
                                       age=age, window=3600, twins=twins, cites=cites,
                                       disabled=disabled)
            if v != expect:
                bad.append(f"    {rel}: want {expect}, got {v} ({why})")
    return (1 if bad else 0), bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plant", action="store_true", help="assert every verdict on a synthetic tree")
    ap.add_argument("--disarm", metavar="RESOLVER",
                    help="plant again with one resolver off; a pass is exit 3 (the harness cannot move)")
    ap.add_argument("--live-minutes", type=int, default=0,
                    help="liveness window; DEFAULT 0 because the window is a clock, not a measurement")
    args = ap.parse_args()

    if args.plant or args.disarm:
        disabled = {args.disarm} if args.disarm else set()
        rc, bad = plant(ROOT, os.path.join(HERE, "residue-plant.tsv"), disabled)
        print(f"# plant: {len(disabled) and 'disarmed ' + args.disarm or 'armed'}; "
              f"{'FAIL' if bad else 'PASS'}")
        for b in bad:
            print(b)
        if args.disarm and not bad:
            print("# THE PLANT STILL PASSES WITH A RESOLVER OFF. A HARNESS THAT CANNOT MOVE PRODUCES A\n"
                  "# CONFIDENT WRONG ANSWER, SO THIS IS EXIT 3, NOT A PASS.")
            return 3
        return rc

    sweep = sweep_module()
    named = sweep.mentioned_filenames(sweep.committed_named_text())
    tracked = git_tracked(ROOT)
    files = walk(ROOT)
    age = dir_ages(ROOT, files)
    auth = authorities()

    first = lambda rel, n: sweep.verdict_for(rel, n)            # noqa: E731
    rows = [(rel, sz, first(rel, named)) for rel, sz in files]
    residue_rows = [r for r in rows if r[2] == "DELETE"]

    twins = outside_twins(ROOT, tracked, residue_rows)

    cites: dict[str, set[str]] = collections.defaultdict(set)
    for rel in sorted(tracked):
        if excluded(rel):
            continue
        try:
            with open(os.path.join(ROOT, rel), "rb") as fh:
                blob = fh.read(4 << 20).decode("utf-8", "replace")
        except OSError:
            continue
        index_citations(cites, ROOT, rel, blob)

    out = []
    for rel, sz, _first in residue_rows:
        sw, v, why = classify(ROOT, rel, sz, sweep_named=named, first_pass=first, auth=auth, age=age,
                              window=args.live_minutes, twins=twins, cites=cites, disabled=set())
        out.append((v, sz, rel, sw, why))
    out.sort(key=lambda r: (r[0], -r[1], r[2]))

    counts = collections.Counter(v for v, *_ in out)
    bybytes = collections.Counter()
    for v, sz, *_ in out:
        bybytes[v] += sz
    os.makedirs(OUT, exist_ok=True)

    total = len(out)
    tb = sum(s for _v, s, *_ in out) or 1
    head = [
        "# THE RESIDUE -- every row `checks/sweep.py` puts in DELETE, and what else is true of it",
        "",
        f"**{total} rows, {tb / 1048576:.1f} MB.** GENERATED by `checks/residue.py`; do not hand-edit.",
        f"**Liveness window: {args.live_minutes}m** -- and this number is a function of the clock, not of",
        "the tree: the same `--plan` printed DELETING 331 with the window off and 150, then 14, three",
        "times over, at the 60-minute default, while seven units wrote into the tree. **A NUMBER THAT",
        "MOVES 22x WHILE NOBODY EDITS ANYTHING IS NOT A MEASUREMENT OF THE TREE.**",
        "",
        "`sweep` = `sweep.verdict_for()`. `residue` = this file. **The two columns disagree, and that is",
        "the output.** `needs=` on an UNKNOWN row is the cheapest test that would resolve it.",
        "",
        "| residue | rows | MB | meaning |",
        "|---|---:|---:|---|",
    ]
    meaning = {
        "AUTHORED": "a naming authority outside the residue RENDERS this name. `sweep` says DELETE.",
        "LIVE": "a directory is being written right now, measured per directory.",
        "DERIVED": "regenerable by construction.",
        "COPY": "byte-identical (sha256) to a file outside the residue; the twin is named.",
        "CITED": "a whole-path token outside the residue names it.",
        "UNNAMED": "every test ran, every test said no. **A CANDIDATE, NOT A VERDICT.**",
        "UNKNOWN": "a test could not run. Reported, never acted on.",
    }
    for v in ("AUTHORED", "CITED", "COPY", "LIVE", "DERIVED", "UNNAMED", "UNKNOWN"):
        if counts[v]:
            head.append(f"| `{v}` | {counts[v]} | {bybytes[v] / 1048576:.2f} | {meaning[v]} |")
    head += ["", "## THE ROWS", "", "| residue | KB | path | sweep | why, or `needs=` |", "|---|---:|---|---|---|"]
    for v, sz, rel, sw, why in out:
        head.append(f"| `{v}` | {sz / 1024:.1f} | `{rel}` | `{sw}` | {why} |")
    head += [
        "",
        "## WHAT THIS FILE IS NOT",
        "",
        "It deletes nothing, moves nothing, and its `--plant` touches no production file. It is a second",
        "opinion; `checks/sweep.py` remains the instrument that acts. **A SECOND INSTRUMENT THAT DISAGREES",
        "WITH THE FIRST IS WORTH MORE THAN A REPLACEMENT THAT AGREES WITH NEITHER** -- and the count that",
        f"matters is that {counts['AUTHORED']} rows `sweep` would destroy are, by one function call, files",
        "the gate that owns them already declares.",
    ]
    with open(os.path.join(OUT, "000-the-residue.md"), "w") as fh:
        fh.write("\n".join(head) + "\n")

    dis = [r for r in out if r[0] in ("AUTHORED", "LIVE", "DERIVED", "COPY", "CITED")]
    with open(os.path.join(OUT, "003-disagreements.md"), "w") as fh:
        fh.write("# WHERE `residue` AND `sweep` DISAGREE, AND WHICH OF THEM HAS THE EVIDENCE\n\n")
        fh.write(f"{len(dis)} of {total} DELETE rows would be KEPT by a test `sweep` does not run.\n\n")
        fh.write("| residue | KB | path | the test `sweep` does not run |\n|---|---:|---|---|\n")
        for v, sz, rel, _sw, why in dis:
            fh.write(f"| `{v}` | {sz / 1024:.1f} | `{rel}` | {why} |\n")
        fh.write("\n# AND WHERE THEY AGREE THAT NOTHING NAMES IT\n\n")
        fh.write("`UNNAMED` is a MEASUREMENT. \"Nothing I can measure names this\" and \"this is junk\"\n"
                 "are different sentences, and only the first one is true here.\n\n")
        fh.write("| KB | path | tracked | needs a decision from |\n|---:|---|---|---|\n")
        for v, sz, rel, _sw, _why in out:
            if v == "UNNAMED":
                fh.write(f"| {sz / 1024:.1f} | `{rel}` | "
                         f"{'yes' if rel in tracked else 'NO'} | the unit that wrote it |\n")

    unk = [r for r in out if r[0] == "UNKNOWN"]
    with open(os.path.join(OUT, "002-unknown.md"), "w") as fh:
        fh.write("# THE FIFTH VERDICT: `UNKNOWN`, THE ROWS THAT NEED A HUMAN, AND WHAT WOULD SETTLE EACH\n\n")
        fh.write(f"**{len(unk)} of {total} rows are UNKNOWN and NONE of them is a deletion candidate.**\n"
                 "`sweep` has no place to record \"I cannot tell\", so these rows were falling through to\n"
                 "`return \"DELETE\"` -- which is not a verdict, it is the ABSENCE of one, and it is the\n"
                 "only bucket `--apply` destroys.\n\n")
        fh.write("| path | why it is UNKNOWN | the cheapest test that would resolve it |\n|---|---|---|\n")
        for _v, _sz, rel, _sw, why in unk:
            need = why.split("needs=", 1)[1] if "needs=" in why else why
            fh.write(f"| `{rel}` | {why.split('; needs=')[0]} | `{need}` |\n")

    print(f"# residue: {total} DELETE rows from sweep ({tb / 1048576:.1f} MB), liveness window "
          f"{args.live_minutes}m")
    for v in ("AUTHORED", "CITED", "COPY", "LIVE", "DERIVED", "UNNAMED", "UNKNOWN"):
        if counts[v]:
            print(f"#   {v:9s} {counts[v]:5d} rows {bybytes[v] / 1048576:7.2f} MB")
    self_cited = [r for r in out if "unstage-self" in r[4]]
    if self_cited:
        print(f"# WARNING: {len(self_cited)} rows are cited by THIS CHECK'S OWN REPORT. Its output is "
              f"in the corpus and\n#          the residue is measuring itself. Unstage it; see "
              "EXCLUDED_DIRS.", file=sys.stderr)
    print(f"# authorities consulted: {', '.join(f'{k}()' for k in auth) or 'NONE -- every row UNNAMED/UNKNOWN'}")
    print(f"# wrote {os.path.relpath(OUT, ROOT)}/000-the-residue.md, 002-unknown.md, 003-disagreements.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())