#!/usr/bin/env python3
"""tc_ptx_render_census-gate.py -- the RECIPE, AS CODE.

    .venv/bin/python gates/tc_ptx_render_census-gate.py
    .venv/bin/python gates/tc_ptx_render_census-gate.py --stage2 <path> --oracle <path>

WHY THIS FILE EXISTS.  The 623-row table of `renderer/tc.bend` (tc.py, 289 rows) and
`renderer/tc_ptx.bend` (ptx.py, 343 rows) was gated by a RECIPE THAT WAS PROSE: two
lines in a `.bend` header naming a `diff` and an oracle selector.  A prose recipe is
not a gate, and MEASURED 2026-10-22 the table it described was RED -- 118 rows carried
the PRE-RENAME dtype spellings, three rows carried a wrong `rcp.` prefix, and the
oracle's `stage2` had NINE rows the port did not -- while NOTHING RAN.

THE FIVE VERDICTS ARE `gatekit`'s: PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5.  A lane
that emitted no rows is DEAD, not PASS, and a file that is not there is REFUSED, not
FAIL.  "A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE THAN NO GATE."

THE TWO LANES, AND WHICH SELECTOR EACH ASKS FOR.  The oracle has FOUR selectors and
the port has TWO files, and the pairing is NOT "one file per stage":

    stage1  ->  tinybendygrad/renderer/tc.bend      (tc.py's 289 rows)
    stage2  ->  tinybendygrad/renderer/tc_ptx.bend  (ptx.py's 343 rows)

`tc_ptx.bend`'s `main` prints `r_stage2()` and NOTHING ELSE, and that is CORRECT: the
1:1 rule is one `.bend` per upstream `.py`, so `tc.py`'s rows live in `tc.bend`.  The
recipe that named `tc_ptx.bend` for BOTH stages was DEAD for the tc.py half, and
"the rows were in NO LANE AT ALL" is a thing that can happen and that this gate now
cannot happen.

THE ASSERTION IS A BYTE DIFF, AND THE ORACLE CARRIES CPYTHON's VALUE.  Every row is
`<name> = [BEND-VALUE]   py=[CPYTHON-VALUE]`, the oracle computes EVERY half from live
`tinygrad/`, and the two lane outputs are compared BYTE FOR BYTE.  The port's `py=`
half is DERIVED -- the port's own value, `T.rd(nm, got)` -- so the `got=` column is
the assertion and the `py=` column is the port's own consistency.

THREE CHECKS, AND THE THIRD IS THE ONE A DIFF CANNOT DO.

  1. `stage1`: the oracle's `stage1` against `tc.bend`.  BYTE FOR BYTE.
  2. `stage2`: the oracle's `stage2` against `tc_ptx.bend`.  BYTE FOR BYTE.
  3. `bend`:   the oracle's `bend` against the PORT'S OWN SOURCE for the four
     dtype-table row builders.  **A DIFF CANNOT SEE A ROW THAT IS MISSING FROM BOTH
     LANES** -- if the port drops a row and the oracle drops it too, the two lanes
     agree and the diff is GREEN.  `bend` is the oracle's INDEPENDENT statement of
     the row set, computed from `PTXRenderer.types` rather than from `type_rows()`.

AND ONE WITNESS WITH NO PORT LANE, REPORTED AND NOT DIFFED.  The oracle's `wmma`
selector answers the three `pm_validate_wmma_*` guards, and the PORT HAS NO
`pm_validate_wmma_*` YET -- the rewrite bodies need `.bitcast`, which is `TODO(p3)` in
`ops.bend`.  So there is nothing to diff against, and the honest thing is to SAY the
row count and NAME the wall, not to fake a port lane.  A gate that prints a number it
did not compare is the shape `gatekit`'s `UNASKABLE` exists for.
"""

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
LOCK = ROOT / "checks" / "bendlock.sh"
ART = HERE / "artifacts" / "tc_ptx_render_census"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
WARM = "ALL PROOFS CHECK"

# THE TWO STAGES, AND THE ROW COUNTS ARE DERIVED FROM THE ORACLE, NOT TYPED HERE.
# A second number that can disagree with the first is a number nobody can check, so
# the count the lane must produce is the count the oracle produced -- and the ORACLE's
# count is what the PORT is compared against.
STAGES = (("stage1", "tinybendygrad/renderer/tc.bend"),
          ("stage2", "tinybendygrad/renderer/tc_ptx.bend"))

# THE FOUR DEFS `bend` GENERATES, AND THE PORT'S OWN SOURCE IS COMPARED AGAINST IT.
BEND_DEFS = ("r_tabs", "r_mc_tabs", "r_tabs_miss", "r_tabs_weak")


def say(msg):
    print(f"tc_ptx_render_census-gate: {msg}", file=sys.stderr)


def refuse(why):
    print(f"== REFUSED, NOT A VERDICT: tc_ptx_render_census-gate: {why}", file=sys.stderr)
    return REFUSED


def norm(text):
    """WHITESPACE-NORMALISED, so a line break is not a difference."""
    return " ".join(text.split())


def port_defs(path, names):
    """The port's own source for the named defs, whitespace-normalised."""
    lines = Path(path).read_text().split("\n")
    out = {}
    for name in names:
        start = None
        for i, l in enumerate(lines):
            if l.startswith(f"def {name}("):
                start = i
                break
        if start is None:
            return None, f"the port has no `def {name}(`"
        body = [lines[start]]
        for l in lines[start + 1:]:
            if not l.strip() or l.startswith("#") or l.startswith("def "):
                break
            body.append(l)
        out[name] = norm("\n".join(body))
    return out, None


def run(argv):
    return subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))


def warm(bendfile):
    """`--check-only`'s FIRST LINE, never its exit status.  `gatekit._warm`'s rule."""
    r = run([str(BEND), str(bendfile), "--check-only"])
    first = (r.stdout or "").splitlines()[:1]
    return bool(first) and first[0].strip() == WARM, first


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage1", default=str(ROOT / STAGES[0][1]))
    ap.add_argument("--stage2", default=str(ROOT / STAGES[1][1]))
    ap.add_argument("--oracle", default=str(HERE / "tc_ptx_render-oracle.py"))
    args = ap.parse_args()

    for p in (args.stage1, args.stage2, args.oracle, BEND, PY, LOCK):
        if not Path(p).exists():
            return refuse(f"an input is absent: {p}")
    ART.mkdir(parents=True, exist_ok=True)

    oracle = Path(args.oracle)
    for sel, bendfile in (("stage1", args.stage1), ("stage2", args.stage2)):
        if not warm(bendfile)[0]:
            return refuse(f"{bendfile} is not warm (`--check-only`'s first line is not {WARM!r})")
        # THE PORT LANE, THROUGH THE LOCK.  `checks/bendlock.sh` is the ONE lock: two
        # lock paths do not exclude each other, and the memory precondition is a SUM
        # over concurrently running compilers.
        pr = run([str(LOCK), "--", str(BEND), str(bendfile)])
        if pr.returncode != 0:
            said = [l.strip() for l in (pr.stderr or "").splitlines() if l.strip()][:4]
            say(f"the port lane for {sel} failed: {' | '.join(said)}")
            return DEAD if not pr.stdout else FAIL
        (ART / f"{sel}.port.out").write_text(pr.stdout)
        orc = run([str(PY), str(oracle), sel])
        if orc.returncode != 0:
            said = [l.strip() for l in (orc.stderr or "").splitlines() if l.strip()][:4]
            say(f"the oracle's {sel} failed: {' | '.join(said)}")
            return REFUSED
        (ART / f"{sel}.oracle.rows").write_text(orc.stdout)
        if not orc.stdout.strip():
            say(f"the oracle's {sel} emitted no rows")
            return DEAD
        if not pr.stdout.strip():
            say(f"the port lane for {sel} emitted no rows")
            return DEAD
        if pr.stdout != orc.stdout:
            a, b = pr.stdout.split("\n"), orc.stdout.split("\n")
            bad = [(x, y) for x, y in zip(a, b) if x != y]
            say(f"{sel} DISAGREES: {len(bad)} of {max(len(a), len(b))} lines differ "
                f"(port {len(a)} lines, oracle {len(b)} lines); first: {bad[:2]}")
            return FAIL
        print(f"  {sel}: {len(pr.stdout.splitlines())} lines, BYTE-IDENTICAL")

    # CHECK 3 -- THE ROW SET, WHICH A DIFF CANNOT SEE.
    br = run([str(PY), str(oracle), "bend"])
    if br.returncode != 0:
        return refuse("the oracle's `bend` selector failed")
    got, why = port_defs(args.stage2, BEND_DEFS)
    if got is None:
        return refuse(why)
    want = {}
    lines = br.stdout.split("\n")
    for i, l in enumerate(lines):
        for name in BEND_DEFS:
            if l.startswith(f"def {name}("):
                body = [l]
                for k in range(i + 1, len(lines)):
                    if not lines[k].strip() or lines[k].startswith("def "):
                        break
                    body.append(lines[k])
                want[name] = norm("\n".join(body))
    for name in BEND_DEFS:
        if name not in want:
            return refuse(f"the oracle's `bend` emitted no `def {name}(`")
        if want[name] != got[name]:
            say(f"the port's `{name}` is not the oracle's generated source:\n"
                f"      want: {want[name][:200]}\n      got:  {got[name][:200]}")
            return FAIL
    print(f"  bend: {len(BEND_DEFS)} generated row builders match the port's own source")

    # THE WITNESS WITH NO PORT LANE.  REPORTED, NOT DIFFED, AND THE WALL IS NAMED.
    wr = run([str(PY), str(oracle), "wmma"])
    if wr.returncode != 0:
        return refuse("the oracle's `wmma` selector failed")
    n = len([l for l in wr.stdout.split("\n") if l.strip()])
    fired = len([l for l in wr.stdout.split("\n") if "[FIRED]" in l])
    (ART / "wmma.rows").write_text(wr.stdout)
    print(f"  wmma: {n} rows, {fired} FIRED -- NO PORT LANE: the port has no "
          f"`pm_validate_wmma_*` (the rewrite bodies need `.bitcast`, `TODO(p3)` in ops.bend)")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
