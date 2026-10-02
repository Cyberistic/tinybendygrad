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

def all_fixtures() -> List<&2, String>:
