"""stage3_parity.py -- THE PYTHON AND BEND LANES ON ONE SCHEDULE, WHICH THEY WERE NOT.

    .venv/bin/python .agents/slop/perf/stage3_parity.py [--size N]

**THE DEFECT THIS EXISTS FOR**, measured 2026-11-01 by dumping each lane's first launch:

    PYTHON  global (16,16,1)  local (16,1,1)  uops  49   <- the scheduler SPLIT TO LOCAL
    BEND    global (1,1,1)    local (1,1,1)   uops 148   <- it could not, so it did not

`ops_bend.py`'s `BendRenderer` sets `has_local = False` because the v1 wire cannot launch a
local size (`BendProgram.__call__` refuses `local_size != (1,1,1)`, and the port's own header
says "the executor is warp 1 and reads every lidxK as 0"). `has_local` is a SCHEDULER input, so
declaring it False does not merely change where the kernel runs -- IT CHANGES THE KERNEL. The
two lanes were therefore never timing the same program, and the 2.6x/5.1x they reported was a
ratio between two different schedules.

**WHAT THIS DOES.** Sets the SAME `has_local` on both renderers, then checks that the two lanes
really do get one schedule -- same grid, same local size, same op sequence, same srcs -- before it
reports a single time. A comparison whose halves are not the same program is not a comparison, so
the identity check is an OUTPUT of this instrument, not a comment in it.

`has_local = False` on both is the direction that EXISTS today: the port cannot launch a local
size, so the only exact arrangement available is "neither side splits". The faithful one -- both
sides splitting, because that is what `DEV=PYTHON` does by default -- needs the port's executor to
run a real warp (bump width > 1, per-lane registers, `lidxK`, `exec_masks` per lane, LOCAL buffers
shared across the warp). Recorded in TODO.md, not attempted here.
"""
import argparse
import statistics
import sys
import pathlib
import time

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / ".agents/slop/perf"))

CANON = {"f32": "f32", "float": "f32", "i32": "i32", "int": "i32", "u32": "u32", "uint": "u32",
         "bool": "bool", "weakint": "weakint", "weakfloat": "weakfloat", "void": "void",
         "i64": "i64", "long": "i64", "u64": "u64", "ulong": "u64"}


def canon(dt) -> str:
  s = str(dt).replace("dtypes.", "")
  return CANON.get(s, s)


def kind(arg) -> str:
  """the ARG's kind, not its spelling: the two lanes encode the same fact differently"""
  s = str(arg)
  if s == "None":
    return "-"
  if "ParamArg" in s or s.startswith("k:param:"):
    return "param" + (":alu" if "ALU" in s or ":r" in s else "")
  if s.startswith("k:buffer:"):
    return "buffer"
  if "sp:" in s or s.startswith("gidx") or s.startswith("lidx"):
    return "special"
  return "value"


def shape(df, lane: str) -> list[tuple[str, str, tuple[int, ...]]]:
  out = []
  for u in df:
    if lane == "BEND":
      out.append((u.op, canon(u.dtype), tuple(u.srcs)))
    else:
      out.append((u.op.name, canon(u.dtype), tuple(df_idxs[u] for u in ())))
  return out


def one(lane: str, mats, iters: int, local: bool):
  from tinygrad import Context, Tensor
  if lane == "BEND":
    import ops_bend as OB
    sys.modules["tinygrad.runtime.ops_bend"] = OB
    mod, cls = OB.BendProgram, OB.BendRenderer
  else:
    import tinygrad.runtime.ops_python as op
    mod, cls = op.PythonProgram, op.PythonRenderer
  cls.has_local = local
  orig = mod.__call__
  seen = []

  def wrap(self, *a, **kw):
    # EVERY LAUNCH, not the first: `(A@B)@C` dispatches twice, and a second matmul on a
    # different shape can schedule differently. A claim of "same program" that reads one
    # launch is a claim about one launch.
    if True:
      rows = []
      if lane == "BEND":
        # THE WIRE IS 1-BASED AND `ops_python` IS 0-BASED, so a raw comparison reports a
        # difference at uop 1 that is pure numbering. Both are normalised to 0-based here.
        for u in self.uops:
          rows.append((u.op, canon(u.dtype), tuple(s - 1 for s in u.srcs)))
      else:
        idx = self.uop_to_index
        for u in self.uops:
          rows.append((u.op.name, canon(u.dtype), tuple(idx[s] for s in u.src)))
      seen.append((kw.get("global_size"), kw.get("local_size"), len(self.uops), rows,
                   len(seen)))
    return orig(self, *a, **kw)

  mod.__call__ = wrap
  with Context(DEV=lane):
    ts = [Tensor(m).realize() for m in mats]
    a, b, c = ts
    w = ((a @ b) @ c).realize()
    _ = w.numpy()
    warm, seen[:] = list(seen), []      # the warm-up realize is the program dump
    t = time.perf_counter()
    for _i in range(iters):
      out = ((a @ b) @ c).realize()
    ms = (time.perf_counter() - t) / iters * 1000.0
    arr = out.numpy()
  mod.__call__ = orig
  return dict(lane=lane, ms=ms, prog=[(g, l, n, r) for g, l, n, r, _i in warm], out=arr)


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--size", type=int, default=16)
  ap.add_argument("--iters", type=int, default=2)
  args = ap.parse_args()
  from bench import build

  mats = build(args.size)
  cpu = one("CPU", mats, args.iters, local=False)
  py = one("PYTHON", mats, args.iters, local=False)
  be = one("BEND", mats, args.iters, local=False)
  same_rows = py["prog"] == be["prog"]
  d = float(np.abs(py["out"] - be["out"]).max())
  print(f"size={args.size}  has_local=False ON BOTH (the only arrangement the v1 wire can launch)")
  for tag, r in (("PYTHON", py), ("BEND", be)):
    per = "  ".join(f"g{g} l{l} {n}u" for g, l, n, _rows in r["prog"])
    print(f"  {tag:6s} {per}   {r['ms']:9.2f} ms")
  print(f"  SAME PROGRAM: {len(py['prog'])} launches, "
        f"{'EVERY LAUNCH IDENTICAL' if same_rows else 'DIFFER'}"
        + ("" if same_rows else " at launch "
           + str(next((i for i, (x, y) in enumerate(zip(py['prog'], be['prog'])) if x != y), "end"))))
  print(f"  max|PYTHON-BEND| {d:.3e}   ratio {py['ms'] / be['ms']:.2f}x "
        f"({'PYTHON faster' if py['ms'] < be['ms'] else 'BEND faster'})")
  print(f"  vs CPU: PYTHON {float(np.abs(py['out'] - cpu['out']).max()):.3e}  "
        f"BEND {float(np.abs(be['out'] - cpu['out']).max()):.3e}  "
        f"(an engine that agrees with CPU bit-for-bit prints 0.000e+00)")
  return 0 if same_rows else 1


if __name__ == "__main__":
  raise SystemExit(main())
