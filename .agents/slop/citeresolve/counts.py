#!/usr/bin/env python3
"""Re-derive every literal count AGENTS.md / .agents/TOOLS.md assert, by DISCOVERY.

Each row prints the claim token, the ONE-LINE RULE that produces it, and the
current value.  Nothing is written outside this directory.
"""
from __future__ import annotations

import ast
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def sh(*args: str) -> str:
    return subprocess.run(args, cwd=ROOT, capture_output=True, text=True).stdout


def find(expr: str) -> int:
    return len([p for p in sh("find", *expr.split()).splitlines() if p.strip()])


def lines(rel: str) -> int:
    try:
        return sum(1 for _ in open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace"))
    except OSError:
        return -1


def load_module(rel: str, name: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, rel))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


ROWS: list[tuple[str, str, str]] = []


def row(token: str, rule: str, value: str) -> None:
    ROWS.append((token, rule, value))


def main() -> int:
    import subprocess as sp
    head = sh("git", "rev-parse", "HEAD").strip()

    row("134 .bend", "find tinybendygrad -name '*.bend' | wc -l", str(find("tinybendygrad -name *.bend")))
    row("140 port files", "find tinybendygrad -type f | wc -l", str(find("tinybendygrad -type f")))

    # TOOLS.md ledger population -- same rule as toolsledger/extract.py
    text = open(os.path.join(ROOT, ".agents/TOOLS.md"), encoding="utf-8").read()
    tracked = set(sh("git", "ls-files").split())

    def norm(t: str) -> str:
        t = t.strip().strip("*_[]()`").rstrip('.,;:)("')
        return t[2:] if t.startswith("./") else t

    toks = sorted({norm(t) for t in re.findall(r"`([^`\n]+)`", text) if "/" in norm(t)})
    toks = [t for t in toks if not (t.startswith(("http", "git@", "//")) or "github.com" in t)]
    toks = [t for t in toks if re.fullmatch(r"[~A-Za-z0-9_./@+\-]+", t)]

    def present(t: str) -> bool:
        if t.startswith("/"):
            return os.path.exists(t)
        if t in tracked or os.path.exists(os.path.join(ROOT, t)):
            return True
        return any(f.startswith(t.rstrip("/") + "/") for f in tracked)

    absent = [t for t in toks if not present(t)]
    abs_slop = [t for t in absent if t.startswith(".agents/slop/")]
    INSTR = re.compile(r"(gate|check|sweep|differ|e2e|repro|corpus|mutate|selftest|pin|census|no-txt|substrate)")
    abs_instr = [t for t in absent if INSTR.search(os.path.basename(t))]
    row("TOOLS.md distinct paths", "backtick tokens with '/' (toolsledger/extract.py rule)", str(len(toks)))
    row("TOOLS.md present", "same rule, exists on disk or in git ls-files", str(len(toks) - len(absent)))
    row("TOOLS.md gone", "same rule, absent", str(len(absent)))
    row("TOOLS.md gone under slop", "same rule, absent & .agents/slop/", str(len(abs_slop)))
    row("TOOLS.md gone instruments", "same rule, absent & basename matches instrument vocab", str(len(abs_instr)))

    # no-txt.py
    p = sp.run([os.path.join(ROOT, ".venv/bin/python"), "checks/no-txt.py"],
               cwd=ROOT, capture_output=True, text=True)
    excused = sum(int(m.group(1)) for m in re.finditer(r"(\d+) `\.txt` EXCUSED", p.stdout))
    hard = sum(int(m.group(1)) for m in re.finditer(r"(\d+) `\.txt` HARD", p.stdout))
    row("no-txt HARD", ".venv/bin/python checks/no-txt.py  (rc + 'HARD' lines)", f"{hard} (rc={p.returncode})")
    row("no-txt EXCUSED", "same, sum of 'N .txt EXCUSED'", str(excused))

    # differ.declared()
    try:
        d = load_module("checks/differ.py", "differprobe")
        row("differ.declared()", "len(differ.declared())", str(len(d.declared())))
    except Exception as e:  # noqa: BLE001
        row("differ.declared()", "len(differ.declared())", f"ERR {type(e).__name__}")

    row("AGENTS.md lines", "wc -l AGENTS.md", str(lines("AGENTS.md")))
    row("TOOLS.md lines", "wc -l .agents/TOOLS.md", str(lines(".agents/TOOLS.md")))
    row("TODO.md lines", "wc -l .agents/TODO.md", str(lines(".agents/TODO.md")))
    row("tracked REPORT.md", "git ls-files '.agents/slop/*/REPORT.md' | wc -l",
        str(len([p for p in sh("git", "ls-files", ".agents/slop/*/REPORT.md").splitlines() if p])))
    row("REPORT.md on disk", "find .agents/slop -name REPORT.md | wc -l",
        str(len(sh("find", ".agents/slop", "-name", "REPORT.md").splitlines())))
    import glob as _glob
    row("checks/*.sh", "ls checks/*.sh | wc -l", str(len(_glob.glob(os.path.join(ROOT, "checks/*.sh")))))
    row("gates/*.py", "ls gates/*.py | wc -l", str(len(_glob.glob(os.path.join(ROOT, "gates/*.py")))))
    row("gates/*.sh", "ls gates/*.sh | wc -l (expect 0)", str(len(_glob.glob(os.path.join(ROOT, "gates/*.sh")))))
    row("substrate.py lines", "wc -l checks/substrate.py", str(lines("checks/substrate.py")))
    row("graphcmp graphs", "grep graphs= runs/graphcmp/D/D0-run-summary.txt", 
        next((l.split("=", 1)[1] for l in open(os.path.join(ROOT, "runs/graphcmp/D/D0-run-summary.txt"), encoding="utf-8").read().splitlines() if l.startswith("graphs=")), "?"))
    row("D0 oracle-selfcheck", "grep oracle-selfcheck= runs/graphcmp/D/D0-run-summary.txt",
        next((l.split("=",1)[1] for l in open(os.path.join(ROOT, "runs/graphcmp/D/D0-run-summary.txt"), encoding="utf-8").read().splitlines() if l.startswith("oracle-selfcheck=")), "?"))
    row("census.rows rows", "wc -l .agents/slop/peakrss/census.rows",
        str(lines(".agents/slop/peakrss/census.rows")))
    row("slop dirs", "ls -d .agents/slop/*/ | wc -l", str(len(_glob.glob(os.path.join(ROOT, ".agents/slop/*/")))))
    row("*-mutate.py under slop", "find .agents/slop -name '*-mutate.py' | wc -l",
        str(len(sh("find", ".agents/slop", "-name", "*-mutate.py").splitlines())))

    print("claim\trule\tvalue")
    for t, r, v in ROWS:
        print(f"{t}\t{r}\t{v}")
    print(f"# HEAD={head}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
