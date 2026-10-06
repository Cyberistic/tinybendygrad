# PEAKRSS — one `bend --check-only` costs up to 1.15 GB, and two at once crashed the machine

**Measured over all 138 port `.bend` files, sequentially, each under `checks/bounded.py` with a
1024 MB ceiling.** Census: `.agents/slop/peakrss/census.txt`. Data: `runs/peakrss.json`.

## The distribution, and it is BIMODAL

```
max      1152 MB   renderer/nir.bend    <- KILLED at the 1 GB ceiling
         1108 MB   sz.bend              <- KILLED at the 1 GB ceiling
          864 MB   runtime/ops_python.bend
median    207 MB
          683 MB   dtype.bend
under 50 MB: 43 of 138        0 MB: LAWS.bend, base.bend, __init__.bend, device.bend
over 600 MB: 12 of 138        timed out: 0 of 138      empty files: 0 of 138
```

**`base.bend` IS 0 MB AND `device.bend` IS 0 MB, SO THIS IS *NOT* THE IMPORT CLOSURE.** `helpers.bend`
(2,768 lines, the root of the closure) is 204 MB and `dtype.bend` (1,132 lines, 4 imports) is
683 MB. **A CLOSURE-SIZE EXPLANATION IS FALSIFIED BY THE MEASUREMENT, NOT ASSUMED.**

## The operational rule, which is what prevents recurrence

**NEVER RUN TWO `bend` PROCESSES CONCURRENTLY ON THIS PORT.**
1,152 + 1,108 MB plus `bun` overhead is the crash. The project's own guard already runs its files
sequentially for this reason, which is why the cost was never noticed and never attributed.

## NOT ESTABLISHED, AND NOT CLAIMED

**WHY `dtype.bend` COSTS 683 MB IS OPEN.** The suspects are `Nat` (Peano, saturating `sub`,
ceiling `2^48-1`, no negative representable) and `i64_mul`'s 16-bit limb arithmetic — a typechecker
that eagerly unfolds either will allocate. **NEITHER IS MEASURED.** A unit chasing this should
bisect by import: `dtype.bend` minus its `dtype.c`/JS seam, then minus `i64_*`, then minus `Nat`.

## Why this census is not just a size table

**`bend --check-only` REPORTS `ALL PROOFS CHECK` FOR AN EMPTY FILE**, so the census counts empty
files separately and names them. **0 of 138 today — after `helpers.bend` was truncated to 0 bytes
for the FOURTH time today while answering `ALL PROOFS CHECK`.** A verdict without a size is not a
verdict about a file.
