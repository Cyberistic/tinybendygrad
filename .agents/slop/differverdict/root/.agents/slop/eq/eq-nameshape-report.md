# DELIVERABLE — the `=`-bearing row-name class, closed: `renderer/nir_llvmir.bend` FIXED, `uop/render.bend` MEASURED AND THE CLASS NOT THERE

Files touched: **`tinybendygrad/renderer/nir_llvmir.bend`** (8 row names) and
**`.agents/slop/nl/nl-oracle.py`** (its generator). **`tinybendygrad/uop/render.bend` was NOT
TOUCHED** — its hash is `3d4497593698ec6e1b50d7a382a9f470` before and after this unit — and §4 says
why, with the counts.

New, all under `.agents/slop/eq/`:

| file | what it is |
|---|---|
| `eq-census2.py` | the re-census, from data, structural |
| `lane.py` | a capture that proves the substrate held still |
| `nl-rename.py` | the `osx=` rename, count-asserted |
| `nl-gate.py`, `nl-gate-noguard.py`, `nl-control.sh` | the nir_llvmir guard, its pre-guard twin, and the control matrix |
| `rn-gate.py` | the render guard |
| `census-tree.txt`, `nl-control-matrix.txt`, `lanes/` | the outputs and the re-captured lane texts |

## 1. HEADLINE, AND IT IS NOT THE HEADLINE THE BRIEF EXPECTED

**`uop/render.bend` has ZERO `=`-bearing row names, on both lanes, and the 31 the census reports
are FALSE POSITIVES.** Measured on fresh captures:

| lane | real rows | names containing `=` | keys of `rows()` | lines `row()` accepts | rows no name can address |
|---|---|---|---|---|---|
| `uop/render.bend` port | 80 | **0** | 97 | 140 | **43** |
| `xd1/render-gate-oracle.py --gate` | 80 | **0** | 85 | 124 | **39** |

The 31 are `pyrender const=[ast`, `pyrender buffer=[c1`, `pyrender xor3=[c1`, … — a reader that cut
at the ` = ` **inside the VALUE** (`ast = UOp.const(3)`). `py_row` writes `nm + " = ["`
(`render.bend:2148`) and the oracle writes `nm + "=["`, so on **neither** lane is that ` = ` a
boundary. `name-census.py`'s own header records this trap at `:205-212` and then falls into it, and
it recorded the error on the **oracle** side of a two-sided lane while the port read 0 — the
direction of the error is itself the tell. A detector that matches a form cannot see the instance
that lacks it.

**So the class is empty here, and there is a LARGER defect on the same lane with the same
arithmetic.** `pyrender` answers legitimately contain newlines, so one logical row is 2–4 physical
lines; `rebase-gate.py:row()` reads every tail as a row of its own. 49 continuation lines on the
port, 44 on the oracle, costing **43** and **39** measurements, landing on `ast` (30×), `c3` (8×),
`c2`, `c4`, `c5` and `py` (5×). No separator rename touches it. §5.

## 2. `renderer/nir_llvmir.bend`, PER KEY: was `=` THE SEPARATOR?

The lane is F2: `r` writes `String.concat([nm, " = [", got, "]   py=[", want, "]\n"])`
(`nir_llvmir.bend:125`), so the writer's boundary is NOT the first `=` on the line and a name **may**
carry one. 8 names over **4 keys of 2 rows each**:

| key (as the shipped reader reads it) | names | `=` | upstream's own name | verdict |
|---|---|---|---|---|
| `sd cpullvm LLVM osx` | `osx=True`, `osx=False` | `osx=` | `OSX`, a module-level **constant**: `tinygrad/helpers.py:17` `OSX, WIN = sys.platform == "darwin", sys.platform == "win32"`; imported into llvmir's namespace at **`tinygrad/renderer/llvmir.py:8`**; READ at **`llvmir.py:219`** `(d != dtypes.half or OSX)` inside `CPU.supported_dtypes` | **separator only.** `OSX` is upstream's identifier; `osx` is not. |
| `sd cpullvm x86_64 osx` | same | same | same | same |
| `sd cpullvm arm osx` | same | same | same | same |
| `sd cpullvm riscv64 osx` | same | same | same | same |

**Two whole-tree greps settle load-bearing-ness, and both are negative:**

```
grep -rnw osx tinygrad/     ->  2 hits, BOTH COMMENTS: llvmir.py:216, compiler_llvm.py:73
grep -rn  "osx=" tinygrad/  ->  NO HITS
```

So upstream has **no identifier `osx`** and **no `osx=` string**. `osx` is this port's own
abbreviation — and already this port's own PARAMETER name: `sd.drop_cpu(+d: S.Dt, x86: Bool, osx:
Bool)` at `nir_llvmir.bend:693` and `sd.cpu.go(+ts, +x86: Bool, +osx: Bool)` at `:717`. That is
exactly the shape of llvmir's `vol=` (upstream's function is `is_volatile`, `vol` is the port's
abbreviation and its parameter name) and cstyle's `lb=` (upstream's `launch_bounds`). The rename
touches the LABEL only; both parameters keep their names, and no `match`/dtype pattern keys on them,
so the `LAWS/spec.bend` fp8 hazard agent-core.md records does not apply.

**`osx=` was never load-bearing, and 0 of the 8 names is a value.** `nl-rename.py` asserts it: all
11 `osx=` occurrences in the port are 6 `osx=True` + 5 `osx=False`, and both oracle sites are
inside f-strings that build a row name (`:201`) or a row-builder argument (`:441`).

**Names may contain spaces and no reader cuts them.** The F3 path in `rebase-gate.py:row()` only
runs on a line with **no** `=`, and this lane's every line has one. Measured: the histogram of
`head.count(" = [")` over all 205 heads is `{1: 205}` and nothing else, on both the pre- and
post-rename captures — so the ambiguity the gate refuses on never fires on the real lane.

## 3. THE RENAME, THE COLLISION CHECK, AND THE GENERATOR

```
nir_llvmir.bend   osx=True  -> osx True    6 occurrences (8 row names in r_sds() + 2 comments)
                  osx=False -> osx False   5 occurrences (same)
nl-oracle.py      osx={osx} -> osx {osx}   2 occurrences (:201, :441)
```

**The oracle needed a DIFFERENT pattern, and that is a finding, not a detail.**
`llvmir-oracle.py:80` is `def par(slot=0, dtype=None, vol=False, aspace=None)` — a **Python keyword
argument** whose text contains ` vol=` — and a bare `osx=`-style substitution there rewrites the
signature and the oracle stops parsing. Here the two files do **not** collide: `grep -o "osx="` on
`nl-oracle.py` counts exactly 2 and both are those f-strings, so the oracle is patched with
`osx={osx}` and the script asserts the split so a future collision cannot pass silently. `nl-rename.py`
also `ast.parse`s the oracle afterwards, because a rename that stops the oracle importing turns
every downstream row into a "0 rows" result, which this project has already mistaken for a pass.

### The rename verified against the GENERATOR, not against my diff

`nl-oracle.py bend` prints this file's row-builder source from the same run that prints the gate
text. Its output is 37 lines; pre- vs post-rename it differs in **1 line**, and after removing
`osx=` from the before-line that line is **byte-identical** to the after-line:

```
THE GENERATOR'S OWN OUTPUT: 37 lines before, 37 after, md5 2216a8f1 -> 63fd9cac
  hunk 1: replace before[25:26] after[25:26]
    after removing `osx=` from the BEFORE line it EQUALS the AFTER line: True
CHANGED HUNKS: 1
```

**Not one other byte of the generated port source moved.**

### And the port's row-builders ARE the generator's output, byte for byte

The strongest statement available, and it is stronger than the diff above: all **12** row-builder
defs `nl-oracle.py bend` emits are present in `nir_llvmir.bend` and **byte-identical**, `r_sds`
included — the one carrying the rename.

```
12 generated defs, 13 in the port
  r_ldts r_lcas r_lcbs r_lopf r_lopz r_lops r_lopos r_consts r_sds r_nms r_geps r_fps
  -- ALL BYTE-IDENTICAL
ALL GENERATED ROW-BUILDERS MATCH THE PORT VERBATIM: True
```

(the 13th is `r_gep`, the single-row helper the generator does not emit.) So the port's row names
cannot disagree with what the oracle emits: they are the same text.

### The collision check, BY MULTISET (`nl-gate.py --compare`)

```
ROWS       206 -> 206 lines; 205 -> 205 read; 205 -> 205 distinct names -- EQUAL distinct counts is
           the collision check: the rename created no name
VALUES     same multiset: True   distinct 141 -> 141   only in BEFORE []   only in AFTER []
RENAME     8 PAIR(S), each one name whose `X=` form is the other side's name with a single space in
           place of the `=`; 0 name(s) on either side have no such partner
COLLISIONS 0 name(s) printed more than once, counted from the LINES and not from `rows_strict`'s dict
           (which has already overwritten them): none
`=` NAMES  8 -> 0, counted from `rows_strict`'s names and NEVER from `rows_shipped`'s keys, which
           cannot contain one by construction
SHIPPED    201 -> 205 keys of `rebase-gate.py:rows()`, i.e. the rows a name can actually address:
           4 more
AUDIT OK on the RENAME
```

**NO COLLISION WAS CREATED, and none was hiding there before either** — 205 distinct names on 205
rows on both sides. A collision after renaming would have been a **finding**; the multiset says
there is none, and it says so as a count rather than by eye.

The port lane moves in exactly 8 lines (16 diff lines: 8 removed, 8 added), all in the row-name
field, values untouched. `./bin/bend tinybendygrad/renderer/nir_llvmir.bend --check-only` prints
`ALL PROOFS CHECK` (first line, not the exit status — agent-core.md).

## 4. HOW MANY COST A MEASUREMENT, WITH THE DENOMINATOR

`rows()` keeps the LAST row on a key, so a key holding *n* rows costs *n−1*.

| key | rows | **cost a measurement** | **merely misnamed** |
|---|---|---|---|
| `rfn abi` (llvmir) | 77 | **76** | 1 |
| `br2 load vol` | 48 | **47** | 1 |
| `br5 stack n` | 10 | 9 | 1 |
| `br3 load vol` | 6 | 5 | 1 |
| `br4 store vol` | 6 | 5 | 1 |
| 5 × `is_volatile <SHAPE> vol` | 2 each | 1 each | 1 each |
| `sd cpullvm {LLVM,x86_64,arm,riscv64} osx` (nir) | 2 each | 1 each | 1 each |
| | **330 `=`-bearing names over 20 keys** | **302** | **28** |

**The census's 302 is REPRODUCED EXACTLY by a method that shares no code with it**
(§6): 294 on llvmir's two lane texts and 8 on nir_llvmir's two, which is the same split
`llvmir-nameshape-control.md` §6 reports. And **after this unit's rename the whole tree has 294
reshape rows and every one of them is still llvmir's** — `nir_llvmir` now contributes 0.

**And the disagreement count is not the point: the pre-rename lane printed `disagree=[]` and `AGREE`
throughout, on both sides, with 4 measurements unreachable by any name.** That is the whole failure.

## 5. `uop/render.bend` — the larger defect, MEASURED, NOT FIXED

`rn-gate.py` GUARD 0, on the real captured pair:

```
port logical rows: 91   oracle logical rows: 80   BYTE-IDENTICAL: False  <- a REAL measurement
lane    phys lines  logical rows  cont lines  keys (shipped)  `=` unaddressable  =cont  refused
port           140            91          49              97    0            43     43        0
oracle         124            80          44              85    0            39     39        0
gated 80   agree 75   disagree ['arg_repr AKern','arg_repr AParam1','arg_repr AParam2',
                                 'arg_repr AParam3','arg_repr AProgr']
```

Three findings, all real, none of them an `=`:

1. **49 / 44 CONTINUATION lines.** `pyrender` answers contain `\n` (`render.bend:2148`), so one row
   is 2–4 physical lines. They land on the keys `ast` (30×), `c3` (8×), `c2`, `c4`, `c5`. 43 and 39
   measurements lost. **No separator rename can touch this.**
2. **FIVE HAND-WRITTEN WRAPS, `render.bend:2809-2819`.** The author prints five rows as TWO
   `IO.print`s each, putting the `py=` column on its own line:
   `IO.print("arg_repr AKern   = [" ++ arg_repr(...) ++ "]")` then
   `IO.print("                     py=KernelInfo(name='test', ...)")`. The oracle prints them as one
   line. So those **five rows DISAGREE** — the only real value disagreements on this lane — and the
   shipped reader, which reads each physical line as a row, sees a phantom row named `py`. **This is
   a genuine port defect and it is the one thing here a byte diff catches, because on this lane the
   two sides do NOT print the same bytes** (port md5 `302944bb48a32379`, oracle
   `642f9770c558df0f1be03a8f67ac997e`; 140 lines against 124).
3. **11 `rnd_*` rows the oracle does not answer** (`render.bend:2693-2703`), a `ghost`, all F1
   (`rnd_param_named=i`) on an otherwise-F2 lane. **THE LANE PRINTS THREE BOUNDARY SPELLINGS** —
   ` = [` (port), `=[` (oracle) and glued `=` (`rnd_row`) — so the shape cannot be decided once for
   the lane, and a per-lane majority rule mis-cuts `rnd_param_named=i`. `rn-gate.py` tries the
   candidates in order and REFUSES ambiguity rather than resolving it.

**Why not fixed.** Fixing (1) means changing what a row *is* on this lane — either the producer
stops emitting newlines inside a value (a `pyrender` change with a real blast radius) or the reader
learns to fold (a `rebase-gate.py:row()` change, which is **not mine** and which 156 forked readers
already disagree about). Fixing (2) is a five-line edit to `render.bend:2809-2819` that deletes a
hand-written wrap — but the `py=` text on those five rows is the port's **transcription**, and
`agent-core.md` records five units that lost money transcribing one; deleting the wrap without
regenerating the transcription against a live CPython call is exactly that mistake. Both are the
owner's call. **REPORTED, not fixed, with the counts.**

## 6. THE RE-CENSUS, FROM DATA, AND IT RECONCILES

`eq-census2.py --all` over 78 lane texts of 39 ports. **The method is structural, not a substring
search**, and the difference is the entire point:

* a **CONTINUATION** is a physical line starting inside a bracketed value (depth, not position);
* the **writer's boundary** is the first depth-0 `=` whose remainder opens a bracket, before the
  `]   py=` column — and the **lane's shape** is read off the lane by the share of its rows printing
  that column, because `engine/jit`'s row carries `= [` at depth 0 **twice** (once in its own
  boundary, once inside its own value's `] != expected_input_info=[`) and no local rule separates
  them. Deciding it per row produced three `=`-names there that DO NOT EXIST, twice;
* `rebase-gate.py:row()`/`rows()` are **IMPORTED**, never copied.

```
TOTAL over 78 lane texts of 39 ports
  ROWS the writer emitted (a line with a boundary): 22968
  LANE SHAPE, which is what decides whether the class CAN exist:
      F1 18495  the writer glued the value on, so the FIRST `=` IS the boundary and a name cannot
                contain one -- STRUCTURALLY IMMUNE (80.5% of rows)
      F2  4473  the boundary is ` = [` or `=[`, so a name MAY contain `=` -- the only population in
                which the class exists (19.5% of rows)
      F3     0
  ROW NAMES CONTAINING `=`: 314 of the 4473 F2 rows that can carry one (7.02%)
  NAMES AS A PRODUCER PRINTED THEM: 22831   LINES `row()` ACCEPTS: 23190   DISTINCT KEYS: 22691
  CONTINUATION lines `row()` reads as rows of their own: 224
  ROWS `row()` ACCEPTS THAT NO NAME CAN ADDRESS: 499 = (accepted 23190 − distinct keys 22691)
       82 a CONTINUATION line landed on a key another line already held   (NO `=` involved)
      294 an `=` in a NAME put two differently-named rows on one key       (THE CLASS)
      123 one NAME printed twice                                          (NO `=` involved)
     attribution 82 + 294 + 123 = 499 against a measured total of 499: RECONCILES
  THE TRACKER'S CONTROL: 5/78 texts report a continuation and 73/78 report none.  The 5 are
      engine/jit, render (both lanes), viz_serve (both lanes).
```

**The 73/78 IS THE METHOD'S OWN FALSIFICATION**: every lane whose producer emits no newline inside a
value must report zero continuations, and every lane that does report some is a lane that emits
one. A tracker that reported continuations on llvmir, cstyle, sqtt, tc_ptx, nir_llvmir or any of
the other 70 would be wrong, and the run would show it.

### Things the re-census found that `name-census.json` does not have

| finding | number | note |
|---|---|---|
| **`uop/fold.bend` port: 93 lines `row()` ACCEPTS ZERO** | 93 of 241 | `mm_add_zero 0:0`, `mm_add_small 0:12` — one space, no `=`, so `row()`'s F3 path needs two spaces and a one-token head and refuses every one. **93 measurements printed on stdout and compared against nothing.** `fold.bend` is on the do-not-touch list → REPORTED |
| `runtime/support/usb.bend` oracle: 75 duplicate names | 75 rows | `usb_ctx_order_debug6`, `usb_enum_order_1_hit`, … 71 names printed twice. **The biggest loss on the tree and it is not an `=` at all** |
| `runtime/ops_nv.bend` | 11 port / 27 oracle | duplicate names, `nv_errstr_N` and friends |
| `runtime/support/hcq2.bend` oracle | 2 | duplicate names |
| `renderer/tc_ptx.bend` | 1 per lane | `fmt 'ret;'` printed twice |
| `uop/render.bend` port | 5 | the hand-written `py=` wraps of §5 |
| the SHIPPED CACHE IS STALE | — | `name-census-lanes/*.txt` was captured 11:00–11:08; `render.bend` gained its 11 `rnd_*` rows at 11:46, so the cached render port text is **129 lines where the live one is 140**. A census that reports its own cache without saying so is a census of a revision nobody has |

## 7. THE GUARD, PER LANE, BEFORE ANY VALUE COMPARISON

Both gates run GUARD 0 first and put every non-zero fact in `bad`. `nl-gate.py`'s `reshape()`
carries the six facts of llvmir's (`eq`, `reshaped`, `repeated`, `gate_only`, `only_*`, `unread`),
each over `physical`; `rn-gate.py`'s carries the continuation count, because on that lane there is
no `=`.

**`row_strict` REFUSES AN AMBIGUOUS BOUNDARY rather than guessing.** `nl-gate.py`: the lane's
` = [` must occur **exactly once** in the head (`rfind`, never `find`), a row that fails is counted
`unreadable`, and a second candidate is a refusal with the count. `rn-gate.py` tries the three
spellings the render lane actually uses and refuses when more than one candidate survives.

**The manufactured-name wording, kept.** Both gates print the shipped reader's residue the way
`cstyle-gate.py`'s predecessor got it wrong — *"MANUFACTURES out of a reshape, which NO producer
printed"* — and put it in `bad` before any value is compared. On `rn-gate.py` this fires for real:
**60 of the port lane's 97 shipped names are manufactures from a continuation**, and the gate names
them.

**Every `=`-count comes from the STRICT reader's names, never from `rows_shipped`'s keys** — a key
cannot contain one by construction, so that count is a tautological 0 over lane text that has the
defect. **Every collision count comes from the LINES**, never from a dict that has already
overwritten the duplicate; I made that mistake myself twice in `eq-census2.py` (a `set()` in two
places) and the reconciliation line is what caught it, both times at `147` against `148`.

## 8. THE CONTROL MATRIX

### `renderer/nir_llvmir.bend` — `sh .agents/slop/eq/nl-control.sh`

Every cell is a real process; every `rc` is that process's `rc`, captured immediately after it and
before any `grep`. Cell 1 runs `nl-gate-noguard.py`, a **running** detector with **no `reshape()` in
it** — a control run against itself is not a control.

| # | gate | bytes | rc | verdict | `eq` | unaddressable | `disagree` | gated |
|---|---|---|---|---|---|---|---|---|
| 0 | — | `unrename(post) == pre-port.txt` | — | **True**, md5 `1dbc8e00` both | **8** | — | — | — |
| 1 | **pre-guard, no reshape** | PRE-RENAME | **0** | **AGREE** | — | — | `[]` | **201** |
| 2 | **guarded** | PRE-RENAME | **1** | **BROKEN** | **8** | **4** | `[]` | 205 |
| 3 | guarded | POST-RENAME | **0** | **AGREE** | 0 | 0 | `[]` | 205 |
| 4 | guarded + **NAME plant, both lanes** | POST-RENAME | **1** | **BROKEN** | **4** | **2** | **`[]`** | 205 |
| 5 | guarded + **VALUE plant** | POST-RENAME | 1 | **BROKEN** | **0** | 0 | `['ldt f32']` | 205 |
| 6 | `--selftest` | real 205-line lane | 0 | OK | | | | |

**Cells 1 → 2 are the argument.** Same bytes, same byte diff, `disagree=[]` in both. The verdict
moves `AGREE` rc=0 → `BROKEN` rc=1 and the coverage moves **201 → 205** of 205 rows. Cell 0 is why
cell 2 is not a reconstruction: `--unrename` reverses the rename in the row-name field of the live
bytes and reproduces the captured pre-rename stdout **byte for byte**, so the pre-rename side needs
no checked-in oracle.

**THE NAME PLANT IS DISTINGUISHABLE FROM THE VALUE PLANT, and the pair is a PLANT with its DISARM.**

* **cell 4 (plant).** Four `sd cpullvm …` names given an `=` back, so **4 rows land on 2 keys**.
  Result `eq=4`, `unaddressable=2`, **`disagree=[]`**, and the two lanes are **still byte-identical**
  (`port md5=4f221ed7 oracle md5=4f221ed7`, printed on the cell). Every value agrees, the byte
  diff is empty, and the verdict moves on the NAME lane alone. A value plant is **incapable** of
  that shape.
* **cell 5 (falsification).** A planted value gives `eq=0` while the lane goes BROKEN, and the lanes
  stop being byte-identical (`False`, printed). A name check a value plant can turn green is not
  testing the name.
* **cell 3 is the DISARM of cell 4** — the same gate on the same bytes with the plant absent, `eq=0`
  and `AGREE` rc=0. **A RED with no paired DISARM proves nothing about where it landed**, and three
  controls on this project were found disarmed. Cells 3 and 4 are that pair.
* cell 6 over the real 205 lines:
  ```
  clean    AGREE    eq=0 unaddressable=0 disagree=[]
  value    BROKEN   eq=0 unaddressable=0 disagree=['ldt f32']
  shape    BROKEN   eq=1 unaddressable=0 disagree=[]
  collide  BROKEN   eq=2 unaddressable=1 disagree=[]
  ```

### `uop/render.bend` — `rn-gate.py --selftest`, over the real captured pair

The base count is **MEASURED, not typed**, and it is **5, not 0** — because the port's five
hand-wrapped rows really do disagree with the oracle. A control that hardcoded 0 would have read
`value` as a failure of the instrument.

```
[selftest base] the REAL captured pair: 80 gated rows, 75 agree, 5 disagree [...]
  base     BROKEN  cont=49 eq=0 unaddressable=43 disagree=5   ok
  value    BROKEN  cont=49 eq=0 unaddressable=43 disagree=6   ok
  shape    BROKEN  cont=49 eq=1 unaddressable=43 disagree=0   ok
  collide  BROKEN  cont=49 eq=0 unaddressable=44 disagree=0   ok
```

A **value** plant raises `disagree` by exactly one; a **name** plant leaves `disagree` at the base
count and moves `eq` and the name sets. Two attempts at the name plant failed first and both are
recorded in the file: a trailing `=` reads as the F2-tight form and silently truncates the name
(`eq=0`), and the candidate test compared `probe[i:i+len(rx)]` against `rx[-2:]` — off by one,
because `probe[i:]` starts **at** the `=` — so it rejected every candidate and fell through to
`eqs[0]`. **A reader whose candidate test rejects all candidates looks exactly like a lane with no
ambiguous rows.**

## 9. ⚠ THE STANDING HAZARD, SAID ON EVERY RUN

* On `nir_llvmir` the port and the oracle print the **same bytes** (md5 `4f221ed7` both, before and
  after the rename), so `disagree` is 0 by construction and **the byte diff is the gate; GUARD 0 is
  the only thing that can be red.** `nl-gate.py` prints that line every run.
* On `uop/render.bend` they print **different** bytes (140 lines / md5 `302944bb` against 124 /
  `642f9770`), so there the value comparison is a **real measurement** — and it is the only thing on
  either lane that finds the five wrapped rows.
* **The substrate on BOTH lanes is not still.** `tinybendygrad/uop/ops.bend` is in both closures
  (6 files for nir_llvmir, 5 for render) and belongs to another live unit. **MEASURED TWICE**: two
  consecutive captures of the nir_llvmir PORT lane printed 206 rows and then **ZERO** with rc=1,
  naming `vd_text` (`ops.bend:7837`) and then `vd_dbg.of` (`ops.bend:7874`) — **a different line**,
  so the file moved between the two failures. A zero on these lanes is a **REQUEST FOR A RETRY**
  through `.agents/slop/eq/lane.py`, never a result. `lane.py` digests the whole import closure
  before and after every capture and prints the load (rc, seconds, lines, distinct keys, closure
  size) so a starved or mid-edit lane is never counted as a measurement.

## 10. FOUND AND NOT FIXED

1. **`uop/fold.bend`: 93 printed measurements `row()` refuses outright** (§6). Do-not-touch file.
2. **`runtime/support/usb.bend` oracle: 75 rows lost to 71 duplicate names** — the largest single
   loss on the tree, and not an `=`. 27 in `ops_nv`, 11 in `ops_nv`'s port, 2 in `hcq2`, 1 each in
   `tc_ptx`, `fold`'s oracle and `viz_serve`.
3. **`uop/render.bend`'s 49 continuation lines and its five hand-written `py=` wraps** (§5).
4. **`render.bend` prints three boundary spellings** on one lane (§5.3).
5. **`rebase-gate.py:row()` cannot fold a multi-line value.** `ga-oracle.py`'s own header records
   the same problem and chose a producer-side fix (one row per emitted line, keyed on its index);
   `render.bend` has not had that treatment and `rebase-gate.py` is not mine.
6. **`uop/render.bend`'s port lane and oracle disagree on 5 rows** and the port has 11 rows the
   oracle does not answer — both reported with the row names.
7. **`name-census.py` should stop reporting `eq` from a `" = "` search.** Its 31 render false
   positives, its 3 `engine_jit` false positives (which the shipped census does not report but my
   first two attempts did), and its `lost`-vs-split reconciliation gap are all the same defect:
   a substring detector asked a lane-shape question. Read-only to me.
8. **`name-census-lanes/` is stale for `render.bend`** (§6).

## 11. REPRODUCE

```
.venv/bin/python .agents/slop/eq/eq-census2.py --all            # the re-census
.venv/bin/python .agents/slop/eq/eq-census2.py --names           # every offending name, per lane
.venv/bin/python .agents/slop/eq/nl-gate.py                      # live nir_llvmir gate, rc=0
.venv/bin/python .agents/slop/eq/nl-gate.py --selftest
.venv/bin/python .agents/slop/eq/nl-gate.py --compare .agents/slop/eq/nl-pre-port.txt \
                                                      .agents/slop/eq/nl-port-post.txt
sh .agents/slop/eq/nl-control.sh                                # the matrix above
.venv/bin/python .agents/slop/eq/rn-gate.py                      # live render gate, rc=1
.venv/bin/python .agents/slop/eq/rn-gate.py --selftest
.venv/bin/python .agents/slop/eq/nl-rename.py --check            # the count assertions, no writes
```

`./bin/bend tinybendygrad/renderer/nir_llvmir.bend --check-only` prints `ALL PROOFS CHECK`.
`uop/render.bend` is untouched: md5 `3d4497593698ec6e1b50d7a382a9f470`.

## 12. ⚠ A CONCURRENCY FACT THE COORDINATOR NEEDS

**I ran no `jj` write command — no `describe`, no `new`, no `commit`.** But `tinybendygrad/renderer/
nir_llvmir.bend` and `.agents/slop/nl/nl-oracle.py` **no longer appear in `jj status`**: the log head
is `9b9b9a42dfa5` with an EMPTY description, and `jj file show -r @` on the port already contains
the rename. Another live unit's `jj` snapshot swept both edits into the working-copy commit, which
is what jj does to every file in the tree at once. So **these two files are inside `@` rather than
in the pending diff**, and `jj status` will not show them to whoever reviews. Verify with
`jj file show -r @ tinybendygrad/renderer/nir_llvmir.bend | grep -c 'osx True'` → **3**, and
`grep -n 'osx {osx}' .agents/slop/nl/nl-oracle.py` → **lines 201 and 441**.

Everything else this unit added is `A`/`M` in `jj status` under `.agents/slop/eq/**` and the
append-only block at the END of `.agents/slop/notes/bend2-constraints.md`.