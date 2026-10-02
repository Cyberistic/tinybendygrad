# nocolor-probe.bend -- the BEND side of the NO_COLOR gate.
#
# no_color_of is helpers.bend's coercion of NO_COLOR.  The gate is a DIFF of
# whole lines against .agents/slop/nocolor-oracle.txt: both files print ONE
# answer per line, in the order of the SAME probe list, so the differ is over
# answers and nothing here is a transcription of the oracle's.
#
# Line 0 is the UNSET case.  The port has one string for it and Python has two:
# `Flags.from_env` passes "" as the getenv default when the key is absent, and
# p0 is that same "" when the key is present and empty.  Both answer False here;
# CPython REFUSES the second, which the differ reports as a stated divergence.
#
#   True  -- NO_COLOR truthy, so helpers.py:41 `if NO_COLOR: return st` returns
#            the PLAIN string, i.e. colour is OFF.
#   False -- colour is ON.
#
# Where CPython REFUSES the string (int() raises, so tinygrad does not import)
# the probe expects False, and that is a stated requirement, not a match.
import Base
import ../../tinybendygrad/helpers.bend as H

def p0() -> String: ""
def p1() -> String: "0"
def p2() -> String: "1"
def p3() -> String: "2"
def p4() -> String: "00"
def p5() -> String: "-0"
def p6() -> String: "0 "
def p7() -> String: " 0"
def p8() -> String: "+0"
def p9() -> String: "+1"
def p10() -> String: "-1"
def p11() -> String: "-2"
def p12() -> String: "007"
def p13() -> String: "0x10"
def p14() -> String: "1_0"
def p15() -> String: "1.0"
def p16() -> String: "0.0"
def p17() -> String: ".5"
def p18() -> String: "abc"
def p19() -> String: "false"
def p20() -> String: "True"
def p21() -> String: "no"
def p22() -> String: "off"
def p23() -> String: "nan"
def p24() -> String: "inf"
def p25() -> String: "1e3"
def p26() -> String: " 1 "
def p27() -> String: "\t2"
def p28() -> String: "2\n"
def p29() -> String: "\u{0663}"
def p30() -> String: "2 "

def probes() -> List<&2, String>:
  [p0(), p1(), p2(), p3(), p4(), p5(), p6(), p7(), p8(), p9(), p10(),
   p11(), p12(), p13(), p14(), p15(), p16(), p17(), p18(), p19(), p20(),
   p21(), p22(), p23(), p24(), p25(), p26(), p27(), p28(), p29(), p30()]

def b(x: Bool) -> String:
  match x:
    case True{}: "True"
    case False{}: "False"

type Out is Data:
  Out{rs: List<&2, String>}

def out_rs(o: Out) -> List<&2, String>:
  match o:
    case Out{rs}: rs

def out_add(o: Out, v: String) -> Out:
  Out{List.append(&2, String, out_rs(o), [b(H.no_color_of(v))])}

def out_go(vs: List<&2, String>, o: Out) -> Out:
  match vs:
    case Nil{}: o
    case v <> t: out_go(t, out_add(o, v))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(b(H.no_color_of("")))
    ps : List<&2, String> <- IO.pure(List<&2, String>, probes())
    o : Out <- IO.pure(Out, out_go(ps, Out{Nil{}}))
    IO.print(String.join(out_rs(o), "\n"))
    IO.print("")