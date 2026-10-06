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
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O

# A Bool row is a 1-cell value, and the gate compares it against CPython's own 1-cell value, so
# the row is the CLAIM's verdict rather than the test's identity: two implementations of the
# same property, one in Bend and one in Python, and no shared code between them to be wrong
# together.
def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

def rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("hashcons_same_index", O.t_hashcons())
    b : Unit <- row("zeros_differ", O.t_float_zeros_differ())
    c : Unit <- row("nan_interns", O.t_float_nan_interns())
    d : Unit <- row("bool_vs_int_key", O.t_dtype_key())
    row("backedge_srcs", O.t_cycle())
    # THE ARG-TYPE LANE. tinygrad's key is `(op, src, arg, tag, type(arg))` -- ops.py:201 --
    # and that tuple carries an ASYMMETRY worth nine rows: it has `type(arg)` and NOT
    # `type(tag)`, so `True` and `1` SPLIT as a top-level arg and MERGE everywhere else. Each
    # `t_*` returns the CLAIM rather than a verdict, so a `0` is a correct answer and not a
    # failure -- which is what makes these rows worth more than the five above: five rows of `1`
    # cannot tell a comparator that always says True from one that is right, and three of these
    # nine are `0`.
    f : Unit <- row("tag_bool_vs_int_interns", O.t_tag_bool_vs_int_interns())
    g : Unit <- row("tag_true_vs_false_splits", O.t_tag_true_vs_false_splits())
    h : Unit <- row("tag_none_vs_zero_interns", O.t_tag_none_vs_zero_interns())
    i : Unit <- row("const_bool_vs_int_splits", O.t_const_bool_vs_int_splits())
    j : Unit <- row("pynest_bool_vs_int_interns", O.t_pynest_bool_vs_int_interns())
    k : Unit <- row("pynest_int_distinct_interns", O.t_pynest_int_distinct_interns())
    l : Unit <- row("pynest_none_vs_zero_interns", O.t_pynest_none_vs_zero_interns())
    m : Unit <- row("pynest_cfloat_vs_int_interns", O.t_pynest_cfloat_vs_int_interns())
    row("pynest_signed_zero_interns", O.t_pynest_signed_zero_interns())

def main() -> IO(Unit): rows()
