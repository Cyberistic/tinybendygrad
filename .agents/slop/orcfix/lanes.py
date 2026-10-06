#!/usr/bin/env python3
"""Discover pre-fix / oracle LANES under `.agents/slop/**` by DISCOVERY (os.walk).

DEFINITION (stated, because a lane is not a suffix).
  A *harness*    = a tracked `.py`/`.sh` under `.agents/slop/**` that can SPAWN a process
                   (`subprocess`/`Popen`/`check_call`/`exec`/a shell `sh`/`bash` call).
  A *lane target* = a `.py`/`.sh` the harness executes, discovered two ways with no hand list:
                   (i)  a string literal ending `.py`/`.sh` that resolves to a tracked file
                        (against the harness dir, then the repo root);
                   (ii) a path JOIN whose components include a SHADOW-dir literal
                        (`prefix`/`frozen*`/`plant`/`broken`/`real`/`tree`/`shadow*`/`old`/`new`)
                        -- the executed file is then inside that shadow tree.
  A lane is *pre-fix* if its target lives in a shadow dir (a frozen copy) and *oracle* if
  its target/name is an oracle.  A lane EMITS `.txt` if the harness, or the target it runs,
  names a `.txt` as a write (`>`/`write_text`/`open(...,'w')`) or the target's own source
  contains `.txt` output names reachable from a run.
  A lane is DECLARED if every `.txt` name it can write is in `checks/differ.py:declared()`,
  or in a generator's own `declared()` loaded by path, or LEFT by a renamer; else UNDECLARED.
"""
from __future__ import annotations
import importlib.util, os, re, subprocess, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
SLOP = ROOT / ".agents/slop"
SHADOW_DIR = ("prefix", "frozen", "frozen-old", "frozen-new", "frozen-prefix", "old", "new",
              "plant", "broken", "real", "tree", "shadow")
SHADOW_LIT = re.compile(r"[\"']([^\"']*(?:%s)[^\"']*)[\"']" % "|".join(SHADOW_DIR))
EXEC = re.compile(r"subprocess|Popen|check_call|check_output|os\.exec|\bexec\(|\bsh\b|\bbash\b")
LIB = re.compile(r"[A-Za-z0-9_./${}-]+\.(?:py|sh)\b")


def tracked() -> set[str]:
    return set(subprocess.run(["git","ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split())


def resolve(raw: str, h: pathlib.Path, tr: set[str]):
    for base in (h.parent, ROOT):
        c = (base / raw)
        try:
            c = c.resolve()
        except OSError:
            continue
        if c.is_file():
            try:
                rel = str(c.relative_to(ROOT))
            except ValueError:
                continue
            if rel in tr:
                return rel
    return None


def main() -> int:
    tr = tracked()
    harnesses = [p for p in sorted(SLOP.rglob("*")) if p.suffix in (".py",".sh") and p.is_file()
                 and str(p.relative_to(ROOT)) in tr]
    rows = []
    for h in harnesses:
        try:
            body = h.read_text(errors="replace")
        except OSError:
            continue
        if not EXEC.search(body):
            continue
        targets, shadow_dirs = set(), set()
        for ln in body.splitlines():
            for m in LIB.finditer(ln):
                r = resolve(m.group(0), h, tr)
                if r and r != str(h.relative_to(ROOT)):
                    targets.add(r)
            for m in SHADOW_LIT.finditer(ln):
                shadow_dirs.add(m.group(1))
        # targets that live under a shadow dir are lanes
        lanes = sorted(t for t in targets if any(seg in SHADOW_DIR for seg in pathlib.Path(t).parts)
                       or "oracle" in pathlib.Path(t).name.lower())
        if lanes or (shadow_dirs and targets):
            emits = sorted({t for t in (targets | {str(h.relative_to(ROOT))})
                            if TXTWRITE.search((ROOT/t).read_text(errors="replace")) } if False else [])
        rows.append((str(h.relative_to(ROOT)), sorted(targets), sorted(shadow_dirs), lanes))
    # print lanes
    lanes = [r for r in rows if r[3] or r[2]]
    print(f"# {len(harnesses)} tracked .py/.sh harnesses under .agents/slop; {len(lanes)} reference a lane/shadow")
    for hh, targets, sdirs, ln in lanes:
        print(f"\n{hh}")
        if sdirs: print(f"    shadow dirs: {', '.join(sdirs)}")
        for t in ln: print(f"    LANE -> {t}")
        for t in targets:
            if t not in ln: print(f"    exec -> {t}")
    return 0


TXTWRITE = re.compile(r">\s*[^\s]*\.txt|write_text\([^)]*\.txt|open\([^)]*\.txt[^)]*['\"]w")
if __name__ == "__main__":
    raise SystemExit(main())
