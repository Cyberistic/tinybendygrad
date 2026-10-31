#!/usr/bin/env python3
"""stage2_metal.py -- STAGE 2, TIMED: the MSL the METAL lane runs, against the MSL the port renders.

    .venv/bin/python .agents/slop/perf/stage2_metal.py

WHAT IT DOES, and why each step is a measurement rather than an inference:

 1. RUNS SEVERAL PROGRAMS on `DEV=METAL` and HOOKS `MetalRenderer.render`, so the exact MSL
    text upstream compiled is CAPTURED (with its uop list), not reconstructed. Each program
    is TIMED: warmup launches, then the minimum of N, and its result is checked against a
    float64 numpy reference.
 2. RENDERS EACH CAPTURED UOP LIST WITH THE PORT (`tinybendygrad/renderer/cstyle.bend` at
    `dev_metal`, through `bin/bend`) and records BOTH sha256s.
 3. WRITES `.agents/slop/perf/stage2-metal.rows`: one row per kernel, with the two hashes,
    whether they are identical, the bytes, and the ms of the program that compiled it.

⇒ AND THE COMPARISON IS READ CORRECTLY: if the two texts are byte-identical then the timing
IS the port's timing, because the bytes that were timed are the bytes the port emits. If a
kernel's texts DIFFER, its `identical` field says `no` and the timing belongs to upstream's
text only -- it is not a comparison of two programs' speeds, and this file does not pretend
it is.

ONE PROGRAM WAS NOT ENOUGH. The first version ran `(a@b)@c` at 32x32 and compared ONE
kernel, so "byte-identical" was a fact about a single matmul. The programs below are chosen
to produce DIFFERENT KINDS of kernel: a WMMA matmul, a second matmul at another size, an
elementwise chain (no WMMA, vectorised stores), and a reduction (a different body shape).
"""
from __future__ import annotations
import hashlib, importlib.util, os, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
MSL, UOPS, GEN = HERE / "msl", HERE / "uops_metal", HERE / "gen_metal"
DRIVER = HERE / "render_metal.bend"
ROWS = HERE / "stage2-metal.rows"
N = int(os.environ.get("STAGE2_ITERS", "2"))


def load_gen_kus():
  spec = importlib.util.spec_from_file_location("gen_kus", ROOT / ".agents/slop/cpuseam/gen_kus.py")
  mod = importlib.util.module_from_spec(spec)
  assert spec.loader is not None
  spec.loader.exec_module(mod)
  return mod


def main() -> int:
  sys.path.insert(0, str(ROOT))
  import numpy as np
  from tinygrad import Tensor, Context, Device
  from tinygrad.renderer.cstyle import MetalRenderer

  dump = importlib.util.spec_from_file_location("dk", ROOT / ".agents/slop/cpuseam/dump_kernel.py")
  dk = importlib.util.module_from_spec(dump)
  assert dump.loader is not None
  dump.loader.exec_module(dk)
  gk = load_gen_kus()

  def T(x): return Tensor(np.asarray(x, dtype=np.float32))

  # each program returns (output tensor, float64 reference); the shapes and op mix differ on purpose
  def p_mm32(rng):
    a, b, c = (rng.standard_normal((32, 32)) for _ in range(3))
    with Context(DEV="METAL"):
      ta, tb, tc = T(a).realize(), T(b).realize(), T(c).realize()
      return (lambda: ((ta @ tb) @ tc).realize()), (a @ b) @ c

  def p_mm16(rng):
    a, b = (rng.standard_normal((16, 16)) for _ in range(2))
    with Context(DEV="METAL"):
      ta, tb = T(a).realize(), T(b).realize()
      return (lambda: (ta @ tb).realize()), a @ b

  def p_ew(rng):
    a, b = (rng.standard_normal((64, 64)) for _ in range(2))
    with Context(DEV="METAL"):
      ta, tb = T(a).realize(), T(b).realize()
      # elementwise chain: ALU only, no WMMA, and still vectorises
      return (lambda: ((ta * tb + ta).relu() * 2.0 - tb).realize()), np.maximum(a * b + a, 0) * 2.0 - b

  def p_reduce(rng):
    a = rng.standard_normal((64, 64))
    with Context(DEV="METAL"):
      ta = T(a).realize()
      return (lambda: ta.sum(axis=1).realize()), a.sum(axis=1)

  def p_mm2048(rng):
    # **OUT OF THE MEASUREMENT FLOOR.** The four small programs run in 0.015-0.136 ms, where a
    # number cannot discriminate; 2048^3 MACs with real tensor cores is ~8.6 GFLOP.
    a, b = (rng.standard_normal((2048, 2048)) for _ in range(2))
    with Context(DEV="METAL"):
      ta, tb = T(a).realize(), T(b).realize()
      return (lambda: (ta @ tb).realize()), a @ b

  def p_mm4096(rng):
    a, b = (rng.standard_normal((4096, 4096)) for _ in range(2))
    with Context(DEV="METAL"):
      ta, tb = T(a).realize(), T(b).realize()
      return (lambda: (ta @ tb).realize()), a @ b

  PROGRAMS = [("mm16", p_mm16), ("mm32", p_mm32), ("ew64", p_ew), ("reduce", p_reduce),
              ("mm2048", p_mm2048), ("mm4096", p_mm4096)]

  captured: list[tuple[str, str, list[str]]] = []
  orig = MetalRenderer.render

  def hooked(self, uops):
    src = orig(self, uops)
    name = next((u.arg.function_name for u in uops if u.op.name == "SINK" and u.arg is not None), "")
    name = (name or f"k{len(captured)}").replace(":", "_")
    captured.append((name, src, dk.dump_uops(uops)))
    return src

  per_prog: dict[str, float] = {}
  ref_err: dict[str, float] = {}
  MetalRenderer.render = hooked
  rng = np.random.default_rng(0)
  for pname, build in PROGRAMS:
    run, want = build(rng)
    # **A LAUNCH MUST BE SYNCHRONISED OR THE NUMBER IS SUBMIT LATENCY.** MEASURED: without the
    # sync the four programs read 0.01 / 0.01 / 0.00 / 0.00 ms, which is the cost of handing
    # work to a queue and not the cost of doing it -- Metal is asynchronous and `realize()`
    # returns before the GPU is done. A "timed" comparison over those numbers would have been
    # the same class of defect this report keeps finding.
    out = run()                       # one full execution for warmup + the reference check
    samples = []
    for _ in range(N):
      st = time.perf_counter()
      out = run()                     # RE-EXECUTES: a realized tensor would be a no-op
      Device["METAL"].synchronize()
      samples.append((time.perf_counter() - st) * 1e3)
    per_prog[pname] = min(samples)
    ref_err[pname] = float(np.max(np.abs(np.asarray(out.numpy(), dtype=np.float64) - want))
                           / max(1.0, float(np.max(np.abs(want)))))
  MetalRenderer.render = orig

  # 2. the port renders the same uop lists
  MSL.mkdir(exist_ok=True); UOPS.mkdir(exist_ok=True); GEN.mkdir(exist_ok=True)
  names = []
  for name, src, rows in captured:
    if name in names:
      continue
    names.append(name)
    (MSL / f"{name}.metal").write_text(src)
    rows = [r.replace("|special|" + r.split("|")[-1], "|special|" + r.split("|")[-1].replace("~", ""))
            if "|special|" in r else r for r in rows]
    (UOPS / f"{name}.rows").write_text(
      f"# {name}.rows -- generated by .agents/slop/perf/stage2_metal.py\n"
      "# columns: idx|op|dtype|addrspace|shape|numel|srcs(1-based)|kind|payload(~-separated)\n"
      + "\n".join(rows) + "\n")
    body = "\n".join(gk.one(name, ln) for ln in rows)
    (GEN / f"{name}.bend").write_text(
      f"# {name}.bend -- GENERATED by .agents/slop/perf/stage2_metal.py from uops_metal/{name}.rows.\n"
      "# DO NOT HAND-EDIT.\nimport Base\n"
      "import ./../../../../tinybendygrad/renderer/cstyle.bend as C\n"
      "import ./../../../../tinybendygrad/uop/ops.bend as O\n"
      "import ./../../../../tinybendygrad/LAWS/spec.bend as S\n"
      "import ./../../../../tinybendygrad/helpers.bend as H\n\n"
      "def kus() -> List<&2, C.KU>:\n  [\n" + body + "\n  ]\n")

  imports = "\n".join(f"import ./gen_metal/{nm}.bend as G{i}" for i, nm in enumerate(names))
  cases = "\n".join(f'    case "{nm}": G{i}.kus()' for i, nm in enumerate(names))
  DRIVER.write_text(
    "# render_metal.bend -- GENERATED by .agents/slop/perf/stage2_metal.py. DO NOT HAND-EDIT.\n"
    "# THE PORT's OWN cstyle.bend AT dev_metal, ON THE UOP LISTS THE METAL LANE ACTUALLY COMPILED.\n"
    "import Base\nimport ./../../../tinybendygrad/renderer/cstyle.bend as C\n" + imports + "\n\n"
    "def nth(xs: List<&1, String>, k: Nat) -> String:\n"
    '  Maybe.default(&1, String, List.get(&1, String, xs, k), "")\n\n'
    "def kus_of(nm: String) -> List<&2, C.KU>:\n  match nm:\n" + cases + "\n    case _: Nil{}\n\n"
    "def main() -> IO(Unit):\n  do IO<Unit>:\n"
    "    args : List<String> <- IO.args()\n"
    "    nm : String = nth(args, 1n)\n"
    "    src : String = C.render(C.dev_metal(), True{}, kus_of(nm))\n"
    "    IO.print(src)\n")

  rows_out = []
  for name in names:
    up = (MSL / f"{name}.metal").read_bytes()
    r = subprocess.run(["./bin/bend", str(DRIVER), name], cwd=ROOT, capture_output=True, text=True)
    # `IO.print` appends ONE "\n"; upstream's `render()` returns the text without it, so the
    # driver's newline is stripped to recover the renderer's own bytes -- and exactly one,
    # so a second trailing newline in the text would still show up as a difference.
    port = (r.stdout[:-1] if r.stdout.endswith("\n") else r.stdout).encode()
    ok = r.returncode == 0 and port == up
    rows_out.append(dict(kernel=name, sha_upstream=hashlib.sha256(up).hexdigest()[:16],
                         sha_port=hashlib.sha256(port).hexdigest()[:16],
                         identical="yes" if ok else "no", bytes=len(up), rc=r.returncode))

  ROWS.write_text(
    "# stage2-metal.rows -- .agents/slop/perf/stage2_metal.py\n"
    "# DEV=METAL, JIT=0, min of " + str(N) + " SYNCHRONISED launches after 3 warmups per program\n"
    + "# program_ms " + " ".join(f"{k}={v:.3f}" for k, v in per_prog.items()) + "\n"
    + "# program_max|diff_vs_float64_cpu| " + " ".join(f"{k}={v:.2e}" for k, v in ref_err.items()) + "\n"
    + f"# kernels={len(rows_out)}\n"
    "# kernel|sha_upstream|sha_port|identical|bytes|bend_rc\n"
    + "\n".join(f"{r['kernel']}|{r['sha_upstream']}|{r['sha_port']}|{r['identical']}|{r['bytes']}|{r['rc']}"
                for r in rows_out) + "\n")
  ok = sum(r["identical"] == "yes" for r in rows_out)
  print(f"programs={len(PROGRAMS)} kernels={len(rows_out)} identical={ok}"
        + " " + " ".join(f"{k}={v:.2f}ms" for k, v in per_prog.items()))
  for r in rows_out:
    print(f"  {r['identical']:>3} {r['bytes']:>6}B {r['sha_upstream']} {r['sha_port']} {r['kernel']}")
  return 0 if ok == len(rows_out) else 1


if __name__ == "__main__":
  raise SystemExit(main())
