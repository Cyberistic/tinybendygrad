#     `__init__.py:12` says "the order of these Ops controls the order of the
# SO WHAT IS LEFT IS `GroupOp.All` (`__init__.py:134`, `All = set(Ops)`), the one
#     schedule/rangeify.py:47    UPat(GroupOp.All, name="b")
#     schedule/indexing.py:144    UPat(GroupOp.All, name="x")
#     schedule/prepare.py:264     UPat(GroupOp.All-{Ops.SINK}, name="x")
#     codegen/decomp/dtype.py:150 UPat(GroupOp.All, name="x")
#     codegen/decomp/dtype.py:185 UPat(GroupOp.All-{Ops.LOAD, Ops.STACK}, ...)
#     codegen/decomp/dtype.py:220 UPat(GroupOp.All, (*fp8s, ...), name="x")
#     uop/render.py:71, :122     UPat(GroupOp.All, name=...)
#     uop/spec.py:207, :208      UPat(GroupOp.All, name="x")

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
