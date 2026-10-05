# devgate — is the `DEV` assignment in this file a SETTING, or a COMMENT?

2026-10-04. Nothing committed. NEW files only; no other unit's tree touched except
`oracles/mm-range.py`, which the brief assigned and which is fixed (it now prints
`device: NULL`). Read `DEV-GATE.md` for the measured counts, the error rate, and the four bugs
this instrument had in its own readout.

## The defect being classified

`Device.DEFAULT` is resolved when `tinygrad` is imported. A source line that assigns `DEV`
**after** that import is not a setting — it is a comment, and the code believes it chose.

## The result

`69` `.py` files in the tree write `DEV`; `14` are vendored; **`55` is the denominator and all
55 are `EARLY`.** The one `LATE` in the tree was `mm-range.py` and it is fixed.

## Deliverables

- `devgate.py` — the classifier: `--check` `--why` `--plants` `--heldout` `--crosscheck`
- `DEV-GATE.md` — counts, error rate, hit rate, and what is still open

## Files

```
devgate.py               the classifier. AST-based, so a READ is never a write.
CLAIM-devgate.md         this file, written BEFORE the code
DEV-GATE.md              the report
```