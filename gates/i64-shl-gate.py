"""gates/i64-shl-gate.py -- the gate for `i64_shl` with a RUNTIME shift amount.

    I64SHL_SEED=7 .venv/bin/python gates/i64-shl-gate.py     # 151 rows, 3 lanes

WHAT THIS GATE IS, AND WHY IT IS A GATE AND NOT A NOTE.  A wall records that "`i64_shl`
takes a `Nat`, which a runtime shift amount cannot be".  `i64_shl` is at
`tinybendygrad/helpers.bend:1819`, it is PURE (`grep -c 'import \"' helpers.bend` is 0),
and it takes `+k: Nat` -- so the claim is about a TYPE and a grep settles it.  A grep is
not a gate.  The rows here are what makes the claim checkable: for every amount in a
table of ten `Nat` literals, `i64_shl` is called TWICE with the same amount, once with
the amount taken at the row's own slot (syntax) and once at an index computed from the
PROCESS ENVIRONMENT (runtime data).  If a runtime amount could not be a `Nat`, the
driver would not compile and these 151 rows would not exist.

THE TWO LANES ARE BOTH PORT LANES, which is the only shape available here: there is no
`i64_shl` in `tinygrad/` to call, so the CPython lane is an INDEPENDENT EVALUATION of
the same predicate by a different route (`(x << k) & 2**64` in one expression, then
decomposed), not a transcription.  `bd` is `bend` interpreting the driver and `bn` is
the NATIVE compile of the same driver; if constant folding differed between them, `bn`
would move and the gate would fail.

THE CLAIM `main` MAKES, WHICH NO LINE DIFF CAN EXPRESS.  A diff compares each row with
its own counterpart, so it can never say "`the same amount`, reached by both routes,
gives the same answer".  That is the wall, so it is asserted here, per value and per
AMOUNT rather than per row -- joined on the printed amount, which is why both amounts
are rows.  A seed that drifted would show up here first.
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT, Gate  # noqa: E402  (the five, BY PATH)


def _coindep():
    """The single declaration, loaded BY PATH -- see checks/coindep.py."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "coindep", Path(__file__).resolve().parent.parent / "checks" / "coindep.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


COINDEP = _coindep()

# THE FIXTURE, and it is read from the ENVIRONMENT because the driver reads it from the
# environment too -- `H.getenv_int("I64SHL_SEED", 7)` at shl.bend:137. Both port lanes
# inherit it, so the seed is one value in the run rather than a constant duplicated in
# two files. `main` below asserts the `seed` ROW equals it, so a lane that failed to
# read the environment is a gate failure rather than a silent fallback to the default.
SEED = 7
os.environ["I64SHL_SEED"] = str(SEED)

# 1 `seed` row + 3 values x 10 amounts x 5 rows (`_x`, `_amt`, `_lc`, `_rt_amt`, `_rt`).
ROWS = 1 + 3 * 10 * 5

# THE ROW NAMES, spelled out rather than counted.  A count is not a gate: 151 empty rows
# and 151 correct rows have the same length.  The set is also what lets a claim be made
# per (value, amount) instead of per row.
EXPECTED = ["seed"]
for _v in COINDEP.I64SHL_VALUES:
    for _i in range(10):
        EXPECTED += [f"sh_{_v}_{_i}_{_f}" for _f in ("x", "amt", "lc", "rt_amt", "rt")]
assert len(EXPECTED) == ROWS

# `seed` in every lane. A claim a diff cannot express: both lanes must have READ the
# environment rather than fallen back to the default 7, and if the seed ever moves the
# pin fails before the amount checks do.
GATE = Gate(
    "i64-shl",
    bend=".agents/slop/i64shl/shl.bend",
    oracle=".agents/slop/i64shl/shl-oracle.py",
    rows=ROWS,
    pins=[("py", "seed"), ("bd", "seed"), ("bn", "seed")],
)


def rows_of(lane):
    """`{name: value}` for one lane. An ABSENT lane is a `REFUSED`, not a `FileNotFoundError`.

    THE SIBLING'S SHAPE, AND IT WAS NOT THIS ONE. `gates/i64-shr-gate.py` resolves a lane
    through a `lane_file()` that raises `SystemExit(REFUSED)`; this file read the published
    path directly, so a missing `py.rows` escaped as `FileNotFoundError` and a missing
    `bd.out` was folded into the freshness guard's `ok = False`. MEASURED 2026-10-17, by
    stubbing `GATE.run` and pointing `GATE.dir` at a scratch dir: with every lane absent this
    file exited 1 through a `FileNotFoundError`, so "a lane is absent" had ONE exit and THREE
    mechanisms. ONE condition, ONE verdict, ONE mechanism.
    """
    p = GATE.dir / f"{lane}.{'rows' if lane == 'py' else 'out'}"
    try:
        text = p.read_text()
    except OSError as e:
        print(f"i64-shl-gate: no lane file for {lane} under {GATE.dir}: {e.strerror} -- the "
              "claims would run on nothing", file=sys.stderr)
        raise SystemExit(REFUSED) from e
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


def main():
    code = GATE.run()
    ok = code == PASS

    # THE CLAIMS RUN WHATEVER THE DIFF DID, and that ordering is not cosmetic.
    # `gatekit.run()` returning non-zero is exactly the situation in
    # which "the two routes reached DIFFERENT amounts" is the thing worth saying, so a
    # gate that skipped its claims on a failed diff could never report the failure it
    # exists to report.  They run on `bd.out` and are SKIPPED, loudly, unless that file
    # holds exactly ROWS rows -- a stale artifact from a previous run would otherwise be
    # read as this run's answer, which is a claim about nothing.
    #
    # TWO CONDITIONS, TWO EXITS -- THE SAME SPLIT AS `gates/i64-shr-gate.py`, WHICH IS WHY
    # IT IS THE SAME SHAPE HERE. The previous line was one boolean over `exists() and
    # count == ROWS`, so "bd.out is ABSENT" and "bd.out holds the WRONG NUMBER OF ROWS"
    # were one verdict reached by one exit. The absent case is `rows_of`'s `SystemExit`,
    # which answers `run()`'s own exit; the count is a `FAIL`, which is
    # `gatekit.py:618`'s own `DEAD if n == 0 else FAIL` for a lane that produced rows and
    # the wrong number of them. MEASURED 2026-10-17 on the previous revision: `bd.out`
    # absent exited 1 through a `FileNotFoundError` for all four of `run()`'s verdicts.
    #
    # **`code if code != PASS else REFUSED`, NEVER BARE `code`** -- a `PASS` from `run()`
    # with no lane to read would be a GREEN EXIT THAT MEASURED NOTHING.
    try:
        bd_text = (GATE.dir / "bd.out").read_text()
        n = len([l for l in bd_text.splitlines() if l])
        # THREE CONDITIONS, THREE EXITS, AND THE COUNT IS STILL ONE `if`. The ABSENT case is
        # the `OSError` arm below (`REFUSED`, or `run()`'s own verdict when that is not
        # `PASS`); the count is the arm here, and it carries TWO of the five: an EMPTY `bd.out`
        # is `DEAD` ("it ran and ALSO emitted nothing") and a wrong NON-EMPTY one is `FAIL`.
        # `gates/gatekit.py:648` already spells the split -- `return DEAD if n == 0 else FAIL`
        # -- and the block comment above claimed THIS arm WAS that mapping while the code was
        # a bare `return FAIL`. MEASURED with `gates/verdictcopy-gate.py` (which walks every
        # `.py` under `checks/`+`gates/` for a row-count guard that cannot tell the two
        # apart): this line and `gates/i64-shr-gate.py`'s were the ONLY TWO in the tree, and
        # both answered `1` (FAIL) for an EMPTY `bd.out`.
        #
        # **`run()`'s OWN VERDICT OUTRANKS THIS ONE** -- a `DEAD` from the lanes is a fact
        # about the lanes, and this arm is about the FILE ON DISK -- so the shape is
        # `code if code != PASS else DEAD/FAIL`, identical to the two arms below it.
        if n != ROWS:
            print("i64-shl-gate: bd.out holds %d rows, expected %d, so the literal-vs-runtime "
                  "claim is SKIPPED rather than answered from a stale file" % (n, ROWS),
                  file=sys.stderr)
            return code if code != PASS else (DEAD if n == 0 else FAIL)
        lanes = {t: rows_of(t) for t in ("py", "bd", "bn")}
    except OSError as e:
        print(f"i64-shl-gate: bd.out is absent under {GATE.dir}: {e.strerror}, so the "
              "literal-vs-runtime claim is SKIPPED rather than answered from a stale file",
              file=sys.stderr)
        return code if code != PASS else REFUSED
    except SystemExit as e:
        print(e, file=sys.stderr)
        return code if code != PASS else REFUSED

    # THE SEED, on both sides. `== str(SEED)` rather than "the row is present",
    # because a pin that only asserts presence passes when the driver silently used
    # its default.  `py` reads the same variable, so all three are asserted.
    for t in ("py", "bd", "bn"):
        if lanes[t].get("seed") != str(SEED):
            print(f"i64-shl-gate: {t} read seed {lanes[t].get('seed')!r}, expected {SEED}",
                  file=sys.stderr)
            ok = False

    # NO ROW MAY BE EMPTY. The recorded failure mode is a guard comparing `""` to
    # `""` and passing, so every value compared below is asserted NON-EMPTY first --
    # otherwise a driver that printed nothing but the right NUMBER of empty rows
    # would sail through this whole function.
    for t, r in lanes.items():
        for k, v in r.items():
            if v == "":
                print(f"i64-shl-gate: {t}'s {k} is EMPTY -- a row that compares "
                      '"":"" can never fail', file=sys.stderr)
                ok = False
        # AND EVERY ROW MUST BE THERE. A lane that printed the right NUMBER of empty
        # rows would pass the count check and mean nothing, so the expected NAMES are
        # asserted too rather than the count alone.
        missing = [k for k in EXPECTED if k not in r]
        if missing:
            print(f"i64-shl-gate: {t} is missing {len(missing)} rows, first "
                  f"{missing[0]} -- a row count is not a row set", file=sys.stderr)
            ok = False

    # THE CLAIM. For each value and each AMOUNT, the literal route's answer and the
    # runtime route's answer must be the same string. Joined on the amount, not on
    # the row, because the two routes reach the same amount on DIFFERENT rows --
    # that permutation is the point of the seed.
    lit, rt = {}, {}
    for name in ("neg1", "one", "lowhi"):
        for i in range(10):
            b = f"sh_{name}_{i}"
            lit.setdefault((name, lanes["bd"][f"{b}_amt"]), lanes["bd"][f"{b}_lc"])
            rt.setdefault((name, lanes["bd"][f"{b}_rt_amt"]), lanes["bd"][f"{b}_rt"])
    if len(lit) != 30 or len(rt) != 30:
        print(f"i64-shl-gate: {len(lit)} literal (value, amount) pairs and {len(rt)} "
              f"runtime ones, expected 30 each -- the permutation is not a permutation",
              file=sys.stderr)
        ok = False
    for key, got in sorted(lit.items()):
        if key not in rt:
            print(f"i64-shl-gate: the runtime route never reached {key}", file=sys.stderr)
            ok = False
        elif rt[key] != got:
            print(f"i64-shl-gate: {key[0]} at amount {key[1]}: literal route says "
                  f"{got}, runtime route says {rt[key]} -- a runtime shift amount is "
                  "NOT a Nat", file=sys.stderr)
            ok = False

    # THE BOUNDARY, restated over the PORT'S OWN rows rather than the oracle's: at
    # `k = 63` the pair must still be nonzero for `neg1`, and at `k = 64` it must be
    # `0:0`. This is the wall's row and the row one below it, and asserting both
    # here is what stops the pair of amounts being collapsed into one answer.
    neg1_63 = lit.get(("neg1", "63"))
    neg1_64 = lit.get(("neg1", "64"))
    if neg1_63 in (None, "0:0"):
        print(f"i64-shl-gate: neg1 << 63 answers {neg1_63} -- that is the int64 sign "
              "bit, so 63 and 64 have been collapsed", file=sys.stderr)
        ok = False
    if neg1_64 != "0:0":
        print(f"i64-shl-gate: neg1 << 64 answers {neg1_64}, expected 0:0 -- the pair "
              "is 64 bits wide and 2**64 does not fit it", file=sys.stderr)
        ok = False

    code_out = PASS if ok else (code if code != PASS else FAIL)
    print(f"i64-shl-gate: {ROWS} rows, 3 lanes identical, and the literal and runtime "
          "routes agree at all 30 (value, amount) pairs" if ok
          else f"{GATE.name}: {VERDICT[code_out]}")
    # PASS ONLY IF EVERYTHING PASSED, AND OTHERWISE `run()`'s OWN VERDICT RATHER THAN A
    # HARD 1 -- `gates/gatekit.py:770-774`'s own `gate()` propagates, and `gatekit.py:618`
    # can return `DEAD(5)` for a lane that emitted nothing while `bd.out` IS promoted.
    #
    # **`VERDICT[code_out]`, NOT `VERDICT[code]`** -- MEASURED 2026-10-17 on the sibling:
    # with `run()` stubbed to `PASS` and one claim forced false, `VERDICT[code]` printed
    # `PASS` while the process exited 1. The printed token and the returned exit are the
    # same expression here so they cannot drift.
    return code_out


if __name__ == "__main__":
    sys.exit(main())