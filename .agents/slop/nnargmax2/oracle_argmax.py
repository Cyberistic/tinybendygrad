#!/usr/bin/env python
# oracle_argmax.py -- CPython's OWN `Tensor.argmax` ANSWERS, so the port's
# graph-level `argmax` rows carry UPSTREAM'S expectations and not the port's
# own output.
#
# THE RECIPE IS `tinygrad/mixin/op.py:863-888`:
#
#     m   = self.eq(self.max(axis=axis, keepdim=True))
#     idx = m * type(self).arange(self.shape[axis], 0, -1).reshape(self.shape[axis], *[1]*(self.ndim-axis-1))
#     return (self.shape[axis] - idx.max(axis=axis, keepdim=keepdim)).cast(dtypes.int32)
#
# EVERY ROW IS ONE OF ITS FOUR NODES, AND EVERY `want` IS CPython's OWN SHAPE OR
# DTYPE FOR THAT NODE. THE FIXTURE IS 1-D SO THE `.reshape` IS A NO-OP AND THE
# PORT'S 1-D FORM IS THE SAME RECIPE.
from tinygrad import Tensor, dtypes


def shp(t):
  return "(" + ",".join(str(d) for d in t.shape) + ("," if len(t.shape) == 1 else "") + ")"


def node(t):
  return "%s dt=%s" % (shp(t), t.dtype)


def main():
  t = Tensor([1.0, 7.0, 3.0, 2.0], device="PYTHON")
  n = t.shape[0]
  mx = t.max(axis=0, keepdim=True)
  m = t.eq(mx)
  ar = type(t).arange(t.shape[0], 0, -1)
  idx = m * ar
  imx = idx.max(axis=0, keepdim=False)
  res = t.shape[0] - imx
  out = res.cast(dtypes.int32)
  print("cp_t            = %s" % node(t))
  print("cp_mx           = %s" % node(mx))
  print("cp_m            = %s" % node(m))
  print("cp_ar           = %s" % node(ar))
  print("cp_idx          = %s" % node(idx))
  print("cp_imx          = %s" % node(imx))
  print("cp_res          = %s" % node(res))
  print("cp_out          = %s" % node(out))
  print("cp_out_value    = %s" % (out.tolist(),))
  # THE OTHER THREE FIXTURES, so the port's rows are not ONE fixture.
  for vals in ([5.0, 5.0, 5.0], [1.0, 9.0, 9.0, 2.0], [9.0, 1.0, 9.0]):
    u = Tensor(vals, device="PYTHON")
    v = u.argmax(0)
    print("cp_out_%d       = %s value=%s" % (len(vals), node(v), v.tolist()))


if __name__ == "__main__":
  main()
