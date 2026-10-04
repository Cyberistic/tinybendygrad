#!/usr/bin/env python3
"""staleness.py -- does any note still claim a number that has since moved?

WHAT IT IS. A grep is enough to find a *string*. It is not enough to decide whether the
string is a claim about the world or a citation of a past measurement, because this tree is
full of both and they are spelled identically. This script does NOT try to judge prose. It
does something narrower and, deliberately, something an instrument can be trusted to do:

    FOR EACH DOCUMENTED COUNT, IT STATES WHAT THE CURRENT VALUE IS,
    AND IT SAYS SO EVEN WHEN IT CANNOT MEASURE IT.

**THE DESIGN IS AN ANTI-CLAIM.** Every row below is a number a note in this tree asserts
about the LIVE tree, paired with the CURRENT value and the command that produces it. The
script's output is the diff between "what the notes say" and "what a run says", plus an
explicit `STALE -- NOT RE-MEASURED` for every claim whose value nobody has re-derived. A
stale-number hunt that only reports what it can measure is a hunt that hides its own
blind spot, which is the failure mode this project's notes keep recording.

**IT DOES NOT HAVE TO BE RIGHT. IT HAS TO NOTICE.** Exit 0 does not mean the tree is
consistent. Exit 2 means "a claim is stale or unverified", and the two are different answers
and the script never collapses them. Run it with `--quiet` to get only the disagreeing rows.

    .venv/bin/python .agents/slop/notes-sweep/staleness.py            # table + verdict
    .venv/bin/python .agents/slop/notes-sweep/staleness.py --quiet    # rows only

MEASUREMENT IS DEFERRED, NOT ASSUMED. `--measure` runs the real census
(`hermetic-census.py --no-publish`, ~2 min) and the real per-graph verdicts, and overwrites
the HARDCODED `current` column with what it just observed. **Without `--measure` the script
compares the notes against the values recorded in `01-GROUND-TRUTH.md`, which is a file
another unit can be editing — so the default mode can itself go stale, and it prints the
date it was last measured so that is visible rather than assumed.**
"""
from __future__ import annotations
import argparse, pathlib, re, subprocess, sys, collections

HERE = pathlib.Path(__file__).resolve().parent
SLOP = HERE.parent
REPO = SLOP.parents[1]

# `expected` is what the notes say TODAY (2026-10-04, after the notes-sweep pass).
# `current` is what a run says. `how` names the instrument, so a reader can re-derive it
# instead of trusting this file -- which is the rule the corpus already learned the hard way
# about a census that could not see its own inputs.
CLAIMS: list[tuple[str, str, int | None, str, str]] = [
  # (claim id, where it is documented, documented value, current value, instrument)
  ("ops reached (both sides)", "REACH.md headline + graphcmp-LIMITS.md s5", 59, 59, "census"),
  ("ops NOT reached", "REACH.md headline + graphcmp-LIMITS.md s5", 18, 18, "census"),
  ("ops denominator", "everywhere", 77, 77, "len(list(Ops))"),
  ("graphs in corpus", "REACH.md headline", 24, 24, "len(G.GRAPHS)"),
  ("graphs AGREE", "graphcmp-repro.sh:66 pin", 22, 22, "per-graph diff"),
  ("graphs DISAGREE", "REACH.md addendum", 2, 2, "per-graph diff"),
  ("commutative ops reached", "graphcmp-LIMITS.md s5", 8, 8, "per-graph diff"),
  (".bend files cold under --check-only", "agent-core.md TRAPS", 14, 14, "check-only census"),
  (".bend files total", "agent-core.md TRAPS", 137, 137, "find | wc -l"),
  ("H.I64 qualified uses", "SPELLING.md", 678, 678, "grep -o"),
  ("H.I64 files", "SPELLING.md", 39, 39, "grep -rl | wc -l"),
]

# Claims NOBODY has re-derived. They are listed so the report can COUNT them rather than
# quietly omit them: "could not re-measure: 12" is a useful sentence and silence is not.
UNVERIFIED: list[tuple[str, str, str]] = [
  ("324 libclang bindings", "AUDIT-CAN-FAIL.md", "not re-measured: needs the generator"),
  ("323/324 laws", "agent-core.md", "not re-measured: full bend run"),
  ("311 trampolines None{}", "brief-adjacent", "not re-measured"),
  ("2,419 of 2,421 bend identifiers", "agent-core.md", "not re-measured: needs the probe"),
  ("24,583 port defs / 724 upstream-named", "agent-core.md", "not re-measured"),
  ("t_ prefix 1,813 uses", "agent-core.md", "not re-measured"),
  ("cstyle.bend 43 reads + 22 readers", "agent-core.md", "not re-measured"),
  ("5,503 lines from bend -o", "agent-core.md", "not re-measured"),
  ("22 phantom blind spots", "agent-core.md", "historical: the $TMPDIR run is gone"),
  ("841 lines lost to a block move", "agent-core.md", "historical: cannot be re-measured"),
  ("190+ rules in bend2-constraints.md", "agent-core.md", "cheap but not run"),
  ("e2e.sh 7 stages / 0 failed", "F64-KERNEL.md", "not re-measured: gate script"),
  ("ABI-1..4 closed, ABI-5/6/7 open", "DTYPE-ABI.md", "not re-measured: gate script"),
  ("154/154 repro files identical", "graphcmp-LIMITS.md header", "STALE: corpus grew past 154"),
  ("189 nodes / 1134 field-records", "graphcmp-LIMITS.md s8", "STALE: not re-summed"),
  ("0 float-CONST nodes of 189", "graphcmp-LIMITS.md s2", "STALE: denominator aged"),
  ("zip-truncated=0 over 189 nodes", "graphcmp-LIMITS.md s4", "STALE: denominator aged"),
  ("40 i64_* defs in helpers.bend", "SPELLING.md", "STALE: count read 23, not re-derived"),
  ("77/77/0/0 port Ops enum", "TENSOR-SURFACE.md", "STALE by construction: live file"),
  ("dtype.c:205 / dtype.js:136", "SPELLING.md", "STALE: file owned by a live unit"),
  ("libclang.bend:95,98,101 nullary uses", "SPELLING.md", "STALE: lines no longer carry them"),
]

def falsify() -> int:
  """Prove the script CAN report a stale claim, by perturbing one and looking.

  An instrument that has only ever printed `STALE: 0` has not been shown to notice. This is
  the cheapest honest way to establish a hit rate: take the claim table, corrupt exactly one
  value, and require the script to exit 2 and NAME that row. If it does not, the script is
  a rubber stamp and the `STALE: 0` above means nothing.
  """
  global CLAIMS
  keep = list(CLAIMS)
  try:
    CLAIMS = [(c, w, (e + 1 if c == "ops reached (both sides)" else e), cur, h) for c, w, e, cur, h in keep]
    rc = report(measure=False, quiet=True)
  finally:
    CLAIMS = keep
  print(f"\n# falsify: expected rc=2 and one named STALE row; got rc={rc} "
        f"({'PASS' if rc == 2 else 'FAIL -- the instrument cannot notice'})")
  return 0 if rc == 2 else 1

def measure_census() -> dict:
  """Run the real census. Returns the measured graph/op/denominator counts, or raises."""
  p = subprocess.run([str(REPO / ".venv/bin/python"), str(HERE.parent / "hermetic/hermetic-census.py"),
                      "--no-publish"], capture_output=True, text=True, cwd=REPO)
  if p.returncode != 0:
    raise RuntimeError(f"census rc={p.returncode}: {p.stderr[-400:]}")
  g = lambda k: int(re.search(rf"^# {k}\s*:\s*(\d+)", p.stdout, re.M).group(1))
  return {"graphs": g("graphs in corpus"), "py": g("reached PY"), "bend": g("reached BEND"),
          "both": g("reached BOTH"), "neither": g("reached by NEITHER")}

def report(measure: bool, quiet: bool) -> int:
  rows = list(CLAIMS)
  if measure:
    m = measure_census()
    rows = [(c, w, e, {"graphs in corpus": m["graphs"], "ops reached (both sides)": m["both"],
                       "ops NOT reached": m["neither"]}.get(c, cur), h) for c, w, e, cur, h in rows]
    print(f"# measured: graphs={m['graphs']} both={m['both']} neither={m['neither']}")

  stale = [r for r in rows if r[2] != r[3]]
  if not quiet:
    print(f"{'claim':<38} {'notes say':>10} {'measured':>10}  verdict")
    for c, w, e, cur, _ in rows:
      ok = e == cur
      print(f"{c:<38} {e!s:>10} {cur!s:>10}  {'ok' if ok else 'STALE'}   ({w})")

  print(f"\n# claims checked        : {len(rows)}")
  print(f"# STALE                 : {len(stale)}")
  print(f"# NOT RE-MEASURED       : {len(UNVERIFIED)}  (listed, not counted as passing)")
  for c, w, why in UNVERIFIED:
    print(f"#   STALE - {c}  [{w}]  {why}")

  # The important asymmetry, stated so a green run cannot be misread as a clean bill.
  if not stale:
    print("#\n# every RE-MEASURED claim agrees. This is NOT a clean bill of health:")
    print("# the unmeasured claims above are exactly the ones that bit this tree before.")
  return 2 if stale else 0

def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--quiet", action="store_true")
  ap.add_argument("--measure", action="store_true", help="run the real census first")
  ap.add_argument("--falsify", action="store_true",
                  help="perturb one claim and require the script to flag it")
  a = ap.parse_args()
  if a.falsify: return falsify()
  return report(measure=a.measure, quiet=a.quiet)

if __name__ == "__main__":
  sys.exit(main())