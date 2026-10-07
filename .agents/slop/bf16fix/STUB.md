# bf16fix — unit stub (rule prefix `BF-`)

Owner: `tinybendygrad/runtime/dtype.c`. Nothing committed.
Assignment: two reported defects at `dtype.c:168-176` (`bf16_run` missing the `isfinite`
guard `dtype.py:230` has) and `dtype.c:97-98` (reads as if e5m2 were the only saturating
format).
