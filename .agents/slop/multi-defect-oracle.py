#!/usr/bin/env python3
"""multi-defect-oracle.py -- CPython's answers for the WIDE probe, on the same fixtures.

Every value is produced by executing the comprehension / `index` call from multi.py at the
cited line. Nothing is restated. Run it twice; it is byte-identical across runs.

    .venv/bin/python .agents/slop/multi-defect-oracle.py
"""
import sys
sys.path.insert(0, '.')


def fmt(t):
  return "(" + ", ".join(str(x) for x in t) + ("," if len(t) == 1 else "") + ")"


def rs_local(dims, axes, counts):
  """multi.py:139  `s//count if a in new_axs else s for a,s in enumerate(new_shape)`.

  UPSTREAM DIVIDES UNCONDITIONALLY on this line -- there is no divisibility test, because
  multi.py:133 already raised if `new_shape[new_ax] % count != 0`. The PORT re-tests
  divisibility per dim and answers `mu_sym_dim()` (0) when a dim is indivisible rather than
  truncating. That is a DELIBERATE divergence, so the port's 0 and CPython's floor-division
  are two different claims; both are printed so the reader can see which one it is looking at.
  """
  new_axs = set(axes)
  cnt = {}
  for a, c in zip(axes, counts):
    cnt.setdefault(a, c)
  out, sym = [], []
  for a, s in enumerate(dims):
    if a in new_axs:
      c = cnt[a]
      if s % c == 0:
        out.append(s // c)
      else:
        out.append(0)          # the port's mu_sym_dim() marker, NOT CPython's floor
        sym.append(a)
    else:
      out.append(s)
  return tuple(out), tuple(sym)


def rs_rev(arg_acc, target):
  """multi.py:132  `arg_acc[::-1].index(target)`, and new_ax = len(arg_acc) - i - 1."""
  r = arg_acc[::-1]
  try:
    i = r.index(target)
    return i, len(arg_acc) - i - 1, 1
  except ValueError:
    return None, 0, 0


def acc(new_shape):
  """multi.py:128-129  arg_acc = [1]; for s in new_shape: arg_acc.append(simplify(acc[-1]*s))."""
  a = [1]
  for s in new_shape:
    a.append(a[-1] * s)
  return a


def main():
  out = []
  # ---- nsl: rs_local over the same 10 fixtures multi-defect-probe.bend asks for.
  NSL = [("d0", (4, 6), (0, 1), (2, 3)), ("keep1", (4, 6), (1, 0), (2, 3)),
         ("none", (4, 6), (), ()), ("emptyax", (4, 6), (7, 8), (2, 3)),
         ("evendiv", (3, 5), (0, 1), (2, 4)), ("odddiv", (5, 6), (0, 1), (2, 3)),
         ("c1", (4, 6), (0, 1), (1, 1)), ("big", (12, 18), (0, 1), (4, 6)),
         ("swap", (4, 6), (1, 0), (2, 3)), ("sameax", (4, 6), (0, 0), (2, 3))]
  for nm, dims, axes, counts in NSL:
    val, sym = rs_local(dims, axes, counts)
    out.append((f"nsl {nm}", f"{fmt(val)}  sym={fmt(sym)}"))

  # ---- rst: rs_rev over arg_acc. `rs_acc([a,b])` is `[1, a, a*b]` (multi.bend:1135).
  RST = [("t_a", (4, 6), 4), ("t_ab", (4, 6), 24), ("t_1", (4, 6), 1),
         ("t_miss", (4, 6), 5), ("t_a1", (1, 6), 1), ("t_eq", (4, 6), 6)]
  for nm, shp, w in RST:
    a = acc(shp)
    i, new_ax, found = rs_rev(a, w)
    out.append((f"rst {nm}", f"arg_acc={fmt(tuple(a))} rev={fmt(tuple(a[::-1]))} "
                             f"i={i} new_ax={new_ax} found={found}"))
  RST3 = [("t3_12", (2, 3, 4), 6), ("t3_24", (2, 3, 4), 24), ("t3_1", (2, 3, 4), 1),
          ("t3_eq", (1, 1, 4), 1)]
  for nm, shp, w in RST3:
    a = acc(shp)
    i, new_ax, found = rs_rev(a, w)
    out.append((f"rst3 {nm}", f"arg_acc={fmt(tuple(a))} rev={fmt(tuple(a[::-1]))} "
                              f"i={i} new_ax={new_ax} found={found}"))

  # ---- exa: multi.py:143  `ax+shift for ax,_ in multi.sharding`, shift = len(root.marg).
  for nm, sh, k in [("e0", ((0, 4),), 0), ("e1", ((0, 4),), 1), ("e2", ((1, 4),), 1),
                    ("e3", ((0, 4), (1, 4)), 2), ("e3b", ((0, 4), (1, 4)), 3)]:
    out.append((f"exa {nm}", fmt(tuple(ax + k for ax, _ in sh))))

  # ---- flf: multi.py:184  `[i for i,x in enumerate(root.marg) if x]`.
  for nm, marg in [("f00", (0, 0)), ("f04", (0, 4)), ("f34", (3, 4)), ("f20", (2, 0)),
                   ("f11", (1, 1)), ("f010", (0, 1, 0)), ("f123", (1, 2, 3))]:
    out.append((f"flf {nm}", fmt(tuple(i for i, x in enumerate(marg) if x))))

  # ---- skk: multi.py:174  `remaining.remove((ax, rng))`, so sk_keep is set difference.
  for nm, sh, dr in [("k_none", ((0, 4), (1, 4)), ()), ("k_drop0", ((0, 4), (1, 4)), ((0, 4),)),
                     ("k_drop1", ((0, 4), (1, 4)), ((1, 4),)),
                     ("k_drop2", ((0, 4), (1, 4)), ((0, 4), (1, 4)))]:
    rem = list(sh)
    for d in dr:
      if d in rem:
        rem.remove(d)
    out.append((f"skk {nm}", str(len(rem))))

  w = max(len(r[0]) for r in out)
  for n, v in out:
    print(f"{n.ljust(w)}  {v}")


if __name__ == "__main__":
  main()
