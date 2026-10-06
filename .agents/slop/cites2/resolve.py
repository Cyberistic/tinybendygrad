#!/usr/bin/env python3
"""Re-resolve every `.bend:<N>` cite at a stated HEAD, by NEEDLE not by number.

Population: os.walk over checks/*.{py,sh,bend}, regex `<name>.bend:<N>`.
For each cite we carry the token its citing sentence expects (NEEDLE) and ask
the target file where that token is TODAY. A cite RESOLVES iff the needle is on
the cited line. Otherwise DRIFT (needle elsewhere), DELETED (needle nowhere),
or NARR (the sentence names a historical position, no current needle).

Emits TSV: check_file  check_line  ref  N  needle  status  current_lines
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CHECKS = os.path.join(ROOT, "checks")
CITE = re.compile(r"(?P<ref>[A-Za-z0-9_./-]+\.bend):(?P<num>\d+)")

# cite key = (check_relpath, N-of-first-cite-on-that-check-line) ; value = needle (regex)
# A needle of None means NARRATIVE: the sentence records a position, not a claim.
NEEDLE: dict[tuple[str, int], str | None] = {
    ("checks/abi_gate.py", 1064): r"def Dt\.i64_trunc",
    ("checks/env-precond.py", 308): r'getenv_int\("DEBUG"',
    ("checks/env-precond.py", 342): r"NO_COLOR|DEFAULT_FLOAT|DEFAULT_INT|SUM_DTYPE",
    ("checks/gate_norm.py", 42): r"0x7FC00000",
    ("checks/nl-gate.py", 125): r"String\.concat\(\[nm, \" = \[\"",
    ("checks/nvrows-deadrow-gate.py", 371): r"import Base",
    ("checks/nvrows-deadrow-gate.py", 48): r"import Base",
    ("checks/nvrows-deadrow-gate.py", 1770): r"def emit\(xs: List<&2, String>\)",
    ("checks/run-port-mm.sh", 49): r"Ops\.SHRINK.*HAS NO DTYPE",
    ("checks/stage1-census.py", 542): r"def ew_add",
    ("checks/unowned.py", 32): r"bend2-constraints\.md",
    # --- live targets (claims about current code) ---
    ("checks/disagree-gate.py", 1057): r"dtype: DType = dtypes\.void",
    ("checks/differ.py", 1066): r"ATuple\{ys: List<&2, U32>\}",
    ("checks/differ.py", 4560): r"ONE-BYTE|def UOp\.mselect|AInt\{k\}",
    ("checks/differ.py", 4554): r"ONE-BYTE|def UOp\.mselect|WALL\(p3\)",
    ("checks/rn-gate.py", 2148): r"def py_row",
    ("checks/rn-gate.py", 2693): r"def rnd_row",
    ("checks/rn-gate.py", 2763): r"def pu_line",
    ("checks/rn-gate.py", 2809): r'arg_repr A(Kern|Progr|Param)',
    # --- deleted subjects (cstyle.bend) ---
    ("checks/e2e.py", 2984): r"def rd_row\(nm: String, py: String",
    ("checks/e2e.sh", 2984): r"def rd_row\(nm: String, py: String",
    ("checks/run-f64.sh", 1879): r"def g_kernel",
    ("checks/run-port-mm.sh", 1879): r"def g_kernel",
    # --- narratives (no current needle) ---
    ("checks/nl-gate.py", 7837): None,
    ("checks/nl-gate.py", 7874): None,
    ("checks/run-port-mm.sh", 2551): None,
}


def read_lines(path: str) -> list[str] | None:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return None


def port_index() -> dict[str, list[str]]:
    idx: dict[str, list[str]] = {}
    for base in (os.path.join(ROOT, "tinybendygrad"), CHECKS, os.path.join(ROOT, ".agents", "slop")):
        for dirpath, _dirs, files in os.walk(base):
            for f in files:
                if f.endswith(".bend"):
                    rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
                    idx.setdefault(f, []).append(rel)
    return idx


def main() -> int:
    idx = port_index()
    rows = []
    for dirpath, _dirs, files in os.walk(CHECKS):
        for f in sorted(files):
            if not f.endswith((".py", ".sh", ".bend")):
                continue
            rel_check = os.path.relpath(os.path.join(dirpath, f), ROOT)
            for i, line in enumerate(read_lines(os.path.join(CHECKS, f)) or [], 1):
                for m in CITE.finditer(line):
                    ref, num = os.path.basename(m.group("ref")), int(m.group("num"))
                    cands = idx.get(ref, [])
                    needle = NEEDLE.get((rel_check, num))
                    if needle is None:
                        rows.append((rel_check, i, ref, num, cands[0] if cands else "", "NARR", ""))
                        continue
                    pat = re.compile(needle)
                    on, drift = "", ""
                    for c in cands:
                        tl = read_lines(os.path.join(ROOT, c)) or []
                        if 1 <= num <= len(tl) and pat.search(tl[num - 1]):
                            on = c
                            break
                        hits = [str(k) for k, t in enumerate(tl, 1) if pat.search(t)]
                        if hits and not drift:
                            drift = f"{c}:" + ",".join(hits[:6])
                    status = "RESOLVES" if on else ("DRIFT" if drift else "DELETED")
                    rows.append((rel_check, i, ref, num, on or (cands[0] if cands else ""), status, drift))
    print("check_file\tcheck_line\tref\tN\ttarget\tstatus\tcurrent_lines")
    for r in rows:
        print("\t".join(str(x) for x in r))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
