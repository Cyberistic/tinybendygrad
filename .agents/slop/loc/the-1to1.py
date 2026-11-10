#!/usr/bin/env python3
"""the-1to1.py -- **THE 1:1 METRIC**, AS A REPEATABLE INSTRUMENT.

    .venv/bin/python .agents/slop/loc/the-1to1.py
    .venv/bin/python .agents/slop/loc/the-1to1.py --json

**WHAT IT MEASURES, AND **WHY **EVERY **TERM **IS **CORRECTED**:

  * **THE PORT's POPULATION IS **THE **TRACKED** FILES** -- `git ls-tree -r HEAD`, **AND NOT
    `git ls-files`**, BECAUSE **THE TREE's INDEX IS ARMED** (`checks/index-arm-gate.py`) **AND
    AN ARMED INDEX **LISTS **A **DIFFERENT **SET** OF FILES** (`checks/repro-paths.py` MEASURED
    `584` UNDER AN ARMED INDEX **AND `541` UNDER A DISARMED ONE, **SAME TREE**).**
  * **THE MAPPING IS **THE PORT FILE's OWN HEADER** -- **EACH FILE NAMES ITS UPSTREAM
    COUNTERPART** (`tinygrad/uop/ops.py`), **AND THE HEADER IS **WHERE **THE CENSUS
    READS IT.** **AND **A FILE WITH **NO** UPSTREAM NAME **IS **THE **TREE's OWN** (AND IT
    IS **COUNTED **AND **LISTED **SEPARATELY**, **NOT **SILENTLY **DROPPED**).**
  * **THE UPSTREAM's POPULATION IS **THE PIN `f5ac54685074`**, **NOT `HEAD`** -- **BECAUSE
    THE PORT WAS WRITTEN AGAINST **THAT** REVISION, **AND **A COMPARISON AGAINST `HEAD` IS **A
    COMPARISON AGAINST **A DIFFERENT **SPECIFICATION**.**
  * **THE `*-mut.bend` FILES ARE EXCLUDED** -- **MEASURED: `.gitignore` HAS `*mut.bend`
    ("in-place mutation scratch") AND `checks/differ.py:1936` CALLS THEM "FIVE GITIGNORED
    SCRATCH FILES" THAT A MUTATION PROBE **REWRITES AS IT RUNS**.** **THEY ARE **NOT **THE
    PORT** **AND **THEY ARE **NOT **EVEN **IN **THE **TRACKED **SET** ANYWAY.**

**AND THE FOUR NUMBERS IT PRINTS ARE **THE **FOUR **CLASSES **THAT **MATTER**:**

| class | what it is |
|---|---|
| **GATE ROWS** | THE INSTRUMENT, WHICH **BELONGS IN `gates/`** (`gates/README.md:173`) |
| **COMMENTS** | THE PROSE, **AND **THE **CITATIONS **AND **MEASUREMENTS** ARE LOAD-BEARING** |
| **BLANK** | NOTHING |
| **CODE** | **THE ONLY LINES THAT ARE **THE PORT** |

**AND THE HEADLINE IS **THE CODE-ONLY RATIO**, **BECAUSE **A COMMENT IS **NOT **A LINE OF
PORT** **AND **A GATE ROW IS **NOT **EITHER** -- **AND **THE WHOLE POINT OF THE EXERCISE IS
**THE PORT's CODE** GETTING CLOSE TO **UPSTREAM's CODE**.**
"""

import argparse
import collections
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
PIN = "f5ac54685074"
UPSTREAM = re.compile(r"tinygrad/([A-Za-z0-9_/]+\.py)")
SUFFIX = ".bend"


def tracked() -> list[str]:
    """**`git ls-tree -r HEAD`, **NOT `git ls-files`** -- **THE INDEX IS ARMED**."""
    out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                         cwd=ROOT, capture_output=True, text=True).stdout.split()
    return [p for p in out if p.startswith("tinybendygrad/") and p.endswith(SUFFIX)]


def upstream_lines(path: str) -> tuple[int, int]:
    """**(TOTAL LINES, CODE LINES) **OF **THE **PIN's** FILE** -- **AND **A MISSING FILE IS
    **A **ZERO**, **NOT **A **CRASH**."""
    r = subprocess.run(["git", "show", f"{PIN}:{path}"], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode != 0:
        return 0, 0
    lines = r.stdout.splitlines()
    code = sum(1 for l in lines if l.strip() and not l.strip().startswith("#"))
    return len(lines), code


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    agg = collections.defaultdict(lambda: [0, 0, 0, 0])   # rows, comments, blank, code
    unmapped = []
    for p in tracked():
        f = ROOT / p
        if not f.exists():
            continue
        lines = f.read_text(errors="replace").splitlines()
        ups = set(UPSTREAM.findall("\n".join(lines[:40])))
        if not ups:
            unmapped.append((len(lines), p))
            continue
        g = sum(1 for l in lines if l.strip().startswith(("srow(", "row(")))
        b = sum(1 for l in lines if not l.strip())
        c = sum(1 for l in lines if l.strip().startswith("#"))
        k = len(lines) - g - b - c
        for u in ups:
            agg[u][0] += g; agg[u][1] += c; agg[u][2] += b; agg[u][3] += k

    G = C = B = K = 0
    for v in agg.values():
        G += v[0]; C += v[1]; B += v[2]; K += v[3]
    T = G + C + B + K
    mu = mu_c = 0
    for u in agg:
        t, c = upstream_lines("tinygrad/" + u)
        mu += t; mu_c += c

    if args.json:
        print(json.dumps({
            "port_lines": T, "upstream_lines": mu, "ratio": round(T / mu, 2) if mu else 0,
            "gate_rows": G, "comments": C, "blank": B, "code": K,
            "upstream_code": mu_c, "code_ratio": round(K / mu_c, 2) if mu_c else 0,
            "unmapped_files": len(unmapped),
            "unmapped_lines": sum(n for n, _ in unmapped),
        }, indent=2))
        return 0

    print("  THE 1:1 METRIC -- the tracked port, mapped by its own headers, against the pin")
    print()
    print("    the port      %7d lines" % T)
    print("    upstream      %7d lines   (at %s)" % (mu, PIN))
    print("    THE RATIO     %7.2fx" % (T / mu if mu else 0))
    print()
    print("    the port's composition:")
    print("      GATE ROWS  %6d  (%2.0f%%)   belongs in gates/" % (G, G / T * 100 if T else 0))
    print("      COMMENTS   %6d  (%2.0f%%)   citations and measurements are load-bearing" % (C, C / T * 100 if T else 0))
    print("      BLANK      %6d  (%2.0f%%)" % (B, B / T * 100 if T else 0))
    print("      CODE       %6d  (%2.0f%%)   the only lines that are the port" % (K, K / T * 100 if T else 0))
    print()
    print("    THE CODE-ONLY RATIO: %d vs upstream's %d = %.2fx" % (K, mu_c, K / mu_c if mu_c else 0))
    print()
    print("    the port's own files with NO upstream counterpart: %d files, %d lines" % (
        len(unmapped), sum(n for n, _ in unmapped)))
    for n, p in sorted(unmapped, reverse=True)[:5]:
        print("      %6d  %s" % (n, p.replace("tinybendygrad/", "")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
