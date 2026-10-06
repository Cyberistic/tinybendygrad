# arghalf -- **`loop`'s SECOND HALF IS NOT A FIELD. IT IS A MISSING CONDITIONAL, AND THE
# `?` NEVER MASKED IT.**

`.agents/slop/arghalf/`, 2026-10-06. Owns `tinybendygrad/uop/ops.bend` and this directory.
**NOT COMMITTED, AND THE FIX IS NOT IN `ops.bend` -- see §1.** Everything below is measured
on a frozen tree (§0) and read by verdict TOKEN, never by exit code.

---

## 1. THE HEADLINE, AND IT CONTRADICTS THE BRIEF IN TWO PLACES

**The brief says the remaining `arg` diff is a 4TH `CallInfo` FIELD, and that
"THE FIELD DELETE IS ALREADY DONE IN `fold.bend`". BOTH ARE FALSE, MEASURED:**

1. **THE FIELD DELETE IS NOT DONE IN `fold.bend`.** `fold.bend:1152-1155` reads the field
   TODAY:
   ```
   def call_dt(arg: O.Arg) -> S.Dt:
     match arg:
       case O.ACall{ci}: O.CallInfo.dtype(ci)
   ```
   and `ops.bend:1057` still declares it. `630d4a889` closed a DIFFERENT wall
   (`call_ds.go`'s outer `None`, `fold.bend:1170-1171`). The field is untouched.
2. **THE REMAINING DIFF IS NOT THE FIELD. IT IS THAT THE PORT'S RENDERER IS
   UNCONDITIONAL WHERE CPYTHON'S IS NOT.** The pin's `__repr__` is
   `", dtype=...)" if self.dtype is not dtypes.void else ")"`
   (`pin ops.py:1403-1404`), i.e. **the dtype slot is printed only when the dtype is
   non-void.** `graphcmp.bend:300` prints it unconditionally.

**SO THE FIX IS ONE `match` ARM IN `.agents/slop/graphcmp.bend` -- A SETTLED, COMMITTED
FILE THAT IS NOT THIS UNIT'S.** It is a **NARROWING** (§4), it closes `loop` completely
(§5), and **it does not require the field to be deleted at all** -- which is why deleting
the field, the shape everyone reached for first, was never going to be the right move.

### 1a. WHY THE FIELD DELETE LOOKED LIKE THE ANSWER, AND WHY IT IS NOT

Deleting `CallInfo.dtype` also makes the row agree -- it makes the port's renderer agree
with `graphcmp.py`'s. **That is a coincidence of two hard-coded strings, not a rule.**
Three measurements separate them:

| | pin `ad117c928^` | HEAD |
|---|---|---|
| `CallInfo.__annotations__` | `[grad_fxn, name, precompile, precompile_backward, aux, **dtype**]` | `[grad_fxn, name, precompile, precompile_backward, aux]` |
| `repr` of a **void** `CallInfo` | `CallInfo(None, 'hcq_fence', False, False)` | `CallInfo(None, 'hcq_fence', False, False)` |
| `repr` of an **i32** `CallInfo` | `CallInfo(None, 'hcq_fence', False, False, dtype=dtypes.i32)` | **no such value** |
| `__reduce__` 5th slot | `dtypes.void` | `None` |

(`pin-tree/` + `reprpin.py`/`cargpin.py`, run against both trees.)

**THE PIN HAS THE FIELD AND PRINTS IT. THE PORT HAS THE FIELD AND PRINTS IT
UNCONDITIONALLY. THE FIX IS TO PRINT IT WHEN THE PIN PRINTS IT.**

**AND `graphcmp.py` IS ON THE HEAD SIDE OF IT, WHICH IS WHY THE ORACLE "AGREED" WITH A
DELETE.** MEASURED, `cargpin.py` against BOTH trees:
`graphcmp.py:508`'s `carg` CALL arm returns **`'cI(shcq_fence,b0,b0)'` ON BOTH** -- it is
a hand-written three-slot string that never reads `x.dtype`, so it cannot tell the pin
from HEAD. **A HAND-WRITTEN SPELLING IS NOT EVIDENCE FOR A TYPE CHANGE** (§7).

---

## 2. `loop` AND `lin`, FROM THE DRIVER, AFTER `630d4a889`

`gcmp.bend <graph>` on the frozen tree, vs `graphcmp.py emit --side py --graph <graph>`.
**NOT read from `runs/graphcmp/D`; `checks/differ.py` was NOT run.**

```
loop   bend  row 25:  3:i25 4:CALL 4:void 1:R 2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid) 18:n(i23,i24,i24,i24)
       py    row 25:  3:i25 4:CALL 4:void 1:R 2:i0 1:N 20:cI(shcq_fence,b0,b0)       18:n(i23,i24,i24,i24)
       => ONE chunk differs. 24 of 25 rows BYTE-IDENTICAL.  `?=0/2` -- the dtype/shape
          columns now READ `4:void` and `1:R`, so `630d4a889` closed the FIRST half.

lin    bend  row 46:  3:i46 4:SINK 4:void 1:R 2:i0 2:i1 22:kI(sr_4_5_3,n(q),N,i0) 6:n(i45)
       py    row 46:  3:i46 4:SINK 4:void 1:R 2:i0 2:i1 66:kI(sr_4_5_3,n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))),N,i0) 6:n(i45)
       => ONE chunk differs. 45 of 46 rows BYTE-IDENTICAL.  UNCHANGED by this unit.
```

**`lin`'s DIFF IS `66` vs `22` = A PAYLOAD, AND THE PORT IS RIGHT TO REFUSE IT.** The py
side prints an `Opt` dataclass's fields; `graphcmp.bend`'s `opts` prints one `q` per
option because the port holds `List<&2, U32>` and cannot read an `Opt`. `AFlags`/
`List<&2,OPT>` would fix the TYPE, **not the RENDER**, and the renderer is the other
settled file. **`lin` IS NOT CLOSEABLE BY THIS UNIT AND WAS NOT TOUCHED.**

---

## 3. `ops.bend:939` AND `:1057` IN FULL, AND THE CORRECT TYPE FOR EACH

### `:939` -- `KernelInfo` (the `lin` half; NOT this unit's to land)
```
type KernelInfo is Data:
  KernelInfo{name: String, applied_opts: List<&2, U32>, opts_to_apply: Maybe<&2, List<&2, U32>>, beam: U32}
```
CORRECT TYPE: `applied_opts: List<&2, OPT>`, `OPT` already exists at
`codegen/opt/postrange.bend:159`. **BUT `postrange.bend:116` imports `../../uop/ops.bend`,
so `ops.bend` CANNOT import it back: `OPT` MUST MOVE DOWN FIRST**, which is
`postrange.bend` + `search.bend` + `heuristic.bend` -- none of them this file's.
`axis: int|None` STAYS UNSPELLABLE: `OPT{op, axis: U32, arg: OPTARG}` cannot hold a
`Maybe`, and `postrange.bend:163-169` says so. **NAMED, NOT WIDENED.**
**DOES A `List<&2,OPT>` NARROW? NO -- IT WIDENS `KernelInfo`'s spellings from `U32`s to
real options, so `ops.bend`'s own note at `:929-931` ("`KernelInfo.of().applied_opts` is
EMPTY and no port file ever writes a non-empty one, so `render.bend:655`'s reading is
UNVERIFIED") says the field is currently DECORATION.** Widening decoration into structure
is not a narrowing, and this is why the third table in the brief is right to be cautious.

### `:1057` -- `CallInfo` (the `loop` half; **KEEP THE FIELD**)
```
type CallInfo is Data:
  CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool, dtype: S.Dt}
```
CORRECT TYPE: **UNCHANGED.** The field is right; the pin has it; `fold.bend:1154` reads it
as the pin's `ops.py:134` (`arg.dtype if isinstance(arg, CallInfo) else dtypes.void`)
reads it. **THE DEFECT IS IN `graphcmp.bend:300`, NOT IN THIS DECLARATION.**
**THE FIELD DELETE IS ALSO A REFUSAL IN ITS OWN RIGHT:** MEASURED on a 3-field record,
`bend` answers `SOME PROOFS FAIL` / `a C3 pattern with 3 fields` (`arity.bend`) -- **record
patterns bind POSITIONALLY and the arity must match exactly**, so the delete costs a
4-binder rewrite at every one of the 9 sites in §8 and cannot be done as a type-only edit.

---

## 4. IS THE FIX A NARROWING? MEASURED, NOT ASSERTED — `probe.bend`, SIX SHAPES, BOTH RENDERERS

`.agents/slop/arghalf/tree/drivers/{two,one}/probe.bend` calls `gcmp.bend`'s OWN
`callinfo` on six `CallInfo`s. `two/` is the pristine renderer, `one/` is patched.

| shape | pristine | patched | moved |
|---|---|---|---|
| void, named | `cI(shcq_fence,b0,b0,Dvoid)` | `cI(shcq_fence,b0,b0)` | **YES** |
| void, anon | `cI(N,b0,b0,Dvoid)` | `cI(N,b0,b0)` | **YES** |
| i32, named | `cI(sf,b0,b0,Di32)` | `cI(sf,b0,b0,Di32)` | no |
| weakint, named | `cI(sf,b0,b0,Dweakint)` | `cI(sf,b0,b0,Dweakint)` | no |
| u32, precompile | `cI(N,b1,b0,Du32)` | `cI(N,b1,b0,Du32)` | no |
| f16, backward | `cI(N,b0,b1,Df16)` | `cI(N,b0,b1,Df16)` | no |

**EXACTLY THE TWO VOID ROWS MOVED; ALL FOUR NON-VOID ROWS ARE UNMOVED.** A fix that
dropped the slot UNCONDITIONALLY would have produced 3 slots for i32/weakint/u32/f16 too,
which is wrong against the pin AND wrong against HEAD (where the field does not exist, so
`dt(cdtype)` renders a `Dvoid` CPython cannot produce). **That is what makes this a
narrowing rather than a fit: it accepts strictly LESS, and the thing it stops accepting is
a spelling the pin's own `repr` refuses.**

**AND THE ANSWER TO "WHAT ELSE WOULD A `List<&2,Bool>` NOW ACCEPT" FOR `flip`, WHICH WAS
ASKED AND IS NOT THIS UNIT'S FIX: `ATuple` would then hold `(0,1)`,`(1,0)`, `(True,False)`
INTERCHANGEABLY -- so `PERMUTE`/`UNSHARD` (really ints) and `FLIP` (really bools) become
ONE arm and the port can hold `UOp(Ops.PERMUTE, src, (True, False))`, which CPython
REJECTS. A SEPARATE `AFlags{fs: List<&2,Bool>}` is right, and `ops.bend:1080-1090`
already names the five sites (`fold.bend`'s `order_arg`, `schedule/prepare.bend:277`,
`mixin/movement.bend:993` and `:1533`, `graphcmp.bend`'s `g_flip` + one `argstr` arm).**

---

## 5. COMPOSITION — **THE FRACTION**, ON A FROZEN TREE, BEFORE AND AFTER

`census.sh` runs all **25** corpus graphs through one renderer, serially (`bend`'s
precondition is the SUM of peak RSS, so no two at once), on `tree/` with
`tree/tinybendygrad/` re-synced to live and `one|gcmp.bend` the only variable.
CPython's rows come from `graphcmp.py emit --side py` per graph.

| | port rows | rows agreeing with CPython | fraction |
|---|---|---|---|
| **BEFORE** | 336 | **310** | **0.9226** |
| **AFTER** | 336 | **311** | **0.9256** |
| `loop` before | 25 | 24 | 0.9600 |
| **`loop` after** | **25** | **25** | **1.0000** |
| `lin` before AND after | 46 | 45 | 0.9783 |

**THE PORT-SIDE BLAST RADIUS IS 1 ROW OF 336 ON 1 GRAPH OF 25** — `24 of 25 byte-identical`,
`loop` differing by exactly 1 line. Re-run against the FRESH `ops.bend` (§0b): **25 of 25
byte-identical**, so the concurrent edit moved nothing this unit measures.

**THE PRIOR CAVEAT IS REPEATED, NOT RESOLVED:** *"the other graphs are byte-identical"
says THE PORT MOVED NOTHING ELSE -- it is NOT a statement that 24 graphs AGREE, and the
`0.9226 -> 0.9256` is the number that is the differ's business, not mine. This unit did
not run `checks/differ.py` and did not regenerate `runs/graphcmp/D`.** The four
`COUNT-MISMATCH` graphs (`allred` 9/18, `cdiv` 10/18, `flip` 6/7, `late` 12/18) are the
ones `disagree-gate.py:70` already classes `SUBSTITUTED`/`NOT A ROW`: **the port's row
count and CPython's are not the same denominator, so they cannot be scored row-for-row,
and they are reported as counts rather than as 0/N.**

---

## 6. THE THREE COUPLINGS, RE-READ AT TODAY'S LINE NUMBERS

1. **`graphcmp.bend:300` RENDERS THE FIELD UNCONDITIONALLY.** `def callinfo(ci: O.CallInfo)`
   at **298**, the `case O.CallInfo{cname, precompile, precompile_backward, cdtype}` at
   **300**, the `dt(cdtype)` at **301**. Its own comment at **292-297** says "the tree
   this gate reads has dropped the `dtype` one" -- **TRUE OF HEAD, FALSE OF THE PIN**, and
   it is the comment that made the delete look right. **NAME ONLY, NOT EDITED.**
2. **`graphcmp.bend:1004-1005` `g_loop` HARDCODES `O.CallInfo{Some{"hcq_fence"}, False{},
   False{}, S.void()}`** -- still the upstream source of the void, still why node 25 is
   void, and **AFTER `630d4a889` it no longer drives `?`.** SETTLED AND COMMITTED
   (`f541da0f1`, `80a2fbc0c`). **NAME ONLY.**
3. **`disagree-gate.py`'s CITES LINE 93 IS `("tinybendygrad/uop/fold.bend", 1144,
   "CallInfo.dtype")` -- AND `fold.bend:1144` TODAY READS `case _: None{}  #
   assert isinstance(arg, ParamArg)`, NOT `CallInfo.dtype`.** The reader moved to
   **`fold.bend:1154`**. **SO THE GATE IS RED ON A MOVED CITATION AS WELL AS ON THE PIN**
   -- and its `:18-22` doctrine ("closing a defect makes THIS gate fail instead of quietly
   making the prose wrong") is what makes the second failure visible. Also stale:
   `CITES` line 91 pins `ops.bend:1010` and `CallInfo` is at **1057**; line 94 pins
   `ops.bend:919` and that is now a COMMENT line, the field being at **939**. **NAME ONLY.**
   **THE THIRD COUPLING THE BRIEF NAMES -- `spec.bend`'s `:412`/`:1092` citing a rule
   "ADDED at `6f4bfde23` AND REMOVED at `ad117c928`" -- IS ABOUT A DIFFERENT THING AND
   IS NOT A CONSTRAINT ON THIS FIX: `ad117c928` IS **OUR OWN** COMMIT** ("rebase B1: 17
   files, the tree imports again"), 2026-10-02, NOT UPSTREAM, and it re-vendored 16
   `tinygrad/` files including `ops.py` (130 lines) and `spec.py` (19). `spec.bend:409`
   still reads `Some{O.CallInfo.dtype(ci)}` and is unchanged by this fix. THE PORT'S PIN
   IS `ad117c928^`; MEASURED, `ops.bend:2699` NAMES `axis_id` AT `ops.py:502-508` AND ONLY
   THE PIN HAS IT THERE (`git show 'ad117c928^:tinygrad/uop/ops.py' | sed -n '502,508p'`
   = `return self.arg[0:-1]`; HEAD is `return self.arg[1:]` at 502). `git merge-base
   --is-ancestor ad117c928 HEAD` = YES.**

---

## 7. THE ROW THAT CANNOT DISTINGUISH TWO RULES, RE-CONFIRMED

`ops.py:130-132` at HEAD is `case Ops.CALL: return src[0].dtype` and `ops.py:386-388`
puts `Ops.CALL` in the **PASSTHROUGH** arm, `return self.src[0]._shape`. The pin's
`ops.py:134` is `arg.dtype if isinstance(arg, CallInfo) else dtypes.void` and its
`ops.py:337-338` is `return None if self.dtype is dtypes.void else ()`. **`fold.bend`'s
`call_dt`/`call_ds` are the PIN'S RULES, verbatim, and they are the port's because the
port is pinned.** MEASURED, on `loop`, `src[0]` is node 23, a SINK, so **all four readings
give `4:void 1:R`** -- the row cannot tell the pin's rule from HEAD's, which is exactly
why the fix here is in the RENDERER (where the two trees DO differ) and not in the dtype
rule (where they do not, on this graph). `Ops.INS` is the opposite case and the port is
right there: `ops.py:339-341` really is the line the port implements.

**AND `graphcmp.py:508`'s `carg` IS THE SAME TRAP ONE LEVEL UP: A THREE-SLOT STRING
HAND-WRITTEN FROM HEAD, WHICH ANSWERS THE SAME ON BOTH TREES. It agreed with the delete
for the wrong reason -- the same reason `fold.bend`'s own header says a pretty diff is
wrong ("a pretty diff over two graph printers compares the two PRINTERS").**

---

## 8. THE FIELD DELETE'S TRUE COST — 9 SITES / 7 FILES, RE-CENSUSED

`arity.bend` MEASURED: a 4-binder pattern on a 3-field record is `SOME PROOFS FAIL` /
`a C3 pattern with 3 fields`. So the delete is **not** a one-line type edit; it is a
positional-arity rewrite at every construction and every destructuring:

| file | lines | what |
|---|---|---|
| `uop/ops.bend` | **1057** (type), **1148** (`of`), **1507/1511/1515/1519** (4 accessors, one deleted), **1865** (`eq_callinfo`), **7089** (`sg.ci`), **7107** (`sg.arena`) | 9 sites |
| `uop/fold.bend` | **1154** (`call_dt`), **4944** (`rg_call`) | 2 |
| `uop/spec.bend` | **409** (`arg_call.go`) | 1 |
| `uop/render.bend` | **634** (`ci_named`), **637** (`ci_weak`) | 2 |
| `engine/jit.bend` | **1243** | 1 |
| `engine/realize.bend` | **1416** (`call_info`) | 1 |
| `.agents/slop/graphcmp.bend` | **300** (`callinfo`), **1005** (`g_loop`) | 2 |

**16 sites / 7 files. FOUR of the seven ARE NOT THIS UNIT'S** (`fold.bend` is fixed and
committed `630d4a889`; `spec.bend`/`graphcmp.bend` are named-not-mine; only `ops.bend`,
`render.bend`, `jit.bend`, `realize.bend` are reachable). **AND THE DELETE IS UNNECESSARY:
THE FIX IS 5 LINES IN ONE FILE AND `ops.bend:1057` IS ALREADY CORRECT.**

---

## 9. BYTE COUNTS, VERDICT TOKENS, PEAK RSS — **AND THE EMPTINESS CHECK**

```
$ .venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- ./bin/bend tinybendygrad/uop/ops.bend --check-only
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=210 MB (ceiling 2048)  1s  out=58B err=42B
ALL PROOFS CHECK
Use --verdict for mathematical validity.
```
**`ALL PROOFS CHECK`, NOT `SOME PROOFS FAIL`.** Read as the TOKEN **and** the stdout was
checked for emptiness: **58 B, 2 lines, sha of the stdout is not the empty string's.**
`helpers.bend` **130,719 B, NOT 0** (off limits, never opened by this unit).
`gcmp.bend` **91,132 B** pristine, **91,311 B** patched; **694 comment lines in BOTH, code
661 -> 665, i.e. +4 code lines.** `ops.bend` **414,792 B / 8,512 lines / 3,712 comment /
4,800 code.**

| run | token | peak |
|---|---|---|
| `gcmp.bend loop` pristine / patched | `WITHIN-LIMITS` | 572 / 571 MB |
| `probe.bend` pristine / patched | `WITHIN-LIMITS` | 402 / 390 MB |
| `ops.bend --check-only` | `WITHIN-LIMITS` | 210-350 MB (two runs) |
| 50 census builds, all 25 graphs x 2 renderers | `WITHIN-LIMITS`, **0 kills** | 457-710 MB |

**NO `KILLED-ON-MEMORY` AND NO `TIMED-OUT` IN 50 BUILDS**, against a 2,048 MB ceiling.
**THE STALE-EXE TRAP WAS HIT FOR REAL WHILE COLLECTING THESE NUMBERS:** a first RSS pass
redirected the child's stdout to `/dev/null` and `bend` answered `out=0B peak-RSS=32 MB`
on FOUR consecutive runs -- **32 MB IS NOT A `bend` BUILD, IT IS A BUILD THAT EMITTED
NOTHING**, and a reader counting rows without checking emptiness would have recorded
four DEAD LANES as four cheap passes. Every number in the table above comes from a run
that also wrote a non-empty row file. `timeout` is not installed; `rc=142` never seen.

---

## 10. THE THREE `disagree-gate.py` ROWS AND WHAT THEY SHOULD BECOME — **NOT LANDED**

`checks/disagree-gate.py` is **not this unit's file** and this unit did not edit it. Its
own `:18-22` doctrine says the gate edit lands in a SEPARATE commit, because a commit that
closes a defect and edits the gate that detects it is one in which the gate's failure is
unverifiable. **The brief's owner said they will land the gate edit; these are the rows.**

| row | today | becomes | why |
|---|---|---|---|
| **`loop`** | `row=25, fields=("dtype","shape","arg"), shape="WRONG SHAPE", fault="PORT"` | **`loop` LEAVES `PIN` ENTIRELY** -- not a narrowed row, an ABSENT one. Its first row becomes `row=None`. | `630d4a889` already killed the `dtype`/`shape` half (`4:void 1:R`, `?=0/2`); the `arg` half is the unconditional 4th slot. **AND NOTE: `lin`'s ONE `q` MATCH IS NOT AFFECTED**, so `graphs-disagree` goes **6 -> 5**, not 6 -> 4. |
| **`lin`** | `row=46, fields=("arg",), shape="WRONG SHAPE", fault="PORT"` | **UNCHANGED.** | `applied_opts: List<&2,U32>` at `ops.bend:939` still cannot hold an `Opt`, and the fix is not in `ops.bend`. |
| **`flip`** | `row=6, fields=("arg",), shape="BOTH", fault="HARNESS+PORT"` | **UNCHANGED**, and its cause should be REWORDED from "a 4th `CallInfo` field" to "the port's renderer prints a dtype slot CPython's repr suppresses". | It is a **HARNESS+PORT** row and this unit did not touch `flip`; rewording it inside the same commit that closes `loop` would put two claims in one unverifiable change. |

**AND TWO CITATIONS INSIDE `CITES` ARE ALREADY STALE, INDEPENDENTLY OF ANY FIX** (§6.3):
line 91 `ops.bend:1010` -> the field is at **1057**; line 92 `fold.bend:1144` -> the
reader is at **1154**; line 94 `ops.bend:919` -> that is now a **COMMENT** line, the field
is at **939**. **SO `disagree-gate.py` IS RED FOR TWO INDEPENDENT REASONS AND ONLY ONE OF
THEM IS THE PINNED DEFECT.** A gate edit that fixes the pin and leaves the citations stale
would still be red, and a reader would conclude the fix did not work.

---

## 11. WHAT COULD NOT BE SETTLED

1. **THE FIX ITSELF.** It is 5 lines in `.agents/slop/graphcmp.bend`, which is settled,
   committed, and **not this unit's**. **`ops.bend` NEEDS NO CHANGE FOR `loop` TO CLOSE.**
   The unit's own file is left untouched deliberately.
2. **`lin` IS NOT CLOSEABLE HERE AND WAS NOT ATTEMPTED.** `OPT` must MOVE DOWN out of
   `codegen/opt/postrange.bend` (which imports `ops.bend`, so `ops.bend` cannot import it
   back), the render is `graphcmp.bend`'s `opts`, and `axis: int|None` has no spelling.
   Three files, none of them this unit's.
3. **WHETHER THE PORT SHOULD EVENTUALLY MOVE OFF THE PIN.** `ad117c928` is our own commit
   and it moved `tinygrad/`; `ops.bend:1022-1055` argues the port is pinned and `HEAD`
   moved. **BOTH SIDES OF THAT ARGUMENT ARE IN FILES I DO NOT OWN**, and `AGENTS.md` itself
   records `ad117c928` as "an ancestor of HEAD that re-vendored 16 `tinygrad/` files and
   broke a pin the tree cites". **THE PORT'S ANSWER AT THE PIN IS CORRECT AND THE ORACLE'S
   ANSWER IS AT HEAD; WHICH ONE IS THE TARGET IS NOT A DECISION THIS UNIT CAN MAKE.**
4. **THE FOUR `COUNT-MISMATCH` GRAPHS** (`allred`, `cdiv`, `flip`, `late`) have different
   row counts on the two sides, so no row-for-row fraction exists for them; they are
   reported as counts. Whether the port's extra rows are substitution artefacts or real
   port nodes is `graphcmp.py`'s and `differ.py`'s question.
5. **`?` NOW HAS NO FIXTURE.** 0 of 336 rows on 25 of 25 graphs. The two-column `?`
   assertion is untestable, and per `loopfix/FINDINGS.md` §5 it must NOT move back to
   `sym`. **NOT RE-MEASURED HERE** -- this unit did not run `differ.py`.