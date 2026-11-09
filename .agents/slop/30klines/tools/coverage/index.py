#!/usr/bin/env python3
"""Build the coverage index: which line of tinygrad is explained by which lesson.

This is the same fold that produces the progress bar, but with attribution kept.
A line is covered when a claim names it, and the claim names the lesson — so the
browser can jump from a green line to the thing that explains it.

    python3 tools/coverage/index.py

Writes content/coverage.json. Refuses if a claim's line is outside its own ref,
because a coverage map built on a bad range points at the wrong code.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent            # .agents/slop/30klines
CONTENT = ROOT / "content"
LESSONS = CONTENT / "lessons"


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--out", default=str(CONTENT / "coverage.json"))
  args = ap.parse_args()

  files: dict[str, dict[str, list[str]]] = {}
  lessons: dict[str, dict] = {}
  problems: list[str] = []

  for path in sorted(LESSONS.glob("*.json")):
    lesson = json.loads(path.read_text())
    lid = lesson["id"]
    claims = []
    for claim in lesson["claims"]:
      ref = lesson["refs"][claim["ref"]]
      for line in claim["lines"]:
        if not ref["start"] <= line <= ref["end"]:
          problems.append(f"{claim['id']}: line {line} outside {ref['file']}:{ref['start']}-{ref['end']}")
          continue
        files.setdefault(ref["file"], {}).setdefault(str(line), [])
        if lid not in files[ref["file"]][str(line)]:
          files[ref["file"]][str(line)].append(lid)
      claims.append({"id": claim["id"], "kind": claim["kind"], "text": claim["text"],
                     "file": ref["file"], "lines": claim["lines"]})
    lessons[lid] = {"title": lesson["title"], "stage": lesson["stage"], "claims": claims}

  if problems:
    print(f"{len(problems)} claim(s) point outside their ref:", file=sys.stderr)
    for p in problems:
      print(f"  ✗ {p}", file=sys.stderr)
    return 1

  covered = sum(len(v) for v in files.values())
  census_path = CONTENT / "census.json"
  census = json.loads(census_path.read_text()) if census_path.exists() else {}
  total = census.get("total", 0)

  out = {
    "tree": census.get("tree"),
    "commit": census.get("commit"),
    "totals": {"covered": covered, "total": total,
               "files_touched": len(files), "files_total": len(census.get("files", {}))},
    "files": files,
    "lessons": lessons,
  }
  pathlib.Path(args.out).write_text(json.dumps(out, indent=1, sort_keys=True) + "\n")

  print(f"covered   {covered} of {total} lines ({100 * covered / total:.2f}%)" if total else f"covered {covered} lines")
  print(f"touched   {len(files)} of {len(census.get('files', {}))} files")
  for f, lines in sorted(files.items(), key=lambda kv: -len(kv[1])):
    who = sorted({l for ls in lines.values() for l in ls})
    print(f"  {f:36} {len(lines):>4} lines   {', '.join(who)}")
  print(f"\nwrote {pathlib.Path(args.out).relative_to(ROOT)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
