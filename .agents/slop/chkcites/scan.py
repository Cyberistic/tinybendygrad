#!/usr/bin/env python3
"""Discover every `.bend:<N>` citation in checks/*.{py,sh,bend} and resolve it.

Population: files matched by `checks/*.py`, `checks/*.sh`, `checks/*.bend`.
A citation is `<name>.bend:<N>`. Resolve `<name>.bend` under `tinybendygrad/`
by basename walk (and `checks/` for `ag-emit.bend`). Then read line <N>.

Emits TSV: check_file  check_line  ref  N  target_relpath  status  line_text
status in {RESOLVES, RESOLVES-AMBIG, GONE-FILE, OUT-OF-RANGE}
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CHECKS = os.path.join(ROOT, "checks")
PORT = os.path.join(ROOT, "tinybendygrad")

CITE = re.compile(r"(?P<ref>[A-Za-z0-9_./-]+\.bend):(?P<num>\d+)")


def port_index() -> dict[str, list[str]]:
    idx: dict[str, list[str]] = {}
    for base in (PORT, CHECKS):
        for dirpath, _dirs, files in os.walk(base):
            for f in files:
                if f.endswith(".bend"):
                    rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
                    idx.setdefault(f, []).append(rel)
    return idx


def read_lines(path: str) -> list[str] | None:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return None


def main() -> int:
    idx = port_index()
    rows: list[tuple] = []
    for dirpath, _dirs, files in os.walk(CHECKS):
        for f in sorted(files):
            if not (f.endswith(".py") or f.endswith(".sh") or f.endswith(".bend")):
                continue
            cpath = os.path.join(dirpath, f)
            rel_check = os.path.relpath(cpath, ROOT)
            for i, line in enumerate(read_lines(cpath) or [], 1):
                for m in CITE.finditer(line):
                    ref, num = m.group("ref"), int(m.group("num"))
                    base = os.path.basename(ref) if "/" not in ref else None
                    cands = idx.get(os.path.basename(ref), [])
                    if not cands:
                        status, target, text = "GONE-FILE", "", ""
                    elif len(cands) > 1:
                        # prefer an exact suffix match when the cite carried a path
                        exact = [c for c in cands if c.endswith(ref)] or cands
                        target = exact[0]
                        lines = read_lines(os.path.join(ROOT, target)) or []
                        if num >= 1 and num <= len(lines):
                            status, text = "RESOLVES-AMBIG", lines[num - 1].strip()
                        else:
                            status, text = "OUT-OF-RANGE", ""
                    else:
                        target = cands[0]
                        lines = read_lines(os.path.join(ROOT, target)) or []
                        if num >= 1 and num <= len(lines):
                            status, text = "RESOLVES", lines[num - 1].strip()
                        else:
                            status, text = "OUT-OF-RANGE", ""
                    rows.append((rel_check, i, ref, num, target, status, text))
    print("check_file\tcheck_line\tref\tN\ttarget\tstatus\tline_text")
    for r in rows:
        print("\t".join(str(x) for x in r))
    n_res = sum(1 for r in rows if r[5] in ("RESOLVES", "RESOLVES-AMBIG"))
    n_gone = sum(1 for r in rows if r[5] == "GONE-FILE")
    n_oor = sum(1 for r in rows if r[5] == "OUT-OF-RANGE")
    print(f"# total={len(rows)} resolves={n_res} gone={n_gone} out_of_range={n_oor}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
