#!/usr/bin/env python3
"""SURFACE2 stage 4 -- the three bins, computed from stage 3's measurement.

Nothing here decides anything by NAME. A bin is read off `stage3-classify.txt`, which
counted the device seams each method's INVOKE crossed, and the tie-breaks that need a
judgement are listed as judgements with the datum that settles them.

    .venv/bin/python .agents/slop/surface2/stage4-bins.py
"""
import ast, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
MEAS = os.path.join(HERE, "stage3-classify.txt")

PRESENT = {"__init__", "_apply_uop", "alu", "_uop", "_wrap_uop", "const", "is_param_",
           "__repr__", "__hash__", "__len__", "device", "shape", "dtype", "replace",
           "assign", "backward", "_mop", "_rop",
           # CLOSED by this unit -- see stage5. `as_param` -> `tn_as_param`, three
           # separator facts on one line, mutations A21-A24 in asparam-mutate.sh.
           "as_param"}

# THE JUDGEMENTS, with the datum. A method with 0 hard seams lands in B or C on one of
# these, and each line says which datum settled it.
JUDGED_B = {
  "_buffer":     "crosses 0 seams, but RETURNS THE DEVICE HANDLE and all four bin-A "
                 "readers are written in terms of it (`self._buffer().as_memoryview`, "
                 "tensor.py:285). One step from the seam, not on it.",
  "clone":       "0 seams, MOVE=2. A second buffer WITHOUT a copy -- the same bytes are "
                 "reachable through `assign`.",
  "to":          "0 seams. `device='PYTHON'` on a `PYTHON` tensor is the IDENTITY arm "
                 "(tensor.py:357-358); the migrating arms are `clone`/`copy_to_device`.",
  "to_":         "0 seams. `to` plus `replace`, both of whose identities are above.",
  "shard":       "0 seams, MOVE=3. UNSHARD is in GroupOp.Movement, so MOVE counts it -- "
                 "and it is a PLACEMENT, not a reshape a caller performs.",
  "shard_":      "as `shard`, plus `replace`.",
  "shard_like":  "0 seams. Its identity arm is `to`.",
  "call":        "0 seams. A CUSTOM_FUNCTION call body; launching it is `realize`'s job.",
  "custom_kernel": "0 seams. `UOp.custom_kernel` is `placeholder_like` + `.call` + "
                   "`after` (ops.py:1313-1316) -- three pure graph steps.",
  "__setitem__": "0 seams, MOVE=2. A write THROUGH A VIEW. `assign` (present, spine) "
                 "covers the whole-tensor write, so this widens what can be addressed, "
                 "not whether anything can be launched or read.",
  "decode_hevc_frame": "0 seams. AND the shape of its own RESULT IS UNREADABLE upstream: "
                       "tensor.py:563 passes arg=\"encdec\" where ops.py:1259 declares "
                       "CustomFunction(name:str, dtype:DType), so `dtype_from_uop` reads "
                       "`arg.dtype` off a str and raises. Upstream DEFECT, reported not "
                       "fixed (tensor.py is read-only here).",
}
JUDGED_C = {
  "__del__":     "0 seams. `all_tensors.pop(weakref.ref(self), None)` -- a GC finalizer.",
  "__bool__":    "0 seams. `raise TypeError` unconditionally; its whole observable is an "
                 "exception, which a pure Bend def cannot raise (the file's own wall at "
                 ":331). NOT CLOSED: a row over a def whose body is a literal would be a "
                 "tautology, and an ungated method is an assertion.",
  "__delitem__": "0 seams. `raise TypeError(\"Tensor does not support deleting items\")` "
                 "-- a REFUSAL. Same reason as `__bool__`: not closed.",
  "from_url":    "0 seams. `fetch` is `urllib` (helpers.py:470) and then `Tensor(Path)`.",
  "manual_seed": "0 seams. Its entire effect is on three class dicts; the only observable "
                 "is `Tensor.rand(n).numpy()`, which needs RNG + realize + readback. "
                 "UNGATEABLE BY NATURE, not by omission.",
  "__eq__":      "0 seams. One line of sugar over `self.eq(x)` (tensor.py:549).",
}
for op in ("iadd", "isub", "imul", "itruediv", "ifloordiv", "ipow", "iand", "ior", "ixor",
           "ilshift", "irshift", "imatmul"):
  JUDGED_C["__%s__" % op] = ("0 seams, 0 movement nodes (0 for `__imatmul__`, which "
                            "reshapes 4 INTERNAL buffers). `self.assign(self.<op>(x))` -- "
                            "sugar over `assign`, which IS present.")

LAUNCH_ARTIFACT = {"linear_with_vars", "schedule_linear"}  # return an `Ops.LINEAR` uop


def measured():
  rows = {}
  for line in open(MEAS):
    m = re.match(r"^(\S+)\s+(OK|RAISED)\s+(\S*)\s+(\d+)\s+(\S+)", line)
    if m:
      rows[m.group(1)] = (m.group(2), m.group(3), int(m.group(4)), m.group(5))
  return rows


def main():
  up = {}
  tree = ast.parse(open(os.path.join(ROOT, "tinygrad", "tensor.py")).read())
  cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Tensor")
  up = {n.name: n.lineno for n in cls.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
  meas = measured()
  missing = sorted(set(up) - PRESENT, key=lambda k: up[k])

  A, B, C = [], [], []
  for m in missing:
    st, seams, move, what = meas.get(m, ("?", "", 0, "?"))
    hard = [s for s in seams.split(",") if s in ("ALLOCATE", "LAUNCH", "READBACK")]
    if hard or m in LAUNCH_ARTIFACT:
      A.append(m)
    elif m in JUDGED_B:
      B.append(m)
    elif m in JUDGED_C:
      C.append(m)
    else:
      raise SystemExit("UNBINNED: %s (seams=%r move=%d what=%r)" % (m, seams, move, what))

  print("DENOMINATOR (AST, class Tensor)          : %d" % len(up))
  print("PRESENT                                  : %d  (%.1f%%)" % (len(PRESENT), 100.0 * len(PRESENT) / len(up)))
  print("MISSING                                  : %d" % len(missing))
  print()
  print("BIN A  NEEDED TO BE A DEVICE             : %2d of %d" % (len(A), len(missing)))
  print("BIN B  NEEDED TO BE USEFUL               : %2d of %d" % (len(B), len(missing)))
  print("BIN C  NOT A DEVICE CONCERN              : %2d of %d  (%.0f%% of the gap)" % (
    len(C), len(missing), 100.0 * len(C) / len(missing)))
  print()
  print("A:", ", ".join(A))
  print()
  print("B:", ", ".join(B))
  print()
  print("C:", ", ".join(C))
  print()
  print("cross-check against the MEASUREMENT, every member:")
  for m in missing:
    st, seams, move, what = meas.get(m, ("?", "", 0, "?"))
    bin_ = "A" if m in A else ("B" if m in B else "C")
    print("  %s %-18s status=%-6s seams=%-18s move=%-2d holds=%s" % (
      bin_, m, st, seams or "-", move, what))
  unmeasured = [m for m in missing if m not in meas]
  print()
  print("UNMEASURED (an ungated bin member would be an assertion):", unmeasured or "none")


if __name__ == "__main__":
  main()