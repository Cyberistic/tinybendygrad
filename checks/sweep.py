#!/usr/bin/env python3
"""Sort every file under .agents/slop and runs into exactly four buckets, then act on three.

    usage: .venv/bin/python checks/sweep.py --plan          # classify, print the plan, delete nothing
           .venv/bin/python checks/sweep.py --apply DOC GATE ORACLE DELETE

THE RULE, AS THE USER STATED IT:

    anything in slop which isn't real documentation, or should be moved to checks/ (gates),
    oracles, or whatever, should be deleted. This includes one-off test scripts.

So there are four buckets and no fifth:

    DOC      a .md report. It records a measurement or a decision. It stays in slop.
    GATE     it RUNS and DECIDES, and something load-bearing names it. It moves to checks/.
    ORACLE   it is reference DATA a gate compares against -- never executed, only diffed.
             It moves to oracles/.
    DELETE   everything else: one-off probes, mutators, generated row dumps, .err captures,
             shadow trees of the source, and the several-thousand scripts that ran once and
             whose answer is already in the report beside them.

WHY THE GATE SET IS DEFINED BY BEING NAMED, NOT BY BEING EXECUTABLE.  MEASURED: `.agents/slop`
holds 5,817 `.sh`/`.py` files and 515 executables, of which **367 are copies of UPSTREAM's own
scripts** (`dev`, `run`, `setup`, `serve`, `train`) inside shadow trees of the source. And the
citation test has already been got wrong three times in this project -- a bare-basename match
reported 3,574 false citations, 138 of them copies of one `__init__.bend`; a bare-substring match
reported 6 citers for a ZERO-BYTE `.err`. **A GATE IS A GATE BECAUSE SOMETHING DEPENDS ON IT, AND
THE ONLY WAY TO KNOW THAT IS TO ASK WHAT NAMES IT.**

CITATIONS ARE WHOLE PATH TOKENS. `in` IS NOT A CITATION TEST. The matcher is a word-boundary
regex over committed reports plus `AGENTS.md` and `checks/README.md`, because a bare `in` is how
four files at the repository root were once kept alive by a report mentioning `.error`.

LIVE FILES ARE NEVER TOUCHED. The window is `--live-minutes`, and it is checked at ACT time, not
only at classify time, because five units are writing into slop while this runs.
"""
from __future__ import annotations

import argparse
import collections
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLOP = os.path.join(ROOT, ".agents/slop")
RUNS = os.path.join(ROOT, "runs")
CHECKS = os.path.join(ROOT, "checks")
ORACLES = os.path.join(ROOT, "oracles")

# What counts as being NAMED. Reports are where claims live; AGENTS.md and checks/README.md are
# what a reader actually reads.
#
# `:(glob)` IS LOAD-BEARING AND ITS ABSENCE WAS A 63% CORRUPTION. MEASURED 2026-10-05: git's
# DEFAULT pathspec magic treats `*` as FNM_PATHNAME-OFF, so `*` CROSSES `/`. `.agents/slop/*.md`
# therefore matched **195** files where `:(glob).agents/slop/*.md` matches **98** — and the extra 97
# were reports from INSIDE the shadow trees this script exists to delete, i.e. COPIES OF THE CORPUS
# ITSELF. The citation blob was **3,736,092 chars of which 1,370,376 were real**: 63% of the
# evidence was a copy of the evidence, so any file named inside a shadow tree counted as "named" and
# the KEEP set was inflated by exactly the files the sweep should have removed.
#
# **A CITATION INDEX BUILT FROM THE TREE BEING SWEPT IS NOT A CITATION INDEX.**
#
# **`checks/*.py` AND `gates/*.py` WERE MISSING, AND THAT IS WHY THE e2e GATE DIED.** MEASURED
# 2026-10-05: this list was byte-identical before and after the sweep that deleted `e2e_mm.py`,
# `e2e_mm.bend` and `e2e_mm_run.mjs` — stage 1's driver, so `checks/e2e.py` exited 2 in stage 1 and
# stages 2-8 NEVER RAN. The guard was not broken; **the gate was not in the corpus.** Both
# `checks/e2e.py` and `checks/sweep.py` name `e2e_mm.py`, and `checks/README.md` has named it
# **0 times, then and now** — so the ONLY thing keeping the project's one artifact alive was
# `.agents/slop/E2E-THROUGH-PORT.md`. **AN INSTRUMENT'S SURVIVAL DEPENDED ON A REPORT MENTIONING IT.**
#
# **A GATE NAMES ITS OWN INPUTS. THAT IS STRUCTURAL; A REPORT MENTIONING THEM IS A COINCIDENCE.**
NAMED_BY = [":(glob).agents/slop/*.md", "AGENTS.md", ":(glob)checks/*.md",
            ":(glob)gates/*.md", ":(glob).agents/*.md",
            ":(glob)checks/*.py", ":(glob)gates/*.py"]

# A gate names itself with these words. `-gate`/`-check` decide; `probe`/`mutate`/`gen`/`fix` are
# a thing that was run once. The distinction is the project's own vocabulary, not mine.
GATE_WORD = re.compile(r"(^|[-_.])(gate|check|census|verdict)([-_.]|$)")
ORACLE_WORD = re.compile(r"(^|[-_.])(oracle|rows|expect|pins|baseline)([-_.]|$)")

# Never touch these, whatever they look like. Each has caused a loss or a false verdict.
#
# `E2E_CHAIN` IS HERE BECAUSE I DELETED IT ONCE. The first `--apply DELETE` run moved 521 files
# and deleted the fixtures and stage drivers of the project's ONE artifact: `e2e_mm.py`,
# `e2e_mm.bend`, `e2e_mm_run.mjs`, `e2e_port/`, `f64/`, `e2e/`. `e2e.sh` itself was moved to
# `checks/` and left pointing at paths that no longer existed, so the artifact was a script that
# could not run. It was recoverable only because every one of those files happened to be
# committed -- WHICH IS NOT A PROPERTY OF THE SWEEP, IT IS A PROPERTY OF THE DAY.
PROTECTED = re.compile(
    r"(^\.agents/slop/(strays|strays-root)/)"          # 42 files restored from origin after regressing
    r"|(RECOVERY-0BYTE\.md$)"                          # the zero-byte incident
    r"|(^\.agents/slop/(e2e|e2e_port|f64|portexec)/)"  # the artifact's fixtures and stage drivers
    r"|(^\.agents/slop/e2e(_mm(\.py|\.bend|_run\.mjs))?\.sh$)"   # e2e.sh itself, and its three fixtures
    r"|(^\.agents/slop/(opsbend-milestone|substrate-check|graphcmp-(run|repro))\.sh$)"
    r"|(^checks/)"                                     # the gates themselves
)

# The differ's implementation and its frozen shell bodies. These are not one-off scripts: they are
# the thing every corpus number comes from. They move, but they move to a real home.
DIFFER = {"graphcmp.py", "graphcmp.bend", "graphcmp-oracle.py",
          "graphcmp-run.sh", "graphcmp-repro.sh", "graphcmp-dbg-oracle.py"}

# A DIRECTORY WHOSE OWN NAME DECLARES ITS ROLE CLASSIFIES ITS WHOLE SUBTREE. MEASURED 2026-10-05:
# `oracles/` (79 files, 520 KB, named by 4 reports) held 60 `.txt` of EXPECTED VALUES and was about to
# be deleted, because the verdict is computed per FILE from its BASENAME — and a file called
# `blob-bn.txt` inside a directory called `oracles` looks like a row dump. **THE ROLE IS A PROPERTY OF
# THE DIRECTORY AND WAS BEING READ FROM THE FILE.** These are the four names this project uses to
# mean a role, so a directory that is one of them is one.
ROLE_DIRS = {"oracles": "ORACLE", "gates": "GATE", "checks": "GATE",
             "strays": "PROTECTED", "strays-root": "PROTECTED"}

LIVE_UNITS = (
    # LIVE RIGHT NOW. MEASURED 2026-10-05: this list was written before the current four were
    # dispatched, and the plan put **255 files of a running unit's** (`e2epy/`) into the DELETE
    # bucket. A live unit's exclusion cannot live in a hand-maintained list that nobody updates at
    # dispatch time, so the mtime window is the real guard and this list is only a second belt.
    "readback", "jsbf16", "bitcastrow", "corpus24", "i64shl", "shfinish", "wallcheck",
    # DISPATCHED AFTER THAT LIST WAS WRITTEN, WHICH IS THE THIRD TIME IT HAS BEEN WRONG. The mtime
    # window catches files a unit is actively writing; it does NOT catch the directory a unit is about
    # to write into, which is why this list exists at all. **A GUARD THAT IS CORRECT EXCEPT FOR THE
    # LAST DISPATCH IS NOT A GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER.**
    "staleruns", "straysunit", "noreports", "runskeep", "dotxt",
    # FINISHED UNITS US TO BE PINNED HERE WERE THE WHOLE PROBLEM. MEASURED 2026-10-05: six names
    # sat under a `# finished` heading and had never been removed, and two of them were
    # `differverdict` (**1,382 files**) and `gatecensus` (**971**) — **2,353 of the 4,455 files in
    # `.slop`, 53%**, every one of them **100% tracked in git** and named by **0 files outside
    # themselves**. A finished unit's tree is not evidence of anything a reader can check; it is a
    # copy, and `git show` is the copy. **THE MTIME WINDOW IS THE LIVENESS GUARD, EXACTLY AS THE
    # COMMENT ABOVE SAYS -- AND A LIST THAT OUTLIVES ITS UNITS IS NOT A SECOND BELT, IT IS THE
    # ONLY BELT, WHICH IS HOW 53% OF THE TREE BECAME PERMANENT.**
    # a port that just completed but whose tree is still the cleanest evidence of a migration
    "e2epy", "substrate",
)

# Four MUTATION ARMS, NOT A COPY. `dd-cone-wt/` is 43 MB and 572 files, and the shadowtrees unit
# measured that its four arms differ in exactly TWO files and that `codegen/decomp/dtype.bend` is
# FOUR DISTINCT STATES: **deleting three of the arms destroys three arms.** It is the record of what
# four mutations did, and a mutation's value is its DIFFERENCE from the real file, so the evidence
# is the four-way divergence rather than any one of the trees.
PROTECTED_DIRS = ("dd-cone-wt",)


def committed_named_text() -> str:
    """Every committed report and every reader-facing doc, as one blob, read once."""
    chunks = []
    try:
        names = subprocess.run(["git", "ls-files", "--"] + NAMED_BY, cwd=ROOT,
                               capture_output=True, text=True).stdout.split()
    except Exception:
        return ""
    for nm in names:
        try:
            r = subprocess.run(["git", "show", f"HEAD:{nm}"], cwd=ROOT,
                               capture_output=True, text=True, errors="replace")
            if r.returncode == 0:
                chunks.append(r.stdout)
        except Exception:
            pass
    return "\n".join(chunks)


def mentioned_filenames(blob: str) -> set[str]:
    """Every filename-shaped token the corpus mentions, extracted in ONE pass.

    THE THIRD INSTANCE OF THIS PROJECT'S WORST PERFORMANCE BUG, AND THE THIRD TIME THE FIX IS ALSO
    THE MORE CORRECT ANSWER:
      1. `_cleanup/classify.py` ran an empty-pattern `git grep` over the whole repo -- >20 minutes.
      2. `move_gates.py` ran one `git grep` PER FILE over the same corpus.
      3. This file scanned a 3.4 MB corpus ONCE PER FILE: 23,000 x 3.4 MB = ~78 GB of scanning,
         and the first `--plan` TIMED OUT AT 15 MINUTES.

    All three share one shape: **A PER-ITEM SCAN OF A SHARED CORPUS.** The corpus does not change
    between items, so scanning it once is not an optimisation, it is the only correct shape.

    And the single pass is MORE correct than the regex-per-file was. A `name.ext` token pattern
    boundaries itself, so a report mentioning `.error` cannot cite a file called `.err`, and
    `xgraphcmp.py` cannot cite `graphcmp.py` -- which is exactly the rule, arrived at by indexing
    rather than by defending a boundary class.
    """
    return set(re.findall(r"[A-Za-z0-9_][A-Za-z0-9_.-]*\.[A-Za-z0-9]+", blob))


def live_set(minutes: int) -> set[str]:
    cutoff = time.time() - minutes * 60
    live = set()
    for base in (SLOP, RUNS):
        for dirpath, _d, files in os.walk(base):
            for f in files:
                p = os.path.join(dirpath, f)
                try:
                    if os.path.getmtime(p) >= cutoff:
                        live.add(os.path.relpath(p, ROOT))
                except OSError:
                    pass
    return live


def verdict_for(rel: str, mentioned: set[str]) -> str:
    name = os.path.basename(rel)
    parts = rel.split(os.sep)
    top = parts[2] if len(parts) > 2 else ""

    # A role directory decides for its whole subtree, before any per-file judgement.
    for part in parts:
        if part in ROLE_DIRS:
            return ROLE_DIRS[part]
    if PROTECTED.search(rel):
        return "PROTECTED"
    # A live unit's own directory, by name. The mtime window catches files; this catches the
    # DIRECTORY a unit is about to write into.
    if top in LIVE_UNITS:
        return "LIVE-UNIT"
    if top in PROTECTED_DIRS:
        return "PROTECTED"
    if name.endswith(".md"):
        return "DOC"
    if name in DIFFER:
        return "GATE"
    # ORACLE IS NOT A WORD SHAPE. MEASURED 2026-10-05: this test was `ORACLE_WORD.search(name)` and
    # nothing else, so **670 of 675 ORACLE files were classified by their FILENAME and were named by NO
    # GATE AT ALL** — `gatecensus/` 167, `arith/` 51, `denom/` 50, `hermetic/` 49, `hdrbase/` 33, `eq/`
    # 32, `name-census-lanes/` 31: **finished units' row dumps that matched `rows|oracle|pins|baseline`
    # in a basename.** Only **5** are named by a live `checks/*.py` or `gates/*.py`.
    #
    # THIS IS THE SAME DEFECT AS `LIVE_UNITS`, ONE LEVEL UP, AND THE FILE ALREADY DIAGNOSED IT:
    # "the verdict is computed per FILE from its BASENAME — and a file called `blob-bn.txt` inside a
    # directory called `oracles` looks like a row dump. **THE ROLE IS A PROPERTY OF THE DIRECTORY AND
    # WAS BEING READ FROM THE FILE.**" `ROLE_DIRS` fixed it for four directory NAMES; the word shape
    # reintroduced it for every basename. **A FILE THAT NOBODY NAMES IS NOT REFERENCE DATA.**
    if name in mentioned and ORACLE_WORD.search(name) and not name.endswith((".sh", ".py")):
        return "ORACLE"
    # A FILE A COMMITTED REPORT NAMES IS **NEVER** DELETE. MEASURED 2026-10-05: the first sweep
    # deleted 3,603 files and `checks/repro-paths.py` went from 24 dangling reproduction paths to
    # **166** — because the GATE rule required a gate-shaped NAME *and* a citation, and everything
    # else fell through to DELETE. So a `.bend` fixture named by a report, and a `.py` an oracle
    # script needed, were both deletable while a report still pointed at them.
    #
    # **THE CITATION IS A LOWER BOUND ON VALUE, NOT A SUFFICIENT CONDITION FOR KEEPING.**
    # Naming something proves SOMEBODY DEPENDS ON IT; the name only decides which bucket.
    if name in mentioned:
        return "KEEP-CITED"
    if (GATE_WORD.search(name) or os.access(os.path.join(ROOT, rel), os.X_OK)) \
            and name in mentioned:
        return "GATE"
    return "DELETE"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="classify and print; touch nothing")
    ap.add_argument("--apply", nargs="*", default=None,
                    help="verdicts to ACT on: DOC GATE ORACLE DELETE")
    ap.add_argument("--live-minutes", type=int, default=60)
    ap.add_argument("--yes", action="store_true", help="required for DELETE")
    args = ap.parse_args()

    blob = committed_named_text()
    mentioned = mentioned_filenames(blob)
    live = live_set(args.live_minutes)

    rows = []
    for base in (SLOP, RUNS):
        for dirpath, _d, files in os.walk(base):
            for f in sorted(files):
                p = os.path.join(dirpath, f)
                rel = os.path.relpath(p, ROOT)
                v = verdict_for(rel, mentioned)
                if rel in live and v not in ("PROTECTED", "LIVE-UNIT"):
                    v = "LIVE"
                try:
                    # lstat, NOT getsize: getsize FOLLOWS SYMLINKS, and slop has 174 of
                    # them pointing into .venv and into shadow trees. Following them counted
                    # each link at its TARGET's size, so the sweep reported **1,291 MB for a
                    # 149 MB tree** -- a 7.5x headline on the ONE number it exists to publish.
                    rows.append((v, os.lstat(p).st_size, rel))
                except OSError:
                    pass

    counts = collections.Counter()
    sizes = collections.Counter()
    for v, sz, _r in rows:
        counts[v] += 1
        sizes[v] += sz

    total_n, total_b = len(rows), sum(sizes.values())
    print(f"# sweep: {total_n} files, {total_b/1048576:.0f} MB, "
          f"live-window {args.live_minutes}m, {len(mentioned)} filenames mentioned in {len(blob)} chars")
    for v in ("DOC", "GATE", "ORACLE", "DELETE", "LIVE", "LIVE-UNIT", "PROTECTED"):
        if counts[v]:
            share = sizes[v] / total_b * 100 if total_b else 0
            print(f"#   {v:11s} {counts[v]:7d} files {sizes[v]/1048576:8.1f} MB  {share:5.1f}%")
    if args.plan or not args.apply:
        keep = counts["DOC"] + counts["GATE"] + counts["ORACLE"]
        print(f"\n# KEEPING {keep} of {total_n}: "
              f"{counts['DOC']} doc + {counts['GATE']} gate + {counts['ORACLE']} oracle")
        print(f"# DELETING {counts['DELETE']} files, {sizes['DELETE']/1048576:.0f} MB")
        if counts["DELETE"] > total_n * 0.5:
            print("#   (more than half. A sweep that keeps less than it removes is not a tidy-up;\n"
                  "#    it is a decision about what this directory is FOR.)")
        big = sorted((r for r in rows if r[0] == "DELETE"), key=lambda d: -d[1])[:12]
        if big:
            print("# largest DELETEs:")
            for _v, sz, rel in big:
                print(f"#     {sz/1024:9.1f} KB  {rel}")
        return 0

    if "DELETE" in args.apply and not args.yes:
        print("refusing to DELETE without --yes. A deletion pass that needs no confirmation\n"
              "is the pass where the allow-list was wrong.", file=sys.stderr)
        return 3

    moved = deleted = 0
    for v, sz, rel in rows:
        src = os.path.join(ROOT, rel)
        # `v not in args.apply` is the check whose absence broke the artifact once: the bucket a
        # caller did NOT name was acted on anyway, because the `elif` tested the VERDICT rather
        # than the REQUEST. `--apply DELETE` moved 521 files and deleted e2e's fixtures.
        if v not in (args.apply or ()):
            continue
        if v == "DELETE":
            try:
                os.remove(src)
                deleted += 1
            except OSError:
                pass
        elif v in ("GATE", "ORACLE"):
            dest_dir = CHECKS if v == "GATE" else ORACLES
            # Flat, because 200 gates in a tree is a tree nobody reads; a name collision is
            # reported rather than silently resolved.
            dest = os.path.join(dest_dir, os.path.basename(rel))
            if os.path.exists(dest):
                continue
            os.makedirs(dest_dir, exist_ok=True)
            try:
                shutil.move(src, dest)
                moved += 1
            except OSError:
                pass

    # Prune directories left empty, derived never listed.
    pruned = 0
    for base in (SLOP, RUNS):
        for dirpath, _dn, _fn in os.walk(base, topdown=False):
            try:
                os.rmdir(dirpath)
                pruned += 1
            except OSError:
                pass
    print(f"DELETED {deleted} files, MOVED {moved} into checks/+oracles/, "
          f"pruned {pruned} empty directories")
    return 0


if __name__ == "__main__":
    sys.exit(main())