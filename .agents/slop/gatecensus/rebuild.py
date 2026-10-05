#!/usr/bin/env python3
"""Rebuild results.json from run.log. BECAUSE A PRUNE TOOK THE JSON AND LEFT THE LOG.

    .venv/bin/python .agents/slop/gatecensus/rebuild.py

WHY THIS FILE IS NECESSARY AND NOT A CONVENIENCE. `run.py` wrote its rows to two places at once:
`run.log` (the human-readable transcript, every row with its quoted cause) and `results.json` (the
machine form). A prune at 16:09 deleted the whole of `.agents/slop/gatecensus/`. The LOG came back
from git and the JSON did not, because the JSON was still uncommitted when the prune ran.

**THE CONSEQUENCE IS THE POINT: the transcript is the durable artifact and the JSON was a
convenience.** Any claim in a report that rests only on the JSON is a claim with no evidence behind
it. So this file rebuilds the JSON from the log, and the report cites `run.log` as the artifact.

THE ROWS THAT CANNOT COME BACK ARE COUNTED, NOT PAPERED OVER. Pass 2 was interrupted at 62 of 184,
so 122 rows have a pass-1 verdict and no re-run at the long leash. They are `NOT-RUN` in the
rebuilt table only if pass 1 said so; where pass 1 said FAIL, that FAIL stands, because a longer
leash cannot turn a red into a green -- it can only turn a NOT-RUN into a verdict. **A NOT-RUN that
was never re-run is reported as NOT-RUN.**
"""
from __future__ import annotations

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, ".agents/slop/gatecensus")

# `[p1  17/438] FAIL     WITHIN-LIMITS rc=   1     1.6s  .agents/slop/x.py`
ROW = re.compile(
    r"^\[(?P<pass>p\d)\s+(?P<i>\d+)/(?P<n>\d+)\]\s+(?P<status>PASS|FAIL|NOT-RUN|SKIP)\s+"
    r"(?P<bound>\S+)\s+rc=\s*(?P<rc>-?\d+)\s+(?P<secs>[\d.]+)s\s+(?P<rel>\S+)")
# The cause is on the NEXT line, indented, after `:: `.
CAUSE = re.compile(r"^\s+::\s?(?P<why>.*)$")


def main() -> int:
    rows: dict[str, dict] = {}
    last: str | None = None
    for line in open(os.path.join(OUT, "run.log")):
        m = ROW.match(line)
        if m:
            r = m.group("rel")
            rows[r] = {"rel": r, "status": m.group("status"), "bound": m.group("bound"),
                       "child_rc": int(m.group("rc")), "pass": int(m.group("pass")[1:]),
                       "wall_s": float(m.group("secs")), "verdict": ""}
            last = r
            continue
        c = CAUSE.match(line)
        if c and last:
            why = c.group("why").strip()
            # The cause line is stored as the row's `why`, and when it is not one of the harness's
            # own reason strings it IS the gate's verdict text. That distinction matters: a FAIL
            # whose `why` is `child rc=1 within both bounds` has no quoted cause and must not be
            # presented as one.
            rows[last]["why"] = why
            if not why.startswith(("child rc=", "rc=0 with", "KILLED", "TIMED", "ZERO bytes",
                                   "printed usage", "our watchdog", "SIGALRM", "SIGKILL",
                                   "could not", "harness error", "bounded.py")):
                rows[last]["verdict"] = why
            last = None
    table = list(rows.values())
    tally: dict[str, int] = {}
    for r in table:
        tally[r["status"]] = tally.get(r["status"], 0) + 1
    print(f"# REBUILT from run.log: {len(table)} rows")
    print(f"#   pass-1 rows {sum(1 for r in table if r['pass']==1)}"
          f"   pass-2 rows {sum(1 for r in table if r['pass']==2)}")
    for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"#   {k:8s} {v:4d}")
    unrun = tally.get("NOT-RUN", 0)
    print(f"#   I COULD NOT RUN {unrun} of {len(table)} that I attempted.")
    json.dump({"denominator": 455, "attempted": 438, "unsafe": 17,
               "rows": table, "tally": tally, "rebuilt_from": "run.log"},
              open(os.path.join(OUT, "results.json"), "w"), indent=1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())