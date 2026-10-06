# The last two live-tree writers, converted

2026-10-04.  Both to `staged_mut`.  Both re-run twice.  Live tree byte-identical
afterwards, measured.

Load at both runs: **17.45 / 20.40 on 12 cores**.  Every count below carries that
number, because a starved lane produced 115 rows where a loaded one produced 787 in
another unit today.

---

## 1. `blob-intern-mutate.py` -- the original offender

It mutated `tinybendygrad/uop/ops.bend` IN PLACE and restored from
`.agents/slop/ops-blob-fixed.pristine.bend` in a `finally`.  Its own docstring recorded
putting a dead 6,623-line `ops.bend` over the live 6,306-line one.

### `--diagnose`: the three conditions the old guard conflated, named apart

The old guard compared live against `PRISTINE` and refused when they differed.  On this
tree they DO differ -- so the old guard refuses, while the anchor it was protecting is
present EXACTLY ONCE in the live file:

```
  live      tinybendygrad/uop/ops.bend  369504 bytes  sha256 569dc3af8f719251
  PRISTINE  ops-blob-fixed.pristine.bend  287092 bytes  sha256 c633427ebd522d5a
            file-changed: live != snapshot (the old guard's REFUSING)
  anchor `FIXED` occurrences in LIVE: 1  -> ANCHOR PRESENT x1, so the anchor is NOT stale
  mirror    sha256(jj --ignore-working-copy @)  569dc3af8f719251  -> mirror-stale: no
```

Per-mutation diagnosis for all four: **anchor-stale 0, mirror-stale 0, file-changed 1**
(the substrate, once, for the whole table).  A guard that refuses for a `file-changed`
reason while printing the words of an `anchor-stale` verdict is worse than no guard: the
operator cannot tell which happened.

`--snapshot` and `--restore` are GONE.  `--restore` had to go: it copies a file from
04:58 onto `ops.bend`, and no flag should exist whose whole job is to do that.

### The suite -- 4 mutations, all MOVED, 8.2 s, twice identical

Control: 310 rows, row-set digest `f703511baf9e9491`, two unedited runs of the same
mirror, SAME.  9 of the 310 rows are `blob_*`.

| MUT | rows moved | of which `blob_*` | witness rows |
|---|---|---|---|
| **M1** content -> LENGTH (the original bug) | **4** | 4 | `blob_count_len_diff_content 2->1`, `blob_len_diff_content True->False`, `blob_sweep True->False`, `blob_sweep_count 6->5` |
| **M2** content -> FIRST BYTE ONLY | **3** | 3 | `blob_diff_len True->False`, `blob_sweep True->False`, `blob_sweep_count 6->2` |
| **M3** content -> NEVER EQUAL | **3** | 3 | `blob_count_same 1->2`, `blob_interns True->False`, `blob_sweep True->False` |
| **M4** content -> ALWAYS EQUAL | **5** | 5 | `blob_count_len_diff_content 2->1`, `blob_diff_len T->F`, `blob_len_diff_content T->F`, `blob_sweep T->F`, `blob_sweep_count 6->1` |

Verdicts: `MOVED=4`.  No zeros to classify, so `ZERO_REASONS` was not needed and
`UNREACHABLE+proof` was not reachable.

**THE WITNESS MATRIX IS THE FINDING.**  M1 is the ORIGINAL BUG and it does not move
`blob_content` (97,97,97,97), `blob_shape` (4,), `blob_diff_len` or `rra_arena`.  Four of
the nine `blob_*` rows are not witnesses for the comparator that the file is named
after.  A reader who counted nine `blob_*` rows as nine pieces of coverage has four
unfalsifiable ones.

### THE SUBSTRATE MOVED UNDER THE RUN, AND THE GUARD IS WHAT THAT LOOKS LIKE

At 12:04 `ops.bend` was `569dc3af8f719251`, 369,504 bytes.  At 12:19 a concurrent unit
landed **3,103 bytes** on it and it became `f683c324358ba92b`, 372,607 bytes.  The old
`blob-intern-mutate.py` would have taken that edit and put the 369,504-byte file back
over it in its `finally`, silently, at the end of the next run.

What the converted harness did instead:

```
SUBSTRATE  live=f683c324358ba92b staged=f683c324358ba92b  (310 rows, 9 blob_*)
LIVE AFTER f683c324358ba92b  ->  f683c324358ba92b
live ops.bend: byte-identical (f683c324358ba92b) -- this harness never wrote it
```

and the measurement is UNCHANGED across the move:

| | substrate | control rows | control row-set digest | M1 M2 M3 M4 |
|---|---|---|---|---|
| before the concurrent write | `569dc3af8f719251` | 310 | `f703511baf9e9491` | 4 3 3 5 |
| after  the concurrent write | `f683c324358ba92b` | 310 | `f703511baf9e9491` | 4 3 3 5 |

The row-SET digest is what makes that a statement rather than a coincidence.  A file
digest would have moved on a 3 KB edit that changes no row, and `LiveMoved` would have
fired on a difference that means nothing -- which is exactly how a guard gets switched
off.  Same digest, same verdicts, no alarm.

---

## 2. `memory-mutate.py` -- the `.mut` beside the live file, and no guard at all

It wrote `memory.bend.mut` BESIDE the live file and deleted it, with no digest guard
anywhere.  A file beside a live source is inside its import closure: `*.bend` misses
`memory.bend.mut`, but any `*.bend*` glob or directory iteration finds a full copy of a
source file in `runtime/support/`.  The staged copy is `memory.staged-mem-<pid>`: beside
the file so `import ./../../helpers.bend` still resolves, and with NO extension.

The 70 anchors are spliced in VERBATIM by a script, not retyped
(`assemble-memory.py`; `MUTS == old.MUTS` asserted True).  Everything the conversion
derives -- row set, moved rows, anchor counts, control -- is measured.

Control: 889 rows, row-set digest `74e55a26d3bfd1a5`, two unedited runs, SAME.

### The suite -- 70 mutations

```
70 mutations: MOVED=60  UNREACHABLE+proof=4  PORT-DEFECT=2
              NO-MUTATION-WRITTEN=2  DID-NOT-COMPILE=2
```

Both runs identical for all 70 verdict+count pairs.  Rows moved range 1..142; the
distribution is in `.agents/slop/memory-mutations-staged.txt` and the full console is at
`/tmp/mem.r1.txt`.

### The 10 that did not move, each with what it actually is

| MUT | verdict | rows | evidence, re-derived |
|---|---|---|---|
| M09 | `UNREACHABLE+proof` | 0 | `type Mv is Data` is **labelled**; every read is an **unlabelled positional** pattern. Probe: all four accessors off `Mv{7,11,13,17}` return `7 11 13 17` before AND after. Two spellings of one type. |
| M12 | `UNREACHABLE+proof` | 0 | same for `Pa`: `7` and `11` off `Pa{7,11}`, both before and after |
| M13 | `UNREACHABLE+proof` | 0 | same for `Vmap` |
| M64 | `UNREACHABLE+proof` | 0 | `PT_SUPPORTS_HUGE()` has **0 call sites** (measured: one mention, the def at :197). No def emits value 8, so every row counting calls under a shared tag counts the same. The pair with M69 (retags onto `PT_VALID`, which IS emitted, and moves) is what separates "the tag space is wrong" from "the tag is wrong". |
| M38 | `PORT-DEFECT` | 0 | **separating fixture exists**: `ladder_hit.go(3, 3, 10)` has `c*n = 9 != 10`, measured `0 -> 1` under M38 |
| M62 | `PORT-DEFECT` | 0 | **separating fixture exists**: `pte_first_largest_of(covers_of([9, 7, 4]))` measured `0 -> 1`. A 14-vector sweep gives 4 True / 10 False, so every existing fixture is in the True minority. |
| M10 | `NO-MUTATION-WRITTEN` (prints `PATCH-NOT-APPLY`) | -- | anchor occurs **5x**, and NONE of the 5 is the `type Bump is Data` declaration, which is labelled (`Bump{size: U32, ptr: U32, base: U32, wrap: Bool}`). The 5 are 4 accessor patterns (:488 :491 :494 :497) and `bump_at`'s constructor (:504). |
| M52 | `NO-MUTATION-WRITTEN` (prints `PATCH-NOT-APPLY`) | -- | `bitlen1(TLSF_DEF_LV2_CNT())` occurs 5x: :2124, :2131, :2135, :2150, :2225 |
| M21 | `DID-NOT-COMPILE` | -- | Bend linearity: `expected: off / observed: off (consumed more than once)` |
| M59 | `DID-NOT-COMPILE` | -- | Bend linearity: `expected: uncached / observed: uncached (consumed more than once)` |

### M10: THE OLD TABLE'S NUMBER DESCRIBED AN EDIT THE ANCHOR DOES NOT PERFORM

The old harness did `src.replace(find, repl)` with **no count**, so it rewrote all 5
sites and reported the result under a description naming one.  Measured, rewriting all
five swaps TWO POSITIONAL BINDERS:

```
probe_bump_base   13 -> 11
probe_bump_ptr    11 -> 13
```

and moves **13 rows**.  So M10's published number was a 13-row move for an edit that is
not "Bump: the field order size,ptr,base,wrap -> size,base,ptr,wrap".  It is "swap the
binders in five positional patterns".  The refusal is the fix; the table needs re-aiming
at the labelled declaration or at one accessor pattern.

### TWO TAUTOLOGICAL ROWS, FOUND ON THE WAY

```
memory.bend:1310    srow("mmio_init_fields", "mv addr nbytes fmt")
memory.bend:1311    srow("bump_init_fields", "size ptr base wrap")
```

Both assert a **string literal against nothing**.  No mutation of `type Mv is Data` or
`type Bump is Data` can move them, which is why M09/M12/M13 moved 0 rows -- and it is
the same shape as `device.bend`'s `sig=0 4 5`: internally consistent, unfalsifiable.
Reported, not fixed: `memory.bend` is a live unit's read-only file.

### A WALL IN `memory.bend` THAT IS FALSE, REPORTED NOT FIXED

`memory.bend:1728` asserts that `pte_ladder` and `pte_first_largest` "are THEOREMS for
every `va_shifts` CPython accepts", and offers three rows as the checkable form.
Measured: `pte_first_largest_of(covers_of([9, 7, 4]))` is **0**, i.e. the port's own
`first_of(covers)` is not `max(covers)` there, so M62's two spellings are
distinguishable and the claim does not hold.  `pte_first_largest_of` IS called
(:1593 -> :1616), so it is reachable rather than dead -- the shape that matters here is
the `schedule/indexing.bend` one, three defs written, commented, never called.

---

## The guard had to be fixed before it could mean anything

`staged_mut.__enter__` asserted `sha256(jj @) == sha256(live)` and the assertion was
**VACUOUS**: `jj file show -r @` SNAPSHOTS the working copy, so it commits the edit it
is about to be compared against and the two digests are equal by construction.

```
live bytes                                    51
sha256(jj file show -r @)          SNAPSHOTS -> 5d2a13b8962e92be
sha256(jj --ignore-working-copy ...)          fa4bc8abe6f09703
```

`--ignore-working-copy` FIRST, before the subcommand, makes it a measurement.
`staged-guard-proof.py` drives all three outcomes to their real branch on a fixture it
creates, owns and deletes -- **8/8 claims fire**, and it proves the *old* spelling cannot
raise by reading the snapshotting spelling second.  Order is the measurement: the first
attempt read the snapshotting call first and both halves agreed for the wrong reason.

## Two of my own bugs, both caught by the project's rules

**`S.zero_verdicts()[:3]`** put `PATCH-NOT-APPLY` in the cell meant for
`INVISIBLE-to-reader`: the query returns `UNREACHABLE+proof, PORT-DEFECT,
PATCH-NOT-APPLY, INVISIBLE-to-reader, NO-MUTATION-WRITTEN`.  A positional read of an
external vocabulary is a transcription wearing a query's clothes.  `zero_verdict_map()`
now looks up BY NAME and refuses a key that does not match exactly one.

**`--report FILE` put FILE in the selector set** -- an option's ARGUMENT does not start
with `--` -- so the harness printed `0 mutations:` and exited 0.  That is the exact
"indistinguishable from not started" trap, hit by my own conversion on its first run.
`0` is now a `SystemExit` with no table.