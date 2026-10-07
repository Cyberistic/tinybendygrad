# W64-MILE — status. Append-only; the report is `../W64-MILE.md`.

Rule prefix for this unit: **`W64M-`** (notes: `notes/bend2-constraints.md`,
TODO: `.agents/TODO.md`). **Nothing committed by hand.**

## 0. Re-run of the previous attempt — BOTH GATES REPRODUCE

Not a fresh build: `99aa3b386` already carries `W64-MILE.md` and its generators.
Measured on Bend 2.0.34, 2026-10-04, on a `$TMPDIR` copy of the whole tree.

| gate | printed |
|---|---|
| `gen_i64.py` (M-1) | `BASE PASS pass=170 diverge=2 fail=0` · `PLANT 7 rows moved, all on cmod` · `DISARM 0 rows moved` · `rows present 173 / rows expected 173` |
| `emit_halves.py` (M-2, `LIBCLANG_PATH` pinned, asserted with `ls -la`) | `built 15/16` · `port line == CPython line: 15 of 15` · `PLANT 1 row moved` · `DISARM 0 rows moved` |

So targets 1 and 2 stand as written, and target 3's list stands except items 4
and 6, which this run refutes.

## 1. What this run added

| file | what |
|---|---|
| `t1_wire.c` / `t1_wire.bend` / `gen_wire.py` / `wire-gate.txt` | an `H.I64` argument arrives **BOXED**; 32 rows; plant 4 (the asymmetric rows only), disarm 0 |
| `gen_seam.py` / `seam-gate.txt` | the six `Dt.i64_*` as shipped agree with CPython **0/30**; fixed **30/30**; plant 30/30, disarm 0 |
| `dtype-c-i64.patch` | the 6-line fix, verified on a copy, **not applied** |
| `t1_probe.bend` / `t1_smoke.bend` / `t1_guard.bend` | the three raw probes the diagnosis came from |

Two of our own walls refuted rather than reconciled, per `agent-core.md`:
`W64-MILE.md` item 4 / build fact 1 (the `#ifdef CID(...)` guards **do** work and
the C lane **does** build), and `W64.md`'s "a 64-bit pair cannot be returned from
one foreign def" (false on the return direction; `pack64` is correct 8/8).

## 2. Substrate, at the end

```
COLD  tinybendygrad/dtype.bend  (638 lines)  :: SOME PROOFS FAIL   <- its own 14 seams, expected
WARM  tinybendygrad/helpers.bend (2605 lines)
```

`tinybendygrad/dtype.bend`, `runtime/dtype.c` and `runtime/dtype.js` are
**byte-unchanged** by this unit — every gate ran on a `$TMPDIR` copy or in a
scratch build under this directory. Both patches are files, not edits.

One caveat on `substrate-check.sh`: it is bend-only, so feeding it `dtype.c` /
`dtype.js` reports them COLD for the trivial reason that they are not Bend. The
substrate claim is about `.bend` files.