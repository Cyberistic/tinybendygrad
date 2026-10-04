#!/usr/bin/env python3
"""LL-1 -- assemble the PURE `dtype.bend` from the LIVE one.

Every seam is replaced by anchor text, not by line number, and every anchor is
asserted to appear EXACTLY ONCE. A line-number patcher silently patches the wrong
lines the moment another agent edits the file above them; `assert s.count(a) == 1`
is the whole defence.

Usage: patch_dtype.py <tree-root> [--edit FILE:OLD=NEW ...]
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))

# ---------------------------------------------------------------------------
# The i64 tail. UPSTREAM'S SPELLING, and this is the change since DTYPEB:
# `i64_mul` exists (`helpers.bend:2206`), so `cdiv`/`cmod` are helpers.bend's own
# `cdiv_i64`/`cmod_i64` -- upstream's `x - cdiv(x,y)*y` -- and DTYPEB's
# multiply-free floor-pair derivation is deleted rather than kept as a second
# spelling of one function.
# ---------------------------------------------------------------------------
I64_TAIL = r'''
def Dt.i64_trunc(x: H.I64) -> H.I64:
  x

def Dt.i64_floor_div(a: H.I64, b: H.I64) -> H.I64:
  H.i64_div(a, b)

def Dt.i64_floor_mod(a: H.I64, b: H.I64) -> H.I64:
  H.i64_mod(a, b)

def Dt.i64_cdiv(+a: H.I64, +b: H.I64) -> H.I64:
  H.cdiv_i64(a, b)

def Dt.i64_cmod(+a: H.I64, +b: H.I64) -> H.I64:
  H.cmod_i64(a, b)

# The ceiling is `cdiv` plus one exactly when the division did not come out even
# and the operands SHARED a sign -- dtype.c:262-267 computes it that way, and it is
# what makes this def TOTAL where the spelling in helpers.py:66-69 is not.
# helpers.py's is `-(num // -amt)`, and `-x` is not representable when x is
# int64.min: `ceildiv(int64.min, int64.min)` is 1 in CPython and the negation route
# answers -1, because `-b` wraps back to int64.min and it computes 1 // 1 and
# negates it. `cmod_i64` is the non-exactness test and needs no multiply of its own,
# and it is asked ONCE: a first version passed it to `above` as well and computed the
# evenness test in BOTH places, so the `P1` plant -- delete one of the two -- moved 0
# rows. That is what a disarm does, not what a plant does, and it is the reason `P1`
# exists in the form it does. `cmod_i64` is a multiply and a subtract; asking twice
# was a cost as well as a redundancy.
#
# THE ZERO DIVISOR IS GUARDED HERE AND ONLY HERE. helpers.py:66-69 has no guard and
# CPython raises ZeroDivisionError; `runtime/dtype.c:262-263` and `runtime/dtype.js:171`
# both totalise it to 0, so 0 is the answer these seams already gave. The gate labels
# those rows TOTALISE and never counts one as a pass.
def Dt.i64_ceildiv.above(an: Bool, bn: Bool) -> Bool:
  Bool.not(Bool.xor(an, bn))

def Dt.i64_ceildiv.of(zero: Bool, +q: H.I64, +r: H.I64, up: Bool) -> H.I64:
  Bool.pick(H.I64, zero, H.i64_zero(),
    H.i64_add(q, H.i64_bit(Bool.to_u32(Bool.and(up, Bool.not(H.i64_is_zero(r)))))))

def Dt.i64_ceildiv(+a: H.I64, +b: H.I64) -> H.I64:
  Dt.i64_ceildiv.of(H.i64_is_zero(b), H.cdiv_i64(a, b), H.cmod_i64(a, b),
    Dt.i64_ceildiv.above(H.i64_is_neg(a), H.i64_is_neg(b)))
'''

# ---------------------------------------------------------------------------
# The fp8 ENCODER, ported from runtime/dtype.c:44-87 by DTYPEB and not landed: the
# live file has the DECODER (FROMBITS) and no encoder, so `Dt.fp8_from` and
# `float_to_fp8` are still seams. Every step is U32 arithmetic on a bit pattern --
# no F32 is ever BUILT -- so the whole encoder is pure and needs nothing from
# `F32.from_bits`, which is why these two close with `Dt.fp8_to` already closed.
# ---------------------------------------------------------------------------
FP8_TAIL = open(os.path.join(HERE, 'tail-fp8-enc.bend.txt')).read().rstrip('\n')

OLD_SEAMS = '''def Dt.i64_trunc(x: H.I64) -> IO(H.I64):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"

def Dt.i64_floor_div(a: H.I64, b: H.I64) -> IO(H.I64):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"

def Dt.i64_floor_mod(a: H.I64, b: H.I64) -> IO(H.I64):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"

def Dt.i64_cdiv(a: H.I64, b: H.I64) -> IO(H.I64):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"

def Dt.i64_cmod(a: H.I64, b: H.I64) -> IO(H.I64):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"

def Dt.i64_ceildiv(a: H.I64, b: H.I64) -> IO(H.I64):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"
'''

OLD_FP8_FROM = '''def Dt.fp8_from(bits: U32, kind: U32) -> IO(U32):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"
'''

OLD_FLOAT_TO_FP8 = '''def float_to_fp8(x: F32, dtype: S.Dt) -> IO(U32):
  Dt.fp8_from(F32.bits(x), fp8_kind(dt_name(dtype)))
'''


def once(s, a, b, what):
    n = s.count(a)
    assert n == 1, '%s: anchor appears %d times, wanted exactly 1' % (what, n)
    return s.replace(a, b, 1)


def patch(src):
    s = open(src).read()
    # IDEMPOTENCE, so the unit is reproducible AFTER the patch is landed. Without it
    # `run.py` cannot be re-run against the tree it produced -- the anchors are gone
    # and every anchor assertion fires. A patcher that only works once cannot be
    # re-gated, and a gate that cannot be re-run is a gate that decays.
    if OLD_SEAMS not in s:
        assert s.count(FP8_TAIL.split('\n')[1]) == 1 and s.count(I64_TAIL.split('\n')[1]) == 1, \
            'neither the seams nor the pure tail is present: refusing to guess'
        return s
    # The encoder goes in ABOVE `Dt.fp8_from`, next to the decoder it mirrors, and
    # the seven seams go out in one block so no half-applied state can exist.
    s = once(s, OLD_FP8_FROM,
             FP8_TAIL + '\n\ndef Dt.fp8_from(bits: U32, +kind: U32) -> U32:\n'
             '  fp8_enc(fp8_cfg(kind), kind, bits)\n',
             'Dt.fp8_from body')
    s = once(s, OLD_SEAMS, I64_TAIL + '\n', 'the six i64 seams')
    s = once(s, OLD_FLOAT_TO_FP8,
             'def float_to_fp8(x: F32, dtype: S.Dt) -> U32:\n'
             '  Dt.fp8_from(F32.bits(x), fp8_kind(dt_name(dtype)))\n',
             'float_to_fp8 signature')
    return s


def main():
    root = sys.argv[1]
    src = None
    for a in sys.argv[2:]:
        if a.startswith('--src:'):
            src = a[len('--src:'):]
    edits = []
    for a in sys.argv[2:]:
        if not a.startswith('--edit'):
            continue
        _, path, rest = a.split(':', 2)
        old, new = rest.split('=>', 1)
        edits.append((open(path).read().rstrip('\n'), new))
    dst = os.path.join(root, 'tinybendygrad', 'dtype.bend')
    # The SOURCE is a parameter so a mutation run patches the PRISTINE copy and not
    # whatever the live file says at that moment; two of those disagreeing is how a
    # baseline silently stops being a baseline.
    s = patch(src or os.path.join(REPO, 'tinybendygrad', 'dtype.bend'))
    for old, new in edits:
        s = once(s, old, new, 'edit')
    open(dst, 'w').write(s)
    print('wrote %s  %d lines' % (dst, len(s.splitlines())))


main()