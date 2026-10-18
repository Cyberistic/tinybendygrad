# `lin` — corpus divergence, STATIC diagnosis

**No compilation, no `bend`, no `graphcmp`, no `gates/`, no `checks/*`, no pytest/mypy/ruff.**
Every number below was produced by `.venv/bin/python .agents/slop/dg-lin/analyse.py`, which reads
two TEXT artifacts and walks the eight-field wire format with `graphcmp.py`'s own `unchunks`
(`graphcmp.py:360`). `.bend` files were read as text. No source file was edited.

| | |
|---|---|
| HEAD | `4b42c0ccf7e53bb140680a19bbcdaddad2f02bf4` — "arenaparam: the 62 self-parenting nodes are threaded, and the corpus is 31/34 BE…" |
| Diagnosis written | 2026-10-18T17:33Z |
| Artifacts analysed | `runs/graphcmp/D/D2-canon-py-lin.txt` sha256 `78104db98a1bccba…`, `D2-canon-bend-lin.txt` sha256 `5fc42e0c8978c56e…`, written 2026-10-18T17:29:14Z / 17:29:17Z |
| Sources analysed | `.agents/slop/graphcmp.py` `3a67ce1b210492d2…` · `.agents/slop/graphcmp.bend` `24295c30ba378ddb…` · `tinybendygrad/codegen/late/linearizer.bend` `9f1fc050fbdb2448…` · `tinygrad/codegen/late/linearizer.py` `9c1d7ae56a0381bd…` |
| Verdict | **`DISAGREE`**, `runs/graphcmp/D/D1-graph-lin.txt:80` |

**THE TREE IS A MOVING TARGET AND WAS MOVING WHILE THIS WAS WRITTEN.** A corpus run was in
flight: `D0-run-summary.txt` was rewritten at 17:26:49Z and `D0-coverage-census.txt` was observed
at 17:31:13Z and then found truncated to 0 bytes. The two canon files analysed here were
**rewritten by that run** after the brief's stated run of 05:51:48Z — and they hash identically
across two consecutive reads, and `lin` reads `DISAGREE` in both the old and the new
`D0-run-summary.txt` (`graphs-agree=31 graphs-disagree=2` both times). The conclusion is stable
across both runs; the hashes above are what it was measured against.

---

## 1. The quantified divergence

| | nodes |
|---|---|
| CPython (`D2-canon-py-lin.txt`) | **50** |
| port (`D2-canon-bend-lin.txt`) | **49** |
| delta | **1** |

**CORRECTION TO THE BRIEF.** The brief read `9,50c9,49` as "CPython has ~42 more nodes than the
port". It does not. 50 vs 49 is a delta of **one node**. The hunk is a *whole-block positional
replace* because `diff` is unaligned and one row is inserted at position 9 — every row after it
shifts by one and `diff` has no way to say so. **47 of 49 rows are byte-identical after dropping
the one CPython-only node and renumbering.** 41 of the 42 rows in the hunk are pure renumbering.

### Op census (computed here, not quoted)

Over 50 py nodes / 49 port nodes, 12 distinct ops:

    ADD 7/7  AFTER 1/0  CAST 6/6  CONST 9/9  END 2/2  INDEX 7/7
    LOAD 6/6  MUL 5/5  PARAM 3/3  RANGE 2/2  SINK 1/1  STORE 1/1

**1 of 12 ops differs in count: `AFTER`, 1 on CPython and 0 on the port.** This reproduces
`runs/graphcmp/D/D1-graph-lin.txt:5` (`AFTER 1/0`) exactly, from an independent instrument.

### The alignment test

Drop CPython arena row 8 and renumber every CPython index above it (the row's own `ix` **and**
every `src` reference, which are arena indices and move together). Demand byte equality on
everything else. **47 of 49 rows match. Exactly two do not:**

| row | py | port | differing field |
|---|---|---|---|
| 8 | `RANGE i32 rg(i0,XWEAK,n(i2)) src=n(i8)` — **one** src | `RANGE i32 rg(i0,XWEAK,n(i2)) src=n(i7,i5)` — **two** srcs | `src` |
| 48 | `SINK void R i0 tag=N` | `SINK void R i0 tag=i1` | `tag` |

The run's own structural pass names the same two, unprompted, at `D1-graph-lin.txt:25-30`:

    #   SINK  py#50 vs bend#49  (same op, unpaired)
    #     tag   py=N bend=i1
    #   RANGE py#10 vs bend#9   (same op, unpaired)
    #     src  py=['617700cb'] bend=['8c6673f6', '7192a3c1']

**So `lin` carries exactly TWO independent semantic divergences, not one**, and row 8's
difference is the *shape* of the single missing node rather than a third divergence.

---

## 2. The FIRST semantic difference

**Arena row 8 of both files. Node id `i9` on both sides** (the AFTER consumes `i9`, so the two
sides' ids coincide exactly once and then run parallel). It is also the first row that differs
with the index field excluded, so it is the first *structural* difference, not the first
renumbering.

**CPython** — `D2-canon-py-lin.txt:9` and `:10`:

    2:i9  5:AFTER 3:i32 2:() 2:i0 1:N 1:N  8:n(i7,i5)
    3:i10 5:RANGE 3:i32 2:() 2:i0 1:N 18:rg(i0,XWEAK,n(i2))  5:n(i9)

**the port** — `D2-canon-bend-lin.txt:9`:

    2:i9  5:RANGE 3:i32 2:() 2:i0 1:N 18:rg(i0,XWEAK,n(i2))  8:n(i7,i5)

Same op (`RANGE`), same dtype (`i32`), same `arg` (`rg(i0,XWEAK,n(i2))`), same depth — and
**different `src` arity**: CPython's RANGE has ONE src, the AFTER, which carries the two
children `(i7, i5)` = `(bound_const, the_range_being_split)`. The port's RANGE carries those
**two children directly**.

**One sentence:** *the port does not wrap the split range's bound in an `AFTER`; it hangs the
ordering dependency off the RANGE as a second source.*

Everything after row 8 is renumbering plus one downstream consequence: the three `ADD`s
`py#30/#33/#42` read `src=['10','7']` where the port reads `src=['9','7']`, which is the same
edge seen through the un-wrapped RANGE. That is not a second cause.

---

## 3. Both `g_lin` definitions

**CPython**, `.agents/slop/graphcmp.py:1211-1229` — it is a REAL graph, not a transcription:

```python
def g_lin():
  """`full_rewrite_to_sink` of the scheduled `(4,3)@(3,5)` matmul -- MEASURED at 46 nodes ..."""
  from tinygrad import Tensor
  from tinygrad.codegen import full_rewrite_to_sink
  out = Tensor.empty(4, 5).realize()
  out.assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5))
  return full_rewrite_to_sink(_kernels(out)[0], _renderer(), optimize=True)
```

**the port**, `.agents/slop/graphcmp.bend:977-1038` — 49 hand-written arena nodes. The two
lines that matter:

```bend
# :993   the split range -- TWO srcs, no AFTER
+rb = O.UOp.new(O.Found.ar(off), O.OpsRANGE{}, [O.Found.i(c5i), O.Found.i(ra)], O.ARange{[2], O.AXIS_WEAK{}}, O.TNone{})
```

```bend
# :1036  the SINK -- a TInt{1} tag no other SINK in this file carries
O.UOp.new(O.Found.ar(e0), O.OpsSINK{}, [O.Found.i(e0)],
  O.AKernel{O.KernelInfo{"r_4_5_3", ...}}, O.TInt{1})
```

**So the port does not skip work and does not use a different lowering.** It is the *same op
with a different shape*: `RANGE` is built with the two children as direct sources instead of one
source that is an `AFTER` over them. The port **has** the constructor it needs —
`tinybendygrad/uop/ops.bend:2818-2819`:

```bend
def UOp.after(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.after.go(srcs, ar, self, UOp.new(ar, OpsAFTER{}, List.append(&2, U32, [self], srcs), ANone{}, TNone{}))
```

— and it **uses it elsewhere in this very corpus**: `graphcmp.bend:1056, 1063, 1070` (`g_loop`).
So this is not an unimplemented op.

### UNIMPLEMENTED markers — none

There is **no** `not ported`, `PORT REFUSES`, `WALL`, `PROMOTION`, or `not implemented` marker
anywhere in `graphcmp.bend`'s `g_lin` (`:977-1038`). The corpus *has* a deliberate-divergence
idiom and `g_lin` does not use it: `graphcmp.bend:778` names `sym` as "disagrees on purpose (see
`g_sym`)", and `graphcmp.bend:728` marks a value "DELIBERATELY 7 and means nothing". **`lin`'s
row 8 carries no such marker.**

---

## 4. Where the shape comes from — and it is a RE-VENDOR REGRESSION

CPython produces this `AFTER` in exactly one place. `tinygrad/codegen/late/linearizer.py:83-86`:

```python
pm_add_control_flow = PatternMatcher([
  # the ordering dep goes on the bound wrapped in AFTER, so a RANGE always has exactly one src
  (UPat(Ops.RANGE, name="x"), lambda ctx,x: x.replace(src=(x.src[0].after(y),)) if (y:=ctx.edges.get(x)) is not None else None),
])
```

`grep -rn 'src\[0\]\.after' tinygrad/` returns **8 sites**; six of them are AFTER-on-AFTER
collapsing in `runtime/support/hcq2.py:422,431,522,558` and `codegen/__init__.py:253`, and one is
`UOp.set` (`uop/ops.py:1211`, `INDEX.after(STORE.end(...))`). **`linearizer.py:85` is the only
one of the eight that wraps a `RANGE`'s src**, and `grep -rn 'Ops.RANGE'` over
`tinygrad/schedule/*.py` and `tinygrad/codegen/late/linearizer.py` finds no other
RANGE-with-AFTER construction. `full_rewrite_to_sink` reaches it through
`tinygrad/codegen/__init__.py:376`, `graph_rewrite(sink, pm_add_control_flow, ctx=CFGContext(sink),
name="add control flow", bottom_up=True)` (the port's own table at `graphcmp.bend:90` cites the
same line), so the AFTER is a **mandatory consequence of the real pass** — not an artefact of the
corpus.

**The port's implementation of that rule is wrong, and its comment states the wrong rule.**

`tinybendygrad/codegen/late/linearizer.bend:1587-1589` (the port's own header for the rule):

> `# pm_add_control_flow -- linearizer.py:83-85. ONE rule, ONE op, and the whole`
> `# rewrite is \`x.src + (edges[x],)\`, so the table is two rows and the answer is`
> `# either the new node's src list or \`-\`.`

`tinybendygrad/codegen/late/linearizer.bend:1617-1620` (the code):

```bend
def cfg_rewrite.new(+ar: O.Arena, ed: RaTb, +x: U32) -> Cg:
  cfg_rewrite.put(O.UOp.new(ar, O.OpsRANGE{},
                            List.append(&2, U32, O.Arena.srcs(ar, x), [tb_get(ed, x)]),
                            O.Arena.arg(ar, x), O.Arena.tag(ar, x)))
```

`List.append(srcs, [edge])` — **append, not wrap**. There is no `O.OpsAFTER{}` anywhere in
`linearizer.bend`: `grep -n after tinybendygrad/codegen/late/linearizer.bend` returns prose
only (lines 6, 427, 676, 719, 846, 1320, 1558), never a constructor call.

**WHY IT IS WRONG — AND WHEN IT STOPPED BEING WRONG.** `git show a79832b01:tinygrad/codegen/late/linearizer.py`
— the upstream commit that introduced `pm_add_control_flow` (PR #12948) — reads:

```python
(UPat(Ops.RANGE, name="x"), lambda ctx,x: x.replace(src=x.src+(y,)) if (y:=ctx.edges.get(x)) is not None else None),
```

**That is the port's code, character for character in shape.** The port implemented the OLD
upstream spelling and it was correct at the time. Upstream then changed it to
`x.src[0].after(y)`, and this tree picked that change up in the re-vendor:

| commit | date | what |
|---|---|---|
| `a79832b01` | PR #12948 | `src=x.src+(y,)` — the spelling the port implements |
| `86c4f1343` | **2026-10-17T04:14:48Z** | "RE-VENDOR tinygrad/ to upstream 002630241 (2026-10-16)" — brings in `src=(x.src[0].after(y),)` |

Everything downstream of the re-vendor is **older than the re-vendor**:

| file | mtime | carries the stale shape? |
|---|---|---|
| `tinygrad/codegen/late/linearizer.py` (re-vendored) | 2026-10-17T04:12:10Z | no — it is the ground truth |
| `tinybendygrad/codegen/late/linearizer.bend` (`cfg_rewrite`) | 2026-10-18T00:50:12Z | **yes** — still `x.src + (edge,)` |
| `gates/linearizer_census-oracle.py` (generates the CPython rows) | 2026-10-14T12:18:03Z | — predates the re-vendor |
| `oracles/tinybendygrad_codegen_late.bend.rows:59` | 2026-10-02T12:20:50Z | **yes** — `cfg_hits=- 1->[CAST,END,END]` |
| `oracles/late-oracle.rows:61` | 2026-10-05T17:58:19Z | **yes** — same row |
| `gates/linearizer_census-pins.rows` | 2026-10-14 | declares **2** divergences of 71 rows; `cfg_hits` is **not** one, so it must agree |

**The corpus fixture carries the stale shape too.** `.agents/slop/graphcmp.bend:985-992`:

> `# A SPLIT RANGE HAS TWO SRCS AND AN INT AXIS ID. MEASURED on the py side's own row 8:`
> `# \`RANGE i32 () depth=i0 rg(i0,XWEAK,n(i2)) src=n(i6,i4)\` -- so \`src\` is`
> `# \`(bound_const, the_range_being_split)\` …`

**That "MEASURED on the py side's own row 8" is no longer what the py side emits.** Today's py
row 8 is the `AFTER`; the RANGE is row 10 and reads `src=n(i9)`, one src. The indices in the
quote (`i6,i4`) do not occur anywhere in today's py file. This is a transcription of the
**pre-re-vendor** row, written into a corpus that names its own per-graph node counts
`graphcmp.bend:963` and `graphcmp.py:1212` as **"46 nodes"** where the run measures **50**.

`graphcmp.bend:805` already names this exact failure mode in this very file:
*"The per-graph node counts in the comments below are the same kind of stale census."*

---

## 5. The second, independent divergence — the SINK tag

`graphcmp.bend:1038` writes the `lin` SINK with tag `O.TInt{1}`; CPython's `lin` SINK tag is
`None` (`D1-graph-lin.txt:78` region; `D2-canon-py-lin.txt:50` reads `1:N` in the tag column).

Evidence it is not deliberate:
- `grep -n TInt .agents/slop/graphcmp.bend` returns **three** hits: the definition match arm
  (`:504`) and **this one use** (`:1038`). Every other SINK in the file writes `O.TNone{}` —
  `:763` (`g_sink`), `:882`, `:1073`, `:1107`.
- No comment at `:1031-1036` mentions the tag; that comment is entirely about the `arg`.
- `g_sink`'s two sides are byte-identical (`D2-canon-py-sink.txt` / `D2-canon-bend-sink.txt`,
  both ending `4:SINK 4:void 1:R 2:i0 1:N 18:kI(stest,n(),N,i0) 5:n(i1)`), so the tag column
  and its reader are sound — this is a value the fixture chose, not a misaligned column.
- The port's own `Tag` docstring (`tinybendygrad/uop/ops.bend:885-899`) records that `TInt` and
  `TBool` are interchangeable in an eq key and that `tag=None` and `tag=0` are distinct nodes,
  so `TInt{1}` is a real, hashable, non-`None` tag and will not fold away.

This one is independent of the `AFTER`: fixing the `AFTER` does not move it, and vice versa.
**`lin` needs two fixes, not one**, which is why the run's own report is two `MISMATCH`/`RUNG 3.5`
entries and not one.

---

## 6. Classification

### Primary: **`MISSING_CASE`** (re-vendor pin drift)

Evidence, strongest first:

1. **The port's implementation of the exact upstream rule that mints this node appends the edge
   instead of wrapping the bound in an `AFTER`** — `linearizer.bend:1617-1620` against
   `linearizer.py:85`. This is a missing case in a *rule*, not a disagreement about intent.
2. **The port's own header comment for that rule states the pre-re-vendor spelling as if it were
   upstream's** (`linearizer.bend:1587-1589`). A deliberate divergence would say so; this says
   "this is what `linearizer.py:83-85` does", and it is false.
3. **The port implemented the spelling that upstream ACTUALLY HAD** at the introduction commit
   (`git show a79832b01:…linearizer.py:70`) — so this is drift, not a design choice made against
   a known alternative.
4. **Every artefact carrying the stale shape predates the re-vendor `86c4f1343` (2026-10-17T04:14Z)**
   and the port's implementation, its oracle generator and both oracle `.rows` dumps are all
   older than the ground truth they are measured against.
5. **No unimplemented marker and no deliberate-divergence marker** anywhere on this path.
6. **The corpus's own expectation table pins `lin` to `AGREE` and records it as fixed** —
   `checks/differ.py:135`, under a comment at `:128-134` saying *"`lin` AGREES NOW, AND IT LEFT
   THE DISAGREEMENT SET ENTIRELY … It disagreed on ONE node of 46 -- its SINK's
   `applied_opts`"*. That previous disagreement is genuinely closed: the `kI(...)` arg column is
   **byte-identical** on both sides in my comparison. **So `lin` is back to DISAGREE after having
   been declared AGREE, and the graph grew 46 → 50 nodes under the re-vendor.** That is a
   regression against a declared expectation, not an accepted limitation.
7. `checks/differ.py`'s `WANT` table (`checks/differ.py:125-205`) holds **34 graph entries and
   every one of the 34 is `AGREE`** — zero non-`AGREE` entries, verified by extraction over that
   line range — while the run reads 3 graphs not-AGREE (`lin` DISAGREE, `gate` DISAGREE, `loop`
   REFUSES, `:135`, `:141`, `:142`). The summary's `expect-moved=3` is that arithmetic: **nothing
   in this tree expects `lin` to disagree.**

### Secondary (the SINK tag): **`MISSING_CASE`** as well, but *weaker* evidence

It is a one-off value in a fixture with no marker. **I did not establish provenance for
`TInt{1}`** — I did not find a comment claiming it, and I did not find one denying it. It is
reported as a separate, unresolved divergence rather than folded into the primary finding.

### Explicitly ruled out

- **Not `DELIBERATE_DIVERGENCE`.** No marker on the path; the corpus has a marker idiom
  (`graphcmp.bend:728`, `:778`) that this row does not use; and the port's rule header *claims*
  fidelity to `linearizer.py:83-85`.
- **Not `UNKNOWN`.** The first divergence is located, quantified, and its producing rule
  identified in both trees by path and line.

---

## 7. What a fix and its verification would require — NOT RUN, NOT DONE

**Nothing below was executed.** No source was edited.

### Fix 1 — the `AFTER` (two edits, in this order; the second is easy to miss)

1. `tinybendygrad/codegen/late/linearizer.bend:1617-1620` — build
   `RANGE(AFTER(bound, edge), arg, tag)` instead of `RANGE(bound, edge, arg, tag)`.
   `UOp.after` is at `tinybendygrad/uop/ops.bend:2818` and must be called with
   `src = [self] ++ srcs`, which it already does; the note at `:2811-2817` warns that
   appending `self` to the END of `srcs` is a live past defect in this tree.
   `:1587-1589` must be rewritten — it is currently a **false claim about upstream**, and
   leaving it would make the next reader trust `x.src + (edges[x],)`.
2. `.agents/slop/graphcmp.bend:993` — replace
   `+rb = O.UOp.new(..., O.OpsRANGE{}, [c5i, ra], O.ARange{[2], WEAK}, ...)` with an
   `AFTER(c5i, ra)` whose single src is the new `RANGE`'s only source. This adds one arena node,
   so **`+of1`, `+ix0` … `+sk` and every later arena index in `g_lin` shifts by one** — and
   `graphcmp.bend:780-783` warns in this very file that *"the arena indices are the toposort
   positions, so a node built in a different ORDER is a different file even though it is the
   same graph."* `graphcmp.bend:985-992` and the `46 nodes` at `:963` and `graphcmp.py:1212`
   must be corrected at the same time or they will be stale again.

### Fix 2 — the SINK tag

`graphcmp.bend:1038`: `O.TInt{1}` → `O.TNone{}`. One token. It must land separately from fix 1
because fix 1 does not move that column and a gate that sees "the graph got closer" must not be
allowed to mark the whole graph green.

### Verification (three instruments, each of which can fail on its own)

| instrument | what it must show | why it is the right one |
|---|---|---|
| `.venv/bin/python gates/linearizer_census-gate.py` | `cfg_hits` moves from `- 1->[CAST,END,END]` to `- 1->[AFTER]` | `cfg_hits` (`:1691-1697`) prints the rewritten range's **src op sequence**, so append-vs-wrap is exactly the field it prints. `cfg_hits` is one of the **69 of 71 rows** that are NOT declared divergences (`gates/linearizer_census-pins.rows:5`), so it must agree. `cfg_edges_n` and `cfg_edges` must NOT move — they gate the edge *table*, not the rewrite. |
| `gates/linearizer_census-oracle.py` → `--refresh` on the pins | the regenerated `cfg_hits` row | the CPython lane imports the **re-vendored** `pm_add_control_flow` (`gates/linearizer_census-oracle.py:57-58`), so it already answers `1->[AFTER]`. A red run here before the port is fixed is the *expected* confirmation that the diagnosis is right. |
| `checks/differ.py run`, then `runs/graphcmp/D/D2-cmp-lin.txt` | `BYTE-IDENTICAL`, and `lin` leaves the disagree set so `graphs-agree=32` and `expect-moved=2` | `D2-cmp-*.txt` byte-identity is the graph-level oracle; the counters are read from `D0-run-summary.txt`. |

**A fix that moves only `g_lin` will NOT turn the `linearizer_census` gate green**, and a fix
that moves only `cfg_rewrite` will not change `D2-cmp-lin.txt` — the fixture is hand-written and
the rule is never driven by the corpus. They are two defects that happen to agree, which is
precisely why their agreement was never evidence.

---

## 8. Instrument status (read, not run)

- `gates/linearizer_census-gate.py` exists with a **present, non-empty** pins file
  (`gates/linearizer_census-pins.rows`, 2116 B, "2 DIVERGENCES of 71 ROWS, 69 OF WHICH AGREE
  EXACTLY"). `gates/artifacts/linearizer_census/` is an **empty directory**. **I did not run the
  gate, so I make no claim about its current verdict.** What I can say statically: the pinned
  `cfg_hits=- 1->[CAST,END,END]` appears in `oracles/tinybendygrad_codegen_late.bend.rows:59` and
  `oracles/late-oracle.rows:61`, both **older than the re-vendor**, and it records a **three-src**
  range rewrite, which the current upstream rule — which yields exactly one src, an `AFTER` —
  cannot produce. **Statically, that row cannot be green against the re-vendored oracle. This is
  a derivation from the two sources, not a measurement.**
- The previous run's `D0-coverage-census.txt` (read at ~17:23Z, before the in-flight run
  truncated it to 0 bytes) already carried the machine-generated verdict for this graph:
  `lin  50/49  BAD  … [PY-BEND OPs DIFFER: ['AFTER']]`. The census and this report agree on
  the op and on both node counts.

## Files written by this unit

- `.agents/slop/dg-lin/REPORT.md` (this file)
- `.agents/slop/dg-lin/diff.rows` — TAB-separated, columns
  `side / first_divergent_node / n_nodes_side / n_nodes_port / note`
- `.agents/slop/dg-lin/analyse.py` — the instrument that produced them; `.venv/bin/python`,
  reads two text files, writes nothing else