#!/usr/bin/env python3
"""WHICH OF THE 17 PINS CAN GO RED, AND WHICH CANNOT. One scratch copy per perturbation.

`derive.selfcheck()` must pass first (byte identity on the live run) or nothing here is
evidence. Then, for each artifact FAMILY, the DEEPEST artifact in that family is perturbed
by the smallest realistic edit a real regression would make, the intermediates are
re-composed with `cmd_run`'s own expressions, the summary is re-derived, and the pins whose
VALUE MOVED are recorded.

  MOVED   the pin is SENSITIVE to that family -- the perturbation reached the pin
  still    the pin did not move -- the perturbation is one this family could really produce

The scratch copies live in the approved temp dir; `runs/graphcmp/D` is never written.
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import derive  # noqa: E402

PINS = derive.differ.PINS


def pin_moves(before, after):
    return sorted(k for (k, v) in before if k in PINS and dict(after).get(k) != v)


# (family, deepest artifact, [(old, new), ...], re-compose?)
PERTURBATIONS = [
    ("D1-graph-*  (34 verdicts)", "D1-graph-matmul.txt",
     [("VERDICT: AGREE", "VERDICT: DISAGREE")], False),
    ("D2-cmp-*  ->  D2-bytediff", "D2-cmp-matmul.txt",
     [("matmul BYTE-IDENTICAL", "matmul NOT COMPARED: py=0 bytes bend=0 bytes")], True),
    ("D9-stability-*  ->  D9-stability", "D9-stability-group-a.txt",
     [("VERDICT: AGREE", "VERDICT: DISAGREE")], True),
    # A SEPARATE perturbation for `stable-failed`, because it needs the OTHER branch of
    # `compose_stability`: `one_line(a)`. `cmd_run` retries a one-lined side ONCE before
    # naming it FAILED, so an edit that makes a side one line has to survive that retry --
    # which it does here, since the retry cannot run (`no bend`) and the composition reads
    # what is on disk. Measured, not assumed: if this pin moves, `stable-failed` has a
    # witness; if it does not, it is DEAD and that is the finding.
    ("D9-stability-* (0-ROW branch)", "D9-stability-group-a.txt",
     [("__ONE_LINE__", "emit bend: 0 rows after 5 attempts -- a FAILURE\n")], True),
    ("D5-plant-*  (7 plants)", "D5-plant-dtype.txt",
     [("VERDICT: DISAGREE", "VERDICT: AGREE")], False),
    ("D3-control-*  (5 controls)", "D3-control-matmul.txt",
     [("CONTROL VERDICT: OK", "CONTROL VERDICT: FAIL")], False),
    ("D4-cross-range", "D4-cross-range.txt",
     [("CROSS VERDICT: OK", "CROSS VERDICT: NO")], False),
    ("D0-selfcheck", "D0-selfcheck.txt",
     [("# SELFCHECK: OK", "# SELFCHECK: FAIL")], False),
    ("D7-conf", "D7-conf.txt", [("VERDICT: OK", "VERDICT: NO")], False),
    ("D0-coverage-census  (rc only)", "D0-coverage-census.txt",
     [("rc=0", "rc=1")], False),
    ("D0-coverage-census  (selfcheck)", "D0-coverage-census.txt",
     [("# ORACLE SELFCHECK: OK", "# ORACLE SELFCHECK: BAD")], False),
]


def run():
    ok, msg = derive.selfcheck()
    print(msg)
    if not ok:
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        base = derive.scratch_copy(Path(tmp) / "base")
        derive.compose_bytediff(base)
        derive.compose_stability(base)
        before = derive.rederive(base)
        rows = []
        for n, (family, artifact, edits, recompose) in enumerate(PERTURBATIONS):
            D = derive.scratch_copy(Path(tmp) / f"p{n}")
            derive.compose_bytediff(D)
            derive.compose_stability(D)
            p = D / artifact
            body = p.read_text(errors="replace")
            for old, new in edits:
                # `__ONE_LINE__` is the 0-row FAILURE shape, which is a whole-file rewrite and
                # not a substring edit: `one_line()` counts NEWLINES, so any multi-line edit to
                # a 31-line artifact leaves it multi-line and the branch never fires.
                if old == "__ONE_LINE__":
                    body = new
                elif old not in body:
                    rows.append((family, artifact, [], f"EDIT DID NOT APPLY: {old!r} absent"))
                    break
                else:
                    body = body.replace(old, new, 1)
            else:
                p.write_text(body)
                if recompose:
                    derive.compose_bytediff(D)
                    derive.compose_stability(D)
                rows.append((family, artifact, pin_moves(before, derive.rederive(D)), ""))
    return rows


def partition_check():
    """`stable-pairs` + `stable-failed` + `stable-differ` -- three pins or one number?"""
    with tempfile.TemporaryDirectory() as tmp:
        D = derive.scratch_copy(Path(tmp) / "p")
        derive.compose_bytediff(D)
        derive.compose_stability(D)
        got = dict(derive.rederive(D))
    n = lambda k: int(got[k].split(" of ")[0])
    return got["stable-pairs"], got["stable-failed"], got["stable-differ"], \
        n("stable-pairs") + n("stable-failed") + n("stable-differ")


def denominator_literals():
    """`of N` is a CONSTANT in differ.py's f-strings, or a derived count?"""
    return [("stable-pairs/failed/differ", "of 5", len(derive.differ.STAB)),
            ("plants-disagree", "of 7", len(derive.differ.PLANTS)),
            ("cross", "of 1", 1),
            ("conflations", "of 4", 4),
            ("controls", "of 5", len(derive.differ.CONTROLS))]


if __name__ == "__main__":
    rows = run()
    print("\n== SENSITIVITY: one perturbation per artifact family ==")
    print(f"{'FAMILY':38} {'ARTIFACT EDITED':32} PINS THAT MOVED")
    for family, artifact, moved, err in rows:
        print(f"{family:38} {artifact:32} {', '.join(moved) or '**NONE** ' + err}")
    print("\n== STABILITY IS A PARTITION ==")
    p, f, d, total = partition_check()
    print(f"stable-pairs={p}  stable-failed={f}  stable-differ={d}  ->  sum={total}")
    print("\n== DENOMINATORS: literal in differ.py, or derived? ==")
    for name, lit, actual in denominator_literals():
        print(f"{name:26} literal {lit:6} actual {actual:3} {'AGREE' if int(lit.split()[1]) == actual else 'DISAGREE'}")
    print(f"\nPINS TOTAL: {len(PINS)}")
    raise SystemExit(0 if rows else 1)
