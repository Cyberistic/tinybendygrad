#!/usr/bin/env python3
"""Pick one recorded pass and hand it to the React Flow view.

    python3 tools/recorder/export.py --step 93

Writes packages/visualizer/src/data.json. The step number is the recorder's, so
a lesson can cite a figure by pass index and the figure cannot drift: it is the
same JSON the caption counts.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
TRACES = ROOT / "content" / "traces"


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--example", default="add_relu_sum")
  ap.add_argument("--lesson", help="take the trace and step from a lesson's figure block")
  ap.add_argument("--step", type=int, default=None, help="pass index; default: the biggest non-pattern pass")
  ap.add_argument("--out", default=str(ROOT / "packages" / "visualizer" / "src" / "data.json"))
  args = ap.parse_args()

  if args.lesson:
    lesson = json.loads((ROOT / "content" / "lessons" / f"{args.lesson}.json").read_text())
    fig = lesson.get("figure")
    if not fig:
      print(f"{args.lesson} declares no figure", file=sys.stderr)
      return 2
    args.example, args.step = fig["trace"], fig["step"]

  dest = TRACES / args.example
  steps = json.loads((dest / "steps.json").read_text())["steps"]
  teaching = [s for s in steps if s.get("stage") != "pattern" and (s["added"] or s["removed"])]

  if args.step is None:
    chosen = max(teaching, key=lambda s: s["added"] + s["removed"])
  else:
    chosen = next((s for s in steps if s["i"] == args.step), None)
    if chosen is None:
      print(f"no step {args.step} in {dest}/steps.json", file=sys.stderr)
      return 2

  before = json.loads((dest / "graphs" / f"{chosen['i']:03d}-before.json").read_text())
  after = json.loads((dest / "graphs" / f"{chosen['i']:03d}-after.json").read_text())

  pathlib.Path(args.out).write_text(json.dumps({
    "example": args.example,
    "step": {**chosen, "before": before, "after": after},
  }, indent=1) + "\n")

  print(f"step {chosen['i']} · {chosen['caller']} · {chosen['file']}:{chosen['line']}")
  print(f"  {len(before)} -> {len(after)} nodes  +{chosen['added']}/-{chosen['removed']}")
  print(f"  wrote {pathlib.Path(args.out).relative_to(ROOT)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
