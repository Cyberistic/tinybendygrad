#!/usr/bin/env python3
"""bufs.py -- THE BUFFERS FOR EVERY WANTED KERNEL, FROM CPython's OWN DEVICE.

    .venv/bin/python .agents/slop/cpuseam/bufs.py            # all five
    .venv/bin/python .agents/slop/cpuseam/bufs.py r_56_7_2_2 # one

WHAT IT WRITES: ONE `.rows` PER KERNEL UNDER `bufs/`.  EACH ROW IS ONE BUFFER,
`bufN <hex>`, IN THE KERNEL's ARGUMENT ORDER, FOLLOWED BY `# bufN after <hex>`
-- THE SAME BUFFER'S BYTES AFTER CPython's OWN DEVICE RAN THE KERNEL.  THE
LAST TWO ROWS ARE `sizes <n,n,...>` AND A `#` COMMENT CARRYING THE LOGIT.

THE HEX IS LITTLE-ENDIAN f32 BYTES, THE PORT's OWN `Hex`/`Blob` SPELLING, SO THE
SAME BYTES CROSS THE SEAM IN BOTH DIRECTIONS.

WHERE THE BYTES COME FROM: CPython's OWN `CPU` DEVICE, HOOKED AT THE PROGRAM
CALL.  `CPUProgram.__call__` receives the buffer views it is about to hand to
`mmap`'d machine code, so hooking IT CAPTURES EXACTLY THE BYTES THE KERNEL
SEES -- THE INPUTS AND, AFTER THE CALL, THE OUTPUTS.

⇒ THIS IS THE ORACLE. NOTHING HERE IS TYPED.

⇒ ONE RUN CAPTURES EVERY KERNEL, BECAUSE THE MNIST FORWARD PASS RUNS THEM ALL
AND THE HOOK IS ON THE DEVICE, NOT ON THE KERNEL.
"""
import pathlib
import sys
import os

HERE = pathlib.Path(__file__).resolve().parent
MNIST = HERE.parent / "mnist"
sys.path.insert(0, str(MNIST))
sys.path.insert(0, str(HERE.parent.parent.parent))

WANT = sys.argv[1] if len(sys.argv) > 1 else ""

os.environ["DEV"] = "CPU"
os.environ["JIT"] = "0"

import numpy as np  # noqa: E402
from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.runtime.ops_cpu import CPUProgram  # noqa: E402
from model import Model, load_weights  # noqa: E402

# THE BUFFER SIZES, PER KERNEL, FROM THE KERNEL's OWN PARAM ROWS.  THE PAYLOAD's
# LAST FIELD IS `max_numel * dtype.itemsize` -- THE BUFFER's OWN BYTE SIZE, AS
# UPSTREAM's `CPUProgram` SIGNS ITS BUFFERS (ops_cpu.py:58-59).
SIZES: dict[str, list[int]] = {}
for p in sorted((HERE / "uops").glob("*.rows")):
    nm = p.stem
    sz = []
    for ln in p.read_text().splitlines():
        if ln.startswith("#") or not ln.strip():
            continue
        f = ln.split("|")
        if f[1] == "PARAM":
            sz.append(int(f[8].split("~")[-1]))
    SIZES[nm] = sz

WANTED = {n for n in SIZES if not WANT or n == WANT}
captured: dict[str, list] = {}


def hooked_call(self, *bufs, **kw):
    # the buffers UPSTREAM is about to hand to the machine code. THE VIEWS ARE
    # THE WHOLE ALLOCATIONS, so EACH ONE IS CUT TO THE KERNEL's DECLARED SIZE --
    # AND WITHOUT THE CUT THIS SCRIPT WROTE 34 GB.
    name = self.name
    shapes = SIZES.get(name)
    if shapes is None or len(shapes) != len(bufs):
        return orig_call(self, *bufs, **kw)
    # THE BUFFERS CROSS AS ADDRESSES (ops_cpu.py:61 PACKS THEM AS `ctypes.c_uint64`),
    # SO THE BYTES ARE READ AT THE ADDRESS.
    import ctypes
    cut = lambda vs: [ctypes.string_at(v, n) for v, n in zip(vs, shapes)]
    before = cut(bufs)
    out = orig_call(self, *bufs, **kw)
    after = cut(bufs)
    if name in WANTED:
        captured.setdefault(name, []).append((before, after))
    return out


orig_call = CPUProgram.__call__
CPUProgram.__call__ = hooked_call

X = np.load(MNIST / "data" / "mnist_test_images.npy", allow_pickle=False)[:1]
with Context(DEV="CPU"):
    m = Model()
load_weights(m, MNIST / "weights.npz")
with Context(DEV="CPU"):
    x = Tensor(X[0:1].astype(np.float32) / 255.0).realize()
    logits = m(x)
    lg = [float(v) for v in logits.flatten().tolist()]

OUT = HERE / "bufs"
OUT.mkdir(parents=True, exist_ok=True)
missing = sorted(WANTED - set(captured))
for nm in sorted(captured):
    before, after = captured[nm][0]
    sizes = []
    lines = []
    for i, (b, a) in enumerate(zip(before, after)):
        sizes.append(len(b))
        lines.append(f"buf{i} {b.hex()}")
        lines.append(f"# buf{i} after {a.hex()}")
    lines.append("sizes " + ",".join(str(x) for x in sizes))
    lines.append(f"# logit0 {lg[0]!r} argmax {int(np.argmax(lg))}")
    lines.append(f"# captured {len(captured[nm])} launches of {nm}")
    (OUT / f"{nm}.rows").write_text("\n".join(lines) + "\n")
    print(f"# {nm}: {len(sizes)} buffers, {len(captured[nm])} launches, sizes={sizes}")
print(f"# wrote {len(captured)} files to {OUT.name}/  missing={missing}")
raise SystemExit(1 if missing else 0)
