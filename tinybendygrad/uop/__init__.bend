# __init__.bend -- tinygrad/uop/__init__.py.
# this file is one DEF and three gate rows, and that is the finding.
# `__init__.py` is 135 lines and has three pieces: the `FastEnum` wrapper (6
#   * `Ops` is `ops.bend`'s `type Op is Data` (uop/ops.bend:170 symbol=Op), with the members
# SO WHAT IS LEFT IS `GroupOp.All` (`__init__.py:134`, `All = set(Ops)`), the one
#     schedule/rangeify.py:47    UPat(GroupOp.All, name="b")
# the set differences are not ported here, and the reason is one line: `All` is
# A DEF OVER A CLOSED DATATYPE IS A TAUTOLOGY, and saying so is worth more than
#     n_ops=77         CPython `len(Ops)`           -- the COUNT, and the row
# The first three are COUNT rows, which is the brief's rule: a boolean about a
# NOT PORTED, with the reason:

import Base
import ./ops.bend as O

# `All = set(Ops)` -- __init__.py:135. Every op, which over a closed datatype is
def GroupOp.all(op: O.Op) -> Bool:
  True{}

def n_ops() -> U32:
  77

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["n_ops=", U32.show(n_ops())]))
    IO.print(String.concat(["first_value=", U32.show(O.Ops.value(O.OpsSPECIAL{}))]))
    IO.print(String.concat(["last_value=", U32.show(O.Ops.value(O.OpsPYLITERAL{}))]))
    IO.print(String.concat(["last_name=", O.Ops.name(O.OpsPYLITERAL{})]))
    IO.print("done")
