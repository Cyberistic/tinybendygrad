#!/usr/bin/env python3
"""Verify every lesson's SourceRef against a vendored tinygrad tree.

A ref is a file plus an inclusive line range. Its sha is sha256 over those
lines and their trailing newlines, byte for byte. Editing one line upstream
changes the sha, and the build goes red naming the lesson — which is the
whole point: a citation that cannot fail is a label.

    python3 tools/verify.py --tree references/tinygrad-latest
    python3 tools/verify.py --tree references/tinygrad-latest --write

`--write` fills a null sha. It refuses to overwrite one that disagrees, so a
clean tree cannot be silently re-pinned.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
CONTENT = HERE.parent / "content"
LESSONS = CONTENT / "lessons"


def read_ref(tree: pathlib.Path, file: str, start: int, end: int) -> bytes:
  path = tree / file
  if not path.exists():
    raise FileNotFoundError(f"{file} is not in {tree}")
  lines = path.read_bytes().splitlines(keepends=True)
  if not 1 <= start <= end <= len(lines):
    raise ValueError(f"{file}:{start}-{end} is outside 1..{len(lines)}")
  return b"".join(lines[start - 1:end])


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--tree", default="references/tinygrad-latest")
  ap.add_argument("--write", action="store_true")
  args = ap.parse_args()
  tree = pathlib.Path(args.tree).resolve()

  failures: list[str] = []
  filled = 0
  totals = {"refs": 0, "claims": 0, "beats": 0}
  declared: dict[str, set[int]] = {}

  for path in sorted(LESSONS.glob("*.json")):
    lesson = json.loads(path.read_text())
    lid = lesson["id"]
    if path.stem != lid:
      failures.append(f"{lid}: filename {path.name} does not match id")

    claim_ids = {c["id"] for c in lesson["claims"]}
    if not claim_ids:
      failures.append(f"{lid}: no claims — a lesson that claims nothing is a blog post")

    for i, ref in enumerate(lesson["refs"]):
      try:
        body = read_ref(tree, ref["file"], ref["start"], ref["end"])
      except (FileNotFoundError, ValueError) as e:
        failures.append(f"{lid}: ref{i}: {e}")
        continue
      sha = hashlib.sha256(body).hexdigest()
      totals["refs"] += 1
      if ref["sha"] is None:
        if args.write:
          ref["sha"] = sha
          filled += 1
        else:
          failures.append(f"{lid}: ref{i} has no sha (run --write)")
      elif ref["sha"] != sha:
        failures.append(f"{lid}: ref{i} DRIFTED {ref['file']}:{ref['start']}-{ref['end']} "
                        f"expected {ref['sha'][:12]} got {sha[:12]}")

    for claim in lesson["claims"]:
      totals["claims"] += 1
      if not 0 <= claim["ref"] < len(lesson["refs"]):
        failures.append(f"{claim['id']}: ref index {claim['ref']} out of range")
        continue
      ref = lesson["refs"][claim["ref"]]
      for line in claim["lines"]:
        if not ref["start"] <= line <= ref["end"]:
          failures.append(f"{claim['id']}: line {line} is outside its ref "
                          f"{ref['file']}:{ref['start']}-{ref['end']}")
      declared.setdefault(ref["file"], set()).update(claim["lines"])

    for beat in lesson["beats"]:
      totals["beats"] += 1
      if not beat["text"].strip():
        failures.append(f"{lid}/{beat['id']}: empty script")
      for cid in beat.get("cue", {}).get("claims", []):
        if cid not in claim_ids:
          failures.append(f"{lid}/{beat['id']}: cues unknown claim {cid}")

    if args.write and filled:
      path.write_text(json.dumps(lesson, indent=2, ensure_ascii=False) + "\n")

  census_path = CONTENT / "census.json"
  covered = sum(len(v) for v in declared.values())
  if census_path.exists():
    census = json.loads(census_path.read_text())
    total = census["total"]
    print(f"coverage   {covered:>6} / {total} lines  ({100 * covered / total:.2f}%)")
  else:
    print(f"coverage   {covered:>6} lines declared (no census.json yet)")
  for file, lines in sorted(declared.items()):
    print(f"  {file:34} {len(lines):>4} lines")

  print(f"\nlessons {len(list(LESSONS.glob('*.json')))} · refs {totals['refs']} · "
        f"claims {totals['claims']} · beats {totals['beats']} · filled {filled}")
  if failures:
    print(f"\n{len(failures)} failure(s):")
    for f in failures:
      print(f"  ✗ {f}")
    return 1
  print("\n✓ every ref matches the tree")
  return 0


if __name__ == "__main__":
  sys.exit(main())
