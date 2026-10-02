def sp.sin32() -> List<&2, String>:
  String.split("2.6083159809786594e-06|-0.00019810690719168633|0.00833307858556509|-0.16666659712791443|1.0", '|')
def sp.sin32_raw() -> String: "2.6083159809786594e-06 | -0.00019810690719168633 | 0.00833307858556509 | -0.16666659712791443 | 1.0"
def sp.sin64() -> List<&2, String>:
  String.split("-7.972559550090379e-18|2.810099727108632e-15|-7.647122191181588e-13|1.605904306056645e-10|-2.5052108376350205e-08|2.7557319223919875e-06|-0.00019841269841269616|0.00833333333333333|-0.16666666666666666|1.0", '|')
def sp.sin64_raw() -> String: "-7.972559550090379e-18 | 2.810099727108632e-15 | -7.647122191181588e-13 | 1.605904306056645e-10 | -2.5052108376350205e-08 | 2.7557319223919875e-06 | -0.00019841269841269616 | 0.00833333333333333 | -0.16666666666666666 | 1.0"
def sp.exp32() -> List<&2, String>:
  String.split("0.0001535920892|0.001339262701|0.009618384764|0.05550347269|0.2402264476|0.6931471825|1.0", '|')
def sp.exp32_raw() -> String: "0.0001535920892 | 0.001339262701 | 0.009618384764 | 0.05550347269 | 0.2402264476 | 0.6931471825 | 1.0"
def sp.exp64() -> List<&2, String>:
  String.split("4.4343590829265295e-10|7.0731645980857074e-09|1.0178192609217605e-07|1.3215438725113276e-06|1.5252733535175847e-05|0.00015403530451011478|0.001333355814670499|0.0096181291075976|0.055504108664820466|0.24022650695910122|0.6931471805599453|1.0", '|')
def sp.exp64_raw() -> String: "4.4343590829265295e-10 | 7.0731645980857074e-09 | 1.0178192609217605e-07 | 1.3215438725113276e-06 | 1.5252733535175847e-05 | 0.00015403530451011478 | 0.001333355814670499 | 0.0096181291075976 | 0.055504108664820466 | 0.24022650695910122 | 0.6931471805599453 | 1.0"
def sp.log32() -> List<&2, String>:
  String.split("0.4374550283|0.5764790177|0.961801290512", '|')
def sp.log32_raw() -> String: "0.4374550283 | 0.5764790177 | 0.961801290512"
def sp.log64() -> List<&2, String>:
  String.split("0.22119417504560815|0.22007686931522777|0.26237080574885147|0.32059774779444955|0.41219859454853247|0.5770780162997059|0.9617966939260809", '|')
def sp.log64_raw() -> String: "0.22119417504560815 | 0.22007686931522777 | 0.26237080574885147 | 0.32059774779444955 | 0.41219859454853247 | 0.5770780162997059 | 0.9617966939260809"
def sp.topi() -> List<&2, String>:
  String.split("0|0x00000000|683565275|0x28be60db|2475754826|0x9391054a|2131351028|0x7f09d5f4|2102212464|0x7d4d3770|920167782|0x36d8a566|1326507024|0x4f10e410", '|')
def sp.topi_raw() -> String: "0 | 683565275 | 2475754826 | 2131351028 | 2102212464 | 920167782 | 1326507024"
def sp.fscal() -> List<&2, String>:
  String.split("m_1_pi|0.3183098861837907|two_24|16777216.0|topi_scale|4294967296.0|neg_half_pi_over_2|3.4061215800865545e-19|nlog2e64|2.8853900817779268|nlog2e32|2.885390043258667|s_lo32|3.273447448356849e-08|one_over_075|1.3333333333333333|switch_over|30.0|pi_over_2|1.5707963267948966|cw0|-3.1414794921875|cw1|-0.0001131594181060791|cw2|-1.984187258941006e-09|cw3|-1.215420125655342e-10|pi_a|3.1415926218032837|pi_b|3.1786509424591713e-08|pi_c|1.2246467864107189e-16|pi_d|1.27366343270219e-24|xexp2_lo_32|-150|xexp2_up_32|128|flmin_16|6.1e-05|flmin_32|0.0001|denorm_scale|1.8446744073709552e+19|two_m24|5.960464477539063e-08", '|')
def sp.m_1_pi() -> String: "0.3183098861837907"
def sp.two_24() -> String: "16777216.0"
def sp.nlog2e32() -> String: "2.885390043258667"
def sp.s_lo32() -> String: "3.273447448356849e-08"
def sp.one_over_075() -> String: "1.3333333333333333"
def sp.switch_over() -> String: "30.0"
def sp.pi_over_2() -> String: "1.5707963267948966"
def sp.cw0() -> String: "-3.1414794921875"
def sp.cw1() -> String: "-0.0001131594181060791"
def sp.cw2() -> String: "-1.984187258941006e-09"
def sp.cw3() -> String: "-1.215420125655342e-10"
def sp.xexp2_lo_32() -> String: "-150"
def sp.xexp2_up_32() -> String: "128"
def sp.flmin_32() -> String: "0.0001"
def sp.denorm_scale() -> String: "1.8446744073709552e+19"
def sp.two_m24() -> String: "5.960464477539063e-08"
def sp.fm1_32() -> U32: 2155872255
def sp.fm1_32_hex() -> String: "0x807fffff"
def sp.fm2_32() -> U32: 1056964608
def sp.fm2_32_hex() -> String: "0x3f000000"
def sp.fm1_16() -> U32: 33791
def sp.fm1_16_hex() -> String: "0x000083ff"
def sp.fm2_16() -> U32: 14336
def sp.fm2_16_hex() -> String: "0x00003800"
def sp.frac_mask() -> U32: 8388607
def sp.frac_mask_hex() -> String: "0x007fffff"
def sp.de_32() -> U32: 64
def sp.de_32_hex() -> String: "0x00000040"
def sp.q_shift() -> U32: 62
def sp.q_shift_hex() -> String: "0x0000003e"
def sp.take_window() -> U32: 6
def sp.take_window_hex() -> String: "0x00000006"
def sp.mb_32() -> U32: 23
def sp.mb_32_hex() -> String: "0x00000017"
def sp.eb_32() -> U32: 127
def sp.eb_32_hex() -> String: "0x0000007f"
def sp.em_32() -> U32: 255
def sp.em_32_hex() -> String: "0x000000ff"
def sp.mb_16() -> U32: 10
def sp.mb_16_hex() -> String: "0x0000000a"
def sp.eb_16() -> U32: 15
def sp.eb_16_hex() -> String: "0x0000000f"
def sp.em_16() -> U32: 31
def sp.em_16_hex() -> String: "0x0000001f"
def sp.p_mask_hi() -> U32: 1073741823
def sp.p_mask_lo() -> U32: 4294967295
def sp.fm1_64_hi() -> U32: 1048575
def sp.fm1_64_lo() -> U32: 4294967295
def sp.fm2_64_hi() -> U32: 1071644672
def sp.fm2_64_lo() -> U32: 0
def sp.mant64_hi() -> U32: 0
def sp.mant64_lo() -> U32: 52
def sp.eb64_hi() -> U32: 0
def sp.eb64_lo() -> U32: 1023
def sp.em64_hi() -> U32: 0
def sp.em64_lo() -> U32: 2047
def sp.mb_64() -> U32: 52
def sp.mb_64_hex() -> String: "0x00000034"
def tx_dt.transcendental_t() -> String: "f16 f32 f64"
def tx_dt.rintk_f64_t() -> String: "dtypes.i64"
def tx_dt.rintk_f32_t() -> String: "dtypes.i32"
def tx_dt.rintk_f16_t() -> String: "dtypes.i16"
def tx_dt.pow2if_i64_t() -> String: "dtypes.f64"
def tx_dt.pow2if_i32_t() -> String: "dtypes.f32"
def tx_dt.pow2if_i16_t() -> String: "<param>"
def tx_dt.ilogb2k_f64_t() -> String: "dtypes.i64"
def tx_dt.ilogb2k_f32_t() -> String: "dtypes.i32"
def tx_dt.ilogb2k_f16_t() -> String: "dtypes.i16"
def tx_dt.ldexp3k_f64_t() -> String: "dtypes.i64"
def tx_dt.ldexp3k_f32_t() -> String: "dtypes.i32"
def tx_dt.ldexp3k_f16_t() -> String: "dtypes.i16"
def tx_dt.frexp_u_f64_t() -> String: "dtypes.u64"
def tx_dt.frexp_u_f32_t() -> String: "dtypes.u32"
def tx_dt.frexp_u_f16_t() -> String: "dtypes.u16"
def tx_dt.pow2if_param_t() -> String: "float_dtype"

def fx.sinpoly() -> List<&2, String>:
  String.split("0.0|0.5|-0.5|1.0|-1.0|1.5707963|0.25|-0.75", '|')
def fx.shr() -> List<&2, String>:
  String.split("1|2|255|256|2147483647|4294967295", '|')
def fx.shl() -> List<&2, String>:
  String.split("1|2|255|256|2147483647|4294967295", '|')
def fx.rintk() -> List<&2, String>:
  String.split("0.0|-0.0|0.4|-0.4|0.5|-0.5|2.5|-2.5|10000000.0|-10000000.0", '|')
def fx.ilogb() -> List<&2, String>:
  String.split("0.5|0.75|1.0|1.5|3.0|1024.0|0.0001|8388608.0", '|')
def fx.frexp_m() -> List<&2, String>:
  String.split("0.5|1.0|1.5|3.0|-2.5|1024.0", '|')
def fx.frexp_e() -> List<&2, String>:
  String.split("0.5|1.0|1.5|3.0|-2.5|1024.0", '|')
def fx.cw_r() -> List<&2, String>:
  String.split("0.0|0.5|1.0|1.5707963|3.0|30.0|100.0|-100.0|39800.0", '|')
def fx.cw_q() -> List<&2, String>:
  String.split("0.0|0.5|1.0|1.5707963|3.0|30.0|100.0|-100.0|39800.0", '|')
def fx.sps() -> List<&2, String>:
  String.split("0.5_0|0.5_1|0.5_2|0.5_3|0.5_4|-0.5_1|1.0_2|1.5707963_2|1.5707963_1", '|')
def fx.xsinfast() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|1.5707963|3.1415927|6.2831855|29.999998|30.0|30.000002|0.25|100.0|-100.0", '|')
def fx.xsinslow() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|1.5707963|3.1415927|6.2831855|29.999998|0.25", '|')
def fx.xexp2() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|2.0|-2.0|30.0|126.99999|127.0|127.99999|128.0|128.00001|200.0|-149.99999|-150.0|-150.00001|-200.0|100000.0|-100000.0", '|')
def fx.xexp2sp() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|2.0|-2.0|30.0|126.99999|127.0|127.99999|128.0|128.00001|200.0|-149.99999|-150.0|-150.00001|-200.0|100000.0|-100000.0|inf|-inf", '|')
def fx.xlog2() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|0.75|1.0|1.5|2.0|3.0|5e-05|9.999e-05|0.00010001|1e-30|3e-40|-1.0|1024.0|0.25|8.0", '|')
def fx.xlog2sp() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|0.75|1.0|1.5|2.0|3.0|5e-05|9.999e-05|0.00010001|1e-30|3e-40|-1.0|1024.0|0.25|8.0|inf|-inf", '|')
def fx.inf() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|inf|-inf|nan", '|')
def fx.g() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|2.0|-2.0|30.0|127.99999|128.0|128.00001|-149.99999|-150.0|-150.00001|inf|-inf|nan", '|')
def fx.special() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|inf|-inf|nan", '|')
def fx.xpowval() -> List<&2, String>:
  String.split("0.0_0.0|0.0_5.0|inf_0.0|4.0_0.0|-4.0_0.0|-0.0_3.0|-0.0_2.5|2.0_0.0|0.0_-1.0|-0.0_-3.0", '|')

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
  String.split("-0.0|-0.5|-1.0|-inf|0.0|0.5|1.0|inf|nan", '|')
