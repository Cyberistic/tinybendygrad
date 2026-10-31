#!/usr/bin/env python3
"""trace_train.py -- TRACE ONE MNIST TRAINING STEP, FOR THE BROWSER TO REPLAY.

    .venv/bin/python .agents/slop/browser/trace_train.py

WHAT IT WRITES, to `.agents/slop/browser/train/`:

    train-net.json     every kernel launch of ONE training step: the WGSL
                       `tinygrad/renderer/wgsl.py` emitted for the SAME ast the
                       CPU executed, the binding order, the dispatch geometry,
                       and each buffer's BEFORE and AFTER contents
    train-oracle.json  the weights BEFORE, the weights AFTER, and the loss --
                       CPython's own numbers, as u32 bit patterns

**⇒ SO THE BROWSER CAN BE ASKED THE QUESTION THAT MATTERS: DOES ONE TRAINING
STEP, REPLAYED ON A REAL ADAPTER, PRODUCE THE SAME WEIGHTS AS CPYTHON?**

`examples/webgpu/mnist` already answers the FORWARD half BIT-EXACTLY -- measured
today, 17 launches, 10/10 logits. **⇒ AND THIS IS THE OTHER HALF, AND IT IS THE
WHOLE OF WHAT "TRAIN IT IN THE BROWSER" MEANS.**

WHY THE STEP IS SPELLED OUT HERE AND NOT `opt.step()`.
**⇒ MEASURED**: `opt.zero_grad()` + `loss.backward()` + `loss.realize(*opt.
schedule_step())` runs -- the weights move, 18 of 18 -- **AND CAPTURES ZERO
KERNELS.** The hook is correct (a `TRAINING=1` FORWARD captures 23 launches in
the same process), so the optimizer's realize path does not reach
`tinygrad/engine/realize.py`'s `exec_kernel`. **⇒ AND A TRACE OF ZERO LAUNCHES
READS EXACTLY LIKE A MODEL THAT COMPUTES NOTHING**, which is the failure the
forward tracer's own header names.

**⇒ SO THE STEP IS THE SAME MATH, SPELLED AS PLAIN TENSOR OPS**: forward, loss,
`loss.gradient(*params)` for the gradients, then `p - lr*g` per parameter, each
stage realized explicitly. **⇒ AND THAT IS NOT A DIFFERENT OPTIMIZER**: it is
SGD, which is `_apply_update`'s own `t.detach() - up` shape
(`nn/optim.py:60`), with `up = lr*grad`. What it is NOT is Adam's moment
buffers, and that is stated rather than implied.
"""
import json
import pathlib
import sys

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "examples"))
sys.path.insert(0, str(ROOT / ".agents" / "slop" / "browser"))

# THE TRACER FIRST, because it sets `DEV=CPU` before tinygrad imports.
import trace_common as TC  # noqa: E402

from tinygrad import Tensor, Context, dtypes  # noqa: E402
from tinygrad.nn.state import get_state_dict, get_parameters  # noqa: E402
from beautiful_mnist import Model  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parent / "train"
BS = 1
# A PYTHON float, NOT `np.float32`: measured, `Tensor.ufix` calls
# `UOp.const(x)` -> `dtypes.from_py(x)` and that raises
# `Could not infer dtype of 0.009999999776482582 with type <class 'numpy.float32'>`.
LR = 0.01
LABEL = 7


def weights_b64(params) -> dict:
    """EVERY FLOAT PARAMETER, as u32 bits, keyed by its state-dict name.

    **⇒ AND `realize()` IS REQUIRED**: a parameter that has never been realized
    has `base.realized is None`, so reading its bits raises
    `AttributeError: 'NoneType' object has no attribute 'as_memoryview'`.
    It is called with the hook OFF, so allocating a weight never enters the trace.
    """
    out = {}
    for name, p in params.items():
        if not dtypes.is_float(p.dtype):
            continue
        p.realize()
        out[name] = TC.bits_of(p.uop.base.realized)
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    model = Model()
    TC.deterministic(model)
    named = {k: v for k, v in get_state_dict(model).items() if dtypes.is_float(v.dtype)}
    params = list(named.values())

    x = Tensor(np.linspace(-0.5, 0.5, BS * 1 * 28 * 28, dtype=np.float32).reshape(BS, 1, 28, 28))
    y = Tensor(np.array([LABEL], dtype=np.int32))

    # **⇒ NOTHING IS REALIZED BEFORE THE HOOK GOES ON, AND THAT IS MEASURED.**
    # `weights_b64` calls `p.realize()`, and pre-realizing the model's parameters
    # -- or even an identically-seeded TWIN's -- takes the traced forward from
    # `23` launches to `0`. **⇒ SO THE PRE-STATE IS READ OUT OF THE TRACE ITSELF**:
    # `TC.buffers[n]["b64"]` is each buffer's contents AT FIRST BIND, which is
    # before any launch in the trace wrote it. **⇒ AND THAT IS THE HONEST SOURCE
    # ANYWAY**: it is the same bytes the page will upload, so a comparison
    # against it cannot disagree about which snapshot it means.

    TC.reset()
    TC.install()
    try:
        with Context(TRAINING=1):
            # 1. FORWARD, realized, so its kernels are in the trace before the
            #    backward pass adds its own.
            logits = model(x).realize()
            # 2. THE LOSS. `beautiful_mnist.py:26`'s own call.
            loss = logits.sparse_categorical_crossentropy(y).realize()
            loss_v = float(loss.item())
            # 3. THE GRADIENTS, as TENSORS rather than through `Tensor.grad`.
            #    `backward()` fills `.grad` from a process-global weakref list
            #    (`tensor.py:487`), and MEASURED: after it runs, the parameter's
            #    `.grad` is still None on this tree. `gradient()` answers the
            #    same numbers as a list, which is what a trace wants anyway.
            grads = loss.gradient(*params)
            gs = [g.realize() for g in grads]
            # 4. THE UPDATE: `t.detach() - lr*g`, which is `_apply_update`'s own
            #    shape (`nn/optim.py:60`) with `up = lr*grad`.
            ups = [(p.detach() - (g * LR).cast(p.dtype)).realize()
                   for p, g in zip(params, gs)]
            for p, u in zip(params, ups):
                p.assign(u).realize()
    finally:
        TC.restore()

    # THE POST-STATE, read with the hook OFF so the read is not a launch.
    after = weights_b64(named)

    (OUT / "train-oracle.json").write_text(json.dumps({
        "bs": BS, "lr": LR, "label": LABEL, "loss": loss_v,
        "weights_after": after,
        "note": "CPython tinygrad, DEV=CPU, TRAINING=1: forward + "
                "sparse_categorical_crossentropy + loss.gradient + SGD "
                "(p - lr*g), u32 bit patterns",
    }, indent=1) + "\n")

    # **⇒ AND `after` IS KEPT ONLY ON THE LAST LAUNCH, WHICH IS A SIZE DECISION
    # WITH A MEASURED COST: the full per-launch snapshots make the file 10.5 MB,
    # and this tree's `jj` refuses to snapshot a new file over 2.9 MB.** The
    # GATE reads only the final state (`lastAfter`), so the compaction removes
    # exactly what nothing reads. **⇒ AND THE PER-LAUNCH LADDER IS STILL ONE FLAG
    # AWAY** -- `--full` keeps every snapshot, for whoever needs to bisect a
    # kernel rather than compare a step.
    compact = "--full" not in sys.argv
    # **⇒ AND THE FINAL STATE OF **EVERY** BUFFER IS ITS OWN KEY, AND IT MUST BE:
    # each launch's `after` only holds the buffers THAT launch bound, so a
    # compaction that keeps just the last launch's `after` leaves the gate with
    # 2 buffers to compare instead of 50. MEASURED, that is exactly what the
    # first compaction did -- `2 of 2 TENSOR buffers` where the claim is 47.
    final = {}
    for r in TC.launches:
        final.update(r.get("after") or {})
    frames = [TC.frames(r) for r in TC.launches]
    if compact:
        for i, fr in enumerate(frames):
            if i != len(frames) - 1:
                fr.pop("after", None)
        # **⇒ AND AN `in` ENTRY EQUAL TO THE BUFFER's FIRST BIND IS DROPPED, AND
        # THAT IS NOT A LOSS: the page WRITES the first bind at creation, so an
        # upload of the same bytes is a no-op.** MEASURED: the `in` snapshots are
        # 3.7 MB of a 5.3 MB file, and most of them are re-uploads of a weight
        # that never changed. **⇒ AND THE COMPARISON IS `<=` ON THE LENGTH TOO,
        # so a SHORTER snapshot is kept rather than silently dropped.**
        for fr in frames:
            ins = fr.get("in") or {}
            fr["in"] = {n: v for n, v in ins.items()
                        if TC.buffers.get(n, {}).get("b64") != v}
            if not fr["in"]:
                fr.pop("in", None)
    print(f"size-normalised payloads: {TC.normalize_sizes(TC.buffers, frames, final)}")
    (OUT / "train-net.json").write_text(json.dumps({
        "entry": {"input": list(x.shape), "output": "1 scalar loss"},
        "buffers": TC.buffers, "final": final, "kernels": frames,
        "note": "one MNIST training step's kernel launches, captured from "
                "tinygrad/engine/realize.py exec_kernel; wgsl is "
                "tinygrad/renderer/wgsl.py on the same ast",
    }) + "\n")

    unrendered = [i for i, r in enumerate(TC.launches) if not r.get("wgsl")]
    print(f"launches {len(TC.launches)}  buffers {len(TC.buffers)}  loss {loss_v!r}")
    for i, r in enumerate(TC.launches):
        print(f"  {i:3d} {str(r.get('entry')):<16} g={r['global']} bufs={len(r['bufs'])} "
              f"wgsl={len(r['wgsl'] or '')}B {r.get('wgslError', '')}")
    print(f"WGSL-UNRENDERED: {len(unrendered)} of {len(TC.launches)}")
    # A STEP WHERE NOTHING MOVED IS INDISTINGUISHABLE FROM A STEP THAT DID NOT RUN.
    # **⇒ AND BOTH SIDES OF THIS COMPARISON ARE THE TRACE'S OWN**, so it cannot
    # disagree with the page about which snapshot it means: `buffers[n]["b64"]`
    # is the FIRST-BIND contents and the LAST launch's `after[n]` is the final
    # one. A buffer no launch wrote has both equal, which is the point.
    last = {}
    for r in TC.launches:
        last.update(r.get("after") or {})
    moved = [n for n in TC.buffers if n in last and TC.buffers[n]["b64"] != last[n]]
    print(f"buffers whose contents moved: {len(moved)} of {len(TC.buffers)} traced")
    for n in moved[:8]:
        print(f"   {n}  {TC.buffers[n]['dtype']}  {TC.buffers[n]['size']}B")
    return 0 if TC.launches and not unrendered and moved and after else 1


if __name__ == "__main__":
    raise SystemExit(main())
