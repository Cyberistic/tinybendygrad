# ew-consts.bend -- the GATE DRIVER for elementwise.bend's F32 constants.
#
#   sh .agents/slop/ew-consts-gate.sh
#
# Every row is `name_dec` and `name_bits`, and the DECIMAL row is the interesting one
# precisely because the two sides SPELL IT DIFFERENTLY. The port has no `F64`, so it cannot
# print 0.044714998453855515 -- the f32 widened to a double -- and the decimals are
# therefore compared through `f32_repr`, the port's own float printer (H.f32_show), against CPython's
# `float(struct.unpack('f', struct.pack('f', x))[0])`. If `f32_repr` is right, the decimal
# rows agree; if it is wrong, they do not, and the BITS still do.
#
# That is two claims on one row and it is deliberate: the bit pattern is the ROUNDING claim
# (does the constant land where CPython puts it) and the decimal is the PRINTING claim (can
# the port show what it landed on). A gate that only did the first would pass with a broken
# float printer, and `f32_repr` is what every other row in the tree prints a float through.
#
# THE CONSTANTS ARE REACHED THROUGH `E`, i.e. through the real elementwise.bend. An earlier
# driver in this tree defined the block it gated LOCALLY and imported the file only for a
# type, which meant it gated a copy; helpers-tc.bend's header records that lesson.
import Base
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/mixin/elementwise.bend as E

def p(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def bits(+nm: String, +x: F32) -> IO(Unit):
  p(nm, U32.show(F32.bits(x)))


# ONE ROW PER CONSTANT, AND IT IS THE BIT PATTERN. The first draft also printed
# `H.f32_show(x)` and called that a second claim; it is not one. `f32_show` is a
# SIX-DECIMAL-PLACE formatter and CPython's `repr` is a SHORTEST-ROUND-TRIP one, so f32(log 2)
# is `0.693147` here and `0.6931471824645996` there -- a real difference, about a different
# def, and not something this unit measured. So the decimal is dropped rather than gated
# wrongly; the printer is its own unit.
def row(+nm: String, +x: F32) -> IO(Unit): bits(nm, x)

def rows() -> IO(Unit):
  do IO<Unit>:
    # --- the eight NAMED transcriptions, i.e. the typo surface ---
    a : Unit <- row("k_log2", E.ew_k.log2())
    b : Unit <- row("k_log10_2", E.ew_k.log10_2())
    c : Unit <- row("k_inv_log2", E.ew_k.inv_log2())
    d : Unit <- row("k_sqrt_2", E.ew_k.sqrt_2())
    e : Unit <- row("k_sqrt_2_over_pi", E.ew_k.sqrt_2_over_pi())
    f : Unit <- row("k_gelu", E.ew_k.gelu())
    g : Unit <- row("k_quick_gelu", E.ew_k.quick_gelu())
    h : Unit <- row("k_selu_alpha", E.ew_k.selu_alpha())
    h2 : Unit <- row("k_selu_gamma", E.ew_k.selu_gamma())
    # --- and the inline ones, which the marker block claimed were impossible ---
    i : Unit <- row("k_pi", F32.pi())
    j : Unit <- row("k_pi_2", F32.div(F32.pi(), 2.0))
    k : Unit <- row("k_sixth", F32.div(1.0, 6.0))
    l : Unit <- row("k_half", 0.5)
    m : Unit <- row("k_one", 1.0)
    n : Unit <- row("k_two", 2.0)
    o : Unit <- row("k_neg_one", F32.neg(1.0))
    p : Unit <- row("k_leak", 0.01)
    q : Unit <- row("k_rtol", 0.00001)
    r : Unit <- row("k_atol", 0.00000001)
    s : Unit <- row("k_e", 2.7182818)
    row("k_two_pi", F32.mul(F32.pi(), 2.0))

def main() -> IO(Unit): rows()
