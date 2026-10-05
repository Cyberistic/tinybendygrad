#!/usr/bin/env python3
"""Two questions the raw run cannot answer: HOW MANY DISTINCT GATES, and HOW MANY DISTINCT PROBLEMS.

    .venv/bin/python .agents/slop/gatecensus/group.py            # both answers
    .venv/bin/python .agents/slop/gatecensus/group.py --why      # the red rows, quoted

DISTINCT GATES. Five units wrote `probe-*.py`, `norm()` variants and `mm-*` gates. Counting 458
files and calling that 458 gates is the same error as calling 356 gate-shaped files 356 gates.
Collapse is by CONTENT, not by name: byte-identical bodies are one gate with aliases, and near-
identical bodies are NOT collapsed, because under-counting a suite is the mirror image of
over-counting it and this project has already paid for both.

DISTINCT PROBLEMS. **A COUNT OF RED GATES IS NOT A COUNT OF PROBLEMS.** 40 reds will be one broken
file seen through 40 gates. So each red is reduced to a CAUSE KEY -- the `.bend`/`.c`/`.js` path it
names, or the missing symbol it names, or the exit shape -- and reds are grouped by that key. The
number that gets reported is the number of KEYS.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, ".agents/slop/gatecensus")

# `expected : a defined name / observed : P.r` is bend naming a symbol that does not exist, and it
# names the cause precisely. So do the compiler's other one-liners.
CAUSE = [
    # bend: "file:line:col: expected : X / observed : Y"
    (re.compile(r"([\w./-]+\.(?:bend|c|js|h)):\d+(?::\d+)?:\s*expected\s*:\s*(\S+)"), "missing-symbol"),
    (re.compile(r"expected\s*:\s*(\S+)\s*/\s*observed\s*:\s*(\S+)"), "missing-symbol"),
    # bend: "file:line:col: Duplicate declaration `X`"
    (re.compile(r"Duplicate declaration `([^`]+)`"), "duplicate-decl"),
    # bend: "file:line:col: Type mismatch"
    (re.compile(r"([\w./-]+\.(?:bend|c|js)):[\d:]*\s*Type mismatch"), "type-mismatch"),
    # the substrate's own vocabulary
    (re.compile(r"\bCOLD\b"), "cold-file"),
    (re.compile(r"no such file|FileNotFoundError|No such file or directory"), "missing-file"),
    (re.compile(r"ModuleNotFoundError|ImportError"), "import-error"),
    (re.compile(r"SyntaxError|IndentationError"), "syntax-error"),
    (re.compile(r"Permission denied"), "permission"),
    (re.compile(r"\bTraceback\b"), "python-traceback"),
    (re.compile(r"\bnot found\b|\bmissing\b"), "not-found"),
]


def cause_of(row: dict) -> str:
    """The CAUSE KEY for a red, taken from the gate's OWN quoted cause line.

    The first version of this function looked in `runs/<gate>.json` for the child's stderr, and when
    that file was missing it fell through to `unclassified: rc=1` -- so 96 of 129 reds came back as
    ONE bucket called "unclassified", which is not a finding, it is a shrug. **A cause key that
    cannot name a cause must be counted separately, loudly, rather than allowed to become the
    largest group.** So the key is derived from the text the run actually captured, and rows with no
    captured text are counted as `UNQUOTED` and excluded from the distinct-problem count.

    The key is deliberately coarse. Too fine re-counts one problem as N; too coarse merges two. Both
    have been measured wrong in this project, so the key stops at the DEFNAME or the missing PATH --
    the level at which a fix is one line and a citation is possible.
    """
    blob = row.get("verdict") or row.get("why") or ""
    if blob.startswith(("child rc=", "rc=0 with")):
        return "UNQUOTED: the harness captured no text for this red"
    for rx, key in CAUSE:
        m = rx.search(blob)
        if m:
            detail = m.group(1) if m.groups() else ""
            return f"{key}:{detail}" if detail else key
    # No pattern matched. Rather than one shrug-bucket, the text itself is the key, truncated --
    # because 96 reds that each say a DIFFERENT thing are 96 problems, and calling them one bucket
    # would under-count the suite by 16x, which is the mirror image of the error this file exists
    # to avoid.
    #
    # ONE EXCEPTION, MEASURED, AND IT IS THE LARGEST GROUP IN THE CENSUS: 38 gates die on
    # `IndexError: list index out of range` from `sys.argv[1]` with no argument. Verified by hand:
    #   .venv/bin/python .agents/slop/ag-diff.py
    #   File ".../ag-diff.py", line 9, in <module>
    #       bend = open(sys.argv[1]).read().split("\n")
    #   IndexError: list index out of range
    # That is ONE cause -- "this instrument needs a file argument and was run bare" -- seen by 38
    # gates, and it is the same class as the usage/REFUSED case that is already a SKIP. It is
    # collapsed to one key here, and the 38 rows are ALSO re-classified as SKIP in the status
    # table, because "run with its population" was never attempted for any of them.
    if "IndexError" in blob and "list index out of range" in blob:
        return "needs-a-file-argument: sys.argv[1] with no argument (run bare)"
    norm = " ".join(blob.split())[:90]
    return f"unclassified[{row.get('child_rc')}]: {norm}" if norm else "UNQUOTED: empty"


def main() -> int:
    res = json.load(open(os.path.join(OUT, "results.json")))
    rows = res["rows"]
    why = "--why" in sys.argv

    # --- DISTINCT GATES, by content -----------------------------------------------
    groups: dict[str, list[str]] = defaultdict(list)
    for r in rows:
        p = os.path.join(ROOT, r["rel"])
        try:
            with open(p, "rb") as fh:
                groups[hashlib.sha256(fh.read()).hexdigest()].append(r["rel"])
        except OSError:
            groups["unreadable"].append(r["rel"])
    aliases = {k: v for k, v in groups.items() if len(v) > 1}
    print("# DISTINCT GATES")
    print(f"#   gate-shaped files run                       {len(rows)}")
    print(f"#   DISTINCT by byte content                    {len(groups)}")
    print(f"#   byte-identical families                     {len(aliases)}"
          f"   [{len(rows) - len(groups)} files saved by collapsing]")
    print(f"#   largest families:")
    for k, v in sorted(aliases.items(), key=lambda kv: -len(kv[1]))[:12]:
        print(f"#     {len(v)}x  {v[0]}" + (f"   (+{len(v)-1} identical)" if len(v) > 1 else ""))

    # --- DISTINCT PROBLEMS, from the reds -------------------------------------------
    reds = [r for r in rows if r["status"] == "FAIL"
            and not cause_of(r).startswith("needs-a-file-argument")]
    causes = defaultdict(list)
    for r in reds:
        causes[cause_of(r)].append(r["rel"])
    print(f"\n# REDS GROUPED BY CAUSE")
    print(f"#   FAIL rows                                  {len(reds)}")
    print(f"#   DISTINCT PROBLEMS                          {len(causes)}")
    print(f"#   red gates per problem, mean                 "
          f"{(len(reds)/len(causes)) if causes else 0:.1f}")
    for k, v in sorted(causes.items(), key=lambda kv: -len(kv[1])):
        print(f"   {len(v):4d}  {k}")
        if why:
            for f in v[:6]:
                print(f"          {f}")
            if len(v) > 6:
                print(f"          ... +{len(v)-6} more")

    by_status = defaultdict(int)
    for r in rows:
        by_status[r["status"]] += 1
    # A red whose cause is "needs a file argument" is a SKIP, not a FAIL. Reclassified here rather
    # than in `run.py` so that the correction is visible next to the raw counts: 38 FAIL rows are
    # 38 SKIP rows, and pretending otherwise inflates both the red count and the problem count.
    reclass = [r for r in rows if r["status"] == "FAIL"
               and cause_of(r).startswith("needs-a-file-argument")]
    for r in reclass:
        r["status"] = "FAIL->SKIP (needs a file argument; run bare)"
        by_status["FAIL"] -= 1
        by_status["FAIL->SKIP (needs a file argument; run bare)"] = \
            by_status["FAIL->SKIP (needs a file argument; run bare)"] + 1
    n_unsafe = res["unsafe"] if isinstance(res["unsafe"], int) else len(res["unsafe"])
    print(f"\n# STATUS over {res['denominator']} denominator "
          f"({res['attempted']} attempted, {n_unsafe} excluded UNSAFE)")
    for k in ("PASS", "FAIL", "NOT-RUN", "SKIP"):
        print(f"#   {k:8s} {by_status.get(k,0):4d} / {res['denominator']}")
    print(f"#   I COULD NOT RUN {by_status.get('NOT-RUN',0) + by_status.get('SKIP',0) + n_unsafe}"
          f" of {res['denominator']}  (NOT-RUN {by_status.get('NOT-RUN',0)}"
          f" + SKIP {by_status.get('SKIP',0)} + UNSAFE {n_unsafe})")

    json.dump({"distinct_gates": len(groups), "alias_families": aliases,
               "reds": len(reds), "distinct_problems": len(causes),
               "causes": {k: v for k, v in causes.items()},
               "by_status": dict(by_status), "denominator": res["denominator"]},
              open(os.path.join(OUT, "grouped.json"), "w"), indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())