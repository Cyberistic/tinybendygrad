#!/usr/bin/env python3
"""Generate draft narration with macOS `say`, so the player works before you record.

This exists for one reason: the lesson player should not be blocked on a
microphone. Drafts use the same timeline contract as the real take, are marked
`draft: true`, and are replaced beat by beat as you record. Nothing downstream
knows the difference except a small badge in the corner.

    python3 tools/voice/draft.py 01.1
    python3 tools/voice/draft.py 01.1 --voice Samantha --rate 165

Writes content/voice/<id>/draft/<beat>.m4a and the timeline beside it.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
CONTENT = HERE.parent.parent / "content"
LESSONS = CONTENT / "lessons"


def duration(path: pathlib.Path) -> float:
  out = subprocess.run(
    ["ffprobe", "-v", "error", "-show_entries", "format=duration",
     "-of", "default=nw=1:nk=1", str(path)],
    capture_output=True, text=True, check=True).stdout.strip()
  return float(out)


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("lesson")
  ap.add_argument("--voice", default="Samantha")
  ap.add_argument("--rate", type=int, default=170)
  args = ap.parse_args()

  path = LESSONS / f"{args.lesson}.json"
  if not path.exists():
    print(f"no lesson at {path}", file=sys.stderr)
    return 2
  lesson = json.loads(path.read_text())
  out = CONTENT / "voice" / args.lesson / "draft"
  out.mkdir(parents=True, exist_ok=True)

  beats, cursor = [], 0.0
  with tempfile.TemporaryDirectory() as tmp:
    for b in lesson["beats"]:
      aiff = pathlib.Path(tmp) / f"{b['id']}.aiff"
      m4a = out / f"{b['id']}.m4a"
      subprocess.run(["say", "-v", args.voice, "-r", str(args.rate),
                      "-o", str(aiff), b["text"]], check=True)
      subprocess.run(["afconvert", "-f", "mp4f", "-d", "aac", str(aiff), str(m4a)], check=True)
      d = duration(m4a)
      beats.append({"id": b["id"], "start": round(cursor, 3), "end": round(cursor + d, 3)})
      cursor += d + 0.18
      print(f"  {b['id']:>3}  {d:5.2f}s  {b['text'][:48]}…")

  total = round(cursor - 0.18, 3)
  (out.parent / "draft-timeline.json").write_text(json.dumps({
    "lesson": args.lesson,
    "mode": "clips",
    "audio": None,
    "duration": total,
    "gap": 0.18,
    "verified": True,
    "draft": True,
    "voice": args.voice,
    "beats": beats,
  }, indent=2) + "\n")
  print(f"\n{total:.1f}s of draft narration in {out}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
