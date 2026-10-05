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
with a `.sh`/`.py`/`.bend` suffix, appearing in a committed report, is a reproduction reference.
Tokens containing `...` or `//` are **patterns**, not paths, and are counted separately rather than
reported as failures — because a report that writes `strays/origin/.../nvdev.bend` is describing a
family, and calling that a broken reference would be this file's own version of a false citation.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A path-shaped token under a directory this project owns, with an extension that means
# "something a report tells a reader to run".
REF = re.compile(r"(?:^|\s)((?:\.agents/slop/|checks/|gates/)[\w./-]+\.(?:sh|py|bend))")
# `...` is an ellipsis and `//` is a doubled separator: a family, not a file.
PATTERN = re.compile(r"\.\.\.|//")

REPORTS = ("*.md",)
REPORT_DIRS = (".agents/slop", ".agents", "checks", "gates", "")


def committed_reports() -> list[str]:
    out: list[str] = []
    for d in REPORT_DIRS:
        pat = os.path.join(d, "*.md") if d else "*.md"
        try:
            r = __import__("subprocess").run(["git", "ls-files", "--", pat],
                                             cwd=ROOT, capture_output=True, text=True)
            out += [x for x in r.stdout.split() if x.endswith(".md")]
        except Exception:
            pass
    return sorted(set(out))


def report_text(rel: str) -> str:
    import subprocess
    r = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=ROOT,
                       capture_output=True, text=True, errors="replace")
    return r.stdout if r.returncode == 0 else ""


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
    print(f"  DANGLING  : {len(dangling)}")
    for p in dangling:
        print(f"    {p}")
        print(f"        named by: {', '.join(sorted(named[p]))}")

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

    if dangling:
        print("  NOT CLEAN. A report that names an instrument which no longer exists is asking a "
              "reader\n  to trust a claim they cannot check -- and the discovery that they cannot "
              "check it costs more\n  than the claim was worth. Re-run with --mark to record the "
              "loss where a reader meets it.")
        return 1
    print("  CLEAN: every reproduction path a report names exists")
    return 0


if __name__ == "__main__":
    sys.exit(main())