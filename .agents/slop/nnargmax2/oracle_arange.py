#!/usr/bin/env python
# oracle_arange.py -- CPython's OWN `arange` GRAPH, in the port's `mo_valsig`
# FORMAT, so the two sides are compared BYTE-IDENTICALLY and not by eye.
#
# THE FORMAT IS `mixin/op.bend:1248`'s: `<OP>/<nsrc>` per node, in toposort
# order, with `=<value>` appended for a CONST. `Ops.CONST`'s value is a Python
# object, so the port's spelling is reproduced here: an int is `i<decimal>`, a
# float is `f<6dp>`, a bool is `True`/`False`.
#
# THE ARGS ARE UPSTREAM'S: `tinygrad/mixin/op.py:166` `arange(start, stop=None,
# step=1, dtype=None)`. `arange(n)` is `start=n, stop=None`; `arange(n, 0, -1)`
# is `start=n, stop=0, step=-1` -- THE CALL `mixin/op.py:887` MAKES.
import sys

from tinygrad import Tensor, dtypes


def const_text(v):
  if isinstance(v, bool): return "True" if v else "False"
  if isinstance(v, int): return "i" + str(v)
  if isinstance(v, float): return "f" + ("%.6f" % v)
  return "x"


def sig(t):
  parts = []
  for u in t.uop.toposort():
    nm = u.op.name.replace("Ops.", "")
    val = ""
    if u.op.name == "Ops.CONST":
      val = "=" + const_text(u.arg)
    parts.append("%s/%d%s" % (nm, len(u.src), val))
  return "%d %s" % (len(t.uop.toposort()), " ".join(parts))


def main():
  which = sys.argv[1] if len(sys.argv) > 1 else "all"
  if which in ("all", "a3"):
    t = Tensor.arange(3, dtype=dtypes.u32)
    print("cp_arange3_u32=%s" % sig(t))
  if which in ("all", "a4"):
    t = Tensor.arange(4, dtype=dtypes.u32)
    print("cp_arange4_u32=%s" % sig(t))
  if which in ("all", "a4neg"):
    # `arange(n, 0, -1)` -- upstream's `mixin/op.py:887` call. The dtype is
    # `commit_int(1, n)` (op.py:190), which is what `arange` picks for itself.
    t = Tensor.arange(4, 0, -1)
    print("cp_arange4_neg=%s" % sig(t))
    print("cp_arange4_neg_dtype=%s" % t.dtype)
    print("cp_arange4_neg_shape=%s" % (t.shape,))
    print("cp_arange4_neg_values=%s" % (t.tolist(),))


if __name__ == "__main__":
  main()
