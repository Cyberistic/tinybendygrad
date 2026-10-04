# STAGE 2 — THE FIX, AND ITS MULTISET PROOF

Fixer: `.agents/slop/nvdup/nvdup-fix-nv.py` (16 text-asserted hunks, `--check` writes nothing,
counts measured by RUNNING the patched source in `$TMPDIR`).
Gate/proof: `.agents/slop/dup/dup-gate.py --compare`, **imported, not forked**.

## 1. THE ONE RULE, AND WHERE IT STOPS

| the two sites | fix |
|---|---|
| both CALL CPython and agree | delete the later one |
| one TYPES the answer | delete the typed one |
| ask CPython two DIFFERENT questions | **delete neither — report both `file:line`** |

The third row is `nv_reloc_bad_n`, and the resolution of it is in Stage 1 §5: the site deleted
is the one whose subject is a helper defined in the oracle itself.

## 2. THE 27, ONE HUNK EACH, WITH THE SITE PAIR

| # | name(s) | site A | site B | why the deleted one |
|---|---|---|---|---|
| 1 | `nv_copy_nsteps_4294967295` | **`:296`** | **`:296`** | ONE line: `2*STEP-1 == 4294967295` with `STEP == 1<<31`, so the tuple names one number twice |
| 1 | `nv_reloc_kind_n` | `:692` typed `3` | `:1222` `len(DT)` | the file's own rule at `:1219` — "a row that prints a literal … is the shape of a test that cannot fail" |
| 3 | `nv_reloc_msg_0/3/100` | `:701` typed `"unknown NV reloc %d"` | `:1156` `str(_e)` | CPython's own raise text wins |
| 2 | `nv_reloc_bad_n`, `nv_reloc_bad_refused` | `:719-721` | `:1156-1162` | the `reloc_fold` row has no upstream subject; the refusal is then CPython's caught exception |
| 2 | `nv_launch_ok_1024_1024`, `_1024_8192` | `:756` folds `(_p,1,1)` | `:757`/`:760` fold `(32,32,1)` | **TWO FIXTURES, ONE NAME, answers that COINCIDE** — drop the colliding tuple members |
| 1 | `nv_bpt_1_48428` | `:878` `_bpt(32,48,4)` | loop `("1_48428",1,48,4)` | same call; the loop's fixture scales |
| 5 | `nv_errstr_0/2/8/999/4096` | `:379-380` | `:980-981` | both call `get_error_str`; delete the foot copy |
| 3 | `nv_paccess_0/2/4` | `:385-387` | `:986/988/990` | the foot block's `1/3/8/9/10` are unique to it and stay |
| 9 | `nv_iowr_*` | `:426-428` | `:437-439` | the file's own `:420-425` said the two tuples were the SAME 9 pairs |
| **27** | | | | + **4 dead arms**, which cost 0 measurements |

## 3. THE MULTISET PROOF — from the committed gate, not a re-implementation

```
$ .venv/bin/python .agents/slop/dup/dup-gate.py --compare \
      .agents/slop/nvdup/nv-oracle-BEFORE.txt .agents/slop/dup/lanes/…ops_nv.bend.oracle0.txt
ROWS       574 -> 547 lines; 574 -> 547 read; 547 -> 547 distinct names -- EQUAL distinct counts is
           the collision check: a rename created no name
VALUES     same multiset: False   distinct 234 -> 234   only in BEFORE []   only in AFTER []
VALUE SET  identical: True   instances 574 -> 547 (a duplicate fix removes INSTANCES, so the
            multiset may differ while the set may not)
DUPLICATES 27 -> 0 name(s) printed more than once, COUNTED FROM THE LINES and not from `rows()`'s
           dict (which has already overwritten them): none
LOST       27 -> 0 measurements unreachable by any name
RENAME     0 pair(s); 547 name(s) on the BEFORE side have no partner
BYTES      sha256(nb) 0df379b30cd8 -> 92c9e3a8e135   CHANGED
AUDIT OK -- no name is printed more than once
```

Read as five claims, because it is five:

1. **547 → 547 distinct names.** A rename created no name; `nvdup-fix-nv.py` also prints
   `names LOST entirely: []   names GAINED: []`, which is the stronger form.
2. **`VALUE SET identical: True`, both `only in` lists empty.** No answer moved.
   `same multiset: False` is the EXPECTED answer — a duplicate fix removes surplus *instances* —
   which is why the set question is asked separately.
3. **27 → 0 duplicates, 27 → 0 lost**, counted from the LINES.
4. **`RENAME 0 pair(s)`.** Nothing was renamed, so the citation list below is a report and not a
   prerequisite.
5. **`BYTES CHANGED`.** A fix that did not change the bytes changed nothing.

## 4. THE BYTE DIFF OF THE ORACLE'S OWN LANE TEXT — 27 deleted, 0 added

```
$ diff nv-oracle-BEFORE.txt …ops_nv.bend.oracle0.txt
109d108
< nv_copy_nsteps_4294967295=2
199,204d197
< nv_iowr_1280_2=3305129474
...
475d448
< nv_paccess_4=WEAK
deleted=27   added=0
```

**Only `deletions`, on the lane text, even though three hunks were REPLACEMENTS** — `:296`,
`:755` and the `:420-425` comment.  A replacement on a *fixture list* removes an instance and a
replacement on a *comment* moves no row at all, so the printed lane loses lines and never gains
one. **That is the load-bearing half of the proof: not one answer moved.**

The source diff is `1227 -> 1207` lines: **20 deleted, 3 replaced, 0 added.**

## 5. THE CITATION CENSUS — every file that cites something this edit touches

**No row NAME was created, destroyed or renamed**, so no citation *can* break.  The census is
printed anyway because a rename with an unmeasured citation list is how a fix silently un-gates a
lane, and the two cases are indistinguishable from the outside.

The hazard that is real here is different: **citations to `nv-oracle.py` BY LINE NUMBER**, which
this edit shifts.  Measured over the whole tree, excluding my own directory:

| file | cites | after the edit | |
|---|---|---|---|
| `.agents/TODO.md` | `:338-339` | `:338-339` | OK |
| `.agents/slop/dup/stage2-classify.md` | `:338-339` `:380` `:1162` | `:338-339` `:380` **`:1144`** | OK (shifted) |
| `.agents/slop/dup/stage3-multiset.md` | `:338-339` `:380` | unchanged | OK |
| `.agents/slop/notes/bend2-constraints.md` | `:688` `:417-420` | **`:684`** `:417-420` | OK (shifted) |
| `.agents/slop/pin-tree-oracle-report.md` | `:149` | `:149` | OK |
| `.agents/slop/reader-fork-census.txt` | `:29` | `:29` | OK |
| **`.agents/slop/dup/REPORT.md`** | **`:720`** | **GONE** | **STALE** |
| **`.agents/slop/dup/stage2-classify.md`** | **`:719-721`** | **GONE** | **STALE** |

**Both stale citations are in `.agents/slop/dup/**`, which is DO-NOT-TOUCH, and they are stale in
the right direction** — they describe a defect this unit closed, so they are a record of the
before.  They are reported, not edited.

`stage3-multiset.md` §7's "FOUND AND **NOT** FIXED" table is now stale for the same reason: its
`ops_nv` rows (`27 names … .agents/slop/nv-oracle.py:380/981, 428/439, …`) name 10 of the 16
hunks and describe them as open.

## 6. THE TREE'S OWN GATE, from an instrument with no part in this fix

```
$ .venv/bin/python .agents/slop/rebase-gate.py --port tinybendygrad/runtime/ops_nv.bend
  cause=- [OK]
  CAUSE: 600 shared row name(s) across 3 lane pair(s), every one agreeing
    rows interpreted=600    rows native=600    rows cpython:nv-oracle=547
  24497e96ddeb  207413B  tinybendygrad/runtime/ops_nv.bend
  ⚠ 1 of 4 closure file(s) CHANGED WHILE THIS LANE RAN: tinybendygrad/helpers.bend
TALLY UNCHANGED=1
```

**`UNCHANGED`, and `rows cpython:nv-oracle=547`** — GUARD 1 is an ABSOLUTE count (the usb unit's
lesson), it read 574 before, and it is **satisfied rather than tripped** because the baselines
key on the **PORT**, and the port is byte-identical:

```
$ shasum -a 256 nv-port-BEFORE.txt …ops_nv.bend.port.txt
f9b565af8ceabfee9df8a80203a4a19def955ec4e2539055ca018517a40e21de   (BEFORE)
f9b565af8ceabfee9df8a80203a4a19def955ec4e2539055ca018517a40e21de   (AFTER)
```

**THE GATE IS STILL RED ON THIS LANE**, `VERDICT: BROKEN (DUPLICATE NAME)` rc 1, on the PORT's
11 — Stage 3.  And the closure-digest line says `helpers.bend` moved under the run, so its counts
are lower bounds; that is its own text and it is quoted rather than smoothed over.

## 7. THE FIXER CAUGHT ITS OWN BAD HUNK BEFORE WRITING

The first `--apply` of the `_smemcfg` hunks left

```python
try:
except ValueError as _e:
```

and `nvdup-fix-nv.py:run()` raises `SystemExit` on a non-zero oracle exit, so `IndentationError`
was reported and **nothing was written** — the file was still the pre-fix text and the census
still read 27.  Recorded because the shape — an expectation right about the intent and wrong
about the text — is what `agent-core.md`'s table of hand-typed `py=` values is made of, and
because a fixer that writes a broken oracle and reports success is worse than no fixer.

## 8. REPRODUCE

```
.venv/bin/python .agents/slop/nvdup/nvdup-fix-nv.py --check          # runs BOTH oracles, writes nothing
.venv/bin/python .agents/slop/nvdup/nvdup-fix-nv.py --apply          # backup at .agents/slop/nvdup/nv-oracle-PREFIX.py
.venv/bin/python .agents/slop/dup/dup-capture.py --only ops_nv       # re-capture both sides
.venv/bin/python .agents/slop/dup/dup-gate.py --compare BEFORE AFTER  # the multiset proof
.venv/bin/python .agents/slop/dup/dup-gate.py --port P --oracle O     # the lane, rc 1 on the PORT's 11
```