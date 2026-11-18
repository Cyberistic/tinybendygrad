# renderer/estimates.bend -- the `Estimates` RECORD, `tinygrad/renderer/__init__.py:15-24`.

import Base

# `Estimates` -- __init__.py:15-61.

type Estimates is Data:
  Estimates{ops: U32, lds: U32, mem: U32}

def Estimates.of(o: U32, l: U32, m: U32) -> Estimates: Estimates{o, l, m}

def Estimates.ops(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: ops

def Estimates.lds(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: lds

def Estimates.mem(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: mem

# `def __add__(self, o)` -- __init__.py:23.
def Estimates.add(+a: Estimates, +b: Estimates) -> Estimates:
  Estimates{U32.add(Estimates.ops(a), Estimates.ops(b)), U32.add(Estimates.lds(a), Estimates.lds(b)),
    U32.add(Estimates.mem(a), Estimates.mem(b))}

# `def simplify(self)` -- __init__.py:24.  `ssimplify` on a plain int is the
# IDENTITY and the port's counter IS a plain int, so this returns its argument.
def Estimates.simplify(a: Estimates) -> Estimates: a

# `Estimates.__repr__` is a dataclass repr, so the oracle is CPython's own
# `Estimates(1,2,3)+Estimates(4,5,6)` printed -- the SAME three-field spelling
# the port emits, and a dropped field shows as a shorter string.
#
# IT IS HERE AND NOT IN `renderer/__init__.bend` because `uop/render.bend`
def Estimates.str(+a: Estimates) -> String:
  String.concat(["Estimates(ops=", U32.show(Estimates.ops(a)), ", lds=", U32.show(Estimates.lds(a)),
    ", mem=", U32.show(Estimates.mem(a)), ")"])
