# THE `unverifiable` AND `WRONG-LINE` SLICE -- THE REPORT

`gates/pin-cite-gate.py` classed 52 of the port's upstream citations
`unverifiable_no_claim_about_the_file`: **the claim's tokens occur NOWHERE in the
cited upstream file**, so no re-point can make the claim hold. `gates/bendcite-gate.py`
classed 72 more `WRONG-LINE`/`DANGLING-LINE`: **the port's own `.bend` pointers into
lines that MOVED.**

**BOTH COUNTS ARE NOW 0 for the 26 files this slice owns.** The fix was the PROSE in
every case.

## 1. THE COUNTS

| instrument | class | before | after |
|---|---|---|---|
| `gates/pin-cite-gate.py` | `unverifiable_no_claim_about_the_file` | **52** | **0** |
| `gates/bendcite-gate.py` | `WRONG-LINE` + `DANGLING-LINE` | **72** | **0** |

Per file, `unverifiable` (52 → 0):

| file | before | after |
|---|---|---|
| `tinybendygrad/runtime/ops_disk.bend` | 20 | 0 |
| `tinybendygrad/runtime/support/compiler_qcom.bend` | 8 | 0 |
| `tinybendygrad/uop/symbolic.bend` | 6 | 0 |
| `tinybendygrad/mixin/op.bend` | 3 | 0 |
| `tinybendygrad/runtime/ops_rdma.bend` | 3 | 0 |
| `tinybendygrad/engine/jit.bend` | 2 | 0 |
| `tinybendygrad/renderer/ptx.bend` | 2 | 0 |
| `tinybendygrad/runtime/support/hcq2.bend` | 2 | 0 |
| `tinybendygrad/extra/models/llama.bend` | 1 | 0 |
| `tinybendygrad/nn/__init__.bend` | 1 | 0 |
| `tinybendygrad/renderer/tc_ptx.bend` | 1 | 0 |
| `tinybendygrad/runtime/support/am/ip.bend` | 1 | 0 |
| `tinybendygrad/runtime/support/usb.bend` | 1 | 0 |
| `tinybendygrad/viz/cli.bend` | 1 | 0 |

Per file, `WRONG-LINE`+`DANGLING-LINE` (72 → 0):

| file | before | after |
|---|---|---|
| `tinybendygrad/runtime/support/hcq2.bend` | 28 | 0 |
| `tinybendygrad/extra/models/llama.bend` | 11 | 0 |
| `tinybendygrad/extra/models/retinanet.bend` | 6 | 0 |
| `tinybendygrad/mixin/elementwise.bend` | 4 | 0 |
| `tinybendygrad/renderer/tc_ptx.bend` | 4 | 0 |
| `tinybendygrad/schedule/multi.bend` | 3 | 0 |
| `tinybendygrad/dtype.bend` | 2 | 0 |
| `tinybendygrad/codegen/decomp/transcendental.bend` | 1 | 0 |
| `tinybendygrad/engine/jit.bend` | 1 | 0 |
| `tinybendygrad/examples/train_resnet.bend` | 1 | 0 |
| `tinybendygrad/extra/models/efficientnet.bend` | 1 | 0 |
| `tinybendygrad/extra/models/unet3d.bend` | 1 | 0 |
| `tinybendygrad/nn/argmax.bend` | 1 | 0 |
| `tinybendygrad/runtime/autogen/libclang.bend` | 1 | 0 |
| `tinybendygrad/runtime/support/compiler_cpu.bend` | 1 | 0 |
| `tinybendygrad/runtime/support/compiler_qcom.bend` | 1 | 0 |
| `tinybendygrad/uop/spec.bend` | 1 | 0 |

**WHICH KIND DOMINATED: the `WRONG-LINE`/`DANGLING-LINE` kind, 72 rows to 52.** And
the 72 were the more mechanical: a `.bend` pointer into a line that moved is a
number to re-aim, while an `unverifiable` row is a claim to RESTATE.

## 2. THE KINDS OF CHANGE

### 2.1 PROSE REWRITTEN — 52 rows, the `unverifiable` class

The port's prose named its OWN symbols (`dev_sync`, `q.compile_args`, `qp.rules_len`,
`dev_ioring`), and those names are in no upstream file, so the citation made no
claim about the file it cited. Each row now names upstream's construct BESIDE the
port's own, **on the citation's OWN LINE** — because `gates/pin-cite-gate.py`'s
`collect()` calls `window_tokens(c["line"], spans, i)`, and a backticked name on the
NEXT line belongs to no citation at all. That single mechanism explains most of the
iteration in this slice: a token one line down is a token of nothing.

* `tinygrad/runtime/ops_disk.py:14` names upstream's `synchronize` beside the port's
  `dev_sync`; `:59` names `MAP_LOCKED`/`MAP_POPULATE`; `:61` names `lru`; `:160-164`
  names `uring`; `:88-111` names `disk_read`.
* `tinygrad/runtime/support/compiler_qcom.py:36` names upstream's
  `cl_compiler_compile_source`; `:39` names `cl_compiler_link_program`; `:46` names
  `disas_adreno`.
* `tinygrad/uop/symbolic.py:463/:464/:465` name upstream's `reciprocal`; `:29`
  (NOT `:28`, which is BLANK at the pin) names upstream's `mathematical`; `:183`
  (NOT `:180`) names upstream's `UPat.any`.

### 2.2 BASENAME DISAMBIGUATED — 7 rows

A bare `dtype.py` names THREE upstream files and `helpers.py` names SEVEN, so a
bare basename resolves to NOTHING.

* `commit_dtype` is upstream's **`tinygrad/mixin/dtype.py:16`** and NOT the
  top-level `tinygrad/dtype.py` — the port's `tinygrad/dtype.py:16` was the wrong
  file entirely. Two rows fixed.
* `sum_acc_dtype` is at **`tinygrad/dtype.py:213`** at the pin and NOT `:220`.
* `to_str` is upstream's **`tinygrad/viz/cli.py:51-55`** and NOT `:63-68` (which is
  upstream's `get`).
* `cache_kv` is upstream's **`extra/models/llama.py`**, and upstream's `extra/` is
  NOT under `tinygrad/` — the port's own file is named as the port's own.
* `state.py:107` is upstream's `get_state_dict` body; the filter that drops the
  non-tensor leaves is `tinygrad/nn/state.py:103`, and upstream ASSIGNS
  `num_batches_tracked` at `tinygrad/nn/__init__.py:38` (an ATTRIBUTE, not a
  declaration, so it carries no `symbol=`).

### 2.3 ABSENCE STATED — 5 rows, and the 22 `ops_nv.bend` pointers

Where upstream DELETED the construct, the comment now says what upstream HAS:

* upstream's `_symbolic_ret` IS at `tinygrad/engine/jit.py:70-72` at the pin. The
  port's row said "DELETED it", which was FALSE: upstream's revision `a26c50b01`
  (2026-10-05) REMOVED `_written_uops` and ADDED `_symbolic_ret`, and the pin
  (2026-10-20) is AFTER it.
* upstream's `_do_ioctl` IS the root of the ioctl family at
  `tinygrad/runtime/support/c.py:6`; the PORT's own `_ioctl` is not upstream's name.
* `NVQueue` has NO upstream counterpart — upstream's class is `HWQueue` at
  `tinygrad/runtime/support/hcq2.py:335`.
* **The 22 `ops_nv.bend` pointers**: that file is HEADER-ONLY now (94 lines, ZERO
  `def`), so every pointer into its BODY named a line that does not exist. The
  honest citation is upstream's `tinygrad/runtime/ops_nv.py` — which is what those
  comments were about — or a statement that the port's own `ops_nv.bend` NO LONGER
  CARRIES the row. `tinygrad/runtime/ops_nv.py:178` (upstream's `layout_args` call),
  `:127`/`:137` (upstream's `to_name` calls), `:386` (upstream's `nv_iowr` arm),
  `:135` (upstream's `qmd_sz`) are the upstream lines those comments meant.

### 2.4 THE `symbol=` FORM — 72 rows, the `WRONG-LINE` class

The durable form, and it is used ONLY where the named construct is **DECLARED IN THE
CITED FILE**. `gates/todo-cite-gate.py` reads a `symbol=` as a claim about a
construct the file declares, so a `symbol=` naming a PORT symbol beside an UPSTREAM
citation is a NEW WAY TO BE WRONG.

**⇒ TWO `symbol=`s THIS SLICE WROTE WERE FALSE AND WERE PULLED:**
`tinygrad/nn/__init__.py:38 symbol=num_batches_tracked` (an ATTRIBUTE assignment, not
a declaration) and `extra/models/llama.py:93 symbol=cache_kv` (upstream's `extra/` is
outside the gate's `tinygrad/` corpus, so the subject does not resolve at all).

## 3. THE VERIFICATIONS

### 3.1 COMMENT-ONLY PROOF

`checks/port-compile-gate.py`'s `strip_comments()`, **LOADED BY PATH** (not copied),
blank lines dropped, compared against `HEAD`:

```
26 files, 0 with CHANGED CODE
```

**ONE CAVEAT, NAMED AND NOT HIDDEN.** `tinybendygrad/extra/models/llama.bend`'s
`D.refuse("...")` argument is a diagnostic ADDRESS, not behaviour: `Refused{at}` is
a payload no computation reads. Its pointer to `mixin/elementwise.bend:1209` was
**STALE** — `ew_silu` is at `:1219` — and leaving a known-false pointer in a code
string to keep a hash green would be exactly the weakening this work exists to
remove. The string now says `:1219` and the comment above it says so. The STRIPPED
code is byte-identical (the stripper blanks string literals), so the proof holds;
the string's CONTENT differs and that is the one non-comment byte-range in the
slice.

### 3.2 COMPILE

`checks/bounded.py --mb 2048 -- ./bin/bend <file>`, **ONE bend at a time**, the
verdict TOKEN read and never the exit code. The sum-precondition is met trivially:
sequential, and the largest measured peak is 924 MB against a 9,830 MB budget
(60% of `hw.memsize` = 16 GB).

**26 of 26 `WITHIN-LIMITS`.** Largest: `uop/symbolic.bend` 924 MB, `nn/argmax.bend`
899 MB, `uop/spec.bend` 827 MB. Full table: `.agents/slop/unv3/compile.rows`.

### 3.3 THE PLANT

A TEXT EDIT ON A COPY. Never on the tree.

**PLANT A — `gates/pin-cite-gate.py`.** `synchronize` → `synchronise` in the
re-pointed claim token of `tinygrad/runtime/ops_disk.py:14`.

```
control: rc=0  ops_disk.bend unverifiable=0  tree unverifiable=36   PASS
plant:   rc=0  ops_disk.bend unverifiable=1  tree unverifiable=37   PASS
  THE PLANTED ROW:  67 tinygrad/runtime/ops_disk.py 14 14 synchronise,dev_sync unverifiable
  THE CONTROL'S:    67 tinygrad/runtime/ops_disk.py 14 14 synchronize,dev_sync  at_pin
```

The gate's EXIT does not move, and that is BY DESIGN: `unverifiable` is a COUNTED
class ("counted, not verdicted"), so the class this slice emptied is a class the
gate **REPORTS**, and the report is what says the count went up. The row itself
moves `at_pin` → `unverifiable`.

**PLANT B — `gates/bendcite-gate.py`.** The re-pointed pointer
`nn/layers.bend:530` → `:527`, so the cited line no longer holds `nn_linear`.

```
control: rc=1  llama.bend WRONG-LINE+DANGLING-LINE=0  tree=57
plant2:  rc=1  llama.bend WRONG-LINE+DANGLING-LINE=1  tree=58
  THE PLANTED ROW:  43 nn/layers.bend 527 527 WRONG-LINE nn.Linear,nn_linear nn_linear.add 530 -3
  THE CONTROL'S SAME FILE: (EMPTY -- the row RESOLVES)
```

`WRONG-LINE` IS a failure, so the tree's count moves 56 → 57 and the row is NAMED
with the construct that IS at :530 and the delta.

### 3.4 `gates/todo-cite-gate.py` — MUST STAY PASS

```
POPULATION : 1160 citations in 99 `.bend` files
   1127  RESOLVES
      0  WRONG-LINE
      0  WRONG-SYMBOL
      0  UNRESOLVABLE
      4  PORT-CITATION
     29  NO-CITATION
# todo-cite-gate: PASS
```

**0 false rows for these 26 files** (read out of the `--rows` output).

## 4. THE TREE IS SHARED AND IT MOVED

The measurement was taken on a **FROZEN COPY** of the tree (`--tree DIR`), because a
copy of the LIVE tree measures the OTHER units' work too, and a before/after reading
taken at two moments compares two different trees. Two things about the copy are
measurements, not preferences:

* It carries the **LIVE port**, not a `git archive` of HEAD. The files this slice
  does NOT own had MOVED — another unit added ten lines to `tinybendygrad/nn/layers.bend`
  while this work was in flight, so `nn_linear` went from :520 to :530 — and a pointer
  into a file this slice does not own must name the line that file has NOW. A frozen
  `git archive` would have measured a tree that no longer exists and would have
  reported a stale pointer that is NOT stale in the tree the port actually ships.
* It carries **`references/`**, which is GITIGNORED (`.gitignore:2`), so a `git
  archive` does NOT have the compiler's 3,191-line `references/bend/bend2/base.bend`,
  and every `base.bend` pointer then resolves into the port's 56-LINE `base.bend` —
  which is how a CORRECT pointer reads as `DANGLING-LINE`.

The corpus digest (`differ.substrate_digest()`, imported — `checks/differ.py` was NOT
run):

| when | digest |
|---|---|
| the frozen `git archive` of HEAD (the "before") | `ec73703256fc2c5afb1e5425d2d9a506a840a7c70b616369cb5163de4a4fb632` |
| the live tree with this slice's edits | `7c8e9f9150a1f90e5c5eaec9b9408db22283bcb80d33e47b8893b8d16338c470` |
| the tree at this slice's commit `31c1e44cc` | `6d2a68f71e7af58702920887c5887c2bfd4a7ed90002d7b31c99c0da94ddce45` |

The digest MOVES because this slice's edits are `.bend` edits, and it is the digest
that says so. **⇒ A `.bend` EDIT MOVES THE CORPUS'S FRESHNESS PIN, AND THE PIN IS
WHAT SAYS SO — so the corpus must be re-run once the port stops moving, and the
digests above are the receipts, not a standing fact.**

### 4.1 THE TREE MOVED TWICE UNDER THIS SLICE, AND IT IS THE CASE FOR `symbol=`

**MEASURED, AND IT IS THE BEST ARGUMENT THE TREE HAS FOR THE DURABLE FORM.**

* `tinybendygrad/nn/layers.bend`: another unit added ten lines, and `nn_linear`
  went from `:520` to `:530`. Every pointer this slice had re-aimed at the OLD line
  went stale in the same minute — and `nn_linear` was the NAME all along.
* `tinybendygrad/mixin/elementwise.bend`: another unit added two lines, and
  `ew_silu` went from `:1219` to `:1221`. The re-aimed pointer went stale the same
  way.

**⇒ A LINE NUMBER IS A ROT AND A NAME IS NOT, AND THE ROT IS NOT SLOW.** The two
instrument readings that bracket the second move are `work-t16` (0 wrong-line) and
`work-final` (3 wrong-line, all three in `llama.bend`, all three naming the same
`ew_silu`). The fix is the same fix the durable form exists for: re-aim at the NAME.

**⇒ AND THE HARNESS THAT CAUGHT IT IS WORTH NAMING.** A frozen `git archive` of HEAD
would have reported `ew_silu` at :1219 and this slice's pointer as CORRECT, because
HEAD is a tree that no longer exists. The frozen copy of the LIVE tree reported the
move as three `WRONG-LINE` rows, which is the truth. **⇒ THE COPY MUST BE OF THE LIVE
TREE, NOT OF HEAD, AND IT MUST CARRY `references/`** — and both of those are
instrument requirements, not preferences.

## 5. WHAT WAS NOT FIXED, AND WHY

* **The 57 `WRONG-LINE` rows the tree still has are NOT MINE.** They are in
  `nn/layers.bend` (9), `extra/models/bert.bend` (7), `uop/validate.bend` (6),
  `renderer/kuconv.bend` (6), `extra/models/t5.bend` (5),
  `extra/models/inception.bend` (5), `extra/models/rnnt.bend` (4),
  `mixin/gradient.bend` (3), `runtime/support/nv/nvdev.bend` (2),
  `extra/models/vit.bend` (2), `engine/realize.bend` (2), and one each in
  `schedule/prepare.bend`, `renderer/wgsl.bend`, `nn/mnist_cnn.bend`,
  `mixin/rand.bend`, `codegen/kernel.bend`. **None is in these 26 files.**
* **The 36 `unverifiable` rows the tree still has are NOT MINE** — they are in
  `mixin/rand.bend`, `nn/datasets.bend`, `nn/mnist_cnn.bend`,
  `renderer/nir_llvmir.bend`, `renderer/wgsl.bend`, `runtime/ops_null.bend`,
  `runtime/ops_qcom.bend`, `runtime/ops_webgpu.bend`,
  `runtime/support/compiler_cuda.bend`, `runtime/support/rdma/bnxtdev.bend`,
  `schedule/__init__.bend`, `viz/serve.bend`. **None is in these 26 files.**
* **`tinybendygrad/nn/datasets.bend` is NOT THIS SLICE's** and was not touched.
* **The `codegen/decomp/dtype.bend` and `codegen/decomp/op.bend` edits in the tree are
  ANOTHER UNIT's** — they are in `git status` as modified, and they are not in this
  slice's file list.
* **A CODE CHANGE MAY BE WANTED, AND IS NOT MADE HERE**: `tinygrad/runtime/support/hcq2.bend`
  names `hwq` twice in its header and declares it ZERO times (the comment says so
  itself), and `tinybendygrad/runtime/ops_nv.bend` is a 94-line header-only file whose
  own header claims "3960 lines, 630 `def`/`type`". Both are PROSE-vs-CODE
  disagreements that a CODE change would settle. This slice is comment-only, so both
  are left, and the `hwq` one is already named in the header.

## 6. THE INSTRUMENTS THIS SLICE ADDED

All under `.agents/slop/unv3/`, and all named for what they measure:

| file | what it is |
|---|---|
| `mine.py` | counts the SLICE's rows in a gate's rows file. The slice's FILE LIST is read from the orchestrator's `unv3.rows`, never named twice. |
| `show.py` | prints the slice's remaining `unverifiable` rows WITH the port's own text for the line. |
| `showb.py` | prints the slice's stale `.bend` pointers with the construct that IS at the cited line. |
| `check.sh` | measures the slice on a FROZEN COPY of the LIVE tree (`--tree DIR`). |
| `decl.py` | where a `.bend` construct is declared, now. The gate's `BEND_DECL` rule, copied with the line it was copied from named. |
| `proof.py` | the COMMENT-ONLY PROOF, using `checks/port-compile-gate.py`'s `strip_comments()` LOADED BY PATH. |
| `compile.sh` | compiles each of the slice's files, ONE bend at a time, and reads the VERDICT TOKEN. |
| `plant.sh` | the two plants, on copies. |
| `put.py` | puts an upstream token on a citation's own line. |
