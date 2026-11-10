# gates/dsl-gate.bend -- THE GATE DRIVER for `tinybendygrad/renderer/amd/dsl.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/renderer/amd/dsl.bend as P
import ./../tinybendygrad/helpers.bend as H

def vdsty_get(raw: U32, vdstx_off: U32) -> U32:
  U32.add(P.VDSTY_LO(), U32.or(U32.shln(raw, P.VDSTY_SHIFT()), P.vdsty_low(vdstx_off)))
# `(vdstx.offset - 256) & 1) ^ 1` -- the low bit comes from Vdstx and is INVERTED
# --- R  Reg.__getitem__ -- index, slice, and BOTH refusals -------------
def Fld.srsc(nm: String, hi: U32, lo: U32) -> P.Fld: P.Fld.of(nm, hi, lo, 0, P.K_SRSC(), 0, 0, P.ALIGN_SRSC())
def src_width_ok(+f: P.Fld) -> Bool: U32.is_eq(U32.add(P.bf_mask(f), 1), P.Fld.valid_n(f))
# the parenthesised number is dsl.py:158's `actual_size`, which is `1 << bits` -- 512 -- and not
# the mask, 511. the port printed the mask. CPython never prints this string for an SRC field,
# because it never raises on one, so the message rows stay a carve-out while the decision rows
# become exact: the port was deciding "refuse" WHERE CPYTHON decides "accept", and a string
# that is never printed hides which one it took.
def rg2(off: U32, sz: U32) -> String: String.concat([P.u32_text(off), ",", P.u32_text(sz)])
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
# int 64 is the last inlineable positive (:165) and -16 the last inlineable
# negative (:166) -- one row either side of each, because the boundary is where
# an off-by-one in the range test shows and nowhere else.
def src_width_msg(+f: P.Fld) -> String:
  String.concat([P.Fld.name(f), ": field size ", U32.show(P.bf_bits(f)), " bits (",
                 U32.show(U32.add(P.bf_mask(f), 1)), ") doesn't match range (", U32.show(P.Fld.rlo(f)),
                 ", ", U32.show(P.Fld.rhi(f)), ") (", U32.show(P.Fld.valid_n(f)), ")"])
# ===========================================================================
# THE REMAINING FIELD CLASSES. `SrcField` is done; these three are the rest.
# ===========================================================================
# `VGPRField.encode` (:190-198). `SrcField.encode` first, and then the 8-bit
# `.h` opsel bit: `if val.hi and (self.hi - self.lo + 1) == 8`. TWO conditions
# and either alone is not enough -- a `.h` in a 9-bit field adds no bit, and a
# `.h` at index >= 128 REFUSES (:196) because 8 bits cannot hold both.
# --- c the register constants and the space boundaries ----------------
def Fld.align2(nm: String, hi: U32, lo: U32, al: U32) -> P.Fld: P.Fld.of(nm, hi, lo, 0, P.K_ALIGN(), 0, 0, al)
# THE FLOAT ENCODING PATH. :164 is `_FLOAT_ENC.get(val, 255)`; the first fixture
# supplies a KNOWN float's offset and the second supplies the 255 a float absent
# from `_FLOAT_ENC` gets -- the negative half of the same `.get`.
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", P.u32_text(v)]))
# TWO EQUALITIES plus the refusal one, because the two fields of `Res` answer two
# different questions: `eqr` compares the VALUE, `eqrs` the rendered STRING and
# `eqrm` the refusal TEXT. A renderer gate is STRINGS before booleans --
# `String.concat` drops a literal silently, so a boolean about a string can be
# true while the string is wrong -- and `eqrs` is the one that catches that.
# THE ORDER FIXTURE. Two fields at the SAME bits with different names: `set` is
# a masked overwrite, so the LAST write wins and the field ORDER decides the
# word. Swap the two and every value-identical gate row on this file still
# passes, which is exactly why this fixture exists -- a transposed pair in
# `_fields` is otherwise invisible.
def g_enc() -> IO(Unit):
  do IO<Unit>:
    urow("sf_mask_8_0", P.bf_mask(P.Fld.src("s0", 8, 0)))
    P.row("sf_width_8_0", src_width_ok(P.Fld.src("s0", 8, 0)))
    srow("sf_widthmsg_8_0", src_width_msg(P.Fld.src("s0", 8, 0)))
    urow("sfenc_8_0_0", P.Res.v(P.src_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_1", P.Res.v(P.src_encode(P.Ov.reg(1, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_63", P.Res.v(P.src_encode(P.Ov.reg(63, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_105", P.Res.v(P.src_encode(P.Ov.reg(105, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_106", P.Res.v(P.src_encode(P.Ov.reg(106, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_127", P.Res.v(P.src_encode(P.Ov.reg(127, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_128", P.Res.v(P.src_encode(P.Ov.reg(128, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_255", P.Res.v(P.src_encode(P.Ov.reg(255, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_256", P.Res.v(P.src_encode(P.Ov.reg(256, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_257", P.Res.v(P.src_encode(P.Ov.reg(257, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_511", P.Res.v(P.src_encode(P.Ov.reg(511, 1, False{}, False{}, False{}), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i0", P.Res.v(P.src_encode(P.Ov.int(0), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i1", P.Res.v(P.src_encode(P.Ov.int(1), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i63", P.Res.v(P.src_encode(P.Ov.int(63), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i64", P.Res.v(P.src_encode(P.Ov.int(64), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i65", P.Res.v(P.src_encode(P.Ov.int(65), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i4294967295", P.Res.v(P.src_encode(P.Ov.int(4294967295), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i4294967280", P.Res.v(P.src_encode(P.Ov.int(4294967280), P.Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i4294967279", P.Res.v(P.src_encode(P.Ov.int(4294967279), P.Fld.src("s0", 8, 0))))
    srow("sfdec_8_0_0", rg2(0, 1))
    srow("sfdec_8_0_1", rg2(1, 1))
    srow("sfdec_8_0_105", rg2(105, 1))
    srow("sfdec_8_0_127", rg2(127, 1))
    srow("sfdec_8_0_128", rg2(128, 1))
    srow("sfdec_8_0_255", rg2(255, 1))
    srow("sfdec_8_0_256", rg2(256, 1))
    srow("sfdec_8_0_257", rg2(257, 1))
    srow("sfdec_8_0_511", rg2(511, 1))
    urow("sf_mask_17_9", P.bf_mask(P.Fld.src("s0", 17, 9)))
    P.row("sf_width_17_9", src_width_ok(P.Fld.src("s0", 17, 9)))
    srow("sf_widthmsg_17_9", src_width_msg(P.Fld.src("s0", 17, 9)))
    urow("sfenc_17_9_0", P.Res.v(P.src_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_1", P.Res.v(P.src_encode(P.Ov.reg(1, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_63", P.Res.v(P.src_encode(P.Ov.reg(63, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_105", P.Res.v(P.src_encode(P.Ov.reg(105, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_106", P.Res.v(P.src_encode(P.Ov.reg(106, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_127", P.Res.v(P.src_encode(P.Ov.reg(127, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_128", P.Res.v(P.src_encode(P.Ov.reg(128, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_255", P.Res.v(P.src_encode(P.Ov.reg(255, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_256", P.Res.v(P.src_encode(P.Ov.reg(256, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_257", P.Res.v(P.src_encode(P.Ov.reg(257, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_511", P.Res.v(P.src_encode(P.Ov.reg(511, 1, False{}, False{}, False{}), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i0", P.Res.v(P.src_encode(P.Ov.int(0), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i1", P.Res.v(P.src_encode(P.Ov.int(1), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i63", P.Res.v(P.src_encode(P.Ov.int(63), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i64", P.Res.v(P.src_encode(P.Ov.int(64), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i65", P.Res.v(P.src_encode(P.Ov.int(65), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i4294967295", P.Res.v(P.src_encode(P.Ov.int(4294967295), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i4294967280", P.Res.v(P.src_encode(P.Ov.int(4294967280), P.Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i4294967279", P.Res.v(P.src_encode(P.Ov.int(4294967279), P.Fld.src("s0", 17, 9))))
    srow("sfdec_17_9_0", rg2(0, 1))
    srow("sfdec_17_9_1", rg2(1, 1))
    srow("sfdec_17_9_105", rg2(105, 1))
    srow("sfdec_17_9_127", rg2(127, 1))
    srow("sfdec_17_9_128", rg2(128, 1))
    srow("sfdec_17_9_255", rg2(255, 1))
    srow("sfdec_17_9_256", rg2(256, 1))
    srow("sfdec_17_9_257", rg2(257, 1))
    srow("sfdec_17_9_511", rg2(511, 1))
    urow("sf_mask_25_17", P.bf_mask(P.Fld.src("s0", 25, 17)))
    P.row("sf_width_25_17", src_width_ok(P.Fld.src("s0", 25, 17)))
    srow("sf_widthmsg_25_17", src_width_msg(P.Fld.src("s0", 25, 17)))
    urow("sfenc_25_17_0", P.Res.v(P.src_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_1", P.Res.v(P.src_encode(P.Ov.reg(1, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_63", P.Res.v(P.src_encode(P.Ov.reg(63, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_105", P.Res.v(P.src_encode(P.Ov.reg(105, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_106", P.Res.v(P.src_encode(P.Ov.reg(106, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_127", P.Res.v(P.src_encode(P.Ov.reg(127, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_128", P.Res.v(P.src_encode(P.Ov.reg(128, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_255", P.Res.v(P.src_encode(P.Ov.reg(255, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_256", P.Res.v(P.src_encode(P.Ov.reg(256, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_257", P.Res.v(P.src_encode(P.Ov.reg(257, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_511", P.Res.v(P.src_encode(P.Ov.reg(511, 1, False{}, False{}, False{}), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i0", P.Res.v(P.src_encode(P.Ov.int(0), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i1", P.Res.v(P.src_encode(P.Ov.int(1), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i63", P.Res.v(P.src_encode(P.Ov.int(63), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i64", P.Res.v(P.src_encode(P.Ov.int(64), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i65", P.Res.v(P.src_encode(P.Ov.int(65), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i4294967295", P.Res.v(P.src_encode(P.Ov.int(4294967295), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i4294967280", P.Res.v(P.src_encode(P.Ov.int(4294967280), P.Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i4294967279", P.Res.v(P.src_encode(P.Ov.int(4294967279), P.Fld.src("s0", 25, 17))))
    srow("sfdec_25_17_0", rg2(0, 1))
    srow("sfdec_25_17_1", rg2(1, 1))
    srow("sfdec_25_17_105", rg2(105, 1))
    srow("sfdec_25_17_127", rg2(127, 1))
    srow("sfdec_25_17_128", rg2(128, 1))
    srow("sfdec_25_17_255", rg2(255, 1))
    srow("sfdec_25_17_256", rg2(256, 1))
    srow("sfdec_25_17_257", rg2(257, 1))
    srow("sfdec_25_17_511", rg2(511, 1))
    urow("sf_mask_9_1", P.bf_mask(P.Fld.src("s0", 9, 1)))
    P.row("sf_width_9_1", src_width_ok(P.Fld.src("s0", 9, 1)))
    srow("sf_widthmsg_9_1", src_width_msg(P.Fld.src("s0", 9, 1)))
    urow("sfenc_9_1_0", P.Res.v(P.src_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_1", P.Res.v(P.src_encode(P.Ov.reg(1, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_63", P.Res.v(P.src_encode(P.Ov.reg(63, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_105", P.Res.v(P.src_encode(P.Ov.reg(105, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_106", P.Res.v(P.src_encode(P.Ov.reg(106, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_127", P.Res.v(P.src_encode(P.Ov.reg(127, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_128", P.Res.v(P.src_encode(P.Ov.reg(128, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_255", P.Res.v(P.src_encode(P.Ov.reg(255, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_256", P.Res.v(P.src_encode(P.Ov.reg(256, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_257", P.Res.v(P.src_encode(P.Ov.reg(257, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_511", P.Res.v(P.src_encode(P.Ov.reg(511, 1, False{}, False{}, False{}), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i0", P.Res.v(P.src_encode(P.Ov.int(0), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i1", P.Res.v(P.src_encode(P.Ov.int(1), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i63", P.Res.v(P.src_encode(P.Ov.int(63), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i64", P.Res.v(P.src_encode(P.Ov.int(64), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i65", P.Res.v(P.src_encode(P.Ov.int(65), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i4294967295", P.Res.v(P.src_encode(P.Ov.int(4294967295), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i4294967280", P.Res.v(P.src_encode(P.Ov.int(4294967280), P.Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i4294967279", P.Res.v(P.src_encode(P.Ov.int(4294967279), P.Fld.src("s0", 9, 1))))
    srow("sfdec_9_1_0", rg2(0, 1))
    srow("sfdec_9_1_1", rg2(1, 1))
    srow("sfdec_9_1_105", rg2(105, 1))
    srow("sfdec_9_1_127", rg2(127, 1))
    srow("sfdec_9_1_128", rg2(128, 1))
    srow("sfdec_9_1_255", rg2(255, 1))
    srow("sfdec_9_1_256", rg2(256, 1))
    srow("sfdec_9_1_257", rg2(257, 1))
    srow("sfdec_9_1_511", rg2(511, 1))
    urow("vgpr_mask_7_0", P.bf_mask(P.Fld.vgpr("vdst", 7, 0)))
    urow("vgenc_7_0_256", P.Res.v(P.vgpr_encode(P.Ov.reg(256, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 7, 0))))
    urow("vgenc_7_0_257", P.Res.v(P.vgpr_encode(P.Ov.reg(257, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 7, 0))))
    urow("vgenc_7_0_383", P.Res.v(P.vgpr_encode(P.Ov.reg(383, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 7, 0))))
    urow("vgenc_7_0_384", P.Res.v(P.vgpr_encode(P.Ov.reg(384, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 7, 0))))
    urow("vgenc_7_0_511", P.Res.v(P.vgpr_encode(P.Ov.reg(511, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 7, 0))))
    srow("vgenchi_7_0_256", P.enc_text(P.vgpr_encode(P.Ov.reg(256, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 7, 0))))
    srow("vgenchi_7_0_300", P.enc_text(P.vgpr_encode(P.Ov.reg(300, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 7, 0))))
    srow("vgenchi_7_0_384", P.enc_text(P.vgpr_encode(P.Ov.reg(384, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 7, 0))))
    srow("vgenchi_7_0_511", P.enc_text(P.vgpr_encode(P.Ov.reg(511, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 7, 0))))
    srow("vgencneg_7_0", P.Res.msg(P.vgpr_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 7, 0))))
    urow("vgpr_mask_15_8", P.bf_mask(P.Fld.vgpr("vdst", 15, 8)))
    urow("vgenc_15_8_256", P.Res.v(P.vgpr_encode(P.Ov.reg(256, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 15, 8))))
    urow("vgenc_15_8_257", P.Res.v(P.vgpr_encode(P.Ov.reg(257, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 15, 8))))
    urow("vgenc_15_8_383", P.Res.v(P.vgpr_encode(P.Ov.reg(383, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 15, 8))))
    urow("vgenc_15_8_384", P.Res.v(P.vgpr_encode(P.Ov.reg(384, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 15, 8))))
    urow("vgenc_15_8_511", P.Res.v(P.vgpr_encode(P.Ov.reg(511, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 15, 8))))
    srow("vgenchi_15_8_256", P.enc_text(P.vgpr_encode(P.Ov.reg(256, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 15, 8))))
    srow("vgenchi_15_8_300", P.enc_text(P.vgpr_encode(P.Ov.reg(300, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 15, 8))))
    srow("vgenchi_15_8_384", P.enc_text(P.vgpr_encode(P.Ov.reg(384, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 15, 8))))
    srow("vgenchi_15_8_511", P.enc_text(P.vgpr_encode(P.Ov.reg(511, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 15, 8))))
    srow("vgencneg_15_8", P.Res.msg(P.vgpr_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 15, 8))))
    urow("vgpr_mask_8_1", P.bf_mask(P.Fld.vgpr("vdst", 8, 1)))
    urow("vgenc_8_1_256", P.Res.v(P.vgpr_encode(P.Ov.reg(256, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 8, 1))))
    urow("vgenc_8_1_257", P.Res.v(P.vgpr_encode(P.Ov.reg(257, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 8, 1))))
    urow("vgenc_8_1_383", P.Res.v(P.vgpr_encode(P.Ov.reg(383, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 8, 1))))
    urow("vgenc_8_1_384", P.Res.v(P.vgpr_encode(P.Ov.reg(384, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 8, 1))))
    urow("vgenc_8_1_511", P.Res.v(P.vgpr_encode(P.Ov.reg(511, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 8, 1))))
    srow("vgenchi_8_1_256", P.enc_text(P.vgpr_encode(P.Ov.reg(256, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 8, 1))))
    srow("vgenchi_8_1_300", P.enc_text(P.vgpr_encode(P.Ov.reg(300, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 8, 1))))
    srow("vgenchi_8_1_384", P.enc_text(P.vgpr_encode(P.Ov.reg(384, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 8, 1))))
    srow("vgenchi_8_1_511", P.enc_text(P.vgpr_encode(P.Ov.reg(511, 1, False{}, False{}, True{}), P.Fld.vgpr("vdst", 8, 1))))
    srow("vgencneg_8_1", P.Res.msg(P.vgpr_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), P.Fld.vgpr("vdst", 8, 1))))
    srow("afmask_ab", P.u32_text(P.bf_mask(Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_0", P.Res.v(P.al_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_2", P.Res.v(P.al_encode(P.Ov.reg(2, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_4", P.Res.v(P.al_encode(P.Ov.reg(4, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_8", P.Res.v(P.al_encode(P.Ov.reg(8, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_100", P.Res.v(P.al_encode(P.Ov.reg(100, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_126", P.Res.v(P.al_encode(P.Ov.reg(126, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_127", P.Res.v(P.al_encode(P.Ov.reg(127, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    srow("afenc_ab_zero", P.enc_text(P.al_encode(P.Ov.int(0), Fld.align2("s", 7, 0, 2))))
    srow("afenc_ab_nonreg", P.Res.msg(P.al_encode(P.Ov.int(7), Fld.align2("s", 7, 0, 2))))
    srow("afenc_ab_hi", P.Res.msg(P.al_encode(P.Ov.reg(128, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    srow("afenc_ab_odd", P.Res.msg(P.al_encode(P.Ov.reg(3, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    srow("afdec_ab_0", rg2(U32.shln(0, U32.to_nat(P.al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_1", rg2(U32.shln(1, U32.to_nat(P.al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_2", rg2(U32.shln(2, U32.to_nat(P.al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_15", rg2(U32.shln(15, U32.to_nat(P.al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_31", rg2(U32.shln(31, U32.to_nat(P.al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_32", rg2(U32.shln(32, U32.to_nat(P.al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_63", rg2(U32.shln(63, U32.to_nat(P.al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afmask_sb", P.u32_text(P.bf_mask(P.Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_0", P.Res.v(P.al_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_2", P.Res.v(P.al_encode(P.Ov.reg(2, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_4", P.Res.v(P.al_encode(P.Ov.reg(4, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_8", P.Res.v(P.al_encode(P.Ov.reg(8, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_100", P.Res.v(P.al_encode(P.Ov.reg(100, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_126", P.Res.v(P.al_encode(P.Ov.reg(126, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_127", P.Res.v(P.al_encode(P.Ov.reg(127, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    srow("afenc_sb_zero", P.enc_text(P.al_encode(P.Ov.int(0), P.Fld.sbase("sdst", 7, 4))))
    srow("afenc_sb_nonreg", P.Res.msg(P.al_encode(P.Ov.int(7), P.Fld.sbase("sdst", 7, 4))))
    srow("afenc_sb_hi", P.Res.msg(P.al_encode(P.Ov.reg(128, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    srow("afenc_sb_odd", P.Res.msg(P.al_encode(P.Ov.reg(3, 1, False{}, False{}, False{}), P.Fld.sbase("sdst", 7, 4))))
    srow("afdec_sb_0", rg2(U32.shln(0, U32.to_nat(P.al_shift_of(P.Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_1", rg2(U32.shln(1, U32.to_nat(P.al_shift_of(P.Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_2", rg2(U32.shln(2, U32.to_nat(P.al_shift_of(P.Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_15", rg2(U32.shln(15, U32.to_nat(P.al_shift_of(P.Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_31", rg2(U32.shln(31, U32.to_nat(P.al_shift_of(P.Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_32", rg2(U32.shln(32, U32.to_nat(P.al_shift_of(P.Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_63", rg2(U32.shln(63, U32.to_nat(P.al_shift_of(P.Fld.sbase("sdst", 7, 4)))), 1))
    srow("afmask_sr", P.u32_text(P.bf_mask(Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_0", P.Res.v(P.al_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_2", P.Res.v(P.al_encode(P.Ov.reg(2, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_4", P.Res.v(P.al_encode(P.Ov.reg(4, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_8", P.Res.v(P.al_encode(P.Ov.reg(8, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_100", P.Res.v(P.al_encode(P.Ov.reg(100, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_126", P.Res.v(P.al_encode(P.Ov.reg(126, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_127", P.Res.v(P.al_encode(P.Ov.reg(127, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    srow("afenc_sr_zero", P.enc_text(P.al_encode(P.Ov.int(0), Fld.srsc("rsrc", 6, 0))))
    srow("afenc_sr_nonreg", P.Res.msg(P.al_encode(P.Ov.int(7), Fld.srsc("rsrc", 6, 0))))
    srow("afenc_sr_hi", P.Res.msg(P.al_encode(P.Ov.reg(128, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    srow("afenc_sr_odd", P.Res.msg(P.al_encode(P.Ov.reg(3, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    srow("afdec_sr_0", rg2(U32.shln(0, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_1", rg2(U32.shln(1, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_2", rg2(U32.shln(2, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_15", rg2(U32.shln(15, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_31", rg2(U32.shln(31, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_32", rg2(U32.shln(32, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_63", rg2(U32.shln(63, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afmask_sr2", P.u32_text(P.bf_mask(Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_0", P.Res.v(P.al_encode(P.Ov.reg(0, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_2", P.Res.v(P.al_encode(P.Ov.reg(2, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_4", P.Res.v(P.al_encode(P.Ov.reg(4, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_8", P.Res.v(P.al_encode(P.Ov.reg(8, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_100", P.Res.v(P.al_encode(P.Ov.reg(100, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_126", P.Res.v(P.al_encode(P.Ov.reg(126, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_127", P.Res.v(P.al_encode(P.Ov.reg(127, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    srow("afenc_sr2_zero", P.enc_text(P.al_encode(P.Ov.int(0), Fld.srsc("rsrc", 5, 0))))
    srow("afenc_sr2_nonreg", P.Res.msg(P.al_encode(P.Ov.int(7), Fld.srsc("rsrc", 5, 0))))
    srow("afenc_sr2_hi", P.Res.msg(P.al_encode(P.Ov.reg(128, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    srow("afenc_sr2_odd", P.Res.msg(P.al_encode(P.Ov.reg(3, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    srow("afdec_sr2_0", rg2(U32.shln(0, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_1", rg2(U32.shln(1, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_2", rg2(U32.shln(2, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_15", rg2(U32.shln(15, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_31", rg2(U32.shln(31, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_32", rg2(U32.shln(32, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_63", rg2(U32.shln(63, U32.to_nat(P.al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("vdstyenc_256", P.enc_text(P.vdsty_encode(P.Ov.reg(256, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_256", P.enc_text(P.vdsty_encode(P.Ov.reg(256, 1, False{}, False{}, False{}))))
    srow("vdstyenc_257", P.enc_text(P.vdsty_encode(P.Ov.reg(257, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_257", P.enc_text(P.vdsty_encode(P.Ov.reg(257, 1, False{}, False{}, False{}))))
    srow("vdstyenc_258", P.enc_text(P.vdsty_encode(P.Ov.reg(258, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_258", P.enc_text(P.vdsty_encode(P.Ov.reg(258, 1, False{}, False{}, False{}))))
    srow("vdstyenc_259", P.enc_text(P.vdsty_encode(P.Ov.reg(259, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_259", P.enc_text(P.vdsty_encode(P.Ov.reg(259, 1, False{}, False{}, False{}))))
    srow("vdstyenc_510", P.enc_text(P.vdsty_encode(P.Ov.reg(510, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_510", P.enc_text(P.vdsty_encode(P.Ov.reg(510, 1, False{}, False{}, False{}))))
    srow("vdstyenc_511", P.enc_text(P.vdsty_encode(P.Ov.reg(511, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_511", P.enc_text(P.vdsty_encode(P.Ov.reg(511, 1, False{}, False{}, False{}))))
    srow("vdstyenc_128", P.enc_text(P.vdsty_encode(P.Ov.reg(128, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_128", P.enc_text(P.vdsty_encode(P.Ov.reg(128, 1, False{}, False{}, False{}))))
    srow("vdstyenc_255", P.enc_text(P.vdsty_encode(P.Ov.reg(255, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_255", P.enc_text(P.vdsty_encode(P.Ov.reg(255, 1, False{}, False{}, False{}))))
    srow("vdstyenc_0", P.enc_text(P.vdsty_encode(P.Ov.reg(0, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_0", P.enc_text(P.vdsty_encode(P.Ov.reg(0, 1, False{}, False{}, False{}))))
    srow("vdstyget_0_256", P.u32_text(vdsty_get(0, 256)))
    srow("vdstyget_0_257", P.u32_text(vdsty_get(0, 257)))
    srow("vdstyget_0_258", P.u32_text(vdsty_get(0, 258)))
    srow("vdstyget_0_259", P.u32_text(vdsty_get(0, 259)))
    srow("vdstyget_1_256", P.u32_text(vdsty_get(1, 256)))
    srow("vdstyget_1_257", P.u32_text(vdsty_get(1, 257)))
    srow("vdstyget_1_258", P.u32_text(vdsty_get(1, 258)))
    srow("vdstyget_1_259", P.u32_text(vdsty_get(1, 259)))
    srow("vdstyget_2_256", P.u32_text(vdsty_get(2, 256)))
    srow("vdstyget_2_257", P.u32_text(vdsty_get(2, 257)))
    srow("vdstyget_2_258", P.u32_text(vdsty_get(2, 258)))
    srow("vdstyget_2_259", P.u32_text(vdsty_get(2, 259)))
    srow("vdstyget_127_256", P.u32_text(vdsty_get(127, 256)))
    srow("vdstyget_127_257", P.u32_text(vdsty_get(127, 257)))
    srow("vdstyget_127_258", P.u32_text(vdsty_get(127, 258)))
    srow("vdstyget_127_259", P.u32_text(vdsty_get(127, 259)))
    srow("vdstyget_128_256", P.u32_text(vdsty_get(128, 256)))
    srow("vdstyget_128_257", P.u32_text(vdsty_get(128, 257)))
    srow("vdstyget_128_258", P.u32_text(vdsty_get(128, 258)))
    srow("vdstyget_128_259", P.u32_text(vdsty_get(128, 259)))
    srow("vdstyget_255_256", P.u32_text(vdsty_get(255, 256)))
    srow("vdstyget_255_257", P.u32_text(vdsty_get(255, 257)))
    srow("vdstyget_255_258", P.u32_text(vdsty_get(255, 258)))
    srow("vdstyget_255_259", P.u32_text(vdsty_get(255, 259)))
# --- N  _needs_literal -------------------------------------------------
# --- V  _variant_suffix ------------------------------------------------
def g_vs() -> IO(Unit):
  do IO<Unit>:
    srow("vsuf_0", P.vs_text(P.vs_off(0, False{})))
    srow("vsufc_0", P.vs_text(P.vs_off(0, True{})))
    srow("vsuf_248", P.vs_text(P.vs_off(248, False{})))
    srow("vsufc_248", P.vs_text(P.vs_off(248, True{})))
    srow("vsuf_249", P.vs_text(P.vs_off(249, False{})))
    srow("vsufc_249", P.vs_text(P.vs_off(249, True{})))
    srow("vsuf_250", P.vs_text(P.vs_off(250, False{})))
    srow("vsufc_250", P.vs_text(P.vs_off(250, True{})))
    srow("vsuf_255", P.vs_text(P.vs_off(255, False{})))
    srow("vsufc_255", P.vs_text(P.vs_off(255, True{})))
    srow("vsuf_124", P.vs_text(P.vs_off(124, False{})))
    srow("vsufc_124", P.vs_text(P.vs_off(124, True{})))
    srow("vsuf_256", P.vs_text(P.vs_off(256, False{})))
    srow("vsufc_256", P.vs_text(P.vs_off(256, True{})))
    srow("vsuf_none", P.vs_text(P.vs_off(0, False{})))
    P.row("vsuf_is_some_255", P.is_some(P.vs_off(255, False{})))
    P.row("vsuf_is_some_0", P.is_some(P.vs_off(0, False{})))
def src_space() -> P.Rg: P.Rg{P.SRC_LO(), P.SRC_SZ(), False{}, False{}, False{}}
# `src[key]` for an int key (:28-29). The bound test is `key < 0 or key >=
# self.sz` and it comes FIRST, so a negative key is a REFUSAL and never
# reaches Python's own negative indexing. `key_neg` is the `< 0` half, which
# the caller supplies because Bend has no I32; the gate pins both answers one
# row apart.
# `_canonical_name(name)` (:261-268). It has only FIVE results, so the port
# gives it a sixth -- DFLT_OFF -- for "not a canonical operand". Both callers
# (:388, :396) guard with `if (cn := ...)`, so the sentinel is never read where
# it decides anything, and the table is now readable from the gate.
def reg_slice_start(r: P.Rg, start: U32, stop: U32) -> P.Res: P.reg_slice(start, False{}, True{}, stop, False{}, True{}, r)
def g_get() -> IO(Unit):
  do IO<Unit>:
    srow("get_at_0", rg2(0, 1))
    srow("get_at_1", rg2(1, 1))
    srow("get_at_63", rg2(63, 1))
    srow("get_at_104", rg2(104, 1))
    srow("get_at_105", rg2(105, 1))
    srow("get_at_106", rg2(106, 1))
    srow("get_at_107", rg2(107, 1))
    srow("get_at_108", rg2(108, 1))
    srow("get_at_123", rg2(123, 1))
    srow("get_at_124", rg2(124, 1))
    srow("get_at_125", rg2(125, 1))
    srow("get_at_126", rg2(126, 1))
    srow("get_at_127", rg2(127, 1))
    srow("get_at_128", rg2(128, 1))
    srow("get_at_129", rg2(129, 1))
    srow("get_at_192", rg2(192, 1))
    srow("get_at_193", rg2(193, 1))
    srow("get_at_208", rg2(208, 1))
    srow("get_at_209", rg2(209, 1))
    srow("get_at_239", rg2(239, 1))
    srow("get_at_240", rg2(240, 1))
    srow("get_at_248", rg2(248, 1))
    srow("get_at_255", rg2(255, 1))
    srow("get_at_256", rg2(256, 1))
    srow("get_at_257", rg2(257, 1))
    srow("get_at_510", rg2(510, 1))
    srow("get_at_511", rg2(511, 1))
    srow("get_slice_0_105", rg2(0, U32.add(U32.sub(105, 0), 1)))
    srow("get_slice_106_107", rg2(106, U32.add(U32.sub(107, 106), 1)))
    srow("get_slice_108_123", rg2(108, U32.add(U32.sub(123, 108), 1)))
    srow("get_slice_126_127", rg2(126, U32.add(U32.sub(127, 126), 1)))
    srow("get_slice_256_511", rg2(256, U32.add(U32.sub(511, 256), 1)))
    srow("get_slice_0_511", rg2(0, U32.add(U32.sub(511, 0), 1)))
    srow("get_slice_default", rg2(0, 512))
    srow("get_neg_index", P.ref(P.Res.msg(P.reg_at(4294967295, True{}, src_space()))))
    srow("get_index_ge_sz", P.ref(P.Res.msg(P.reg_at(512, False{}, src_space()))))
    srow("get_slice_stop_ge_sz", P.ref(P.Res.msg(reg_slice_start(src_space(), 0, 512))))
    srow("get_slice_neg_start", P.ref(P.Res.msg(P.reg_slice(4294967295, True{}, True{}, 5, False{}, True{}, src_space()))))
    srow("get_ok_511", P.Res.s(P.reg_at(511, False{}, src_space())))
    srow("get_ok_0", P.Res.s(P.reg_at(0, False{}, src_space())))
# --- F  Reg.fmt -- EVERY ARM, at sz 1 and sz>1, upper and not ----------
def bf_width_ok(f: P.Fld) -> Bool: U32.is_le(P.bf_bits(f), 32)
# a field that does not fit the WORD is refused, not truncated, and this is the
# guard that makes "no instruction word ever comes back short" TRUE rather than
# merely intended. `bf_width_ok` above is a WIDTH test against 32; this one is a
# POSITION test against `WORD_HI`, and they are not the same test: `F64_FIELDS`'s
# `lit` is 32 bits wide at [63:32] and `bf_width_ok` refuses it, while a 2-bit
# field at [71:70] is comfortably narrow and `bf_in_word` refuses that one.
#
# `dsl.py`'s `_raw` is a Python int, so CPython has no such refusal and cannot
# have one -- which is why `bfset_word64` is a PINNED divergence rather than a
# match. The port is right to be louder than the oracle here: `H.i64_shl`
# saturates silently, and a clean zero written where `blgp` belongs is a wrong
# kernel with no error anywhere.
def VOP2_INT65() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.int(65), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
# `Reg(offset=0, sz=512)` (:66). The whole src space, ONE register of 512 wide.
def canon_of(nm: String) -> U32: P.nm_off.go(P.canon_in_n(), nm, P.canon_in(), False{}, P.DFLT_OFF())
# ===========================================================================
# `Reg`. :18-63.
# ===========================================================================
# `Reg(offset=0, sz=512)` (:66). The whole src space, ONE register of 512 wide.
# --- I  the Inst field order, _base_size, and the raw-word walk --------
def VOP2_FIELDS() -> List<&2, P.Fld>:
  [P.Fld.fixed("op", 7, 0, 0), P.Fld.vgpr("vdst", 15, 8), P.Fld.src("src0", 25, 17),
   P.Fld.ssrc("src1", 33, 26), P.Fld.plain("op_sel", 35, 34), P.Fld.sbase("sdst", 41, 36)]
# the field list AS TEXT, by name and in order -- the gate's answer to "is the
# order right", which a count cannot answer.
def F64_VALS() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 5), P.Ov.none(), False{}), P.Vf.of(P.Fld.plain("lit", 63, 32), P.Ov.int(305419896), True{})]
# ===========================================================================
# the renderers the generated rows need. Injected with the fixtures for the
# same reason: the generator replaces everything from its marker down, so a def
# written after the marker is deleted on the next run. Measured, twice.
# ===========================================================================
# `_canonical_name` prints the NAME or `None` -- CPython's own answer, and the
# gate compares THAT and not a slot index. The index is still reachable through
# `canon_name`, so the table is readable in both directions; only the REFUSAL
# needs a different spelling, because "not a canonical operand" is `None`.
def MOD_NONE() -> U32: 3
def F32_FIELDS() -> List<&2, P.Fld>: [P.Fld.fixed("op", 7, 0, 5), P.Fld.plain("A", 23, 8)]
# --- M  the modifier flags: __neg__ / __abs__ / .h / .l ----------------
def exempt_width(+off: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(off, P.EXEMPT_LO1()), U32.is_le(off, P.EXEMPT_HI1())),
          Bool.and(U32.is_ge(off, P.EXEMPT_LO2()), U32.is_le(off, P.EXEMPT_HI2())))
# `_needs_literal` (:248-253). `None` and a `Reg` are NEVER literal; an int is
# literal outside 0..64 and -16..-1; a float is literal when `_FLOAT_ENC` has
# no entry. The int arm is the same pair of range tests `enc_off` uses, and it
# is the same answer, so the two share `inl_int_val` / `inl_neg_val` ON PURPOSE:
# if they ever disagree the file is wrong, and a mutation on one is caught by a
# row on the other.
# `(vdstx.offset - 256) & 1) ^ 1` -- the low bit comes from Vdstx and is INVERTED
def F16_VALS() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 5), P.Ov.none(), False{}), P.Vf.of(P.Fld.plain("A", 23, 8), P.Ov.int(4660), True{}),
   P.Vf.of(P.Fld.plain("B", 31, 16), P.Ov.int(22136), True{})]
def ORD_VALS_SWAP() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.plain("second", 7, 0), P.Ov.int(22), True{}), P.Vf.of(P.Fld.plain("first", 7, 0), P.Ov.int(11), True{})]
# THE `Inst` FIXTURES for `_base_size` and `to_bytes`. Each is ONE field apart,
# so `(max(hi) + 8) // 8` (:282) crosses a byte boundary at each one, and
# F64I's 32-bit-wide `lit` at [63:32] is the widest legal field there is.
def VOP2_BIG2() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.reg(266, 2, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.reg(250, 8, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.reg(4, 1, False{}, False{}, False{}), True{})]
# THE ORDER FIXTURES. Two fields at the SAME bits with different names: `set` is
# a masked overwrite, so the LAST write wins and the field ORDER decides the
# word. Swap the two and every value-identical gate row on this file still
# passes, which is exactly why this fixture exists -- a transposed pair in
# `_fields` is otherwise invisible to a count, to a graph shape, and to a diff of
# the final word.
def mod_merge(given: U32, +has: Bool, +bits: U32) -> U32:
  Bool.pick(U32, has, U32.or(given, bits), bits)
# `__init__`'s positional walk (:304-307): `_fields` in order, a FixedBitField
# consuming NOTHING, then kwargs, then the next positional. `skip` is the
# "already consumed" flag that stands in for Python's `iter`.
def mod_hi(+v: P.Ov, has: Bool) -> U32: Bool.pick(U32, Bool.and(has, Bool.and(U32.is_eq(P.Ov.k(v), P.OV_REG()), P.Ov.hi(v))), 1, 0)
# `vals['neg'] = (vals.get('neg') or 0) | neg_bits` (:322) and the same for
# `abs` and `opsel`. TWO facts and both matter: the `or 0` swallows a zero, and
# the `|` MERGES with a value the caller already gave.
#
# WHICH IS `(vals.get(k) or 0) | bits` IN ITS WHOLE, AND `has` IS `vals.get(k) IS
# NOT None`. The `or 0` is INERT once the left side is a U32 (0 | bits IS bits), so the
# whole expression is `has ? (given | bits) : bits`.
#
# this DEF was an outer `Bool.pick` over that answer, with the literal `0` as its ELSE
# ARM AND `Bool.and(has, U32.is_zero(bits))` AS ITS CONDITION -- so it returned 0 for
# every case where `has` is false OR `bits` is nonzero, i.e. for every case that was
# worth encoding. `Bool.pick` ITSELF IS CORRECT: `base.bend:614` is
# `match c: case False{}: b / case True{}: a`, and `Bool.pick(U32, Bool.and(has,
# U32.is_zero(bits)), ..., 0)` reads exactly as written. The cause was here and not
# there, and `mod_merge(2, True{}, 1)` was CPython `3` against port `0`.
def VOP2_HI() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.reg(266, 1, False{}, False{}, True{}), True{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.reg(3, 1, False{}, False{}, True{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
# int 64 is the last inlineable positive (:165) and -16 the last inlineable
# negative (:166) -- one row either side of each, because the boundary is where
# an off-by-one in the range test shows and nowhere else.
def from_bytes(w: H.I64) -> H.I64: w
# `to_bytes` (:416) is `self._raw.to_bytes(self._base_size, 'little')`, so the
# hex is LITTLE-ENDIAN and exactly `base_size` bytes: the LOW byte first, two
# digits per byte, no `0x`.
#
# the old DEF dropped `8 - sz*2` characters from the left of a ten-character `0x%08x`,
# which is three wrong things at once and all three are the same ERROR. It is
# BIG-endian (dropping the high characters keeps the HIGH bytes), it keeps the `0x`,
# and `8 - 12` is not a number, so a SIX-byte instruction -- every VOP3, every MFMA --
# dropped more characters than the string had and answered the EMPTY string.
# MEASURED: `to_bytes_vop2` CPython `000a06144800`, port ``; `to_bytes_f32i` CPython
# `053412`, port `00123405`.
def VOP2_DPP() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.reg(3, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.reg(250, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
# `vdst` given TWO registers where `op_regs` says one. The two rows below are the
# EXEMPTION and its opposite: `sdst` at 4 wide with offset 124 is exempt
# (:339's `106 <= offset <= 127`), `src0` at 8 wide with offset 250 is exempt
# (`:339`'s `249 <= offset <= 255`), and `vdst` at 2 wide is NOT.
def mod_ab(+v: P.Ov, has: Bool) -> U32: Bool.pick(U32, Bool.and(has, Bool.and(U32.is_eq(P.Ov.k(v), P.OV_REG()), P.Ov.ab(v))), 1, 0)
def VOP2_INTN17() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.int(4294967279), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
# THE FLOAT ENCODING PATH. :164 is `_FLOAT_ENC.get(val, 255)`; the first fixture
# supplies a KNOWN float's offset and the second supplies the 255 a float absent
# from `_FLOAT_ENC` gets -- the negative half of the same `.get`.
def F40_VALS() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 5), P.Ov.none(), False{}), P.Vf.of(P.Fld.plain("A", 39, 8), P.Ov.int(1193046), True{})]
# MUBUF/MTBUF: `max(1, self.offen + self.idxen) * 32` (:368). `max(1, ...)` is
# load-bearing: both zero still gives 32, one register, not zero.
def VOP2_INT() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.int(64), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.int(4294967280), True{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
def no_resize(+off: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(off, P.NORESIZE_A()), U32.is_eq(off, P.NORESIZE_B())),
         Bool.and(U32.is_ge(off, P.NORESIZE_C()), U32.is_lt(off, P.NORESIZE_D())))
# the `op_regs` width check's exemption (:339) -- a DIFFERENT pair of ranges,
# 106..127 and 249..255. Two similar-looking exemption sets in one file, and
# they are NOT the same; the gate has a row for each boundary.
def VOP2_FNOLIT() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.src_ov_float(P.FLOAT_ENC_DEFAULT(), False{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
def rws(+res: P.Wrd) -> String: String.concat([P.Wrd.s(res), "|", P.hexw(P.Wrd.w(res))])
# a `fixed` field's fixture value is an absence, and that is not a spelling
# CHOICE -- IT IS WHAT CPython REFUSES ANYTHING ELSE ON. `FixedBitField.set`
# (dsl.py:120-123) opens `assert val is None`, so every `*_VALS` list below
# spells `op` `Ov.none(), False{}` and NOT `Ov.int(0), True{}`, which is what
# these eighteen lists used to say.
#
# MEASURED, CPython's own `_walk` on `VOP2_ALL` with `op=0`:
# `FixedBitField does not accept values, got 0`, word `0`. Nothing here could
# see it. `fld_encode.k`'s K_FIXED arm does not READ the value, `fld_encode.dflt`
# and `fld_encode.k` answer the same `Fld.dflt(f)` for either spelling of `has`,
# and the packed word is identical -- so the change moves ZERO rows and is
# proven by `fixtures_hold`, which compared the fixture VALUES and not the
# fixture NAMES. That guard dropped the second element of `(n, v)` for its whole
# life, which is why `F64_VALS`' `lit` could be `0x1234` on one lane and
# `0x12345678` on the other for as long as the file existed.
# THE ORDER FIXTURE. Two fields at the SAME bits with different names: `set` is
# a masked overwrite, so the LAST write wins and the field ORDER decides the
# word. Swap the two and every value-identical gate row on this file still
# passes, which is exactly why this fixture exists -- a transposed pair in
# `_fields` is otherwise invisible.
def mod_neg(+v: P.Ov, has: Bool) -> U32: Bool.pick(U32, Bool.and(has, Bool.and(U32.is_eq(P.Ov.k(v), P.OV_REG()), P.Ov.neg(v))), 1, 0)
def ORD_FIELDS() -> List<&2, P.Fld>: [P.Fld.plain("first", 7, 0), P.Fld.plain("second", 7, 0)]
# the parenthesised number is dsl.py:158's `actual_size`, which is `1 << bits` -- 512 -- and not
# the mask, 511. the port printed the mask. CPython never prints this string for an SRC field,
# because it never raises on one, so the message rows stay a carve-out while the decision rows
# become exact: the port was deciding "refuse" WHERE CPYTHON decides "accept", and a string
# that is never printed hides which one it took.
def VOP2_NEG() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.reg(266, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.reg(3, 1, True{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.reg(5, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
def VOP2_FCONST() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.src_ov_float(P.F0_5_OFF(), True{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.src_ov_float(247, True{}), True{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
def F32_VALS() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 5), P.Ov.none(), False{}), P.Vf.of(P.Fld.plain("A", 23, 8), P.Ov.int(4660), True{})]
def F8_VALS() -> List<&2, P.Vf>: [P.Vf.of(P.Fld.fixed("op", 7, 0, 5), P.Ov.none(), False{})]
def ORD_VALS() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.plain("first", 7, 0), P.Ov.int(11), True{}), P.Vf.of(P.Fld.plain("second", 7, 0), P.Ov.int(22), True{})]
def ORD_FIELDS_SWAP() -> List<&2, P.Fld>: [P.Fld.plain("second", 7, 0), P.Fld.plain("first", 7, 0)]
def base_size(P.hi_max: U32) -> U32: U32.div(U32.add(P.hi_max, P.BASE_SIZE_ROUND()), P.BASE_SIZE_DIV())
# ===========================================================================
# THE FIELD CLASSES' `encode`. Each is the class's OWN rule, and a swapped pair
# here writes the wrong bits into the wrong field, so each is gated against
# CPython over a range that crosses every branch.
# ===========================================================================
# `SrcField.encode` (:161-171). FOUR cases, in this order, and the order is
# load-bearing because a `Reg` is also an int in Python's duck-typing sense:
#
#   Reg        -> val.offset
#   float      -> _FLOAT_ENC.get(val, 255)          (:164)  THE FLOAT WALL
#   0 <= v<=64 -> 128 + v                            (:165)
#   -16 <= v<0 -> 192 - v                            (:166)
#   any int    -> 255  (literal)                     (:167)
#   else       -> TypeError                          (:168)
#
# then `offset - _valid_range[0]` (:171), which is 0 for a plain SrcField and
# -256 for a VGPRField. `enc_off` is that offset and `enc_kind` says which case
# fired, so the refusal and the value are separate facts.
# `SrcField.encode` (:161-171). FOUR cases, in this order, and the ORDER is
# load-bearing: a `Reg` is tested before an `int` (:163 vs :165), and a `float`
# before both (:164).
#
#   Reg        -> val.offset                              (:163)
#   float      -> _FLOAT_ENC.get(val, 255)                (:164)  THE FLOAT WALL
#   0 <= v<=64 -> 128 + v                                 (:165)
#   -16 <= v<0 -> 192 - v                                 (:166)
#   any int    -> 255, the literal marker                 (:167)
# then the range test against `_valid_range` (:169-170), THEN
# `return offset - self._valid_range[0]` (:171) -- which is 0 for a SrcField
# and -256 for a VGPRField, so the subtraction is not a no-op in general.
#
# ---------------------------------------------------------------------------
# the FLOAT wall, named, with its line and its reason.
#
# :164 is `isinstance(val, float)` and :164's other half looks a float up in
# `_FLOAT_ENC`. Bend here cannot construct an `F32` at all: `F32` is
# `F32{data: Word(32n)}` and `Word` is not exported -- the identical wall
# `tinybendygrad/tensor.bend:1214 symbol=tn_const` and
# `tinybendygrad/renderer/wgsl.bend:340 symbol=nan_thr` record, for the identical reason. `_f32` (:147, `struct.pack('f')`) is behind
# the same door, and so is `_needs_literal`'s float arm (:251).
#
# SO WHAT IS PORTED. The TABLE (`_FLOAT_ENC`, both directions) is ported, and so
# is the dispatch: `OV_FLOAT` is a distinct kind, `enc_off`'s float arm is its
# own arm, and an UNKNOWN float answers 255 -- the negative case, which is the
# half of :164 that is a decision rather than a comparison. What is NOT ported
# is deciding, from a float VALUE, which of the eight entries applies: that is
# one `F32` construction, and it is four bytes the seam must hand over.
# `src_ov_float` is the whole of the ported part and its `known` flag IS
# `_FLOAT_ENC.get`'s hit test.
# ---------------------------------------------------------------------------
def VOP2_ALL() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.reg(266, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.reg(3, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.reg(5, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.int(2), True{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.reg(8, 1, False{}, False{}, False{}), True{})]
# `self.op_name.lower()` -- the tests are all on the LOWERCASE name (:355), so
# `V_CNDMASK_F32` and `V_cndmask_f32` take the same arm and a case-folded name
# would silently take the OTHER one.
def F16_FIELDS() -> List<&2, P.Fld>:
  [P.Fld.fixed("op", 7, 0, 5), P.Fld.plain("A", 23, 8), P.Fld.plain("B", 31, 16)]
def VOP2_SDWA() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.reg(3, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.reg(249, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
def VOP2_BIG() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.reg(266, 2, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.reg(3, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.reg(124, 4, False{}, False{}, False{}), True{})]
# --- F  Reg.fmt -- EVERY ARM, at sz 1 and sz>1, upper and not ----------
def F64_FIELDS() -> List<&2, P.Fld>: [P.Fld.fixed("op", 7, 0, 5), P.Fld.plain("lit", 63, 32)]
def VOP2_LIT() -> List<&2, P.Vf>:
  [P.Vf.of(P.Fld.fixed("op", 7, 0, 0), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.vgpr("vdst", 15, 8), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.src("src0", 25, 17), P.Ov.reg(255, 1, False{}, False{}, False{}), True{}),
   P.Vf.of(P.Fld.ssrc("src1", 33, 26), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.plain("op_sel", 35, 34), P.Ov.none(), False{}),
   P.Vf.of(P.Fld.sbase("sdst", 41, 36), P.Ov.none(), False{})]
def g_inst() -> IO(Unit):
  do IO<Unit>:
    srow("vop2_fields", P.fields_of(VOP2_FIELDS()))
    urow("vop2_base_size", base_size(P.hi_max(VOP2_FIELDS())))
    urow("vop2_hi_max", P.hi_max(VOP2_FIELDS()))
    srow("ord_fields", P.fields_of(ORD_FIELDS()))
    srow("ord_fields_swap", P.fields_of(ORD_FIELDS_SWAP()))
    srow("raw_ord", rws(P.raw_walk(ORD_VALS())))
    srow("raw_ord_swap", rws(P.raw_walk(ORD_VALS_SWAP())))
    srow("fields_F16", P.fields_of(F16_FIELDS()))
    urow("base_size_F16", base_size(P.hi_max(F16_FIELDS())))
    srow("fields_F64", P.fields_of(F64_FIELDS()))
    urow("base_size_F64", base_size(P.hi_max(F64_FIELDS())))
    urow("f64i_mask_lit", P.bf_mask(P.Fld.plain("lit", 63, 32)))
    urow("f64i_mask_frac", P.bf_mask(P.Fld.plain("f", 31, 0)))
    urow("f40i_mask", P.bf_mask(P.Fld.plain("a", 39, 8)))
    P.row("bf_width_ok_31", bf_width_ok(P.Fld.plain("f", 31, 0)))
    P.row("bf_width_ok_40", bf_width_ok(P.Fld.plain("f", 40, 0)))
    srow("raw_vop2_all", rws(P.raw_walk(VOP2_ALL())))
    srow("raw_vop2_neg", rws(P.raw_walk(VOP2_NEG())))
    srow("raw_vop2_hi", rws(P.raw_walk(VOP2_HI())))
    srow("raw_vop2_int", rws(P.raw_walk(VOP2_INT())))
    srow("raw_vop2_fconst", rws(P.raw_walk(VOP2_FCONST())))
    srow("raw_vop2_fnolit", rws(P.raw_walk(VOP2_FNOLIT())))
    srow("raw_vop2_int65", rws(P.raw_walk(VOP2_INT65())))
    srow("raw_vop2_intn17", rws(P.raw_walk(VOP2_INTN17())))
    srow("raw_vop2_big2", rws(P.raw_walk(VOP2_BIG2())))
    srow("raw_vop2_lit", rws(P.raw_walk(VOP2_LIT())))
    srow("raw_vop2_sdwa", rws(P.raw_walk(VOP2_SDWA())))
    srow("raw_vop2_dpp", rws(P.raw_walk(VOP2_DPP())))
    srow("raw_vop2_big", rws(P.raw_walk(VOP2_BIG())))
    srow("raw_f32i", rws(P.raw_walk(F32_VALS())))
    srow("raw_f16i", rws(P.raw_walk(F16_VALS())))
    srow("raw_f64i", rws(P.raw_walk(F64_VALS())))
    srow("raw_f40i", rws(P.raw_walk(F40_VALS())))
    srow("raw_f8i", rws(P.raw_walk(F8_VALS())))
    P.row("noresize_105", no_resize(105))
    P.row("exemptw_105", exempt_width(105))
    P.row("noresize_106", no_resize(106))
    P.row("exemptw_106", exempt_width(106))
    P.row("noresize_107", no_resize(107))
    P.row("exemptw_107", exempt_width(107))
    P.row("noresize_124", no_resize(124))
    P.row("exemptw_124", exempt_width(124))
    P.row("noresize_125", no_resize(125))
    P.row("exemptw_125", exempt_width(125))
    P.row("noresize_126", no_resize(126))
    P.row("exemptw_126", exempt_width(126))
    P.row("noresize_127", no_resize(127))
    P.row("exemptw_127", exempt_width(127))
    P.row("noresize_128", no_resize(128))
    P.row("exemptw_128", exempt_width(128))
    P.row("noresize_239", no_resize(239))
    P.row("exemptw_239", exempt_width(239))
    P.row("noresize_240", no_resize(240))
    P.row("exemptw_240", exempt_width(240))
    P.row("noresize_248", no_resize(248))
    P.row("exemptw_248", exempt_width(248))
    P.row("noresize_249", no_resize(249))
    P.row("exemptw_249", exempt_width(249))
    P.row("noresize_254", no_resize(254))
    P.row("exemptw_254", exempt_width(254))
    P.row("noresize_255", no_resize(255))
    P.row("exemptw_255", exempt_width(255))
    P.row("noresize_256", no_resize(256))
    P.row("exemptw_256", exempt_width(256))
    # `modmerge_{given}_0_{bits}` -- THE MIDDLE DIGIT IS `has`, and it is 0 in EVERY one
    # of these rows, because `vals` is a DICT in CPython (dsl.py:334-335 looks a value
    # up BY NAME) and a caller that supplied nothing and a caller that supplied a value
    # are only told apart by the KEY. Three of these rows read `True{}` where their own
    # NAME says `0`, and the census caught it as CPython `0` against port `2`.
    urow("modmerge_0_0_0", mod_merge(0, False{}, 0))
    urow("modmerge_0_0_0", mod_merge(0, False{}, 0))
    urow("modmerge_0_0_1", mod_merge(0, False{}, 1))
    urow("modmerge_0_0_1", mod_merge(0, False{}, 1))
    urow("modmerge_2_0_0", mod_merge(2, False{}, 0))
    urow("modmerge_2_0_1", mod_merge(2, False{}, 1))
    urow("modmerge_6_0_1", mod_merge(6, False{}, 1))
    urow("srcbit_src0", P.src_bit("src0"))
    urow("srcbit_src1", P.src_bit("src1"))
    urow("srcbit_src2", P.src_bit("src2"))
    urow("srcbit_vdst", P.src_bit("vdst"))
    urow("srcbit_sdst", P.src_bit("sdst"))
    urow("srcbit_op", P.src_bit("op"))
    urow("srcbit_nosuch", P.src_bit("nosuch"))
    # THE THREE MASKS (dsl.py:313-319), each over the REGISTER its own bit names:
    # the census convention is neg -> src0, abs -> src1, opsel -> src2, so
    # MOD_SRC0_BIT / MOD_SRC1_BIT / MOD_SRC2_BIT and NOT a shift of the index.
    # and the four families named for a register rather than a mask: dsl.py has no
    # line that ORs a register's NAME into a mask, so MOD_NONE and the answer is 0.
    #
    # these rows passed `1` for all three masks. `mod_mask` could not tell them
    # apart -- it asked only `is a Reg` -- AND NEITHER COULD THE ROWS, so `ab` and
    # `hi` were src0 under two more names. that is a second, independent defect,
    # and it is the one the pin class did not name: it lives in the fixture, not in
    # the def, and a correct `mod_mask` with the old bits still disagrees on
    # `modmask_hi_hi` (src0.hi is set in VOP2_HI; the row asked about src2).
    urow("modmask_neg_vop2", P.mod_mask(P.MOD_NEG(), P.MOD_SRC0_BIT(), VOP2_ALL()))
    urow("modmask_neg_neg", P.mod_mask(P.MOD_NEG(), P.MOD_SRC0_BIT(), VOP2_NEG()))
    urow("modmask_neg_hi", P.mod_mask(P.MOD_NEG(), P.MOD_SRC0_BIT(), VOP2_HI()))
    urow("modmask_ab_vop2", P.mod_mask(P.MOD_ABS(), P.MOD_SRC1_BIT(), VOP2_ALL()))
    urow("modmask_ab_neg", P.mod_mask(P.MOD_ABS(), P.MOD_SRC1_BIT(), VOP2_NEG()))
    urow("modmask_ab_hi", P.mod_mask(P.MOD_ABS(), P.MOD_SRC1_BIT(), VOP2_HI()))
    urow("modmask_hi_vop2", P.mod_mask(P.MOD_OPSEL(), P.MOD_SRC2_BIT(), VOP2_ALL()))
    urow("modmask_hi_neg", P.mod_mask(P.MOD_OPSEL(), P.MOD_SRC2_BIT(), VOP2_NEG()))
    urow("modmask_hi_hi", P.mod_mask(P.MOD_OPSEL(), P.MOD_SRC2_BIT(), VOP2_HI()))
    urow("modmask_src0_vop2", P.mod_mask(MOD_NONE(), P.MOD_SRC0_BIT(), VOP2_ALL()))
    urow("modmask_src0_neg", P.mod_mask(MOD_NONE(), P.MOD_SRC0_BIT(), VOP2_NEG()))
    urow("modmask_src0_hi", P.mod_mask(MOD_NONE(), P.MOD_SRC0_BIT(), VOP2_HI()))
    urow("modmask_src1_vop2", P.mod_mask(MOD_NONE(), P.MOD_SRC1_BIT(), VOP2_ALL()))
    urow("modmask_src1_neg", P.mod_mask(MOD_NONE(), P.MOD_SRC1_BIT(), VOP2_NEG()))
    urow("modmask_src1_hi", P.mod_mask(MOD_NONE(), P.MOD_SRC1_BIT(), VOP2_HI()))
    urow("modmask_src2_vop2", P.mod_mask(MOD_NONE(), P.MOD_SRC2_BIT(), VOP2_ALL()))
    urow("modmask_src2_neg", P.mod_mask(MOD_NONE(), P.MOD_SRC2_BIT(), VOP2_NEG()))
    urow("modmask_src2_hi", P.mod_mask(MOD_NONE(), P.MOD_SRC2_BIT(), VOP2_HI()))
    urow("modmask_vdst_vop2", P.mod_mask(MOD_NONE(), P.MOD_VDST_BIT(), VOP2_ALL()))
    urow("modmask_vdst_neg", P.mod_mask(MOD_NONE(), P.MOD_VDST_BIT(), VOP2_NEG()))
    urow("modmask_vdst_hi", P.mod_mask(MOD_NONE(), P.MOD_VDST_BIT(), VOP2_HI()))
    urow("mod_src0_neg", mod_merge(0, False{}, mod_neg(P.Ov.reg(3, 1, True{}, False{}, False{}), True{})))
    urow("mod_src0_ab", mod_merge(0, False{}, mod_ab(P.Ov.reg(3, 1, False{}, True{}, False{}), True{})))
    urow("mod_src0_hi", mod_merge(0, False{}, mod_hi(P.Ov.reg(3, 1, False{}, False{}, True{}), True{})))
    urow("mod_merge_or", mod_merge(2, True{}, 1))
    urow("mod_merge_zero", mod_merge(0, True{}, 0))
    urow("mod_merge_nogiven", mod_merge(0, False{}, 1))
    srow("to_bytes_vop2", P.bytes_of(P.Wrd.w(P.raw_walk(VOP2_ALL())), base_size(P.hi_max(VOP2_FIELDS()))))
    srow("to_bytes_f32i", P.bytes_of(P.Wrd.w(P.raw_walk(F32_VALS())), base_size(P.hi_max(F32_FIELDS()))))
    srow("to_bytes_f16i", P.bytes_of(P.Wrd.w(P.raw_walk(F16_VALS())), base_size(P.hi_max(F16_FIELDS()))))
    # the only `to_bytes_*` row with a nonzero high BYTE above BYTE 0, and it is
    # here because a MUTATION PROVED IT MISSING: masking `wbyte`'s high limb to
    # eight bits moved ZERO rows and left the gate GREEN, because every other
    # word in this census has a high limb of `0x00` or `0x48`. `F64_FIELDS` is
    # 64 bits wide, so `base_size` is 8 and all four high bytes are `78 56 34 12`.
    srow("to_bytes_f64i", P.bytes_of(P.Wrd.w(P.raw_walk(F64_VALS())), base_size(P.hi_max(F64_FIELDS()))))
    urow("from_bytes_ff", H.lo32(from_bytes(H.i64_of_i32(4294967295))))
    urow("from_bytes_dead", H.lo32(from_bytes(H.i64_of_i32(3735928559))))
# --- O  op_bits / op_regs / canonical_* / num_srcs ---------------------
def rg5(+r: P.Rg) -> String:
  String.concat([P.u32_text(P.Rg.off(r)), ",", P.u32_text(P.Rg.sz(r)), ",", P.bs(P.Rg.neg(r)), ",",
                 P.bs(P.Rg.ab(r)), ",", P.bs(P.Rg.hi(r))])
# THE VOP2 FIXTURE, fields in DECLARATION order. `op` is a plain BitField here,
# NOT an EnumBitField, because a class whose `op` is a plain int cannot reach
# `self.op_regs` at all (:337 -> :343 needs `.name`) -- so this fixture is the
# "no opcode enum" shape and its rows are about `_fields` order and `fmt`, not
# about `op_bits`.
def SCC_OFF() -> U32: 253
# --- O  op_bits / op_regs / canonical_* / num_srcs ---------------------
def canon_seed_bits(id: U32) -> U32: P.CANON_SEED()
# `num_srcs` (:404-410). THREE RUNGS, tested in order, off the OPERAND NAMES
# and not off `op_bits`. 'src2' is the only spelling of the third source; the
# first source has three spellings and the second has three.
# `vals['neg'] = (vals.get('neg') or 0) | neg_bits` (:322) and the same for
# `abs` and `opsel`. TWO facts and both matter: the `or 0` swallows a zero, and
# the `|` MERGES with a value the caller already gave.
#
# WHICH IS `(vals.get(k) or 0) | bits` IN ITS WHOLE, AND `has` IS `vals.get(k) IS
# NOT None`. The `or 0` is INERT once the left side is a U32 (0 | bits IS bits), so the
# whole expression is `has ? (given | bits) : bits`.
#
# this DEF was an outer `Bool.pick` over that answer, with the literal `0` as its ELSE
# ARM AND `Bool.and(has, U32.is_zero(bits))` AS ITS CONDITION -- so it returned 0 for
# every case where `has` is false OR `bits` is nonzero, i.e. for every case that was
# worth encoding. `Bool.pick` ITSELF IS CORRECT: `base.bend:614` is
# `match c: case False{}: b / case True{}: a`, and `Bool.pick(U32, Bool.and(has,
# U32.is_zero(bits)), ..., 0)` reads exactly as written. The cause was here and not
# there, and `mod_merge(2, True{}, 1)` was CPython `3` against port `0`.
def mfma_raw_blgp(raw: U32) -> U32: U32.and(U32.shrn(raw, U32.to_nat(P.ADJ_BLGP_SHIFT())), P.ADJ_MFMA_SEL_MASK())
def adj_vaddr_bits(offen: U32, idxen: U32) -> U32:
  U32.mul(U32.max(P.REG_MIN(), U32.add(offen, idxen)), P.ADJ_VADDR_MULT())
# F8F6F4: `cbsz = getattr(self, 'cbsz') if hasattr(type(self), 'cbsz') else
# (self._raw >> 8) & 0x7` and the same for blgp at 61 (:373-374). TWO sources
# for each and the class-wins one is the FIRST arm of a conditional expression,
# so a class that declares the field and a class that does not read different
# bits of the SAME raw word.
# THE THREE ROW WRITERS. A row is an `IO(Unit)` that PRINTS, because a `do`
# block cannot bind a non-`Unit` (see fact 1 in the header), so nothing in this
# gate is RETURNED -- every fact is printed and `dsl_gate.py` diffs the lines.
def is_f8f6f4(name: String) -> Bool: P.has_name_bit(name, "f8f6f4")
# `op_regs = {k: max(1, v // 32)}` (:381). The `max(1, ...)` is what makes a
# zero-width operand still one register wide.
def mfma_raw_cbsz(raw: U32) -> U32: U32.and(U32.shrn(raw, U32.to_nat(P.ADJ_CBSZ_SHIFT())), P.ADJ_MFMA_SEL_MASK())
# `op_regs = {k: max(1, v // 32)}` (:381). The `max(1, ...)` is what makes a
# zero-width operand still one register wide.
def op_regs_of(bits: U32) -> U32: U32.max(P.REG_MIN(), U32.div(bits, P.REG_STRIDE()))
# `canonical_op_bits` (:384-389) SEEDS all five canonical names at 32 bits and
# only overwrites on a canonical name -- so an operand dict with no canonical
# name leaves the seed in place, and the seed is NOT derived from anything.
def adj_vdst_bits(name: String, has_vdst: Bool) -> U32:
  Bool.pick(U32, Bool.and(has_vdst, P.has_name_bit(name, "cmp")), P.ADJ_VDST_BITS(), 0)
def addr_exempt(+cls: String) -> Bool: Bool.or(String.eq(cls, "SCRATCH"), String.eq(cls, "VSCRATCH"))
# MUBUF/MTBUF: `max(1, self.offen + self.idxen) * 32` (:368). `max(1, ...)` is
# load-bearing: both zero still gives 32, one register, not zero.
def adj_src2_bits(+name: String, has_src2: Bool) -> U32:
  Bool.pick(U32, Bool.and(has_src2, Bool.or(P.has_name_bit(name, "cndmask"), P.has_name_bit(name, "_co_ci_"))), P.ADJ_SRC2_BITS(), 0)
def g_ops() -> IO(Unit):
  do IO<Unit>:
    urow("adj_src2_cndmask", adj_src2_bits("v_cndmask_f32", True{}))
    urow("adj_vdst_cndmask", adj_vdst_bits("v_cndmask_f32", True{}))
    P.row("is_f8f6f4_cndmask", is_f8f6f4("v_cndmask_f32"))
    P.row("is_vop3sd_cndmask", P.is_vop3sd("VOP3SD"))
    urow("adj_src2_cmp", adj_src2_bits("v_cmp_lt_f32", True{}))
    urow("adj_vdst_cmp", adj_vdst_bits("v_cmp_lt_f32", True{}))
    P.row("is_f8f6f4_cmp", is_f8f6f4("v_cmp_lt_f32"))
    P.row("is_vop3sd_cmp", P.is_vop3sd("VOP3SD"))
    urow("adj_src2_co_ci", adj_src2_bits("v_co_ci_add_f32", True{}))
    urow("adj_vdst_co_ci", adj_vdst_bits("v_co_ci_add_f32", True{}))
    P.row("is_f8f6f4_co_ci", is_f8f6f4("v_co_ci_add_f32"))
    P.row("is_vop3sd_co_ci", P.is_vop3sd("VOP3SD"))
    urow("adj_src2_other", adj_src2_bits("v_add_f32", True{}))
    urow("adj_vdst_other", adj_vdst_bits("v_add_f32", True{}))
    P.row("is_f8f6f4_other", is_f8f6f4("v_add_f32"))
    P.row("is_vop3sd_other", P.is_vop3sd("VOP3SD"))
    urow("adj_src2_f8f6f4", adj_src2_bits("v_f8f6f4_mfma_f32_32x32x8_f16", True{}))
    urow("adj_vdst_f8f6f4", adj_vdst_bits("v_f8f6f4_mfma_f32_32x32x8_f16", True{}))
    P.row("is_f8f6f4_f8f6f4", is_f8f6f4("v_f8f6f4_mfma_f32_32x32x8_f16"))
    P.row("is_vop3sd_f8f6f4", P.is_vop3sd("VOP3SD"))
    urow("addr_0", P.adj_addr_bits(0, False{}))
    urow("addrx_0", P.adj_addr_bits(0, True{}))
    urow("addr_1", P.adj_addr_bits(1, False{}))
    urow("addrx_1", P.adj_addr_bits(1, True{}))
    urow("addr_62", P.adj_addr_bits(62, False{}))
    urow("addrx_62", P.adj_addr_bits(62, True{}))
    urow("addr_123", P.adj_addr_bits(123, False{}))
    urow("addrx_123", P.adj_addr_bits(123, True{}))
    urow("addr_124", P.adj_addr_bits(124, False{}))
    urow("addrx_124", P.adj_addr_bits(124, True{}))
    urow("addr_125", P.adj_addr_bits(125, False{}))
    urow("addrx_125", P.adj_addr_bits(125, True{}))
    urow("addr_126", P.adj_addr_bits(126, False{}))
    urow("addrx_126", P.adj_addr_bits(126, True{}))
    urow("addr_127", P.adj_addr_bits(127, False{}))
    urow("addrx_127", P.adj_addr_bits(127, True{}))
    urow("addr_255", P.adj_addr_bits(255, False{}))
    urow("addrx_255", P.adj_addr_bits(255, True{}))
    P.row("addr_exempt_scratch", addr_exempt("SCRATCH"))
    P.row("addr_exempt_vscratch", addr_exempt("VSCRATCH"))
    P.row("addr_exempt_global", addr_exempt("GLOBAL"))
    urow("vaddr_00", adj_vaddr_bits(0, 0))
    urow("vaddr_01", adj_vaddr_bits(0, 1))
    urow("vaddr_10", adj_vaddr_bits(1, 0))
    urow("vaddr_11", adj_vaddr_bits(1, 1))
    srow("f8f6f4_0_0", String.concat([P.u32_text(P.mfma_bits(0, 0)), ",", P.u32_text(P.mfma_bits(0, 0))]))
    urow("f8f6f4_s0_0_0", P.mfma_bits(0, 0))
    srow("f8f6f4_0_1", String.concat([P.u32_text(P.mfma_bits(0, 0)), ",", P.u32_text(P.mfma_bits(1, 1))]))
    urow("f8f6f4_s0_0_1", P.mfma_bits(0, 0))
    srow("f8f6f4_0_2", String.concat([P.u32_text(P.mfma_bits(0, 0)), ",", P.u32_text(P.mfma_bits(2, 2))]))
    urow("f8f6f4_s0_0_2", P.mfma_bits(0, 0))
    srow("f8f6f4_0_3", String.concat([P.u32_text(P.mfma_bits(0, 0)), ",", P.u32_text(P.mfma_bits(3, 3))]))
    urow("f8f6f4_s0_0_3", P.mfma_bits(0, 0))
    srow("f8f6f4_0_4", String.concat([P.u32_text(P.mfma_bits(0, 0)), ",", P.u32_text(P.mfma_bits(4, 4))]))
    urow("f8f6f4_s0_0_4", P.mfma_bits(0, 0))
    srow("f8f6f4_1_0", String.concat([P.u32_text(P.mfma_bits(1, 1)), ",", P.u32_text(P.mfma_bits(0, 0))]))
    urow("f8f6f4_s0_1_0", P.mfma_bits(1, 1))
    srow("f8f6f4_1_1", String.concat([P.u32_text(P.mfma_bits(1, 1)), ",", P.u32_text(P.mfma_bits(1, 1))]))
    urow("f8f6f4_s0_1_1", P.mfma_bits(1, 1))
    srow("f8f6f4_1_2", String.concat([P.u32_text(P.mfma_bits(1, 1)), ",", P.u32_text(P.mfma_bits(2, 2))]))
    urow("f8f6f4_s0_1_2", P.mfma_bits(1, 1))
    srow("f8f6f4_1_3", String.concat([P.u32_text(P.mfma_bits(1, 1)), ",", P.u32_text(P.mfma_bits(3, 3))]))
    urow("f8f6f4_s0_1_3", P.mfma_bits(1, 1))
    srow("f8f6f4_1_4", String.concat([P.u32_text(P.mfma_bits(1, 1)), ",", P.u32_text(P.mfma_bits(4, 4))]))
    urow("f8f6f4_s0_1_4", P.mfma_bits(1, 1))
    srow("f8f6f4_2_0", String.concat([P.u32_text(P.mfma_bits(2, 2)), ",", P.u32_text(P.mfma_bits(0, 0))]))
    urow("f8f6f4_s0_2_0", P.mfma_bits(2, 2))
    srow("f8f6f4_2_1", String.concat([P.u32_text(P.mfma_bits(2, 2)), ",", P.u32_text(P.mfma_bits(1, 1))]))
    urow("f8f6f4_s0_2_1", P.mfma_bits(2, 2))
    srow("f8f6f4_2_2", String.concat([P.u32_text(P.mfma_bits(2, 2)), ",", P.u32_text(P.mfma_bits(2, 2))]))
    urow("f8f6f4_s0_2_2", P.mfma_bits(2, 2))
    srow("f8f6f4_2_3", String.concat([P.u32_text(P.mfma_bits(2, 2)), ",", P.u32_text(P.mfma_bits(3, 3))]))
    urow("f8f6f4_s0_2_3", P.mfma_bits(2, 2))
    srow("f8f6f4_2_4", String.concat([P.u32_text(P.mfma_bits(2, 2)), ",", P.u32_text(P.mfma_bits(4, 4))]))
    urow("f8f6f4_s0_2_4", P.mfma_bits(2, 2))
    srow("f8f6f4_3_0", String.concat([P.u32_text(P.mfma_bits(3, 3)), ",", P.u32_text(P.mfma_bits(0, 0))]))
    urow("f8f6f4_s0_3_0", P.mfma_bits(3, 3))
    srow("f8f6f4_3_1", String.concat([P.u32_text(P.mfma_bits(3, 3)), ",", P.u32_text(P.mfma_bits(1, 1))]))
    urow("f8f6f4_s0_3_1", P.mfma_bits(3, 3))
    srow("f8f6f4_3_2", String.concat([P.u32_text(P.mfma_bits(3, 3)), ",", P.u32_text(P.mfma_bits(2, 2))]))
    urow("f8f6f4_s0_3_2", P.mfma_bits(3, 3))
    srow("f8f6f4_3_3", String.concat([P.u32_text(P.mfma_bits(3, 3)), ",", P.u32_text(P.mfma_bits(3, 3))]))
    urow("f8f6f4_s0_3_3", P.mfma_bits(3, 3))
    srow("f8f6f4_3_4", String.concat([P.u32_text(P.mfma_bits(3, 3)), ",", P.u32_text(P.mfma_bits(4, 4))]))
    urow("f8f6f4_s0_3_4", P.mfma_bits(3, 3))
    srow("f8f6f4_4_0", String.concat([P.u32_text(P.mfma_bits(4, 4)), ",", P.u32_text(P.mfma_bits(0, 0))]))
    urow("f8f6f4_s0_4_0", P.mfma_bits(4, 4))
    srow("f8f6f4_4_1", String.concat([P.u32_text(P.mfma_bits(4, 4)), ",", P.u32_text(P.mfma_bits(1, 1))]))
    urow("f8f6f4_s0_4_1", P.mfma_bits(4, 4))
    srow("f8f6f4_4_2", String.concat([P.u32_text(P.mfma_bits(4, 4)), ",", P.u32_text(P.mfma_bits(2, 2))]))
    urow("f8f6f4_s0_4_2", P.mfma_bits(4, 4))
    srow("f8f6f4_4_3", String.concat([P.u32_text(P.mfma_bits(4, 4)), ",", P.u32_text(P.mfma_bits(3, 3))]))
    urow("f8f6f4_s0_4_3", P.mfma_bits(4, 4))
    srow("f8f6f4_4_4", String.concat([P.u32_text(P.mfma_bits(4, 4)), ",", P.u32_text(P.mfma_bits(4, 4))]))
    urow("f8f6f4_s0_4_4", P.mfma_bits(4, 4))
    srow("f8f6f4_default_9", String.concat([P.u32_text(P.mfma_bits(9, 9)), ",", P.u32_text(P.mfma_bits(9, 9))]))
    urow("mfma_raw_cbsz", mfma_raw_cbsz(65792))
    urow("mfma_raw_blgp", mfma_raw_blgp(65792))
    urow("opregs_0", op_regs_of(0))
    urow("opregs_1", op_regs_of(1))
    urow("opregs_31", op_regs_of(31))
    urow("opregs_32", op_regs_of(32))
    urow("opregs_64", op_regs_of(64))
    urow("opregs_96", op_regs_of(96))
    urow("opregs_128", op_regs_of(128))
    urow("opregs_256", op_regs_of(256))
    urow("opregs_511", op_regs_of(511))
    urow("opregs_1000", op_regs_of(1000))
    urow("canon_seed_c_s0", canon_seed_bits(canon_of("src0")))
    urow("canon_seed_c_vs0", canon_seed_bits(canon_of("vsrc0")))
    urow("canon_seed_c_ss0", canon_seed_bits(canon_of("ssrc0")))
    urow("canon_seed_c_s1", canon_seed_bits(canon_of("src1")))
    urow("canon_seed_c_vs1", canon_seed_bits(canon_of("vsrc1")))
    urow("canon_seed_c_ss1", canon_seed_bits(canon_of("ssrc1")))
    urow("canon_seed_c_s2", canon_seed_bits(canon_of("src2")))
    urow("canon_seed_c_d", canon_seed_bits(canon_of("vdst")))
    urow("canon_seed_c_sdst", canon_seed_bits(canon_of("sdst")))
    urow("canon_seed_c_sdata", canon_seed_bits(canon_of("sdata")))
    urow("canon_seed_c_data", canon_seed_bits(canon_of("data")))
    urow("canon_seed_c_vdata", canon_seed_bits(canon_of("vdata")))
    urow("canon_seed_c_data0", canon_seed_bits(canon_of("data0")))
    urow("canon_seed_c_vsrc", canon_seed_bits(canon_of("vsrc")))
    urow("canon_seed_c_unknown", canon_seed_bits(canon_of("zz")))
    urow("numsrcs_n3", P.num_srcs(True{}, True{}, True{}))
    urow("numsrcs_n3b", P.num_srcs(True{}, True{}, True{}))
    urow("numsrcs_n3c", P.num_srcs(True{}, True{}, True{}))
    urow("numsrcs_n2", P.num_srcs(False{}, True{}, True{}))
    urow("numsrcs_n2b", P.num_srcs(False{}, True{}, True{}))
    urow("numsrcs_n2c", P.num_srcs(False{}, True{}, True{}))
    urow("numsrcs_n2d", P.num_srcs(False{}, False{}, True{}))
    urow("numsrcs_n1", P.num_srcs(False{}, False{}, True{}))
    urow("numsrcs_n1b", P.num_srcs(False{}, False{}, True{}))
    urow("numsrcs_n1c", P.num_srcs(False{}, False{}, True{}))
    urow("numsrcs_n0", P.num_srcs(False{}, False{}, False{}))
    urow("numsrcs_n0b", P.num_srcs(False{}, False{}, False{}))
    urow("numsrcs_n0c", P.num_srcs(False{}, False{}, False{}))
    urow("numsrcs_n0d", P.num_srcs(False{}, False{}, False{}))
# --- V  _variant_suffix ------------------------------------------------
# THE `Inst` FIXTURES for `_base_size` and `to_bytes`. Each is ONE field apart,
# so `(max(hi) + 8) // 8` (:282) crosses a byte boundary at each one, and
# F64I's 32-bit-wide `lit` at [63:32] is the widest legal field there is.
def rg_neg(+r: P.Rg) -> P.Rg: P.Rg{P.Rg.off(r), P.Rg.sz(r), Bool.not(P.Rg.neg(r)), P.Rg.ab(r), P.Rg.hi(r)}
def rg_ab(+r: P.Rg) -> P.Rg: P.Rg{P.Rg.off(r), P.Rg.sz(r), P.Rg.neg(r), True{}, P.Rg.hi(r)}
def rg_hi(+r: P.Rg) -> P.Rg: P.Rg{P.Rg.off(r), P.Rg.sz(r), P.Rg.neg(r), P.Rg.ab(r), True{}}
# a 32-bit fixture lifted into the WORD, and zero-extended rather than
# sign-extended: an instruction word is a BIT PATTERN and `H.i64_of_i32` is
# `match_hi(i32_is_neg(x))`, so it turns `BF_RAWS`' `0xDEADBEEF` into
# `0xFFFFFFFFDEADBEEF` and every `bfset_*_3735928559_*` row gains a high word
# CPython does not have. `H.i64_of_hi_lo(0, v)` says what it means.
def rg_lo(+r: P.Rg) -> P.Rg: P.Rg{P.Rg.off(r), P.Rg.sz(r), P.Rg.neg(r), P.Rg.ab(r), False{}}
def g_mod() -> IO(Unit):
  do IO<Unit>:
    srow("mod_neg_0_1", rg5(rg_neg(P.Rg{0, 1, False{}, False{}, False{}})))
    srow("mod_abs_0_1", rg5(rg_ab(P.Rg{0, 1, False{}, False{}, False{}})))
    srow("mod_h_0_1", rg5(rg_hi(P.Rg{0, 1, False{}, False{}, False{}})))
    srow("mod_l_0_1", rg5(rg_lo(P.Rg{0, 1, False{}, False{}, False{}})))
    srow("mod_neg_256_4", rg5(rg_neg(P.Rg{256, 4, False{}, False{}, False{}})))
    srow("mod_abs_256_4", rg5(rg_ab(P.Rg{256, 4, False{}, False{}, False{}})))
    srow("mod_h_256_4", rg5(rg_hi(P.Rg{256, 4, False{}, False{}, False{}})))
    srow("mod_l_256_4", rg5(rg_lo(P.Rg{256, 4, False{}, False{}, False{}})))
    srow("mod_neg_108_1", rg5(rg_neg(P.Rg{108, 1, False{}, False{}, False{}})))
    srow("mod_abs_108_1", rg5(rg_ab(P.Rg{108, 1, False{}, False{}, False{}})))
    srow("mod_h_108_1", rg5(rg_hi(P.Rg{108, 1, False{}, False{}, False{}})))
    srow("mod_l_108_1", rg5(rg_lo(P.Rg{108, 1, False{}, False{}, False{}})))
    srow("mod_neg_124_1", rg5(rg_neg(P.Rg{124, 1, False{}, False{}, False{}})))
    srow("mod_abs_124_1", rg5(rg_ab(P.Rg{124, 1, False{}, False{}, False{}})))
    srow("mod_h_124_1", rg5(rg_hi(P.Rg{124, 1, False{}, False{}, False{}})))
    srow("mod_l_124_1", rg5(rg_lo(P.Rg{124, 1, False{}, False{}, False{}})))
    srow("mod_add_5_2", rg2(U32.add(5, 3), 2))
    srow("eq_self", Bool.show(P.rg_eq(P.Rg{1, 2, False{}, False{}, False{}}, P.Rg{1, 2, False{}, False{}, False{}})))
    srow("eq_sz", Bool.show(P.rg_eq(P.Rg{1, 3, False{}, False{}, False{}}, P.Rg{1, 2, False{}, False{}, False{}})))
    srow("eq_neg", Bool.show(P.rg_eq(P.Rg{1, 2, True{}, False{}, False{}}, P.Rg{1, 2, False{}, False{}, False{}})))
    srow("eq_abs", Bool.show(P.rg_eq(P.Rg{1, 2, False{}, True{}, False{}}, P.Rg{1, 2, False{}, False{}, False{}})))
    srow("eq_hi", Bool.show(P.rg_eq(P.Rg{1, 2, False{}, False{}, True{}}, P.Rg{1, 2, False{}, False{}, False{}})))
# --- B  BitField masks and set, with both refusals ---------------------
# THE SLICES, :68-89. An inclusive Python end becomes size = end - start + 1,
# and `Reg(src, a:b)` is `Reg(a, b - a + 1)`. Four boundaries, four spellings.
def S_LO() -> U32: 0
def nat_text(v: Nat) -> String: U32.show(U32.from_nat(v))
def VCCZ_OFF() -> U32: 251
# the `op_regs` width check's exemption (:339) -- a DIFFERENT pair of ranges,
# 106..127 and 249..255. Two similar-looking exemption sets in one file, and
# they are NOT the same; the gate has a row for each boundary.
def fixed_set(enc: U32, wants: U32) -> Bool: Bool.not(U32.is_eq(enc, 0))
# `EnumBitField.encode` (:135-139): a non-member REFUSES with the ENUM's name,
# and a member outside `allowed` REFUSES with the member's own name. TWO
# refusals, and the second one is a policy -- `allowed` is per-encoding.
def INV_2PI_OFF() -> U32: 248
def TTMP_LO() -> U32: 108       # ttmp = src[108:123]
def TTMP_SZ() -> U32: 16
def LIT_OFF() -> U32: 255
# THE FLOAT CONSTANTS, :151 `_FLOAT_ENC`. Eight values, and the OFFSETS are the
# same eight `_NAMES` entries at :14 -- two spellings of one table.
# `canonical_op_bits` (:384-389) SEEDS all five canonical names at 32 bits and
# only overwrites on a canonical name -- so an operand dict with no canonical
# name leaves the seed in place, and the seed is NOT derived from anything.
def pair_off_of(nm: String) -> U32: P.nm_off.go(P.reg_pairs_n(), nm, P.reg_pairs(), False{}, P.DFLT_OFF())
def M0_OFF() -> U32: 125
# dsl.py:154-157 compares a SIZE with a RANGE count, not a bit count with a RANGE count:
#     expected_size = self._valid_range[1] - self._valid_range[0] + 1
#     actual_size   = 1 << (hi - lo + 1)
#     if actual_size != expected_size: raise RuntimeError(...)
#
# For `Fld.src("s0", 8, 0)` that is `expected_size = 512` (the register's valid range 0..511)
# against `actual_size = 1 << 9 = 512` -- EQUAL, so CPython ACCEPTS. THIS DEF READ
# `U32.is_eq(bf_bits(f), Fld.valid_n(f))`, i.e. `9 == 512`, which is FALSE, so the port REFUSED
# A FIELD CPYTHON ACCEPTS on every SRC field. `1 << bits` IS `bf_mask(f) + 1`, and `bf_mask` IS
# `(1 << bits) - 1` (`:663`), so the size is the mask plus one and nothing new is computed.
#
# not the same shape as `bf_width_ok` above, which really is a bit count against 32 -- and reading
# one as the other is the mask-versus-count confusion `al_shift_of` just had.
def SDWA_OFF() -> U32: 249
def VCC_OFF() -> U32: 106
# --- B  BitField masks and set, with both refusals ---------------------
def bfg(+f: P.Fld) -> String:
  String.concat([P.u32_text(P.Fld.hi(f)), ",", P.u32_text(P.Fld.lo(f)), ",",
                 P.u32_text(P.Fld.dflt(f)), ",", P.u32_text(P.bf_mask(f))])
# CPython's `f"{x:#010x}"` -- `0x` and EIGHT hex digits -- so a `set` row is
# compared as TEXT and a one-digit slip in one nibble is visible as text.
# `fld_encode` -- the DISPATCH over the five classes. A default BitField passes
# its value through (:110-112); a FixedBitField writes `dflt` (:126-128); the
# four typed classes run their own `encode`.
def w32(v: U32) -> H.I64: H.i64_of_hi_lo(0, v)
# `__get__` (:120-122): `(obj._raw >> self.lo) & self.mask`. The word arrives at
# its own width and only the MASKED FIELD leaves, so a field at bit 40 reads the
# bit that is actually there -- and this used to take a `U32` word, which is the
# same defect as the write side read backwards.
def g_bf() -> IO(Unit):
  do IO<Unit>:
    srow("bf_7_0", bfg(P.Fld.plain("f", 7, 0)))
    urow("bf_mask_7_0", P.bf_mask(P.Fld.plain("f", 7, 0)))
    srow("bf_15_8", bfg(P.Fld.plain("f", 15, 8)))
    urow("bf_mask_15_8", P.bf_mask(P.Fld.plain("f", 15, 8)))
    srow("bf_16_8", bfg(P.Fld.plain("f", 16, 8)))
    urow("bf_mask_16_8", P.bf_mask(P.Fld.plain("f", 16, 8)))
    srow("bf_31_16", bfg(P.Fld.plain("f", 31, 16)))
    urow("bf_mask_31_16", P.bf_mask(P.Fld.plain("f", 31, 16)))
    srow("bf_17_16", bfg(P.Fld.plain("f", 17, 16)))
    urow("bf_mask_17_16", P.bf_mask(P.Fld.plain("f", 17, 16)))
    srow("bf_23_8", bfg(P.Fld.plain("f", 23, 8)))
    urow("bf_mask_23_8", P.bf_mask(P.Fld.plain("f", 23, 8)))
    srow("bf_9_0", bfg(P.Fld.plain("f", 9, 0)))
    urow("bf_mask_9_0", P.bf_mask(P.Fld.plain("f", 9, 0)))
    srow("bf_30_24", bfg(P.Fld.plain("f", 30, 24)))
    urow("bf_mask_30_24", P.bf_mask(P.Fld.plain("f", 30, 24)))
    srow("bf_17_9", bfg(P.Fld.plain("f", 17, 9)))
    urow("bf_mask_17_9", P.bf_mask(P.Fld.plain("f", 17, 9)))
    srow("bf_30_0", bfg(P.Fld.plain("f", 30, 0)))
    urow("bf_mask_30_0", P.bf_mask(P.Fld.plain("f", 30, 0)))
    srow("bf_31_0", bfg(P.Fld.plain("f", 31, 0)))
    urow("bf_mask_31_0", P.bf_mask(P.Fld.plain("f", 31, 0)))
    srow("bf_0_0", bfg(P.Fld.plain("f", 0, 0)))
    urow("bf_mask_0_0", P.bf_mask(P.Fld.plain("f", 0, 0)))
    srow("bf_6_0", bfg(P.Fld.plain("f", 6, 0)))
    urow("bf_mask_6_0", P.bf_mask(P.Fld.plain("f", 6, 0)))
    srow("bf_40_32", bfg(P.Fld.plain("f", 40, 32)))
    urow("bf_mask_40_32", P.bf_mask(P.Fld.plain("f", 40, 32)))
    srow("bf_47_32", bfg(P.Fld.plain("f", 47, 32)))
    urow("bf_mask_47_32", P.bf_mask(P.Fld.plain("f", 47, 32)))
    srow("bf_23_16", bfg(P.Fld.plain("f", 23, 16)))
    urow("bf_mask_23_16", P.bf_mask(P.Fld.plain("f", 23, 16)))
    srow("bfset_3_0_0_0", P.bfs(P.Fld.plain("f", 3, 0), w32(0), 0))
    srow("bfset_3_0_0_1", P.bfs(P.Fld.plain("f", 3, 0), w32(0), 1))
    srow("bfset_3_0_0_7", P.bfs(P.Fld.plain("f", 3, 0), w32(0), 7))
    srow("bfset_3_0_0_8", P.bfs(P.Fld.plain("f", 3, 0), w32(0), 8))
    srow("bfset_3_0_0_255", P.bfs(P.Fld.plain("f", 3, 0), w32(0), 255))
    srow("bfset_3_0_0_4294967295", P.bfs(P.Fld.plain("f", 3, 0), w32(0), 4294967295))
    srow("bfset_3_0_3735928559_0", P.bfs(P.Fld.plain("f", 3, 0), w32(3735928559), 0))
    srow("bfset_3_0_3735928559_1", P.bfs(P.Fld.plain("f", 3, 0), w32(3735928559), 1))
    srow("bfset_3_0_3735928559_7", P.bfs(P.Fld.plain("f", 3, 0), w32(3735928559), 7))
    srow("bfset_3_0_3735928559_8", P.bfs(P.Fld.plain("f", 3, 0), w32(3735928559), 8))
    srow("bfset_3_0_3735928559_255", P.bfs(P.Fld.plain("f", 3, 0), w32(3735928559), 255))
    srow("bfset_3_0_3735928559_4294967295", P.bfs(P.Fld.plain("f", 3, 0), w32(3735928559), 4294967295))
    srow("bfset_7_4_0_0", P.bfs(P.Fld.plain("f", 7, 4), w32(0), 0))
    srow("bfset_7_4_0_1", P.bfs(P.Fld.plain("f", 7, 4), w32(0), 1))
    srow("bfset_7_4_0_7", P.bfs(P.Fld.plain("f", 7, 4), w32(0), 7))
    srow("bfset_7_4_0_8", P.bfs(P.Fld.plain("f", 7, 4), w32(0), 8))
    srow("bfset_7_4_0_255", P.bfs(P.Fld.plain("f", 7, 4), w32(0), 255))
    srow("bfset_7_4_0_4294967295", P.bfs(P.Fld.plain("f", 7, 4), w32(0), 4294967295))
    srow("bfset_7_4_3735928559_0", P.bfs(P.Fld.plain("f", 7, 4), w32(3735928559), 0))
    srow("bfset_7_4_3735928559_1", P.bfs(P.Fld.plain("f", 7, 4), w32(3735928559), 1))
    srow("bfset_7_4_3735928559_7", P.bfs(P.Fld.plain("f", 7, 4), w32(3735928559), 7))
    srow("bfset_7_4_3735928559_8", P.bfs(P.Fld.plain("f", 7, 4), w32(3735928559), 8))
    srow("bfset_7_4_3735928559_255", P.bfs(P.Fld.plain("f", 7, 4), w32(3735928559), 255))
    srow("bfset_7_4_3735928559_4294967295", P.bfs(P.Fld.plain("f", 7, 4), w32(3735928559), 4294967295))
    srow("bfset_23_8_0_0", P.bfs(P.Fld.plain("f", 23, 8), w32(0), 0))
    srow("bfset_23_8_0_1", P.bfs(P.Fld.plain("f", 23, 8), w32(0), 1))
    srow("bfset_23_8_0_7", P.bfs(P.Fld.plain("f", 23, 8), w32(0), 7))
    srow("bfset_23_8_0_8", P.bfs(P.Fld.plain("f", 23, 8), w32(0), 8))
    srow("bfset_23_8_0_255", P.bfs(P.Fld.plain("f", 23, 8), w32(0), 255))
    srow("bfset_23_8_0_4294967295", P.bfs(P.Fld.plain("f", 23, 8), w32(0), 4294967295))
    srow("bfset_23_8_3735928559_0", P.bfs(P.Fld.plain("f", 23, 8), w32(3735928559), 0))
    srow("bfset_23_8_3735928559_1", P.bfs(P.Fld.plain("f", 23, 8), w32(3735928559), 1))
    srow("bfset_23_8_3735928559_7", P.bfs(P.Fld.plain("f", 23, 8), w32(3735928559), 7))
    srow("bfset_23_8_3735928559_8", P.bfs(P.Fld.plain("f", 23, 8), w32(3735928559), 8))
    srow("bfset_23_8_3735928559_255", P.bfs(P.Fld.plain("f", 23, 8), w32(3735928559), 255))
    srow("bfset_23_8_3735928559_4294967295", P.bfs(P.Fld.plain("f", 23, 8), w32(3735928559), 4294967295))
    srow("fixed_op7", P.bfs(P.Fld.fixed("op", 7, 0, 0), w32(4294967295), 4294967295))
    srow("fixed_def_op7", P.u32_text(P.Fld.dflt(P.Fld.fixed("op", 7, 0, 0))))
    P.row("fixed_cls_op7", fixed_set(1, 0))
    srow("fixed_enc33", P.bfs(P.Fld.fixed("op", 6, 0, 33), w32(4294967295), 4294967295))
    srow("fixed_def_enc33", P.u32_text(P.Fld.dflt(P.Fld.fixed("op", 6, 0, 33))))
    P.row("fixed_cls_enc33", fixed_set(1, 0))
    srow("fixed_enc17", P.bfs(P.Fld.fixed("op", 16, 8, 0), w32(4294967295), 4294967295))
    srow("fixed_def_enc17", P.u32_text(P.Fld.dflt(P.Fld.fixed("op", 16, 8, 0))))
    P.row("fixed_cls_enc17", fixed_set(1, 0))
    # the WORD's last addressable bit and a field that starts past it, both 32 bits
# wide and both carrying a U32-NAMABLE value, because a field is at most 32 bits
# so `enc` is always below 2^32 and the thing that had to widen is the WORD, not
# the value -- `4294967296` is not even a legal literal here, which is the same
# fact from the other side.
#   `bfset_word63` is the CONTROL: [63:32] with 2^31 reaches bit 63, the port
#   places it, and both lanes answer `0x8000000000000000`.
#   `bfset_word64` is the guard: [95:64] starts at bit 64, CPython's word is
#   `0x10000000000000000` -- past the end of any 64-bit word -- and the port
#   REFUSES, loudly, because `H.i64_shl` would have written a zero and said
#   nothing.
    srow("bfset_word63", P.bfs(P.Fld.plain("lit", 63, 32), w32(0), 2147483648))
    srow("bfset_word64", P.bfs(P.Fld.plain("lit", 95, 64), w32(0), 1))
# --- E  the five field classes' encode -- one negative per positive ----
def OFF_OFF() -> U32: 124
def DPP_OFF() -> U32: 250
def NULL_OFF() -> U32: 124
def reg_off_of(nm: String) -> U32: P.nm_off.go(P.reg_names_n(), nm, P.reg_names(), False{}, P.DFLT_OFF())
def g_tables() -> IO(Unit):
  do IO<Unit>:
    srow("names_count", nat_text(P.reg_names_n()))
    srow("names_rev_count", nat_text(P.reg_names_n()))
    srow("names_fwd_102", P.reg_name_of(102))
    srow("names_fwd_103", P.reg_name_of(103))
    srow("names_fwd_104", P.reg_name_of(104))
    srow("names_fwd_105", P.reg_name_of(105))
    srow("names_fwd_106", P.reg_name_of(106))
    srow("names_fwd_107", P.reg_name_of(107))
    srow("names_fwd_124", P.reg_name_of(124))
    srow("names_fwd_125", P.reg_name_of(125))
    srow("names_fwd_126", P.reg_name_of(126))
    srow("names_fwd_127", P.reg_name_of(127))
    srow("names_fwd_233", P.reg_name_of(233))
    srow("names_fwd_234", P.reg_name_of(234))
    srow("names_fwd_235", P.reg_name_of(235))
    srow("names_fwd_236", P.reg_name_of(236))
    srow("names_fwd_237", P.reg_name_of(237))
    srow("names_fwd_238", P.reg_name_of(238))
    srow("names_fwd_240", P.reg_name_of(240))
    srow("names_fwd_241", P.reg_name_of(241))
    srow("names_fwd_242", P.reg_name_of(242))
    srow("names_fwd_243", P.reg_name_of(243))
    srow("names_fwd_244", P.reg_name_of(244))
    srow("names_fwd_245", P.reg_name_of(245))
    srow("names_fwd_246", P.reg_name_of(246))
    srow("names_fwd_247", P.reg_name_of(247))
    srow("names_fwd_248", P.reg_name_of(248))
    srow("names_fwd_249", P.reg_name_of(249))
    srow("names_fwd_250", P.reg_name_of(250))
    srow("names_fwd_251", P.reg_name_of(251))
    srow("names_fwd_252", P.reg_name_of(252))
    srow("names_fwd_253", P.reg_name_of(253))
    srow("names_fwd_254", P.reg_name_of(254))
    srow("names_fwd_255", P.reg_name_of(255))
    srow("names_rev_FLAT_SCRATCH_LO", P.u32_text(reg_off_of("FLAT_SCRATCH_LO")))
    srow("names_rev_FLAT_SCRATCH_HI", P.u32_text(reg_off_of("FLAT_SCRATCH_HI")))
    srow("names_rev_XNACK_MASK_LO", P.u32_text(reg_off_of("XNACK_MASK_LO")))
    srow("names_rev_XNACK_MASK_HI", P.u32_text(reg_off_of("XNACK_MASK_HI")))
    srow("names_rev_VCC_LO", P.u32_text(reg_off_of("VCC_LO")))
    srow("names_rev_VCC_HI", P.u32_text(reg_off_of("VCC_HI")))
    srow("names_rev_NULL", P.u32_text(reg_off_of("NULL")))
    srow("names_rev_M0", P.u32_text(reg_off_of("M0")))
    srow("names_rev_EXEC_LO", P.u32_text(reg_off_of("EXEC_LO")))
    srow("names_rev_EXEC_HI", P.u32_text(reg_off_of("EXEC_HI")))
    srow("names_rev_DPP8", P.u32_text(reg_off_of("DPP8")))
    srow("names_rev_DPP8FI", P.u32_text(reg_off_of("DPP8FI")))
    srow("names_rev_SHARED_BASE", P.u32_text(reg_off_of("SHARED_BASE")))
    srow("names_rev_SHARED_LIMIT", P.u32_text(reg_off_of("SHARED_LIMIT")))
    srow("names_rev_PRIVATE_BASE", P.u32_text(reg_off_of("PRIVATE_BASE")))
    srow("names_rev_PRIVATE_LIMIT", P.u32_text(reg_off_of("PRIVATE_LIMIT")))
    srow("names_rev_0.5", P.u32_text(reg_off_of("0.5")))
    srow("names_rev_-0.5", P.u32_text(reg_off_of("-0.5")))
    srow("names_rev_1.0", P.u32_text(reg_off_of("1.0")))
    srow("names_rev_-1.0", P.u32_text(reg_off_of("-1.0")))
    srow("names_rev_2.0", P.u32_text(reg_off_of("2.0")))
    srow("names_rev_-2.0", P.u32_text(reg_off_of("-2.0")))
    srow("names_rev_4.0", P.u32_text(reg_off_of("4.0")))
    srow("names_rev_-4.0", P.u32_text(reg_off_of("-4.0")))
    srow("names_rev_INV_2PI", P.u32_text(reg_off_of("INV_2PI")))
    srow("names_rev_SDWA", P.u32_text(reg_off_of("SDWA")))
    srow("names_rev_DPP", P.u32_text(reg_off_of("DPP")))
    srow("names_rev_VCCZ", P.u32_text(reg_off_of("VCCZ")))
    srow("names_rev_EXECZ", P.u32_text(reg_off_of("EXECZ")))
    srow("names_rev_SCC", P.u32_text(reg_off_of("SCC")))
    srow("names_rev_SRC_LDS_DIRECT", P.u32_text(reg_off_of("SRC_LDS_DIRECT")))
    srow("names_rev_LIT", P.u32_text(reg_off_of("LIT")))
    srow("pairs_count", nat_text(P.reg_pairs_n()))
    srow("pairs_fwd_106", P.pair_name_of(106))
    srow("pairs_fwd_126", P.pair_name_of(126))
    srow("pairs_rev_VCC", P.u32_text(pair_off_of("VCC")))
    srow("pairs_rev_EXEC", P.u32_text(pair_off_of("EXEC")))
    srow("names_rev_0.5", P.u32_text(reg_off_of("0.5")))
    srow("names_rev_-0.5", P.u32_text(reg_off_of("-0.5")))
    srow("names_rev_1.0", P.u32_text(reg_off_of("1.0")))
    srow("names_rev_-1.0", P.u32_text(reg_off_of("-1.0")))
    srow("names_rev_2.0", P.u32_text(reg_off_of("2.0")))
    srow("names_rev_-2.0", P.u32_text(reg_off_of("-2.0")))
    srow("names_rev_4.0", P.u32_text(reg_off_of("4.0")))
    srow("names_rev_-4.0", P.u32_text(reg_off_of("-4.0")))
    srow("float_enc_count", nat_text(P.float_enc_n()))
    srow("floatenc_r_240", P.float_enc_of_text("0.5"))
    srow("floatenc_r_241", P.float_enc_of_text("-0.5"))
    srow("floatenc_r_242", P.float_enc_of_text("1.0"))
    srow("floatenc_r_243", P.float_enc_of_text("-1.0"))
    srow("floatenc_r_244", P.float_enc_of_text("2.0"))
    srow("floatenc_r_245", P.float_enc_of_text("-2.0"))
    srow("floatenc_r_246", P.float_enc_of_text("4.0"))
    srow("floatenc_r_247", P.float_enc_of_text("-4.0"))
    srow("canon_src0", P.canon_of_text(canon_of("src0")))
    srow("canon_vsrc0", P.canon_of_text(canon_of("vsrc0")))
    srow("canon_ssrc0", P.canon_of_text(canon_of("ssrc0")))
    srow("canon_src1", P.canon_of_text(canon_of("src1")))
    srow("canon_vsrc1", P.canon_of_text(canon_of("vsrc1")))
    srow("canon_ssrc1", P.canon_of_text(canon_of("ssrc1")))
    srow("canon_src2", P.canon_of_text(canon_of("src2")))
    srow("canon_vdst", P.canon_of_text(canon_of("vdst")))
    srow("canon_sdst", P.canon_of_text(canon_of("sdst")))
    srow("canon_sdata", P.canon_of_text(canon_of("sdata")))
    srow("canon_data", P.canon_of_text(canon_of("data")))
    srow("canon_vdata", P.canon_of_text(canon_of("vdata")))
    srow("canon_data0", P.canon_of_text(canon_of("data0")))
    srow("canon_vsrc", P.canon_of_text(canon_of("vsrc")))
    srow("canon_op", P.canon_of_text(canon_of("op")))
    srow("canon_off", P.canon_of_text(canon_of("off")))
    srow("canon_abs", P.canon_of_text(canon_of("abs")))
    srow("canon_neg", P.canon_of_text(canon_of("neg")))
    srow("canon_opsel", P.canon_of_text(canon_of("opsel")))
    srow("canon_src3", P.canon_of_text(canon_of("src3")))
    srow("canon_Src0", P.canon_of_text(canon_of("Src0")))
    srow("canon_Src1", P.canon_of_text(canon_of("Src1")))
    srow("canon_S0", P.canon_of_text(canon_of("S0")))
    srow("canon_xsrc0", P.canon_of_text(canon_of("xsrc0")))
    srow("canon_rsrc", P.canon_of_text(canon_of("rsrc")))
    srow("canon_isrc", P.canon_of_text(canon_of("isrc")))
    srow("canon_sdst_x", P.canon_of_text(canon_of("sdst_x")))
    srow("canon_S0", P.canon_of_text(canon_of("S0")))
    srow("canon_out_s0", P.canon_of_text(canon_of("s0")))
    srow("canon_out_s1", P.canon_of_text(canon_of("s1")))
    srow("canon_out_s2", P.canon_of_text(canon_of("s2")))
    srow("canon_out_d", P.canon_of_text(canon_of("d")))
    srow("canon_out_data", P.canon_of_text(canon_of("data")))
    srow("names_fwd_absent", P.reg_name_of(209))
    srow("names_rev_absent", P.u32_text(reg_off_of("NOSUCHREG")))
    srow("pairs_rev_absent", P.u32_text(pair_off_of("NOSUCHPAIR")))
    srow("floatenc_r_absent", P.float_enc_of_text("3.0"))
# --- c the register constants and the space boundaries ----------------
# THE ORDER FIXTURES. Two fields at the SAME bits with different names: `set` is
# a masked overwrite, so the LAST write wins and the field ORDER decides the
# word. Swap the two and every value-identical gate row on this file still
# passes, which is exactly why this fixture exists -- a transposed pair in
# `_fields` is otherwise invisible to a count, to a graph shape, and to a diff of
# the final word.
def DPP16_OFF() -> U32: 250
# --- N  _needs_literal -------------------------------------------------
def V_SZ() -> U32: 256
# THE NAMED REGISTERS. Each is `src[N]`, i.e. offset N, size 1. NULL and OFF
# are the SAME register (:74 `NULL = OFF = src[124]`), and DPP and DPP16 are
# the same register (:83 `DPP = DPP16 = src[250]`); the aliasing is the point.
# the raw-word fallback, for a class with NO declared cbsz/blgp (:373-374)
def EXEC_OFF() -> U32: 126
def EXECZ_OFF() -> U32: 252
# `vdst` given TWO registers where `op_regs` says one. The two rows below are the
# EXEMPTION and its opposite: `sdst` at 4 wide with offset 124 is exempt
# (:339's `106 <= offset <= 127`), `src0` at 8 wide with offset 250 is exempt
# (`:339`'s `249 <= offset <= 255`), and `vdst` at 2 wide is NOT.
def SRC_LDS_DIRECT_OFF() -> U32: 254
def S_SZ() -> U32: 106
def g_const() -> IO(Unit):
  do IO<Unit>:
    srow("const_VCC_LO", rg5(P.Rg{P.VCC_LO(), 1, False{}, False{}, False{}}))
    srow("const_VCC_HI", rg5(P.Rg{P.VCC_HI(), 1, False{}, False{}, False{}}))
    srow("const_NULL", rg5(P.Rg{NULL_OFF(), 1, False{}, False{}, False{}}))
    srow("const_OFF", rg5(P.Rg{OFF_OFF(), 1, False{}, False{}, False{}}))
    srow("const_M0", rg5(P.Rg{M0_OFF(), 1, False{}, False{}, False{}}))
    srow("const_EXEC_LO", rg5(P.Rg{P.EXEC_LO(), 1, False{}, False{}, False{}}))
    srow("const_EXEC_HI", rg5(P.Rg{P.EXEC_HI(), 1, False{}, False{}, False{}}))
    srow("const_INV_2PI", rg5(P.Rg{INV_2PI_OFF(), 1, False{}, False{}, False{}}))
    srow("const_SDWA", rg5(P.Rg{SDWA_OFF(), 1, False{}, False{}, False{}}))
    srow("const_DPP", rg5(P.Rg{DPP_OFF(), 1, False{}, False{}, False{}}))
    srow("const_DPP16", rg5(P.Rg{DPP16_OFF(), 1, False{}, False{}, False{}}))
    srow("const_VCCZ", rg5(P.Rg{VCCZ_OFF(), 1, False{}, False{}, False{}}))
    srow("const_EXECZ", rg5(P.Rg{EXECZ_OFF(), 1, False{}, False{}, False{}}))
    srow("const_SCC", rg5(P.Rg{SCC_OFF(), 1, False{}, False{}, False{}}))
    srow("const_SRC_LDS_DIRECT", rg5(P.Rg{SRC_LDS_DIRECT_OFF(), 1, False{}, False{}, False{}}))
    srow("const_LIT", rg5(P.Rg{LIT_OFF(), 1, False{}, False{}, False{}}))
    P.row("alias_null_off", U32.is_eq(NULL_OFF(), OFF_OFF()))
    P.row("alias_dpp_dpp16", U32.is_eq(DPP_OFF(), DPP16_OFF()))
    P.row("alias_vcc_pair", U32.is_eq(VCC_OFF(), P.VCC_LO()))
    P.row("alias_exec_pair", U32.is_eq(EXEC_OFF(), P.EXEC_LO()))
    srow("const_src", rg5(P.Rg{P.SRC_LO(), P.SRC_SZ(), False{}, False{}, False{}}))
    srow("const_s", rg5(P.Rg{S_LO(), S_SZ(), False{}, False{}, False{}}))
    srow("const_ttmp", rg5(P.Rg{TTMP_LO(), TTMP_SZ(), False{}, False{}, False{}}))
    srow("const_v", rg5(P.Rg{P.V_LO(), V_SZ(), False{}, False{}, False{}}))
    srow("src_at_0", rg2(0, 1))
    srow("src_at_1", rg2(1, 1))
    srow("src_at_63", rg2(63, 1))
    srow("src_at_104", rg2(104, 1))
    srow("src_at_105", rg2(105, 1))
    srow("src_at_106", rg2(106, 1))
    srow("src_at_107", rg2(107, 1))
    srow("src_at_108", rg2(108, 1))
    srow("src_at_123", rg2(123, 1))
    srow("src_at_124", rg2(124, 1))
    srow("src_at_125", rg2(125, 1))
    srow("src_at_126", rg2(126, 1))
    srow("src_at_127", rg2(127, 1))
    srow("src_at_128", rg2(128, 1))
    srow("src_at_129", rg2(129, 1))
    srow("src_at_192", rg2(192, 1))
    srow("src_at_193", rg2(193, 1))
    srow("src_at_208", rg2(208, 1))
    srow("src_at_209", rg2(209, 1))
    srow("src_at_239", rg2(239, 1))
    srow("src_at_240", rg2(240, 1))
    srow("src_at_248", rg2(248, 1))
    srow("src_at_255", rg2(255, 1))
    srow("src_at_256", rg2(256, 1))
    srow("src_at_257", rg2(257, 1))
    srow("src_at_510", rg2(510, 1))
    srow("src_at_511", rg2(511, 1))
# --- R  Reg.__getitem__ -- index, slice, and BOTH refusals -------------
def g_lit() -> IO(Unit):
  do IO<Unit>:
    P.row("needs_lit_reg_0", P.needs_literal(P.Ov.reg(0, 1, False{}, False{}, False{})))
    P.row("needs_lit_reg_1", P.needs_literal(P.Ov.reg(1, 1, False{}, False{}, False{})))
    P.row("needs_lit_reg_105", P.needs_literal(P.Ov.reg(105, 1, False{}, False{}, False{})))
    P.row("needs_lit_reg_128", P.needs_literal(P.Ov.reg(128, 1, False{}, False{}, False{})))
    P.row("needs_lit_reg_240", P.needs_literal(P.Ov.reg(240, 1, False{}, False{}, False{})))
    P.row("needs_lit_reg_255", P.needs_literal(P.Ov.reg(255, 1, False{}, False{}, False{})))
    P.row("needs_lit_reg_256", P.needs_literal(P.Ov.reg(256, 1, False{}, False{}, False{})))
    P.row("needs_lit_reg_511", P.needs_literal(P.Ov.reg(511, 1, False{}, False{}, False{})))
    P.row("needs_lit_int_0", P.needs_literal(P.Ov.int(0)))
    P.row("needs_lit_int_1", P.needs_literal(P.Ov.int(1)))
    P.row("needs_lit_int_63", P.needs_literal(P.Ov.int(63)))
    P.row("needs_lit_int_64", P.needs_literal(P.Ov.int(64)))
    P.row("needs_lit_int_65", P.needs_literal(P.Ov.int(65)))
    P.row("needs_lit_int_100", P.needs_literal(P.Ov.int(100)))
    P.row("needs_lit_int_4294967295", P.needs_literal(P.Ov.int(4294967295)))
    P.row("needs_lit_int_4294967280", P.needs_literal(P.Ov.int(4294967280)))
    P.row("needs_lit_int_4294967279", P.needs_literal(P.Ov.int(4294967279)))
    P.row("needs_lit_none", P.needs_literal(P.Ov.none()))
# --- I  the Inst field order, _base_size, and the raw-word walk --------
def g_fmt() -> IO(Unit):
  do IO<Unit>:
    srow("fmt_0_1", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_0_1", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_0_1", P.Res.msg(P.reg_fmt(P.Rg{0, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_0_4", P.Res.s(P.reg_fmt(P.Rg{0, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_0_4", P.Res.s(P.reg_fmt(P.Rg{0, 4, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_0_4", P.Res.msg(P.reg_fmt(P.Rg{0, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_1_2", P.Res.s(P.reg_fmt(P.Rg{1, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_1_2", P.Res.s(P.reg_fmt(P.Rg{1, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_1_2", P.Res.msg(P.reg_fmt(P.Rg{1, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_105_1", P.Res.s(P.reg_fmt(P.Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_105_1", P.Res.s(P.reg_fmt(P.Rg{105, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_105_1", P.Res.msg(P.reg_fmt(P.Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_256_1", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_256_1", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_256_1", P.Res.msg(P.reg_fmt(P.Rg{256, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_256_4", P.Res.s(P.reg_fmt(P.Rg{256, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_256_4", P.Res.s(P.reg_fmt(P.Rg{256, 4, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_256_4", P.Res.msg(P.reg_fmt(P.Rg{256, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_300_2", P.Res.s(P.reg_fmt(P.Rg{300, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_300_2", P.Res.s(P.reg_fmt(P.Rg{300, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_300_2", P.Res.msg(P.reg_fmt(P.Rg{300, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_511_1", P.Res.s(P.reg_fmt(P.Rg{511, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_511_1", P.Res.s(P.reg_fmt(P.Rg{511, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_511_1", P.Res.msg(P.reg_fmt(P.Rg{511, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_106_2", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_106_2", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_106_2", P.Res.msg(P.reg_fmt(P.Rg{106, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_126_2", P.Res.s(P.reg_fmt(P.Rg{126, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_126_2", P.Res.s(P.reg_fmt(P.Rg{126, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_126_2", P.Res.msg(P.reg_fmt(P.Rg{126, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_106_1", P.Res.s(P.reg_fmt(P.Rg{106, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_106_1", P.Res.s(P.reg_fmt(P.Rg{106, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_106_1", P.Res.msg(P.reg_fmt(P.Rg{106, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_126_1", P.Res.s(P.reg_fmt(P.Rg{126, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_126_1", P.Res.s(P.reg_fmt(P.Rg{126, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_126_1", P.Res.msg(P.reg_fmt(P.Rg{126, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_102_1", P.Res.s(P.reg_fmt(P.Rg{102, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_102_1", P.Res.s(P.reg_fmt(P.Rg{102, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_102_1", P.Res.msg(P.reg_fmt(P.Rg{102, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_103_2", P.Res.s(P.reg_fmt(P.Rg{103, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_103_2", P.Res.s(P.reg_fmt(P.Rg{103, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_103_2", P.Res.msg(P.reg_fmt(P.Rg{103, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_104_1", P.Res.s(P.reg_fmt(P.Rg{104, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_104_1", P.Res.s(P.reg_fmt(P.Rg{104, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_104_1", P.Res.msg(P.reg_fmt(P.Rg{104, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_105_1", P.Res.s(P.reg_fmt(P.Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_105_1", P.Res.s(P.reg_fmt(P.Rg{105, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_105_1", P.Res.msg(P.reg_fmt(P.Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_107_1", P.Res.s(P.reg_fmt(P.Rg{107, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_107_1", P.Res.s(P.reg_fmt(P.Rg{107, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_107_1", P.Res.msg(P.reg_fmt(P.Rg{107, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_233_1", P.Res.s(P.reg_fmt(P.Rg{233, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_233_1", P.Res.s(P.reg_fmt(P.Rg{233, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_233_1", P.Res.msg(P.reg_fmt(P.Rg{233, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_234_1", P.Res.s(P.reg_fmt(P.Rg{234, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_234_1", P.Res.s(P.reg_fmt(P.Rg{234, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_234_1", P.Res.msg(P.reg_fmt(P.Rg{234, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_235_1", P.Res.s(P.reg_fmt(P.Rg{235, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_235_1", P.Res.s(P.reg_fmt(P.Rg{235, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_235_1", P.Res.msg(P.reg_fmt(P.Rg{235, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_236_1", P.Res.s(P.reg_fmt(P.Rg{236, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_236_1", P.Res.s(P.reg_fmt(P.Rg{236, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_236_1", P.Res.msg(P.reg_fmt(P.Rg{236, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_237_1", P.Res.s(P.reg_fmt(P.Rg{237, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_237_1", P.Res.s(P.reg_fmt(P.Rg{237, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_237_1", P.Res.msg(P.reg_fmt(P.Rg{237, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_238_1", P.Res.s(P.reg_fmt(P.Rg{238, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_238_1", P.Res.s(P.reg_fmt(P.Rg{238, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_238_1", P.Res.msg(P.reg_fmt(P.Rg{238, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_240_1", P.Res.s(P.reg_fmt(P.Rg{240, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_240_1", P.Res.s(P.reg_fmt(P.Rg{240, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_240_1", P.Res.msg(P.reg_fmt(P.Rg{240, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_241_1", P.Res.s(P.reg_fmt(P.Rg{241, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_241_1", P.Res.s(P.reg_fmt(P.Rg{241, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_241_1", P.Res.msg(P.reg_fmt(P.Rg{241, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_242_1", P.Res.s(P.reg_fmt(P.Rg{242, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_242_1", P.Res.s(P.reg_fmt(P.Rg{242, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_242_1", P.Res.msg(P.reg_fmt(P.Rg{242, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_243_1", P.Res.s(P.reg_fmt(P.Rg{243, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_243_1", P.Res.s(P.reg_fmt(P.Rg{243, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_243_1", P.Res.msg(P.reg_fmt(P.Rg{243, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_244_1", P.Res.s(P.reg_fmt(P.Rg{244, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_244_1", P.Res.s(P.reg_fmt(P.Rg{244, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_244_1", P.Res.msg(P.reg_fmt(P.Rg{244, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_245_1", P.Res.s(P.reg_fmt(P.Rg{245, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_245_1", P.Res.s(P.reg_fmt(P.Rg{245, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_245_1", P.Res.msg(P.reg_fmt(P.Rg{245, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_246_1", P.Res.s(P.reg_fmt(P.Rg{246, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_246_1", P.Res.s(P.reg_fmt(P.Rg{246, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_246_1", P.Res.msg(P.reg_fmt(P.Rg{246, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_247_1", P.Res.s(P.reg_fmt(P.Rg{247, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_247_1", P.Res.s(P.reg_fmt(P.Rg{247, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_247_1", P.Res.msg(P.reg_fmt(P.Rg{247, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_248_1", P.Res.s(P.reg_fmt(P.Rg{248, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_248_1", P.Res.s(P.reg_fmt(P.Rg{248, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_248_1", P.Res.msg(P.reg_fmt(P.Rg{248, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_249_1", P.Res.s(P.reg_fmt(P.Rg{249, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_249_1", P.Res.s(P.reg_fmt(P.Rg{249, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_249_1", P.Res.msg(P.reg_fmt(P.Rg{249, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_250_1", P.Res.s(P.reg_fmt(P.Rg{250, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_250_1", P.Res.s(P.reg_fmt(P.Rg{250, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_250_1", P.Res.msg(P.reg_fmt(P.Rg{250, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_251_1", P.Res.s(P.reg_fmt(P.Rg{251, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_251_1", P.Res.s(P.reg_fmt(P.Rg{251, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_251_1", P.Res.msg(P.reg_fmt(P.Rg{251, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_252_1", P.Res.s(P.reg_fmt(P.Rg{252, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_252_1", P.Res.s(P.reg_fmt(P.Rg{252, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_252_1", P.Res.msg(P.reg_fmt(P.Rg{252, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_253_1", P.Res.s(P.reg_fmt(P.Rg{253, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_253_1", P.Res.s(P.reg_fmt(P.Rg{253, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_253_1", P.Res.msg(P.reg_fmt(P.Rg{253, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_254_1", P.Res.s(P.reg_fmt(P.Rg{254, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_254_1", P.Res.s(P.reg_fmt(P.Rg{254, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_254_1", P.Res.msg(P.reg_fmt(P.Rg{254, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_255_1", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_255_1", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_255_1", P.Res.msg(P.reg_fmt(P.Rg{255, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_108_1", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_108_1", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_108_1", P.Res.msg(P.reg_fmt(P.Rg{108, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_108_4", P.Res.s(P.reg_fmt(P.Rg{108, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_108_4", P.Res.s(P.reg_fmt(P.Rg{108, 4, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_108_4", P.Res.msg(P.reg_fmt(P.Rg{108, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_115_2", P.Res.s(P.reg_fmt(P.Rg{115, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_115_2", P.Res.s(P.reg_fmt(P.Rg{115, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_115_2", P.Res.msg(P.reg_fmt(P.Rg{115, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_123_1", P.Res.s(P.reg_fmt(P.Rg{123, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_123_1", P.Res.s(P.reg_fmt(P.Rg{123, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_123_1", P.Res.msg(P.reg_fmt(P.Rg{123, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_128_1", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_128_1", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_128_1", P.Res.msg(P.reg_fmt(P.Rg{128, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_129_1", P.Res.s(P.reg_fmt(P.Rg{129, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_129_1", P.Res.s(P.reg_fmt(P.Rg{129, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_129_1", P.Res.msg(P.reg_fmt(P.Rg{129, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_160_1", P.Res.s(P.reg_fmt(P.Rg{160, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_160_1", P.Res.s(P.reg_fmt(P.Rg{160, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_160_1", P.Res.msg(P.reg_fmt(P.Rg{160, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_192_1", P.Res.s(P.reg_fmt(P.Rg{192, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_192_1", P.Res.s(P.reg_fmt(P.Rg{192, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_192_1", P.Res.msg(P.reg_fmt(P.Rg{192, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_193_1", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_193_1", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_193_1", P.Res.msg(P.reg_fmt(P.Rg{193, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_194_1", P.Res.s(P.reg_fmt(P.Rg{194, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_194_1", P.Res.s(P.reg_fmt(P.Rg{194, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_194_1", P.Res.msg(P.reg_fmt(P.Rg{194, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_207_1", P.Res.s(P.reg_fmt(P.Rg{207, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_207_1", P.Res.s(P.reg_fmt(P.Rg{207, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_207_1", P.Res.msg(P.reg_fmt(P.Rg{207, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_208_1", P.Res.s(P.reg_fmt(P.Rg{208, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_208_1", P.Res.s(P.reg_fmt(P.Rg{208, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_208_1", P.Res.msg(P.reg_fmt(P.Rg{208, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_209_1", P.Res.s(P.reg_fmt(P.Rg{209, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_209_1", P.Res.s(P.reg_fmt(P.Rg{209, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_209_1", P.Res.msg(P.reg_fmt(P.Rg{209, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_512_1", P.Res.s(P.reg_fmt(P.Rg{512, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_512_1", P.Res.s(P.reg_fmt(P.Rg{512, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_512_1", P.Res.msg(P.reg_fmt(P.Rg{512, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_108_16", P.Res.s(P.reg_fmt(P.Rg{108, 16, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_108_16", P.Res.s(P.reg_fmt(P.Rg{108, 16, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_108_16", P.Res.msg(P.reg_fmt(P.Rg{108, 16, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_256_2", P.Res.s(P.reg_fmt(P.Rg{256, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_256_2", P.Res.s(P.reg_fmt(P.Rg{256, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_256_2", P.Res.msg(P.reg_fmt(P.Rg{256, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_106_4", P.Res.s(P.reg_fmt(P.Rg{106, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_106_4", P.Res.s(P.reg_fmt(P.Rg{106, 4, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_106_4", P.Res.msg(P.reg_fmt(P.Rg{106, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmod_0_1_000", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_000", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_001", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_001", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_010", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_010", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_011", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_011", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_100", P.Res.s(P.reg_fmt(P.Rg{0, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_100", P.Res.s(P.reg_fmt(P.Rg{0, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_101", P.Res.s(P.reg_fmt(P.Rg{0, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_101", P.Res.s(P.reg_fmt(P.Rg{0, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_110", P.Res.s(P.reg_fmt(P.Rg{0, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_110", P.Res.s(P.reg_fmt(P.Rg{0, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_111", P.Res.s(P.reg_fmt(P.Rg{0, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_111", P.Res.s(P.reg_fmt(P.Rg{0, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_000", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_000", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_001", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_001", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_010", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_010", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_011", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_011", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_100", P.Res.s(P.reg_fmt(P.Rg{256, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_100", P.Res.s(P.reg_fmt(P.Rg{256, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_101", P.Res.s(P.reg_fmt(P.Rg{256, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_101", P.Res.s(P.reg_fmt(P.Rg{256, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_110", P.Res.s(P.reg_fmt(P.Rg{256, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_110", P.Res.s(P.reg_fmt(P.Rg{256, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_111", P.Res.s(P.reg_fmt(P.Rg{256, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_111", P.Res.s(P.reg_fmt(P.Rg{256, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_000", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_000", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_001", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_001", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_010", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_010", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_011", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_011", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_100", P.Res.s(P.reg_fmt(P.Rg{124, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_100", P.Res.s(P.reg_fmt(P.Rg{124, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_101", P.Res.s(P.reg_fmt(P.Rg{124, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_101", P.Res.s(P.reg_fmt(P.Rg{124, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_110", P.Res.s(P.reg_fmt(P.Rg{124, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_110", P.Res.s(P.reg_fmt(P.Rg{124, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_111", P.Res.s(P.reg_fmt(P.Rg{124, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_111", P.Res.s(P.reg_fmt(P.Rg{124, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_000", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_000", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_001", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_001", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_010", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_010", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_011", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_011", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_100", P.Res.s(P.reg_fmt(P.Rg{106, 2, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_100", P.Res.s(P.reg_fmt(P.Rg{106, 2, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_101", P.Res.s(P.reg_fmt(P.Rg{106, 2, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_101", P.Res.s(P.reg_fmt(P.Rg{106, 2, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_110", P.Res.s(P.reg_fmt(P.Rg{106, 2, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_110", P.Res.s(P.reg_fmt(P.Rg{106, 2, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_111", P.Res.s(P.reg_fmt(P.Rg{106, 2, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_111", P.Res.s(P.reg_fmt(P.Rg{106, 2, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_000", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_000", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_001", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_001", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_010", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_010", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_011", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_011", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_100", P.Res.s(P.reg_fmt(P.Rg{108, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_100", P.Res.s(P.reg_fmt(P.Rg{108, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_101", P.Res.s(P.reg_fmt(P.Rg{108, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_101", P.Res.s(P.reg_fmt(P.Rg{108, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_110", P.Res.s(P.reg_fmt(P.Rg{108, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_110", P.Res.s(P.reg_fmt(P.Rg{108, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_111", P.Res.s(P.reg_fmt(P.Rg{108, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_111", P.Res.s(P.reg_fmt(P.Rg{108, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_000", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_000", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_001", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_001", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_010", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_010", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_011", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_011", P.Res.s(P.reg_fmt(P.Rg{128, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_100", P.Res.s(P.reg_fmt(P.Rg{128, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_100", P.Res.s(P.reg_fmt(P.Rg{128, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_101", P.Res.s(P.reg_fmt(P.Rg{128, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_101", P.Res.s(P.reg_fmt(P.Rg{128, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_110", P.Res.s(P.reg_fmt(P.Rg{128, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_110", P.Res.s(P.reg_fmt(P.Rg{128, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_111", P.Res.s(P.reg_fmt(P.Rg{128, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_111", P.Res.s(P.reg_fmt(P.Rg{128, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_000", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_000", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_001", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_001", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_010", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_010", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_011", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_011", P.Res.s(P.reg_fmt(P.Rg{193, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_100", P.Res.s(P.reg_fmt(P.Rg{193, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_100", P.Res.s(P.reg_fmt(P.Rg{193, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_101", P.Res.s(P.reg_fmt(P.Rg{193, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_101", P.Res.s(P.reg_fmt(P.Rg{193, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_110", P.Res.s(P.reg_fmt(P.Rg{193, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_110", P.Res.s(P.reg_fmt(P.Rg{193, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_111", P.Res.s(P.reg_fmt(P.Rg{193, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_111", P.Res.s(P.reg_fmt(P.Rg{193, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_000", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_000", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_001", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_001", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_010", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_010", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_011", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_011", P.Res.s(P.reg_fmt(P.Rg{255, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_100", P.Res.s(P.reg_fmt(P.Rg{255, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_100", P.Res.s(P.reg_fmt(P.Rg{255, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_101", P.Res.s(P.reg_fmt(P.Rg{255, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_101", P.Res.s(P.reg_fmt(P.Rg{255, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_110", P.Res.s(P.reg_fmt(P.Rg{255, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_110", P.Res.s(P.reg_fmt(P.Rg{255, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_111", P.Res.s(P.reg_fmt(P.Rg{255, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_111", P.Res.s(P.reg_fmt(P.Rg{255, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmt_szov_0_1_4", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, False{}, False{}}, 4, False{}, False{})))
    srow("fmt_szov_256_1_2", P.Res.s(P.reg_fmt(P.Rg{256, 1, False{}, False{}, False{}}, 2, False{}, False{})))
    srow("fmt_szov_106_2_2", P.Res.s(P.reg_fmt(P.Rg{106, 2, False{}, False{}, False{}}, 2, False{}, False{})))
    srow("fmt_szov_124_1_4", P.Res.s(P.reg_fmt(P.Rg{124, 1, False{}, False{}, False{}}, 4, False{}, False{})))
    srow("fmt_szov_108_1_2", P.Res.s(P.reg_fmt(P.Rg{108, 1, False{}, False{}, False{}}, 2, False{}, False{})))
    srow("fmt_szov_0_1_0", P.Res.s(P.reg_fmt(P.Rg{0, 1, False{}, False{}, False{}}, 0, False{}, False{})))
# --- M  the modifier flags: __neg__ / __abs__ / .h / .l ----------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- g_tables()
    b : Unit <- g_const()
    c : Unit <- g_get()
    d : Unit <- g_fmt()
    e : Unit <- g_mod()
    f : Unit <- g_bf()
    +g : Unit <- g_enc()
    h : Unit <- g_lit()
    +i : Unit <- g_inst()
    +j : Unit <- g_ops()
    +k : Unit <- g_vs()
    IO.print("dsl-done=1")
