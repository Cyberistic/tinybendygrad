# ops-core.bend -- the FIRST GATE for uop/ops.bend, over the CONST-IDENTITY claims.
#
#   .venv/bin/python gates/ops-core-gate.py
#
# WHY A GATE OVER ALREADY-WRITTEN TESTS. `ops.bend` carries 55 in-file `t_*` tests and until
# now NO gate at all, so every one of them was a claim with no denominator: written, believed,
# unverified. The project rule is that nothing is ported until it has a CPython-confirmed row,
# and the cheapest honest way to get one for code that already exists is to make the oracle
# compute the SAME property from tinygrad and let the diff decide. No new port code is written
# here -- the driver CALLS the five tests the file already has.
#
# WHY FIVE AND NOT FIFTY-FIVE. These five are the CONST-identity cluster, and they are the
# cluster where the port's own notes record CPython's answers MEASURED on the live tree, so the
# oracle is a restatement of a measurement rather than a guess. The rest of the 55 need
# `simplify` or arena machinery that is still behind its own markers; gating them now would mean
# gating a wall. A gate over the subset that is finished is worth more than a gate over
# everything, because the first one can be trusted.
#
# WHAT THE CLAIMS ARE, AND WHY EACH IS NOT A CHANGE-DETECTOR:
#   t_hashcons            the same key on an arena that already holds it returns the SAME index,
#                         and does not consume a slot. Two facts, so two rows.
#   t_dtype_key           a bool const and an int const are DIFFERENT keys even at the same
#                         width, which is why `cls` is an explicit tag rather than a signedness
#                         flag (`spec.bend:54`).
#   t_float_zeros_differ  0.0 and -0.0 are distinct CONSTs: identity is the BIT PATTERN, and
#                         IEEE equality says they are equal, so a port that keys on `F32.is_eq`
#                         would collapse two nodes CPython keeps apart.
#   t_float_nan_interns   two NaNs ARE one node: IEEE equality disagrees in the OTHER direction
#                         here, so the same `is_eq` would re-mint an identical node. Together
#                         with the row above this is the pair that makes the choice of `F32.bits`
#                         non-negotiable -- `decomp.bend:126` may keep `is_eq` because there it
#                         asks a different question.
#   t_cycle               the BACKEDGE reads back as itself: src[0] is the SPECIAL and src[1]
#                         the RANGE whose arg names the axis it closes over.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O

# A Bool row is a 1-cell value, and the gate compares it against CPython's own 1-cell value, so
# the row is the CLAIM's verdict rather than the test's identity: two implementations of the
# same property, one in Bend and one in Python, and no shared code between them to be wrong
# together.
# The pop_const rows spell their OWN whole line and print it, rather than handing a name and a
# value to a printer -- three list elements in one `String.concat` is where the two shapes part
# company, and a row builder that can print is one call shorter than one that describes.
def prow(v: String) -> IO(Unit): IO.print(v)

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# `pop_const` -- ops.py:1082. `(src[0], src[1].val) if op is self.op and src[1].op is CONST else
# (self, None)`. TWO rows per fixture, because the pair of conditions and the popped VALUE fail
# independently: a reader that always refused would satisfy every `_val` row, and a reader that
# always popped would satisfy every `_hits` row. The float CONST is the third shape -- it IS a
# CONST, so `_hits` is true and `_val` is still absent, because `APy{CFloat{}}` carries an F32
# and this reader hands back an I64.
def g_add_const() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  O.UOp.alu(O.Found.ar(c), O.OpsADD{}, [O.Found.i(c), O.Found.i(c)])

# Right op, but `src[1]` is a RANGE and not a CONST.
def g_add_noconst() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(2)})
  +r = O.UOp.range_end(O.Found.ar(c), O.Found.i(c), [0], O.AXIS_LOOP{})
  O.UOp.alu(O.Found.ar(r), O.OpsADD{}, [O.Found.i(r), O.Found.i(r)])

# Right second src, WRONG op -- the row that says the op is compared and not merely assumed.
def g_mul_const() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  O.UOp.alu(O.Found.ar(c), O.OpsMUL{}, [O.Found.i(c), O.Found.i(c)])

def g_add_cfloat() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CFloat{2.5})
  O.UOp.alu(O.Found.ar(c), O.OpsADD{}, [O.Found.i(c), O.Found.i(c)])

# MATCHED RATHER THAN PASSED ON, because `Maybe<&1, H.I64>` is the reader's lifetime and the
# printer's is its own -- the same rebind `wk-cd.bend`'s `show` does.
# A MATCH MAY NOT SCRUTINISE A COMPUTED VALUE, so the reader is matched in a def of its own that
# takes the `Maybe` -- `wk-cd.bend`'s `show`, and the reason that shape is a pair of defs there
# too. `&1` rather than `&2` because the value is being consumed by the match, not returned.
# ONE PRINTER FOR THE THREE CONST CLASSES, in the order `Const` declares them, and `none` for the
# absent value -- which is a fourth case and NOT a fourth class.
def cshow(m: Maybe<&1, O.Const>) -> String:
  match m:
    case Some{O.CBool{b}}: Bool.show(b)
    case Some{O.CInt{i}}: H.i64_text(i)
    case Some{O.CFloat{f}}: H.f32_show(f)
    case _: "none"

def popv(+f: O.Found) -> String:
  cshow(O.UOp.pop_const_val(O.Found.ar(f), O.Found.i(f), O.OpsADD{}))

def pc(+nm: String, +f: O.Found) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- prow(String.concat([nm, "_hits=",
      Bool.show(O.UOp.pop_const_hits(O.Found.ar(f), O.Found.i(f), O.OpsADD{}))]))
    prow(String.concat([nm, "_val=", popv(f)]))

# `ssimplify` -- ops.py:92 -- TWO rows per fixture, because the value and the "is this a value at
# all" answer fail separately and CPython's third arm (`ret.val if CONST else ret`) hands back the
# NODE, which is a different answer rather than an absent one. THREE shapes: a bare CONST, a CAST
# of a CONST (the arm that does not need `simplify`), and a CAST of a PARAM (which is the third
# arm, and is the row that says `cval_arg`'s arm set is doing the work).
def cshow_of(+f: O.Found) -> String:
  cshow(O.UOp.ssimplify_val(O.Found.ar(f), O.Found.i(f)))

def ss_rows(+nm: String, +f: O.Found) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- prow(String.concat([nm, "_is_val=",
      Bool.show(O.UOp.ssimplify_is_val(O.Found.ar(f), O.Found.i(f)))]))
    prow(String.concat([nm, "_val=", cshow_of(f)]))

def g_ss_const() -> O.Found:
  +ar = O.Arena.empty()
  O.UOp.const(ar, O.CInt{H.i64_of_i32(7)})

# CAST of a CONST -- `cconst` is the forced cast, so this node's op is CAST and its src[0] is CONST.
def g_ss_cast() -> O.Found:
  +ar = O.Arena.empty()
  O.UOp.cconst(ar, O.CFloat{2.5}, S.single())

# CAST of a PARAM -- the third arm: not a value, and CPython hands the NODE back.
def g_ss_cast_param() -> O.Found:
  +ar = O.Arena.empty()
  # The PARAM's arg is spelled here rather than through `fold.bend`'s `mw_pa`, so this driver
  # keeps the three imports it already had. `cval_arg` refuses it because a PARAM's arg is an
  # `AParam`, not one of the three `APy` arms -- which is the whole point of the fixture.
  +p = O.UOp.new(ar, O.OpsPARAM{}, Nil{}, O.AParam{O.ParamArg{0, S.int32(), None{}, None{}, None{},
    None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})
  O.UOp.new(O.Found.ar(p), O.OpsCAST{}, [O.Found.i(p)], O.ADt{S.int32()}, O.TNone{})

def rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("hashcons_same_index", O.t_hashcons())
    b : Unit <- row("zeros_differ", O.t_float_zeros_differ())
    c : Unit <- row("nan_interns", O.t_float_nan_interns())
    d : Unit <- row("bool_vs_int_key", O.t_dtype_key())
    e : Unit <- row("backedge_srcs", O.t_cycle())
    f : Unit <- row("tag_bool_vs_int_interns", O.t_tag_bool_vs_int_interns())
    g : Unit <- row("tag_true_vs_false_splits", O.t_tag_true_vs_false_splits())
    h : Unit <- row("tag_none_vs_zero_interns", O.t_tag_none_vs_zero_interns())
    i : Unit <- row("const_bool_vs_int_splits", O.t_const_bool_vs_int_splits())
    j : Unit <- row("pynest_bool_vs_int_interns", O.t_pynest_bool_vs_int_interns())
    k : Unit <- row("pynest_int_distinct_interns", O.t_pynest_int_distinct_interns())
    l : Unit <- row("pynest_none_vs_zero_interns", O.t_pynest_none_vs_zero_interns())
    m : Unit <- row("pynest_cfloat_vs_int_interns", O.t_pynest_cfloat_vs_int_interns())
    # THE POP_CONST FIXTURES, and `pop_mul_const` is popped with `ADD` on purpose: it is the row
    # that says the op is COMPARED rather than assumed, and without it a reader that ignored the
    # op argument would pass the other three.
    n : Unit <- pc("pop_add_const", g_add_const())
    o : Unit <- pc("pop_add_noconst", g_add_noconst())
    q : Unit <- pc("pop_mul_const", g_mul_const())
    r : Unit <- pc("pop_add_cfloat", g_add_cfloat())
    w : Unit <- ss_rows("ss_const", g_ss_const())
    x : Unit <- ss_rows("ss_cast_const", g_ss_cast())
    y : Unit <- ss_rows("ss_cast_param", g_ss_cast_param())
    row("pynest_signed_zero_interns", O.t_pynest_signed_zero_interns())

def main() -> IO(Unit): rows()
