# The `UNCLAIMED` slice -- 201 rows in 33 files, and what the fix IS.

MEASURED 2026-10-28 against `HEAD` `c49a51616`. The slice is
`/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unclaimed1.rows`.

## WHAT THE CLASS IS

`gates/bendcite-gate.py` measures the port's own `.bend` -> `.bend` LINE citations.
`UNCLAIMED` means the pointer RESOLVES and lands in the file, but the citing text
names NOTHING the target holds IN CODE -- so there is no claim to falsify.

MEASURED: **ALL 201 rows** have the same `why`:
`the citing text names [...] and <target> DECLARES none of them, so there is no
construct for the pointer to point at`.

## THE DURABLE FORM, AND THE RULE THE GATE ENFORCES

`symbol=<name>` next to the citation. The gate's `_holds` accepts a row iff the
TARGET FILE DECLARES `<name>` and the cited line IS the declaration or is INSIDE
its span (the span includes the doc-comment run above the `def`).

**⇒ SO THE CITED LINE MUST BE THE CONSTRUCT'S DECLARATION LINE.** A citation into
free comment space (between two `def`s, or inside a `TODO(pN)`/`WALL(p3)` block)
has NO construct to name, and `symbol=` there is a FAIL.

## THE ALIAS TRAP -- MEASURED, AND IT IS A GATE DEFECT

`Corpus._scan` computes `self.aliases` in the SAME loop that fills `self.bodies`,
so an import whose TARGET has not been scanned yet resolves to `None`.
`os.walk` visits `schedule/` before `uop/`, so **69 of 170 files have a `None`
alias** (MEASURED: `schedule/indexing.bend` -> `{'H': ..., 'O': None}`).

`strip_alias` returns the token UNCHANGED when the alias is `None`, so a claim
written `O.GroupOp.movement` never resolves against `uop/ops.bend`, which declares
`GroupOp.movement`.

**⇒ THE WORKAROUND: WRITE THE `symbol=` WITH THE UNALIASED DOTTED NAME.**
`symbol=GroupOp.movement`, NOT `symbol=O.GroupOp.movement`.
MEASURED: `uop/ops.bend:504 symbol=GroupOp.movement` -> `RESOLVES`.

**⇒ THE GATE IS NOT EDITED.** The defect is reported, not fixed here.

## THE NEAREST-PRECEDING BINDING

`gates/bendcite-gate.py`'s `_tokens` adds EVERY `symbol=` ON THE LINE to EVERY
citation on that line. MEASURED on a two-citation line:
`a.bend:713 symbol=cr_in a.bend:100 symbol=nope` -> the `:100` row is judged with
the token set `{cr_in, nope}` and goes `WRONG-LINE`.

**⇒ SO A LINE THAT CARRIES MORE THAN ONE CITATION MUST CARRY MORE THAN ONE
`symbol=`, AND EVERY `symbol=` ON IT IS A CANDIDATE FOR EVERY CITATION ON IT.**
The safe form is one citation per line.

`gates/todo-cite-gate.py` binds the nearest-preceding `symbol=` to a citation and
requires the symbol to be DECLARED by the target at the pin
(`WRONG-SYMBOL` otherwise). **⇒ A PORT `symbol=` MUST NOT SHARE A LINE WITH A
`.py` CITATION** -- it would bind to the `.py` one and fail.

## THE COUNTS, MEASURED ON THE LIVE TREE

`gates/bendcite-gate.py --rows OUT.rows`, `HEAD` `c49a51616`:

| verdict | tree |
|---|---|
| RESOLVES | 737 |
| UNCLAIMED | 408 |
| WRONG-LINE-BY-BLOCK | 120 |
| AMBIGUOUS | 19 |
| OUT-OF-CORPUS | 10 |
| WRONG-LINE | 3 |

THE 201 SLICE ROWS ARE ALL STILL `UNCLAIMED` IN THE LIVE TREE (MEASURED), AND MY
33 FILES HOLD **282** `UNCLAIMED` ROWS -- the slice's 201 plus **81** that a
LATER COMMIT ADDED (prose pointers like `nn/layers.bend:530 nn_linear` with NO
`symbol=`), all of them in MY files.
