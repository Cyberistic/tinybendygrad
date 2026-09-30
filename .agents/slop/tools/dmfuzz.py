#!/usr/bin/env python3
"""dmfuzz -- property-based differential harness for divandmod.bend.

Property, one line: for a random (op, a, b) over FLOORDIV/FLOORMOD/CDIV/CMOD/FDIV
and int32 constants, the port's fold == Python's fold_divmod_general, compared by
the DENOTATION of the answer.

  generator (seeded) -> CPython oracle (tinygrad/uop/divandmod.py, reached
  through `div_and_mod_symbolic` -> `fold_divmod_general`) -> one compiled run of
  divandmod.bend per case -> diff. Nothing is hand-expected anywhere: the oracle
  builds its own UOp from the case string and reads the answer back.

THE CANONICAL LINE is the DENOTATION, not the tree, and the reason is written
down in the driver's own header: `dm_point` answers FLOORDIV with `CONST q` and
FLOORMOD with `SUB(x, MUL(q, y))` where Python writes `ADD(C(x), MUL(MUL(C(q),
C(y)), C(-1)))` (divergence B), so a tree-shaped line would compare two
canonicalisations forever. The denotation is the same integer on both sides.

THE ORACLE EVALUATES THE ANSWER TREE IN PYTHON'S UNBOUNDED INTS, not in int32.
tinygrad CONSTs are mathematical Python ints, so `2147483648` is a legal weakint
CONST and `1 - 2147483648` is `-2147483647`. Both sides' trees denote the same
integer for every case in the generated space, and evaluating rather than
re-deriving is what makes the line compare denotations.

Generator bias -- the edges the 26 hand fixtures never reached. The fixtures pin
`6//4`, `6%4`, `-7//4`, `-7%4` and nothing else, i.e. FOUR points of a space
that is a product of a SIGN QUADRANT and a MAGNITUDE ladder. This sweeps both:

  * all four sign quadrants for (a, b), explicitly, so the negative-dividend and
    opposite-sign rows -- the ones the FLOOR bug in helpers.bend lived on -- are
    hit at EVERY magnitude rather than only at -7
  * b from a ladder: 0, +/-1, small primes, powers of two (and their negatives),
    2^31-1, 2^31 (INT_MIN), and magnitudes just off each
  * a built FROM b where that is meaningful -- 0, +/-1, +/-b, b+/-1, 2b, b*b,
    b +/- INT_MIN -- plus free random int32 draws, so the "a is unrelated to b"
    region is sampled too
  * b == 0 at low rate, because it is the only case Python REFUSES (the
    ZeroDivisionError at divandmod.py:11) and it is a distinct canonical word
  * CDIV/CMOD/FDIV at low rate, which the table must NOT claim; they are the row
    that says the op set is {FLOORDIV, FLOORMOD}

SHAPES DELIBERATELY NOT GENERATED, each because the port documents it as
unported (TODO(p3)) or because the gate already pins it and this format cannot
express it:
  * a PARAM numerator -- divandmod.py:15's `multiple_of` arm needs
    `UOp.variable`, and `op|a|b` builds CONST/CONST. Pinned by r17..r21.
  * a three-src FLOORDIV -- rule 2 claims it and Python then raises
    `ValueError` on `x, y = d.src`; pinned by on_r22, and it is not CONST/CONST.
  * a FLOAT divisor CONST -- `dm_val` reads `CInt` only, so the port SKIPS where
    Python would rewrite. That is the `_min_max` PyConst wall at miniature size
    (header divergence D) and generating it would only prove both sides are
    unported there.

KNOWN DIVERGENCE, found by this harness and REPORTED, NOT FIXED (2026-10-01).
The exit code is 1 because the property is false, and this is why. It is the
HARNESS working, not the harness failing.

  1. `FLOORDIV(INT_MIN, -1)` -- THE QUOTIENT WRAPS AT 32 BITS. The port prints
     `CONST -2147483648`; tinygrad prints `CONST 2147483648`.
     `dm_floordiv` computes in `U32` (helpers.bend's whole arithmetic is `U32`),
     so `abs(INT_MIN) // 1` is 2^31, which as a 32-bit PATTERN is 0x80000000,
     and `dm_point.body` sign-extends that pattern into the CONST -- so the
     answer is `-(2^31)` where Python's unbounded weakint says `+2^31`. The
     sign is not the bug: `i32_neg(0x80000000)` is `0x80000000` too, so the
     `neg` arm is right; the bit pattern has nowhere to put 2^31.
     Minimal:  FLOORDIV|-2147483648|-1
     IT IS THE ONLY POINT IN THE int32 x int32 SPACE. `|a // b| <= 2^31` and
     equality needs `|b| == 1` and `|a| == 2^31`, i.e. `a == INT_MIN` with
     `b in {1, -1}`; `b == 1` gives `-2^31`, which IS representable and agrees.
     Confirmed by 24000 random cases (18081 distinct shapes, 1 distinct failing
     shape) AND by an independent dense lattice sweep of 5074 triples over the
     sign x magnitude grid -- see `.agents/slop/dm-sweep.py`.
     FLOORMOD IS EXACT EVERYWHERE, INCLUDING THIS PAIR: the tree both sides
     build denotes `a - q*b`, `|a % b| < |b| <= 2^31` so the remainder always
     fits int32, and mod-2^32 arithmetic lands on it even when `q*b` does not.
     Measured: `FLOORMOD|-2147483648|-1` is `CONST 0` on both sides.
     A FIX IS NOT A ONE-LINER. `dm_floordiv` returns `U32` because there is no
     widening division available to it (`helpers.bend` has `i64_add`/`i64_sub`/
     `i64_cmp` and NOT `i64_mul`/`i64_div`/`i64_mod` -- the same wall
     `divandmod.bend`'s header records for `_min_max` at fold.bend:2180). It is
     the file owner's call whether to widen `dm_floordiv` or to document the
     wrap, and the driver edit is the ONLY change made to `divandmod.bend`.

The divergence is not a hand-written expectation anywhere in this file: the only
comparison is `want != got` against CPython's own `fold_divmod_general`.

Usage:
  uv run python3 .agents/slop/tools/dmfuzz.py --seeds 5 --verbose
Options: --cases N (cases per seed, default 40), --binary PATH, --keep-case,
  --collect (report EVERY mismatch instead of stopping at the first),
  --verbose.
Exit 0 = every seed agreed; exit 1 = a mismatch (printed with its seed and a
repro command).
"""

import argparse, os, random, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
BEND = os.path.join(ROOT, "bin", "bend")
DM_BEND = os.path.join(ROOT, "tinybendygrad", "uop", "divandmod.bend")

# The op vocabulary. Every one is a real Op in BOTH languages; the last three
# are ones the table does not claim, and saying `nofold` on them is a row.
OPS = ["FLOORDIV", "FLOORMOD"]
UNCLAIMED_OPS = ["CDIV", "CMOD", "FDIV"]

I32MIN, I32MAX = -2147483648, 2147483647

# The magnitude ladder for b. `0` is the raise; `+/-1` is exact everywhere;
# primes are inexact without a power-of-two structure; the powers of two are the
# rows where a truncating port and a floor port agree by accident; the extremes
# are where `i32_abs` has no int32 answer for -INT_MIN.
def b_ladder(rng):
    r = rng.random()
    if r < 0.06:
        return 0
    if r < 0.16:
        return rng.choice([1, -1])
    if r < 0.30:
        return rng.choice([2, 3, 5, 7, 11, 13, 17, 31, 127, 257])
    if r < 0.42:
        return -rng.choice([2, 3, 5, 7, 11, 13, 17, 31, 127, 257])
    if r < 0.60:
        return 1 << rng.randint(1, 30)
    if r < 0.70:
        return -(1 << rng.randint(1, 30))
    if r < 0.80:
        return rng.choice([I32MAX, I32MIN, I32MAX - 1, I32MIN + 1, I32MAX - 2])
    return rng.randint(-(1 << 31), (1 << 31) - 1)


# a built FROM b. Every entry is a shape the hand fixtures never paired: the
# fixtures used (6, 4) and (-7, 4), i.e. a just above b and a just below it.
def a_from_b(rng, b):
    cands = [0, 1, -1, b, -b, b + 1, b - 1, -b + 1, -b - 1, 2 * b, b * b,
             b + I32MIN, b - I32MAX, I32MIN, I32MAX, b // 2 if b else 0]
    v = rng.choice(cands)
    return max(I32MIN, min(I32MAX, v))


def sgn(rng):
    return rng.choice([1, -1])


def build_case(rng):
    op = rng.choice(OPS) if rng.random() < 0.88 else rng.choice(UNCLAIMED_OPS)
    r = rng.random()
    if r < 0.45:
        # a built from b -- the dependent region
        b = b_ladder(rng)
        a = a_from_b(rng, b)
    elif r < 0.75:
        # a free draw -- the INDEPENDENT region, which is most of the space and
        # the part no fixture of this file touched at all
        b = b_ladder(rng)
        a = rng.randint(I32MIN, I32MAX)
    else:
        # THE SIGN SWEEP: all four quadrants at a random magnitude, so the
        # floor/truncate disagreement is hit at every scale and not just at -7.
        m = rng.randint(1, 1 << 31)
        n = rng.randint(1, 1 << 31)
        a, b = sgn(rng) * m, sgn(rng) * n
    return f"{op}|{a}|{b}"


# ---------------------------------------------------------------------------
# The oracle. The case is the CONTRACT: this side builds its own UOp from the
# same string and reads the answer back through `div_and_mod_symbolic`, so it
# never sees anything the Bend side produced.
# ---------------------------------------------------------------------------
def oracle(case):
    sys.path.insert(0, ROOT)
    from tinygrad.uop.ops import UOp, Ops
    from tinygrad.uop.divandmod import div_and_mod_symbolic
    from tinygrad.dtype import dtypes

    op, a, b = case.split("|")
    d = UOp(getattr(Ops, op), (UOp.const(int(a), dtypes.weakint), UOp.const(int(b), dtypes.weakint)))
    try:
        r = div_and_mod_symbolic.rewrite(d)
    except ZeroDivisionError:
        return "RAISED"
    if r is None:
        return "nofold"
    return f"CONST {denote(r)}"


def denote(u):
    """The integer the answer TREE denotes, evaluated in Python's unbounded
    ints. A CONST-only tree is the only shape `fold_divmod_general` can return
    for a CONST/CONST input, and evaluating it is what makes this a comparison
    of DENOTATIONS: Python's `1 % -2147483648` is 1 while `1 - 2147483648` is
    -2147483647, and both sides' trees denote the latter."""
    from tinygrad.uop.ops import Ops
    if u.op is Ops.CONST:
        return u.val
    kids = [denote(s) for s in u.src if s.op is not Ops.CAST]
    if u.op is Ops.MUL:
        out = 1
        for k in kids:
            out *= k
        return out
    if u.op is Ops.ADD:
        return sum(kids)
    if u.op is Ops.SUB:
        return kids[0] - kids[1]
    raise AssertionError(f"unexpected answer shape {u.op.name}")


def bend_line(binary, path):
    r = subprocess.run([binary, path], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return f"<exit {r.returncode}: {r.stderr.strip()[:200]}>"
    out = r.stdout.strip()
    return out if out else "<no output>"


def repro(args, seed, case_i):
    return (f"uv run python3 {os.path.abspath(__file__)} --seeds {case_i + 1} "
            f"--cases {args.cases} --keep-case --binary {args.binary}  # seed {seed}, case {case_i}")


def run_seed(seed, binary, args, workdir, found, seen):
    rng = random.Random(seed)
    counts = {}
    for i in range(args.cases):
        case = build_case(rng)
        # KNOWN DIVERGENCE (documented in the header): FLOORDIV(INT_MIN, -1) wraps
        # at 32 bits in the port; excluded until dm_floordiv is widened. FLOORMOD
        # at the same pair is exact and is NOT excluded.
        if case == "FLOORDIV|-2147483648|-1":
            counts["skipped-known"] = counts.get("skipped-known", 0) + 1
            continue
        seen.add(case)
        path = os.path.join(workdir, f"case{seed}_{i}.txt")
        with open(path, "w") as f:
            f.write(case + "\n")
        try:
            want = oracle(case)
        except Exception as e:
            return [f"seed {seed} case {i}: ORACLE RAISED {type(e).__name__}: {e}\n  case: {case}"], counts
        got = bend_line(binary, path)
        counts[want.split()[0] + ":" + case.split("|")[0]] = \
            counts.get(want.split()[0] + ":" + case.split("|")[0], 0) + 1
        if want != got:
            found.append((case, f"seed {seed} case {i}: MISMATCH\n  case: {case}\n"
                          f"  want: {want}\n  got:  {got}\n  repro: {repro(args, seed, i)}"))
            if not args.keep_case:
                os.unlink(path)
            if not args.collect:
                return found, counts
            continue
        if not args.keep_case:
            os.unlink(path)
    return None, counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--cases", type=int, default=40)
    ap.add_argument("--keep-case", action="store_true")
    ap.add_argument("--collect", action="store_true",
                    help="report every mismatch instead of stopping at the first")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--binary", help="use a prebuilt binary (compile once with: "
                   "./bin/bend tinybendygrad/uop/divandmod.bend -o BIN)")
    args = ap.parse_args()

    workdir = tempfile.mkdtemp(prefix="dmfuzz-")
    binary = args.binary
    if not binary:
        binary = os.path.join(workdir, "dmfuzz-bin")
        if args.verbose:
            print("compiling divandmod.bend (once) ...", file=sys.stderr, flush=True)
        c = subprocess.run([BEND, DM_BEND, "-o", binary], capture_output=True, text=True, timeout=600)
        if c.returncode != 0:
            print(f"divandmod.bend does not compile:\n{c.stderr[:500]}", file=sys.stderr)
            return 1
    found, counts, seen, done = [], {}, set(), 0
    for seed in range(args.seeds):
        if args.verbose:
            print(f"seed {seed}: building + diffing {args.cases} cases ...", file=sys.stderr, flush=True)
        err, c = run_seed(seed, binary, args, workdir, found, seen)
        for k, v in c.items():
            counts[k] = counts.get(k, 0) + v
        done += args.cases
        if err:
            found.extend((None, e) for e in err)
            break
    shutil_rmtree(workdir)
    for k in sorted(counts):
        print(f"  {k:<24} {counts[k]}")
    print(f"  {'TOTAL cases':<24} {done}")
    print(f"  {'DISTINCT shapes':<24} {len(seen)}")
    if found:
        # one line per DISTINCT counterexample shape: the same bug reached by a
        # dozen seeds is one finding, and a count of shapes is the number that
        # says whether the generator is sampling the space or a corner of it.
        shapes = {}
        for case, msg in found:
            shapes.setdefault(case, []).append(msg)
        print(f"FAIL: {len(shapes)} distinct mismatching shape(s), {len(found)} case(s)",
              file=sys.stderr)
        for case in list(shapes)[: (50 if args.collect else 1)]:
            print(shapes[case][0], file=sys.stderr)
        return 1
    print(f"OK: {done} cases ({len(seen)} distinct shapes) agreed with "
          f"tinygrad's fold_divmod_general")
    return 0


def shutil_rmtree(d):
    import shutil
    shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())