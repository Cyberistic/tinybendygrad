#!/usr/bin/env python3
"""clang-cost.py -- the PER-FUNCTION cost, measured, not estimated.

ffi-port-cost.py predicts ~3 law lines + ~3 C lines per function
(LAW_LINES_PER_FN = 3, C_LINES_PER_FN = 3) from ONE three-function experiment.
This reads the GENERATED files and splits every line into "shared, written once"
and "marginal, one per binding", so the estimate can be compared with what was
actually paid.

  usage: clang-cost.py <dir>      dir holds shim.c and shim.bend

The Bend side is counted STRUCTURALLY rather than by subtraction, because a
subtraction that guessed the header size wrong once reported 3.00 lines/law for
a 6-line block.

  A law block is exactly SIX lines:
      law clang_x:
        <domain> -> IO(<codomain)>
      <blank>
      def clang_x(<params>):
        import "./shim.c"
      <blank>
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

LAW_BLOCK = 6


def bend_costs(path: Path) -> tuple[int, int, int]:
    """(laws, marginal lines, shared lines)."""
    lines = path.read_text().splitlines()
    laws = [l for l in lines if re.match(r"^law clang_\w+:$", l)]
    names = {re.match(r"^law (clang_\w+):$", l).group(1) for l in laws}
    marginal = 0
    i = 0
    while i < len(lines):
        m = re.match(r"^law (\w+):$", lines[i])
        if m and m.group(1) in names:
            # law-name, type, blank, def, import, blank
            j = i + 1
            while j < len(lines) and not re.match(r"^def \w+\(", lines[j]):
                j += 1
            while j < len(lines) and lines[j].strip() != "":
                j += 1
            while j < len(lines) and lines[j].strip() == "":
                j += 1
            marginal += j - i
            i = j
            continue
        i += 1
    return len(laws), marginal, len(lines) - marginal


def c_costs(path: Path, names: set[str]) -> tuple[dict[str, int], int]:
    """Per binding: its extern declaration, its _run body, its io_eff line."""
    lines = path.read_text().splitlines()
    per: dict[str, int] = {}
    for i, l in enumerate(lines):
        m = re.match(r"^Term (clang_\w+)_run\(Env e, Term\* f, IoWork\* w\) \{$", l)
        if not m or m.group(1) not in names:
            continue
        k, j = 1, i + 1
        while j < len(lines) and lines[j] != "}":
            k += 1
            j += 1
        k += 1                                        # the closing brace
        e = any(re.match(r"^extern .*\b" + m.group(1) + r"\(", lines[q])
                for q in range(i - 1, -1, -1))
        g = f"  io_eff(CID({m.group(1)}), {m.group(1)}_run, 0);" in lines
        per[m.group(1)] = k + int(e) + int(g)
    return per, len(lines) - sum(per.values())


def main() -> int:
    d = Path(sys.argv[1])
    bend = (d / "shim.bend").read_text().splitlines()
    names = {m.group(1) for m in
             (re.match(r"^law (clang_\w+):$", l) for l in bend) if m}
    n = len(names)
    laws, mb, sb = bend_costs(d / "shim.bend")
    per, sc = c_costs(d / "shim.c", names)
    v = sorted(per.values())
    tot_c = len((d / "shim.c").read_text().splitlines())
    tot_b = len(bend)
    print(f"bindings                      : {n}")
    print(f"BEND  marginal / law          : {mb / laws:.2f} lines  "
          f"(measured; the block is {LAW_BLOCK} lines)")
    print(f"BEND  shared, written once   : {sb} lines  "
          f"(header, import, the blocked table, main's caller lines)")
    print(f"C     marginal / binding      : min {v[0]} median {v[len(v)//2]} "
          f"max {v[-1]} mean {sum(v)/len(v):.2f} lines")
    print(f"C     shared, written once   : {sc} lines")
    print(f"TOTAL lines                  : shim.c {tot_c} + shim.bend {tot_b} "
          f"= {tot_c + tot_b} for {n} bindings")
    print(f"                             = {(tot_c + tot_b) / n:.2f} lines/binding "
          f"ALL-IN, every shared line included")
    print(f"vs ffi-port-cost.py's estimate: 3 law + 3 C = 6 lines/function "
          f"-> MEASURED {mb / laws:.1f} + {sum(v)/len(v):.1f} = "
          f"{(mb / laws) + sum(v)/len(v):.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())