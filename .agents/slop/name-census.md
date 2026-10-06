# DELIVERABLE 4 — the cross-lane census, with every denominator

`.agents/slop/name-census.py` (fetch / `--refetch-zero` / report / `--names`).
Raw output: `.agents/slop/name-census-report.txt`. Lane texts: `name-census-lanes/`.
Lane roster is `rebase-gate.py`'s own `BASE_ORACLES`, **imported read-only**: **39 wired
ports, 78 lane texts.**

## The answer

```
38057 lines, 23179 read by rows(), 22672 distinct names
LANE SHAPE: 18443 F1 rows   (79.6%) -- the boundary IS `=`
             4736 F2 rows    (20.4%) -- the boundary is ` = `
                0 F3 rows            -- no `=` at all
UNREADABLE LINES  : 14878/38057
NAMES CONTAINING `=` : 361/4736 = 7.62% of the F2 rows that can carry one
                       361/22672 = 1.59% of all names
READER-DEPENDENT NAMES : 361/4736 = 7.62%; of those 59 are merely MISNAMED and
                       302 share a key with another row and COST a measurement
UNADDRESSABLE ROWS : 507/23179 = 2.19%, split 302 reshape + 205 repeated-name, residual 0
```

## THE DENOMINATOR IS THE FINDING. 79.6% of this tree cannot have the defect.

`row()` (`rebase-gate.py:437`) cuts a row line at its **first `=`**. So whether a name *can*
contain `=` is decided by the lane's own boundary, and there are three shapes:

- **F1, `name=value` (18,443 rows, 79.6%).** The boundary IS `=`, so the writer has no way to
  express a `=` in a name. **Structurally immune.** A name with a space cannot survive here
  either. This is 79.6% of the tree and it is a *reportable finding, not a pass*: it means the
  headline "1.59% of all names" is mostly measuring the wrong denominator.
- **F2, `NAME = [v]` (4,736 rows, 20.4%).** The boundary is ` = `, so a name **may** contain
  `=` and the two readers can disagree. **This is the only population in which the class can
  exist, and 7.62% of it does.**
- **F3, no `=` at all (0 rows).** An explained zero: 14,864 cached lines contain no `=`, and
  `rows()` reads **none** of them — they are `dtype_tables.py`'s 14,766 TSV lines, GUARD 2's
  "compared nothing" BY DESIGN. Verified by counting, not inferred.

## Where the class actually is: THREE ports, and llvmir is four times cstyle's

| lane | port | READ | F2 | NAMES | `=` | DIFFER | LOST |
|---|---|---|---|---|---|---|---|
| port | `renderer/llvmir.bend` | 471 | 471 | 323 | **157** | 157 | **148** |
| `cpython:llvmir-oracle` | `renderer/llvmir.bend` | 471 | 471 | 323 | **157** | 157 | **148** |
| `cpython:render-gate-oracle` | `uop/render.bend` | 124 | 75 | 85 | **31** | 31 | 39 |
| port | `renderer/nir_llvmir.bend` | 205 | 205 | 201 | **8** | 8 | 4 |
| `cpython:nl-oracle` | `renderer/nir_llvmir.bend` | 205 | 205 | 201 | **8** | 8 | 4 |
| — | **`renderer/cstyle.bend` (fixed here)** | 227 | 227 | 227 | **0** | 0 | 0 |

`cstyle.bend`'s eight were **3.5% of its 227 rows; llvmir's 157 are 33% of its 471**, and the
collapse is coarser:

```
KEY 'br2 load vol'            <- 48 rows   (br2 load vol=False f32 [0] .. [47])
KEY 'br5 stack n'             <- 10 rows   (br5 stack n=1 f32 [0] .. n=4 u8 [0])
KEY 'br3 load vol'            <-  6 rows
KEY 'is_volatile AFTER vol'   <-  2 rows   (vol=False, vol=True)   <- cstyle's exact shape
KEY 'is_volatile BUFFER vol'  <-  2 rows
```

`is_volatile AFTER vol=False` / `vol=True` is `kern CUDA  lb=1` / `lb=4`. The same defect,
the same two-measurements-per-key collapse, in a lane nobody has renamed.

## The inverse, which is why a rename and not a smarter split

A detector that matches `=` to find the name/value boundary **mis-splits a name containing
one**. So `=`, `<=`, `==`, `<`, `>` and `:` in a name are not merely ugly — they make the
name reader-dependent in whichever direction the reader cuts. `uop/validate.bend`'s
`cmp_i<=5` is this class, already paid once (310 printed rows read as 280).

Counted by reading names, **not** by pattern: I did **not** run a `re.search(r'[=<>]', name)`
census, because a pattern census cannot tell a delimiter that is part of a name from one that
is not, and the whole defect is that the two are indistinguishable from the bytes. The
census instead asks the only question that is decidable: **do two readers name this row the
same?** 361 do not.

## THE LOAD, because a disagreement count is not a coverage statement

| | |
|---|---|
| lane texts | 78 of 78 fetched, over 39 wired ports |
| lines cached | 38,057 |
| rows read | 23,179 (0.61 of lines; 14,878 unread, see F3) |
| lanes reading **zero** rows | **3** — `dtype.bend` port, `dtype.bend`'s `dtype_tables`, `jit-oracle` |

A starved lane is plausible and I refused to count them as zeros:

- **`dtype_tables.py`** — 14,766 TSV lines, GUARD 2's documented dead lane, **by design**.
- **`tinybendygrad/dtype.bend`** port — `./bin/bend --check-only` first line is
  `SOME PROOFS FAIL` naming `Dt.bf16` and 13 siblings: `dtype.bend`'s 14 permanently unfilled
  laws, exactly the trap `agent-core.md` records ("never gate on the exit status"). It is also
  under a live unit during this run, so I cannot separate the two causes and say so.
- **`jit-oracle.py`** — a real traceback at `jit-oracle.py:44`, i.e. **the oracle is broken**,
  not starved. **Reported, not fixed** (not this unit's file).

**MY OWN HARNESS STARVED 25 OF 39 PORT LANES FIRST, and that is worth recording.** The
parallel `--fetch` ran 8 `bend` compiles at once; `./bin/bend tinybendygrad/renderer/cstyle.bend`
alone prints **227** rows and the same command in the pool printed **0** with an empty
`--check-only` line. So `--refetch-zero` re-runs every empty lane **alone**, with
`rebase-gate.py`'s own `BEND_ROW_TRIES`/`BEND_ROW_BACKOFF`, and records `row_tries` and
`row_secs` per lane. All 25 came back with rows on try 1 (`cstyle.bend`: 227 names, 2.0 s).
**A starved lane is my harness until proven otherwise**, and this is the second time today
that number has been the harness's rather than the tree's.

## FOUR DEFECTS THIS CENSUS FOUND IN ITSELF — all of them produced a clean or a wrong number

Recorded because they are the exact shapes the census exists to catch, and because three of
them made it report `0`:

1. **`eq` was a tautological zero.** It counted `=` in `rows_shipped(text)`'s keys — and
   `row()` splits at `=`, so a key can never contain one. It printed `0 names containing `=``
   over all 78 texts **including cstyle's eight**. A measure that cannot fail is not a
   measurement. The count now comes from a name the census cuts itself.
2. **`reshape`/`dupe` split said `0` on a lane with 148 unaddressable rows.** The condition
   counted *distinct keys a name produced*; the loss is *many rows on one key*, which is 1
   whenever the collapse is total — exactly when the loss is largest.
3. **An unexplained residual of 82, then 146, then 349 rows.** Three separate under-counts:
   F1 collisions were unclassified, then same-shape-name collisions were unclassified, then
   the split counted KEYS where the quantity is ROWS. `lost` itself was right the whole time.
   The split now carries `residual 0` and asserts it in the output, because **an unexplained
   number in a coverage census is worse than a wrong one — nobody can check it.**
4. **The F3 class did not exist and the `=` count for `uop/render.bend` was wrong.** That
   lane's oracle is a *mixed* F1/F2 text; my second reader cut at `" = "` and found ` = ` in
   the middle of a value, so it reported `pyrend buffer=[c1` as a name containing `=` — 31 of
   them — on a lane where the shipped reader never sees that string. **A lane-shape-blind count
   is the brief's own rule aimed at me.**

Also: the first `--fetch` wrote its lane texts with `_secs()` stubbed to a constant `0.0`.
Harmless (the figure is cosmetic) but it is a lie in a column, and it is gone.

## Not fixed, not mine

- `renderer/llvmir.bend` — 157 reader-dependent names, **48 rows on one key**. Needs the same
  rename. `renderer/nir_llvmir.bend` — 8, all `sd cpullvm ... osx=False`/`True`.
- `uop/render.bend` — 31 `=`-names on the oracle side; 30 rows collapse onto the single F1 key
  `ast`.
- `rebase-gate.py:1987` carries `# 222` on the cstyle lane entry, the pre-rename shared-name
  count over the oracle lane. It is **224** now. Live file, another unit's.
- **205 unaddressable rows from lanes printing one row name twice** — `usb.bend` 75,
  `uop/render.bend` 43, `ops_nv.bend` 38, `hcq2` 2, `tc_ptx` 1. **No `=` involved.** A separate,
  older defect that the `=` census would have hidden inside its own number, which is why the
  split is reported at all.