#!/usr/bin/env python3
"""Record every rewrite pass on one tinygrad program as a graph diff.

The course cannot draw a graph it has not recorded, so this is the instrument
that makes every figure downstream honest. It wraps RewriteContext.unified_rewrite
— a method, so every importer is caught — snapshots the sink before and after,
and writes what was added and removed.

Nothing is patched inside tinygrad's source. The hook is a class attribute on an
object we already own at import time.

    uv run --no-project --with numpy --python 3.12 \\
      python .agents/slop/30klines/tools/recorder/record.py --example add_relu_sum

Determinism is the contract: node ids are positions in toposort order, so two
runs on the same program produce byte-identical JSON.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent.parent / "content" / "traces"


def short(x, n: int = 26) -> str:
  s = str(x)
  return s if len(s) <= n else s[:n - 1] + "…"


def snap(root) -> dict:
  nodes = list(root.toposort())
  idx = {id(n): i for i, n in enumerate(nodes)}
  out = []
  for i, n in enumerate(nodes):
    try:
      dt = str(n.dtype)
    except Exception:
      dt = "?"
    out.append({"i": i, "op": str(n.op), "arg": short(n.arg), "dtype": dt,
                "src": [idx[id(s)] for s in n.src if id(s) in idx]})
  return {"n": len(nodes), "nodes": out, "ids": {id(n) for n in nodes}}


SKIP = {"__wrapper", "unified_rewrite", "walk_rewrite", "graph_rewrite", "<module>"}


def stage_of(frame) -> str:
  """Which stage of the pipeline asked for this rewrite.

  A large share of passes are the pattern compiler simplifying its own
  generated Python (upat.py). They are real, and they are not the lesson's
  subject, so they are labelled rather than silently dropped.
  """
  name = pathlib.Path(frame.f_code.co_filename)
  parts = name.parts
  if "upat.py" in parts:
    return "pattern"
  if "schedule" in parts:
    return "schedule"
  if "codegen" in parts:
    return "codegen"
  if "uop" in parts:
    return "uop"
  return "frontend"


def caller_frame():
  """Walk out of the rewrite machinery to the function that asked for it."""
  f = sys._getframe(2)
  while f is not None and f.f_code.co_name in SKIP:
    f = f.f_back
  return f or sys._getframe(2)


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--example", default="add_relu_sum")
  # HERE is …/30klines/tools/recorder, so parents[4] is the repo root
  ap.add_argument("--tree", default=str(HERE.parents[4] / "references" / "tinygrad-latest"))
  ap.add_argument("--keep-graphs", type=int, default=6, help="how many changed passes to keep in full")
  args = ap.parse_args()
  sys.path.insert(0, str(pathlib.Path(args.tree).resolve()))

  from tinygrad import Tensor
  from tinygrad.uop.ops import RewriteContext

  # The repo also contains a pinned tinygrad/ at its root. If sys.path resolves
  # there instead of the vendored tree, every line number in every lesson is
  # measured against the wrong source and nothing complains. So: refuse.
  src = pathlib.Path(__import__("tinygrad").__file__).resolve()
  if not src.is_relative_to(pathlib.Path(args.tree).resolve()):
    print(f"REFUSED: imported {src}, expected the tree at {args.tree}", file=sys.stderr)
    return 2
  print(f"source         {src.parent.parent}")

  steps: list[dict] = []
  armed = {"on": False}
  originals = {name: getattr(RewriteContext, name) for name in ("unified_rewrite", "walk_rewrite")}

  def wrap(name: str):
    orig = originals[name]

    def hooked(self, root):
      if not armed["on"]:
        return orig(self, root)
      before = snap(root)
      out = orig(self, root)
      after = snap(out)
      frame = caller_frame()
      steps.append({
        "i": len(steps),
        "pass": name,
        "caller": frame.f_code.co_name,
        "file": pathlib.Path(frame.f_code.co_filename).name,
        # the function's first line: f_lineno is the executing instruction, which
        # moves with the statement and can land inside a decorator or a helper
        "line": frame.f_code.co_firstlineno,
        "stage": stage_of(frame),
        "before": before["n"],
        "after": after["n"],
        "added": len(after["ids"] - before["ids"]),
        "removed": len(before["ids"] - after["ids"]),
        "_before": before,
        "_after": after,
      })
      return out

    setattr(RewriteContext, name, hooked)

  for name in originals:
    wrap(name)

  # the running example: literal data, because randn is 180 nodes of RNG
  a = Tensor([[1.0, 2.0], [3.0, 4.0]])
  b = Tensor([[5.0, 6.0], [7.0, 8.0]])
  c = (a + b).relu()
  out = c.sum()

  graph_only = out.uop
  armed["on"] = True
  schedule = out.schedule_linear()
  armed["on"] = False

  for name, fn in originals.items():
    setattr(RewriteContext, name, fn)

  changed = [s for s in steps if s["added"] or s["removed"]]
  teaching = [s for s in changed if s["stage"] != "pattern"]
  keep = sorted(teaching, key=lambda s: -(s["added"] + s["removed"]))[:args.keep_graphs]
  keep_ids = {s["i"] for s in keep}

  for s in steps:
    s["kept"] = s["i"] in keep_ids

  dest = OUT / args.example
  shutil.rmtree(dest / "graphs", ignore_errors=True)   # a stale before/after pair is a wrong figure
  (dest / "graphs").mkdir(parents=True, exist_ok=True)

  for s in steps:
    if s["i"] in keep_ids:
      (dest / "graphs" / f"{s['i']:03d}-before.json").write_text(json.dumps(s["_before"]["nodes"], indent=1))
      (dest / "graphs" / f"{s['i']:03d}-after.json").write_text(json.dumps(s["_after"]["nodes"], indent=1))
    del s["_before"], s["_after"]

  summary = {
    "example": args.example,
    "program": "a = Tensor([[1,2],[3,4]]); b = Tensor([[5,6],[7,8]]); c = (a+b).relu(); c.sum().schedule_linear()",
    "lazy_nodes": len(list(graph_only.toposort())),
    "linear_nodes": len(list(schedule.toposort())),
    "passes": len(steps),
    "changing_passes": len(changed),
    "steps": steps,
  }
  blob = json.dumps(summary, indent=1, sort_keys=True)
  summary["digest"] = hashlib.sha256(blob.encode()).hexdigest()[:16]
  (dest / "steps.json").write_text(json.dumps(summary, indent=1, sort_keys=True) + "\n")

  print(f"lazy graph      {summary['lazy_nodes']} nodes")
  print(f"after schedule  {summary['linear_nodes']} nodes")
  print(f"rewrite passes  {summary['passes']} ({len(changed)} changed the graph, {len(teaching)} outside the pattern compiler)")
  print(f"kept in full    {sorted(keep_ids)}")
  print(f"digest          {summary['digest']}")
  for s in sorted(teaching, key=lambda s: -(s["added"] + s["removed"]))[:8]:
    print(f"  {s['i']:>3} {s['caller']:<22} {s['before']:>3} -> {s['after']:>3}  "
          f"+{s['added']}/-{s['removed']}  {s['file']}:{s['line']}")

  first = next((s for s in teaching if s["removed"]), None)
  if first:
    print(f"\nfirst pass that removes nodes: {first['i']} ({first['caller']})")
  return 0


if __name__ == "__main__":
  sys.exit(main())
