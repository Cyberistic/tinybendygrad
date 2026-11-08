# Voice, synced to the lesson

The problem is small and exact: a recording is a continuous stream, and a lesson is a
sequence of beats that each highlight a different set of lines. Something has to map
time to beat, and it has to be right on the first frame and the nine-hundredth.

## The rule

**Timing is derived from the audio, never authored by hand and never inferred from text.**

A hand-authored `start: 12.4` goes stale the moment a sentence is re-read. A text-to-timing
model (forced alignment) is a guess that changes when the model changes, and it fails
silently — you get a plausible timeline that is two seconds wrong and nobody notices until
the highlight is on the wrong line. So the boundary comes from the recording itself.

There are two ways to get one, and they produce the same file.

## Mode A — one clip per beat (exact by construction)

`record.html` shows the beat text, records one file, and names it after the beat id.
Sync is not estimated: beat *n* starts when clip *n* starts.

    content/voice/02.4/
      b1.m4a b2.m4a … b7.m4a
      timeline.json

    python3 tools/voice/sync.py clips 02.4 --clips content/voice/02.4

Best for: fixing a single sentence later, because you re-record one 12-second clip.

## Mode B — one continuous take (better to listen to)

Read straight through, pausing about **0.4 s** between beats. `sync.py` runs
`silencedetect`, keeps the silences that are not at the very start or end, and puts each
boundary at the midpoint of a pause.

    python3 tools/voice/sync.py take 02.4 --audio take.wav --slice

`--slice` also writes the per-beat clips, so a continuous take still gives you Mode A's
replaceability.

**The refusal is the feature.** If the number of pauses is not exactly `beats - 1`, it exits
**3** and says how many it heard:

    REFUSED: take.wav has 0 internal pauses, the lesson has 5 beats and needs 4.

It will not guess. A wrong timeline is worse than no timeline, because the player looks fine.

## The seam

Both modes emit `timeline.json`, and the player only ever sees that:

```ts
type Timeline = { lesson, mode, duration, gap?, verified, beats: Beat[] }
type Beat = { id, start, end }        // seconds
```

`packages/course-voice/src/track.ts` answers `beatAt(t, ms)` and `positionAt(t, ms)`. It has no
React, no DOM and no Effect runtime, so it runs in a Worker, in Node under `bun test`, and in
the browser unchanged. The player asks where it is; it never computes a beat from the script.

`validate(t)` is the second gate: contiguous beats (or gaps no larger than the declared pause
in clips mode), a `verified` flag, and a last beat that reaches the end of the audio. A dropped
beat is a gap, and a gap is a failure — not a rounding difference.

    cd packages/course-voice && bun test      # 11 tests, including the timeline on disk

## Before you record: drafts

The player should not wait for a microphone. `draft.py` renders every beat with macOS `say`,
measures each clip, and writes the same timeline marked `draft: true`:

    python3 tools/voice/draft.py 01.1

That is how the first five lessons already have audio: 55 s for 01.1, marked as draft.

## Recording hygiene

- Mono, 48 kHz. Loudness-normalise to **−16 LUFS**, true peak −1.5 dB:
  `ffmpeg -i in.wav -af loudnorm=I=-16:TP=-1.5:LRA=11 -ar 48000 -ac 1 out.wav`
- One room, one microphone, one afternoon. A different room per lesson is audible.
- No music, no room tone bed. Silence between beats is the sync signal.
- Re-read a beat and re-take it; do not edit mid-sentence. The boundary is a pause.

## What is still hand-made

The recording. Everything after it — boundaries, slicing, the timeline, the highlight — is
computed, checked, and red when it is wrong.
