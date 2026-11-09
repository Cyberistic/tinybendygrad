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

`content/lessons/*.json` — 01.1, 01.2, 02.1, 02.2, 02.3, 02.4, 02.5. 33 claims, 42 narration beats.

```
python3 .agents/slop/30klines/tools/verify.py --tree references/tinygrad-latest
  coverage       72 / 26106 lines  (0.28%)
    tinygrad/tensor.py                   39 lines
    tinygrad/uop/__init__.py              6 lines
    tinygrad/uop/ops.py                  27 lines
  lessons 7 · refs 8 · claims 33 · beats 42 · filled 0
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

## 4. The player is real, and it is driven by the timeline

`tools/player/build.py` cuts the source out of the vendored tree, inlines the timeline,
copies the clips, and bundles the page with bun. The page imports `track.ts` — the same file
`bun test` covers — so the player has no timing logic of its own to drift.

```
python3 tools/player/build.py 02.4
  content/player/02.4/index.html  (7 clips, 1 refs, 14 source lines)
```

`art/07-player-b2.png` and `art/08-player-b6.png` are the same page at two beats:
b2 highlights line 184 and the effect claim; b6 highlights 186–193 and the SPEC claim, with
its own narration. `?beat=b6` is a shareable frame, which is also how the screenshots were taken.

## 5. The recorder, and VIZ in React Flow

`tools/recorder/record.py` wraps `RewriteContext.unified_rewrite` — a method, so every
importer is caught — and snapshots the sink before and after each pass. No tinygrad source is
patched.

```
uv run --no-project --with numpy --python 3.12 python tools/recorder/record.py
  lazy graph      14 nodes
  after schedule  18 nodes
  rewrite passes  293 (231 changed the graph, 33 outside the pattern compiler)
  digest          3084f7012aa42ca4      # identical on a second run
```

231 of the 293 changing passes are the pattern compiler simplifying its own generated Python
(`upat.py`). They are labelled `stage: "pattern"` rather than dropped, because a filter that
silently removes data is the thing this repo keeps getting bitten by.

The pass worth a figure is `transform_to_call` at `schedule/__init__.py:263`: **21 nodes in,
21 nodes out, +15/−15**. A count says nothing happened. The structure says everything did.

`packages/visualizer` renders it: `src/flow.ts` is the adapter (recorded graph → React Flow
nodes/edges, top-down ranks like VIZ's dagre config), `src/app.tsx` is the view, and 9 tests
cover the adapter against the real recorded passes.

```
cd packages/visualizer && bun test
  9 pass, 0 fail
```

`art/09-viz-react-flow.png` is that page.

## 6. What is not done

- Seven lessons is not a course. Stage 01 needs eight, stage 02 needs nineteen.
- No React app yet: the six screens are `mock/*.html` and the player is a bundled
  single-page build, not the TanStack app.
- The draft voice is macOS `say`. The real takes are the user's to record.
- The trace recorder (SPEC §6.1) is designed, not written.
