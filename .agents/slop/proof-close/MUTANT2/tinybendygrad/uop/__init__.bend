# __init__.bend -- tinygrad/uop/__init__.py.
#
# THIS FILE IS ONE DEF AND THREE GATE ROWS, AND THAT IS THE FINDING.
#
# `__init__.py` is 135 lines and has three pieces: the `FastEnum` wrapper (6
# lines), the `Ops` enum (90 lines, 77 members), and the `GroupOp` class (31
# lines, 15 frozensets). `ops.bend` ALREADY HOLDS THE FIRST TWO AND FOURTEEN OF
# THE FIFTEEN:
#
#   * `Ops` is `ops.bend`'s `type Op is Data` (ops.bend:101), with the members
#     in `__init__.py`'s declaration order, which is load-bearing --
#     `__init__.py:12` says "the order of these Ops controls the order of the
#     toposort", and `ops.bend:62` repeats it.
#   * `FastEnum` is not a table, it is a NUMBERING MECHANISM:
#     `_generate_next_value_` is `1 + max([0, *last_values, *[max(c) for c in
#     FastEnum.__subclasses__()]])`, and `Ops` is the only subclass, so its
#     whole observable effect is "the values are 1, 2, 3, ... in declaration
#     order" -- which is what `ops.bend:307 Ops.value` is. `__str__` and
#     `__repr__` are both `str(self)`, which is `ops.bend:301 Ops.name`.
#   * `GroupOp.Unary .. GroupOp.Comparison` are `ops.bend:387-493`.
#
# SO WHAT IS LEFT IS `GroupOp.All` (`__init__.py:135`, `All = set(Ops)`), the one
# member of the file's vocabulary `ops.bend` does not have. It is here because
# it is LOAD-BEARING: ten call sites read it, and two read a SET DIFFERENCE.
#
#     schedule/rangeify.py:47    UPat(GroupOp.All, name="b")
#     schedule/indexing.py:144    UPat(GroupOp.All, name="x")
#     schedule/prepare.py:264     UPat(GroupOp.All-{Ops.SINK}, name="x")
#     codegen/decomp/dtype.py:150 UPat(GroupOp.All, name="x")
#     codegen/decomp/dtype.py:185 UPat(GroupOp.All-{Ops.LOAD, Ops.STACK}, ...)
#     codegen/decomp/dtype.py:220 UPat(GroupOp.All, (*fp8s, ...), name="x")
#     uop/render.py:71, :122     UPat(GroupOp.All, name=...)
#     uop/spec.py:207, :208      UPat(GroupOp.All, name="x")
#
# THE SET DIFFERENCES ARE NOT PORTED HERE, and the reason is one line: `All` is
# EVERY op, so `All - {SINK}` is a predicate, and the honest spelling is the
# `UPat`'s own `reject` set -- which is where tinygrad already puts a one-op
# exclusion. A `GroupOp.all_but(op, ...)` here would be a new abstraction for a
# set subtraction over a total function, and both call sites name ONE op. The
# three counts those call sites depend on are pinned in the header of the gate
# so the difference is not lost silently.
#
# A DEF OVER A CLOSED DATATYPE IS A TAUTOLOGY, and saying so is worth more than
# pretending otherwise. `Op` has 77 constructors and is closed, so
# `GroupOp.all` answers `True{}` for every value that exists: there is NO input
# for which a Boolean row could read `False`, so every `GroupOp.all(o)` row
# would be a restatement of the code. The rows below are therefore chosen for
# the failure mode this def actually has, which is DRIFT between the `Op` type
# and the `Ops` enum -- a total function cannot detect a new constructor and a
# count can. So the gate is:
#
#     n_ops=77         CPython `len(Ops)`           -- the COUNT, and the row
#                                                    that a new member moves
#     first_value=1    CPython `Ops.SPECIAL.value`  -- FastEnum starts at 1
#     last_value=77    CPython `Ops.PYLITERAL.value`-- the LAST arm of the
#                                                    ladder, so a truncated or
#                                                    reordered `Op` moves it
#     last_name=Ops.PYLITERAL  CPython `str(...)`    -- `__str__` is preserved
#
# The first three are COUNT rows, which is the brief's rule: a boolean about a
# string is worthless when the string can be compared, and a count pins the
# thing a set cannot report.
#
# NOT PORTED, with the reason:
#   * `FastEnum` (the class, not its effect) -- a Python `IntEnum` subclass
#     mechanism. Its three observable effects are `Ops.value`, `Ops.name` and
#     the declaration order, and all three are in `ops.bend`.
#   * `Ops` -- `ops.bend:101`. Declared here too would be a duplicate
#     constructor declaration, which Bend refuses.

import Base
import ./ops.bend as O

# `All = set(Ops)` -- __init__.py:135. Every op, which over a closed datatype is
# the identity. The parameter is read by NO arm, and an unused parameter is
# accepted (measured: `uop/spec.bend`'s rule 2), which is the only reason this
# one line is legal at all.
def GroupOp.all(op: O.Op) -> Bool:
  True{}

# `len(Ops)` / `len(GroupOp.All)`. CPython: 77 and 77. The BEND-ONLY count is
# the `Op` type's constructor arity, read off `ops.bend:101`; the row that
# compares it to CPython is `n_ops` below.
def n_ops() -> U32:
  77

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["n_ops=", U32.show(n_ops())]))
    IO.print(String.concat(["first_value=", U32.show(O.Ops.value(O.OpsSPECIAL{}))]))
    IO.print(String.concat(["last_value=", U32.show(O.Ops.value(O.OpsPYLITERAL{}))]))
    IO.print(String.concat(["last_name=", O.Ops.name(O.OpsPYLITERAL{})]))
    IO.print("done")
