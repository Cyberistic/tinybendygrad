# The `UNCLAIMED` slice -- 201 rows in 33 files, and the `symbol=` form.

MEASURED 2026-10-28. The slice is
`/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/work/../slices/unclaimed1.rows`
(the orchestrator's `unclaimed1.rows`). The tree moved FOUR times under this slice
(`9b1e3aa53`, `9616cb3f6`, `949e15c36`, `f48472ed1`), so EVERY line number below was
re-derived against the tree as it stood at the commit.

## WHAT THE CLASS WAS

`gates/bendcite-gate.py` judges the port's own `.bend` -> `.bend` LINE citations.
`UNCLAIMED` means the pointer RESOLVES and lands in the file, but the citing text names
nothing the target holds IN CODE -- so there is no claim to falsify.

MEASURED: **ALL 201 rows** carried the same `why` --
`the citing text names [...] and <target> DECLARES none of them, so there is no
construct for the pointer to point at`.

## THE THREE RULES THAT DECIDED EVERY ROW, AND WHERE THEY COME FROM

1. **`symbol=<name>` NAMES A CONSTRUCT THE TARGET DECLARES, AND THE CITED LINE IS THAT
   CONSTRUCT'S DECLARATION LINE.** MEASURED: a `symbol=` whose cited line is merely
   INSIDE the construct's span RESOLVES, but the span INCLUDES the doc-comment run
   above the `def` -- so a pointer at a doc comment is a pointer at the PREVIOUS
   construct. **⇒ THE LINE MUST BE THE `def` LINE.** MEASURED, this bit me: my first
   pass derived the line from the SPAN and `mixin/op.bend:853` (which is `mo_sum`'s
   doc comment) was 1 line off from `mo_sum`'s declaration at `:854`, and it showed up
   as 13 `WRONG-LINE` rows.
2. **THE `symbol=` NAME IS UNALIASED.** MEASURED, `gates/bendcite-gate.py`'s
   `Corpus._scan` computes `self.aliases` in the SAME loop that fills `self.bodies`,
   so an import whose TARGET has not been scanned yet resolves to `None`. `os.walk`
   visits `schedule/` before `uop/`, so **69 of 170 files have a `None` alias**
   (MEASURED: `schedule/indexing.bend` -> `{'H': ..., 'O': None}`), and `strip_alias`
   returns the token UNCHANGED for a `None` alias -- so `O.GroupOp.movement` never
   resolves against `uop/ops.bend`, which declares `GroupOp.movement`.
   **⇒ WRITE `symbol=GroupOp.movement`, NOT `symbol=O.GroupOp.movement`.**
   **⇒ THE GATE IS NOT EDITED. THE DEFECT IS REPORTED HERE.**
3. **A LINE THAT CARRIES MORE THAN ONE CITATION GIVES EVERY `symbol=` ON IT TO EVERY
   CITATION ON IT.** MEASURED on a two-citation line:
   `a.bend:713 symbol=cr_in a.bend:100 symbol=nope` -> the `:100` row is judged with
   the token set `{cr_in, nope}` and goes `WRONG-LINE`. **⇒ ONE CITATION PER LINE.**

**AND A `symbol=` MUST NOT SHARE A LINE WITH A `.py` CITATION** -- `gates/todo-cite-gate.py`
binds the NEAREST-PRECEDING `symbol=` to a citation and requires the symbol to be
DECLARED by the target at the pin, so a port `symbol=` next to an upstream `.py` line
binds to the `.py` and goes `WRONG-SYMBOL`. MEASURED: 3 of my rows did exactly that and
the gate went red; the fix was to move the port `symbol=` onto a line that carries no
`.py` citation, **WITHOUT CHANGING THE FILE'S LINE COUNT**.

## THE COUNTS

`gates/bendcite-gate.py --rows OUT.rows`, `HEAD` `f48472ed1`:

| verdict | HEAD, no my edits | HEAD + my edits |
|---|---|---|
| RESOLVES | 732 | 1031 |
| UNCLAIMED | 410 | 60 |
| WRONG-LINE | 4 | 1 |
| WRONG-LINE-BY-BLOCK | 122 | 116 |
| AMBIGUOUS | 19 | 19 |
| OUT-OF-CORPUS | 10 | 9 |

**MY 33 FILES: `UNCLAIMED` 284 -> 0, PER FILE.** Every file's own count is in
`plan.tsv`'s sibling `per-file.rows`.

**NO CLASS ROSE IN ANY FILE, MINE OR NOT.** MEASURED per file:
`MY FILES UNCLAIMED: rose in 0 files`, `NOT-MINE FILES UNCLAIMED: rose in 0 files`
(126 -> 60), `MY FILES BAD: rose in 0 files` (3 -> 0), `NOT-MINE FILES BAD: rose in 0
files` (1 -> 1).

**THE ONE REMAINING TREE-WIDE `WRONG-LINE` IS NOT MINE**:
`tinybendygrad/nn/mnist_cnn.bend:155 -> layers.bend:927` -- `nn/mnist_cnn.bend` is in
the do-not-touch list AND is dirty in another unit's working copy.

## THE THREE EXTRA-TASK ROWS -- ALREADY DONE BY THE TREE

`mixin/rand.bend` is CLEAN (MEASURED: `git status --porcelain -- tinybendygrad/mixin/rand.bend`
is empty). The three rows
`efficientnet.bend:31 -> mixin/rand.bend:945`, `rnnt.bend:54 -> mixin/rand.bend:921`,
`vit.bend:23 -> mixin/rand.bend:921` are **RESOLVES**:
MEASURED, `commit 9b1e3aa53` ("bendcite: FOUR POINTERS RE-DERIVED, because ANOTHER UNIT
MOVED mixin/rand.bend") re-aimed them, and this slice's own re-derive put the
`symbol=` field on the rows that followed (`mixin/rand.bend:950 symbol=rd_glorot_uniform`,
`mixin/rand.bend:925 symbol=rd_uniform`).

## THE KINDS OF CHANGE

1. **THE `symbol=` FORM** (the bulk): `subject:NNN` -> `subject:NNN symbol=name`, with
   `NNN` the construct's DECLARATION line.
2. **THE HEADER FORM**: a pointer into a file's HEADER (or a TODO wall block) has NO
   construct to name -- the header is free comment space, before the first `def`. The
   honest form is prose that NAMES THE REGION: `THE PORT's `nn/__init__.bend` WALL
   BLOCK`. The claim's TEXT is kept; only the fragile line pointer is replaced by a
   name. MEASURED: 24 of the 201 rows.
3. **THE PROSE FORM**: three rows where the claim is about upstream's construct and the
   port's file has NO def for it -- `hcq2.bend:94` says upstream's `view_as` IS ABSENT
   FROM THE PORT, so the citation became the upstream `tinygrad/uop/ops.py:1236`.
4. **THE `D.refuse(...)` PAYLOADS** (9 files): the payload's `.bend:NN` was STALE or had
   no claim token, so it got the `symbol=` field and the stale line was re-pointed.
   **⇒ THESE 9 FILES ARE NOT COMMENT-ONLY.**
5. **THE `ARange` AND `AXIS_UNROLL` SITE LISTS** (`uop/ops.bend:607-610` and
   `:3120-3125`): the bare `,NNN` continuations are INVISIBLE to the gate, so each site
   was split onto its own line with its own `symbol=`. MEASURED, the lists were ROTTED:
   `AXIS_UNROLL`/`AXIS_REDUCE` are constructed in SIX files at 23 sites (the block said
   "six committed files" -- CORRECT) and `ARange` is read POSITIONALLY in 14 files at 31
   sites (the block said "eleven committed files" and "twenty-nine of those sites" --
   BOTH FALSE, and the block's site list named `codegen/late.bend`, which is now
   `codegen/late/linearizer.bend`).

## THE COMMENT-ONLY PROOF

`checks/port-compile-gate.py`'s `strip_comments()` imported BY PATH, blank lines
dropped, sha256 of the result:

**24 of 33 files strip to the SAME CODE HASH as `HEAD`.**

**9 files do NOT, and they are the `D.refuse(...)` PAYLOAD files** --
`retinanet.bend`, `train_resnet.bend`, `rnnt.bend`, `vit.bend`, `t5.bend`,
`llama.bend`, `unet3d.bend`, `bert.bend`, `efficientnet.bend`. MEASURED, their PURE CODE
(no comments, no string contents) is **BYTE-IDENTICAL** to `HEAD` in all 9; the
difference is INSIDE the `D.refuse("...")` string literals, which the brief's EXCEPTION
covers ("A `D.refuse("…")` DIAGNOSTIC STRING THAT NAMES A STALE `.bend:NN`, MAY BE
CORRECTED -- IT IS A PAYLOAD NO COMPUTATION READS").

## THE COMPILE TOKENS

`.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>`, ONE `bend` at a
time (the sum-precondition: the largest of the 33 is `dtype.bend` at 683 MB in
`.agents/slop/peakrss/census.rows`, and 33 x 683 MB is far over 60% of `hw.memsize`,
so they are run SEQUENTIALLY, not in parallel).

**33 of 33: `WITHIN-LIMITS`.** rc=0 for the two biggest (`uop/ops.bend`, `dtype.bend`).

## THE PLANT

`.agents/slop/bendcite-unclaimed1/plant.py`. A TEXT EDIT on a COPY of the port tree on
disk (NEVER `git show HEAD:`), and a BYTE-IDENTICAL control copy of the SAME snapshot.

```
PLANT control : {'RESOLVES': 1031, 'WRONG-LINE-BY-BLOCK': 116, 'AMBIGUOUS': 19, 'UNCLAIMED': 60, 'WRONG-LINE': 1, 'OUT-OF-CORPUS': 9}
PLANT the pointer moved is tinybendygrad/dtype.bend:840 -> helpers.bend:2328, and the construct it names is `cdiv_i64` declared at tinybendygrad/helpers.bend:2328; 1 line(s) are inserted above it
PLANT control : RESOLVES  (the pointer holds)
PLANT moved   : WRONG-LINE
PLANT moved   : {'RESOLVES': 1016, 'WRONG-LINE-BY-BLOCK': 116, 'AMBIGUOUS': 19, 'WRONG-LINE': 11, 'UNCLAIMED': 65, 'OUT-OF-CORPUS': 9}
PLANT twin    : reproduces the control exactly (byte-identical)
PLANT OK: a text edit that moves the construct makes the re-pointed pointer stale, and a byte-identical copy does not
```

**THE PLANT IS DISCOVERED, NOT NAMED**: the pointer it moves is the first `RESOLVES` row
in the slice's own files whose `symbol=` names a construct the target declares AT the
cited line. **THE EDIT INSERTS CODE IMMEDIATELY ABOVE THE `def`**, because a construct's
SPAN includes the comment run above it -- an insertion at the TOP of the file only
shifts the declaration and the pointer stays INSIDE the span. MEASURED: with the
insertion at the top of the file the plant did NOT go red; with it immediately above
the `def` it does.

## WHAT WAS NOT FIXED, AND WHY

* **THE TREE-WIDE `WRONG-LINE` (1) IS `nn/mnist_cnn.bend`'s** -- not mine, and dirty in
  another unit's working copy.
* **THE 60 REMAINING TREE-WIDE `UNCLAIMED`** are all in files this slice does not own.
* **`gates/bendcite-gate.py`'s ALIAS ORDERING DEFECT** (69 of 170 files have a `None`
  alias) is REPORTED, NOT FIXED: the brief says do not edit a gate, so the workaround
  is the unaliased `symbol=` name.
* **`gates/bendcite-gate.py`'s `SYMBOL_FIELD` REGEX ALLOWS ONE DOT**, so a construct
  named `mm.bin.and_int.mask.go` is truncated to `mm.bin` and cannot be named. The
  honest target for that claim was `ended_of` (`uop/fold.bend:2805`), which IS the
  construct that implements `UOp.ended_ranges`.
* **THE `D.refuse(...)` PAYLOADS THAT NAME A NON-STALE `.bend:NN`** were given the
  `symbol=` field anyway (that is a code-string edit, which the brief's exception
  covers because the alternative was a row the gate cannot check at all). The 9 files
  are counted as NOT COMMENT-ONLY above.
