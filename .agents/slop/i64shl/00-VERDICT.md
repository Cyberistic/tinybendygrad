# `i64_shl` with a RUNTIME shift amount — verdict

unit: one job. establish OPEN / STALE / RETIRED for the `i64_shl` runtime-amount wall.

STATUS: IN PROGRESS. started 2026-10-05.

## FIRST FINDING (before any compile)

`helpers.bend:1819` — grep hit on the very first sweep:

    def i64_shl(+x: I64, +k: Nat) -> I64:

so the def EXISTS, IS PURE, and ALREADY TAKES A `Nat`. And
`codegen/decomp/dtype.bend:1604` calls it with `U32.to_nat(j)` — a runtime amount.
So the wall's premise ("a runtime shift amount cannot be a `Nat`") is disproven in-tree
BEFORE a single row was written. Verdict shaping up as STALE.

## Pending

- read `helpers.bend:1800-1830` verbatim
- read `uop/fold.bend` standing instruction (~2659)
- find upstream `tinygrad/` answer with `file:line`
- rows over the boundary amounts 0/63/64/65/>=64
- plant + disarm with row NAMES