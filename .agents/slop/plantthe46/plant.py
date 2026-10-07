#!/usr/bin/env python3
"""EVERY PLANT THIS UNIT LANDED, RUN IN BOTH DIRECTIONS, WITH RESIDUE ASSERTED ABSENT.

    .venv/bin/python .agents/slop/plantthe46/plant.py            # the table
    .venv/bin/python .agents/slop/plantthe46/plant.py --rows     # TSV

THE RULE THIS FILE EXISTS TO SATISFY. `.agents/slop/zerogate/REPORT.md` §4: *"TWO OF MY OWN FIRST
PLANTS WERE GREEN-ONLY AND PROVED NOTHING -- the lane I picked was a pre-rename capture (already
red), and the row name I invented didn't exist in it, so the plant was a NO-OP EXITING 0."* A plant
is only a plant if the SAME gate, on the SAME code path, produces a DIFFERENT verdict when the
mutation is absent. So every row here carries two invocations and asserts the two exit codes differ,
and the counterfactual is constructed by REMOVING the mutation -- never by pointing the gate at
something that was already red, which is what makes a plant vacuous.

THE COUNTERFACTUALS ARE BUILT HERE, NOT ASKED OF THE GATE. `checks/wallcheck.py --plant` writes the
ledger it grades; a counterfactual taken from the gate's own `--plant` would prove the gate agrees
with itself. So `SHIPPED_ROW` is read from `.agents/slop/wallcheck/walls.tsv` here and handed back
through `--ledger`: one row, unmutated, which is exactly what `--plant` changes one field of.

NO `bin/bend`. Every gate in this table is a `checks/*.py` that refuses above its parser and never
reaches the port compiler, and `--plant` is `env_precond`-free by construction. `bendarm`-style
subprocesses are not used anywhere in this file.
"""
import argparse
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = ROOT / ".venv" / "bin" / "python"
LEDGER = ROOT / ".agents/slop/wallcheck/walls.tsv"


def shipped_row() -> str:
    """The first data row of the shipped ledger, byte for byte. The unmutated control."""
    for line in LEDGER.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            return line + "\n"
    raise SystemExit("the shipped ledger has no data row")


def control_row(pattern, date=None) -> str:
    """A ledger holding ONE row derived from the shipped row, with `pattern` and `date` chosen here.

    WHY NOT THE SHIPPED ROW ITSELF, and this is `zerogate/REPORT.md` §4 reproduced in my own plant:
    the first version used the shipped row as the counterfactual for `--plant fail` and BOTH runs
    exited 1, because `W1a`'s anchor `^def i64_mul\\(` now MATCHES -- that wall LANDED in this tree,
    so the unmutated row is already red and the plant proved nothing. **A counterfactual has to be
    the opposite VERDICT, not merely an unmutated INPUT.** So the control pattern is one that cannot
    match any file, which grades STANDS (0) for the same row, the same scope, the same pin and the
    same code path -- and the only difference from the plant is whether the anchor matches.
    """
    f = shipped_row().rstrip("\n").split("\t")
    f[0], f[1], f[3], f[4] = "CONTROL", "MISSING", pattern, "-"
    f[6], f[7] = "-", "-"
    if date is not None:
        f[8] = date
    return "\t".join(f[:11]) + "\n"


NEVER = "^__CONTROL_ANCHOR_THAT_CANNOT_MATCH_ANY_FILE__$"


def run(rel, argv):
    r = subprocess.run([str(PY), str(ROOT / rel), *[str(a) for a in argv]],
                       cwd=ROOT, capture_output=True, text=True, timeout=300)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def head(out, n=64):
    for line in out.splitlines():
        if line.strip():
            return line.strip()[:n]
    return "(no output)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", action="store_true")
    a = ap.parse_args()
    with tempfile.TemporaryDirectory() as td:
        stances = pathlib.Path(td) / "control-stands.tsv"
        stances.write_text(control_row(NEVER))
        landed = pathlib.Path(td) / "control-landed.tsv"
        landed.write_text(control_row("^", date="2026-10-07"))
        cases = [
            ("checks/wallcheck.py", 0, ["--selftest"], [], "the shipped ledger, which is red today"),
            ("checks/wallcheck.py", 1, ["--plant", "fail"], ["--ledger", stances],
             "the same row with an anchor that cannot match: STANDS, so 0"),
            ("checks/wallcheck.py", 2, ["--ledger", "/no/such/walls.tsv"], [],
             "the shipped ledger, which exists"),
            ("checks/wallcheck.py", 3, ["--plant", "story"], ["--ledger", landed],
             "the same row with its date PRESENT: LANDED, so 1"),
            ("checks/wallcheck.py", 4, ["NO-SUCH-ID"], ["W1a"], "an id the ledger carries"),
            ("checks/wallcheck.py", 5, ["--plant", "dead"], ["--ledger", stances],
             "one row, so the population is NOT empty"),
            ("checks/no-txt.py", 0, [], ["--plant"], "the tree has no `.txt` the gate owns"),
            ("checks/no-txt.py", 1, ["--plant"], [], "the same tree, `.txt` absent"),
            ("checks/norm_check.py", 0, [], ["--plant"], "the real normaliser is the subject"),
            ("checks/norm_check.py", 1, ["--plant"], [], "the same normaliser, at rest"),
        ]
        rows = []
        for rel, verdict, plant, counter, why in cases:
            prc, pout = run(rel, plant)
            crc, cout = run(rel, counter)
            rows.append((rel, verdict, " ".join(plant) or "(no argv)", prc, head(pout),
                         " ".join(str(c) for c in counter) or "(no argv)", crc, head(cout), why,
                         prc == verdict and prc != crc))
    if a.rows:
        print("gate\tverdict\tplant_argv\tplant_rc\tplant_first\tcounterfactual_argv\t"
              "counterfactual_rc\tcounterfactual_first\twhy_the_counterfactual_is_not_a_plant"
              "\tmoves_both_ways")
        for r in rows:
            print("\t".join(str(x) for x in r))
        return 0
    w = max(len(r[2]) for r in rows)
    print(f"{'gate':24} {'rc':>2}  {'plant':{w}}  -> rc  {'counterfactual':{w}}  -> rc   MOVES")
    for rel, v, pa, prc, pl, ca, crc, cl, why, ok in rows:
        print(f"{rel:24} {v:>2}  {pa:{w}}  -> {prc:<3} {ca:{w}}  -> {crc:<3}  "
              f"{'YES' if ok else 'NO  <-- VACUOUS'}")
    print()
    for rel, v, pa, prc, pl, ca, crc, cl, why, ok in rows:
        print(f"  {rel} {v}: PLANT {pa or '(no argv)'} says {pl!r}")
        print(f"  {' ' * len(rel)} {v}: CONTROL {ca or '(no argv)'} says {cl!r} -- {why}")
    n_ok = sum(1 for r in rows if r[9])
    print(f"\n{n_ok} of {len(rows)} landed plants MOVE a verdict in both directions. "
          f"{len(rows) - n_ok} are VACUOUS and are named above.")
    return 0 if n_ok == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())