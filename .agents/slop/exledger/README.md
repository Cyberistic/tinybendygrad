# `examples.manifest.rows` — the 1:1 ledger for the models / train / benchmark layer

MEASURED 2026-10-19 against HEAD, population **`299`** tracked files: `examples/` 271,
`extra/models/` 15, `extra/datasets/` 13. Every row is one upstream path.

## WHY A MANIFEST AND NOT A MIRRORED TREE

The pilot proved the mirrored tree is the wrong shape: a stub `.bend` that honestly `refuse()`s reports
`SOME PROOFS FAIL` under `bend --check-only`, and `checks/substrate.py` defines **`COLD` as exactly
"first line != `ALL PROOFS CHECK`"** — its own docs warn *"one missing def reddens 19."* So 271 stubs
would flood the substrate census with files that read as broken. The corpus driver was unharmed
(`graphcmp.bend` still `ALL PROOFS CHECK`), so this is a census-cost problem, not a correctness one.

**A `.bend` file lands only when it is real.** Until then the row here is the record.

## DISPOSITIONS ARE MEASURED, NOT DERIVED FROM THE EXTENSION

Each row's `reason` says which test put it there. The extension alone would have misfiled files in
BOTH directions, and the measured counts are why:

| disposition | n | meaning |
|---|---:|---|
| `VERBATIM_COPY` | 166 | no tinygrad API reference — copy the bytes |
| `PORT` | 88 | **the real work** — python/js reaching into the tinygrad API |
| `MINIMAL` | 24 | prose or js that *names* the API; path and note only |
| `MINIMAL_COPY` | 20 | shell/js/py that reach no API but are not assets |
| `ALREADY_BEND` | 1 | ships as `.bend` upstream |

**`117` of the `119` `.sh` files need no tinygrad API; the other 2 do.** **`24` of the `26` `.md`
reference it; 2 do not.** Extension-only classification would have got both pairs backwards.

**LOC that is actually work: `19,104` of `44,135`.**

## THE ORDER, AND WHY IT IS NOT "TRAIN FIRST"

`examples/test_pkl_imagenet.py` (eval) needs **only the forward pass**, and the forward corpus is
**34/34 byte-identical** with `unhealthy() -> 0`, `artefacts_ok() -> 0`, `repro_bad() -> 0`.
`examples/train_resnet.py` (train) additionally needs the backward pass, and
`tinybendygrad/mixin/gradient.bend` (2,453 LOC) **has never been executed by any of the 34 graphs** —
the corpus builds forward graphs only. **EVAL BEFORE TRAIN**, or the first thing that "works" is a
2,453-line gradient engine that has never run.

## HOW TO USE A ROW

Take a `PORT` row, read the upstream file, write `tinybendygrad/<ported_path>`, tick the row's status.
`extra/datasets/*` is the cheapest real work in the ledger: it is largely `fetch()`.
