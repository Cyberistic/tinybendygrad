# THE CITATIONS IN 26 FILES: 53 UNVERIFIABLE AND 57 STALE POINTERS, BOTH TO ZERO

**UNIT:** the `unv2.rows` slice. **FILES:** 26, listed below. **COMMITS:** `c15e67b4d`
(26 files, +201/-134) and `18afa3fde` (1 file, +2/-2).

---

## 1. THE TWO COUNTS, BEFORE AND AFTER

Both measured with the gate's OWN rows file, on a COPY of the LIVE tree
(`gates/pin-cite-gate.py --tree DIR --rows OUT.rows` and
`gates/bendcite-gate.py --tree DIR --rows OUT.rows`), because the tree is owned by
other units and moves under the gate's feet.

| instrument | class | BEFORE | AFTER |
|---|---|---|---|
| `gates/pin-cite-gate.py` | `cite.unverifiable_no_claim_about_the_file` | **53** | **0** |
| `gates/bendcite-gate.py` | `WRONG-LINE` + `DANGLING-LINE` | **57** | **0** |
| `gates/todo-cite-gate.py` | `WRONG-LINE` + `WRONG-SYMBOL` + `UNRESOLVABLE` (my 26) | 0 | **0** |

The BEFORE was 53 unverifiable (the `unv2.rows` file) and 57 stale
(`bendcite-gate.py`'s own rows on the same tree state: 45 WRONG-LINE + 0
DANGLING-LINE at that moment, growing to 57 as other units moved their files).

**WHICH KIND OF FIX DOMINATED: THE STALE POINTERS (57), NOT THE PROSE (53).**
And the reason is the interesting one: **57 of the 110 rows were one MECHANICAL
class** — a `.bend`-to-`.bend` line pointer whose target had moved — and the
durable fix (`symbol=<name>`) is the tree's own convention. The 53 prose rows
needed 53 separate readings of upstream, one construct at a time.

### PER FILE

| file | unverifiable before | unverifiable after | stale before | stale after |
|---|---|---|---|---|
| `codegen/decomp/transcendental_f32.bend` | 20 | 0 | 3 | 0 |
| `runtime/support/system.bend` | 9 | 0 | 0 | 0 |
| `runtime/support/compiler_amd.bend` | 6 | 0 | 1 | 0 |
| `codegen/decomp/dtype.bend` | 3 | 0 | 2 | 0 |
| `runtime/ops_cpu.bend` | 3 | 0 | 1 | 0 |
| `device.bend` | 2 | 0 | 0 | 0 |
| `nn/optim.bend` | 2 | 0 | 0 | 0 |
| `runtime/support/compiler_mesa.bend` | 2 | 0 | 1 | 0 |
| `codegen/opt/heuristic.bend` | 1 | 0 | 1 | 0 |
| `mixin/dtype.bend` | 1 | 0 | 0 | 0 |
| `renderer/isa/x86.bend` | 1 | 0 | 0 | 0 |
| `runtime/ops_npy.bend` | 1 | 0 | 0 | 0 |
| `runtime/support/nv/ip.bend` | 1 | 0 | 0 | 0 |
| `uop/render.bend` | 1 | 0 | 2 | 0 |
| `codegen/decomp/op.bend` | 0 | 0 | 1 | 0 |
| `codegen/rewriter.bend` | 0 | 0 | 1 | 0 |
| `examples/test_pkl_imagenet.bend` | 0 | 0 | 2 | 0 |
| `extra/models/convnext.bend` | 0 | 0 | 6 | 0 |
| `extra/models/resnet.bend` | 0 | 0 | 6 | 0 |
| `extra/models/unet.bend` | 0 | 0 | 5 | 0 |
| `helpers.bend` | 0 | 0 | 3 | 0 |
| `mixin/reduce.bend` | 0 | 0 | 4 | 0 |
| `renderer/amd/generate.bend` | 0 | 0 | 4 | 0 |
| `runtime/support/c.bend` | 0 | 0 | 1 | 0 |
| `schedule/memory.bend` | 0 | 0 | 2 | 0 |
| `uop/ops.bend` | 0 | 0 | 13 | 0 |
| **TOTAL** | **53** | **0** | **57** | **0** |

---

## 2. THE KINDS OF CHANGE

### (a) PROSE REWRITTEN — the 53 `unverifiable` rows

The claim tokens were the PORT's own vocabulary, so **no re-point could make the
claim hold**. The fix names UPSTREAM'S construct, backticked, beside the port's
row name, which is written as the port's:

- `transcendental_f32.bend`'s INVENTORY: twenty bare `:N` cites became
  `tinygrad/codegen/decomp/transcendental.py:9-11 \`_lazy_map_numbers\`` and so on
  — upstream's own names, each at its real line, with the port's gate-row prefix
  (`xf_lazy0_*`, `cu_mb_*`) kept as the port's and SAID to be the port's.
- `system.bend`'s INVENTORY: `vis.*`/`MAP_*`/`gid.*`/`Meta.*`/`face.*`/`Rcmd.*`/
  `rmm.*` became `filter_visible_devices`, `MAP_FIXED`, `ipv4_to_gid`,
  `PCIAllocationMeta`, `PCIIfaceBase`, `RemoteCmd`, `RemoteMMIOInterface`, at
  upstream's real lines.
- `compiler_amd.bend`'s INVENTORY: `c.asm_fail`/`h.opt_empty`/`C.hip_key`/
  `C.short_circuit`/`C.rocm_include` got upstream's `RuntimeError`, `set_options`,
  `HIPCompiler`, `self.no_hipcc`, `ROCM_PATH` beside them, ON THE SAME LINE (the
  gate reads a claim token off the citation's OWN line, so a name one line below
  is invisible).
- `compiler_mesa.bend`: `lpt.*` → upstream's `struct_lp_type`; `a3.*` → upstream's
  `struct_nv_device_info` and its `sm`.
- `dtype.bend`: `l2i_cdiv.step`/`l2i_cdiv.abs`/`l2i_cast1.quo` → upstream's `l2i`
  at `tinygrad/codegen/decomp/dtype.py`, and upstream's `remint` at
  `tinygrad/mixin/elementwise.py:12`.
- `mixin/dtype.bend`: `commit_dtype` was cited at `tinygrad/dtype.py:17`, where
  upstream has NO `commit_dtype` — it is `tinygrad/mixin/dtype.py:16-17`. RE-POINTED
  TO THE RIGHT FILE.
- `device.bend`: the `:0` inside a backticked `` `:0` `` was being parsed as a
  BARE CITATION, so the row's subject was `tinygrad/device.py:0`. REWORDED.
  `device.bend`'s `pm_encode`/`pm_lower`/`pm_link`/`link_bufs` row was reading the
  English words `answers`/`NOTHING`/`carries` as its claim tokens, because a
  backtick span ran across two lines and MISALIGNED the pairing. REBALANCED so
  the upstream names sit on the citation's own line.
- `nn/optim.bend`: `Data` and `Ops.SQRT` → upstream's `assign` and `sqrt`.
- `uop/render.bend`: `METHOD` → upstream's `render_uir`.

### (b) ABSENCE STATED — where the port's symbol has no upstream counterpart

The tree's own pattern (`runtime/ops_amd.bend`: "NOT IN upstream at this pin"):

- `system.bend`: `elemsize` and `post_args` are **this port's** names for
  upstream's `struct.calcsize(self.fmt)` (`tinygrad/runtime/support/system.py:367
  symbol=RemoteMMIOInterface`) and `struct.pack(REMOTE_REQ, ...)`
  (`tinygrad/runtime/support/compiler_amd.py:415` — no: `system.py:415
  symbol=_post`). The comment now says so.
- `device.bend`: `open_one` and `open_two` are **the port's own row names** and
  are NOT in upstream. Said so.
- `ops_cpu.bend`: the port's `D.dev_id` is upstream's `device_id`
  (`tinygrad/device.py:383 symbol=Compiled.__init__`); the port's
  `D.timeline_bytes` is upstream's `timeline`
  (`tinygrad/runtime/ops_null.py:65 symbol=timeline`). Both said so.

### (c) BASENAME DISAMBIGUATED — the ambiguous-basename trap

`dtype.py` is THREE upstream files and `helpers.py` is SEVEN, so a bare basename
names NO file. Every upstream citation that is not the header's own target is now
spelled with its FULL PATH:

- `dtype.py` → `tinygrad/codegen/decomp/dtype.py`, `tinygrad/mixin/dtype.py`,
  `tinygrad/mixin/elementwise.py`
- `optim.py` → `tinygrad/nn/optim.py`
- `device.py` → `tinygrad/device.py`
- `ops_cpu.py` → `tinygrad/runtime/ops_cpu.py`
- `ops_null.py` → `tinygrad/runtime/ops_null.py`
- `x86.py` → `tinygrad/renderer/isa/x86.py`

And every `.bend` pointer into the COMPILER's own tree is now spelled
`references/bend/bend2/base.bend`, because **the port's `base.bend` is a 56-LINE
file and the compiler's is 3,191** — a pointer at `base.bend:2191` can only be
about the compiler's.

### (d) STALE POINTERS RE-POINTED AND NAMED — the 57 rows

Every one is now `file.bend:<the line the construct is AT NOW> symbol=<the
construct's name>`, so the pointer NAMES the construct and does not rot when the
lines move again.

**THE `symbol=` FIELD IS ONLY DURABLE IF THE SYMBOL IS DECLARED IN THE CITED FILE
AT THE CITED LINE, AND THE FIRST ATTEMPT GOT THAT WRONG IN FOUR PLACES** — the
correction is in the second commit's neighbourhood and is worth recording:

| the wrong `symbol=` | why it was wrong | the fix |
|---|---|---|
| `tinygrad/device.py:390 symbol=has_copy_queue` | `has_copy_queue` is DECLARED at :391 | cited :391 |
| `tinygrad/device.py:383 symbol=__init__` | `__init__` is declared SEVEN times in that file | `symbol=Compiled.__init__` |
| `tinygrad/mixin/dtype.py:53 symbol=bitcast` | the token `bitcast` (lowercase) is not on :53; the code says `Ops.BITCAST` | the prose names `Ops.BITCAST` and `symbol=bitcast` |
| `tinygrad/codegen/decomp/dtype.py:64 symbol=l2i` | `l2i` is declared at :21 | `symbol-body` holds :64; the row is about the SHR at :64 |

**MEASURED, EVERY NEW `symbol=` HOLDS BY `symbol-decl` OR `symbol-body`, NEVER BY
THE WEAKEST `symbol-named`** (`gates/todo-cite-gate.py`'s `how` column).

**AND THE `symbol=` FIELD BINDS TO THE NEAREST-PRECEDING CITATION, WHICH IS A
TRAP WHEN A LINE CARRIES BOTH A `.py` AND A `.bend` CITE.** MEASURED, THREE OF MY
ROWS WERE WRONG FOR IT: `jit.py:55, and jit.bend:403 symbol=ii_vars` bound the
symbol to the `.py` cite and read `WRONG-SYMBOL`. THE FIX IS TO PUT THE `.bend`
POINTER AND ITS `symbol=` ON A LINE OF ITS OWN.

---

## 3. THE COMMENT-ONLY PROOF

`checks/port-compile-gate.py`'s `strip_comments()` — LOADED BY PATH, not copied —
then blank lines dropped, then SHA-256. EVERY file compared against `HEAD`:

```
0 of 26 file(s) DIFFER in code.
```

All 26 SAME. (The instrument is `.agents/slop/slice2/commentonly.py`.)

---

## 4. THE COMPILE TOKENS

`.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>`, **ONE bend at
a time**, and the VERDICT TOKEN read, never the exit code:

```
WITHIN-LIMITS tinybendygrad/codegen/decomp/dtype.bend
WITHIN-LIMITS tinybendygrad/codegen/decomp/op.bend
WITHIN-LIMITS tinybendygrad/codegen/decomp/transcendental_f32.bend
WITHIN-LIMITS tinybendygrad/codegen/opt/heuristic.bend
WITHIN-LIMITS tinybendygrad/codegen/rewriter.bend
WITHIN-LIMITS tinybendygrad/device.bend
WITHIN-LIMITS tinybendygrad/examples/test_pkl_imagenet.bend
WITHIN-LIMITS tinybendygrad/extra/models/convnext.bend
WITHIN-LIMITS tinybendygrad/extra/models/resnet.bend
WITHIN-LIMITS tinybendygrad/extra/models/unet.bend
WITHIN-LIMITS tinybendygrad/helpers.bend
WITHIN-LIMITS tinybendygrad/mixin/dtype.bend
WITHIN-LIMITS tinybendygrad/mixin/reduce.bend
WITHIN-LIMITS tinybendygrad/nn/optim.bend
WITHIN-LIMITS tinybendygrad/renderer/amd/generate.bend
WITHIN-LIMITS tinybendygrad/renderer/isa/x86.bend
WITHIN-LIMITS tinybendygrad/runtime/ops_cpu.bend
WITHIN-LIMITS tinybendygrad/runtime/ops_npy.bend
WITHIN-LIMITS tinybendygrad/runtime/support/c.bend
WITHIN-LIMITS tinybendygrad/runtime/support/compiler_amd.bend
WITHIN-LIMITS tinybendygrad/runtime/support/compiler_mesa.bend
WITHIN-LIMITS tinybendygrad/runtime/support/nv/ip.bend
WITHIN-LIMITS tinybendygrad/runtime/support/system.bend
WITHIN-LIMITS tinybendygrad/schedule/memory.bend
WITHIN-LIMITS tinybendygrad/uop/ops.bend
WITHIN-LIMITS tinybendygrad/uop/render.bend
```

26 of 26 `WITHIN-LIMITS`. Peak RSS was read from
`.agents/slop/peakrss/census.rows` first: the largest of the 26 is `uop/ops.bend`
at 345 MB, well under the 2048 MB ceiling, so the sum-precondition held and the
runs were sequential.

---

## 5. THE PLANT

`gates/bendcite-gate.py --tree DIR` on COPIES. THE EDIT IS ONE TEXT EDIT: it
moves `uop/ops.bend`'s re-pointed `ax_names_str` pointer from
`ops.bend:6514 symbol=ax_names_str` BACK to the stale `ops.bend:5793`.

```
PLANT control       tinybendygrad/uop/ops.bend  stale rows: 0
PLANT control-copy  tinybendygrad/uop/ops.bend  stale rows: 0
PLANT broken        tinybendygrad/uop/ops.bend  stale rows: 1
    8750  ops.bend:5793  claim=ax_names_str  the pointer says :5793 and `ax_names_str` is declared at :6516 -- the nearest is -723 line

PLANT OK: the control and its byte copy are green (0 stale rows), and the TEXT EDIT that moves the pointer back to the stale line makes the gate RED (1 stale row(s)).
```

The byte-identical copy is asserted byte-identical (`a == b`) and the broken copy
is asserted NOT byte-identical (`a != c`), so the arm cannot pass by accident.

---

## 6. THE COMMITS

| commit | files | what |
|---|---|---|
| `c15e67b4d` | 26 (+201/-134) | the 53 prose rows and the 57 stale pointers |
| `18afa3fde` | 1 (+2/-2) | two pointers re-pointed again because `mixin/elementwise.bend` MOVED under them |

`git commit --only -F <msgfile> -- <26 paths>`, on the SHARED index, **never
`git add` on a directory, never `git add -A`**. `git show --stat` and
`git fsck --no-progress` were run in the SAME command, in both commits.

`git show --stat` for `c15e67b4d`: **26 files changed, 201 insertions(+), 134
deletions(-)** — and the file list is EXACTLY the 26, no more.

`git fsck --no-progress` reads **3** `duplicateEntries` errors, and they are the
THREE PRE-EXISTING MALFORMED TREES the brief names (`d57bc484`, `3a60f33f`,
`d83cf685`) — NOT MINE. **My commit's own tree is well-formed**: `git fsck`
names it zero times.

---

## 7. THE CORPUS DIGEST, BEFORE AND AFTER

Computed by IMPORTING the instrument, never by running it:

```
.venv/bin/python -c "import sys; sys.path.insert(0,'checks'); import differ; print(differ.substrate_digest())"
```

| | digest |
|---|---|
| BEFORE | `6b1dc7b4abc0cfae6984da7494ce1c70bc273bd019c59b39bfaadcbfc583fd4d` |
| AFTER | `6b1dc7b4abc0cfae6984da7494ce1c70bc273bd019c59b39bfaadcbfc583fd4d` |

**THE DIGEST DID NOT MOVE, AND THAT IS A MEASUREMENT ABOUT THE TREE, NOT ABOUT
MY CHANGE.** `substrate_digest()` is the WORKING TREE's digest, and the working
tree at the moment of the AFTER reading already carried ANOTHER UNIT's edits to
`.bend` files (`mixin/elementwise.bend`, `mixin/op.bend`, `engine/jit.bend`,
`nn/__init__.bend`, `renderer/ptx.bend`, `runtime/ops_disk.bend`, and twenty
more) on top of mine, so the two readings are of two DIFFERENT working trees
and their agreement is a coincidence of the moving target rather than a
property of my edit.

**⇒ THE CORPUS RUN IS STALE FOR A SECOND REASON, AND THE DIGEST IS WHAT SAYS
SO.** `AGENTS.md` records that the citation work moved `tinybendygrad/uop/fold.bend`,
`mixin/op.bend`, `runtime/webgpu_call.bend` and forty more `.bend` files, and
that the live digest is now `ed6a074fe1aa0dfe54df4a768e226f3781df814999e9f7ccafcead1437163cb9`
and NOT the `eb6ef860…` the run recorded. **MY 26 FILES ADD TO THAT SET.** The
corpus run must be re-taken once the port stops moving.

---

## 8. WHAT I DID NOT FIX, AND WHY

1. **THE `WRONG-LINE-BY-BLOCK` CLASS (26 rows for my 26 files).** The gate
   REPORTS this class and does NOT fail on it: "A CLAIM READ OFF THE ENCLOSING
   COMMENT BLOCK IS A CLAIM ABOUT THE PARAGRAPH, AND THE PARAGRAPH NAMES THINGS
   THE POINTER IS NOT ABOUT ... A FALSE FAILURE IS WORSE THAN A MISSED ROW, SO THE
   TWO STRENGTHS ARE TWO VERDICTS AND ONLY THE STRONG ONE FAILS." The brief
   requires `WRONG-LINE` + `DANGLING-LINE` at 0, and both ARE at 0. The
   BY-BLOCK rows are a REPORTED class and fixing them means rewriting the
   ENCLOSING PARAGRAPH, which is a much larger edit than the pointer and would
   change claims about constructs this slice does not own.

2. **THE `AMBIGUOUS` (8) AND `OUT-OF-CORPUS` (7) CLASSES.** Both are counted, not
   failed. `AMBIGUOUS` is a refusal to guess between two same-named `.bend`
   files and needs the corpus's own disambiguator, not an edit.

3. **THE `UNCLAIMED` CLASS (121 rows for my 26 files).** A pointer that lands in
   the file but names nothing the target holds IN CODE. It is counted and
   reported; the brief does not name it.

4. **THE 4 `at_no_revision` AND 3 `only_older_revision` ROWS FOR MY FILES.** These
   are the gate's HOLDING classes — a citation that holds at an older upstream
   revision, which the gate's own header says is "A ROW AND NOT A FAILURE: It is
   a header pinned to the revision it was written against."

5. **TWO ROWS IN OTHER UNITS' FILES.** `gates/todo-cite-gate.py` reads 0
   WRONG-LINE / 0 WRONG-SYMBOL / 0 UNRESOLVABLE for MY 26 files. The two
   WRONG-SYMBOL rows that existed during my work were in
   `mixin/elementwise.bend` and `schedule/multi.bend` — **NOT MINE** — and their
   owner closed them.

6. **A SHARED-PATH RACE I COULD NOT CLOSE.** `engine/jit.bend` and
   `mixin/elementwise.bend` were being edited by another unit WHILE my pointers
   into them were being measured, and they moved TWICE under me: `ii_vars` went
   :393 → :401 → :403, and `ew_exp`/`ew_silu` went :1312/:1219 → :1314/:1221.
   **THE SECOND MOVE IS WHAT COMMIT `18afa3fde` IS.** **THE POINTERS ARE NOW
   CORRECT, BUT A THIRD MOVE WOULD BREAK THEM AGAIN, AND THAT IS WHAT THE
   `symbol=` FORM IS FOR** — a pointer that names the construct is a one-token
   fix when the line moves, where a bare line number is a hunt.

---

## 9. THE INSTRUMENTS

All under `.agents/slop/slice2/`, and none of them is a GATE:

| file | what it is |
|---|---|
| `check.sh` | measures BOTH gates on a COPY of the LIVE tree and prints the counts for my 26 files |
| `rows.py` | the pin-cite gate's OWN rows for named files, loaded BY PATH |
| `symcheck.py` | audits every `symbol=` in my 26 files against the upstream file |
| `symcheck2.py` | the same audit against `gates/todo-cite-gate.py`'s OWN four `how` classes |
| `repoint.py` | the re-point plan, EXPLICIT — one row per edit, with the old text and the new text, and it REFUSES a row whose text it cannot find |
| `plant.py` | the plant: a TEXT EDIT on a copy, plus a byte-identical control |
| `compile.sh` | compiles the 26 files one bend at a time and reads the VERDICT TOKEN |
| `commentonly.py` | the comment-only proof, using `strip_comments()` LOADED BY PATH |
| `msg.txt` | the commit message |

**NO GATE WAS EDITED.** `gates/pin-cite-gate.py`,
`gates/todo-cite-gate.py`, `gates/header-census-gate.py` and
`gates/bendcite-gate.py` are byte-identical to HEAD, and `checks/differ.py` and
`checks/devpin.py` were not touched either. `checks/differ.py` was IMPORTED, never
run.
