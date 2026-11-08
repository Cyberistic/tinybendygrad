# Report — 2026-11-09

What exists, and the command that proves it. Nothing here is asserted without a transcript.

## 1. The tree is on latest tinygrad

`references/tinygrad-latest` is a shallow clone at `6295132e` (2026-11-08, `fix valid dropped
through EXPAND [pr] (#19262)`). It is gitignored; the course cites it and nothing else.

Upstream moved **47 files** relative to this repo's pinned `tinygrad/`, including 112 lines in
`uop/ops.py` and 8 in `tensor.py`. That is why the lesson refs were re-pointed: the metaclass is
at line 181 in the new tree, not 190.

The census comes from tinygrad's own counter, `sz.py`, loaded by path and called as a function —
not re-implemented:

```
uv run --no-project --with tabulate --with numpy --python 3.12 \
  python .agents/slop/30klines/tools/census.py

  tinygrad/runtime           7303
  tinygrad/renderer          3629
  tinygrad/uop               2581
  ...
  core                       9329
  total                     26106
  files                       116
```

## 2. Five lessons exist, with scripts

`content/lessons/{01.1, 01.2, 02.1, 02.4, 02.5}.json` — 23 claims, 30 narration beats.

```
python3 .agents/slop/30klines/tools/verify.py --tree references/tinygrad-latest
  coverage       64 / 26106 lines  (0.25%)
    tinygrad/tensor.py                   38 lines
    tinygrad/uop/ops.py                  26 lines
  lessons 5 · refs 5 · claims 23 · beats 30 · filled 0
  ✓ every ref matches the tree
```

Every ref carries a sha256 of its exact lines. **The gate can go red** — mutating one line in a
copy of the tree:

```
sed -i '' 's/__slots__ = "uop", "is_param", "grad"/… , "extra"/' /tmp/30k-mut/tinygrad/tensor.py
python3 tools/verify.py --tree /tmp/30k-mut
  ✗ 01.1: ref0 DRIFTED tinygrad/tensor.py:44-55 expected 7bfa220a6c06 got 41bf88bce14e
  rc=1
```

It also rejects a claim whose line falls outside its own ref, an unknown cue, an empty beat, and
a lesson with no claims.

Scripts are generated from the lessons, never written twice:

```
python3 tools/voice/script.py
  wrote 01.1.script.md … 02.5.script.md
```

## 3. Voice sync works, both directions

`tools/voice/sync.py` derives the timeline from the audio. No ASR: the boundary is the midpoint of
a pause the reader leaves, so it cannot drift with a model.

**Accepted** — five beats from an 8 s file with four pauses:

```
python3 tools/voice/sync.py take 01.1 --audio /tmp/30k-take.wav --out /tmp/30k-tl
   b1     0.00 →    1.30
   b2     1.30 →    2.90
   b3     2.90 →    4.50
   b4     4.50 →    6.10
   b5     6.10 →    8.00
  rc=0
```

**Refused** — a flat take with no pauses:

```
python3 tools/voice/sync.py take 01.1 --audio /tmp/30k-flat.wav
  REFUSED: 30k-flat.wav has 0 internal pauses, the lesson has 5 beats and needs 4.
  rc=3
```

The runtime contract is `packages/course-voice/src/track.ts` — dependency-free, so it runs in a
Worker and under `bun test`. The test suite found a real inconsistency on first run: clips mode
has an intentional 0.18 s gap that `validate` was rejecting as a hole. Fixed in the contract.

```
cd packages/course-voice && bun test
  11 pass, 0 fail, 19 expect() calls
```

Draft audio exists so the player is not blocked on a microphone:

```
python3 tools/voice/draft.py 01.1
  b1 9.23s · b2 9.98s · b3 16.62s · b4 11.37s · b5 7.28s
  55.2s of draft narration
```

## 4. What is not done

- Four lessons is not a course. Stage 01 needs eight, stage 02 needs nineteen.
- No React app yet: the six screens are `mock/*.html`, the player is `track.ts` only.
- The draft voice is macOS `say`. The real takes are the user's to record.
- The trace recorder (SPEC §6.1) is designed, not written.
