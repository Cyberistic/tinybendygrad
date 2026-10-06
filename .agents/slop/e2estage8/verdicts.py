#!/usr/bin/env python3
"""EVERY STAGE `checks/e2e.py` EMITS, WITH THE DENOMINATOR OF EACH, COUNTED OUT OF ITS OWN BLOCK.

    usage: .venv/bin/python .agents/slop/e2estage8/verdicts.py [TRANSCRIPT] [GATE]
           TRANSCRIPT defaults to `.agents/slop/e2epy/artifacts/live.port.out`, GATE to
           `checks/e2e.py`. A stage absent from TRANSCRIPT is printed as RETIRED and is not an error.

**A VERDICT WITH NO DENOMINATOR IS NOT A GATE.** A denominator is the count of the things a stage
compares, and it is counted HERE, out of the artifact, by one rule per stage -- never declared by the
stage about itself. Three failures, and it exits 1 on any of them:

  * an EMITTED stage whose denominator counts **0**. Such a stage cannot fail on the bug it exists
    for, so it cannot pass either, and its presence makes the stages around it look like a suite.
  * an EMITTED stage that RAN and printed no countable row, so nothing can be held responsible.
    A stage that SKIPPED is exempt: it measured nothing, and `SKIP IS NOT PASS` cuts both ways.
  * **the stage names in the gate's PROSE, the stage headers its CODE emits, and the stage headers in
    a run's TRANSCRIPT do not agree.** This is the check that would have caught the retirement's
    two failures. `RETIRED` appeared in `checks/e2e.py`'s docstring while stage 8 was still emitted at
    the code line, so the prose a reader trusts and the program that runs disagreed, and no reader
    running `--help` could tell which one was true.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = ROOT / ".agents/slop/e2epy/artifacts/live.port.out"
HEADER = re.compile(r"^== (\d+)/\d+ (.*)$")
VERDICT = re.compile(r"^  (stage \d+ [^:]*): (PASS|FAIL \(rc=-?\d+\)|SKIP -- .*)$")
# THE THREE READERS OF A STAGE LIST, AND THE ONLY THING THAT KEEPS THEM HONEST IS THAT THEY MUST
# AGREE. `PROSE` is the gate's own docstring stage table, `CODE` is what `say("== n/...")` prints, and
# `TRANSCRIPT` is what a run actually emitted. Any pair of them disagreeing is a reader being misled,
# and the docstring is the one that is trusted and never executed.
#
# A PROSE ROW THAT SAYS `RETIRED` IS THE RECORD OF A RETIREMENT, NOT A STAGE, and it is counted apart
# from the live rows -- otherwise naming the retirement is the same defect as keeping the stage.
PROSE = re.compile(r"^  (\d)  \S+.*$", re.M)
CODE = re.compile(r'say\("== (\d+)/')

# ONE RULE PER STAGE, AND EVERY COUNT BELOW IS READ OUT OF THE TRANSCRIPT, NOT ASSERTED. Stages 1, 3
# and 4 are the three whose claim IS a status rather than a row count, and their denominator is the
# 1 item that can disagree; the other five are counted by their own printed line.
COUNTED: dict[int, tuple[str, str]] = {
    1: ("the oracle's own exit status, which under `set -e` IS the gate's exit status", None),
    2: ("`name=value` rows a clean bend printed (want > 20)", r"^bend: (\d+) rows"),
    3: ("node's exit status, and nothing else", None),
    4: ("`mm_e2e_*` rows the gate compared against CPython", r"^mm_e2e_\w+="),
    5: ("rows read back out of PACKET.out", r"# \d+ failed of (\d+) rows read"),
    6: ("u32 words read back, against CPython's", r"words port=(\d+)  CPython=\d+"),
    7: ("u32 words (32 doubles) read back, against CPython's", r"F64-1 words_port=(\d+)"),
    8: ("rows that REACH `dtype.js`", r"rows that REACH `dtype\.js`\s+(\d+)"),
}
STAGES = sorted(COUNTED)


def blocks(text: str) -> dict[int, list[str]]:
    """Stage number -> that stage's own lines. `== n/m` opens a stage; the verdict lines and every
    body line between two headers belong to the one they are in."""
    out: dict[int, list[str]] = {}
    for ln in text.splitlines():
        if m := HEADER.match(ln):
            out[int(m.group(1))] = []
        elif out:
            out[max(out)] += [ln]
    return out


def denominator(n: int, body: list[str]) -> int | None:
    """The count, or `None` when this stage's rule found nothing to count. `None` and `0` are
    different answers and are kept apart: `None` means the stage printed no countable row, `0` means
    it printed rows and every one of them is exempt."""
    _, rx = COUNTED[n]
    if rx is None:
        return 1
    pat = re.compile(rx, re.M)
    if not (hit := pat.search("\n".join(body))):
        return None
    return int(hit.group(1)) if pat.groups else len(pat.findall("\n".join(body)))


def agree(gate: Path, emitted: set[int], bad: list[str]) -> None:
    """PROSE, CODE and TRANSCRIPT must name the same stages. Reported as a diff between the sets, so
    the answer says WHICH stage a reader would be misled about."""
    src = gate.read_text()
    rows = [(int(m.group(1)), "RETIRED" in m.group(0)) for m in PROSE.finditer(src)]
    prose = {n for n, gone in rows if not gone}
    retired = {n for n, gone in rows if gone}
    code = {int(n) for n in CODE.findall(src)}
    print(f"--- PROSE      {len(prose)} live: {' '.join(str(x) for x in sorted(prose))}"
          + (f"   |   {len(retired)} RETIRED: {' '.join(str(x) for x in sorted(retired))}"
             if retired else ""))
    print(f"--- CODE       {len(code)} stage(s): {' '.join(str(x) for x in sorted(code))}")
    print(f"--- TRANSCRIPT {len(emitted)} stage(s): {' '.join(str(x) for x in sorted(emitted))}")
    if prose != code:
        bad.append(f"{gate.name}: PROSE names {sorted(prose - code)} the CODE does not emit, and "
                   f"{sorted(code - prose)} the CODE emits and the PROSE does not name -- the "
                   f"docstring and the program disagree, and the docstring is the one a reader "
                   f"trusts")
    if code != emitted:
        bad.append(f"{gate.name}: CODE emits {sorted(code - emitted)} this transcript does not "
                   f"contain, and {sorted(emitted - code)} this transcript contains and the CODE "
                   f"does not emit -- the gate and its own artifact disagree")
    if retired & emitted:
        bad.append(f"{gate.name}: PROSE says {sorted(retired & emitted)} is RETIRED and this "
                   f"transcript contains it -- a retirement nobody took is a comment")


def main() -> int:
    args = sys.argv[1:]
    src = Path(args[0]) if args else DEFAULT
    gate = ROOT / (args[1] if len(args) > 1 else "checks/e2e.py")
    text = src.read_text(errors="replace")
    bs = blocks(text)
    bad: list[str] = []
    print(f"TRANSCRIPT {src.relative_to(ROOT) if src.is_relative_to(ROOT) else src}")
    for n in STAGES:
        label, _ = COUNTED[n]
        if n not in bs:
            print(f"  {n}  RETIRED            DENOMINATOR  -  {label}")
            continue
        body = bs[n]
        v = next((f"{m.group(1)}: {m.group(2)}" for m in (VERDICT.match(b) for b in body) if m),
                 None)
        d = denominator(n, body)
        print(f"  {n}  {(v or 'NO VERDICT LINE (`set -e` aborts the gate here)'):<34}  "
              f"DENOMINATOR {str(d):>4}  {label}")
        if d == 0:
            bad.append(f"stage {n}: DENOMINATOR 0 -- this stage cannot fail on the bug it exists "
                       f"for, so it cannot pass either; retire it, do not re-point it")
        elif d is None and v and not v.partition(": ")[2].startswith("SKIP"):
            # A STAGE THAT SKIPPED PRINTED NOTHING BY CONSTRUCTION and its denominator is simply not
            # knowable this run -- `SKIP IS NOT PASS` cuts both ways. A stage that RAN and claims it
            # compared things without printing how many is the defect worth failing on.
            bad.append(f"stage {n}: EMITTED, verdict {v.partition(': ')[2]}, and no denominator "
                       f"counted -- a stage that compared nothing it can name cannot be held "
                       f"responsible")
    for n in sorted(set(bs) - set(STAGES)):
        bad.append(f"stage {n}: EMITTED and not in this table -- a stage with no denominator is not "
                   f"a gate, and one nobody wrote down is worse")
    print(f"--- {len(bs)} stage(s) emitted, {len(STAGES) - len(bs)} retired")
    agree(gate, set(bs), bad)
    for ln in bad:
        print(f"DENOMINATOR FAIL: {ln}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())