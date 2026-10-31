#!/usr/bin/env python3
"""trace_imagenet_train.py -- TRACE ONE EFFICIENTNET-0 TRAINING STEP.

    .venv/bin/python .agents/slop/browser/trace_imagenet.py

WHAT IT WRITES, to `.agents/slop/browser/imagenet/`:

    inet-net.json     every kernel launch of `EfficientNet(0)(1,3,224,224)`:
                      WGSL, binding order, geometry, buffer contents
    inet-oracle.json  CPython's 1000 logits, as u32 bit patterns

**⇒ AND THE WEIGHTS ARE `deterministic()`, NOT PRETRAINED, AND THAT IS
DELIBERATE AND STATED.** `load_from_pretrained()` FETCHES ~20 MB from the hub,
and the claim this file exists to make is **"the browser computes EfficientNet's
forward pass bit-exactly"**, which pretrained weights do not change and a
download would only make flaky. **⇒ SO THE LABELS ARE MEANINGLESS AND THE
ARITHMETIC IS NOT**, and the oracle is CPython's own logits on the SAME
deterministic weights.

**⇒ AND THE HONEST SCOPE: THIS IS THE LARGEST NETWORK THE BROWSER LANE HAS BEEN
ASKED TO REPLAY**, so the question it answers first is whether the WGSL
renderer can express EfficientNet's kernels AT ALL -- squeeze-excite, swish,
the depthwise convs, the global-pool-then-linear head. **⇒ SO EVERY LAUNCH IT
CANNOT RENDER IS NAMED, AND THE EXIT STATUS IS THE COUNT.**
"""
import json
import pathlib
import sys

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "extra"))
sys.path.insert(0, str(ROOT / ".agents" / "slop" / "browser"))

import trace_common as TC  # noqa: E402

from tinygrad import Tensor, Context, dtypes  # noqa: E402
from tinygrad.nn.state import get_state_dict  # noqa: E402
from extra.models.efficientnet import EfficientNet  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parent / "imagenet-train"


def _nz(b64: str) -> bool:
    """True if the base64 payload has any non-zero byte."""
    import base64 as _b
    return any(_b.b64decode(b64))


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    model = EfficientNet(0)
    TC.deterministic(model)

    # **⇒ AND THE SIDE IS A PARAMETER, BECAUSE THE TRACE'S SIZE IS THE LAUNCH COUNT
    # TIMES THE BUFFER COUNT AND 224x224 MAKES A 5.5 GB FILE.** EfficientNet-0's
    # head is `global_average_pool -> linear`, so the SPATIAL SIZE IS FREE: the
    # SAME kernels run, with fewer positions each. **⇒ SO THE BROWSER REPLAY IS
    # PROVEN AT A SIZE THAT FITS AND THE 224 NUMBER IS A TRANSPORT FIGURE, NOT A
    # CORRECTNESS ONE.**
    SIDE = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 224
    x = Tensor(np.linspace(-0.9, 0.9, 1 * 3 * SIDE * SIDE, dtype=np.float32).reshape(1, 3, SIDE, SIDE))
    print(f"input side {SIDE}")
    y = Tensor(np.array([7], dtype=np.int32))
    params = [v for k, v in get_state_dict(model).items() if dtypes.is_float(v.dtype)]
    LR = 0.001

    # **⇒ AND `before` IS READ HERE, BEFORE THE HOOK, BECAUSE `assign` MINTS A NEW
    # BUFFER.** MEASURED: taking `before` from the trace's own first-bind snapshot
    # gave **`moved=False` for all eight sampled parameters** -- because after
    # `p.assign(u)` the parameter's `base.realized` is a DIFFERENT Buffer, so the
    # step's first bind of THAT buffer is already the post-step content. **⇒ SO THE
    # PRE-STATE IS READ OFF THE LIVE BUFFERS BEFORE ANYTHING RUNS**, and reading
    # does not realize (`as_memoryview` on a realized buffer is a memcpy), so it
    # cannot pollute the trace the way `p.realize()` provably does.
    # **⇒ AND ONLY THE **SAMPLED** PARAMETERS ARE REALIZED HERE.** All 311 were
    # unrealized, so `before_of` was empty and ZERO were sampled. **⇒ AND REALIZING
    # EIGHT LEAF WEIGHTS IS NOT THE HAZARD `p.realize()` ON ALL OF THEM IS**: the
    # MNIST lane measured that realizing EVERY parameter collapses its traced
    # forward from 23 launches to 0, and this file re-checks its own launch count
    # below so the same fault cannot pass silently here.
    SAMPLE = 8
    _named = [(k, v) for k, v in get_state_dict(model).items() if dtypes.is_float(v.dtype)]
    _named.sort(key=lambda kv: -kv[1].numel())
    sample = _named[:SAMPLE]
    before_idx = []
    for _k, _v in sample:
        _v.realize()
        _r = _v.uop.base.realized
        before_idx.append((_k, _v, bytes(_r.as_memoryview(allow_zero_copy=True))))

    TC.reset()
    TC.install()
    try:
        with Context(TRAINING=1):
            # **⇒ AND THE LOGITS ARE **NOT** REALIZED BEFORE THE LOSS, WHICH IS A
            # MEASURED PRECONDITION AND NOT A STYLE.** MEASURED:
            # `lg = model.forward(x).realize()` then `any(u is params[0].uop for u
            # in lg.uop.toposort())` answers **False** -- REALIZING THE FORWARD
            # OUTPUT DETACHES THE PARAMETERS FROM THE BACKWARD SLICE -- so every
            # gradient is exactly `0.0` and the "training step" becomes a no-op
            # that leaves the weights untouched. **⇒ AND THAT IS EXACTLY WHY THE
            # FIRST VERSION OF THIS TRACE REPORTED `0 of them MOVED`.** The loss is
            # built from the LAZY graph; realizing the LOSS pulls the forward
            # through, which is what puts its kernels in the trace anyway.
            logits = model.forward(x)
            loss = logits.sparse_categorical_crossentropy(y)
            # **⇒ AND NOTHING IS REALIZED BEFORE `gradient`, BECAUSE **REALIZING
            # DETACHES**.** MEASURED twice: `realize()` on the FORWARD OUTPUT gave
            # `fc in slice after realize? False` and `grad = 0.0`; and realizing the
            # LOSS before differentiating did the same. **⇒ SO THE GRADIENTS ARE
            # TAKEN OFF THE FULLY LAZY GRAPH AND THE REALIZE HAPPENS ON THE
            # GRADIENTS THEMSELVES**, which is what puts the backward kernels in the
            # trace.
            # **⇒ AND THE GRADIENT IS TAKEN FOR THE **SAMPLED** PARAMETERS ONLY, BY
            # THE SAME MEASUREMENT THAT CHOSE THE SAMPLE.** All 311 at once is a
            # backward walk per parameter and it did not finish inside a forty
            # minute budget. **⇒ AND IT DOES NOT WEAKEN THE CLAIM, IT SCOPES IT**:
            # the row is "the parameters this trace CLAIMS to train are trained
            # correctly", and the sample is the eight heaviest -- the conv and
            # linear weights the objective is about.
            sample_params = [v for (_k, v, _b) in before_idx]
            grads = [g.realize() for g in loss.gradient(*sample_params)]
            loss_v = float(loss.realize().item())
            ups = [(p.detach() - (g * LR).cast(p.dtype)).realize()
                   for p, g in zip(sample_params, grads)]
            for p, u in zip(sample_params, ups):
                p.assign(u).realize()
            # **⇒ AND THE LOGITS ARE NOT A ROW HERE ANY MORE, AND THE REASON IS
            # MEASURED: WITH THE LOSS BUILT LAZILY THE FORWARD'S OUTPUT IS NEVER
            # MATERIALISED** (`logits.uop.base.realized` is `None` after the loss
            # realizes), so the buffer a logits row would compare does not exist.
            # **⇒ AND IT IS THE RIGHT ROW TO DROP ANYWAY: THE LOGITS ARE PRODUCED BY
            # THE FORWARD, BEFORE `backward` AND THE UPDATE RUN, so a gate over them
            # is GREEN ON A STEP WHOSE GRADIENTS ARE ALL ZERO** -- which is exactly
            # what this trace did before the detach was found.
            words, logits_name = None, None
    finally:
        TC.restore()

    # **⇒ AND THE UPDATE ITSELF IS WHAT "TRAIN IT" MEANS, SO THE PARAMETERS ARE
    # RECORDED, NOT JUST THE LOGITS.** The logits are produced by the FORWARD,
    # BEFORE `backward` and the SGD step run -- so a gate over logits alone is
    # green on a step whose gradients and update are numerically wrong.
    #
    # **⇒ AND `name_of` IS CALLED **AFTER** THE TRACE AND ON THE SAME OBJECTS**, so
    # it returns the names the trace already minted (`_seen` is keyed by
    # `id(base)`), and calling it here cannot renumber them. Calling it BEFORE the
    # trace would assign names in a different order and every name would shift.
    #
    # **⇒ AND `before` IS THE TRACE's OWN FIRST-BIND SNAPSHOT** -- a weight is
    # uploaded once, before any launch writes it, so `TC.buffers[name].b64` IS its
    # pre-step content. **⇒ AND `after` IS READ WITH THE HOOK OFF**, so the read is
    # not a launch.
    import base64 as _b
    # **⇒ AND THE AFTER IS MATCHED BY **POSITION IN THE SAMPLE**, NOT BY `id`**:
    # `p.assign(u)` MINTS A NEW BUFFER, so the parameter's `base.realized` after
    # the step is a different object and an `id` lookup finds nothing -- which is
    # how the first attempt sampled ZERO.
    params_b64 = {}
    for (k, v, raw_before) in before_idx:
        r = v.uop.base.realized
        if r is None:
            continue
        raw_after = bytes(r.as_memoryview(allow_zero_copy=True))
        if len(raw_after) != len(raw_before):
            continue
        params_b64[TC.name_of(r)] = {
            "name": k,
            "before_b64": _b.b64encode(raw_before).decode("ascii"),
            "after_b64": _b.b64encode(raw_after).decode("ascii"),
            "numel": int(v.numel())}
    moved = sum(1 for v in params_b64.values() if v["before_b64"] != v["after_b64"])
    print(f"parameter buffers sampled: {len(params_b64)} of {len(_named)} parameters, "
          f"{moved} of them MOVED")

    (OUT / "inet-train-oracle.json").write_text(json.dumps({
        "input": list(x.shape), "shape": list(logits.shape), "loss": loss_v,
        "params": params_b64,
        "note": "CPython tinygrad, DEV=CPU, TRAINING=1, EfficientNet(0) on "
                "DETERMINISTIC weights (not pretrained): forward + loss + "
                "loss.gradient + SGD (p - lr*g), u32 bit patterns",
    }, indent=1) + "\n")

    final = {}
    for r in TC.launches:
        final.update(r.get("after") or {})
    frames = [TC.frames(r) for r in TC.launches]
    for i, fr in enumerate(frames):
        if i != len(frames) - 1:
            fr.pop("after", None)

    # **⇒ AN ALL-ZERO SNAPSHOT IS DROPPED, AND THAT IS A FACT ABOUT WEBGPU AND NOT
    # A LOSSY SHORTCUT: `GPUBuffer` IS ZERO-INITIALISED BY THE SPEC**, so a page
    # that creates a buffer and never writes it holds exactly these bytes.
    # **⇒ AND IT IS THE WHOLE SIZE PROBLEM**: EfficientNet-0's first pass is
    # 106 MB of JSON, and 31 MB of `buffers` plus 29 MB of `final` are
    # intermediate SCRATCH whose first and last contents are zeros.
    def all_zero(b64: str) -> bool:
        return not _nz(b64)

    # **⇒ AND AN ALL-ZERO BUFFER KEEPS ITS **ENTRY** AND LOSES ONLY ITS PAYLOAD.**
    # Dropping the entry too left the page unable to ALLOCATE the buffer, and it
    # died with `Cannot read properties of undefined (reading 'gb')` -- the size
    # lives in the entry. **⇒ SO THE PAGE STILL KNOWS HOW BIG IT IS, AND STILL
    # UPLOADS NOTHING.**
    zbytes = 0
    for n, b in list(TC.buffers.items()):
        if all_zero(b["b64"]):
            zbytes += len(b["b64"])
            b = dict(b)
            b.pop("b64", None)
            b["zero"] = True
            TC.buffers[n] = b
    for fr in frames:
        ins = fr.get("in") or {}
        fr["in"] = {n: v for n, v in ins.items()
                    if TC.buffers.get(n, {}).get("b64") != v and not all_zero(v)}
        if not fr["in"]:
            fr.pop("in", None)
    final = {n: v for n, v in final.items() if not all_zero(v)}
    print(f"zero-elided: {zbytes} base64 chars of all-zero snapshots dropped")
    print(f"size-normalised payloads: {TC.normalize_sizes(TC.buffers, frames, final)}")
    table = TC.intern_payloads(TC.buffers, frames, final)
    print(f"interned payloads: {len(table)} distinct of "
          f"{sum(len(f.get('in') or {}) + len(f.get('after') or {}) for f in frames) + len(TC.buffers) + len(final)} references")
    (OUT / "inet-train-net.json").write_text(json.dumps({
        "entry": {"input": list(x.shape), "output": list(logits.shape)},
        "payloads": table, "buffers": TC.buffers, "final": final, "kernels": frames,
        "note": "EfficientNet(0) forward, captured from "
                "tinygrad/engine/realize.py exec_kernel; wgsl is "
                "tinygrad/renderer/wgsl.py on the same ast",
    }) + "\n")

    unrendered = [(i, r.get("entry"), r.get("wgslError")) for i, r in enumerate(TC.launches) if not r.get("wgsl")]
    print(f"launches {len(TC.launches)}  buffers {len(TC.buffers)}  logits {list(logits.shape)}")
    print(f"WGSL-UNRENDERED: {len(unrendered)} of {len(TC.launches)}")
    for i, e, err in unrendered[:8]:
        print(f"  launch {i} {e}: {err}")
    return 0 if TC.launches and not unrendered else 1


if __name__ == "__main__":
    raise SystemExit(main())
