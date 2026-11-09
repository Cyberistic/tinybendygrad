#!/usr/bin/env python3
"""Assemble the app's course data from the lessons and the recorded trace.

The app must not read the content directory at runtime — it is a static import,
so a build that succeeds has a course in it. This is the only place that knows
where content lives.

    python3 tools/app-data.py
"""
from __future__ import annotations

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
CONTENT = ROOT / "content"
OUT = ROOT / "apps" / "webapp" / "src" / "data" / "course.json"

STAGES = [
    ("01", "user space & tensor", "what is a Tensor, really?", "2301"),
    ("02", "lazy capture & uop", "why has nothing run yet?", "2566"),
    ("03", "codegen & execution", "what does this program become?", "602"),
    ("04", "schedule", "which ops belong in one kernel?", "933"),
    ("05", "rangeify", "how does a shape become a loop?", "244"),
    ("06", "decompose & rewrite", "how does RELU become MAX?", "445"),
    ("07", "placement & memory", "where does the buffer actually live?", "351"),
    ("08", "linearize & optimize", "in what order do the loops run?", "812"),
    ("09", "render", "how does a UOp become text?", "2101"),
    ("10", "compile & runtime", "what launches, and when?", "2530"),
]


def main() -> int:
  tree = (HERE.parents[3] / "references" / "tinygrad-latest").resolve()
  lessons = []
  for path in sorted(CONTENT.glob("lessons/*.json")):
    lesson = json.loads(path.read_text())
    refs = []
    for ref in lesson["refs"]:
      lines = (tree / ref["file"]).read_text().splitlines()[ref["start"] - 1:ref["end"]]
      refs.append({**ref, "lines": lines})
    lessons.append({
      "id": lesson["id"],
      "stage": lesson["stage"],
      "order": lesson["order"],
      "kind": lesson["kind"],
      "title": lesson["title"],
      "summary": lesson["summary"],
      "minutes": lesson["minutes"],
      "refs": refs,
      "claims": lesson["claims"],
      "beats": lesson["beats"],
      "figure": lesson.get("figure"),
    })

  traces = {}
  for dest in (CONTENT / "traces").iterdir():
    if not (dest / "steps.json").exists():
      continue
    steps = json.loads((dest / "steps.json").read_text())["steps"]
    kept = []
    for s in steps:
      if not s.get("kept"):
        continue
      b = json.loads((dest / "graphs" / f"{s['i']:03d}-before.json").read_text())
      a = json.loads((dest / "graphs" / f"{s['i']:03d}-after.json").read_text())
      kept.append({**s, "before": b, "after": a})
    traces[dest.name] = kept

  OUT.parent.mkdir(parents=True, exist_ok=True)
  OUT.write_text(json.dumps({
    "stages": [{"id": i, "name": n, "question": q, "budget": int(b)} for i, n, q, b in STAGES],
    "lessons": lessons,
    "traces": traces,
  }, separators=(",", ":")))

  print(f"{len(lessons)} lessons · {sum(len(v) for v in traces.values())} kept passes · "
        f"{OUT.stat().st_size // 1024}K → {OUT.relative_to(ROOT)}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
