#!/usr/bin/env python3
"""Render every lesson's narration into a recording script.

The lesson JSON is the source. This file is a projection of it, so a beat that
is edited or deleted cannot survive in the script: there is no second copy to
drift. Run it after any content change.

    python3 tools/voice/script.py            # writes content/voice/*.script.md
    python3 tools/voice/script.py --check    # exits 1 if a script is stale

Pace is estimated at 150 words per minute, which is slow-but-clear for
technical narration. The estimate is for planning only; the real timing comes
from the audio, never from this number.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
CONTENT = HERE.parent.parent / "content"
LESSONS = CONTENT / "lessons"
OUT = CONTENT / "voice"
WPM = 150


def render(lesson: dict) -> str:
  words = sum(len(b["text"].split()) for b in lesson["beats"])
  seconds = round(words / WPM * 60)
  lines = [
    f"# {lesson['id']} — {lesson['title']}",
    "",
    f"stage {lesson['stage']} · order {lesson['order']} · {lesson['minutes']} min · "
    f"{len(lesson['beats'])} beats · ~{seconds}s of narration",
    "",
    f"> {lesson['summary']}",
    "",
    "## recording",
    "",
    "Two modes, one output contract. Do not rename a beat id: it is the filename.",
    "",
    "- **per beat** — `record.html`, one clip per beat. Sync is exact by construction.",
    "- **one take** — read straight through, pausing **0.4 s** between beats. `sync.py`",
    "  finds the pauses, requires exactly `beats - 1` of them, and writes the timeline.",
    "  If it hears a different number it refuses; it never guesses a boundary.",
    "",
    "| beat | words | ~s | cue |",
    "| --- | ---: | ---: | --- |",
  ]
  for b in lesson["beats"]:
    cue = ", ".join(b.get("cue", {}).get("claims", [])) or "—"
    lines.append(f"| `{b['id']}` | {len(b['text'].split())} | "
                 f"{round(len(b['text'].split()) / WPM * 60)} | {cue} |")

  for b in lesson["beats"]:
    lines += ["", "---", "", f"### {b['id']}", "", b["text"], ""]
    cue = b.get("cue", {})
    if cue.get("claims"):
      lines.append(f"*cue:* {', '.join(cue['claims'])}")
    if cue.get("lines"):
      lines.append(f"*lines:* {', '.join(str(n) for n in cue['lines'])}")
    if b.get("direction"):
      lines.append("")
      lines.append(f"*direction:* {b['direction']}")
  lines.append("")
  return "\n".join(lines)


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--check", action="store_true")
  args = ap.parse_args()
  OUT.mkdir(parents=True, exist_ok=True)

  stale = 0
  for path in sorted(LESSONS.glob("*.json")):
    lesson = json.loads(path.read_text())
    text = render(lesson)
    target = OUT / f"{lesson['id']}.script.md"
    if args.check:
      if not target.exists() or target.read_text() != text:
        print(f"stale: {target.name}")
        stale += 1
    else:
      target.write_text(text)
      print(f"wrote {target.name}  ({len(text.splitlines())} lines)")

  if args.check:
    print(f"{stale} stale script(s)")
    return 1 if stale else 0
  return 0


if __name__ == "__main__":
  sys.exit(main())
