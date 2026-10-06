# bf16 unit — STUB (first thing on disk, resumable)

Scope: `tinybendygrad/runtime/dtype.c` (owned), `tinybendygrad/runtime/dtype.js`
(READ-ONLY, other lane). Report prefix `BF16-`. **Nothing committed.**

Baselines (md5, measured at unit start):

- `tinybendygrad/runtime/dtype.c`  `b04ed13da1716b9e757a839fa33da790`
- `tinybendygrad/runtime/dtype.js` `44294858354c23b02c595f423aacef40`

Defect as briefed: `bf16_run has no isfinite guard`. Re-measurement in progress.