# ansi_probe.bend -- the BEND lane of the `ansistrip` gate.
#
# One `name=value` line per fixture, walked in the order of
# `.agents/slop/ansi_fixture.py`, which is the single source of the list. The
# values are produced by CALLING `tinybendygrad/helpers.bend`'s `ansistrip`; not
# one answer is transcribed. `.agents/slop/ansi_oracle.py` produces the other
# lane by CALLING `tinygrad.helpers.ansistrip`, and `.agents/slop/ansi_gate.py`
# diffs WHOLE LINES.
#
# The rendering is the one thing that must agree byte for byte between the two
# lanes: every byte below 0x20 and 0x7f becomes `<XX>` in uppercase hex so a
# terminal cannot swallow the ESC and the newline inside a fixture, and every
# other byte is passed through. `re.sub` and `String.from_list` see the same
# bytes; only the PRINT differs.

import Base
import ../../tinybendygrad/helpers.bend as H

# Bend 2.0.34's string escapes are `\n \t \r \0 \\ \' \" \u{...}` and NO `\x`,
# so ESC is spelled `[`. `ansi_fixture.py` spells it `\x1b`.
def E() -> String: String.from_list([Char.from_u32(27)])

# ===========================================================================
# FIXTURES -- the same 43 entries, in the same order, as ansi_fixture.py.
# ===========================================================================
def p00() -> String: ""
def p01() -> String: "plain"
def p02() -> String: E()
def p03() -> String: String.append(E(), "[")
def p04() -> String: String.append(E(), "[31")
def p05() -> String: "[31m"
def p06() -> String: "["
def p07() -> String: "[x"
def p08() -> String: String.append(E(), "[K")
def p09() -> String: String.append(E(), "[Kx")
def p10() -> String: String.append(E(), "[Km")
def p11() -> String: String.append(E(), "[K31m")
def p12() -> String: String.append(E(), "[K[K")
def p13() -> String: String.append(E(), "[31m")
def p14() -> String: String.append(E(), "[m")
def p15() -> String: String.append(E(), "[mx")
def p16() -> String: String.concat([String.append(E(), "[31mred"), String.append(E(), "[0m")])
def p17() -> String: String.concat([String.append(E(), "[1;31;42mWARN"), String.append(E(), "[0m")])
def p18() -> String: String.concat([String.append(E(), "[38;2;255;0;0mT"), String.append(E(), "[0m")])
def p19() -> String: String.append(E(), "[31mK")
def p20() -> String: String.concat([String.append(E(), "[31mK"), String.append(E(), "[K")])
def p21() -> String: String.concat([String.append(E(), "[1m"), String.append(E(), "[0m"), String.append(E(), "[0m")])
def p22() -> String: String.concat([String.append(E(), "[0m"), String.append(E(), "[0m"), String.append(E(), "[0m")])
def p23() -> String: String.append(E(), "[31m\nm")
def p24() -> String: String.append(E(), "[\nm")
def p25() -> String: String.append(E(), "[31\nmred")
def p26() -> String: String.concat([String.append(E(), "[\n"), String.append(E(), "[31m")])
def p27() -> String: String.concat([String.append(E(), "["), String.append(E(), "[31m")])
def p28() -> String: String.concat([String.append(E(), "["), String.append(E(), "[31")])
def p29() -> String: String.concat([String.append(E(), "["), String.append(E(), "[K\n")])
def p30() -> String: String.concat([String.append(E(), "["), String.append(E(), "[Km")])
def p31() -> String: String.append(E(), E())
def p32() -> String: String.concat([String.append(E(), E()), "[31m"])
def p33() -> String: String.concat([String.append(E(), E()), "x"])
def p34() -> String: String.append(E(), "x")
def p35() -> String: String.concat([String.append(E(), "[31mx"), String.append(E(), "y")])
def p36() -> String: String.concat([String.append(E(), "[31m"), E()])
def p37() -> String: String.append(E(), "]0;title")
def p38() -> String: String.concat(["x", String.append(E(), "[K"), "y", String.append(E(), "[31mz")])
def p39() -> String: String.append(E(), "[K\n")
def p40() -> String: String.append(E(), "[m\n")
def p41() -> String: String.concat([String.append(E(), "[1"), String.append(E(), "[0m"), String.append(E(), "[K")])
def p42() -> String: String.concat([String.append(E(), "[31m"), String.append(E(), "[")])

def all_fixtures() -> List<&1, String>:
  [p00(), p01(), p02(), p03(), p04(), p05(), p06(), p07(), p08(), p09(),
   p10(), p11(), p12(), p13(), p14(), p15(), p16(), p17(), p18(), p19(),
   p20(), p21(), p22(), p23(), p24(), p25(), p26(), p27(), p28(), p29(),
   p30(), p31(), p32(), p33(), p34(), p35(), p36(), p37(), p38(), p39(),
   p40(), p41(), p42()]

# ===========================================================================
# RENDERING -- shared byte-for-byte with ansi_oracle.py's `render`.
# ===========================================================================
def pr_hexdig(+v: U32) -> Char:
  Bool.pick(Char, U32.is_lt(v, 10), Char.from_u32(U32.add(48, v)),
            Char.from_u32(U32.add(55, v)))

def pr_hexbyte(+v: U32) -> String:
  String.from_list([Char.from_u32(60), pr_hexdig(U32.shrn(v, 4n)),
                    pr_hexdig(U32.and(v, 15)), Char.from_u32(62)])

# a byte is CONTROL when it is below 0x20 or exactly 0x7f, and `U32.is_lt` on
# the raw code is the whole test apart from the DEL comparison spelled out.
def pr_control(+v: U32) -> Bool: Bool.or(U32.is_lt(v, 32), U32.is_eq(v, 127))

def pr_char(+h: Char) -> String:
  Bool.pick(String, pr_control(Char.to_u32(h)), pr_hexbyte(Char.to_u32(h)),
            String.from_list([h]))

def pr_go(+cs: List<&2, Char>) -> String:
  match cs:
    case Nil{}: ""
    case +h <> t: String.append(pr_char(h), pr_go(t))

def pr_render(s: String) -> String: pr_go(String.to_list(H.ansistrip(s)))

# zero-padded to two digits, because `ansi_0` and `ansi_00` would not be the
# same row NAME on the two lanes and the diff is over whole lines.
def pr_two(+n: Nat, +s: String) -> String:
  String.concat(["ansi_", String.from_list([pr_hexdig(U32.div(U32.from_nat(n), 10)),
                                             pr_hexdig(U32.mod(U32.from_nat(n), 10))]), "=", s])

# the SHRINKING argument comes first: Bend reads self-call arguments left to
# right and each is passed unchanged until one shrinks. MEASURED, the other
# order is rejected with "expected : a decreasing self-call".
def pr_emit(xs: List<&1, String>, +n: Nat) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case +h <> t: do IO<Unit>:
      IO.print(pr_two(n, h))
      pr_emit(t, Nat.add(n, 1n))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["# rows ", U32.show(U32.from_nat(List.length(&1, String, all_fixtures())))]))
    pr_emit(List.map(String, String, pr_render, all_fixtures()), 0n)
