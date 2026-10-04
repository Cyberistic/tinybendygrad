# W64-MILE — status (append-only)

Rule prefix for this unit: **`W64M-`**. Source spec: `.agents/slop/W64.md`.

## 0. STARTED (stub written before any reading)

Own slop tree: `.agents/slop/w64mile/`. Nothing committed.

- `STATUS.md` — this file.
- Read `agent-core.md` and `W64.md`. Nothing else yet.
## 1. DONE

Report: `.agents/slop/W64-MILE.md`. Prefix `M-` (in TODO.md and
notes/bend2-constraints.md) and `W64M-` (here).

| file | what |
|---|---|
| `patch_dtype.py` + `i64-pure.bend.txt` | the six `Dt.i64_*` as pure Bend, installed IN PLACE by one anchored span |
| `dtype-i64.patch` + `dtype.patched.bend` | the change, unapplied |
| `gen_i64.py` + `gate.txt` + `i64_pure.out.txt` + `i64_pure.bend` | 172 rows vs CPython, BASE/PLANT/DISARM |
| `gen_halves.py` + `halves-census.txt` | the 16 blocked bindings: return-only 16/16, 7 call sites, 5 of 16 called |
| `emit_halves.py` + `halves.txt` + `halves/*.bend` + `halves/*.c` | 15/16 built, linked, run, equal to CPython |

M-1 `dtype.bend` 14 red -> 8. M-2 308 + 15 = **323/324** laws that compile, link
and run. Nothing committed; `tinybendygrad/dtype.bend` and
`tinybendygrad/helpers.bend` untouched by this unit.

## 2. THE HAZARD THAT WAS LIVE DURING THIS UNIT, NOW CLEARED

`tinybendygrad/helpers.bend` was **0 bytes** for most of this session. `jj status`
reported it as a RENAME to `.agents/slop/nested/baseline-probe.err` — two empty
files, so the inference was technically right and completely misleading. It was
back at 116,479 bytes (HEAD: 116,482) by 19:51. **If a future unit sees that
directory entry, the file is empty, not moved.**
