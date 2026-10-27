#!/usr/bin/env python3
"""oracle_shapes.py -- THE COMPARER for `tinybendygrad/nn/mnist_cnn.bend`.

    .venv/bin/python .agents/slop/mnist/oracle_shapes.py

WHY A COMPARER AND NOT A `row(...)` PRINT. `examples/beautiful_mnist.bend`'s
own header records the measurement: reverting a one-line fix in a copy leaves
`bend --check-only` GREEN, because the port's compilation IR is outside the law
system by design. **⇒ A PRINTED ROW IS A LABEL.** This file is what makes the
rows go red.

WHAT IT COMPARES, AND AGAINST WHAT.

    the port's `got=`            <- `./bin/bend tinybendygrad/nn/mnist_cnn.bend`
    CPython's OWN answer        <- `nn.Conv2d(...)(x).shape`, `Tensor.max_pool2d(...)`,
                                   `Tensor.flatten(1)`, `nn.Linear(...)(x).shape`,
                                   called on THIS repo's upstream `tinygrad`.

The port's `want=` is NOT what this file compares against: the `want=` is the
FORMULA's answer (computed by `gen_mnist_cnn.py` from the model's constants),
and the oracle's answer is upstream's CODE. Three derivations, and the oracle
asserts the first and the third agree -- which is what makes the `want=` worth
printing.

THE GRAPH ROWS ARE COMPARED ON THE PORT's SPELLING AND THE PORT's FIXTURE. The
port builds its graph over a BUFFER+RESHAPE fixture; CPython's `nn.Conv2d`
builds its graph over a CONT-backed parameter, so the NODE COUNTS are not
comparable and the oracle says so out loud instead of quietly comparing them.
The ROOT OP, the SOURCE COUNT and the SOURCE OPS are compared.

EXIT STATUS: 0 every compared row matched · 1 a row mismatched · 3 a
precondition was absent (no `bin/bend`, the port did not run, the port's rows
could not be parsed). AN ABSENT SUBJECT IS REFUSED, NEVER FAIL.
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(HERE))

import numpy as np  # noqa: E402

from tinygrad import Tensor, nn  # noqa: E402

import model as M  # noqa: E402

BEND = ROOT / "bin" / "bend"
PORT = ROOT / "tinybendygrad" / "nn" / "mnist_cnn.bend"

ROW = re.compile(r"^(\S+) got=(.*) want=(.*)$")


def port_rows() -> dict[str, tuple[str, str]]:
    """the port's rows, parsed out of its own stdout."""
    if not BEND.exists():
        raise FileNotFoundError(f"no {BEND}")
    r = subprocess.run([str(BEND), str(PORT)], capture_output=True, text=True, cwd=str(ROOT))
    if r.returncode != 0:
        raise RuntimeError(f"the port exited {r.returncode}: {r.stderr[-400:]}")
    out = {}
    for line in r.stdout.splitlines():
        m = ROW.match(line.strip())
        if m:
            out[m.group(1)] = (m.group(2), m.group(3))
    if not out:
        raise RuntimeError(f"the port printed no rows:\n{r.stdout[-400:]}")
    return out


def show(t) -> str:
    """the PORT's shape spelling: `MX.mx_show` -- the dims joined by a comma,
    no parentheses. CPython's `Tensor.shape` is a tuple."""
    return ",".join(str(d) for d in t.shape)


def sig(t) -> str:
    """the PORT's signature spelling: `MX.mxw_sig` (movement.bend:1380)."""
    us = t.uop.toposort()
    root = t.uop
    srcops = "|".join("Ops." + s.op.name for s in root.src)
    return f"n={len(us)} op=Ops.{root.op.name} nsrc={len(root.src)} srcops={srcops}"


def sig_shape_root(t) -> str:
    """the part of a signature that survives a fixture difference in the
    SOURCE OPS: the root op and the source count."""
    root = t.uop
    return f"op=Ops.{root.op.name} nsrc={len(root.src)}"


def sig_shape(t) -> str:
    """the part of a signature that does NOT depend on the fixture: the root op,
    the source count and the source ops. The node COUNT does depend on the
    fixture (a BUFFER+RESHAPE against CPython's CONT-backed parameter) and the
    oracle says so rather than comparing two things that cannot be equal."""
    us = t.uop.toposort()
    root = t.uop
    srcops = "|".join("Ops." + s.op.name for s in root.src)
    return f"op=Ops.{root.op.name} nsrc={len(root.src)} srcops={srcops}"


def cpython_answers() -> dict[str, str]:
    """CPython's OWN answers, from upstream's code in THIS repo."""
    C1, C2, K, PAD, POOL, NCLS = M.C1, M.C2, M.K, M.PAD, M.POOL, M.NCLS
    a = {}
    x_in = Tensor.zeros(1, 1, M.IN_H, M.IN_W)
    a["mnist_in_shape"] = show(x_in)

    conv1 = nn.Conv2d(1, C1, K, padding=PAD)(x_in)
    a["mnist_conv1_shape"] = show(conv1)
    # THE GRAPH COMPARISON IS FIXTURE-MATCHED: the port builds its conv over a
    # BUFFER weight and no bias, so CPython's side is `x.conv2d(w)` over a
    # numpy-backed weight and no bias. `nn.Conv2d(...)(x)` would add a BIAS ADD
    # that the port's fixture does not have.
    a["mnist_conv1_sig"] = sig_shape(x_in.conv2d(Tensor(np.zeros((C1, 1, K, K), np.float32))))

    a["mnist_relu1_shape"] = show(conv1.relu())

    pool1 = conv1.relu().max_pool2d(POOL)
    a["mnist_pool1_shape"] = show(pool1)

    x2 = Tensor.zeros(1, C1, M.POOL1_OUT_H, M.IN_W // POOL)
    conv2 = nn.Conv2d(C1, C2, K, padding=PAD)(x2)
    a["mnist_conv2_shape"] = show(conv2)
    a["mnist_conv2_sig"] = sig_shape(x2.conv2d(Tensor(np.zeros((C2, C1, K, K), np.float32))))

    a["mnist_pool2_shape"] = show(conv2.relu().max_pool2d(POOL))

    flat = Tensor.zeros(1, C2, M.POOL2_OUT_H, M.IN_W // POOL // POOL).flatten(1)
    a["mnist_flat"] = str(int(np.prod(flat.shape)))

    fc = nn.Linear(M.FLAT, NCLS)(Tensor.zeros(1, M.FLAT))
    a["mnist_fc_shape"] = show(fc)
    # WITH the bias the port's bias is a BUFFER and CPython's `nn.Linear` bias
    # is a CONT-backed ADD, so the SOURCE OPS differ and only the ROOT OP and
    # the SOURCE COUNT are comparable. The row still goes red if the port's
    # root op or source count changes.
    a["mnist_fc_sig"] = sig_shape_root(fc)
    a["mnist_fc_sig_nobias"] = sig_shape(nn.Linear(M.FLAT, NCLS, bias=False)(Tensor.zeros(1, M.FLAT)))

    n_conv1 = C1 * 1 * K * K + C1
    n_conv2 = C2 * C1 * K * K + C2
    a["mnist_nparam"] = str(n_conv1 + n_conv2 + NCLS * M.FLAT + NCLS)
    return a


# the pool's UNREDUCED shape is `noop ++ o_ ++ k_` (movement.bend:905) and the
# port prints it whole; CPython's `max_pool2d` returns the REDUCED shape, so
# the reduced row is the comparable one and the unreduced row is compared
# against the port's own `want=` (which the generator computed).
COMPARE_AGAINST_CPYTHON = [
    "mnist_in_shape",
    "mnist_conv1_shape",
    "mnist_relu1_shape",
    "mnist_pool1_shape",
    "mnist_conv2_shape",
    "mnist_pool2_shape",
    "mnist_flat",
    "mnist_fc_shape",
    "mnist_nparam",
]
COMPARE_GRAPH_AGAINST_CPYTHON = ["mnist_conv1_sig", "mnist_conv2_sig", "mnist_fc_sig_nobias"]
# the WITH-BIAS linear graph: the ROOT OP and the SOURCE COUNT only, because the
# bias's uop differs between the fixtures (the port's is a BUFFER, CPython's
# `nn.Linear` bias is a CONT-backed ADD).
COMPARE_GRAPH_ROOT_ONLY = ["mnist_fc_sig"]
COMPARE_AGAINST_OWN_WANT = ["mnist_pool1_full", "mnist_pool2_full"]


def main() -> int:
    try:
        rows = port_rows()
    except Exception as e:  # noqa: BLE001
        print(f"REFUSED: {type(e).__name__}: {e}", file=sys.stderr)
        return 3

    cp = cpython_answers()
    ok = bad = 0
    print(f"# port rows: {len(rows)}")
    for name in COMPARE_AGAINST_CPYTHON:
        if name not in rows:
            print(f"  {name}: ABSENT FROM THE PORT'S OUTPUT")
            bad += 1
            continue
        got = rows[name][0]
        want = cp.get(name, "<NO CPYTHON ANSWER>")
        if got == want:
            print(f"  {name}: MATCH  got={got}")
            ok += 1
        else:
            print(f"  {name}: MISMATCH got={got} cpython={want}")
            bad += 1
    for name in COMPARE_GRAPH_AGAINST_CPYTHON:
        if name not in rows:
            print(f"  {name}: ABSENT FROM THE PORT'S OUTPUT")
            bad += 1
            continue
        got = rows[name][0]
        # the port's own string carries the node count first; the comparable
        # part is everything after the first space.
        got_shape = got.split(" ", 1)[1] if " " in got else got
        want = cp.get(name, "<NO CPYTHON ANSWER>")
        if got_shape == want:
            print(f"  {name}: MATCH  got={got_shape}")
            ok += 1
        else:
            print(f"  {name}: MISMATCH got={got_shape} cpython={want}")
            bad += 1
    for name in COMPARE_GRAPH_ROOT_ONLY:
        if name not in rows:
            print(f"  {name}: ABSENT FROM THE PORT'S OUTPUT")
            bad += 1
            continue
        got = rows[name][0]
        got_root = " ".join(got.split(" ")[1:3])
        want = cp.get(name, "<NO CPYTHON ANSWER>")
        if got_root == want:
            print(f"  {name}: MATCH  got={got_root}  (root op and source count only)")
            ok += 1
        else:
            print(f"  {name}: MISMATCH got={got_root} cpython={want}")
            bad += 1
    for name in COMPARE_AGAINST_OWN_WANT:
        if name not in rows:
            print(f"  {name}: ABSENT FROM THE PORT'S OUTPUT")
            bad += 1
            continue
        got, want = rows[name]
        if got == want:
            print(f"  {name}: MATCH  got={got}")
            ok += 1
        else:
            print(f"  {name}: MISMATCH got={got} want={want}")
            bad += 1

    (HERE / "shapes.rows").write_text(
        "# shapes.rows -- generated by .agents/slop/mnist/oracle_shapes.py\n"
        "# columns: row port_got port_want cpython\n"
        + "\n".join(
            f"{n} {rows.get(n, ('ABSENT', 'ABSENT'))[0]} {rows.get(n, ('ABSENT', 'ABSENT'))[1]} {cp.get(n, 'NONE')}"
            for n in sorted(set(list(COMPARE_AGAINST_CPYTHON) + list(COMPARE_GRAPH_AGAINST_CPYTHON)
                                + list(COMPARE_GRAPH_ROOT_ONLY) + list(COMPARE_AGAINST_OWN_WANT)))
        ) + "\n"
    )
    print(f"# {ok} match, {bad} mismatch")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
