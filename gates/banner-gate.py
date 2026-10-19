#!/usr/bin/env python3
"""banner-gate.py -- THE INNER LANE MAY NOT PRINT ITS OWN `== n/m`, AND A COMPARISON ARTIFACT
MAY NOT BE OLDER THAN THE CODE IT COMPARES.

    .venv/bin/python gates/banner-gate.py

ZERO bend LANES, ZERO rows of its own, TWO CLAIMS, and both are about CLAIMS rather than values.
Each is a defect `.agents/slop/e2estage8/verdicts.py` structurally CANNOT see, and it is the
GENERAL FORM of the re-open rather than the instance: `verdicts.py` classifies a stage by the SHAPE
`^== <n>/<m> ` and has no way to know whether the line came from the gate or from a child the gate
started. A stage's inner lane that prints its own banner therefore re-opens the stage it lives
inside, and the transcript cannot say which banner the body between them belongs to.

THE POPULATION IS `checks/e2e.py`'s OWN DECLARATION, READ FROM ITS AST, NOT A LIST. `C1` walks the
`stage([...])` call sites of the gate itself and takes the repo path out of each argv -- a generator's
own declaration, loaded by path, which is one of the three shapes `AGENTS.md` admits. A three-element
tuple of lane scripts would have been right until stage 4 was added, and nothing in this file would
have noticed, which is `checks/sweep.py`'s removed `LIVE_UNITS` all over again.

**C1 ANSWERS AN OPEN QUESTION THIS TREE HAS NOT ANSWERED: MAY A STAGE'S INNER LANE PRINT AN `== n/m`
BANNER? NO.** Not because the shape is ugly, but because `verdicts.py:HEADER` is the census's ONLY
discriminator between "a stage began here" and "a line of text", so a second writer of that shape is a
second writer of the census's population. The remedy is on the WRITER'S side, and this gate is it.

MEASURED 2026-10-19, THREE LANES CARRY THE SHAPE, AND THE DENOMINATOR IS 3. The middle row is the
one to read twice, because it was expected to be safe and is not:

| lane | its own banners | reaches the transcript? |
|---|---|---|
| `.agents/slop/e2e_port/run-port-mm.sh:107` | `== 6/6 THE MATMUL THROUGH THE PORT` | **YES, EVERY RUN.** Stage 6 forwards the lane's WHOLE output through `echo_file`, so it re-opens stage 6 in any run that gets that far. RECEIPT: `live.port.out:77`, where the census prints `RE-OPEN  stage 6 was ALREADY OPEN at transcript line 77`. |
| `.agents/slop/opsbend-milestone.sh:55,59,65,71,96` | `== 1/3` twice, `== 2/3` twice, `== 3/3` | **YES, MEASURED RATHER THAN PREDICTED.** Stage 5 forwards `tail -3`. `runs/e2e/e2e-opsbend.out` -- 179 B, mtime `2026-10-17T06:45Z`, the most recent recording of that lane -- ends with `== 1/3 executor up to date …` and `== 2/3 checking tinybendygrad/runtime/ops_bend.bend`, and both match `verdicts.HEADER`, so a transcript built from THAT run re-opens **stages 1 and 2**. The `2026-10-07` transcript shows neither, because that run's lane got further and its `tail -3` was `# 0 failed of 46 rows read` / `PASS` instead. |
| `.agents/slop/f64/run-f64.sh:78` | `== 7/7 AN f64 KERNEL THROUGH THE PORT` | not today -- stage 7 forwards through `grep_file(F64_RE)`, whose pattern admits `STAGE 7 …`, `F64-[0-9]` and no `== n/m`. **A LANE WHOSE BANNER A FILTER HAPPENS TO DROP IS STILL A LANE WRITING THE CENSUS'S POPULATION**; the drop is arithmetic, not a decision, and `F64_RE` is one edit away from admitting it. |

**THE THIRD COLUMN IS NOT A PROPERTY OF THE LANE.** It is a property of how much of the lane's output
the gate happens to forward -- `tail -3` for stage 5, the whole file for stage 6, a `grep` for stage 7
-- and a re-open that is avoided by a window size is a re-open with a countdown, not a re-open that
is not there. Row 2 is what that looks like when the countdown has already run out.

WHY THE BANNER SHAPE IS IMPORTED AND NOT RE-SPELLED. `verdicts.py` is out of this gate's grant, so it
cannot be edited to agree with a copy of `HEADER` living here -- and a second copy of a regex is two
witnesses with no generator between them, which is the same lesson as the two loops over
`ORACLE_EDITS` that `.agents/slop/e2esh/refreeze.py` grew and this commit deleted. So this file LOADS
the census by path and USES `verdicts.HEADER` as it is. `blocks` and `DEFAULT` are REQUIRED, not
USED: `blocks()` is the function that turns a banner into a stage boundary, so its absence would mean
the rule below is enforcing a mechanism that no longer exists, and `DEFAULT` is C2's artifact. **IF
ANY OF THE THREE IS ABSENT, THIS GATE REFUSES (exit 3) RATHER THAN FALLING BACK TO A SPELLING OF
ITS OWN**, because a fallback is a gate that passes for the wrong reason and nothing in its output
would say so.

**AND `C2` IS THE FORM OF `C1`, WHICH IS WHY THEY ARE IN ONE FILE.** `verdicts.py` compares a
TRANSCRIPT against a GATE SOURCE, and it cannot tell that the artifact is older than the code: every
row it prints is a fact about the transcript, so all 8 of its failures are true and none of them says
the transcript is out of date. MEASURED 2026-10-19, `.agents/slop/e2epy/artifacts/live.port.out` has
mtime `2026-10-07T23:25:58Z` against `checks/e2e.py` at `2026-10-19T18:43:07Z` -- **11.8 days**, and 7
of the census's 8 complaints are `gate SAYS / run PRINTED` rows that a re-run would clear, which is
exactly the shape of a failure that gets attributed to the code instead of to the clock. That file is
NOT `.gitignore`d (`git check-ignore .agents/slop/e2epy/artifacts/live.port.out` exits 1; only
`/runs/` is ignored, `.gitignore:262`), so `git status` shows it clean and proves nothing. **A
COMPARISON ARTIFACT OLDER THAN ITS CODE IS NOT A FINDING, IT IS A FINDING NOT YET MADE.**

EXIT STATUS, `gates/gatekit.py`'s five: 0 PASS · 1 FAIL · 3 REFUSED (`verdicts.py` will not load, so
the banner shape and the transcript are both unavailable and neither claim was measured) · 5 DEAD
(`checks/e2e.py` holds no `stage([...])` call site, so the walk found no population).
"""
from __future__ import annotations

import ast
import datetime
import re
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GATE = ROOT / "checks/e2e.py"
# THE CENSUS, NAMED AND NOT COPIED. Its `HEADER`, its `blocks()` and its own default TRANSCRIPT are
# this gate's inputs, and a gate's inputs have to be a path somebody else owns.
CENSUS = ROOT / ".agents/slop/e2estage8/verdicts.py"

# FROM SOURCE TEXT, NOT `module_from_spec`. MEASURED 2026-10-19 while repairing
# `.agents/slop/e2esh/refreeze.py`: the import machinery treats a cached `.pyc` as current when the
# source's mtime AND SIZE match, and a `*_SHA` line is 64 characters before and after a re-freeze, so
# a same-second edit was being read back STALE and `oracle_drift()` answered about the previous file.
# Any reader of a pin this tree re-freezes inherits that hazard unless it compiles the text itself.
#
# `checks/e2e.py` AND `verdicts.py` ARE NOT PIN HOLDERS, BUT THE HAZARD IS THE IMPORT PATH, NOT THE
# FILE, and the fix is four characters of discipline. `.agents/slop/e2esh/plant.py:drift()` and
# `.agents/slop/e2esh/refreeze.py` both use it now.


def by_path(src: Path, name: str) -> SimpleNamespace:
    """`src` as a module namespace, compiled from its TEXT. `name` is the module name."""
    ns: dict = {"__file__": str(src), "__name__": name}
    exec(compile(src.read_text(), str(src), "exec"), ns)   # noqa: S102 -- both files are this tree's
    return SimpleNamespace(**{k: v for k, v in ns.items() if not k.startswith("__")})


def lane_argv(tree: ast.Module) -> list[list[str]]:
    """The argv of every `stage([...])` call in `tree`, in source order. **THE POPULATION IS THIS.**

    `stage()` is `checks/e2e.py`'s own single process-spawning helper -- its docstring says so and
    `grep -c 'subprocess' checks/e2e.py` agrees -- so its call sites are where the gate declares which
    programs it runs. The argv keeps only string CONSTANTS, so a lane named by a module global
    (`stage([PY, "…/e2e_mm_gate.py", str(...)])`) is not dropped for having its interpreter spelled as
    a name; the program itself may also be a path, which is why nothing here indexes positionally.

    `bend_run()` (stage 2) does not go through `stage()` and is therefore INVISIBLE here; that hole is
    named rather than papered over with a fallback list, because a fallback list is a second population
    that can disagree with the first.
    """
    sites = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == "stage" and node.args):
            continue
        argv = node.args[0]
        if isinstance(argv, ast.List):
            sites.append([e.value for e in argv.elts
                          if isinstance(e, ast.Constant) and isinstance(e.value, str)])
    return sites


def repo_path(token: str) -> Path | None:
    """The repo file an argv token names, or `None` for a tool by name (`zsh`, `node`, `python`).

    A leading `./` is dropped rather than resolved, because `ROOT / "./x"` and `ROOT / "x"` are the
    same file and only one of them is how anybody writes it.
    """
    if "/" not in token:
        return None
    cand = ROOT / token.removeprefix("./")
    return cand if cand.is_file() else None


# THE QUOTED LITERALS OF A SHELL LINE, AND NOTHING ELSE. `verdicts.py` reads the gate's own call-site
# LITERALS (`CODE = re.compile(r'say\("== (\d+)')`), not its output, and this reads a lane's the same
# way: matching a lane's SOURCE against `HEADER` would find nothing at all, because `say "== 6/6 …"`
# is `HEADER`-shaped only in what it PRINTS. **WHAT THE CENSUS MATCHES IS THE OUTPUT, SO THE INPUT
# HERE IS THE STRING THAT BECOMES THAT OUTPUT.**
LITERAL = re.compile(r"""(['"])(.*?)\1""")
# **THE HOLE, NAMED, AND IT IS NOT EMPTY.** A banner built by concatenation, out of a variable, or
# inside a heredoc body is invisible here, and no regex over source can see it. This tree HAS heredocs
# in two of the three lanes -- `grep -n "<<'EOF'"` answers `run-port-mm.sh:252` and `run-f64.sh:226`,
# both feeding Python on stdin. What it does NOT have is a `== n/m` inside one, and that is a
# measurement as of 2026-10-19 and not a guarantee. So this claim is one FAIL row per lane, not a proof
# of absence, and a lane that starts building its banner out of a variable goes quiet here rather than
# red -- which is the honest limit of a static read, stated in the gate rather than discovered by it.


def claim_no_inner_banner(census: SimpleNamespace) -> tuple[int, list[str]]:
    """C1. `(code, rows)`: one row per lane that PRINTS a line matching the CENSUS'S OWN `HEADER`."""
    header = census.HEADER
    bad: list[str] = []
    lanes = lane_argv(ast.parse(GATE.read_text()))
    print(f"--- C1 population: {len(lanes)} `stage([...])` call site(s) in {GATE.name}, read from its AST")
    if not lanes:
        # DEAD, NOT PASS. An empty population is this claim having measured nothing, and `gatekit`
        # exists so that can have its own exit. A PASS here would be a green over an absence -- the
        # `rebase-gate-selftest` shape AGENTS.md quotes, "0 disagreements over 0 comparisons".
        print("banner-gate: DEAD: `checks/e2e.py` holds no `stage([...])` call site, so the walk found "
              "no population and this claim compared nothing", file=sys.stderr)
        return DEAD, bad
    for argv in lanes:
        paths = [p for p in (repo_path(t) for t in argv) if p is not None]
        if not paths:
            print(f"---   (no repo file in argv) {' '.join(argv)[:72]}")
            continue
        for path in paths:
            hits = [(i, lit) for i, ln in enumerate(path.read_text().splitlines(), 1)
                    for _, lit in LITERAL.findall(ln) if header.match(lit)]
            print(f"---   {path.relative_to(ROOT)}: {len(hits)} literal(s) print a `verdicts.HEADER` line")
            for i, lit in hits:
                rel = path.relative_to(ROOT)
                bad.append(f"{rel}:{i} prints `{lit[:58]}` -- that is the SHAPE "
                           f"`verdicts.blocks()` opens a stage on, and a stage's inner lane writing it "
                           f"re-opens the stage it lives inside")
    return (FAIL if bad else PASS), bad


def claim_artifact_fresh(census: SimpleNamespace) -> tuple[int, list[str]]:
    """C2. `(code, rows)`: the census's own TRANSCRIPT against the GATE SOURCE it is compared to."""
    transcript = Path(census.DEFAULT)
    if not transcript.is_file():
        print(f"banner-gate: DEAD: `{transcript}` is the census's own DEFAULT and does not exist, so "
              f"every row the census would print about it is about nothing", file=sys.stderr)
        return DEAD, [f"{transcript}: the census's own DEFAULT transcript does not exist"]
    src_m, art_m = GATE.stat().st_mtime, transcript.stat().st_mtime
    days = (src_m - art_m) / 86_400
    stamp = datetime.datetime.fromtimestamp(art_m, datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    src_stamp = datetime.datetime.fromtimestamp(src_m, datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"--- C2 artifact: {transcript.relative_to(ROOT)} mtime {stamp}")
    print(f"---   compared against {GATE.relative_to(ROOT)} mtime {src_stamp}: {days:.1f} day(s) older")
    print("---   the instrument here is the CLOCK, not a content hash: a checkout touches mtime, so "
          "this claim is about the artifact's age and nothing else")
    if days <= 0:
        return PASS, []
    return FAIL, [f"{transcript.relative_to(ROOT)} is {days:.1f} day(s) OLDER than the {GATE.name} it "
                  f"is compared against ({stamp} vs {src_stamp}), and it is NOT `.gitignore`d, so "
                  f"`git status` shows it clean and proves nothing: every row "
                  f"`.agents/slop/e2estage8/verdicts.py` prints about it is a fact about the artifact, "
                  f"not about this tree"]


def main() -> int:
    if not (ROOT / "pyproject.toml").is_file():
        print(f"banner-gate: REFUSED, NOT A VERDICT: `{ROOT}` is not at the repo root (no "
              f"`pyproject.toml`), so this gate would report on a tree that is not this one",
              file=sys.stderr)
        return REFUSED
    # THE PRECONDITION IS THE CENSUS ITSELF, AND IT IS ABSENT-OR-NOT. Both claims here are claims
    # ABOUT `verdicts.py`: C1 borrows its discriminator and C2 reads its default artifact. If it
    # stops loading, or stops carrying `HEADER`/`blocks()`/`DEFAULT`, then both claims are unmeasured
    # -- and a gate that fell back to its own spelling of the banner would then be passing for a
    # reason nothing holds. Refuse, loudly, with the reason.
    try:
        census = by_path(CENSUS, "banner_gate_census")
    except OSError as exc:
        print(f"banner-gate: REFUSED: `{CENSUS.relative_to(ROOT)}` does not load ({exc}), so this "
              f"gate's banner shape and its default artifact are both unavailable", file=sys.stderr)
        return REFUSED
    for attr in ("HEADER", "blocks", "DEFAULT"):
        if not hasattr(census, attr):
            print(f"banner-gate: REFUSED: `{CENSUS.relative_to(ROOT)}` no longer defines "
                  f"`{attr}`, so this gate would have to invent a substitute for it", file=sys.stderr)
            return REFUSED

    c1, rows1 = claim_no_inner_banner(census)
    c2, rows2 = claim_artifact_fresh(census)
    # DEAD OUTRANKS FAIL, AND WITH TWO CLAIMS THE WHOLE LADDER IS THESE TWO LINES. A claim that
    # measured nothing cannot be outranked by one that measured something -- its answer is unknown
    # rather than good -- so a DEAD claim is reported as DEAD and not as FAIL. `gates/devtag-gate.py`
    # argues the four-way order at length and is the precedent; a fifth copy of that function would
    # be the second-copy-with-no-generator shape this tree keeps paying for, so the order is written
    # inline for the two claims that actually exist here.
    code = DEAD if DEAD in (c1, c2) else FAIL if FAIL in (c1, c2) else PASS
    for b in rows1 + rows2:
        print(f"banner-gate: FAIL: {b}", file=sys.stderr)
    print(f"banner-gate: {verdict_of(code)} -- {len(rows1) + len(rows2)} complaint(s) "
          f"(C1 {verdict_of(c1)}, C2 {verdict_of(c2)}), no bend lane, no row of its own")
    return code


if __name__ == "__main__":
    sys.exit(main())