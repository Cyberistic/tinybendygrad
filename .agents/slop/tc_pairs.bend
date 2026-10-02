# ldexp2k / ldexp3k: "d_e"
def fx.ldexp() -> List<&2, String>:
  String.split("0.75_5|1.0_3|1.5_-2|3.0_0", '|')
# pow2if: plain integers
def fx.pow2if() -> List<&2, String>:
  String.split("-1|-10|-126|0|1|10|126", '|')
# spl: "d_q", the LARGE sibling of the sps fixtures
def fx.spl() -> List<&2, String>:
  String.split("-0.5_1|0.5_0|0.5_1|0.5_2|0.5_3|0.5_4|1.0_2|1.5707963_1|1.5707963_2", '|')
# the four xpow predicate families
def fx.xpowp() -> List<&2, String>:
  String.split("-0.0_2.5|-0.0_3.0|-2.0_-3.0|-2.0_2.0|-2.0_2.5|-2.0_3.0|-4.0_0.0|0.0_-1.0|0.0_0.0|0.0_5.0|0.5_2.0|2.0_0.0|2.0_0.5|4.0_0.0|inf_0.0", '|')
# xpow: "base_exponent"
# (the fixture lists themselves live in `fixtures` mode)
def fx.lazy() -> List<&2, String>:
  String.split("-0.0|-0.5|-1.0|0.0|0.5|1.0", '|')
