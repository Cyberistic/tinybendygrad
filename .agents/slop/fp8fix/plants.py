"""FX-6 -- the plants and the disarms, as TEXT EDITS on a copy of dtype.c.

A PLANT is a second, DIFFERENT wrong answer in the same place, and its moved set is
asserted EQUAL to a set derived from the mutation's own algebra over the oracle --
never to a transcribed list (AGENTS.md:137). A DISARM is the same function by a
different expression and must move nothing; a disarm that moves something is not a
failed disarm, it is a defect that has not been named yet (which happened to me once
in this file's history and is why the assertion is in code).

Order in run.sh is DISARM FIRST, then plant, then fix. Each edit is `(find, replace)`
and the script ASSERTS the find-string occurs exactly once, because a `replace` that
matched twice would be a second mutation wearing a plant's name.
"""
import os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
LIVE = os.path.join(REPO, 'tinybendygrad/runtime/dtype.c')
KN = ['fp8e4m3', 'fp8e5m2', 'fp8e4m3fnuz', 'fp8e5m2fnuz']
# dtype.py's own sig_bits, because a derived set that assumes four mantissa bits is a
# derived set for the wrong format -- which is how C-plant first predicted 56 against a
# measured 40.
SIG = [4, 3, 4, 3]
MAXNORM = [0x7E, 0x7B, 0x7F, 0x7F]


def code_fields(code, k):
    """exp and mant of an fp8 CODE, by dtype.py's own field split (dtype.py:273-275)."""
    mb = SIG[k] - 1
    return (code >> mb) & ((1 << (8 - SIG[k])) - 1), code & ((1 << mb) - 1)

FIXED_OVF = [0x43E80000, 0x476FFFFF, 0x4377FFFF, 0x476FFFFF]

# name -> (kind, [(find, replace)], derived)
#   kind      'plant' or 'disarm'
#   derived   a predicate (rowkey, kind_index, pattern) -> bool, evaluated against the
#             ORACLE. None for a disarm (a disarm's whole claim is the empty set).
EDITS = {
    # -- A: the ovf threshold. BOTH of these are BOUNDS, not exact sets, and the
    #    difference is worth stating: the arm's answer at a pattern is a function of the
    #    PORT, and the normal-path answer at the boundary is not a function of the
    #    oracle. So "which patterns change" is a bound; "how many actually change" is a
    #    measurement. A derived set that claimed equality here would be a fiction.
    'A-plant': ('plant', [
        ('static const u32 fp8_ovf[4]       = { 0x43E80000,  0x476FFFFF, 0x4377FFFF,  0x476FFFFF };',
         'static const u32 fp8_ovf[4]       = { 0x43E80000,  0x47700001, 0x43780001,  0x47700001 };')],
        # THE THRESHOLD ONE f32 PATTERN TOO HIGH. THE FIXED ARM FIRES AT `p > V`, so it
        # fires from V+1; the plant's fires from V+2. THE LOST SET IS THEREFORE
        # {V+1, V+2} -- and my first derived set said {V, V+1}, which the containment
        # assertion caught by reporting 12 out-of-mechanism rows. An off-by-one in the
        # PREDICTION is the same species of bug as the one the plant was written for.
        # BOUND, not equality: at e4m3's threshold saturating and rounding agree, which
        # A-plant-ge measures directly.
        lambda key, k, p: (key.startswith('E[')
                           and FIXED_OVF[k] + 1 <= (p & 0x7FFFFFFF) <= FIXED_OVF[k] + 2)),
    'A-plant-ge': ('plant', [
        ('} else if (absx > fp8_ovf[kind]) {',
         '} else if (absx >= fp8_ovf[kind]) {')],
        # `>=` differs from `>` AT EQUALITY ONLY. BOUND = {p == ovf}. This one MEASURED
        # ZERO, which is a property of the table and not a failure of the fixture: at
        # every format's own threshold, saturating and rounding give the same code, so
        # the arm is IDEMPOTENT there. The arm is still needed above the threshold.
        lambda key, k, p: key.startswith('E[') and p == FIXED_OVF[k]),
    'A-disarm': ('disarm', [
        ('static const u32 fp8_ovf[4]       = { 0x43E80000,  0x476FFFFF, 0x4377FFFF,  0x476FFFFF };',
         'static const u32 fp8_ovf[4]       = { 0x43E80000,  0x47700000, 0x43780000,  0x47700000 };'),
        ('} else if (absx > fp8_ovf[kind]) {',
         '} else if (absx >= fp8_ovf[kind] - 1) {')],
        # `absx >= P(v) - 1` IS `absx > 0x476FFFFF` with the table put back the way it
        # was. Same function, two edits, opposite directions: THE POINT of a disarm.
        None),
    # -- C: the subnormal decode scale ------------------------------------------------
    'C-plant': ('plant', [
        ('ldexpf(1.0f, 1 - (int)bias)', 'ldexpf(1.0f, 2 - (int)bias)')],
        # exactly the codes with exp == 0 and mant != 0, per format's own field split.
        # EXACT: the subnormal scale is a pure multiplier, so it changes the answer of
        # every such code and of no other code.
        lambda key, k, p: (key.startswith('D[')
                           and (lambda e, m: e == 0 and m != 0)(*code_fields(p, k)))),
    'C-disarm': ('disarm', [
        ('ldexpf(1.0f, 1 - (int)bias)', '1.0f / (1u << (bias - 1))')],
        None),
    # -- D: e4m3's nan is unsigned upstream ---------------------------------------------
    'D-plant': ('plant', [
        ('if (mant == mant_max) return 0x7FC00000u;   // dtype.py:278 `math.nan`, UNSIGNED',
         'if (mant == mant_max) return sgn ? 0x7FC00000u : 0xFFC00000u;')],
        # Swapping the arms changes only the code whose SIGN BIT IS CLEAR: d255 has sgn == 1,
        # and `sgn ? 0x7FC00000 : 0xFFC00000` answers 0x7FC00000 for it too, so d255
        # DOES NOT MOVE and d127 does. My first derived set took both and the assertion
        # reported "derived-but-static d255" -- correctly: the row the fix was ABOUT is
        # the row this plant REPAIRS. A prediction naming the symptom instead of the
        # mechanism is how a plant gets called inexact when it is exact.
        lambda key, k, p: (key.startswith('D[') and KN[k] == 'fp8e4m3'
                           and (lambda e, m: e == 15 and m == 7)(*code_fields(p, k))
                           and not p & 0x80)),
    'D-disarm': ('disarm', [
        ('if (mant == mant_max) return 0x7FC00000u;   // dtype.py:278 `math.nan`, UNSIGNED',
         'if (mant == mant_max) return f32_rewrap(NAN);   // same bits, a float constant')],
        None),
    # -- B: the ladder, which dtype.c does not have ---------------------------------------
    'B-plant': ('plant', [
        ('u32 sh = 1 - exp;', 'u32 sh = exp <= -3 ? 1u : 1u - exp;')],
        # exp == -3 is `denorm`'s OWN exponent field with a nonzero mantissa -- reachable
        # for e4m3 and e4m3fnuz only, the two whose `denorm` f32 pattern has a zero
        # mantissa, which is what leaves its exponent field INSIDE the window. `exp` is
        # a u32 and wraps, so exp == -3 is written `exp <= -3u`.
        # BOUND: sh = 1 instead of 4 changes the answer for MOST such rows, not all --
        # the two can coincide where the extra three bits round away. The exponent
        # field is MASKED: `p >> 23` on a negative pattern carries the sign bit, and
        # the containment assertion caught that too, as 112 out-of-mechanism rows.
        lambda key, k, p: (key.startswith('E[') and (p & 0x7FFFFFFF) > 0
                           and ((p >> 23) & 0xFF) - 127 + [7, 15, 8, 16][k] == -3)),
}


def make(name, out_dir):
    kind, edits, _ = EDITS[name]
    src = open(LIVE).read()
    for find, repl in edits:
        n = src.count(find)
        assert n == 1, '%s: find-string occurs %d times (must be 1)' % (name, n)
        src = src.replace(find, repl)
    path = os.path.join(out_dir, 'dtype.c')
    open(path, 'w').write(src)
    return path, kind


# -- BASE: THE FILE AS IT WAS, reconstructed by REVERSE-applying this unit's edits.
#
# TWO md5s, and the distinction is not pedantry. `BASE_MD5` is the whole pre-fix file;
# `BASE_CODE_MD5` is the same file with every `//` comment removed. The reconstruction is
# checked against the SECOND, because this unit also rewrote four comment blocks and a
# reverse-applied comment is brittle text nobody benefits from -- while a reverse-applied
# COMPILED LINE is exactly the thing that must be proven byte for byte. The comment
# delta is 41 lines, all of them `//`, and is reported rather than asserted.
BASE_MD5 = 'd8cb867e20c53a2cfaaba6d4dc2f7286'
BASE_CODE_MD5 = 'ebe5a0e43c117d4891a4bfa00929925b'


def code_md5(src):
    """md5 of the file with every `//` comment removed AND every blank line dropped.
    Both are needed: stripping the comments this unit rewrote leaves 16 empty lines
    where they used to be, which is a comment delta and not a code one."""
    import hashlib
    t = '\n'.join(l for l in re.sub(r'//[^\n]*', '', src).split('\n') if l.strip())
    return hashlib.md5(t.encode()).hexdigest()


def make_base(out_dir):
    """Reverse-apply every edit this unit made to dtype.c, and PROVE the result is the
    original by md5. The three forward edits, in reverse:"""
    src = open(LIVE).read()
    pairs = [
        # the ovf table and the comparison
        ('static const u32 fp8_ovf[4]       = { 0x43E80000,  0x476FFFFF, 0x4377FFFF,  0x476FFFFF };',
         'static const u32 fp8_ovf[4]       = { 0x43E80000,  0x47700000, 0x43780000,  0x47700000 };'),
        ('} else if (absx > fp8_ovf[kind]) {',
         '} else if (absx > fp8_ovf[kind]) {'),   # no-op: the arm is UNCHANGED by the fix
        # the subnormal decode scale
        ('ldexpf(1.0f, 1 - (int)bias)', '(1.0f / (1u << bias))'),
        # e4m3's nan
        ('if (mant == mant_max) return 0x7FC00000u;   // dtype.py:278 `math.nan`, UNSIGNED',
         'if (mant == mant_max) return sgn ? 0xFFC00000u : 0x7FC00000u;'),
    ]
    # the comparison arm text is identical before and after the fix, so reverse-applying
    # it is a no-op and md5 is what proves the rest. Drop it from the pair list.
    pairs = [p for p in pairs if p[0] != p[1]]
    for find, repl in pairs:
        assert src.count(find) == 1, 'BASE reverse: %r occurs %d times' % (find[:40], src.count(find))
        src = src.replace(find, repl)
    path = os.path.join(out_dir, 'dtype.c')
    open(path, 'w').write(src)
    got = code_md5(src)
    assert got == BASE_CODE_MD5, ('BASE is not the pre-fix file: code md5 %s != %s'
                                  % (got, BASE_CODE_MD5))
    return path


if __name__ == '__main__':
    out = sys.argv[2]
    if sys.argv[1] == 'BASE':
        p = make_base(out)
        print('BASE -> %s' % p)
    else:
        p, k = make(sys.argv[1], out)
        print('%s -> %s  [%s]' % (sys.argv[1], p, k))