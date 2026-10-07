# SPINE — the port emitted no rows for any graph, and now it does

`.agents/slop/spine/`, 2026-10-06. Not committed. Owned: `graphcmp.bend`, this directory.
**`tinybendygrad/uop/ops.bend` and `render.bend` were read and left byte-identical to HEAD.**

## 0. THE COMPILER ERROR, CAPTURED, BEFORE AND AFTER

`00-before-bend-check.out` and `08-final-bend-check.out`, both via
`checks/bounded.py --seconds 900 --mb 2048 -- ./bin/bend .agents/slop/graphcmp.bend --check-only`.

    BEFORE  rc=1                        AFTER  rc=0
    SOME PROOFS FAIL                    ALL PROOFS CHECK
    Error:                              Use --verdict for mathematical validity.
    - expected : cases for              [bounded] WITHIN-LIMITS  peak-RSS=537 MB (ceiling 2048)  1s
      ../../tinybendygrad/uop/ops.AOpLit
    - observed : \{\}
    Location: argstr
    373 | def argstr(a: O.Arg, depth: U32) -> String:
    374>|   match a:
         |   ^^^^^^^^

**`ALL PROOFS CHECK` IS NOT THE ANSWER, SO THE FILE WAS CHECKED FOR EMPTINESS AFTER IT.**
`helpers.bend` is **130719 bytes** and `graphcmp.bend` **91132**, and the arm is at
`graphcmp.bend:404`. A `--check-only` that says `ALL PROOFS CHECK` over an empty file is
the trap `agent-core.md` records, and `helpers.bend` has been truncated to 0 four times here.

## 1. (a) OR (b)? **MEASURED BY TAKING BOTH. (a) WINS.**

`AOpLit` is spelled in **THREE** files, not one. MEASURED, and the second file was the
decider because the first measurement missed it — `grep -rn "AOpLit" --include='*.bend'`
needs quoting under zsh or the glob never expands and the search silently returns nothing:

| file | sites | in my grant? |
|---|---|---|
| `tinybendygrad/uop/ops.bend` | `:1030` taxonomy row, `:1079` constructor, `:1866`+`:1868` `eq_arg.AOpLit`, `:1965` dispatch | only "if the fix requires it" |
| **`tinybendygrad/uop/render.bend`** | **`:714` `arg_repr`** | **NO** |
| `.agents/slop/graphcmp.bend` | `argstr` | yes |

**(b) DOES NOT COMPILE.** Taken, it failed at `render.bend:714` — `07-option-b-bend-check.out`:

    - message  : a declared constructor (unknown: ../../tinybendygrad/uop/ops.AOpLit)
    714>|     case O.AOpLit{op}: O.Ops.name(op)

so (b) is **seven deletions across two files this work does not own**, to remove a payload
**MEASURED to appear in zero rows**: `grep -rh '5:PYLITERAL' runs/graphcmp/D/` → **0 hits**
on either side. It cannot change one byte of output. (b) then reverted; `ops.bend` and
`render.bend` verified byte-identical to HEAD afterwards.

**(a) IS ONE ARM.** `case O.AOpLit{op}: opx(op)`, and `opx` already existed. **The spelling
was not invented — it was already agreed.** `_carg`'s `isinstance(x, Ops)` arm
(`graphcmp.py:603`) returns `ATOMS["ops"] + x.name` and `ATOMS["ops"]` is `"O"`
(`graphcmp.py:324`), so:

    MEASURED  gc._carg(Ops.INDEX) -> 'OINDEX'      ==  opx -> "O" + name

**A SYMMETRY WAS RESTORED, NOT A NEW ONE INVENTED: the py side could already print this
value and the bend side had no arm for it.** No new atom, no new `COMPOSITE` opener.

## 2. THE TENSION `corpus24` AND `graphrestore` LEFT OPEN — IT IS NOT A TENSION

`graphrestore` §5 says PYLITERAL *IS* portable and is blocked by the missing arm.
`corpus24` says PYLITERAL is a **CORPUS GAP**. Both are true and they are about different
things: one is whether the port **can spell** the value, the other is whether **any graph
emits** one. Neither cancels the other, and **PYLITERAL IS STILL A PORT GAP** — a third,
separate one. `upat.py` mints **SEVEN** `PYLITERAL`s and `AOpLit` covers **ONE**:

| `upat.py` | payload | port type? |
|---|---|---|
| `:26` | bare `Ops` (`self.op[0]`) | **`AOpLit`** — the one this arm prints |
| `:25` | `frozenset(self.op)` | none |
| `:36` | `frozenset(self.match_dtype)` | none |
| `:43` | `frozenset(self.match_tag)` | none |
| `:39` | bare `DType` | none |
| `:44` | bare `AddrSpace` | none |
| `:29` | `self.arg` whole | none |

**`upat.py:25` IS NOT EXOTIC.** `UPat((Ops.INDEX, Ops.SHRINK), ...)` is all over this tree —
`renderer/isa/x86.py:154,329,331,436,451,473`, `renderer/nir.py:137,149,151,156`,
`renderer/cstyle.py:22,76`. So **`PYLITERAL` = 3 gaps: a CORPUS gap (no graph mints one), a
COMPILE gap (fixed here), and a PAYLOAD gap (1 of 7 modelled).** The first two being closed
is what this file does; the third is untouched and named.

**THE PORT'S OWN TABLE IS NOT STALE** — `ops.bend:1030-1033` cites `upat.py:26`, `:39`,
`:44`, `:29`, and all four lines say what it claims. Checked because this project has logged
nine stale-citation classes today; this one came back clean.

## 3. DOES THE PORT AGREE? **YES, ON 14 OF 16. THE OTHER 2 ARE THE ONES `WANT` PREDICTS.**

`03-diff-*.out`, one per graph, `# VERDICT:` present in every one. **`not-comparable=0`**

| graph | rows py/bend | verdict | | graph | rows py/bend | verdict |
|---|---|---|---|---|---|---|
| matmul | 18/18 | AGREE | | gate | 14/14 | AGREE |
| reduce | 7/7 | AGREE | | sym | 12/12 | AGREE |
| cast | 6/6 | AGREE | | lin | 46/46 | **DISAGREE** |
| buffer | 5/5 | AGREE | | loop | 25/25 | **DISAGREE** |
| sink | 2/2 | AGREE | | binblob | 19/19 | AGREE |
| range | 2/2 | AGREE | | group | 8/8 | AGREE |
| rangeflat | 2/2 | AGREE | | commute | 14/14 | AGREE |
| special | 2/2 | AGREE | | indexed | 7/7 | AGREE |

`runs/graphcmp/D/D1-verdicts.txt`: `all 16 graphs: verdict as expected (14 AGREE; lin and
loop DISAGREE, each with a named cause in the WANT comment above)`. **ZERO verdicts moved.**

**THE TWO DISAGREES ARE THE PREDICTED CAUSES, 1 NODE EACH, `field-mismatches=0`:**
- `lin` — SINK `applied_opts`: py `n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST)))` against
  bend `n(q)`, 1 of 46. The port's slot is `List<&2,U32>` (`ops.bend:978`); upstream's are `Opt`.
- `loop` — CALL: py `cI(shcq_fence,b0,b0)` + `dtype=void` against bend `cI(shcq_fence,b0,b0,Dvoid)`
  + `dtype=?`, 1 of 25. The port's `CallInfo` has a fourth field CPython's does not.

**REPRODUCIBLE: TWO INDEPENDENT `differ.py run`s, ALL 50 CANONICAL ARTIFACTS BYTE-IDENTICAL**
(`05-differ-run.out`, `09-differ-run-final.out`).

| | before | after |
|---|---|---|
| `graphs-agree` | **0** | **14** |
| `not-comparable` | **16** | **0** |
| `byte-identical` | — | **14** |
| `stable-failed` | **5 of 5** | **0 of 5** |
| `plants-disagree` | — | 7 of 7 |

## 4. `checks/corpus-figure.py` BEFORE AND AFTER

One line moves. `04-corpus-figure-before.out` / `10-corpus-figure-final.out`, both `EXIT=1`.

    - RUN HEALTH : **FAILED** -- 0 of 16 graphs agree, 16 not comparable.
    + RUN HEALTH : **FAILED** -- 14 of 16 graphs agree, 0 not comparable.

`CPYTHON-SIDE UNION : 60 of 77` is **UNCHANGED, and it had to be**: the script builds the
CPython side only (`checks/corpus-figure.py:71`), so it cannot see this fix at all.

**IT STILL EXITS 1, AND NOW FOR A DIFFERENT REASON — WHICH IS THE FINDING.**
`corpus-figure.py:78` demands `nc == 0 and agree == total`. `WANT` records `lin` and `loop`
as `DISAGREE` **on purpose**, with measured causes. **So this instrument cannot print `OK`
over a healthy run of this corpus: `agree` can never equal `total` while two graphs are
supposed to disagree.** That is the `not-comparable` error one level up — a health predicate
that cannot tell *"a graph did not run"* from *"a graph ran and disagreed"*, so it refuses a
run that did exactly what it was supposed to do. **NOT FIXED: not mine.** It needs
`agree + disagree == total`, or a read of the per-graph expected verdicts.

## 5. WHAT I COULD NOT SETTLE

1. **`oracle-selfcheck=# ORACLE SELFCHECK: FAIL` and `census-rc=rc=1`** in `D0-run-summary.txt`,
   unchanged by this fix. `.agents/slop/graphcmp-oracle.py` is not mine and I did not chase it.
2. **`checks/corpus-figure.py` never pins `DEV`** (graphrestore §6.2). It reads `METAL` here,
   so it says **60** where the differ's `CPU` says **61**. My whole §3 table is `DEV=NULL`,
   the differ's own `ENV` (`checks/differ.py:44`). Not mine.
3. **`checks/differ.py` `WANT` still iterates 16 hand-written names**, not `graphcmp.GRAPHS`
   (graphrestore §1). Nine graphs — `allred alu bit bw cdiv flip late move where` — are still
   never compared, and three of them (`allred`/`cdiv`/`late`) exist on neither side's
   `graphcmp.bend` fixture list. **Not fixed; another unit owns it.** Consequence: **`not-comparable=0`
   now means "all sixteen names in the table ran", not "the corpus was compared".**
4. **Restoring `g_allred`/`g_cdiv`/`g_late` into `graphcmp.bend`** (graphrestore §7, inert
   until now) is **NOT DONE** — out of scope for a spine, and `WANT` would not run them anyway
   until point 3 lands. `rows.pick3` has no arm for any of the three.
5. **The arm has no graph witness.** `AOpLit` matches zero rows today. Its justification is
   `upat.py:26` plus the compiler's own refusal to accept a 19-arm `argstr` over a
   20-constructor `Arg` — a source witness, not a test one — but nothing in the corpus
   exercises it, and this report does not pretend otherwise.

## 6. WHAT IS HERE

`00`/`08` the check-only pair · `02` 20 raw probe rows for `matmul` · `03-diff-*` the 16
verdicts · `04`/`10` corpus-figure before/after · `05`/`09` the two runs · `07` option (b)'s
compile failure. **No `.txt` written by this work**; `checks/no-txt.py` fails on 449
pre-existing files in `oracles/` (the sweep residue, not mine) and flagged **0** of mine.
