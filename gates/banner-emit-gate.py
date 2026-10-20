#!/usr/bin/env python3
"""banner-emit-gate.py -- THE SECOND SOURCE READ, BECAUSE `banner-gate.py`'s C1 IS A LITERAL READ AND A
BANNER IS NOT ALWAYS A LITERAL.

    .venv/bin/python gates/banner-emit-gate.py

ZERO bend LANES, ZERO rows of its own, ONE CLAIM, and it is C1's with one more read bolted on. It is
a SEPARATE FILE rather than an edit to `banner-gate.py` because that file is not this unit's grant,
and because a claim that can be PLANTED is worth more than a claim that can only be argued about.

**WHAT C1 SEES AND WHAT THIS ADDS.** `banner-gate.py:144` `LITERAL` takes the QUOTED LITERALS of a
lane's lines and asks `verdicts.HEADER` whether any of them is a banner. That is the right read for
`say "== 6/6 …"` and for `say("== 6/6 …")`, and it is the whole of what a lane that spells its banner
out can hide behind. It misses TWO shapes:

  * **A HEREDOC BODY.** `cat <<'EOF'` … `== 6/6 THE MATMUL` … `EOF` -- the banner is a bare line, so
    `LITERAL.findall` returns `[]` for it and C1's population sees nothing. `gates/banner-emit-plant.py`
    ARM 2 plants exactly this and MEASURES that `banner-gate.py` answers `PASS`.
  * **A BANNER SPLIT ACROSS LITERALS OR BUILT FROM A VARIABLE.** `say "== 6/" "$d …"`. C1 cannot see
    this and NEITHER CAN THIS FILE, and the reason is not a missing regex: **no static read of a source
    text can resolve what a shell assembles at run time.** That is a property of the medium, so this
    file NAMES the hole instead of narrowing it, and `gates/banner-emit-plant.py` ARM 3 measures it.

**WHAT CLOSES THE HEREDOC HOLE, AND WHY IT IS NOT A WEAKENING.** One more read, unioned with C1's:
`header.match(line.lstrip())` -- the line itself with its leading whitespace removed. **A non-comment
line of a lane whose first non-blank characters are `== n/m ` is a banner by any reading of the word**:
either the shell evaluates it and it prints, or it is dead text, and a dead banner is not worth a gate.
So the read cannot invent a row C1 would have called a defect of the same thing. MEASURED 2026-10-20T00:21Z
over all SIX lanes `checks/e2e.py` names: `0` lines match, so the read is quiet on the tree as it stands
and it is a claim about the writers rather than a restatement of what is already there. The census has
already decided the shape is harmless: `gates/e2estage8-stage-selftest.py` NEGATIVE 4 asserts that a
banner-shaped line ONE space off column 0 is NOT a banner, and its `CONTROL the frozen fixtures were
never written` arm is what stops that arm passing vacuously.

**THE POPULATION IS `banner-gate.py`'s, LOADED BY PATH, AND IS NOT RE-DERIVED HERE.** This file reads
its sibling with `importlib.util.spec_from_file_location` -- the HYPHEN in `banner-gate.py` is why, and
that is the same reason `banner-gate.py` itself loads `verdicts.py` that way -- and then calls
`lane_argv()`, `repo_path()`, `LITERAL` and `by_path()` OUT OF IT. There is ONE place in this tree that
declares which lanes the gate runs: `checks/e2e.py`'s `stage([...])` call sites, read from its AST. A
second copy of that walk would be the second population with no generator between them, which is the
shape `AGENTS.md` charges at `checks/sweep.py`'s deleted `LIVE_UNITS`. **IF ANY OF THE FIVE IS ABSENT
THIS GATE REFUSES (exit 3) RATHER THAN RE-IMPLEMENTING IT**, because a fallback is a gate that passes
for a reason nothing holds and nothing in its output would say so.

**AND THE ANSWER TO THE OPEN QUESTION IS THE SAME ONE `banner-gate.py` GIVES.** No: a stage's inner lane
may not print a `== n/m` line, because `verdicts.HEADER` is the census's ONLY discriminator between "a
stage began here" and "a line of text", so a second writer of that shape is a second writer of the
census's population. The three lanes stopped by indenting their banners one level, text unchanged --
`.agents/slop/opsbend-milestone.sh` (5 banners), `.agents/slop/e2e_port/run-port-mm.sh:107` and
`.agents/slop/f64/run-f64.sh:78`. **A HOLLOW GATE IS NOT A REASON TO KEEP THE BANNER**, so this file
exists to keep the WINDOW closed from the other side of the hole rather than to admire it.

EXIT STATUS, `gates/gatekit.py`'s five: 0 PASS · 1 FAIL · 3 REFUSED (a sibling or the census would not
load, or stopped carrying one of the five names this file borrows, so nothing was measured) · 5 DEAD
(`checks/e2e.py` holds no `stage([...])` call site, so the borrowed walk found no population).
"""
from __future__ import annotations

import ast
import importlib.util
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
# THE SIBLING. Loaded, never copied: this file holds no lane name, no walk and no banner spelling.
SIBLING = HERE / "banner-gate.py"
BORROWED = ("lane_argv", "repo_path", "LITERAL", "by_path")


def sibling() -> object:
    """`banner-gate.py` as a module, loaded BY PATH. The HYPHEN is why `import` cannot be spelled."""
    spec = importlib.util.spec_from_file_location("banner_gate", SIBLING)
    if spec is None or spec.loader is None:
        raise OSError(f"{SIBLING} has no import spec")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def claim_second_read(bg: object, census: object) -> tuple[int, list[str]]:
    """`(code, rows)`: one row per lane holding a banner in EITHER read -- C1's literals, or a line
    whose leading whitespace is removed, which is what a heredoc body and a bare `echo == 1/3 x` are."""
    header, bad = census.HEADER, []
    lanes = bg.lane_argv(ast.parse((ROOT / "checks/e2e.py").read_text()))
    print(f"--- population: {len(lanes)} `stage([...])` call site(s), read by "
          f"`{SIBLING.name}`'s OWN `lane_argv()` -- this file declares none")
    if not lanes:
        print("banner-emit-gate: DEAD: the borrowed walk found no `stage([...])` call site, so this "
              "claim compared nothing", file=sys.stderr)
        return DEAD, bad
    for argv in lanes:
        for path in (p for p in (bg.repo_path(t) for t in argv) if p is not None):
            lit = line = 0
            for i, ln in enumerate(path.read_text().splitlines(), 1):
                for _, text in bg.LITERAL.findall(ln):
                    if header.match(text):
                        lit += 1
                        bad.append(f"{path.relative_to(ROOT)}:{i} literal `{text[:52]}`")
                if header.match(ln.lstrip()):   # THE READ THIS FILE ADDS
                    line += 1
                    bad.append(f"{path.relative_to(ROOT)}:{i} bare line `{ln.strip()[:52]}` -- a "
                               f"heredoc body or an unquoted argument, and C1's literal read cannot "
                               f"see it")
            print(f"---   {path.relative_to(ROOT)}: {lit} literal(s) (C1's read), "
                  f"{line} line(s) (the added read)")
    return (FAIL if bad else PASS), bad


def main() -> int:
    if not (ROOT / "pyproject.toml").is_file():
        print(f"banner-emit-gate: REFUSED, NOT A VERDICT: `{ROOT}` is not at the repo root (no "
              f"`pyproject.toml`)", file=sys.stderr)
        return REFUSED
    try:
        bg = sibling()
    except OSError as exc:
        print(f"banner-emit-gate: REFUSED: `{SIBLING.name}` does not load ({exc}), so this gate's "
              f"population is unavailable", file=sys.stderr)
        return REFUSED
    for attr in BORROWED:
        if not hasattr(bg, attr):
            print(f"banner-emit-gate: REFUSED: `{SIBLING.name}` no longer defines `{attr}`, and "
                  f"re-implementing it here would make TWO populations with no generator between "
                  f"them", file=sys.stderr)
            return REFUSED
    try:
        census = bg.by_path(bg.CENSUS, "banner_emit_census")   # the census's OWN HEADER, by path
    except OSError as exc:
        print(f"banner-emit-gate: REFUSED: the census does not load ({exc})", file=sys.stderr)
        return REFUSED
    if not hasattr(census, "HEADER"):
        print("banner-emit-gate: REFUSED: the census no longer defines `HEADER`, so this gate would "
              "have to invent a substitute for it", file=sys.stderr)
        return REFUSED
    code, rows = claim_second_read(bg, census)
    for r in rows:
        print(f"banner-emit-gate: FAIL: {r}", file=sys.stderr)
    print(f"banner-emit-gate: {verdict_of(code)} -- {len(rows)} complaint(s) over two reads, no bend "
          f"lane, no row of its own")
    return code


if __name__ == "__main__":
    sys.exit(main())