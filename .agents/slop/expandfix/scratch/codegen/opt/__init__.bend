# tinybendygrad/codegen/opt/__init__.bend -- port of
# tinygrad/codegen/opt/__init__.py
#
# `tinygrad/codegen/opt/__init__.py` is 19 lines and exports four names:
#
#     OptOps    -- an `Enum` (auto): TC, SPLIT, PADTO, SWAP
#     Opt       -- a `frozen dataclass`: (op: OptOps, axis: int|None, arg: int|tuple|None)
#     KernelOptError -- an `Exception`
#     check(cond, msg) -- a guard that raises KernelOptError
#
# Each one is ALREADY in `postrange.bend`, the file the rest of the
# opt unit imports from. The mapping is:
#
#     OptOps        ->  OPTOPS  (type OPTOPS is Data, postrange.bend:6)
#     Opt           ->  OPT     (type OPT is Data, postrange.bend:42)
#     KernelOptError ->  Bool   (postrange.bend:13, "KernelOptError" is a verdict)
#     check         ->  per-site: a Bool precondition, with the message
#                       as a `match` arm and the raise as a `Bool` row in
#                       the gate. The Python `check` is one helper, the
#                       port has it as N sites, where N is the number of
#                       `raise KernelOptError(...)` call sites in
#                       `postrange.py` and `search.py`.
#
# So this file is a re-export in Python, and the port is the SAME
# re-export by path: `from tinygrad.codegen.opt import Opt` is
# `import ./postrange.bend as Opt` here, and a reader who looks for
# `tinybendygrad/codegen/opt/__init__.bend` because they know
# `tinygrad/codegen/opt/__init__.py` finds a 0-logic file that says
# "the names live in `postrange.bend`".
#
# The gate is the four-name count, because that is what `tinygrad`'s
# `from tinygrad.codegen.opt import ...` call sites depend on:
#     n_OptOps        = 4   (TC, SPLIT, PADTO, SWAP)
#     n_Opt_fields    = 3   (op, axis, arg)
#     n_OptOps_calls  = (no public surface, the count is internal)
#     kernel_opt_is_bool = True  (the verdict mapping in postrange.bend)
#
# NOT PORTED, with the reason:
#   * `OptOps.__lt__` (auto value comparison) -- Bend `Data` constructors
#     are TOTAL FUNCTIONS over their tag, so the comparison is the
#     constructor's tag value, not a method. Not a port target.
#   * `Opt.__repr__` -- Python repr. The port has `IO.print` rows in the
#     gates that name the fields by hand.
#   * `check`'s `msg` argument as a string -- the port's gates are the
#     message surface, and the message is in the gate row, not in the
#     call.
