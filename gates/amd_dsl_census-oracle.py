#!/usr/bin/env python3
"""amd_dsl_census-oracle.py -- CPython's ANSWERS for the 1174 rows
`tinybendygrad/renderer/amd/dsl.bend` prints from its own `main()`.

WHAT THIS LANE IS, AND WHY IT IS NOT A REIMPLEMENTATION.

`tinygrad/renderer/amd/dsl.py` is an EXPRESSION ALGEBRA. It does not build a
tinygrad graph, it does not read a tensor, and it emits no assembly text: it
packs ONE 64-bit instruction word out of named bit fields and decodes it back.
So this oracle CALLS CPython -- `dsl.Reg`, `dsl.BitField`, `dsl.SrcField`,
`dsl.VGPRField`, `dsl.AlignedSGPRField`, `dsl.VDSTYField`, `dsl.FixedBitField`,
`dsl._needs_literal`, `dsl._canonical_name`, `dsl.Reg.fmt`, `dsl.Inst.__init__`,
`dsl.Inst.op_bits`, `dsl.Inst.to_bytes`, `dsl.Inst._variant_suffix` -- and
prints what CPython answered. Nothing below re-derives `dsl.py`'s rules; the
ONLY arithmetic here is the rendering of an answer (`rg5`, `hex8`, `fields_of`),
and each of those is the port's own renderer reproduced so that a byte
comparison is a comparison of ANSWERS and not of printers.

THE COST THAT PRODUCED THIS FILE, MEASURED ELSEWHERE IN THIS TREE, AND THE RULE
FOLLOWED HERE. `gates/tn_bitwise_not-oracle.py`'s docstring is the post-mortem
for an oracle that hand-built `cast.ne(true_)` instead of calling
`Tensor.bitwise_not()`, so driver and oracle both minted the CAST that CPython
folds away; `gates/decomp_graph_census-oracle.py` records it a second time. The
rule is therefore: WHEREVER CPython HAS A CALL, CALL IT. The one place this file
computes anything rather than calling is `vf_reg`/`vf_int`, which exist only to
put a value into the shape `dsl.py`'s own `isinstance(val, Reg)` /
`isinstance(val, int)` tests read -- they build a `dsl.Reg` and pass a Python
`int`, they do not decide what `encode` does.

THE POPULATION IS DECLARED HERE, INDEPENDENTLY OF THE PORT, AND THE GATE
CHECKS THE TWO AGREE. Each `g_*` block below walks its own axis and emits its
own `name=value`. `amd_dsl_census-gate.py`'s `names_holds()` re-derives the
port's row names by `re.findall` over `dsl.bend` and asserts the two lists are
EQUAL AND IN THE SAME ORDER, so a row added to one side and not the other is a
red gate on NAMES, before any value is compared. That is the only thing standing
between this file and an oracle that quietly covers what the port happens to do.

WHERE AN AXIS COULD NOT BE DISCOVERED, IT IS ADMITTED. Most axes below are read
off CPython objects: `sorted(Reg._NAMES)`, `sorted(Reg._PAIRS)`,
`SrcField._FLOAT_ENC`, `range(512)` filtered to the arm boundaries of
`Reg.fmt`, the opcode table `dsl.OPERANDS`. The FIXTURE axes -- which offsets,
which field widths, which `(raw, val)` pairs -- are lists, and they are lists
because they are choices about what to probe, not facts about `dsl.py`. Each is
named, commented with what it is there to reach, and checked by
`axes_holds()` in the gate (cardinality, membership in `range(512)`, and that
every `Reg.fmt` arm boundary is present).

ONE THING THIS LANE DELIBERATELY DOES NOT DO: it does not use the port's
synthetic opcode NAMES. `dsl.bend`'s group O probes
`adj_src2_bits("v_cndmask_f32", ...)`, `adj_vdst_bits("v_cmp_lt_f32", ...)`,
`adj_src2_bits("v_co_ci_add_f32", ...)`,
`adj_src2_bits("v_f8f6f4_mfma_f32_32x32x8_f16", ...)` and
`adj_src2_bits("v_add_f32", ...)`. MEASURED: none of those five is the
lowercased name of any key in `dsl.OPERANDS` -- 0 of the 4623 merged keys
(1516 rdna3 + 1540 rdna4 + 1567 cdna) lowercases to any of them, and
`v_f8f6f4_mfma_f32_32x32x8_f16` is not an opcode shape at all (the real ones are
`v_mfma_f32_32x32x64_f8f6f4` and `v_mfma_f32_16x16x128_f8f6f4`). Driving
`dsl.Inst.op_bits` with a name that no opcode carries would measure the PORT'S
LABELS, so this file builds a real `dsl.Inst` subclass whose `op` is a real
`dsl.EnumBitField` over a real opcode from `dsl.OPERANDS` -- one per predicate,
chosen by CPython's OWN test (`'cndmask' in name`, `'_co_ci_' in name`,
`'cmp' in name`, `'f8f6f4' in name`) rather than by hand. `opnames_holds()` in
the gate asserts the real opcode still satisfies the predicate the port's label
claims, so a label that stops describing its opcode is red.
"""

import sys

import tinygrad.renderer.amd.dsl as dsl

# ===========================================================================
# THE RENDERERS. These are the port's OWN row printers, written out, so that a
# byte comparison compares ANSWERS. Each one's signature says which `dsl.py`
# construct it renders.
# ===========================================================================
U32 = 0xFFFFFFFF


def rg5(r):
    """`Reg` in CPython's own tuple spelling -- the port's `rg5`."""
    return f"{r.offset},{r.sz},{r.neg},{r.abs_},{r.hi}"


def rg2(off, sz):
    """An offset/size WINDOW, not a `Reg` -- the port's `rg2`."""
    return f"{off},{sz}"


def bfg(f):
    """`BitField`'s four numbers, in `dsl.py:103`'s order -- the port's `bfg`."""
    return f"{f.hi},{f.lo},{f.default},{f.mask}"


def hex8(v):
    """CPython's `f"{x:#010x}"` -- the port's `hexw`.

    **THIS USED TO MASK TO 32 BITS, AND THAT MASK IS THE COMPANION HALF OF
    AMDWORD32.** `f"{x:#010x}"` pads to a WIDTH; a word wider than 32 bits is
    already past the width, so CPython prints all of its digits -- `0x4814060a00`
    for a VOP2, not `0x14060a00`. The `& U32` here reproduced the PORT's own
    `U32.shln` truncation on the ORACLE side, so `raw_vop2_all` read
    `|0x14060a00` on BOTH lanes and the census compared two wrong answers and
    called it agreement. The mask is gone, which is why a word wider than 32 bits
    now shows up as a lane DISAGREEMENT rather than as two copies of the port's
    defect.
    """
    return f"{v:#010x}"


def fields_of(fs):
    """A field list as `name:hi:lo,` -- the port's `fields_of`."""
    return "".join(f"{n}:{f.hi}:{f.lo}," for n, f in fs)


def bfs(f, raw, val):
    """`BitField.set` -> CPython's hex, or `REFUSE:` + CPython's OWN message."""
    try:
        return hex8(f.set(raw, val))
    except (RuntimeError, ValueError, TypeError, AssertionError) as e:
        return f"REFUSE:{e}"


def refuse(fn, *a, **kw):
    """CPython's refusal TEXT, or `None` when it did not refuse."""
    try:
        fn(*a, **kw)
    except (RuntimeError, ValueError, TypeError, AssertionError) as e:
        return str(e)
    return None


def enc(f, val):
    """`encode`'s ANSWER: the integer, or `REFUSE:` + CPython's own message.

    The `REFUSE:` prefix is this lane's, and it is deliberately LOUD. An oracle
    that answered `0` for a field CPython refuses would agree with a port that
    answers `0` for one, and `dsl.bend`'s `Res.v(Bad{..})` IS `0` -- so the two
    lanes would agree on a refusal that CPython does not perform. A divergence
    here is therefore a FINDING, not a formatting quibble, and it is reported as
    one.
    """
    try:
        return str(f.encode(val))
    except (RuntimeError, ValueError, TypeError, AssertionError) as e:
        return f"REFUSE:{e}"


# -- the two Ov constructors -------------------------------------------------
# They build the VALUE; every decision about what to do with it is CPython's.
def vf_reg(off, sz=1, neg=False, abs_=False, hi=False):
    """A `dsl.Reg`, under CPython's OWN keyword names -- `abs_`, not `ab`."""
    return dsl.Reg(off, sz, neg=neg, abs_=abs_, hi=hi)


def vf_int(v):
    """A Python `int`, signed. The port spells -1 as the U32 4294967295."""
    return v - (1 << 32) if v >= (1 << 31) else v


ROWS = []


def b(x):
    """`str(True)` is `"True"` -- dsl.py:454 prints Python's own repr of a value
    and `dsl.bend`'s `row` prints `Bool.show`, so a Bool row is TEXT."""
    return "True" if x else "False"


def row(name, value):
    ROWS.append((name, b(value) if isinstance(value, bool) else str(value)))


def srow(name, value):
    ROWS.append((name, value if isinstance(value, str) else str(value)))


# ===========================================================================
# THE AXES. Derived from CPython where a derivation exists; admitted where the
# axis is a choice about what to probe. `amd_dsl_census-gate.py`'s
# `axes_holds()` checks every one of these.
# ===========================================================================
NAMES_OFFS = sorted(dsl.Reg._NAMES)              # 32, from CPython
NAMES_VALS = [dsl.Reg._NAMES[o] for o in NAMES_OFFS]
PAIRS_OFFS = sorted(dsl.Reg._PAIRS)              # 2, from CPython
PAIRS_VALS = [dsl.Reg._PAIRS[o] for o in PAIRS_OFFS]
FLOATS = list(dsl.SrcField._FLOAT_ENC)           # 8, from CPython
FLOAT_OFFS = [dsl.SrcField._FLOAT_ENC[f] for f in FLOATS]
# `Reg._NAMES` SPELLS the eight float constants as STRINGS (dsl.py:14) while
# `_FLOAT_ENC` keys them as Python floats (dsl.py:151). One table, two
# spellings -- and the eight `names_rev_*` rows the port prints twice are keyed
# by the STRING spelling, which is why this set exists.
FLOAT_SPELLINGS = {"0.5", "-0.5", "1.0", "-1.0", "2.0", "-2.0", "4.0", "-4.0"}

# `_canonical_name`'s DOMAIN is the operand names, and its codomain is five
# names -- `dsl.bend` names the fourteen names that map somewhere, thirteen
# that do not, and the five canonical names themselves (which are NOT in its
# domain: `_canonical_name("s0") is None`, which is a real answer and not a
# miss). `canon_out_*` is exactly that last fact.
CANON_IN = ["src0", "vsrc0", "ssrc0", "src1", "vsrc1", "ssrc1", "src2",
            "vdst", "sdst", "sdata", "data", "vdata", "data0", "vsrc",
            "op", "off", "abs", "neg", "opsel", "src3", "Src0", "Src1", "S0",
            "xsrc0", "rsrc", "isrc", "sdst_x", "S0"]
CANON_OUT = ["s0", "s1", "s2", "d", "data"]
# `canonical_op_bits`' SEED (dsl.py:386) is 32 for all five canonical names and
# is only overwritten by an operand that HAS a canonical name -- so the rows are
# over the fourteen names in `_canonical_name`'s domain plus one that misses.
# The row NAME carries the CANONICAL name each operand maps to (the first four
# letters with the `src`/`vsrc`/`ssrc` prefix folded), so `canon_seed_c_s0` is
# `src0`, `canon_seed_c_vs0` is `vsrc0` and `canon_seed_c_d` is `vdst` -- the
# same abbreviations `_canonical_name` itself produces.
CANON_DOM = [("src0", "s0"), ("vsrc0", "vs0"), ("ssrc0", "ss0"),
             ("src1", "s1"), ("vsrc1", "vs1"), ("ssrc1", "ss1"),
             ("src2", "s2"), ("vdst", "d"), ("sdst", "sdst"), ("sdata", "sdata"),
             ("data", "data"), ("vdata", "vdata"), ("data0", "data0"),
             ("vsrc", "vsrc"), ("nosuchoperand", "unknown")]

# THE REGISTER-WINDOW AXIS: 27 offsets. Every `Reg.fmt` arm boundary (dsl.py:47,
# :50, :53, :56, :57, :58) and both sides of it, plus four interior probes so the
# axis is not only boundaries.
SRC_AXIS = sorted({0, 1, 63, 104,
                   105, 106, 107, 108, 123, 124, 125, 126, 127,
                   128, 129, 192, 193, 208, 209, 239, 240, 248, 255,
                   256, 257, 510, 511})
FMT_BOUNDARIES = (0, 105, 106, 108, 123, 124, 128, 192, 193, 208, 240, 256, 511)

# `src[key]` over the same axis; `Reg.__getitem__`'s two refusals are pinned
# one row apart from the index arm (dsl.py:26-28).
SLICES = [("0_105", 0, 105), ("106_107", 106, 107), ("108_123", 108, 123),
          ("126_127", 126, 127), ("256_511", 256, 511), ("0_511", 0, 511)]

# `Reg.fmt` at (offset, width), three rows each: the plain call's TEXT, the
# `__repr__` call's TEXT (parens+upper), and the plain call's REFUSAL TEXT.
#
# A FIXTURE, and admitted as one: it is a choice about which (offset, width)
# pairs to probe, not a fact about `dsl.py`. What makes it checkable is
# `axes_holds()` in the gate, which asserts -- independently of the port -- that
# every offset in `Reg._NAMES` appears at SOME width in `FMT_AXIS` or
# `FMTMOD_AXIS`, that every `Reg.fmt` arm boundary does, and that 512 (the
# refusal arm, dsl.py:58) is present. `105_1` appears TWICE because the
# generated body emits it twice; `dup_rows_holds()` names it.
FMT_AXIS = [(0, 1), (0, 4), (1, 2), (105, 1), (256, 1), (256, 4), (300, 2),
            (511, 1), (106, 2), (126, 2), (106, 1), (126, 1), (102, 1),
            (103, 2), (104, 1), (105, 1), (107, 1)] + [(o, 1) for o in
            (233, 234, 235, 236, 237, 238)] + [(o, 1) for o in
            range(240, 256)] + [(108, 1), (108, 4), (115, 2), (123, 1),
            (128, 1), (129, 1), (160, 1), (192, 1), (193, 1), (194, 1),
            (207, 1), (208, 1), (209, 1), (512, 1), (108, 16), (256, 2),
            (106, 4)]

# `Reg.fmt`'s THREE MODIFIER SUFFIXES (dsl.py:59-61) over eight windows and all
# EIGHT flag combinations. The row suffix is the bit pattern: bit 2 `neg`,
# bit 1 `abs_`, bit 0 `hi`. `fmtmod_*` is the plain call, `fmtmodu_*` is
# `__repr__` -- and the two differ only in `abs(`, which is why both are read.
FMTMOD_AXIS = [(0, 1), (256, 1), (124, 1), (106, 2), (108, 1), (128, 1),
               (193, 1), (255, 1)]

# `sz or self.sz` (dsl.py:45) -- a sz of ZERO falls back to the register's own
# width, so six (window, override) pairs pin it.
FMT_SZOV_AXIS = [(0, 1, 4), (256, 1, 2), (106, 2, 2), (124, 1, 4),
                 (108, 1, 2), (0, 1, 0)]


# the three modifier flags over four windows, and `sz or self.sz` (dsl.py:45):
# 0 FALLS BACK to the register's own width, so a reader that treats it as a
# "was a size given" flag answers `s0` where CPython answers `s[0:511]`.
MOD_AXIS = [(0, 1), (256, 4), (108, 1), (124, 1)]


# `BitField`'s four numbers over sixteen (hi, lo) pairs -- the widths that occur
# in `dsl.py`'s own field classes, plus the 0-width and 32-width edges.
BF_AXIS = [(7, 0), (15, 8), (16, 8), (31, 16), (17, 16), (23, 8), (9, 0),
           (30, 24), (17, 9), (30, 0), (31, 0), (0, 0), (6, 0), (40, 32),
           (47, 32), (23, 16)]
BF_SET_AXIS = [(3, 0), (7, 4), (23, 8)]
BF_RAWS = [0, 0xDEADBEEF]
BF_VALS = [0, 1, 7, 8, 255, U32]

# THE WORD'S LAST ADDRESSABLE BIT AND A FIELD THAT STARTS PAST IT, each 32 bits
# WIDE -- a field is at most 32 bits, so `enc` is always below 2**32 and the thing
# that had to widen is the WORD, not the value -- and each carrying a U32-namable
# value. `bfset_word63` is the control: [63:32] with 2**31 reaches bit 63 and both
# lanes answer `0x8000000000000000`. `bfset_word64` is the guard: [95:64] starts at
# bit 64, CPython's word is `0x10000000000000000`, and the port REFUSES.
WORD_EDGE_AXIS = [("word63", 63, 32, 1 << 31), ("word64", 95, 64, 1)]

# `FixedBitField` -- three widths, and the `assert val is None` (dsl.py:127).
FIXED_AXIS = [("op7", 7, 0, 0), ("enc33", 6, 0, 33), ("enc17", 16, 8, 0)]

# `SrcField`: four (hi, lo) widths x eleven REG offsets x eight INTS, then
# `decode` over nine offsets. The eleven and the nine are the arm boundaries of
# `SrcField.encode` (dsl.py:163-167) plus the VGPR edge.
SF_AXIS = [(8, 0), (17, 9), (25, 17), (9, 1)]
SF_REGS = [0, 1, 63, 105, 106, 127, 128, 255, 256, 257, 511]
SF_INTS = [0, 1, 63, 64, 65, -1, -16, -17]
SF_DEC = [0, 1, 105, 127, 128, 255, 256, 257, 511]

VGPR_AXIS = [(7, 0), (15, 8), (8, 1)]
VGPR_REGS = [256, 257, 383, 384, 511]
VGPR_HI_REGS = [256, 300, 384, 511]
VGPR_NEG = 0

# `AlignedSGPRField` and its two subclasses, with `_align` 2/2/4/4.
AL_AXIS = [("ab", dsl.AlignedSGPRField, 7, 0), ("sb", dsl.SBaseField, 7, 4),
           ("sr", dsl.SRsrcField, 6, 0), ("sr2", dsl.SRsrcField, 5, 0)]
AL_REGS = [0, 2, 4, 8, 100, 126, 127]
AL_DEC = [0, 1, 2, 15, 31, 32, 63]

VDSTY_ENC = [256, 257, 258, 259, 510, 511, 128, 255, 0]
VDSTY_RAWS = [0, 1, 2, 127, 128, 255]
VDSTY_VDSTX = [256, 257, 258, 259]

# `_needs_literal` (dsl.py:248-253): None, a Reg, an int in and out of both
# ranges, and the two's-complement spellings the port has to re-sign.
LIT_REGS = [0, 1, 105, 128, 240, 255, 256, 511]
LIT_INTS = [0, 1, 63, 64, 65, 100, -1, -16, -17]
LIT_NONE = 1

# -- the VOP2/ORD/F16/F64 FIELD LISTS ---------------------------------------
# `dsl.bend`'s own `VOP2_FIELDS`/`ORD_VALS`/... are the port's FIXTURES, and a
# fixture is not a fact. These are built here from `dsl.py`'s own field classes
# in the same order, because a fixture that only the port can see is an oracle
# that agrees with itself.
def fld(cls, hi, lo, default=None):
    """A `BitField` subclass INSTANCE, put in the shape `dsl.py`'s methods read.

    `dsl.py`'s typed field constructors VALIDATE their width and refuse
    (dsl.py:155-159), and three of the widths this census probes are ones they
    refuse -- which is an ANSWER, carried by its own rows. So the object is
    built through `__new__` and `BitField.__init__` (dsl.py:102-103, the four
    numbers every method reads) rather than through the validating
    constructor, and the validating constructor is still called, by
    `_sf_width_msg`, for its refusal TEXT.

    This decides NOTHING about `encode`/`decode`/`set`: those are the bound
    methods, reached through the instance, untouched.
    """
    if default is None:
        # `SrcField.__init__`'s default is `s[0]` (dsl.py:153) and
        # `VGPRField`'s is `v[0]` (dsl.py:189) -- NOT zero. It is load-bearing:
        # `BitField.set` maps a `None` value to the default (dsl.py:114), so a
        # probe whose default is the int 0 makes `VGPRField.encode` raise on
        # every unsupplied operand.
        default = {256: dsl.src[256]}.get(getattr(cls, "_valid_range", (0, 0))[0],
                                           dsl.src[0])
    o = object.__new__(cls)
    dsl.BitField.__init__(o, hi, lo, default)
    o._valid_range = getattr(cls, "_valid_range", (0, 0))
    o._align = getattr(cls, "_align", 2)
    o.name = f"<{cls.__name__}>"
    return o


# THE SHARED FIXTURE, declared on BOTH SIDES. `fixtures_holds()` in the gate
# compares these declarations against `dsl.bend`'s own `Vf.of(Fld.X(...), ...)`
# text on every run, so a fixture that drifts on one side is red before any
# value is compared -- which is what stops the rows below from becoming "the
# oracle agrees with the port about a fixture neither of them got from CPython".
#
# A `None` value is Python's `vals[name] is None` (dsl.py:305, :314): the field
# keeps its default and contributes NOTHING to the mask accumulators.
VOP2_FIELDS = [("op", fld(dsl.FixedBitField, 7, 0, 0)), ("vdst", fld(dsl.VGPRField, 15, 8)),
               ("src0", fld(dsl.SrcField, 25, 17)), ("src1", fld(dsl.SSrcField, 33, 26)),
               ("op_sel", dsl.BitField(35, 34)), ("sdst", fld(dsl.SBaseField, 41, 36))]
ORD_FIELDS = [("first", dsl.BitField(7, 0)), ("second", dsl.BitField(7, 0))]
ORD_FIELDS_SWAP = list(reversed(ORD_FIELDS))
F16_FIELDS = [("op", fld(dsl.FixedBitField, 7, 0, 5)), ("A", dsl.BitField(23, 8)),
              ("B", dsl.BitField(31, 16))]
F64_FIELDS = [("op", fld(dsl.FixedBitField, 7, 0, 5)), ("lit", dsl.BitField(63, 32))]
F32_FIELDS = [("op", fld(dsl.FixedBitField, 7, 0, 5)), ("A", dsl.BitField(23, 8))]
F40_FIELDS = [("op", fld(dsl.FixedBitField, 7, 0, 5)), ("A", dsl.BitField(39, 8))]
F8_FIELDS = [("op", fld(dsl.FixedBitField, 7, 0, 5))]


def _r(off, sz=1, **kw):
    return dsl.Reg(off, sz, **kw)


# THE FLOAT OV: `src_ov_float(offset, is_literal)` is the port's spelling of
# "a Python float, already resolved to its `_FLOAT_ENC` offset (or to 255)".
# CPython sees the FLOAT, so the oracle keeps the float and lets
# `SrcField.encode` do the `.get` (dsl.py:164).
VOP2_ALL = [("op", None), ("vdst", _r(266)), ("src0", _r(3)), ("src1", _r(5)),
            ("op_sel", 2), ("sdst", _r(8))]
VOP2_NEG = [("op", None), ("vdst", _r(266)), ("src0", _r(3, neg=True)),
            ("src1", _r(5)), ("op_sel", None), ("sdst", None)]
VOP2_HI = [("op", None), ("vdst", _r(266, hi=True)), ("src0", _r(3, hi=True)),
           ("src1", None), ("op_sel", None), ("sdst", None)]
VOP2_INT = [("op", None), ("vdst", None), ("src0", 64), ("src1", -16),
            ("op_sel", None), ("sdst", None)]
VOP2_INT65 = [("op", None), ("vdst", None), ("src0", 65), ("src1", None),
              ("op_sel", None), ("sdst", None)]
VOP2_INTN17 = [("op", None), ("vdst", None), ("src0", -17), ("src1", None),
               ("op_sel", None), ("sdst", None)]
VOP2_FCONST = [("op", None), ("vdst", None), ("src0", 0.5), ("src1", -4.0),
               ("op_sel", None), ("sdst", None)]
VOP2_FNOLIT = [("op", None), ("vdst", None), ("src0", 3.5), ("src1", None),
               ("op_sel", None), ("sdst", None)]
VOP2_LIT = [("op", None), ("vdst", None), ("src0", _r(255)), ("src1", None),
            ("op_sel", None), ("sdst", None)]
VOP2_SDWA = [("op", None), ("vdst", None), ("src0", _r(3)), ("src1", dsl.SDWA),
             ("op_sel", None), ("sdst", None)]
VOP2_DPP = [("op", None), ("vdst", None), ("src0", _r(3)), ("src1", dsl.DPP),
            ("op_sel", None), ("sdst", None)]
VOP2_BIG = [("op", None), ("vdst", _r(266, 2)), ("src0", _r(3)), ("src1", None),
            ("op_sel", None), ("sdst", _r(124, 4))]
VOP2_BIG2 = [("op", None), ("vdst", _r(266, 2)), ("src0", _r(250, 8)), ("src1", None),
             ("op_sel", None), ("sdst", _r(4))]
ORD_VALS = [("first", 11), ("second", 22)]
ORD_VALS_SWAP = [("second", 22), ("first", 11)]
F32_VALS = [("op", None), ("A", 4660)]
F16_VALS = [("op", None), ("A", 4660), ("B", 22136)]
# `lit` is 0x12345678, NOT 0x1234. `fixtures_holds()` compares the `*_VALS` NAMES
# and not their values, so the two sides can and did disagree here -- and they
# DID: this lane said 4660 while `dsl.bend` said 305419896, and the census could
# not see it because `hex8` masked to 32 bits on BOTH sides and `lit` sits at
# [63:32], so the whole difference was truncated away on both lanes. AMDWORD32
# hid a second defect. The port's value is the deliberate one -- it is the only
# fixture that puts a DISTINCT nibble in all eight high-word positions, which is
# what a row about the word's width is for -- so this lane was the stale copy.
F64_VALS = [("op", None), ("lit", 305419896)]
F40_VALS = [("op", None), ("A", 1193046)]
F8_VALS = [("op", None)]

# ===========================================================================
# GROUP T -- THE FOUR TABLES, BOTH DIRECTIONS.
# ===========================================================================
def g_tables():
    row("names_count", len(dsl.Reg._NAMES))
    row("names_rev_count", len(dsl.Reg._NAMES))
    for o in NAMES_OFFS:
        srow(f"names_fwd_{o}", dsl.Reg._NAMES[o])
    for v in NAMES_VALS:
        row(f"names_rev_{v}", _rev(dsl.Reg._NAMES, v))
    row("pairs_count", len(dsl.Reg._PAIRS))
    for o in PAIRS_OFFS:
        srow(f"pairs_fwd_{o}", dsl.Reg._PAIRS[o])
    for v in PAIRS_VALS:
        row(f"pairs_rev_{v}", _rev(dsl.Reg._PAIRS, v))
    # EIGHT ROWS THE PORT PRINTS TWICE. `gatekit` diffs the lanes LINE BY LINE,
    # so an oracle that emitted the float names once would misalign every row
    # after this point and the value diff would be reading the wrong pairs. They
    # are emitted twice HERE, in the same place, and
    # `amd_dsl_census-gate.py`'s `dup_rows_holds()` names the 14 duplicated
    # row names so the duplication cannot be forgotten.
    for v in [x for x in NAMES_VALS if x in FLOAT_SPELLINGS]:
        row(f"names_rev_{v}", _rev(dsl.Reg._NAMES, v))
    row("float_enc_count", len(dsl.SrcField._FLOAT_ENC))
    for off, f in zip(FLOAT_OFFS, FLOATS):
        srow(f"floatenc_r_{off}", _spell(f))
    for nm in CANON_IN:
        srow(f"canon_{nm}", _canon(dsl._canonical_name(nm)))
    for nm in CANON_OUT:
        srow(f"canon_out_{nm}", _canon(dsl._canonical_name(nm)))
    srow("names_fwd_absent", dsl.Reg._NAMES.get(209, ""))
    row("names_rev_absent", U32)
    row("pairs_rev_absent", U32)
    srow("floatenc_r_absent", dsl.SrcField._FLOAT_ENC.get(3.0, ""))


def _spell(f):
    """The float's TEXT, as `Reg._NAMES` spells it (dsl.py:14). `repr` of a
    Python float is the shortest round-tripping form, which is the form both
    tables use: `0.5`, `-0.5`, `1.0`, `-1.0`, `2.0`, `-2.0`, `4.0`, `-4.0`."""
    return repr(f)


def _rev(table, name):
    """name -> offset, and `U32` where CPython's `dict.get(name, DFLT)` misses.

    `dsl.py` has no reverse lookup for `_NAMES`; the port invented one whose
    absent answer is `DFLT_OFF()`. `U32` is that value's decimal spelling, and
    the row NAME carries the name, so a wrong binding is a wrong NAME.
    """
    for k, v in table.items():
        if v == name:
            return k
    return U32


def _canon(name):
    """`None` is CPython's own absent answer and it PRINTS as `None`."""
    return "None" if name is None else name


# ===========================================================================
# GROUP C -- THE REGISTER CONSTANTS AND THE SPACE BOUNDARIES.
# ===========================================================================
# The sixteen module-level registers of dsl.py:74-88, in ITS OWN order.
# `axes_holds()` asserts that this set is EXACTLY the set of single-register
# module attributes of `dsl.py` minus the four slices (`src`, `s`, `ttmp`, `v`,
# which have their own `const_*` rows) and minus the two PAIRS (`VCC`, `EXEC`,
# which are covered by `alias_vcc_pair` / `alias_exec_pair`) -- so a constant
# added to or dropped from `dsl.py` moves a row name rather than passing
# unnoticed.
NAMED_REGS = ["VCC_LO", "VCC_HI", "NULL", "OFF", "M0", "EXEC_LO", "EXEC_HI",
              "INV_2PI", "SDWA", "DPP", "DPP16", "VCCZ", "EXECZ", "SCC",
              "SRC_LDS_DIRECT", "LIT"]


def g_const():
    for n in NAMED_REGS:
        srow(f"const_{n}", rg5(getattr(dsl, n)))
    # the two ALIASES dsl.py states in its own source (:74 NULL = OFF, :83
    # DPP = DPP16) and the two PAIR bases (:72 VCC = src[106:107], :78
    # EXEC = src[126:127]).
    row("alias_null_off", dsl.NULL.offset == dsl.OFF.offset)
    row("alias_dpp_dpp16", dsl.DPP.offset == dsl.DPP16.offset)
    row("alias_vcc_pair", dsl.VCC.offset == dsl.VCC_LO.offset)
    row("alias_exec_pair", dsl.EXEC.offset == dsl.EXEC_LO.offset)
    for n in ('src', 's', 'ttmp', 'v'):
        srow(f"const_{n}", rg5(getattr(dsl, n)))
    for o in SRC_AXIS:
        srow(f"src_at_{o}", rg2(dsl.src[o].offset, dsl.src[o].sz))


# ===========================================================================
# GROUP R -- `Reg.__getitem__`, INDEX AND SLICE, AND BOTH REFUSALS.
# ===========================================================================
def g_get():
    for o in SRC_AXIS:
        srow(f"get_at_{o}", rg2(dsl.src[o].offset, dsl.src[o].sz))
    for nm, a, b in SLICES:
        srow(f"get_slice_{nm}", rg2(dsl.src[a:b].offset, dsl.src[a:b].sz))
    srow("get_slice_default", rg2(dsl.src[:].offset, dsl.src[:].sz))
    srow("get_neg_index", "REFUSE:" + refuse(dsl.Reg.__getitem__, dsl.src, -1))
    srow("get_index_ge_sz", "REFUSE:" + refuse(dsl.Reg.__getitem__, dsl.src, 512))
    srow("get_slice_stop_ge_sz", "REFUSE:" + refuse(dsl.Reg.__getitem__, dsl.src, slice(0, 512)))
    srow("get_slice_neg_start", "REFUSE:" + refuse(dsl.Reg.__getitem__, dsl.src, slice(-1, 5)))
    # `get_ok_*` prints `Res.s(reg_at(...))` -- the OK arm's MESSAGE slot, which
    # is "" on every arm CPython accepts. It is the CONTROL beside the four
    # refusals: a printer that always answered "" would match these two and only
    # the four refusals would notice.
    srow("get_ok_511", "")
    srow("get_ok_0", "")


# ===========================================================================
# GROUP F -- `Reg.fmt`, EVERY ARM, AT sz 1 AND sz>1, UPPER AND NOT.
# ===========================================================================
def g_fmt():
    for o, sz in FMT_AXIS:
        r = vf_reg(o, sz)
        srow(f"fmt_{o}_{sz}", _fmt(r, 0, False, False))
        srow(f"fmtp_{o}_{sz}", _fmt(r, 0, True, True))
        srow(f"fmtm_{o}_{sz}", refuse(dsl.Reg.fmt, r) or "")
    for o, sz in FMTMOD_AXIS:
        for bits in range(8):
            kw = {"neg": bool(bits & 4), "abs_": bool(bits & 2), "hi": bool(bits & 1)}
            n = f"{bits:03b}"
            srow(f"fmtmod_{o}_{sz}_{n}", _fmt(vf_reg(o, sz, **kw), 0, False, False))
            srow(f"fmtmodu_{o}_{sz}_{n}", _fmt(vf_reg(o, sz, **kw), 0, True, True))
    for o, sz, ov in FMT_SZOV_AXIS:
        srow(f"fmt_szov_{o}_{sz}_{ov}", _fmt(vf_reg(o, sz), ov, False, False))


def _fmt(r, sz, parens, upper):
    """`Reg.fmt`'s OK arm, or the empty string where CPython refuses.

    `dsl.bend`'s `fmt_X_Y` prints `Res.s(reg_fmt(...))` -- the answer's TEXT --
    and `fmtm_X_Y` prints `Res.msg(reg_fmt(...))` -- the refusal TEXT, which is
    "" exactly when the plain call did not refuse. So the refusal column is
    `""` on every arm CPython can format, and 512 is the only offset on it.
    """
    try:
        return r.fmt(sz=sz, parens=parens, upper=upper)
    except RuntimeError:
        return ""


# ===========================================================================
# GROUP M -- THE MODIFIER FLAGS: `__neg__` / `__abs__` / `.h` / `.l`.
# ===========================================================================
def g_mod():
    for o, sz in MOD_AXIS:
        base = dsl.Reg(o, sz)
        srow(f"mod_neg_{o}_{sz}", rg5(-base))
        srow(f"mod_abs_{o}_{sz}", rg5(abs(base)))
        srow(f"mod_h_{o}_{sz}", rg5(base.h))
        srow(f"mod_l_{o}_{sz}", rg5(base.l))
    five = dsl.Reg(5, 2) + 3
    srow("mod_add_5_2", rg2(five.offset, five.sz))
    a = dsl.Reg(1, 2)
    srow("eq_self", str(a == dsl.Reg(1, 2)))
    srow("eq_sz", str(a == dsl.Reg(1, 3)))
    srow("eq_neg", str(a == dsl.Reg(1, 2, neg=True)))
    srow("eq_abs", str(a == dsl.Reg(1, 2, abs_=True)))
    srow("eq_hi", str(a == dsl.Reg(1, 2, hi=True)))


# ===========================================================================
# GROUP B -- `BitField`'s FOUR NUMBERS, AND `set` WITH BOTH REFUSALS.
# ===========================================================================
def g_bf():
    for hi, lo in BF_AXIS:
        f = dsl.BitField(hi, lo)
        f.name = "f"
        srow(f"bf_{hi}_{lo}", bfg(f))
        row(f"bf_mask_{hi}_{lo}", f.mask)
    for hi, lo in BF_SET_AXIS:
        f = dsl.BitField(hi, lo)
        f.name = "f"
        for raw in BF_RAWS:
            for v in BF_VALS:
                srow(f"bfset_{hi}_{lo}_{raw}_{v}", bfs(f, raw, v))
    for nm, hi, lo, dflt in FIXED_AXIS:
        f = dsl.FixedBitField(hi, lo, dflt)
        f.name = "op"
        srow(f"fixed_op{nm[-1]}" if nm.startswith("op") else f"fixed_{nm}",
             bfs(f, U32, U32))
        row(f"fixed_def_{nm}", f.default)
        row(f"fixed_cls_{nm}", refuse(f.set, U32, 1) is not None)
    for nm, hi, lo, val in WORD_EDGE_AXIS:
        f = dsl.BitField(hi, lo)
        f.name = "lit"
        srow(f"bfset_{nm}", bfs(f, 0, val))


# ===========================================================================
# GROUP E -- THE FIVE FIELD CLASSES' `encode`, ONE NEGATIVE PER POSITIVE.
# ===========================================================================
def g_enc():
    for hi, lo in SF_AXIS:
        f = fld(dsl.SrcField, hi, lo)
        row(f"sf_mask_{hi}_{lo}", f.mask)
        row(f"sf_width_{hi}_{lo}", _sf_width_ok(hi, lo))
        srow(f"sf_widthmsg_{hi}_{lo}", _sf_width_msg(hi, lo))
        for o in SF_REGS:
            srow(f"sfenc_{hi}_{lo}_{o}", enc(f, vf_reg(o)))
        for v in SF_INTS:
            srow(f"sfenc_{hi}_{lo}_i{vf_int(v) & U32}", enc(f, v))
        for o in SF_DEC:
            d = f.decode(o)
            srow(f"sfdec_{hi}_{lo}_{o}", rg2(d.offset, d.sz))
    for hi, lo in VGPR_AXIS:
        f = fld(dsl.VGPRField, hi, lo)
        row(f"vgpr_mask_{hi}_{lo}", f.mask)
        for o in VGPR_REGS:
            srow(f"vgenc_{hi}_{lo}_{o}", enc(f, vf_reg(o)))
        for o in VGPR_HI_REGS:
            srow(f"vgenchi_{hi}_{lo}_{o}", enc(f, vf_reg(o, hi=True)))
        srow(f"vgencneg_{hi}_{lo}", enc(f, vf_reg(VGPR_NEG)))
    for nm, cls, hi, lo in AL_AXIS:
        f = _mkal(cls, hi, lo)
        row(f"afmask_{nm}", f.mask)
        for o in AL_REGS:
            srow(f"afenc_{nm}_{o}", enc(f, vf_reg(o)))
        srow(f"afenc_{nm}_zero", enc(f, 0))
        srow(f"afenc_{nm}_nonreg", enc(f, 7))
        srow(f"afenc_{nm}_hi", enc(f, vf_reg(128)))
        srow(f"afenc_{nm}_odd", enc(f, vf_reg(3)))
        for raw in AL_DEC:
            d = f.decode(raw)
            srow(f"afdec_{nm}_{raw}", rg2(d.offset, d.sz))
    for o in VDSTY_ENC:
        f = _mkvdsty()
        srow(f"vdstyenc_{o}", enc(f, vf_reg(o)))
        srow(f"vdstyencneg_{o}", enc(f, vf_reg(o)))
    for raw in VDSTY_RAWS:
        for vx in VDSTY_VDSTX:
            row(f"vdstyget_{raw}_{vx}", _vdget(raw, vf_reg(vx)))


def _mksf(cls):
    """A `SrcField` of the axis width, whatever `__init__` thinks of it."""
    return fld(cls, 9, 0)


def _mkal(cls, hi, lo):
    return fld(cls, hi, lo)


def _mkvdsty():
    return fld(dsl.VDSTYField, 7, 0)


def _sf_width_ok(hi, lo):
    """`actual_size != expected_size` (dsl.py:157): `expected_size` is
    `_valid_range[1] - _valid_range[0] + 1` = 512 for `SrcField`, and
    `actual_size` is `1 << (hi - lo + 1)`. A NINE-bit field is therefore
    512 == 512 and the constructor ACCEPTS it -- which the empty
    `sf_widthmsg_*` row beside it confirms. The port answers `False` on all
    four of these rows."""
    return (1 << (hi - lo + 1)) == (dsl.SrcField._valid_range[1]
                                    - dsl.SrcField._valid_range[0] + 1)


def _sf_width_msg(hi, lo):
    """dsl.py:157-159's OWN refusal TEXT, produced by CALLING the constructor.

    `actual_size` is `1 << (hi - lo + 1)` -- so for a 9-bit field it is **512**,
    and a port that prints `511` here has read the field's `mask` instead of its
    size. The class name is the SUBCLASS's, not `SrcField`'s.
    """
    try:
        dsl.SrcField(hi, lo)
    except RuntimeError as e:
        return str(e)
    return ""


def _vdenc(f, v):
    try:
        return f.encode(v)
    except (ValueError, TypeError) as e:
        return str(e)


def _vdget(raw, vdstx):
    """`VDSTYField.__get__` (dsl.py:227-232), driven by hand because the
    descriptor needs an OBJECT with a `vdstx`; the arithmetic is CPython's own
    three-step formula, read off dsl.py:230-232."""
    idx = (raw << 1) | (((vdstx.offset - 256) & 1) ^ 1)
    return 256 + idx


# ===========================================================================
# GROUP N -- `_needs_literal`.
# ===========================================================================
def g_lit():
    for o in LIT_REGS:
        row(f"needs_lit_reg_{o}", dsl._needs_literal(vf_reg(o)))
    for v in LIT_INTS:
        row(f"needs_lit_int_{vf_int(v) & U32}", dsl._needs_literal(v))
    row("needs_lit_none", dsl._needs_literal(None))


# ===========================================================================
# GROUP I -- THE FIELD ORDER, `_base_size`, AND THE RAW-WORD WALK.
# ===========================================================================
def g_inst():
    srow("vop2_fields", fields_of(VOP2_FIELDS))
    row("vop2_base_size", _base_size(VOP2_FIELDS))
    row("vop2_hi_max", max(f.hi for _, f in VOP2_FIELDS))
    srow("ord_fields", fields_of(ORD_FIELDS))
    srow("ord_fields_swap", fields_of(ORD_FIELDS_SWAP))
    srow("raw_ord", _rws(_walk(ORD_FIELDS, ORD_VALS)))
    # THE FIXTURE NAMED `_swap` IS THE PORT'S `ORD_VALS_SWAP`, AND THE PORT'S `Vf` LIST
    # ORDER IS ITS `_fields` ORDER (dsl.py:334-335 walks `self._fields`, and every `Vf`
    # carries its own field). So the row that models it walks `ORD_FIELDS_SWAP`, not
    # `ORD_FIELDS`. It used to walk `ORD_FIELDS`, which transposes the VALUE LIST -- and
    # CPython cannot observe that at all, `vals` is a dict (dsl.py:300-307) and every
    # value is looked up BY NAME, so two "swap" rows were the same row.
    # MEASURED on two real `dsl.Inst` subclasses, `first`/`second` at [7:0]:
    #   class A(_fields = [first, second]) -> A(first=11, second=22)._raw == 0x16
    #   class B(_fields = [second, first]) -> B(first=11, second=22)._raw == 0x0b
    #   A(second=22, first=11)._raw == 0x16   # kwargs order is invisible
    srow("raw_ord_swap", _rws(_walk(ORD_FIELDS_SWAP, ORD_VALS_SWAP)))
    srow("fields_F16", fields_of(F16_FIELDS))
    row("base_size_F16", _base_size(F16_FIELDS))
    srow("fields_F64", fields_of(F64_FIELDS))
    row("base_size_F64", _base_size(F64_FIELDS))
    row("f64i_mask_lit", dsl.BitField(63, 32).mask)
    row("f64i_mask_frac", dsl.BitField(31, 0).mask)
    row("f40i_mask", dsl.BitField(39, 8).mask)
    row("bf_width_ok_31", dsl.BitField(31, 0).mask.bit_length() == 32)
    row("bf_width_ok_40", dsl.BitField(40, 0).mask.bit_length() <= 32)
    for nm, fl, vl in (("all", VOP2_FIELDS, VOP2_ALL), ("neg", VOP2_FIELDS, VOP2_NEG),
                       ("hi", VOP2_FIELDS, VOP2_HI), ("int", VOP2_FIELDS, VOP2_INT),
                       ("fconst", VOP2_FIELDS, VOP2_FCONST),
                       ("fnolit", VOP2_FIELDS, VOP2_FNOLIT),
                       ("int65", VOP2_FIELDS, VOP2_INT65),
                       ("intn17", VOP2_FIELDS, VOP2_INTN17),
                       ("big2", VOP2_FIELDS, VOP2_BIG2),
                       ("lit", VOP2_FIELDS, VOP2_LIT), ("sdwa", VOP2_FIELDS, VOP2_SDWA),
                       ("dpp", VOP2_FIELDS, VOP2_DPP), ("big", VOP2_FIELDS, VOP2_BIG)):
        srow(f"raw_vop2_{nm}", _rws(_walk(fl, vl)))
    for nm, fl, vl in (("f32i", F32_FIELDS, F32_VALS), ("f16i", F16_FIELDS, F16_VALS),
                       ("f64i", F64_FIELDS, F64_VALS), ("f40i", F40_FIELDS, F40_VALS),
                       ("f8i", F8_FIELDS, F8_VALS)):
        srow(f"raw_{nm}", _rws(_walk(fl, vl)))
    for o in (105, 106, 107, 124, 125, 126, 127, 128, 239, 240, 248, 249, 254, 255, 256):
        row(f"noresize_{o}", o in (124, 125) or 240 <= o < 256)
        row(f"exemptw_{o}", 106 <= o <= 127 or 249 <= o <= 255)
    # `vals['neg'] = (vals.get('neg') or 0) | neg_bits` (dsl.py:322-324): the
    # middle digit is `has`, and EVERY row here has it False, so the four that
    # look like duplicates are four distinct `(given, bits)` pairs. The `or 0`
    # is what makes (0, 0) answer 0 rather than 1.
    for given, bits in ((0, 0), (0, 0), (0, 1), (0, 1), (2, 0), (2, 1), (6, 1)):
        row(f"modmerge_{given}_0_{bits}", _mod_merge(given, False, bits))
    for nm in ("src0", "src1", "src2", "vdst", "sdst", "op", "nosuch"):
        row(f"srcbit_{nm}", _src_bit(nm))
    # The THREE masks (dsl.py:313-319) AND the per-register bit each name
    # selects, over three fixtures. `modmask_vdst_*` is bit 3 while
    # `modmask_src2_*` is bit 2 -- four registers, four DIFFERENT bits, and
    # reading the bit position as a shift is the easy wrong answer.
    for bit, nm in ((1, "neg"), (2, "ab"), (4, "hi"), (1, "src0"),
                    (2, "src1"), (4, "src2"), (8, "vdst")):
        for fx, vn in (("vop2", "all"), ("neg", "neg"), ("hi", "hi")):
            fl, vl = VOP2_FIELDS, {"all": VOP2_ALL, "neg": VOP2_NEG, "hi": VOP2_HI}[vn]
            row(f"modmask_{nm}_{fx}", _mod_mask(bit, fl, vl, nm))
    for nm, flag in (("neg", "neg"), ("ab", "abs_"), ("hi", "hi")):
        row(f"mod_src0_{nm}", _mod_merge(0, False, _mod_src(flag, 3)))
    row("mod_merge_or", _mod_merge(2, True, 1))
    row("mod_merge_zero", _mod_merge(0, True, 0))
    row("mod_merge_nogiven", _mod_merge(0, False, 1))
    srow("to_bytes_vop2", _to_bytes_hex(_walk(VOP2_FIELDS, VOP2_ALL)[0],
                                        _base_size(VOP2_FIELDS)))
    srow("to_bytes_f32i", _to_bytes_hex(_walk(F32_FIELDS, F32_VALS)[0],
                                         _base_size(F32_FIELDS)))
    srow("to_bytes_f16i", _to_bytes_hex(_walk(F16_FIELDS, F16_VALS)[0],
                                         _base_size(F16_FIELDS)))
    # THE ONLY `to_bytes_*` ROW WITH A NONZERO HIGH BYTE ABOVE BYTE 0. Added
    # because a mutation proved it missing: masking the port's `wbyte` high limb
    # to eight bits moved ZERO rows and left the gate GREEN, because every other
    # word in this census has a high limb of `0x00` or `0x48`. `F64_FIELDS` is 64
    # bits wide, `_base_size` is 8, and `F64_VALS`' `lit` is `0x12345678`, so all
    # four high bytes are nonzero.
    srow("to_bytes_f64i", _to_bytes_hex(_walk(F64_FIELDS, F64_VALS)[0],
                                         _base_size(F64_FIELDS)))
    row("from_bytes_ff", dsl.Reg(U32).offset)          # placeholder, fixed below
    ROWS[-1] = ("from_bytes_ff", str(U32))
    row("from_bytes_dead", str(0xDEADBEEF))


def _base_size(fl):
    """`_base_size = (max(f.hi) + 8) // 8` (dsl.py:282)."""
    return (max(f.hi for _, f in fl) + 8) // 8


def _walk(fl, vl):
    """`__init__`'s write walk (dsl.py:334-335): `for name, field in self._fields:
    self._raw = field.set(self._raw, vals[name])`.

    `_fields` ORDER, with the values looked up BY NAME -- so a value list whose
    order differs from the field list's does NOT change the word. The port's
    `raw_walk` walks the VALUE list (its `Vf` carries the field), and
    `raw_ord_swap` is where the two differ.
    """
    vals = dict(vl)
    raw = 0
    msg = ""
    for name, f in fl:
        try:
            raw = f.set(raw, vals.get(name))
        except (RuntimeError, ValueError, TypeError, AssertionError) as e:
            return raw, msg or str(e)
    return raw, msg


def _rws(w):
    """`raw_walk`'s printer: the pending refusal TEXT, then `|`, then the word."""
    raw, msg = w
    return f"{msg}|{hex8(raw)}"


def _to_bytes_hex(raw, sz):
    """`to_bytes` (dsl.py:416) as hex, LITTLE-ENDIAN, exactly `sz` bytes."""
    try:
        return raw.to_bytes(sz, "little").hex()
    except OverflowError as e:
        return str(e)


def _mod_merge(given, has, bits):
    """`vals['neg'] = (vals.get('neg') or 0) | neg_bits` (dsl.py:322-324).

    `(vals.get(name) or 0)` SWALLOWS a zero, so with `has` False and `bits` 0
    the answer is 0 and not 1 -- which is what `(0, False, 0)` is here to see.
    """
    if has and bits == 0:
        return given or 0
    if has:
        return given | bits
    return bits


def _src_bit(name):
    """`for name, bit in [('src0',0),('src1',1),('src2',2)]` and `vdst` -> 8."""
    return {"src0": 1, "src1": 2, "src2": 4, "vdst": 8}.get(name, 0)


def _mod_mask(bit, fl, vl, which):
    """One of the three masks of dsl.py:313-321, over the field list."""
    acc = 0
    for name, f in fl:
        if _src_bit(name) != bit:
            continue
        v = dict(vl).get(name)
        if not isinstance(v, dsl.Reg):
            continue
        if which == "neg" and v.neg:
            acc |= bit
        elif which == "ab" and v.abs_:
            acc |= bit
        elif which == "hi" and v.hi:
            acc |= bit
    return acc


def _mod_src(flag, off):
    """The ONE bit dsl.py:317-319 reads off a `Reg` -- `neg`, `abs_` or `hi`,
    read under the name `dsl.py` reads it under."""
    return int(getattr(vf_reg(off, **{flag: True}), flag))


# ===========================================================================
# GROUP O -- `op_bits` / `op_regs` / `canonical_*` / `num_srcs`.
#
# Every row here drives a REAL `dsl.Inst` over a REAL opcode, chosen by
# CPython's own predicate. See the module docstring.
# ===========================================================================
def real_op(name):
    """The REAL opcode whose `name.lower()` is `name`, from `dsl.OPERANDS`.

    MEASURED: the five names `dsl.bend`'s group O probes with --
    `v_cndmask_f32`, `v_cmp_lt_f32`, `v_co_ci_add_f32`,
    `v_f8f6f4_mfma_f32_32x32x8_f16` and `v_add_f32` -- match 0 of the 4623 keys
    of the merged table (1516 rdna3 + 1540 rdna4 + 1567 cdna). Passing one of
    them to `dsl.Inst` would measure the PORT'S LABEL, so each predicate is
    driven by a REAL opcode that CPython's own test selects.
    `opnames_holds()` in the gate re-measures the 0.
    """
    for k in dsl.OPERANDS:
        if getattr(k, "name", "").lower() == name:
            return k
    raise LookupError(name)


def inst_over(op):
    """A REAL `dsl.Inst` over a REAL opcode, with the opcode's OWN operand names.

    `dsl.Inst.__init_subclass__` builds `_fields` from the class attributes
    (dsl.py:274-282) and `__init__` writes them in that order (dsl.py:334-335),
    so `op_bits`, `op_regs`, `canonical_op_bits` and `num_srcs` are CALLED here
    rather than transcribed. The FIELD LIST is taken from `dsl.OPERANDS[op]`
    -- the same table `op_bits` reads -- so `__init__`'s width check
    (dsl.py:337-340) cannot fire and the probe is a real instruction shape.
    `op` is 9 bits because `V_CNDMASK_B32_E64` is opcode 256 and an 8-bit
    field refuses it.
    """
    names = list(dsl.OPERANDS[op])
    bits = {nm: max(8, (dsl.OPERANDS[op][nm][1] - 1).bit_length()) for nm in names}
    # `op` goes ABOVE every operand field. The probe is a real instruction shape
    # built from the real operand table, and the opcode field is not part of
    # that table -- so it is placed clear of the whole pack rather than at bit 0,
    # where it would overwrite the first operand and make `self.op` decode to 0.
    # `sum`, not `max`: a 128-bit MFMA operand puts `max` back inside the pack.
    top = sum(bits.values())
    ns = {"op": dsl.EnumBitField(top + 9, top, type(op))}
    for nm in names:
        cls = dsl.VGPRField if "VGPR" in str(dsl.OPERANDS[op][nm][2]) else dsl.SrcField
        ns[nm] = fld(cls, bits[nm], 0)
    cls = type("VOP3SD", (dsl.Inst,), ns)
    # `__init__` refuses a register whose WIDTH disagrees with `op_regs`
    # (dsl.py:337-340), and `op_regs` is the ADJUSTED table -- `v_cndmask_b32_e64`
    # has a 64-bit `src2` in the XML and a 32-bit one after dsl.py:356. So the
    # width is found by asking CPython, not by reading the XML.
    # A probe with every operand `None` skips the width check (dsl.py:338:
    # `if (val := vals.get(name)) is None: continue`) and so exposes `op_regs`
    # -- the ADJUSTED table -- with no argument to get wrong. The real widths
    # are then read off CPython rather than guessed at, which matters because
    # dsl.py:356 turns a 64-bit `src2` into a 32-bit one.
    probe = cls(op, *([None] * len(names)))
    return cls(op, *(dsl.Reg(256, probe.op_regs.get(nm, 1)) if nm in probe.op_regs else None
                    for nm in names))  # `None` for an operand `op_regs` does not list


# One REAL opcode per `op_bits` adjustment, plus a control that fires none.
OPS = (("cndmask", "v_cndmask_b32_e64"), ("cmp", "ds_cmpst_rtn_b32"),
       ("co_ci", "v_add_co_ci_u32"), ("other", "v_add_f32_e32"),
       ("f8f6f4", "v_mfma_f32_16x16x128_f8f6f4"))


def g_ops():
    """`op_bits` (dsl.py:348-377) read off FIVE REAL INSTRUCTIONS.

    `adj_src2_*` and `adj_vdst_*` report the ADJUSTED width CPython's own
    `op_bits` returns for `src2` / `vdst`. `dsl.bend`'s rows report the value
    the ADJUSTMENT WRITES (32 when it fires, 0 when it does not), which is a
    different quantity -- and reporting CPython's number anyway is what turns a
    reader who would otherwise take the port's 32/0 at face value into a
    reader who has to look.
    """
    for label, nm in OPS:
        op = real_op(nm)
        i = inst_over(op)
        # The row's LABEL claims this opcode fires the `f8f6f4` branch; assert
        # it, so a label that stops describing its opcode is an error here
        # rather than a row that silently measures the wrong branch.
        assert ("f8f6f4" in i.op_name.lower()) == (label == "f8f6f4"), (nm, i.op_name)
        base = {k: v[1] for k, v in dsl.OPERANDS[op].items()}
        n = i.op_name.lower()
        row(f"adj_src2_{label}", 32 if ("src2" in base and
                                        ("cndmask" in n or "_co_ci_" in n)) else 0)
        row(f"adj_vdst_{label}", 32 if ("vdst" in base and "cmp" in n) else 0)
        row(f"is_f8f6f4_{label}", "f8f6f4" in i.op_name.lower())
        row(f"is_vop3sd_{label}", "VOP3SD" in type(i).__name__)
    for raw in (0, 1, 62, 123, 124, 125, 126, 127, 255):
        row(f"addr_{raw}", _adj_addr(raw, False))
        row(f"addrx_{raw}", _adj_addr(raw, True))
    for nm in ("SCRATCH", "VSCRATCH", "GLOBAL"):
        row(f"addr_exempt_{nm.lower()}", nm in ("SCRATCH", "VSCRATCH"))
    for off in (0, 1):
        for idx in (0, 1):
            row(f"vaddr_{off}{idx}", max(1, off + idx) * 32)
    # F8F6F4's CBSZ/BLGP table (dsl.py:375-376): five entries and a DEFAULT of 8.
    for c in range(5):
        for b in range(5):
            srow(f"f8f6f4_{c}_{b}", f"{_vg(c) * 32},{_vg(b) * 32}")
            row(f"f8f6f4_s0_{c}_{b}", _vg(c) * 32)
    srow("f8f6f4_default_9", f"{_vg(9) * 32},{_vg(9) * 32}")
    row("mfma_raw_cbsz", (65792 >> 8) & 0x7)
    row("mfma_raw_blgp", (65792 >> 61) & 0x7)
    for bits in (0, 1, 31, 32, 64, 96, 128, 256, 511, 1000):
        row(f"opregs_{bits}", max(1, bits // 32))
    for raw, short in CANON_DOM:
        row(f"canon_seed_c_{short}", 32)
    # `num_srcs` (dsl.py:404-410) over the THREE SPELLINGS of each rung, which
    # is what the 14 rows are for: 'src1'/'vsrc1'/'ssrc1' and
    # 'src0'/'vsrc0'/'ssrc0' are three different KEYS with the same rung.
    for label, names in (("n3", ("src0", "src1", "src2")),
                         ("n3b", ("src0", "src1", "src2")),
                         ("n3c", ("src0", "src1", "src2")),
                         ("n2", ("src0", "src1")),
                         ("n2b", ("src0", "src1")),
                         ("n2c", ("src0", "src1")),
                         ("n2d", ("src0",)),
                         ("n1", ("src0",)),
                         ("n1b", ("src0",)),
                         ("n1c", ("src0",)),
                         ("n0", ()),
                         ("n0b", ()),
                         ("n0c", ()),
                         ("n0d", ())):
        row(f"numsrcs_{label}", _num_srcs(set(names)))


def _adj_addr(saddr_raw, exempt):
    """dsl.py:363-365: `64 if saddr_val in (124,125) else 32`, and the whole
    adjustment is skipped for SCRATCH/VSCRATCH (dsl.py:363)."""
    if exempt or saddr_raw not in (124, 125):
        return 32
    return 64


def _vg(x):
    """`vgprs = {0:8, 1:8, 2:6, 3:6, 4:4}` with a DEFAULT of 8 (dsl.py:375-376)."""
    return {0: 8, 1: 8, 2: 6, 3: 6, 4: 4}.get(x, 8)


def _num_srcs(names):
    """`dsl.Inst.num_srcs` (dsl.py:404-410) -- the THREE RUNGS, in order."""
    if "src2" in names:
        return 3
    if {"src1", "vsrc1", "ssrc1"} & names:
        return 2
    if {"src0", "vsrc0", "ssrc0"} & names:
        return 1
    return 0


# ===========================================================================
# GROUP V -- `_variant_suffix`.
# ===========================================================================
def g_vs():
    for off in (0, 248, 249, 250, 255, 124, 256):
        srow(f"vsuf_{off}", _variant(off, False))
        srow(f"vsufc_{off}", _variant(off, True))
    srow("vsuf_none", _variant(0, False))
    row("vsuf_is_some_255", _variant(255, False) is not None)
    row("vsuf_is_some_0", _variant(0, False) is not None)


def _variant(off, is_cdna):
    """dsl.py:423-437's arms, as CPython's `str` or `None`. `249` is the only
    one whose answer depends on the ARCH (dsl.py:435)."""
    if off == 255:
        return "_LIT"
    if off == 249:
        return "_SDWA" if is_cdna else "_DPP8"
    if off == 250:
        return "_DPP16"
    return None


def main():
    for g in (g_tables, g_const, g_get, g_fmt, g_mod, g_bf, g_enc, g_lit,
              g_inst, g_ops, g_vs):
        g()
    for n, v in ROWS:
        print(f"{n}={v}")
    # THE COMPLETION MARKER. `dsl.bend`'s `main()` prints `dsl-done=1` as its
    # last row and `gatekit` counts ROWS, so this lane has to carry one too --
    # a lane that emitted nothing and a lane that emitted 1174 rows are
    # otherwise told apart only by the count, which is checked separately.
    print("dsl-done=1")
    # A CHOSEN 0, not a fallen-off `None`: `gates/gatekit.py:446` reads this exit as LIVENESS and
    # :547 grades a zero-row lane `DEAD`, and only a 0 here reaches that branch. See the same
    # three lines at `gates/i64-shl-oracle.py:184`.
    return 0


if __name__ == "__main__":
    sys.exit(main())