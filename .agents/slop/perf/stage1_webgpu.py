#!/usr/bin/env python3
"""stage1_webgpu.py -- STAGE 1's CORPUS: WGSL that tinygrad emitted, for SEVERAL PROGRAMS.

    .venv/bin/python .agents/slop/perf/stage1_webgpu.py <program>
    bun .agents/slop/perf/stage1_time.js          # compiles, runs and times every manifest

PROGRAMS, chosen so the kernels differ in KIND and not only in size:

    ew16 ew32 ew64   an elementwise chain `a*b + a` at 16, 32 and 64
    relu32           `relu(a*b)` -- the WHERE/CMPLT path, not a plain ALU chain
    red32            `a.sum(axis=1)` -- a REDUCTION, whose body has a RANGE
    odd              `a*b + a` over a 1000-element 1-D tensor, NOT a power of two

WHY `NOOPT=1`: WGSL is produced from WebGPU-LOWERED uops, and a normally-optimised kernel
vectorises its stores into an `Ops.STACK`, which `WGSLRenderer` cannot spell because it sets
`float4 = None`. With `NOOPT=1` the upcast pass does not run, so no STACK is emitted and the
same renderer answers a REAL kernel.

WHAT IT WRITES: `.agents/slop/perf/stage1/<kernel>.json` -- the WGSL text from BOTH sides,
the input buffers as base64, the dispatch, and the EXPECTED outputs. `stage1_time.js`
compiles, binds, runs and TIMES both, and records a side that REFUSES with its compile error.

THE BUFFER ORDER IS NOT GUESSED: two candidate expectations travel (`a*b+a` and `a*b+b`), so
the driver reports WHICH operand order the emitted code implements, and `NEITHER` is a real
defect rather than a binding mistake. `relu(a*b)` and a reduction are order-insensitive.
"""
from __future__ import annotations
import base64, hashlib, importlib.util, json, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent / "stage1"


def build(prog: str, np, Tensor, Context):
    rng = np.random.default_rng(0)
    if prog in ("ew16", "ew32", "ew64"):
        n = {"ew16": 16, "ew32": 32, "ew64": 64}[prog]
        a, b = rng.standard_normal((n, n)).astype(np.float32), rng.standard_normal((n, n)).astype(np.float32)
        with Context(DEV="METAL", NOOPT=1):
            ta, tb = Tensor(a).realize(), Tensor(b).realize()
            out = (ta * tb + ta).realize()
        return out, [a, b], a * b + a, a * b + b, "a*b+a", "a*b+b"
    if prog == "relu32":
        a, b = rng.standard_normal((32, 32)).astype(np.float32), rng.standard_normal((32, 32)).astype(np.float32)
        with Context(DEV="METAL", NOOPT=1):
            ta, tb = Tensor(a).realize(), Tensor(b).realize()
            out = (ta * tb).relu().realize()
        w = np.maximum(a * b, 0)                       # symmetric in a, b: the order does not matter
        return out, [a, b], w, w, "relu(a*b)", "relu(b*a)"
    if prog == "cst32":
        # A NON-ZERO CONSTANT: this is the program that would have COMPILED AND BEEN WRONG
        # before the walk materialised a CONST's value (`f32()` is a valid zero, `2.5` is not).
        a, b = rng.standard_normal((32, 32)).astype(np.float32), rng.standard_normal((32, 32)).astype(np.float32)
        with Context(DEV="METAL", NOOPT=1):
            ta, tb = Tensor(a).realize(), Tensor(b).realize()
            out = (ta * tb).maximum(2.5).realize()
        w = np.maximum(a * b, np.float32(2.5))
        return out, [a, b], w, w, "max(a*b,2.5)", "max(b*a,2.5)"
    if prog == "red32":
        a = rng.standard_normal((64, 64)).astype(np.float32)
        with Context(DEV="METAL", NOOPT=1):
            out = Tensor(a).realize().sum(axis=1).realize()
        return out, [a], a.sum(axis=1), None, "a.sum(1)", "-"   # ONE input: one expectation
    if prog == "odd":
        a, b = rng.standard_normal(1000).astype(np.float32), rng.standard_normal(1000).astype(np.float32)
        with Context(DEV="METAL", NOOPT=1):
            ta, tb = Tensor(a).realize(), Tensor(b).realize()
            out = (ta * tb + ta).realize()
        return out, [a, b], a * b + a, a * b + b, "a*b+a", "a*b+b"
    raise SystemExit(f"unknown program {prog}")


def main() -> int:
    sys.path.insert(0, str(ROOT))
    import numpy as np
    from tinygrad import Tensor, Context
    from tinygrad.renderer.wgsl import WGSLRenderer
    from tinygrad.renderer.cstyle import MetalRenderer
    from tinygrad.device import Target

    prog = sys.argv[1] if len(sys.argv) > 1 else "ew32"
    cap = []
    orig = MetalRenderer.render

    def hooked(self, uops):
        src = orig(self, uops)
        for u in uops:
            if u.op.name == "SINK" and u.arg is not None:
                cap.append((u.arg.function_name, list(uops)))
                break
        return src

    MetalRenderer.render = hooked
    out, ins, want_a, want_b, lab_a, lab_b = build(prog, np, Tensor, Context)
    MetalRenderer.render = orig
    name, uops = cap[0]
    wgsl = WGSLRenderer(Target("webgpu")).render(uops)

    # the uop list, in the same `|`-delimited form the cstyle lane uses
    dump = importlib.util.spec_from_file_location("dk", ROOT / ".agents/slop/cpuseam/dump_kernel.py")
    dk = importlib.util.module_from_spec(dump)
    assert dump.loader is not None
    dump.loader.exec_module(dk)
    OUT.mkdir(exist_ok=True)
    key = f"{prog}__{name}"
    rows = dk.dump_uops(uops)
    (OUT / f"{key}.rows").write_text(
        f"# {key}.rows -- generated by .agents/slop/perf/stage1_webgpu.py ({prog})\n"
        "# columns: idx|op|dtype|addrspace|shape|numel|srcs(1-based)|kind|payload(~-separated)\n"
        + "\n".join(rows) + "\n")

    # ---- THE PORT's SIDE: its own walk, driven from those rows -------------------------
    subprocess.run([".venv/bin/python", ".agents/slop/perf/gen_wgsl.py", key], cwd=ROOT,
                   check=True, capture_output=True, text=True)
    (pathlib.Path(__file__).parent / "render_wgsl.bend").write_text(
        "# render_wgsl.bend -- GENERATED by .agents/slop/perf/stage1_webgpu.py. DO NOT HAND-EDIT.\n"
        "# THE PORT's OWN WALK (`wgsl_walk.bend`) OVER A REAL UOP LIST, assembled by `wgsl.bend`.\n"
        "import Base\n"
        "import ./../../../tinybendygrad/renderer/wgsl.bend as V\n"
        "import ./../../../tinybendygrad/renderer/wgsl_walk.bend as W\n"
        f"import ./gen_wgsl/{key}.bend as G\n\n"
        "def render(rs: List<&2, W.R>) -> String:\n"
        "  +w = W.walk(rs)\n"
        "  V.render_kernel(W.Wk.nm(w), W.Wk.body(w), W.Wk.bufs(w), V.Scan{[1], False{}})\n\n"
        "def main() -> IO(Unit):\n  do IO<Unit>:\n    IO.print(render(G.rs()))\n")
    r = subprocess.run(["./bin/bend", ".agents/slop/perf/render_wgsl.bend"], cwd=ROOT,
                       capture_output=True, text=True)
    port = (r.stdout[:-1] if r.stdout.endswith("\n") else r.stdout)
    same = r.returncode == 0 and port == wgsl
    if not same:
        (OUT / f"{key}.bend.wgsl").write_text(port)          # the refusal or the divergence, kept
    # THE CAUSE, DERIVED FROM THE PORT's OWN TEXT -- not typed: a refusal names its op, and a
    # CONST the walk never materialised shows up as an EMPTY TYPE CALL (`f32()`, `i32()`).
    cause = ""
    if not same:
        m = re.search(r"UNHANDLED\((\w+)\)", port)
        cause = (f"refuses {m.group(1)}" if m else
                 "a CONST's value is not materialised" if re.search(r"\b(f32|i32|u32|bool)\(\)", port) else
                 "text differs")
    o = np.asarray(out.numpy(), dtype=np.float32)
    bufs = [base64.b64encode(x.tobytes()).decode() for x in [o, *ins]]
    (OUT / f"{key}.json").write_text(json.dumps({
        "program": prog, "name": name, "key": key, "label_a": lab_a, "label_b": lab_b, "wgsl": wgsl, "wgsl_bend": port,
        "sha256": hashlib.sha256(wgsl.encode()).hexdigest()[:16],
        "sha_bend": hashlib.sha256(port.encode()).hexdigest()[:16], "bytes": len(wgsl),
        "identical": same, "cause": cause, "bend_rc": r.returncode,
        "bufs": bufs, "nbytes": [x.nbytes for x in [o, *ins]],
        "dispatch": [int(np.prod(o.shape)) if o.shape else 1, 1, 1], "workgroup_size": [1, 1, 1],
        "want_a": base64.b64encode(np.ascontiguousarray(want_a, dtype=np.float32).tobytes()).decode(),
        "want_b": base64.b64encode(np.ascontiguousarray(
            want_a if want_b is None else want_b, dtype=np.float32).tobytes()).decode(),
    }, indent=1) + "\n")
    print(f"{prog}: kernel={name} uops={len(uops)} python={len(wgsl)}B {hashlib.sha256(wgsl.encode()).hexdigest()[:16]} "
          f"bend={len(port)}B {hashlib.sha256(port.encode()).hexdigest()[:16]} rc={r.returncode} "
          + ("IDENTICAL" if same else "DIFFER -- kept as " + f"{name}.bend.wgsl"))
    return 0 if same else 1


if __name__ == "__main__":
    raise SystemExit(main())
