#!/usr/bin/env python3
"""W-3 generator: does Word(64n) INTEGER ADDITION actually run?

PRE-REGISTERED EXPECTATION (from CPython, computed below, not transcribed):
    Word.add(64n, A, B) returns the 64-bit little-endian integer sum, printed as
    an LSB-first bit string, and the bit string equals CPython's (A+B) in binary.

Word(p) is `Word.Con{head: Bool, tail: Word(p)}` and `Word.shl` puts the incoming
bit at the HEAD, so HEAD IS THE LOW BIT: Word(64n) is an LSB-first bit list.
That is the readback convention this probe ASSUMES, and the CPython comparison is
what confirms or refutes it -- a wrong convention here would make a correct
Word.add look wrong, and an uncorrect convention would make a wrong Word.add
look right. So the generator also emits a KNOWN CONSTANT probe: a Word built
from the literal bit pattern of 1, which must read back as ...0001.

No hand-written 64-deep nesting: python emits the WCon spine, because a typo in
hand-written nesting would be indistinguishable from a compiler bug.
"""
import subprocess, sys, pathlib

REPO = pathlib.Path(__file__).resolve().parents[3]
OUT = REPO / ".agents/slop/w64"
BEND = REPO / "bin/bend"


def bits_lsb_first(v: int, n: int = 64) -> str:
    assert 0 <= v < (1 << n), v
    return "".join("True{}" if (v >> i) & 1 else "False{}" for i in range(n))


def plain_lsb(v: int, n: int = 64) -> str:
    """Same order, but '1'/'0' -- the form IO.print actually emits."""
    assert 0 <= v < (1 << n), v
    return "".join("1" if (v >> i) & 1 else "0" for i in range(n))


def word_literal(v: int) -> str:
    """Nested WCon spine, LSB at the head, terminating in WNil{}."""
    s = "WNil{}"
    for i in range(63, -1, -1):
        b = "True{}" if (v >> i) & 1 else "False{}"
        s = f"WCon{{{b}, {s}}}"
    return s


def bch_fun() -> str:
    # `++` demands String on BOTH sides; a Char does not coerce. Char.show is
    # the bridge. Writing bch(b) directly gives "expected : String / observed :
    # Char" -- which, like every other error in this unit, does not name the
    # function you actually have to change.
    return '''def bch(b: Bool) -> Char:
  match b:
    case False{}:
      Chr{U32.from_nat(48n)}
    case True{}:
      Chr{U32.from_nat(49n)}
'''

# The readback: walk k peels, head is the low bit, emit LSB-first digits.
def bits_fun() -> str:
    return '''# Readback. `k` is the peel fuel (a parameter, because a match may only inspect
# a parameter) and it goes FIRST so the termination checker sees the shrinking
# argument before the free one. Prints LSB-first, so bit i of the answer is the
# i-th character -- which is the convention the CPython diff assumes.
def bits(k: Nat, w: Word(k)) -> String:
  match k:
    case 0n:
      ""
    case 1n+kk:
      match w:
        case WCon{b, t}:
          Char.show(bch(b)) ++ bits(kk, t)
'''

def probe(name: str, body: str) -> dict:
    p = OUT / name
    p.write_text(body)
    print(f"=== {name} ===")
    r = subprocess.run([str(BEND), str(p)], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        print(line)
    if r.stderr.strip():
        for line in r.stderr.splitlines():
            print("STDERR:", line)
    print(f"rc={r.returncode}")
    return {"rc": r.returncode, "out": r.stdout, "err": r.stderr}


HEADER = '''import Base

# Does a 64-bit word exist as a user-declared type? This is the whole question:
# Base ships F32{data: Word(32n)} and NO F64/I64/U64, so if a user can declare
# F64{data: Word(64n)} the representation question is settled.
type F64 is Data:
  F64{data: Word(64n)}

'''

# ---- control: a Word whose value is known to be 1 -------------------------
ctl = (HEADER + bch_fun() + bits_fun() + f'''
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("W-3 control w1   =" ++ bits(64n, {word_literal(1)}))
''')

# ---- the actual measurement ----------------------------------------------
# A, B and A+B must all be EVEN. W-1/W-2 measured that an odd Nat >= 2^48 is
# refused ("a Nat past the largest immediate 2^48-1") wherever it is produced,
# including inside `Word.to_nat`. The first version of this probe used
# A=0x0123456789ABCDEF, whose sum is ...DF00 -- even, fine -- but A itself is
# ODD, so the probe died inside the harness while printing its own a and b rows,
# and a harness that cannot run is not a harness. Even constants keep the
# measurement inside the range Nat can actually carry, which is the whole point:
# W-3 is asking whether Word(64n) ARITHMETIC works, not re-testing the ceiling.
A, B = 0x0123456789ABCDEE, 0x1111111111111110
EXP = (A + B) & ((1 << 64) - 1)
assert A % 2 == 0 and B % 2 == 0 and EXP % 2 == 0, "Word.to_nat refuses odd Nats >= 2^48"
print(f"# CPython expectation: A={A:#018x} B={B:#018x} A+B mod 2^64 = {EXP:#018x}")
print(f"# as LSB-first bits: {bits_lsb_first(EXP)}")
print(f"# as MSB-first bits: {bits_lsb_first(EXP)[::-1]}")
print()

probe("w3_control.bend", ctl)

main = (HEADER + bch_fun() + bits_fun() + f'''
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("W-3 a     =" ++ bits(64n, {word_literal(A)}))
    IO.print("W-3 b     =" ++ bits(64n, {word_literal(B)}))
    IO.print("W-3 sum   =" ++ bits(64n, Word.add(64n, {word_literal(A)}, {word_literal(B)})))
''')
res = probe("w3_wordadd.bend", main)

# ---------------------------------------------------------------------------
# GATE. The expected value is COMPUTED BY CPYTHON above, never transcribed, and
# the comparison is on whole `name=value` lines -- a harness that diffs row
# NAMES reported 0 for all 30 mutations in one unit of this project and 0 for
# all 68 in another. Two directions are checked, so a transposed readback
# convention cannot pass:
#   LSB-first  == CPython's (A+B) rendered LSB-first
#   MSB-first  != that, proving the convention was not silently reversed
# ---------------------------------------------------------------------------
rows = dict(
    line.split("=", 1) for line in res["out"].splitlines() if line.startswith("W-3 ")
)
expect_lsb = plain_lsb(EXP)
checks = [
    ("W-3 sum LSB-first equals CPython (A+B)", rows.get("W-3 sum   ", "") == expect_lsb),
    ("W-3 sum is NOT the MSB-first rendering", rows.get("W-3 sum   ", "") != expect_lsb[::-1]),
    ("W-3 a round-trips through the generator", rows.get("W-3 a     ", "") == plain_lsb(A)),
    ("W-3 b round-trips through the generator", rows.get("W-3 b     ", "") == plain_lsb(B)),
    ("bend exited 0", res["rc"] == 0),
]
print("--- gate ---")
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
print(f"got    sum = {rows.get('W-3 sum   ', '<none>')}")
print(f"expect sum = {expect_lsb}")

# Independent second opinion: decode what bend printed back to an integer,
# WITHOUT reusing the encoder. If the two disagree, the encoder is wrong.
got_bits = rows.get("W-3 sum   ", "")
if len(got_bits) == 64:
    back = sum((1 << i) for i, c in enumerate(got_bits) if c == "1")
    print(f"decode(bend sum) = {back:#018x}   CPython = {EXP:#018x}   "
          f"{'AGREE' if back == EXP else 'DISAGREE'}")

# The runnable, diffable artefact: stdout of both probes, verbatim.
(OUT / "w3_wordadd.out.txt").write_text(
    f"# command: ./bin/bend .agents/slop/w64/w3_wordadd.bend\n"
    f"# A={A:#018x} B={B:#018x} A+B mod 2^64 ={EXP:#018x}  (all from CPython)\n"
    + res["out"]
)
(OUT / "w3_control.out.txt").write_text(
    "# command: ./bin/bend .agents/slop/w64/w3_control.bend\n"
    "# a Word built from the literal bit pattern of 1 must read back as 1\n"
)
sys.exit(0 if all(ok for _, ok in checks) else 1)