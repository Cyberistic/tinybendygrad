#!/usr/bin/env python3
"""EVERY STAGE `checks/e2e.py` EMITS, WITH THE DENOMINATOR OF EACH, COUNTED OUT OF ITS OWN BLOCK.

    usage: .venv/bin/python .agents/slop/e2estage8/verdicts.py [TRANSCRIPT] [GATE]
           TRANSCRIPT defaults to `.agents/slop/e2epy/artifacts/live.port.out`, GATE to
           `checks/e2e.py`. A stage absent from TRANSCRIPT is printed as RETIRED and is not an error.

**A VERDICT WITH NO DENOMINATOR IS NOT A GATE.** A denominator is the count of the things a stage
compares, and it is counted HERE, out of the artifact, by one rule per stage -- never taken from the
stage's own banner.

**THE STAGE ALSO WRITES A DENOMINATOR ON THAT BANNER, AND IT IS A ROW, NOT A SUBSTITUTE.** The first
version of this file captured `m` out of `== n/m` and threw it away, so a gate could print any
denominator it liked and this census said nothing. MEASURED 2026-10-19T04:24Z: the transcript
`.agents/slop/e2epy/artifacts/live.port.out` carries `== 1/4`, and the gate's docstring carried four
stages, and the file exited 0. **THREE READINGS OF THE SAME LINE ARE NOW PRINTED AS SEPARATE ROWS AND
DISPUTED** -- `gate SAYS` (the `m` of the gate's `say("== n/m ...` call sites), `run PRINTED` (the
`m` the run's own banner carries), and `census FOUND` (how many stage call sites the gate source
holds, which no banner can influence). They disagree today in BOTH directions: `gate SAYS 1/7` against
`run PRINTED 1/4`, and `checks/e2e.py:543` says `== 5/5` and `:555` says `== 6/6` in a gate that
emits SEVEN stages.

**THE STAGE SET STAYS A DECLARATION, AND THAT REFUSAL IS WHY `m` IS A ROW.** `CODE` discovers the
stages from `say("== (\\d+)` and `COUNTED` names them by hand. Deriving either from the banner's own
`m` was REFUSED: the `m` is written by the code under test, so a gate emitting two stages could print
`== 1/2` twice, agree with itself, and be counted complete. **A CENSUS THAT DERIVES ITS OWN
DENOMINATOR FROM THE THING IT IS CHECKING CHECKS NOTHING** -- so the population is a DECLARATION this
census can be wrong about, and `m` is a READING it can dispute.

**A `== n/m` LINE INSIDE A STAGE's OWN BODY IS NOT A NEW STAGE.** The old `blocks()` re-opened on ANY
header-shaped line and RESET the stage's list, so `live.port.out:77` -- stage 6's own lane printing
`== 6/6 THE MATMUL THROUGH THE PORT -- ...` -- discarded lines 75-77 and kept 153 of stage 6's 156
(MEASURED 2026-10-19T04:24Z). A stage's body is now every line after ITS FIRST banner up to the next
banner that opens a stage this transcript has not opened yet; a later banner for an already-open stage
is a body line, AND IS REPORTED AS A RE-OPEN, because one stage number with two banners is a
transcript that cannot say which banner the body belongs to.

Five failures, and it exits 1 on any of them:

  * an EMITTED stage whose denominator counts **0**. Such a stage cannot fail on the bug it exists
    for, so it cannot pass either, and its presence makes the stages around it look like a suite.
  * an EMITTED stage that RAN and printed no countable row, so nothing can be held responsible.
    A stage that SKIPPED is exempt: it measured nothing, and `SKIP IS NOT PASS` cuts both ways.
  * **the stage names in the gate's PROSE, the stage headers its CODE emits, and the stage headers in
    a run's TRANSCRIPT do not agree.** This is the check that would have caught the retirement's
    two failures. `RETIRED` appeared in `checks/e2e.py`'s docstring while stage 8 was still emitted at
    the code line, so the prose a reader trusts and the program that runs disagreed, and no reader
    running `--help` could tell which one was true.
  * **a stage's DECLARED denominator is not the number of stages the gate emits** (`gate SAYS` against
    `census FOUND`), or **not the denominator the run printed** (`gate SAYS` against `run PRINTED`).
  * **one stage opened twice in one transcript.** The body is no longer lost -- that is fixed above --
    but a re-open is still a defect, and a tool that fixed the loss and said nothing about the cause
    would have hidden it.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = ROOT / ".agents/slop/e2epy/artifacts/live.port.out"
HEADER = re.compile(r"^== (\d+)/(\d+) (.*)$")
VERDICT = re.compile(r"^  (stage \d+ [^:]*): (PASS|FAIL \(rc=-?\d+\)|SKIP -- .*)$")
# THE THREE READERS OF A STAGE LIST, AND THE ONLY THING THAT KEEPS THEM HONEST IS THAT THEY MUST
# AGREE. `PROSE` is the gate's own docstring stage table, `CODE` is what `say("== n/...")` prints, and
# `TRANSCRIPT` is what a run actually emitted. Any pair of them disagreeing is a reader being misled,
# and the docstring is the one that is trusted and never executed.
#
# A PROSE ROW THAT SAYS `RETIRED` IS THE RECORD OF A RETIREMENT, NOT A STAGE, and it is counted apart
# from the live rows -- otherwise naming the retirement is the same defect as keeping the stage.
# **AND THE SHAPE ALONE IS NOT A POPULATION.** MEASURED 2026-10-15: `checks/e2e.py`'s docstring has
# TWO tables of `  <digit>  <word>` rows -- the STAGE table (`:18`-`:63`) and the EXIT STATUS table
# (`:125`-`:132`) -- and the first version of this regex scanned the WHOLE docstring, so the exit
# codes `0`..`4` joined the stage set and the gate reported the fiction
# `PROSE names [0] the CODE does not emit`. **Stage `0` does not exist and never did; a shape that
# cannot see its own section boundary reads the NEXT table as if it were its own.** So the scan is
# cut at the `EXIT STATUS` header, which is the DECLARATION of where the stage table ends -- not at
# a line number, which the next edit would move.
PROSE_TABLE = re.compile(r"^  (\d)  \S+.*$", re.M)
PROSE_END = re.compile(r"^EXIT STATUS\b", re.M)
CODE = re.compile(r'say\("== (\d+)/')
# THE SAME CALL SITES, READ A SECOND TIME, FOR THE `m`. `CODE` is the DECLARATION of the stage set
# and is never derived from `m`; `CODE_SAYS` is an independent READING of the same line that the
# census reports and disputes. Two readings of one line is a check; one reading used as the
# population is a census that cannot be wrong, because it cannot be anything.
CODE_SAYS = re.compile(r'say\("== (\d+)/(\d+) ')


def prose_rows(src: str) -> list[tuple[int, bool]]:
    """`(stage, retired)` for the STAGE table only: the docstring from its start up to the
    `EXIT STATUS` header, which is where that table stops being about stages."""
    cut = PROSE_END.search(src)
    table = src[:cut.start()] if cut else src
    return [(int(m.group(1)), "RETIRED" in m.group(0)) for m in PROSE_TABLE.finditer(table)]

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


def blocks(text: str) -> tuple[dict[int, list[str]], dict[int, list[tuple[int, str]]]]:
    """`(bodies, banners)`: stage number -> that stage's body lines, and stage number -> EVERY
    `== n/m ...` line carrying that number, `(line number, line)`.

    **THE FIRST BANNER FOR A STAGE OPENS IT AND A LATER ONE DOES NOT.** The old rule re-opened on any
    header-shaped line and RESET the stage's list, so a stage's OWN lane printing `== n/m` inside its
    own body threw away everything printed before it -- MEASURED 2026-10-19T04:24Z on
    `live.port.out`, stage 6's body at `:77` cost it lines 75-77 and 3 of its 156. Every line after
    the first banner belongs to the stage that banner opened, and a later banner is kept AS A BODY
    LINE and reported by `reopens()`, because the alternative -- discarding it -- loses lines and the
    other choice -- re-opening -- attributes them to a stage that never started.

    Lines before the first banner are preamble and belong to no stage; `current` is explicit rather
    than `max(out)`, which would have attributed a back-tracking banner to the largest stage seen."""
    bodies: dict[int, list[str]] = {}
    banners: dict[int, list[tuple[int, str]]] = {}
    current: int | None = None
    for no, ln in enumerate(text.splitlines(), 1):
        if m := HEADER.match(ln):
            n = int(m.group(1))
            banners.setdefault(n, []).append((no, ln))
            if n not in bodies:            # the FIRST banner for n opens it
                bodies[n], current = [], n
            elif current is not None:      # a RE-OPEN: n is already open, so this is n's own body
                bodies[current].append(ln)
        elif current is not None:
            bodies[current].append(ln)
    return bodies, banners


def reopens(banners: dict[int, list[tuple[int, str]]]) -> list[tuple[int, int, str]]:
    """`(stage, line number, line)` for every banner after a stage's FIRST, i.e. every line that the
    old `blocks()` turned into a stage boundary. One stage number with two banners is a transcript
    that cannot say which banner the body between them belongs to, so it is a row and a failure."""
    return sorted(((n, no, ln) for n, hs in banners.items() for no, ln in hs[1:]), key=lambda r: r[1])


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


def readings(gate: Path, banners: dict[int, list[tuple[int, str]]], bad: list[str]) -> None:
    """THREE READINGS OF THE SAME `== n/m` LINE, PRINTED AS SEPARATE ROWS AND DISPUTED.

    `gate SAYS` is the `m` the gate's own call sites carry -- a READING, never a substitute for
    `COUNTED`, which stays the declaration. `run PRINTED` is the `m` the run's banner carried. `census
    FOUND` is how many stage call sites the gate source holds, and it is the only one of the three no
    banner can influence. A census that printed `m` without being able to dispute it would be worse
    than the bug it was written for, so BOTH disagreements are failures."""
    src = gate.read_text()
    says = {int(n): int(m) for n, m in CODE_SAYS.findall(src)}
    printed = {}
    for n, hs in banners.items():
        m = HEADER.match(hs[0][1])       # the FIRST banner is the one that opened the stage
        printed[n] = int(m.group(2)) if m else None
    found = len({int(n) for n in CODE.findall(src)})
    for label, got in (("gate SAYS", says), ("run PRINTED", printed)):
        print(f"--- {label:<11} {len(got)} denominator(s), from "
              f"{'the gate source' if got is says else 'the transcript'}: "
              + " ".join(f"{n}->{got[n]}" for n in sorted(got)))
    print(f"--- census FOUND {found} stage call site(s) in {gate.name}; that count is the DECLARED "
          f"population (`CODE`, `COUNTED`) and no banner can move it")
    for n in sorted(says):
        if found and says[n] != found:
            bad.append(f"stage {n}: the gate's own banner says `== {n}/{says[n]}` and the gate emits "
                       f"{found} stage(s) -- a denominator nothing disputes is a number, not a count")
    for n in sorted(set(says) & set(printed)):
        if printed[n] != says[n]:
            bad.append(f"stage {n}: the gate SAYS its denominator is {says[n]} and this transcript "
                       f"PRINTED {printed[n]} -- the gate and its own artifact disagree about how "
                       f"many stages there are")


def agree(gate: Path, emitted: set[int], bad: list[str]) -> None:
    """PROSE, CODE and TRANSCRIPT must name the same stages. Reported as a diff between the sets, so
    the answer says WHICH stage a reader would be misled about."""
    src = gate.read_text()
    rows = prose_rows(src)
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
    bs, hs = blocks(text)
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
    for n, no, ln in reopens(hs):
        print(f"--- RE-OPEN    stage {n} was ALREADY OPEN at transcript line {no}: {ln}")
        bad.append(f"stage {n}: re-opened at transcript line {no} by `{ln}` -- one stage number, two "
                   f"banners, so the body between them belongs to neither by name")
    print(f"--- {len(bs)} stage(s) emitted, {len(STAGES) - len(bs)} retired")
    agree(gate, set(bs), bad)
    readings(gate, hs, bad)
    for ln in bad:
        print(f"DENOMINATOR FAIL: {ln}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())