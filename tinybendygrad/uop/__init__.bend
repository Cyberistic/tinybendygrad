# __init__.bend -- tinygrad/uop/__init__.py.
# this file is one DEF and three gate rows, and that is the finding.
# `__init__.py` is 135 lines and has three pieces: the `FastEnum` wrapper (6
#   * `Ops` is `ops.bend`'s `type Op is Data` (uop/ops.bend:170 symbol=Op), with the members
#     in `__init__.py`'s declaration order, which is load-bearing --
#     `__init__.py:12` says "the order of these Ops controls the order of the

import Base
import ./ops.bend as O

# `All = set(Ops)` -- __init__.py:135. Every op, which over a closed datatype is
def GroupOp.all(op: O.Op) -> Bool:
  True{}

# `len(Ops)` / `len(GroupOp.All)`. CPython: 77 and 77. The BEND-ONLY count is
def n_ops() -> U32:
  77

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["n_ops=", U32.show(n_ops())]))
    IO.print(String.concat(["first_value=", U32.show(O.Ops.value(O.OpsSPECIAL{}))]))
    IO.print(String.concat(["last_value=", U32.show(O.Ops.value(O.OpsPYLITERAL{}))]))
    IO.print(String.concat(["last_name=", O.Ops.name(O.OpsPYLITERAL{})]))
    IO.print("done")
