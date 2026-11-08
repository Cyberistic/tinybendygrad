#!/usr/bin/env python3
"""Turn a recording into the timeline the player drives the lesson from.

There is no speech recognition here on purpose. Recognition would make the
sync a guess that changes when the model changes. Instead the reader leaves a
pause between beats, ffmpeg reports the silences, and the beat boundaries are
the midpoints. If the number of pauses is not exactly `beats - 1`, this
refuses and says how many it heard. A refusal is a different outcome from a
wrong timeline, and only one of them is recoverable.

Two modes, one output:

    take     one continuous file, pauses between beats
    clips    one file per beat, named <beat>.wav

    python3 tools/voice/sync.py take  01.1 --audio take.wav
    python3 tools/voice/sync.py clips 01.1 --clips content/voice/01.1

`take` also writes the per-beat clips if you pass --slice, so the player can
fetch 11 short files instead of one 90-second one.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
CONTENT = HERE.parent.parent / "content"
LESSONS = CONTENT / "lessons"


def probe_duration(path: pathlib.Path) -> float:
  out = subprocess.run(
    ["ffprobe", "-v", "error", "-show_entries", "format=duration",
     "-of", "default=nw=1:nk=1", str(path)],
    capture_output=True, text=True, check=True).stdout.strip()
  return float(out)


def read_silences(path: pathlib.Path, noise: str, minimum: float) -> list[tuple[float, float]]:
  proc = subprocess.run(
    ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af",
     f"silencedetect=noise={noise}:d={minimum}", "-f", "null", "-"],
    capture_output=True, text=True)
  starts = [float(m) for m in re.findall(r"silence_start: (-?[\d.]+)", proc.stderr)]
  ends = [float(m) for m in re.findall(r"silence_end: (-?[\d.]+)", proc.stderr)]
  return list(zip(starts, ends))


def load_lesson(lid: str) -> dict:
  path = LESSONS / f"{lid}.json"
  if not path.exists():
    raise SystemExit(f"no lesson {lid} at {path}")
  return json.loads(path.read_text())


def write(out: pathlib.Path, data: dict) -> None:
  out.mkdir(parents=True, exist_ok=True)
  target = out / "timeline.json"
  target.write_text(json.dumps(data, indent=2) + "\n")
  for b in data["beats"]:
    print(f"  {b['id']:>3}  {b['start']:7.2f} → {b['end']:7.2f}   {b['end'] - b['start']:6.2f}s")
  print(f"\nwrote {target}")


def from_take(args) -> int:
  lesson = load_lesson(args.lesson)
  audio = pathlib.Path(args.audio).resolve()
  duration = probe_duration(audio)
  gaps = read_silences(audio, args.noise, args.min_gap)

  # a silence that opens the file or runs to the end is not a beat boundary
  internal = [(s, e) for s, e in gaps if s > 0.05 and e < duration - 0.05]
  want = len(lesson["beats"]) - 1
  if len(internal) != want:
    print(f"REFUSED: {audio.name} has {len(internal)} internal pauses, "
          f"the lesson has {len(lesson['beats'])} beats and needs {want}.\n"
          f"  pauses heard: {[(round(s, 2), round(e, 2)) for s, e in internal]}",
          file=sys.stderr)
    return 3

  cuts = [0.0] + [(s + e) / 2 for s, e in internal] + [duration]
  beats = [
    {"id": b["id"], "start": round(cuts[i], 3), "end": round(cuts[i + 1], 3)}
    for i, b in enumerate(lesson["beats"])
  ]
  out = pathlib.Path(args.out) if args.out else CONTENT / "voice" / args.lesson
  write(out, {
    "lesson": args.lesson,
    "mode": "continuous",
    "audio": audio.name,
    "duration": round(duration, 3),
    "detected_gaps": len(internal),
    "verified": True,
    "beats": beats,
  })

  if args.slice:
    for b in beats:
      subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(audio),
        "-ss", str(b["start"]), "-to", str(b["end"]),
        "-c:a", "aac", "-b:a", "96k", str(out / f"{b['id']}.m4a")],
        check=True)
    print(f"sliced {len(beats)} clips into {out}")
  return 0


def from_clips(args) -> int:
  lesson = load_lesson(args.lesson)
  src = pathlib.Path(args.clips)
  beats, cursor = [], 0.0
  for b in lesson["beats"]:
    match = next((p for p in src.glob(f"{b['id']}.*")
                  if p.suffix in {".wav", ".m4a", ".webm", ".mp3", ".aac"}), None)
    if match is None:
      print(f"REFUSED: no clip for beat {b['id']} in {src}", file=sys.stderr)
      return 3
    d = probe_duration(match)
    beats.append({"id": b["id"], "start": round(cursor, 3), "end": round(cursor + d, 3)})
    cursor += d + args.gap

  write(src, {
    "lesson": args.lesson,
    "mode": "clips",
    "audio": None,
    "duration": round(cursor - args.gap, 3),
    "gap": args.gap,
    "verified": True,
    "beats": beats,
  })
  return 0


def main() -> int:
  ap = argparse.ArgumentParser()
  sub = ap.add_subparsers(dest="mode", required=True)

  t = sub.add_parser("take", help="one continuous recording with pauses between beats")
  t.add_argument("lesson")
  t.add_argument("--audio", required=True)
  t.add_argument("--out")
  t.add_argument("--noise", default="-35dB")
  t.add_argument("--min-gap", type=float, default=0.30)
  t.add_argument("--slice", action="store_true")

  c = sub.add_parser("clips", help="one file per beat")
  c.add_argument("lesson")
  c.add_argument("--clips", required=True)
  c.add_argument("--gap", type=float, default=0.18)

  args = ap.parse_args()
  return from_take(args) if args.mode == "take" else from_clips(args)


if __name__ == "__main__":
  sys.exit(main())
