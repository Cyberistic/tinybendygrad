import Base

# WHERE DOES `F32.div(3.0, 7.0)` LAND?
#
# `ulp_probe.bend` measured, with literals SEARCHED by `.agents/slop/mathlib/
# expect4.py` so they are genuine adjacent f32 neighbours of 3/7:
#
#     ctl_exact_2.5div1.25   = True    control passes
#     ctl_int_6div3          = True    control passes
#     three_sevens_is_exact  = False   not 3edb6db7
#     three_sevens_is_low    = False   not 3edb6db6
#
# Both False is not a rounding question, it is a DEFECT: the quotient is at least
# two ulps from the correctly rounded answer. This file brackets it for real, by
# SEARCHING over a ladder of decimals rather than assuming the offset, so the
# reported distance is measured.

def say(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

def q() -> F32:
  F32.div(3.0, 7.0)

def main() -> IO(Unit):
  do IO<Unit>:
    # A ladder of 12-decimal literals spanning 3/7 +/- 12 ulps. `expect5.txt`
    # names, for each, which f32 it rounds to. EXACTLY ONE must be True.
    say("k_m12", F32.is_eq(q(), 0.428571061))
    say("k_m11", F32.is_eq(q(), 0.428571091))
    say("k_m10", F32.is_eq(q(), 0.428571121))
    say("k_m9", F32.is_eq(q(), 0.428571151))
    say("k_m8", F32.is_eq(q(), 0.428571180))
    say("k_m7", F32.is_eq(q(), 0.428571210))
    say("k_m6", F32.is_eq(q(), 0.428571240))
    say("k_m5", F32.is_eq(q(), 0.428571270))
    say("k_m4", F32.is_eq(q(), 0.428571300))
    say("k_m3", F32.is_eq(q(), 0.428571329))
    say("k_m2", F32.is_eq(q(), 0.428571359))
    say("k_m1", F32.is_eq(q(), 0.428571389))
    say("k_exact", F32.is_eq(q(), 0.428571419))
    say("k_p1", F32.is_eq(q(), 0.428571449))
    say("k_p2", F32.is_eq(q(), 0.428571478))
    say("k_p3", F32.is_eq(q(), 0.428571508))
    say("k_p4", F32.is_eq(q(), 0.428571538))
    say("k_p5", F32.is_eq(q(), 0.428571568))
    say("k_p6", F32.is_eq(q(), 0.428571598))
    say("k_p7", F32.is_eq(q(), 0.428571627))
    say("k_p8", F32.is_eq(q(), 0.428571657))
    say("k_p9", F32.is_eq(q(), 0.428571687))
    say("k_p10", F32.is_eq(q(), 0.428571717))
    say("k_p11", F32.is_eq(q(), 0.428571747))
    say("k_p12", F32.is_eq(q(), 0.428571776))
