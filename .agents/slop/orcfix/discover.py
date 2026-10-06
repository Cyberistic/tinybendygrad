#!/usr/bin/env python3
"""Discover pre-fix/oracle LANES: a lane is an executed `.py`/`.sh` target that is a
frozen COPY (shadow dir) or an ORACLE/gate lane, launched by a harness under `.agents/slop/**`.

Population by DISCOVERY: `os.walk(.agents/slop)` for `.py`/`.sh`, plus git-ls track check.
A lane target is a string literal ending `.py`/`.sh` in a harness, resolved against the
harness dir then the repo root.
"""
from __future__ import annotations
import os, re, subprocess, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
SLOP = ROOT / ".agents/slop"
SHADOW = re.compile(r"(^|/)(prefix|frozen-?old|frozen-?new|frozen-prefix|frozen|shadow[^/]*|plant|broken|real|tree|oracles?)(/|$)")
LIB = re.compile(r"[A-Za-z0-9_./${}-]+\.(?:py|sh)\b")
# subprocess/exec constructs: any literal on a line with subprocess/Popen/check_call/exec
EXEC = re.compile(r"subprocess|Popen|check_call|check_output|os\.exec|shlex|\bexec\(")

def tracked() -> set[str]:
    out = subprocess.run(["git","ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    return set(out)

def main() -> int:
    tr = tracked()
    harnesses = [p for p in SLOP.rglob("*") if p.suffix in (".py",".sh") and p.is_file()
                 and str(p.relative_to(ROOT)) in tr]
    edges = []
    for h in harnesses:
        try:
            lines = h.read_text(errors="replace").splitlines()
        except OSError:
            continue
        for i, ln in enumerate(lines, 1):
            if not EXEC.search(ln):
                continue
            for m in LIB.finditer(ln):
                raw = m.group(0)
                if raw.startswith(("http",)): continue
                for base in (h.parent, ROOT):
                    cand = (base / raw)
                    try:
                        cand = cand.resolve()
                    except OSError:
                        continue
                    if cand.exists() and cand.is_file() and str(cand.relative_to(ROOT)) in tr:
                        rel = str(cand.relative_to(ROOT))
                        edges.append((str(h.relative_to(ROOT)), rel, i, raw))
                        break
    # dedupe (harness,target)
    seen = {}
    for hh, tt, i, raw in edges:
        seen.setdefault((hh, tt), (i, raw))
    print(f"# {len(harnesses)} tracked harnesses under .agents/slop")
    print(f"# {len(seen)} harness -> executed-target edges")
    shadowed = []
    for (hh, tt), (i, raw) in sorted(seen.items()):
        if SHADOW.search(tt) or "oracle" in tt.lower():
            shadowed.append((hh, tt, i))
    print(f"# {len(shadowed)} edges whose TARGET is a frozen/shadow/oracle lane:")
    for hh, tt, i in shadowed:
        print(f"  {hh}:{i}  ->  {tt}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
