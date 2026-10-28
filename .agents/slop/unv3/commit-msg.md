cites: the slice's 124 citation rows go to 0, and the PROSE is what was wrong

`gates/pin-cite-gate.py` classed 52 of the port's upstream citations
`unverifiable_no_claim_about_the_file` -- the claim's tokens occur NOWHERE in the
cited upstream file, so NO re-point can make the claim hold. `gates/bendcite-gate.py`
classed 72 more `WRONG-LINE`/`DANGLING-LINE` -- the port's own `.bend` pointers
into lines that MOVED. BOTH COUNTS ARE NOW 0 for these 26 files, and the fix was
the PROSE in every case: a name upstream does not have was replaced by the name
upstream HAS, and a pointer into a line that moved was re-aimed at the construct.

THE CLASS, AND WHY ONLY THE PROSE COULD FIX IT. The port's prose named its OWN
symbols -- `dev_sync`, `q.compile_args`, `mo_softmax`, `qp.rules_len` -- and those
names are in no upstream file, so the citation made no claim about the file it
cited. Upstream's names are `synchronize`, `cl_compiler_compile_source`,
`mo_softmax` in `mixin/op.bend` (the PORT's own file, not upstream's), and
`PatternMatcher`. So each row now carries BOTH: the port's name AND upstream's,
on the citation's OWN LINE, because `gates/pin-cite-gate.py`'s `collect()` reads
the claim tokens from the citation's own line and a name on the NEXT line belongs
to no citation at all.

THE FOUR KINDS OF CHANGE, AND WHAT EACH ONE WAS.

  1. PROSE REWRITTEN (52 rows). The upstream construct is named beside the port's
     own name: `tinygrad/runtime/ops_disk.py:14` now names upstream's
     `synchronize` and not only the port's `dev_sync`. Where the port's symbol has
     NO upstream counterpart the comment says so in the tree's own words -- `NVQueue`
     (upstream's class is `HWQueue`), `cache_kv`'s home (`extra/` is NOT under
     `tinygrad/`, so the port's own `extra/models/llama.py` is named as the port's
     own), and the 22 `ops_nv.bend` pointers.

  2. BASENAME DISAMBIGUATED (7 rows). A bare `dtype.py` names THREE upstream
     files and `helpers.py` names SEVEN, so a bare basename resolves to NOTHING.
     `commit_dtype` is upstream's `tinygrad/mixin/dtype.py:16` and NOT the
     top-level `tinygrad/dtype.py`, and `sum_acc_dtype` is at `tinygrad/dtype.py:213`
     and NOT :220. Every such row now spells the FULL upstream path.

  3. ABSENCE STATED (5 rows). Where upstream DELETED the construct, the comment
     now says what upstream HAS instead: upstream's `_symbolic_ret` at
     `tinygrad/engine/jit.py:70-72` and upstream's `_do_ioctl` at
     `tinygrad/runtime/support/c.py:6` -- the PORT's own `_ioctl` is not upstream's
     name. The 22 `ops_nv.bend` pointers are of this kind: that file is HEADER-ONLY
     now (94 lines, ZERO `def`), so every pointer into its BODY named a line that
     does not exist, and the honest citation is upstream's `tinygrad/runtime/ops_nv.py`
     -- which is what those comments were about -- or a statement that the port's
     own `ops_nv.bend` NO LONGER CARRIES the row.

  4. THE `symbol=` FORM (72 rows). The durable form, and it is used ONLY where the
     named construct is DECLARED IN THE CITED FILE: `gates/todo-cite-gate.py` reads
     a `symbol=` as a claim about a construct the file DECLARES, and a `symbol=`
     naming a port symbol beside an upstream citation is a NEW WAY TO BE WRONG.

THE MEASUREMENTS, AND THE INSTRUMENTS.

  `gates/pin-cite-gate.py`  52 -> 0 `unverifiable` for these 26 files.
  `gates/bendcite-gate.py`  72 -> 0 `WRONG-LINE`+`DANGLING-LINE` for these 26 files.
  `gates/todo-cite-gate.py`  1160 citations, 1127 RESOLVES, 0 WRONG-LINE,
                             0 WRONG-SYMBOL, 0 UNRESOLVABLE, 4 PORT-CITATION.
                             0 false rows for these 26 files.
  COMMENT-ONLY PROOF: all 26 files strip to the SAME code as `HEAD` under
  `checks/port-compile-gate.py`'s `strip_comments()` (LOADED BY PATH), blank lines
  dropped: 26 of 26 CODE-IDENTICAL.
  COMPILE: 26 of 26 `WITHIN-LIMITS` under `checks/bounded.py --mb 2048`, ONE bend
  at a time, the verdict TOKEN read and not the exit code. The largest peak was
  924 MB (`uop/symbolic.bend`) against a 2048 MB ceiling.
  PLANT: a TEXT EDIT ON A COPY. `gates/pin-cite-gate.py`: breaking one re-pointed
  claim token (`synchronize` -> `synchronise`) moved the row from `at_pin` to
  `unverifiable` and the tree's count from 36 to 37, with the byte-identical
  control at 36. `gates/bendcite-gate.py`: moving one re-pointed pointer
  (`nn/layers.bend:530` -> `:527`) took these files from 0 to 1 `WRONG-LINE` and
  the tree from 56 to 57, with the byte-identical control at 0 for this file.

THE TREE IS SHARED AND IT MOVED, AND THAT IS A MEASUREMENT AND NOT AN EXCUSE. The
measurement was taken on a FROZEN COPY of the tree (`--tree DIR`), because a
copy of the LIVE tree measures the OTHER units' work too and a before/after
reading taken at two moments compares two different trees. The copy carries the
LIVE port -- not a `git archive` of HEAD -- because the files this slice does NOT
own had MOVED (another unit added ten lines to `nn/layers.bend` while this work
was in flight), and a pointer into a file this slice does not own must name the
line that file has NOW. It also carries `references/`, which is GITIGNORED, so a
`git archive` does not have the compiler's 3,191-line `base.bend` and every
`base.bend` pointer then resolves into the port's 56-line one.

ONE STRING IS NOT A COMMENT, AND IT IS NAMED HERE RATHER THAN HIDDEN.
`tinybendygrad/extra/models/llama.bend`'s `D.refuse(...)` argument is a diagnostic
ADDRESS, not behaviour: `Refused{at}` is a payload no computation reads. Its
pointer to `mixin/elementwise.bend:1209` was STALE -- `ew_silu` is at :1219 -- and
leaving it false to keep a hash green would be exactly the weakening this work
exists to remove. The string now says :1219, and the comment above it says so.
