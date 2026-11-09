#!/usr/bin/env python3
"""Export every kept pass of a recorded trace for the visualizer.

    python3 tools/recorder/export.py                 # the whole run
    python3 tools/recorder/export.py --lesson 04.1   # one lesson, positioned at its figure

The page is a scrubbable timeline, so it needs the sequence, not one frame.
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
  ap.add_argument("--lesson", help="open at this lesson's figure")
  ap.add_argument("--out", default=str(ROOT / "packages" / "visualizer" / "src" / "data.json"))
  args = ap.parse_args()

  start_at = None
  if args.lesson:
    lesson = json.loads((ROOT / "content" / "lessons" / f"{args.lesson}.json").read_text())
    fig = lesson.get("figure")
    if not fig:
      print(f"{args.lesson} declares no figure", file=sys.stderr)
      return 2
    args.example, start_at = fig["trace"], fig["step"]

  dest = TRACES / args.example
  steps = json.loads((dest / "steps.json").read_text())["steps"]

  out = []
  for step in steps:
    if not step.get("kept"):
      continue
    before = json.loads((dest / "graphs" / f"{step['i']:03d}-before.json").read_text())
    after = json.loads((dest / "graphs" / f"{step['i']:03d}-after.json").read_text())
    out.append({**step, "before": before, "after": after})

  start = next((i for i, s in enumerate(out) if s["i"] == start_at), 0)
  pathlib.Path(args.out).write_text(json.dumps({
    "example": args.example,
    "start": start,
    "steps": out,
  }, indent=1) + "\n")

  print(f"{len(out)} kept passes · opens at index {start} ({out[start]['caller']})")
  print(f"  wrote {pathlib.Path(args.out).relative_to(ROOT)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
