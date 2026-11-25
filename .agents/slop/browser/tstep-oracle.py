# tstep-oracle.py -- THE TRAINING STEP'S EXPECTED VALUES, from CPython tinygrad.
#
# The graph is `.agents/slop/browser/tstepc.bend`'s, node for node, and the inputs are
# `fchain-harness.c`'s `seed()` -- the same 784/4/490 arrays, row-major -- plus the
# target that harness never needed:
#
#     t[i] = ((i*11) % 43)/43 - 0.5          (i = 0..9)
#
# and the step is `w - 0.1*g` (`sgd.mk`, lr = 0x3dcccccd).
#
# `_rop` DROPS the reduced axes (`tinygrad` `Tensor._rop`): `sum((3,5))` on
# `(1,1,14,2,14,2)` IS `(1,1,14,14)`, which is why the fixture's reshape there is an
# identity -- MEASURED, and it is what makes the shapes reconcile with `sh_out=:2:1x10`.
#
# Writes `tstep-want.rows`: `name=value` lines, one value per row, `%.9g`.
import numpy as np
from tinygrad import Tensor

NX, NW1, NW2, NT = 784, 4, 490, 10

def seed():
    x = np.array([(((i * 37) % 97) / 97.0) - 0.5 for i in range(NX)], dtype=np.float32)
    w1 = np.array([(i + 1) / 4.0 for i in range(NW1)], dtype=np.float32)
    w2 = np.array([(((i * 13) % 61) / 61.0) - 0.4 for i in range(NW2)], dtype=np.float32)
    t = np.array([(((i * 11) % 43) / 43.0) - 0.5 for i in range(NT)], dtype=np.float32)
    return x, w1, w2, t

def main():
    xv, w1v, w2v, tv = seed()
    x = Tensor(xv.reshape(1, 1, 28, 28))
    w1 = Tensor(w1v.reshape(1, 1, 2, 2))
    w2 = Tensor(w2v.reshape(49, 10))
    t = Tensor(tv.reshape(1, 10))

    xs = x.reshape(1, 1, 14, 2, 14, 2)
    ws = w1.reshape(1, 1, 1, 2, 1, 2)
    c1 = xs * ws
    f1 = c1.sum((3, 5))                      # (1,1,14,14)
    v1 = f1.reshape(1, 1, 14, 14)
    a2 = v1.relu()
    v2 = a2.reshape(1, 1, 7, 2, 7, 2)
    f3 = v2.max((3, 5))                      # (1,1,7,7)
    lhs = f3.reshape(1, 1, 49)
    w2r = w2.reshape(1, 49, 10)
    rhs = w2r.permute(0, 2, 1)               # (1,10,49)
    c4 = lhs * rhs
    out = c4.sum((2,))                       # (1,10)
    d = out - t
    loss = (d * d).sum((1,))                 # (1,)
    # this vendor's Tensor has no `requires_grad`; `gradient` is the functional form
    gw1t, gw2t = loss.gradient(w1, w2, gradient=Tensor.ones_like(loss))

    lr = 0.1
    w1n = (w1 - lr * gw1t).numpy().reshape(-1)
    w2n = (w2 - lr * gw2t).numpy().reshape(-1)
    outv = out.numpy().reshape(-1)
    lossv = float(loss.numpy().reshape(-1)[0])
    gw1 = gw1t.numpy().reshape(-1)
    gw2 = gw2t.numpy().reshape(-1)

    # THE ORACLE'S OWN CONTROL: a central finite difference on two entries of each
    # gradient. An oracle that has never been checked is a fixture against nobody.
    def loss_at(w1a: np.ndarray, w2a: np.ndarray) -> float:
        w1x = Tensor(w1a.reshape(1, 1, 2, 2)); w2x = Tensor(w2a.reshape(49, 10))
        xs2 = x.reshape(1, 1, 14, 2, 14, 2); ws2 = w1x.reshape(1, 1, 1, 2, 1, 2)
        f12 = (xs2 * ws2).sum((3, 5)).reshape(1, 1, 14, 14).relu()
        f32 = f12.reshape(1, 1, 7, 2, 7, 2).max((3, 5)).reshape(1, 1, 49)
        o2 = (f32 * w2x.reshape(1, 49, 10).permute(0, 2, 1)).sum((2,))
        d2 = o2 - t
        return float((d2 * d2).sum((1,)).numpy().reshape(-1)[0])

    h = 1e-2
    for label, base, gidx, gval in (("gw1_0", w1v, 0, gw1[0]), ("gw2_7", w2v, 7, gw2[7])):
        b1 = w1v.copy(); b2 = w2v.copy()
        if label.startswith("gw1"):
            b1[gidx] += h; lp = loss_at(b1, b2)
            b1[gidx] -= 2 * h; lm = loss_at(b1, b2)
        else:
            b2[gidx] += h; lp = loss_at(b1, b2)
            b2[gidx] -= 2 * h; lm = loss_at(b1, b2)
        fd = (lp - lm) / (2 * h)
        print("FD %s: analytic %.6f fd %.6f rel %.2e" % (label, gval, fd, abs(fd - gval) / max(1e-9, abs(gval))))

    rows = []
    for i, v in enumerate(outv):  rows.append(("out_%d" % i, v))
    rows.append(("loss", lossv))
    for i, v in enumerate(gw1):   rows.append(("gw1_%d" % i, v))
    for i, v in enumerate(w1n):   rows.append(("w1n_%d" % i, v))
    for i, v in enumerate(gw2):   rows.append(("gw2_%d" % i, v))
    for i, v in enumerate(w2n):   rows.append(("w2n_%d" % i, v))
    for i, v in enumerate(tv):    rows.append(("t_%d" % i, v))
    for i, v in enumerate(w1v):   rows.append(("w1_%d" % i, v))
    for i, v in enumerate(xv[:8]): rows.append(("x_%d" % i, v))
    for i, v in enumerate(w2v[:8]): rows.append(("w2_%d" % i, v))

    with open(".agents/slop/browser/tstep-want.rows", "w") as f:
        for k, v in rows:
            f.write("%s=%.9g\n" % (k, float(v)))
    print("wrote %d rows" % len(rows))
    print("out[0..3]", outv[:4], "loss", lossv)
    print("gw1", gw1, "w1n", w1n)

if __name__ == "__main__":
    main()
