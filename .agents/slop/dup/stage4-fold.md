# STAGE 4 — `uop/fold.bend`'s 93 printed-but-unread rows.  CLASSIFIED, NOT FIXED.

**Do-not-touch file.  Not edited.  `file:line` and the classification are below.**

## 1. THE POPULATION, MEASURED

```
lane      tinybendygrad_uop_fold.bend.port.txt
  physical lines                                    334
  lines the shipped reader `row()` ACCEPTS          241
  lines the shipped reader REFUSES                   93   <-- the class
  continuation lines (inside a bracketed value)       0
  lines with NO writer boundary                      93   <-- the same 93, under `eq-census2`
  accepted lines that contain no `=` at all           0
  241 + 93 = 334                                     ✓ every line accounted for
```

Line range **L201 – L310** of the port's stdout.  Two families, by prefix: **55 `mm_*`**
(`mm_add_zero`, `mm_shl_over63`, `mm_div_2p63_max`) and **38 `bl_*`** (`bl_bl_0`, `bl_mk_m1_2p32`,
`bl_dt_uint64`).  **Every one of the 93 contains exactly ONE space** — the space-count histogram
is `{1: 93}` and nothing else.

## 2. THE CLASSIFICATION: **A FORMAT THE READER CANNOT PARSE.**  Not a naming class, not an `=`,
not a continuation, not a duplicate.

`rebase-gate.py:412-415` defines the third row shape and the gap that goes with it:

```
GAP = "  "   # F3's gap is SPACES. A TAB is a table cell and a table's first column is not a
             # row name: dtype_tables.py emits 14,774 TSV lines and must keep reading as ZERO rows
```

and `rebase-gate.py:448-455` is the whole F3 rule:

```python
head, sep, tail = line.partition(GAP)     # GAP is TWO spaces
name = head.strip()
if not sep or len(head.split()) != 1 or not name or not tail.strip():
    return None
```

`fold.bend` prints **one** space.  So `row()` returns `None` for all 93, and the brief's question —
*is this the reader's fault?* — has a MEASURED answer on both sides:

| input | `row()` |
|---|---|
| `mm_add_zero 0:0` (one space, what the lane prints) | `None` |
| `mm_add_zero  0:0` (two spaces) | `('mm_add_zero', '0:0', '0:0')` |
| `mm_add_zero=0:0` (F1) | `('mm_add_zero', '0:0', '0:0')` |

**The row is well-formed and the separator width is the whole difference.**  The producer emits a
valid row in a spelling the reader does not have a case for.  The brief's warning that
`rebase-gate.py:row()` "cannot fold" is about CONTINUATION lines and does not apply here: this lane
reports **0** continuations and is bracket-balanced end to end (`eq-census2.measure()`'s
`end-unbalanced` is empty), so nothing needs folding.

## 3. THE PRODUCER, AT `file:line`

`tinybendygrad/uop/fold.bend:4070-4077` — two printers, and both use one space:

```bend
4070: def mm_row(nm: String, got: String) -> IO(Unit):
4071:   IO.print(String.concat(["mm_", nm, " ", got]))
...
4076: def bl_row(nm: String, got: String) -> IO(Unit):
4077:   IO.print(String.concat(["bl_", nm, " ", got]))
```

Both comments say why the printers exist and neither mentions the separator:
`:4068-4069` — *"`_min_max`'s row is a STRING ANSWER and not a Bool, so `row` cannot print it and
this is the second printer"*; `:4073-4075` — *"`bit_length`'s rows print under `bl_` rather than
`mm_`, because the oracle's two tables are two KINDS of answer"*.

**`fold.bend:4083` says the generator:** *".agents/slop/mm-lift-gate.py GENERATES BOTH THE …"*.
So the producer of the spelling is the oracle's generator, and the port's copy is that generator's
output — the same symmetry as `llvmir` and `tc_ptx` in Stage 2.  **A correct fix therefore has to
move both**, and `fold.bend` is do-not-touch.

## 4. THE LARGER FACT UNDERNEATH IT, which the 93 was hiding

**These 93 rows are not merely unreadable — they are UNGATED.**  The fold oracle
(`.agents/slop/mm-lift-gate.py`, wired at `rebase-gate.py:1791`) prints **131 rows and not one of
them is an `mm_*` or a `bl_*` row**:

```
$ grep -c '^mm_\|^bl_' .agents/slop/dup/lanes/tinybendygrad_uop_fold.bend [DANGLING 2026-10-05: this path DOES NOT EXIST. It was pruned, or moved, or never committed -- do not assume which. `checks/repro-paths.py` lists all of them.].oracle0.txt
0
```

So 93 measurements are printed by the port, addressed by no name, and corroborated by no CPython
call — a double loss, and the census's `phys` column never showed it because a row with no writer
boundary is not a row at all.  **Any coverage claim that reads "241 rows" is reading 241.**

## 5. WHAT THE FIX IS, AND WHO OWNS IT

Two candidates, and they are not equivalent:

* **producer-side, one character per printer** — `fold.bend:4071` and `:4077`, `" "` → `"  "`,
  and the same in `mm-lift-gate.py`'s generator.  It makes 93 measurements addressable, and
  **ungates nothing**: the oracle still prints no `mm_*`/`bl_*` row, so the 93 become addressable
  PORT rows with no CPython counterpart, which `rebase-gate.py`'s GUARD 4 will report as a
  shrinking shared set rather than as coverage.
* **reader-side** — teach `row()` a one-space F3.  `rebase-gate.py` is do-not-touch and **156
  forked row readers exist**, one of which already caused a two-round contradiction between two
  gates.  A second spelling inside the shipped reader multiplies that surface.
* **the one that actually closes the gap** is on the oracle: `mm-lift-gate.py` emitting the
  `mm_*`/`bl_*` families so the 93 have a CPython answer, plus the two-space separator.  That is
  a real unit of work and it belongs to whoever owns `uop/fold.bend`.

## 6. REPORTED, NOT CHOSEN.  The three findings, one line each

1. **93 printed measurements, 0 addressable, 0 corroborated** — `fold.bend:4071` and `:4077` print
   one space; `rebase-gate.py:412` `GAP` is two.  *A format the reader cannot parse.*
2. **`lf_sub_int32_-3_4 lo`, printed twice, `fold.bend` L84/L87** — the lane's ONE duplicate, and
   it is a **separate defect of a different species**: the producer writes `" lo="` with a SPACE
   before the `=` while every other row in the file writes `"="`, so on an F1 lane the shipped
   reader puts ` lo` into the NAME.  **The name the earlier unit recorded, `lf_sub_int32_-3_4`, does
   not exist** — the real key is `lf_sub_int32_-3_4 lo`.  That is the brief's own rule ("prove the
   name field is what you think it is") catching a recorded finding: the *values* are also equal,
   not different, so "printed TWICE WITH DIFFERENT VALUES" is wrong on this tree in both halves.
3. **The oracle prints 0 of the 93's rows** (`mm-lift-gate.py`, wired `rebase-gate.py:1791`), so
   the separator rename alone would turn 93 unaddressable rows into 93 uncompared ones.