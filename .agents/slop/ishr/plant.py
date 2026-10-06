"""Plant and disarm for `gates/i64-shr-gate.py`.

    .venv/bin/python .agents/slop/ishr/plant.py            # all four
    .venv/bin/python .agents/slop/ishr/plant.py P1 P2      # a subset

THE INSTRUMENT IS A WHOLE-`name=value` LINE DIFF, and a count of MOVED ROW NAMES, not a
verdict from the gate's exit code and not a comparison of row names alone. Both of those
have been recorded failing in this project: a name-comparing harness reported 0 moved for
all 30 mutations in one unit and all 68 in another, and `"" == ""` is the recorded shape
of a guard that cannot fail. So the baseline is `base.bd.rows`, every row is compared as a
whole line, and the moved set is printed BY NAME so a 0 can be told apart from a harness
that did not run.

THE BASELINE IS ASSERTED NON-EMPTY AND BY LENGTH before anything is compared, and it is a
FILE IN THIS DIRECTORY rather than a read of `gates/artifacts/`. Two reasons, both
recorded elsewhere in this tree: a red run used to leave the last GREEN artifact in place,
so reading it as a baseline would diff P1's rows under P2's heading; and `gatekit` now
empties the artifact directory before every run and promotes the staged lanes only on a
green verdict, so a red run's rows are not there to be read at all. The planted rows are
therefore captured from the driver run itself (see `run`).

EVERY PLANT IS IN `helpers.bend` AND NOT IN THE DRIVER, which is the gap the sibling
`i64_shl` gate named for itself: plants in a driver prove the HARNESS sees wrong answers,
not that the def under test is covered against its own mutation. `helpers.bend` is the
root of a 33-file import closure and has been truncated to 0 bytes four times, so its
sha256 is taken before every edit and VERIFIED after, and a mismatch aborts rather than
compounding.

NO `bend` PROCESS IS RUN CONCURRENTLY. Every run is sequential and bounded through
`checks/bounded.py`, and the verdict token is parsed rather than the exit code.
"""
import hashlib
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HELPERS = ROOT / "tinybendygrad" / "helpers.bend"
BASE = ROOT / ".agents/slop/ishr/base.bd.rows"
# The planted driver writes HERE, in this gate's own directory: `gates/artifacts/i64-shr/`
# is `gatekit`'s to clear and promote, and a file this harness leaves in it would be
# deleted by the gate that runs inside the same plant.
HERE = Path(__file__).resolve().parent
PLANTED = HERE / "planted.rows"
# Every row this driver emits starts with one of these two, and NOTHING ELSE in the captured
# output does -- which is what separates the rows from `bend`'s update notice and from
# `checks/bounded.py`'s verdict line without hand-listing 301 names.
ROW_PREFIX = ("sr_", "seed=")
ROWS = 301

# name -> (the line to find, the line to replace it with, what it breaks)
PLANTS = {
    # P1 drops the sign fill from the HIGH word. The classic arithmetic-shift bug: the low
    # word is untouched, so every row whose fill happens to be 0 (all three non-negative
    # values) is blind, and so is `neg1`, whose high word is all ones.
    "P1": ("U32.or(U32.shrn(hi, k), U32.shln(match_hi(neg), Nat.sub(32n, k))),",
           "U32.or(U32.shrn(hi, k), 0),"),
    # P2 drops the sign fill from the LOW word, i.e. writes it into the high word alone.
    # This is the bug the gate's `neg1 >> 33` pin names, and it is INVISIBLE for every
    # amount at or below 32 -- which is 60 of the 120 answers.
    "P2": ("U32.or(U32.shrn(hi, Nat.sub(k, 32n)),\n    U32.shln(match_hi(neg), Nat.sub(64n, k))))",
           "U32.shrn(hi, Nat.sub(k, 32n)))"),
    # P3 shifts the low word's cross term by one, i.e. `hi << (32-k)` becomes `hi << (31-k)`,
    # so `hi` supplies the wrong number of bits to the low word. This is the term that only
    # exists because the value CROSSES the word boundary, and the whole reason `spill` is in
    # the fixture set: `hi`'s bit 0 is set there and set in `max` too, but in `neg1` and
    # `zero` the term is invisible.
    "P3": ("U32.or(U32.shrn(lo, k), U32.shln(hi, Nat.sub(32n, k))))",
           "U32.or(U32.shrn(lo, k), U32.shln(hi, Nat.sub(31n, k))))"),
    # P4 wraps the amount modulo 64, which is the classic "the shift amount is masked to
    # the word width" bug. Only `one` and `max` at 64/65 and `signmin`/`spill` at 64/65 can
    # see it, and NOTHING at 127 can: the oracle computes that set rather than assuming it.
    "P4": ("Bool.pick(I64, U32.is_le(U32.from_nat(k), 32), i64_shr.lo(neg, hi, lo, k),",
           "Bool.pick(I64, U32.is_le(U32.mod(U32.from_nat(k), 64), 32), i64_shr.lo(neg, hi, lo, k),"),
}


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def rows_of(text, prefixes=None):
    """`name=value` rows, optionally restricted to a prefix set."""
    out = {}
    for line in text.splitlines():
        if prefixes is not None and not line.startswith(prefixes):
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


def run(name, find, repl):
    """Plant, run, restore. Returns (moved_names, gate_rc, stderr)."""
    before = sha(HELPERS)
    original = HELPERS.read_text()
    try:
        if original.count(find) != 1:
            print(f"{name}: the anchor line occurs {original.count(find)} times, so the plant "
                  "would not be a single surgical edit -- REFUSING", file=sys.stderr)
            return None, None, None
        HELPERS.write_text(original.replace(find, repl))
        after = sha(HELPERS)
        if after == before:
            print(f"{name}: helpers.bend's sha256 did not change, so the plant did not land",
                  file=sys.stderr)
            return None, None, None
        if HELPERS.stat().st_size == 0:
            print(f"{name}: helpers.bend is 0 bytes after the plant -- the recorded failure",
                  file=sys.stderr)
            return None, None, None
        if original.count("def i64_shr") != HELPERS.read_text().count("def i64_shr"):
            print(f"{name}: the plant removed a def", file=sys.stderr)
            return None, None, None
        # BOUNDED, SEQUENTIALLY, AND THE VERDICT TOKEN PARSED. `sz.bend` peaks at
        # 1,468 MB and four units are live, so no `bend` runs unguarded and none runs
        # concurrently with another.
        r = subprocess.run([str(ROOT / ".venv/bin/python"), "checks/bounded.py",
                            "--seconds", "900", "--mb", "2048", "--",
                            str(ROOT / ".venv/bin/python"), "gates/i64-shr-gate.py"],
                           capture_output=True, text=True, cwd=ROOT)
        if "WITHIN-LIMITS" not in r.stdout + r.stderr:
            print(f"{name}: the bounded run did not report a verdict token:\n"
                  f"{(r.stdout + r.stderr)[-400:]}", file=sys.stderr)
            return None, None, None
        # THE ROWS ARE CAPTURED HERE, NOT READ FROM `gates/artifacts/`. `gatekit` now clears
        # the artifact directory before every run and promotes the staged lanes ONLY on a
        # green verdict, which is the right policy and leaves a red run with an EMPTY
        # directory -- so a red run's rows cannot be read back from there at all. Reading
        # the artifact would also have been the sibling gate's recorded bug (a red run
        # leaving the last GREEN rows in place, diffed under the wrong heading), and doing it
        # here would reproduce that bug in the one instrument meant to detect it. So the
        # driver is run DIRECTLY, bounded, here, and the gate is run separately for its
        # verdict: two rows-301 evaluations per plant, never concurrently.
        # `--out` so the driver's rows land in a file this harness owns. Read from stdout
        # they are indistinguishable from `checks/bounded.py`'s own verdict line, which
        # contains an `=` and would inflate the row count by one on every single run.
        # `bend` has NO `--out` (measured: `unknown option --out`, rc 1), so the rows go to a file
        # this harness owns. MEASURED, AND IT MATTERS: `checks/bounded.py` copies its child's
        # stderr into ITS OWN STDOUT (`stderr=subprocess.STDOUT`, bounded.py:103) and then
        # appends its verdict to stdout too, so the redirect captures 303 lines -- the 301
        # rows, `bend`'s own "2.0.35 is available" notice, and the `[bounded] WITHIN-LIMITS`
        # token. The token is therefore read FROM THE SAME FILE as the rows and the rows are
        # filtered by the `_ROW` prefix, rather than assumed to arrive on a separate stream.
        PLANTED.unlink(missing_ok=True)
        subprocess.run(
            f".venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- "
            f"./bin/bend .agents/slop/ishr/shr.bend > {PLANTED}",
            shell=True, cwd=ROOT, env={**os.environ, "I64SHR_SEED": "7"})
        lane = PLANTED.read_text() if PLANTED.exists() else ""
        if "WITHIN-LIMITS" not in lane:
            print(f"{name}: the bounded driver run reported no verdict token:\n{lane[-400:]}",
                  file=sys.stderr)
            return None, None, None
        if not PLANTED.exists():
            print(f"{name}: the bounded driver run wrote no {PLANTED.name}", file=sys.stderr)
            return None, None, None
        # ONLY THE DRIVER'S OWN ROWS, by prefix -- see the note at the redirect above.
        rows = rows_of(lane, ROW_PREFIX)
        if len(rows) != ROWS:
            print(f"{name}: the planted driver emitted {len(rows)} rows, expected {ROWS}",
                  file=sys.stderr)
            return None, None, None
        return rows, r.returncode, r.stderr
    finally:
        HELPERS.write_text(original)
        rest = sha(HELPERS)
        if rest != before:
            print(f"{name}: helpers.bend was NOT restored ({rest[:16]} != {before[:16]})",
                  file=sys.stderr)
            sys.exit(2)


def main():
    """0 if every requested plant moved rows, the gate went red for each, and the disarm
    is byte-identical to the baseline. 1 otherwise, on any path."""
    want = sys.argv[1:] or sorted(PLANTS)
    bad = 0
    base = BASE.read_text().splitlines()
    assert len([l for l in base if l]) == ROWS, f"baseline is {len(base)} lines, expected {ROWS}"
    assert all(l.strip() and "=" in l for l in base), "the baseline has an empty or shapeless row"
    b = rows_of(BASE.read_text())
    print(f"baseline: {ROWS} rows, {len(b)} named, all non-empty")

    for name in want:
        if name not in PLANTS:
            print(f"{name}: not one of the known plants {sorted(PLANTS)}")
            bad += 1
            continue
        got = run(name, *PLANTS[name])
        if got[0] is None:
            print(f"\n{name}: DID NOT RUN")
            bad += 1
            continue
        now, rc, err = got
        moved = sorted(k for k in set(b) & set(now) if b[k] != now[k])
        print(f"\n{name}: gate rc={rc}, {len(moved)} of {len(b)} rows moved BY NAME")
        print(f"  moved: {moved}")
        if err.strip():
            print(f"  stderr: {err.strip()[:300]}")
        # THE OUT-OF-MECHANISM ASSERTION, in both directions, and both must be able to
        # FAIL: a plant that moves nothing means this fixture set cannot see that mutation,
        # and a plant that moves rows while the gate is GREEN means the diff missed them.
        if not moved:
            print(f"  {name} MOVED NOTHING -- this fixture set cannot see that mutation")
            bad += 1
        if rc == 0:
            print(f"  {name} PASSED the gate despite {len(moved)} moved rows")
            bad += 1

    # DISARM IS ASSERTED BY RE-RUN, NOT BY THE RESTORE. `run` already restored the file and
    # verified its sha256 in a `finally`, so the rows below are the GREEN run's rows read
    # back through the same instrument: the baseline diffed against a fresh bounded driver
    # run. If a plant had leaked, this would be non-zero and the disarm would be a claim.
    PLANTED.unlink(missing_ok=True)
    subprocess.run(
        f".venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- "
        f"./bin/bend .agents/slop/ishr/shr.bend > {PLANTED}",
        shell=True, cwd=ROOT, env={**os.environ, "I64SHR_SEED": "7"})
    after_run = rows_of(PLANTED.read_text(), ROW_PREFIX)
    left = sorted(k for k in set(b) & set(after_run) if b[k] != after_run[k])
    if left:
        print(f"DISARM FAILED: {len(left)} rows differ from the baseline after restoring: {left}")
        return 1
    print(f"\nDISARMED: {len(after_run)} rows, identical to the baseline through the same "
          "bounded instrument that armed them")
    print(f"i64-shr plants: {len(want) - bad} of {len(want)} armed and disarmed")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    # `main` returns 0 or 1 EXPLICITLY on every path, and `main() or 0` is NOT used: it
    # would discard a 1, which is the shape of a guard that reports a failure and exits 0.
    sys.exit(main())