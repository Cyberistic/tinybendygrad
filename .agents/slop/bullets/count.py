"""Re-derive the AGENTS.md bullet population by discovery. Python only, .venv interp."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MD = ROOT / "AGENTS.md"

# Rule (declared, not a hand list):
#  * TABLE   : a line whose first non-space char is '|'
#  * BULLET  : a line matching ^-  (top level) or ^  -  (nested), tables excluded.
#              A bullet body extends to the last non-blank continuation line that is
#              more indented than the bullet marker and is not itself a bullet start.
#  * WITH-INSTRUMENT : bullet text matches a path ending (checks|gates)/<name>.py
#                      OR a file:line citation (name.ext:NN).
#  * WITH-MEASUREMENT: bullet text contains the literal token MEASURED (case-insens).
#  * WITH-NEITHER    : neither of the two above.

INSTRUMENT_RE = re.compile(r"(?:checks|gates)/[A-Za-z0-9_.-]+\.py")
FILELINE_RE = re.compile(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:\d+")
MEASURED_RE = re.compile(r"measured", re.IGNORECASE)


def is_table(line: str) -> bool:
    return line.lstrip().startswith("|")


def bullet_start(line: str) -> re.Match[str] | None:
    return re.match(r"^( *)- ", line)


def main() -> int:
    lines = MD.read_text().split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]  # a trailing newline is not a line
    total = len(lines)

    starts: list[int] = []
    for i, ln in enumerate(lines):
        if not is_table(ln) and bullet_start(ln) is not None:
            starts.append(i)

    # assign each bullet a text block = its start line + following non-bullet, non-table,
    # non-blank continuation lines until the next bullet start or a blank-separated header.
    bullets = []
    for idx, s in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else total
        block = [lines[s]]
        for j in range(s + 1, end):
            ln = lines[j]
            if ln.strip() == "":
                break
            if is_table(ln):
                break
            block.append(ln)
        bullets.append((s + 1, "\n".join(block)))

    table_lines = sum(1 for ln in lines if is_table(ln))

    n = len(bullets)
    with_instr, with_meas, with_neither = [], [], []
    for lineno, txt in bullets:
        has_instr = bool(INSTRUMENT_RE.search(txt) or FILELINE_RE.search(txt))
        has_meas = bool(MEASURED_RE.search(txt))
        if has_instr:
            with_instr.append(lineno)
        if has_meas:
            with_meas.append(lineno)
        if not has_instr and not has_meas:
            with_neither.append(lineno)

    print(f"rule: table='|'+; bullet = ^( *)- ; body = following non-blank non-bullet lines")
    print(f"file_lines            = {total}")
    print(f"table_lines           = {table_lines}")
    print(f"bullets               = {n}")
    print(f"with_instrument       = {len(with_instr)}")
    print(f"with_measured         = {len(with_meas)}")
    print(f"with_neither          = {len(with_neither)}")
    print(f"neither_linenos       = {with_neither}")
    print()
    for lineno, txt in bullets:
        flags = ""
        flags += "I" if (INSTRUMENT_RE.search(txt) or FILELINE_RE.search(txt)) else "."
        flags += "M" if MEASURED_RE.search(txt) else "."
        if flags == "..":
            first = txt.split("\n")[0]
            print(f"[{flags}] L{lineno}: {first[:150]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
