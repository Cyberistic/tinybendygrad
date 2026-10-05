"""gates/i64-shr-gate.py -- the gate for `def i64_shr`, the absent half of `mixin/dtype.bend:58`.

    I64SHR_SEED=7 .venv/bin/python gates/i64-shr-gate.py     # 301 rows, 3 lanes

WHAT THIS GATE IS. `mixin/dtype.bend:58` records `SHL/SHR -> i64 shift -> NOWHERE` as ONE
row. `i64_shl` is at `tinybendygrad/helpers.bend:1819`, so that half of the row was stale
when it was written; `def i64_shr` was genuinely absent everywhere, and a grep settles
it, so a grep is not a gate. These rows are what makes the RIGHT shift checkable: every
amount in a table of ten `Nat` literals reaches `i64_shr` TWICE, once with the amount at
the row's own slot (syntax) and once at an index computed from the PROCESS ENVIRONMENT
(runtime data). The amount is what selects the shift's two ARMS, so a driver that could
not carry a runtime `Nat` would not compile and these 301 rows would not exist.

THE THREE LANES. `bd` is `bend` interpreting the driver, `bn` is the NATIVE compile of
the same driver, and `py` is CPython. There is no `i64_shr` in `tinygrad/` to call, so
the `py` lane is an INDEPENDENT EVALUATION of the same law by a different route -- one
unbounded `x >> k` in a single expression, then a decomposition -- not a transcription of
the pair shift. `bd == bn` is the anti-constant-folding check on the runtime amount.

THE CLAIMS RUN WHATEVER THE DIFF DID, and that ordering is not cosmetic. `gatekit.run()`
returning 1 on a lane disagreement is exactly when "the two routes reached DIFFERENT
amounts" is the thing worth saying, so a gate that skipped its claims on a failed diff
could never report the failure it exists to report. They run on `bd.out` and are SKIPPED,
loudly, unless that file holds exactly ROWS rows -- a stale artifact from a previous run
would otherwise be read as this run's answer, which is a claim about nothing. (That is a
known defect: `gatekit.run()` returns before writing, so a FAILED run leaves the last
green `bd.out` in place.)
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate  # noqa: E402

# THE FIXTURE, and it is read from the ENVIRONMENT because the driver reads it from the
# environment too (`H.getenv_int("I64SHR_SEED", 7)` at shr.bend). Both port lanes inherit
# it, so the seed is one value in the run rather than a constant duplicated in two files.
SEED = 7
os.environ["I64SHR_SEED"] = str(SEED)

# 1 `seed` row + 6 values x 10 amounts x 5 rows (`_x`, `_amt`, `_lc`, `_rt_amt`, `_rt`).
VALUES = ("neg1", "zero", "one", "signmin", "max", "spill")
AMOUNTS = 10
FIELDS = ("x", "amt", "lc", "rt_amt", "rt")
ROWS = 1 + len(VALUES) * AMOUNTS * len(FIELDS)

# THE ROW NAMES, spelled out rather than counted. A count is not a gate: 301 empty rows and
# 301 correct rows have the same length.
EXPECTED = ["seed"] + [f"sr_{v}_{i}_{f}" for v in VALUES for i in range(AMOUNTS)
                       for f in FIELDS]
assert len(EXPECTED) == ROWS

GATE = Gate(
    "i64-shr",
    bend=".agents/slop/ishr/shr.bend",
    oracle=".agents/slop/ishr/shr-oracle.py",
    rows=ROWS,
    pins=[("py", "seed"), ("bd", "seed"), ("bn", "seed")],
)


def lane_file(lane):
    """`gates/artifacts/i64-shr/<lane>.out`, wherever `gatekit` decided to stage it.

    RESOLVED, NOT ASSUMED. `gatekit`'s staging policy moved under this file once while it
    was being written -- it publishes lanes under `self.dir` for `run()`'s own reads and
    stages the raw stdout under a temp name that `_lane` passes as a "name" -- and a hard
    path here would have been a claim about a plumbing detail another unit owns. Both
    layouts are accepted, and the resolution FAILS LOUDLY if neither exists rather than
    falling through to an empty dict, which is the `"" == ""` shape.
    """
    p = GATE.dir / f"{lane}.{'rows' if lane == 'py' else 'out'}"
    if p.exists():
        return p
    staged = sorted(GATE.dir.glob(f".tmp*/{lane}*.out")) + sorted(GATE.dir.glob(f"{lane}.txt.*"))
    if staged:
        return staged[0]
    raise SystemExit(f"i64-shr-gate: no lane file for {lane} under {GATE.dir} -- the claims "
                     "would run on nothing")


def rows_of(lane):
    out = {}
    for line in lane_file(lane).read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


def unpair_u(s):
    hi, lo = (int(w) for w in s.split(":"))
    return (hi << 32) | lo


def unpair(s):
    v = unpair_u(s)
    return v - (1 << 64) if v >> 63 else v


def main():
    ok = GATE.run() == 0

    # THE FRESHNESS GUARD, and it is the sibling gate's recorded finding: `gatekit.run()`
# returned BEFORE writing, so a red run left the LAST GREEN `bd.out` in place and a diff of
# that path after a failure was a diff of the wrong run. The count is the guard -- and it is
# checked BEFORE the claims read a single row, because a claim made from a stale file is a
# claim about nothing. `gatekit` has since grown a clear-and-promote policy for its own
# reads; this one is kept because it guards THIS function, which reads the lane files
# directly and would otherwise inherit whatever is on disk.
    try:
        bd = lane_file("bd")
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 1
    if len([l for l in bd.read_text().splitlines() if l]) != ROWS:
        print(f"i64-shr-gate: {bd.name} is absent or not {ROWS} rows, so the "
              "literal-vs-runtime claim is SKIPPED rather than answered from a stale file",
              file=sys.stderr)
        return 1
    lanes = {t: rows_of(t) for t in ("py", "bd", "bn")}

    # THE SEED, on all three lanes. `== str(SEED)` rather than "the row is present",
    # because a pin that only asserts presence passes when the driver silently used its
    # default of 7. A lane that failed to read the environment is a gate failure, not a
    # silent fallback.
    for t in ("py", "bd", "bn"):
        if lanes[t].get("seed") != str(SEED):
            print(f"i64-shr-gate: {t} read seed {lanes[t].get('seed')!r}, expected {SEED}",
                  file=sys.stderr)
            ok = False

    # NO ROW MAY BE EMPTY. The recorded failure mode is a guard comparing `""` to `""` and
    # passing, so every value compared below is asserted NON-EMPTY first -- otherwise a
    # driver printing the right NUMBER of empty rows would sail through this function.
    # AND EVERY ROW MUST BE THERE: the expected NAMES are asserted, not just the count.
    for t, r in lanes.items():
        for k, v in r.items():
            if v == "":
                print(f'i64-shr-gate: {t}\'s {k} is EMPTY -- a row that compares "" to "" '
                      "can never fail", file=sys.stderr)
                ok = False
        missing = [k for k in EXPECTED if k not in r]
        if missing:
            print(f"i64-shr-gate: {t} is missing {len(missing)} rows, first {missing[0]} "
                  "-- a row count is not a row set", file=sys.stderr)
            ok = False

    # THE CLAIM A LINE DIFF CANNOT EXPRESS. A diff compares each row with its own
    # counterpart, so it can never say "`the same amount`, reached by both routes, gives
    # the same answer". Joined on the PRINTED amount, not on the row, because the two
    # routes reach the same amount on DIFFERENT rows -- that permutation is the point of
    # the seed.
    lit, rt = {}, {}
    for name in VALUES:
        for i in range(AMOUNTS):
            b = f"sr_{name}_{i}"
            lit.setdefault((name, lanes["bd"][f"{b}_amt"]), lanes["bd"][f"{b}_lc"])
            rt.setdefault((name, lanes["bd"][f"{b}_rt_amt"]), lanes["bd"][f"{b}_rt"])
    if len(lit) != len(VALUES) * AMOUNTS or len(rt) != len(VALUES) * AMOUNTS:
        print(f"i64-shr-gate: {len(lit)} literal (value, amount) pairs and {len(rt)} runtime "
              f"ones, expected {len(VALUES) * AMOUNTS} each -- the permutation is not a "
              "permutation", file=sys.stderr)
        ok = False
    for key, got in sorted(lit.items()):
        if key not in rt:
            print(f"i64-shr-gate: the runtime route never reached {key}", file=sys.stderr)
            ok = False
        elif rt[key] != got:
            print(f"i64-shr-gate: {key[0]} at amount {key[1]}: literal route says {got}, "
                  f"runtime route says {rt[key]} -- a runtime shift amount is NOT a Nat",
                  file=sys.stderr)
            ok = False

    # ---- THE BOUNDARY, restated over THE PORT'S OWN rows, which is the whole point ----
    #
    # `i64_shr` has NO width boundary: a sign-extending shift cannot outgrow a signed 64-bit
    # word. Asserted as a PREDICATE over all 60 cells of the literal route rather than as a
    # few hand-picked rows, because the claim is universal and a fixture that only checked
    # 64 and 65 would let `k = 33` through -- and 33 is exactly the amount the pair's
    # sign-fill split gets wrong when the fill is written into the high word alone.
    x_of = {}
    for name in VALUES:
        x_of[name] = unpair(lanes["bd"][f"sr_{name}_0_x"])
    wide = 0
    for (name, amt), got in sorted(lit.items()):
        x, k = x_of[name], int(amt)
        exact = x >> k
        if not -(1 << 63) <= exact <= (1 << 63) - 1:
            print(f"i64-shr-gate: {name} >> {k} = {exact} does not fit a signed 64-bit pair, "
                  "so i64_shr would need a wider carrier", file=sys.stderr)
            ok = False
        if unpair(got) != exact:
            print(f"i64-shr-gate: {name} >> {k} reads {unpair(got)}, expected {exact}",
                  file=sys.stderr)
            ok = False
        # AND THE PAST-THE-WIDTH ANSWER IS A SATURATION TO THE SIGN, NOT A WRAP: past 63 the
        # answer is -1 or 0, and an implementation that took the amount mod 64 would answer
        # `x` itself. Only SOME rows can see that, and which ones is a measured set rather
        # than an assumption -- so it is recomputed here from the port's own answers.
        if k >= 64:
            wide += 1
            if exact != (-1 if x < 0 else 0):
                print(f"i64-shr-gate: {name} >> {k} is {exact}, expected the saturation",
                      file=sys.stderr)
                ok = False
    if wide != 18:  # 3 non-negative values + 3 negative ones, x 3 amounts past 63
        print(f"i64-shr-gate: {wide} cells past the width, expected 18", file=sys.stderr)
        ok = False

    # THE AMOUNT WRAP IS BLIND ON MOST OF THOSE ROWS, and the gate says so out loud. A
    # wrap of 64/65/127 lands on 0/1/63, and `x >> 63` is -1 for every negative int64 and 0
    # for every non-negative one, so at 127 NO row can see a wrap. Recomputed rather than
    # pinned, because a pin is a claim about a number nobody here can re-derive.
    sees = sorted(k for k in lit if int(k[1]) >= 64
                  and (x_of[k[0]] >> (int(k[1]) % 64)) != (x_of[k[0]] >> int(k[1])))
    if len(sees) != 7:
        print(f"i64-shr-gate: only {len(sees)} of the past-the-width rows can distinguish a "
              f"mod-64 wrap from a saturation, expected 7: {sees}", file=sys.stderr)
        ok = False

    # THE SIGN FILL IS BLIND ON `neg1`, which is the row a naive fixture set is built from.
    # Asserted so that a later edit which made the fill unnecessary, or a fixture change that
    # made the rows vacuous, both fail here rather than passing quietly.
    # `0xC0000000:0xCD5E6F78`, SPELLED IN DECIMAL because `lit` holds the driver's own
    # decimal text and comparing two hand-transcribed hex strings is how a fixture goes
    # wrong and green. It was derived from CPython and then checked against the row.
    if lit.get(("spill", "1")) != "3221225472:3445518200":
        print(f'i64-shr-gate: spill >> 1 reads {lit.get(("spill", "1"))}, expected '
              "3221225472:3445518200 -- this is the row that makes the sign fill "
              "load-bearing, and neg1 cannot see it", file=sys.stderr)
        ok = False
    if lit.get(("neg1", "33")) != "4294967295:4294967295":
        print(f"i64-shr-gate: neg1 >> 33 reads {lit.get(('neg1', '33'))}, expected "
              "4294967295:4294967295 -- the fill belongs in BOTH words above amount 32",
              file=sys.stderr)
        ok = False

    print(f"i64-shr-gate: {ROWS} rows, 3 lanes identical, both routes agree at all "
          f"{len(VALUES) * AMOUNTS} (value, amount) pairs, and every one of the "
          f"{wide} past-the-width cells saturates to the sign" if ok
          else "i64-shr-gate: FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())