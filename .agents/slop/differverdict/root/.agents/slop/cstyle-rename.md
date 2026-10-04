# DELIVERABLE 1 — the eight `kern` row names, and the citation for the new spelling

## The eight, exactly as they shipped

`./bin/bend tinybendygrad/renderer/cstyle.bend`, read through `rows_strict` (`cstyle-gate.py`),
227 names, **8 of them containing `=`**:

```
kern BASE  lb=1     kern CLANG lb=4     kern OPENCL lb=1    kern METAL lb=1
kern CUDA  lb=1     kern CUDA  lb=4     kern HIP   lb=1     kern HIP   lb=4
```

One coordinate emits all eight: `cstyle.bend:1757` `kern_row`, which printed
`nm ++ " lb=" ++ U32.show(lb) ++ " = [" ++ kernel_typedef(dev, lb) ++ "]   py=[" ++ py ++ "]"`.

## What a reader does to them, MEASURED by calling `rebase-gate.py:rows()`

`rows()` -> `row()` splits a row line on its **FIRST `=`** and keeps the head as the name.

| lane | physical rows | `rows()` names | unaddressable |
|---|---|---|---|
| port | 227 | **225** | **2** |
| oracle | 224 | **222** | **2** |

And the survivors were the **`lb=4`** values — `rows()` builds a dict, so the later row
silently overwrote the earlier one:

```
'kern CUDA  lb' -> '4 = [extern "C" __global__ void __launch_bounds__(4)]'
'kern HIP   lb' -> '4 = [extern "C" __attribute__((global)) void __attribute__((amdgpu_fla'
```

So `kern CUDA  lb=1` and `kern HIP   lb=1` were **two measurements that existed on stdout and
that no name could reach**, on both sides of the lane. `uop/validate.bend` paid the identical
bill once (`cmp_i<=5`, 310 printed rows read as 280, 30 collapsed onto 10 names).

## The rename, and the upstream citation for the VALUE

`kern <DEV> lb=<N>`  ->  `kern <DEV> lb <N>`. One character in one def
(`cstyle.bend:1758`, `" lb="` -> `" lb "`), and the same f-string in
`.agents/slop/renderer_oracle.py:396`, which is ONE coordinate with it.

**Why `lb` stays and only the separator moves.** Upstream's name for the value is
`launch_bounds`, and it is a single name for a single thing:

- `tinygrad/renderer/cstyle.py:163` — `launch_bounds = prod([d.vmax for d in local_dims])`
- `tinygrad/renderer/cstyle.py:164` — `self.kernel_typedef.format(launch_bounds=launch_bounds)`,
  its **only** consumer, reached from `render_kernel`.

`cstyle.py` has no identifier `lb`; the token `lb` is this port's standing abbreviation, and
the port already used it on the `kern_row` **parameter** (`def kern_row(..., +lb: U32)`) with
the same meaning. So the rename changes the separator and nothing else, and the name still
says the same thing. The `=` was the defect, not the token.

Rejected alternatives, and why:

- **`kern CUDA  launch_bounds 1`** — upstream's spelling, and the longest. Rejected because it
  makes one family (`kern`, 8 rows) read under two vocabularies against its own 30-row
  `kern2` sibling and 26 `opt`/`acc`/`ptr` rows that already abbreviate.
- **`kern CUDA  lb1`** — no separator at all, so no reader can split it. Rejected: `lb1` reads
  as one identifier and `lb 1` reads as two columns, and the file is column-aligned
  throughout (`kern CUDA `, `kern HIP  `, `kern2 HIP   bf16h`). Two tokens keeps the alignment
  and every existing reader splits it the same way, because the only delimiter in the name is
  now a space — which the shipped `row()` only treats as a separator on the **F3** path, i.e.
  only for lines with no `=` at all.
- **Teach `row()` a smarter split.** Rejected: `rebase-gate.py` is live and owned elsewhere,
  and the brief is right that this does not fix the class — a boundary matcher that splits on
  `=` will mis-split the name that contains it. `tcptx-oracle.py:386` already shows the cost of
  that route in a sibling lane.

## Collisions after renaming: NONE, and here is the check

```
new port rows: 227   distinct names: 227   DUPLICATE names: none
value multiset unchanged by the rename: True
removed-without-replacement: []
```

1:1, value-neutral, 227 distinct names out of 227 rows. All eight new names are pairwise
distinct because `<DEV>` and `<N>` were already distinct across the eight; the separator was
carrying no information that the two tokens did not.

So there is no collision finding here. What the rename *did* find is the other half of the
brief's warning, and it is in the deliverable below: the eight names were **6 keys**, and the
two that vanished were not the two whose names looked redundant.

## What is left for another unit

`rebase-gate.py:1987` carries the literal comment `# 222` on the cstyle lane entry, which was
the shared-name count **over the oracle lane before the rename**. It is now **224**. That file
is live and owned by another unit, so I did not touch it; the number is a comment, not a
threshold, but it is now wrong and should be corrected with its reasoning.