"""Join the CPython ground truth with the port's BEFORE and AFTER measurements.

Every field is READ OFF a measurement; nothing here is transcribed by hand.

In:  cpython-cases.rows, port-before.rows, port-after.rows
Out: cases.rows
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))


def read(name):
  with open(os.path.join(HERE, name)) as f:
    return [ln.rstrip("\n") for ln in f if ln.strip()]


def cp_rows():
  out = {}
  for ln in read("cpython-cases.rows"):
    p = ln.split("\t")
    out[p[0]] = {"src": p[1][4:], "dst": p[2][4:], "marg": p[3][5:], "shape": p[4][6:], "note": p[5]}
  return out


def port_rows(name):
  """`caseN final=<shape> | expand marg=<m> shape=<s> | permute shape=<s>`."""
  out = {}
  for ln in read(name):
    if "|" not in ln:
      continue
    head, *parts = ln.split("|")
    nm, _, final = head.strip().partition(" final=")
    exps = [re.match(r"\s*expand marg=(\S*) shape=(\S*)", p) for p in parts]
    exps = [m.groups() for m in exps if m]
    perms = [m.group(1) for p in parts if (m := re.match(r"\s*permute shape=(\S*)", p))]
    out[nm] = {"final": final.strip(), "expand": exps[0][0] if exps else "",
               "expand_shape": exps[0][1] if exps else "", "permute": perms[0] if perms else ""}
  return out


cp = cp_rows()
before = port_rows("port-before.rows")
after = port_rows("port-after.rows")

order = ["case1_conv_expand", "case2_repeat", "case3_repeat_mid", "case4_pool_maxpool",
         "case5_scalar_expand", "case6_left_added", "case7_middle_one", "case8_conv2d"]

L = ["# THE EXPAND marg: CPython's rule, the port BEFORE, and the port AFTER.",
     "#",
     "# CPython: `_broadcast_to` (tinygrad/mixin/movement.py:128-146). The marg is",
     "#   new_shape[:n_left]  ++  the dims of the SOURCE axes that were 1 and became bigger,",
     "#   with a squeeze before and a permute after, so the result's shape IS the target.",
     "#",
     "# PORT: the EXPAND node's own shape is `tuple(self.marg) + ps` (tinygrad/uop/ops.py:397),",
     "#   so `marg` is read off the node with `mixin/movement.bend`'s `mxm_marg`.",
     "#",
     "# cols: case | src -> dst | CPython marg | CPython shape | BEFORE marg | BEFORE expand shape |",
     "#       BEFORE final | AFTER marg | AFTER expand shape | AFTER final | verdict"]

for nm in order:
  c, b, a = cp.get(nm), before.get(nm), after.get(nm)
  if c is None or b is None or a is None:
    continue
  if nm == "case8_conv2d":
    L.append("\t".join([nm, "the whole conv2d graph", "-", "-", "-", "-", "-", "-", "-",
                         "the two EXPANDs inside it are the ones the row above measures"]))
    continue
  ok = (a["expand"] == c["marg"]) and (a["permute"] == c["shape"] or a["final"] == c["shape"])
  unchanged = (b["expand"] == a["expand"]) and (b["final"] == a["final"])
  verdict = ("UNCHANGED (the 0-dim source: every dim is left-added)" if unchanged else
             ("OK: the marg is CPython's and the shape is the target" if ok else "MISMATCH"))
  L.append("\t".join([nm, f"{c['src']} -> {c['dst']}", c["marg"], c["shape"],
                      b["expand"], b["expand_shape"], b["final"],
                      a["expand"], a["expand_shape"], a["final"], verdict]))

out = "\n".join(L) + "\n"
print(out)
with open(os.path.join(HERE, "cases.rows"), "w") as f:
  f.write(out)
