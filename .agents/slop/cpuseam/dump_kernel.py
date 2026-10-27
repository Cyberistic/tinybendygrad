#!/usr/bin/env python3
"""dump_kernel.py -- UPSTREAM's REAL kernel, as TWO things the port can be checked against.

    .venv/bin/python .agents/slop/cpuseam/dump_kernel.py CPU 1

WHAT IT WRITES, and NOTHING ELSE:

  * `csrc/<name>.c`   -- the C SOURCE upstream's own `ClangRenderer` produced for that
                         kernel.  THIS IS THE ORACLE for the port's `cstyle.bend` assembler:
                         the port's `render_kernel` + `_render` must emit the same text.
  * `uops/<name>.rows` -- the UOP LIST upstream's scheduler produced for that kernel, one
                         row per uop, in upstream's own order, with the fields the C
                         SPELLING reads: op, dtype, addrspace, shape, the arg payload and
                         the src indices.

WHY A `.rows` AND NOT A HAND-TYPED FIXTURE: the brief's rule.  The expectations are
TRANSCRIBED BY SCRIPT, never typed: every field below is READ OUT OF UPSTREAM'S OWN
OBJECTS at run time.

WHY TWO FILES AND NOT ONE: the port's assembler must be able to produce the C from the
uop list ALONE -- that is the whole claim -- so the C file is the EXPECTATION and the
uop file is the INPUT, and a gate that compares them can tell which side broke.

THE HOOK: `ClangRenderer.render(self, uops)` is where upstream turns a uop list into C.
Wrapping it captures BOTH halves at once, from the same list, so the two files cannot
drift apart.
"""
import pathlib
import sys
import os

HERE = pathlib.Path(__file__).resolve().parent
MNIST = HERE.parent / "mnist"
CSRC = HERE / "csrc"
UOPS = HERE / "uops"


def dump_uops(uops) -> list[str]:
    """one row per uop: the fields the C spelling reads, in upstream's order.

    THE FORMAT IS `|`-DELIMITED, and the payload's own fields are `~`-delimited.
    MEASURED: the first version of this format was SPACE-separated with an
    EMPTY field for "no shape", and it was AMBIGUOUS -- row
    `32 INDEX f32 GLOBAL  1 index None 2 31` reads as `max_numel = 1` and
    `srcs = 2 31` only if you already know the field count, and the empty shape
    field shifts every column. A delimiter that cannot be empty is the fix.
    """
    rows = []
    idx = {u: i for i, u in enumerate(uops)}
    for i, u in enumerate(uops):
        srcs = " ".join(str(idx[s] + 1) for s in u.src)
        shape = u._shape
        shp = "" if shape is None else "x".join(str(int(d)) for d in shape)
        arg = u.arg
        kind = "plain"
        payload = "-"
        if u.op.name == "CONST":
            kind = "const"
            payload = repr(arg)
        elif u.op.name == "PARAM":
            kind = "param"
            payload = "~".join([
                str(arg.slot),
                str(arg.name) if arg.name is not None else "-",
                "1" if arg.volatile else "0",
                str(u.max_numel() * u.dtype.itemsize),
            ])
        elif u.op.name == "BUFFER":
            kind = "buffer"
            payload = "~".join([
                "1" if arg.volatile else "0",
                str(u.max_numel() * u.dtype.itemsize),
            ])
        elif u.op.name == "RANGE":
            kind = "range"
            payload = "~".join([str(getattr(arg[0], "name", arg[0]))] +
                               [str(x) for x in arg[1:]])
        elif u.op.name == "SPECIAL":
            kind = "special"
            payload = "~".join(str(x) for x in arg)
        elif u.op.name in ("INDEX", "SHRINK"):
            kind = "index"
            payload = str(arg) if isinstance(arg, int) else "-"
        elif u.op.name == "SINK":
            kind = "sink"
            payload = str(arg.function_name if arg is not None else "-")
        elif u.op.name in ("CALL", "CUSTOM_FUNCTION"):
            kind = "call"
            payload = str(getattr(arg, "name", "-"))
        numel = 1
        try:
            numel = u.max_numel()
        except RuntimeError:
            pass
        rows.append("|".join([
            str(i + 1), u.op.name, str(u.dtype.name),
            str(u.addrspace.name) if u.addrspace is not None else "NONE",
            shp, str(numel), srcs, kind, payload,
        ]))
    return rows


def main() -> int:
    device = sys.argv[1] if len(sys.argv) > 1 else "CPU"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    sys.path.insert(0, str(MNIST))
    sys.path.insert(0, str(HERE.parent.parent.parent))
    os.environ["DEV"] = device
    os.environ["JIT"] = "0"

    import numpy as np
    from tinygrad import Tensor, Context
    from tinygrad.renderer.cstyle import ClangRenderer
    from model import Model, load_weights

    CSRC.mkdir(parents=True, exist_ok=True)
    UOPS.mkdir(parents=True, exist_ok=True)

    seen: dict[str, int] = {}
    captured: list[tuple[str, str, list[str]]] = []
    reprs: list[tuple[str, list, list[str]]] = []

    orig_render = ClangRenderer.render

    def hooked(self, uops):
        src = orig_render(self, uops)
        name = getattr(self, "name", None) or f"k{len(captured)}"
        # upstream's function name is the SINK's arg.function_name
        for u in uops:
            if u.op.name == "SINK" and u.arg is not None:
                name = u.arg.function_name
        nm = name.replace(":", "_")
        captured.append((nm, src, dump_uops(uops)))
        reprs.append((nm, list(uops), []))
        return src

    ClangRenderer.render = hooked

    X = np.load(MNIST / "data" / "mnist_test_images.npy", allow_pickle=False)[:n]
    with Context(DEV=device):
        m = Model()
    load_weights(m, MNIST / "weights.npz")
    with Context(DEV=device):
        x = Tensor(X[0:1].astype(np.float32) / 255.0).realize()
        logits = m(x)
    lg = [float(v) for v in logits.flatten().tolist()]
    print(f"# device={device} captured={len(captured)} logit0={lg[0]!r} argmax={int(np.argmax(lg))}")

    if os.environ.get("DUMP_REPR"):
        (HERE / "uops_repr.out").write_text("\n".join(
            f"=== {nm} ===\n" + "\n".join(repr(u) for u in ups) for nm, ups, _ in reprs) + "\n")
        print(f"# repr={(HERE / 'uops_repr.out').name}")

    for nm, src, rows in captured:
        seen[nm] = seen.get(nm, 0) + 1
        (CSRC / f"{nm}.c").write_text(src)
        (UOPS / f"{nm}.rows").write_text(
            f"# {nm}.rows -- generated by .agents/slop/cpuseam/dump_kernel.py\n"
            "# columns: idx|op|dtype|addrspace|shape|numel|srcs(1-based)|kind|payload(~-separated)\n"
            + "\n".join(rows) + "\n")
    print(f"# distinct={len(seen)} csrc={len(seen)} uops={len(seen)}")
    for nm, k in sorted(seen.items()):
        print(f"#   {nm} x{k} c_bytes={len((CSRC / (nm + '.c')).read_text())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
