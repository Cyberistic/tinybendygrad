# tinybendygrad/__init__.bend -- port of tinygrad/__init__.py
#
# `tinygrad/__init__.py` is 10 lines, every one a re-export. There is no
# logic to port: the seven names this file exposes (`Tensor`, `TinyJit`,
# `function`, `UOp`, `Variable`, `dtypes`, `GlobalCounters`, `fetch`,
# `Context`, `getenv`, `Device`) live in their own modules, and `from X
# import Y` is Python's way of saying "the public surface of this package
# is the union of these names".
#
# In Bend there is no `__init__` indirection: every reader of
# `tinygrad/tensor.py` is also a reader of `tensor.bend`, and the
# one-to-one rule (one `.bend` per upstream `.py` at the same path) is
# what makes the port navigable. The shape is therefore the same as
# `viz/__init__.py` and the other empty-package markers: this file
# exists so a reader who looks for `tinybendygrad/__init__.bend` because
# they know `tinygrad/__init__.py` finds it.
#
# WHAT IS HERE, item by item against the upstream (1-indexed by line):
#   1-2  `TYPED` import hook          -- NOT PORTED. The `typeguard` integration
#                                        is a Python import-time side effect,
#                                        not a name to expose.
#   3    `from tinygrad.tensor import Tensor`            in `tensor.bend`
#   4    `from tinygrad.engine.jit import TinyJit`      NOT YET PORTED (`engine/jit.bend`
#                                                        exists; `TinyJit` itself is a
#                                                        TODO(p3) per `engine/jit.bend`).
#   5    `from tinygrad.function import function`       in `function.bend` (as `function_`,
#                                                        TS-reserved word).
#   6    `from tinygrad.uop.ops import UOp`              in `uop/ops.bend`
#        `Variable = UOp.variable`                       NOT YET PORTED (`UOp.variable` is
#                                                        a TODO(p3) in `uop/ops.bend`).
#   7    `from tinygrad.dtype import dtypes`             in `dtype.bend`
#   8    `from tinygrad.helpers import ...`              each name in `helpers.bend`:
#                                                          * `GlobalCounters` -- in `helpers.bend`
#                                                          * `fetch`         -- NOT YET PORTED
#                                                                                (helpers.bend has
#                                                                                no `fetch` def; the
#                                                                                URL/`CachedFile`
#                                                                                seam is a TODO(p3)).
#   9    `from tinygrad.device import Device`            NOT YET PORTED (`device.bend` has
#                                                        the registry as a `DEnt` table, not
#                                                        a `class Device` symbol).
#
# The four unported names are each a known wall and not a `__init__.py`
# problem: the wall is in the modules that DEFINE them, and a re-export
# here would land in the same gate as the def. Re-exporting names that
# do not yet exist would be a fence-post ahead of the fence.
#
# The gate is therefore the COUNT of names in scope, against CPython's
# `tinygrad.__init__`, and a row per name that is `True` if the
# definition lives in the named module, `False` if it is a TODO(p3).
