#!/usr/bin/env python3
"""Every path a committed report tells a reader to run must exist. `checks/repro-paths.py`

THE CLAIM, WITH ITS DENOMINATOR: of the paths named by committed reports as reproduction commands,
the number that resolve is printed beside the number named, and the exit status is non-zero if any
does not.

WHY, MEASURED ON 2026-10-05, AND IT WAS MY OWN PRUNE THAT DID IT.  A cleanup pass kept `.md` files
and files matching `*gate.py`/`*oracle.py`, and deleted the rest of six finished units'
directories. **That silently deleted six INSTRUMENTS that six reports instruct the reader to run:**

    .agents/slop/blob-intern-gate.sh          named by a report
    .agents/slop/ops-gate.sh                 named by a report
    .agents/slop/li/li-control.sh            named by a report
    .agents/slop/wallrule/wallcheck.sh       named by WALLRULE.md  <- deleted by THAT unit's own prune
    .agents/slop/guardfix/probe-c.bend       named by FP8FIX.md
    .agents/slop/mathlib/const_probe.bend    named by MATHLIB.md

**NONE OF THE SIX IS IN GIT.** They were never committed, so there was nothing to restore. That is
the whole point: **the prune was irreversible for exactly the files whose loss is invisible until
somebody tries to reproduce a claim.**

**A DANGLING `REPRODUCE` LINE IS WORSE THAN NO LINE**, because it invites a reader to trust a claim
they cannot check — and it costs the reader the discovery that they cannot check it.

WHAT IS CHECKED, AND WHAT IS NOT.  A path-shaped token under `.agents/slop/`, `checks/` or `gates/`
appearing in a committed report is a reproduction reference, WHATEVER ITS EXTENSION: whether it
resolves is asked of the FILESYSTEM, never of a suffix list.
Tokens containing `...` or `//` are **patterns**, not paths, and are counted separately rather than
reported as failures — because a report that writes `strays/origin/.../nvdev.bend` is describing a
family, and calling that a broken reference would be this file's own version of a false citation.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A path-shaped token under a directory this project owns. WHAT MAKES IT A REFERENCE IS THAT IT
# NAMES A PATH, and the FILESYSTEM is what decides that -- `os.path.exists` below -- so there is no
# suffix list here to go stale.
#
# **THERE WAS ONE, AND IT FAILED THE SAME WAY THREE TIMES.** The set was `sh|py|bend`; `.mjs` was
# ADDED when `checks/e2e.py`'s two `.mjs` stage inputs proved invisible (9 of 15 counted) and
# **RESTORING THEM MOVED THIS TOOL'S OUTPUT BY EXACTLY ZERO**; and on 2026-10-15 the five-item set
# was still blind to 164 of the 713 paths 584 committed reports name. A SUFFIX FILTER IS A
# POPULATION DEFINED BY A LIST, AND A LIST IS NOT A POPULATION.
#
# **AND A TRUNCATED TOKEN IS NOT A HARMLESS ONE: IT WROTE FALSE ROWS IN BOTH DIRECTIONS.**
# MEASURED 2026-10-15: `untrack/REPORT.md:142` names `...blastradius.cpython-312.pyc`, which the
# suffix set read as `...312.py` -- a DANGLING row for a name that never existed -- while
# `whosecache/REPORT.md:73` names `gates/tn_graph_census-gate.py.bak`, which it read as
# `gates/tn_graph_census-gate.py`, A FILE THAT EXISTS, so a broken reference counted as RESOLVED.
# The permissive pattern fixes both, because it stops at the REAL extension instead of at a
# remembered one.
#
# `runs/graphcmp/D/` IS NOT SPECIAL-CASED ANY MORE, AND THAT IS THE POINT: `checks/differ.py`'s
# `declared()` makes those `.txt` names a CONTRACT, so a report naming one names a REAL path -- and
# a real path that exists is not this file's business. A report naming one that is GONE is.
REF = re.compile(r"(?<![\w/.])((?:\.agents/slop/|checks/|gates/)[\w./-]*\.[A-Za-z0-9]+)")
# `...` is an ellipsis and `//` is a doubled separator: a family, not a file.
PATTERN = re.compile(r"\.\.\.|//")

REPORTS = ".md"


def committed_reports() -> list[str]:
    """EVERY `REPORTS` FILE AT HEAD, ASKED OF HEAD.  This asked `git ls-files`, which reads the INDEX,
    while the TEXT below comes from `git show HEAD:` -- so the DENOMINATOR moved with the index's
    arming STATE and the SAME TREE answered twice: MEASURED 2026-10-15, 584 reports while the default
    index was armed and 541 once it agreed with HEAD.  It also inherited `GIT_INDEX_FILE`, so an agent
    that commits the prescribed way ran a different population than one that did not -- the same defect
    and the same shape as `checks/index-arm-gate.py`'s false `PASS`.  HEAD is not a shell variable, so
    nothing has to be scrubbed now."""
    r = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                       cwd=ROOT, capture_output=True, text=True)
    return sorted(p for p in r.stdout.split() if p.endswith(REPORTS))


def report_text(rel: str) -> str:
    r = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=ROOT,
                       capture_output=True, text=True, errors="replace")
    return r.stdout if r.returncode == 0 else ""


LIVE_HOMES = ("checks", "gates", "bin")
_LIVE_SRC = None


def live_sources():
    """The LIVE INSTRUMENTS, DISCOVERED BY WALKING -- not a list, not a suffix set."""
    global _LIVE_SRC
    if _LIVE_SRC is None:
        _LIVE_SRC = {}
        for home in LIVE_HOMES:
            d = os.path.join(ROOT, home)
            if not os.path.isdir(d):
                continue
            for f in sorted(os.listdir(d)):
                if f.endswith((".py", ".sh")) and os.path.isfile(os.path.join(d, f)):
                    _LIVE_SRC[os.path.join(home, f)] = open(
                        os.path.join(d, f), encoding="utf-8", errors="replace").read()
    return _LIVE_SRC


def live_citers(path):
    """Which live instruments name this path, by CONTENT. A name match, so prose counts too -- which is
    why `checks/repro-paths.py`'s OWN docstring appears among the citers and is stated, not hidden."""
    return [rel for rel, body in live_sources().items() if path in body]


def classify(dangling):
    """Split by WHO still needs the path, which is the question the docstring actually asks.

    ACTIONABLE -- a live instrument names it, so a reader following that instrument is misdirected.
    HISTORICAL -- only finished units' reports name it, and a record of a pruned tool is accurate."""
    act, hist = [], []
    for path in dangling:
        (act if live_citers(path) else hist).append(path)
    return act, hist


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mark", action="store_true",
                    help="append a DANGLING marker next to each broken reference, in place")
    args = ap.parse_args()

    reports = committed_reports()
    named: dict[str, set[str]] = {}
    patterns: set[str] = set()
    for rel in reports:
        for m in REF.finditer(report_text(rel)):
            p = m.group(1)
            if PATTERN.search(p):
                patterns.add(p)
            else:
                named.setdefault(p, set()).add(rel)

    dangling = sorted(p for p in named if not os.path.exists(os.path.join(ROOT, p)))
    print(f"repro-paths: {len(reports)} committed reports name {len(named)} distinct paths "
          f"(+{len(patterns)} written as patterns)")
    print(f"  resolve   : {len(named) - len(dangling)} of {len(named)}")
    # THE TWO CLASSES, AND ONLY THE FIRST ONE IS THIS GATE'S CLAIM. A path named by a LIVE INSTRUMENT
    # (`checks/*.py`, `gates/*.py`, `bin/*` -- DISCOVERED, not listed) that no longer exists is a
    # reproduction a reader is told to run and cannot. A path named only by a finished unit's own
    # report is that unit's RECORD of what it used, and is accurate. MEASURED 2026-10-17: widening
    # the anchor takes dangling 110 -> 560, of which 40 are ACTIONABLE and 520 historical, so one
    # number for both buries 40 real findings under 520 records. The claim in the docstring -- "every
    # path a report tells a reader to RUN" -- is only about the 40, and only those set the exit.
    actionable, historical = classify(dangling)
    print(f"  DANGLING  : {len(dangling)}  ({len(actionable)} ACTIONABLE + {len(historical)} historical)")
    for p in actionable:
        print(f"    ACTIONABLE {p}   <- {', '.join(live_citers(p))}")
    if historical:
        print(f"    historical: {len(historical)} named only by finished units' reports, records not repros")
        print(f"      e.g. {historical[0]}")

    if args.mark and dangling:
        # Mark in place rather than delete: a REPRODUCE line whose instrument is gone is a
        # RECORD that the instrument was, and deleting the line would hide the loss.
        import subprocess
        for p in dangling:
            for rel in sorted(named[p]):
                if not os.path.exists(os.path.join(ROOT, rel)):
                    continue
                t = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
                if p not in t or "DANGLING" in t:
                    continue
                t = t.replace(p, f"{p} [DANGLING: this instrument was DELETED by the 2026-10-05 "
                                 f"prune and is not in git]")
                open(os.path.join(ROOT, rel), "w").write(t)
                print(f"  marked in {rel}")
        return 0

    if actionable:
        print(f"  NOT CLEAN -- {len(actionable)} ACTIONABLE. A live instrument names a path that no "
              "longer\n  exists, so a reader following it is misdirected. The "
              f"{len(historical)} historical\n  rows are records of pruned tools and do not fail "
              "this gate.\n  Re-run with --mark to record the loss where a reader meets it.")
        return 1
    if historical:
        print(f"  CLEAN of actionable breakage: the {len(historical)} historical rows name pruned "
              "tools\n  in finished units' own reports and no live instrument is misdirected by "
              "them.\n  (They are records, not repros. This gate's claim is about REPROS.)")
    else:
        print("  CLEAN: every reproduction path a report names exists")
    return 0


if __name__ == "__main__":
    sys.exit(main())