# loopfix -- THE TWO SURVIVING TWINS OF THE `?`/`R` CONFLATION, LANDED

`.agents/slop/loopfix/`, 2026-10-06. Owns `tinybendygrad/uop/fold.bend` and this directory.
**NOT COMMITTED.** Every number below is measured on a FROZEN substrate -- see §0.

---

## 0. THE SUBSTRATE WAS MOVING UNDER THE FIRST MEASUREMENT, SO IT IS FROZEN

`tinybendygrad/uop/ops.bend` is another unit's file and it was edited *while this unit
ran*: **407,671 B at 06:49**, **410,235 B at 07:01**, **410,516 B at 07:04**. It was
transiently UNCOMPILABLE across those minutes -- `fold.bend --check-only` answered
`SOME PROOFS FAIL`, `- expected : i / - observed : i (consumed more than once)`, at
`ops.bend:6871`, a line that does not exist in `fold.bend` at all. That is the hazard
`fold.bend`'s own header records ("`uop/ops.bend` … went transiently uncompilable three
times while this table was being measured"), and it is why **a before/after measured
against the live tree would have measured two different ports.**

So the whole comparison runs in `tree/`:

| what | how it is pinned |
|---|---|
| `tree/tinybendygrad/` | one `cp -R`; `sha256 7b6b849e…` `ops.bend`, `2f2cb93e…` `helpers.bend`, equal to the live files (`tree/00-frozen-shas.rows`) |
| `tree/…/uop/fold-old.bend` | `jj file show -r @-`, **385,810 B** = the live file's pre-edit size, so "before" is provably the committed file |
| `tree/…/uop/fold-new.bend` | this unit's `fold.bend`, sha-matched to the live file |
| `tree/…/uop/fold.bend` | which of the two is imported -- the ONE variable swapped between builds |
| `tree/drivers/one/gcmp.bend` | `graphcmp.bend` byte for byte, 91,132 B. Two levels deep because its own `import ./../../tinybendygrad/…` is relative to the FILE and the file is not editable |

---

## 1. THE FIX, AT `file:line`

`fold.bend:741-745` and `747-750` held `call_ds.go` and `ins_ds.shape` as two
byte-identical bodies, plus `ins_ds.pick` reaching one of them. **BOTH DELETED.**

`fold.bend:1112-1115` is new -- **one** def for the rule upstream writes three times:

```
def nil_ds.shape(+dt: S.Dt) -> Maybe<&2, DtShape>:      # fold.bend:1112
  match dt:
    case S.Dt{_, _, S.CVoid{}, _}: late()
    case _: Some{dt_of_nil(dt)}
```

| op | `file:line` | reads |
|---|---|---|
| CALL | `fold.bend:1170-1171` | `nil_ds.shape(call_dt(arg))` |
| INS | `fold.bend:1182-1188` (`ins_ds.pick`, then `ins_ds`) | `nil_ds.shape(dt)` |
| CUSTOM_FUNCTION | `fold.bend:1193-1196` | `nil_ds.shape(O.CustomFunction.dtype(cf))` |

`cfun_ds.shape` is GONE -- it was a **third** copy of the same three lines -- and
`custom_ds.of` (`fold.bend:1228-1231`) keeps its own one-line void arm because its else arm
is a broadcast, not `()`. There is now no fourth copy available to be left behind.

### 1a. IT IS A NARROWING, MEASURED, AND NOT BY ASSERTION

`tree/drivers/one/insprobe.bend` calls the four readers directly on both sides of the dtype
test, and was run against BOTH `fold.bend` revisions on the same frozen tree
(`insprobe-old.rows` vs `insprobe-final.rows`):

```
                        BEFORE                  AFTER
INS    void     OUTER-None -> ?         Some{void R}      <- moved
INS    u64      Some{u64 ()}            Some{u64 ()}      <- unmoved
INS    i32      Some{i32 ()}            Some{i32 ()}      <- unmoved
INS    (no arg) OUTER-None -> ?         OUTER-None -> ?   <- unmoved, AND MUST BE
CALL   void     OUTER-None -> ?         Some{void R}      <- moved
CALL   u64      Some{u64 ()}            Some{u64 ()}      <- unmoved
CFUN   void     Some{void R}            Some{void R}      <- unmoved (fixed 2026-10-05)
CFUN   u64      Some{u64 ()}            Some{u64 ()}      <- unmoved
CUSTOM void     Some{void R}            Some{void R}      <- unmoved (fixed 2026-10-05)
CUSTOM u64      Some{u32 R}             Some{u32 R}       <- unmoved
```

**EXACTLY TWO ROWS MOVED, BOTH THE VOID COLUMN OF THE TWO TWINS.** No arm accepted more
and no non-void answer changed. The `CFUN`/`CUSTOM` rows are the 2026-10-05 fix visible in
the same table, which is the independent check that the twins carried the identical defect.

**AND THE OUTER `None` IS NOT DEAD, WHICH IS THE POINT OF THE FOURTH ROW.** `ins_ds` still
answers the outer `None` for an arg that is not `AInk`, and that is CORRECT -- ops.py:139
raises `assert isinstance(arg, tuple)` there. The fix narrowed the *dtype* arm and left the
*malformed-arg* refusal intact; a fix that had cleared the outer `None` wholesale would have
taken a real refusal with it.

### 1b. HOW I KNEW THE SECOND TWIN WAS UNEXERCISED -- MEASURED, NOT ASSUMED

1. **0 of 304 rows** across all 22 graphs name an `INS` op. The corpus carries exactly one
   `CALL` and it is in `loop`.
2. **0 of 334** self-test rows build one.
3. **THE STRONG ONE** -- `insprobe.bend`, run against both revisions. That is a control, not
   a snapshot, and it is what turns "no row exercises this" into "here is the defect,
   exercised".

---

## 2. `loop`, FROM THE DRIVER

`tree/drivers/one/gcmp.bend loop`, on `tree/`, with `tree/…/uop/fold.bend` the only thing
that differs between the two runs.

```
BEFORE   # root=25 nodes=26 settled=False
         3:i25 4:CALL 1:? 1:? 2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid) 18:n(i23,i24,i24,i24)

AFTER    # root=25 nodes=26 settled=True
         3:i25 4:CALL 4:void 1:R 2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid) 18:n(i23,i24,i24,i24)
```

THE CAUSAL CHAIN, every link in `fold.bend` and every one checked:

`call_ds.go` answered the OUTER `None` when `dt == vd` -> `derived.put`'s `case None{}:
None{}` (`fold.bend:2503-2507`) -> `Kahn.ans.of` never inserts the node -> `Kahn.settled`
is `Nat.is_eq(Table.len(tb), U32.to_nat(O.Arena.next(ar)))` (`fold.bend:2689-2690`), so
`26 != 25` -> `settled=False` -> `UOp.dtype` (`fold.bend:4404`) and `UOp.shape`
(`fold.bend:4388`) are BOTH `Kahn.get(i, tb)` -> one absence read as `?` twice.

**THE UPSTREAM SOURCE OF THE VOID IS NAMED AND NOT EDITED: `graphcmp.bend:1004-1005`**, which
hard-codes `O.CallInfo{Some{"hcq_fence"}, False{}, False{}, S.void()}`. `graphcmp.bend` is
SETTLED AND COMMITTED and is not this unit's file. The fix makes the fold answer the
`void` it is handed instead of refusing it, so the hard-code is no longer load-bearing for
`?` -- but it is still the reason node 25 is void, and it is still the thing that would have
to change for a non-void CALL to be exercised.

---

## 3. BLAST RADIUS -- TWENTY-TWO GRAPHS, NOT SIX

The previous unit reported "6 other graphs". The corpus has **22** and all 22 were run on
both sides, so the radius is a census rather than a sample. **304 rows.**

| belt | result |
|---|---|
| 1 -- `diff -r` over whole files, no parsing at all | **21 of 22 byte-identical**, `loop` differs by exactly 2 lines (the header and row 25) |
| 2 -- length-prefixed chunk walk, EXACT row consumption (`belt.py --mode=chunks`) | **21 IDENTICAL, 1 MOVED**, 0 unreadable on both sides |

`sym` is byte-identical, and it is the graph that FIRST emitted `?` -- MEASURED, not
asserted.

**`fold.bend`'s OWN 334-ROW SELF-TEST: BYTE-IDENTICAL**, by both belts and by sha256:

```
232be7fe302e80b94b69f3ab04912e81c601a9374de940910aeb3dda8c6e0530   frozen-OLD
232be7fe302e80b94b69f3ab04912e81c601a9374de940910aeb3dda8c6e0530   frozen-NEW
232be7fe302e80b94b69f3ab04912e81c601a9374de940910aeb3dda8c6e0530   probe-rewritten
232be7fe302e80b94b69f3ab04912e81c601a9374de940910aeb3dda8c6e0530   the LIVE tree, before the edit
```

Four runs, three substrates, one hash. `diff` rc 0; `belt.py --mode=kv` `0 moved`.

### 3a. THE BELT, AND THE TWO DEFECTS ITS OWN PLANTS FOUND IN IT

`belt.py --selftest` is **20 cases, 0 failed**, and it exists because the first two versions
of this file were wrong in ways only a plant could catch:

* **v1 walked the chunks without the single-space separator**, so it reported
  `NON-NUMERIC-COUNT` on every row -- and its `SPACE` plant still PASSED, because both
  sides were unreadable and *unreadable is a fixed point*. That is a belt agreeing with a
  broken belt. Fixed, and the control now demands `0 unreadable` on BOTH sides.
* **v2 fixed the control and left the hole in `main()`**: pointed at the 334-row corpus it
  answered `IDENTICAL [UNREADABLE] … 334 unreadable` and **exited 0**. `main()` now fails on
  an unreadable file, in either mode.
* The `kv` mode's first cut split on `=` and read **93 of 334** rows as garbage. The
  self-test corpus is MIXED and that is now measured and stated: 31 `name=value`, 93
  `name <chunked>` with no `=` at all, 210 `name` + `k=v` pairs.
* One selftest case asserted a FALSEHOOD -- that a `kv` corpus is unreadable under
  `--mode=chunks`. It FAILED, because `chunks` is a deliberate SUPERSET. The claim was
  wrong, not the code; the case now pins the true asymmetry. A selftest that asserts a
  falsehood gets "fixed" by breaking the reader.

The fixture is `base/loop.rows` and `selftest-frozen-old.rows` OFF DISK, never typed: v0
hand-typed its own `<n>:` counts, got two wrong, and its own control caught it.

---

## 4. THE PROBE AT `fold.bend:4922-4955` -- **DELETED, NOT KEPT**

`rg_call` carried `S.int32()` in the `CallInfo`'s dtype field and its comment said the
non-void was NECESSARY, quoting the now-dead `call_ds.go`. A non-void left in place would
be a probe passing for a reason its own comment had disowned.

**DELETED: the `dt` is now a parameter, and each row carries the dtype CPython computes
for ITS OWN BODY.** `.agents/slop/loopfix/callprobe.out`:

```
call_cf arg=dtypes.i32   dtype=!! AttributeError: 'tuple' object has no attribute 'dtype'   ranges=[0,1]
call_cf arg=dtypes.void  dtype=!! AttributeError: 'tuple' object has no attribute 'dtype'   ranges=[0,1]
call_c  arg=dtypes.i32   dtype=dtypes.weakint   _shape=()   ranges=[]
call_c  arg=dtypes.void  dtype=dtypes.weakint   _shape=()   ranges=[]
```

Three things fall out, and all three are why the field was wrong:

1. **CPython NEVER READS IT.** `arg=dtypes.i32` and `arg=dtypes.void` give byte-identical
   `dtype`, `_shape` and `ranges`, because upstream reads a CALL's dtype off `src[0].dtype`
   (ops.py:130) and the arg's 4th slot is `aux`, not a dtype.
2. **`S.int32()` WAS WRONG FOR BOTH ROWS.** For the CONST body CPython says **`weakint`**,
   which is also what the port's own `const_ds` answers (ops.py's `isinstance(arg, int) ->
   dtypes.weakint`) and what `loop`'s CONST rows print. For the CUSTOM_FUNCTION body CPython
   says **NOTHING** -- `oracles/fold-rng-oracle.py:116` passes a 2-tuple where ops.py:135
   reads `arg.dtype`, and it RAISES. `S.void()` is what `rg_cf`'s own
   `CustomFunction{"myext", S.void()}` states, so it is the closest faithful answer.
3. **THE ORACLE IS THE FILE WITH THE BAD FIXTURE, AND IT IS NOT THIS UNIT'S.**
   `oracles/fold-rng-oracle.py:111-115` carries the SAME obsolete "NON-VOID on purpose"
   comment. **REPORTED, NOT PATCHED.** That oracle's dtype is uncomputable for `call_cf`,
   which is invisible only because an `rg_*` row compares `ranges` alone.

**MEASURED THAT REMOVING THE NON-VOID COSTS NOTHING: the 334 rows are byte-identical** with
the old `S.int32()` and the new per-row dtypes. So the field was never load-bearing for any
row -- it was decoration that had acquired a justification. That is exactly the "passing for
the wrong reason" case, and it is now gone. The 4 `rg_` rows still agree with CPython
(`callprobe` aside, `oracle-rng.rows` vs the port: `rg_er`, `rg_call_cf`, `rg_call_c`,
`rg_absent` all agree).

---

## 5. `LIMITS.md` -- THREE WRONG ATTRIBUTIONS, ALL STILL IN THE FILE. REPORTED, NOT EDITED.

`.agents/slop/graphcmp-LIMITS.md` is under `.agents/slop/`, which another unit prunes. Its
`citations` lane's own doctrine (`checks/disagree-gate.py:18-22`) is "closing a defect makes
THIS gate fail instead of quietly making the prose wrong", so all three are named here.

### (1) `LIMITS.md:283-286` -- `?` IS NOT ATTRIBUTED TO `call_dt`, AND `?=0/2` IS STALE

> "the port's CALL dtype is decided by a field upstream does not consult and does not have,
> and on `--graph loop` it reads `?` where CPython reads `void`/`R` on **1 node of 25** …
> this is the only node in the corpus that answers `?` (`?=0/2`)"

**MEASURED FALSE as a cause.** `call_dt` (`fold.bend:1152-1155`) is TOTAL and of type `S.Dt`:
it returns `O.CallInfo.dtype(ci)`, i.e. `S.void()` here. It cannot produce a `?`. The `?`
came from `call_ds.go`'s outer `None` (§2). And on this graph the `CallInfo.dtype` field
**AGREES** with upstream's `src[0].dtype` (both void, because `src[0]` is a SINK), so the
field is a LATENT divergence, not this row's cause. The pin is also internally
contradictory -- "the only node that answers `?`" beside `?=0/2`. MEASURED: `loop` emits
`?` in **2 of 2** columns on 1 of 26 nodes, i.e. `?=2/2`.

**SHOULD SAY:** the `?` was `call_ds.go`/`ins_ds.shape`'s outer `None` -- the `?`/`R`
conflation -- and the `CallInfo.dtype` field is a separate, still-open divergence that
happens not to bite on this graph.

### (2) `LIMITS.md:406-414` (this is §3(c), THE MOST DAMAGING ONE) -- THE ASSERTION RESTS ON A FALSE CAUSE

> "`--graph loop`'s CALL is now the carrier (`?=2`, one node x two columns) **because its
> wall has a DIFFERENT and still-open cause** -- `fold.bend`'s `call_dt` reads
> `CallInfo.dtype` and CPython's `CallInfo` has no dtype (see §2)."

**MEASURED FALSE, AND THE CAUSE IS NOW CLOSED.** The wall that kept `loop`'s CALL a hole was
`call_ds.go`, a defect with NO upstream counterpart -- upstream answers a definite shape for
CALL (ops.py:386-388) and for INS (ops.py:339-341). Closed 2026-10-06.

**SHOULD SAY, AND THIS IS THE ANSWER TO "MOVE IT BACK TO `sym`?":** **NO -- it must not
move back to `sym`, and the reason is not that `sym` is wrong.** `sym` stopped emitting `?`
because §3(b) closed the `marg.of`/symbolic-dim wall on 2026-04, so pinning `?=2` there
would pin a bug that no longer exists -- which is the identical error §0:61-62 already
records having made once ("the `?=6` row was a regression row for a defect that no longer
existed, which made a FIX look like a break").

**THE REAL CONSEQUENCE, AND IT IS STRONGER THAN "MOVE IT":** after this fix **NO GRAPH IN THE
CORPUS EMITS `?` AT ALL** -- 0 of 304 rows on 22 of 22 graphs, `sym` included. So the
two-column `?` assertion has **no fixture left**, and the thing LIMITS.md:287-288 called "a
claim with no denominator" is BACK. The `?=2` row on `loop` must be replaced by a fixture
that MANUFACTURES the hole -- a plant, like `graphcmp-probe-optq.bend` does for the differ's
three refusal atoms -- or the assertion deleted as no-longer-testable. Asserting `?=0`
everywhere would be the worst outcome: a green row that can never go red.

### (3) `LIMITS.md:416-419`, restated at `:821-825` -- `loop` DOES NOT "DISAGREE ON ITS CALL's dtype"

> "`loop` on its CALL's **dtype** (1 node of 25)" / "each of those disagreements is a NAMED,
> MEASURED PORT gap: the `applied_opts` count and the `CallInfo.dtype` gap"

**MEASURED FALSE FRAMING.** The node was not a field MISMATCH; it was ABSENT from the fold's
table, so both of its columns read `?` and no rung-1 comparison of that node can be formed
at all. `lin` on `applied_opts` IS a field mismatch; `loop` was a hole.

**SHOULD SAY:** `loop` had one node of 26 the fold did not answer, for `call_ds.go`'s
reason. (And as of 2026-10-06 `loop` is not in the disagreeing set at all, on this unit's
own measurement -- see §7.)

### (3a) A FOURTH, BONUS: `LIMITS.md:279`'s CITATION IS STALE BY 75 LINES

`"call_dt` is `case O.ACall{ci}: O.CallInfo.dtype(ci)` (`uop/fold.bend:1067-1070`)"` --
MEASURED, `call_dt` was at `fold.bend:1142-1145` before this unit and **is at
`fold.bend:1152-1155`** after. `checks/disagree-gate.py:93` has the same fact RIGHT at
`1144`. So LIMITS.md:279 is a `STALE-LINE` citation -- the text is in that file at another
line -- which is the class its own remedy table calls `RESTORE`.

---

## 6. TWO MORE CITATIONS IN `fold.bend` THAT ARE WRONG AGAINST THIS TREE

Found while verifying the fix's own rule, and **not fixed by substitution** -- a silent
port of the passthrough would have changed the port's documented CALL model, which is
LIMITS.md §2's named divergence and another owner's decision.

**`Ops.CALL`'s `_shape` IS NOT `return None if self.dtype is dtypes.void else ()`.**
MEASURED at **`tinygrad/uop/ops.py:386-388`**: `Ops.CALL` is in the PASSTHROUGH arm,
`return self.src[0]._shape`, and its dtype arm is **`return src[0].dtype`**
(**`ops.py:130-132`**) -- "a call has the dtype of its body". `fold.bend`'s CALL comment
quoted the line that is at `ops.py:374`, which is `Ops.CUSTOM_FUNCTION`'s.

**WHY THE ROW CANNOT TELL THE TWO APART, AND WHY THAT IS THE POINT.** On `--graph loop`,
`src[0]` is node 23, a **SINK**, and SINK is a late op, so the passthrough answers `None`
and so does the rule this unit landed. **BOTH READ `4:void 1:R`.** So the `loop` row is
consistent with either reading and this unit's fix is NOT evidence about which one is
right. What IS settled is the half that is wrong under **both** readings: the outer `None`.

`Ops.INS` is the opposite case and the port is right: **`ops.py:339-341` really is** `if
self.dtype is dtypes.void: return None; return ()`, and `insprobe.rows` now measures both
arms of it.

Recorded in `fold.bend:1157-1169`, beside the CALL comment, so the next reader is told the
port's model and the tree's rule are not the same rule.

---

## 7. WHAT IS **NOT** CLOSED, STATED AS A FRACTION

**`loop` IS NOT FIXED. ONE HALF OF ITS TWO PORT DEFECTS IS CLOSED: `1/2`.**

`f186c1011` recorded TWO real port defects in `loop`. This unit closed **one** -- the
dtype/shape hole, `fold.bend`'s own file. The other is **`opshapes`' `arg`**, in
`tinybendygrad/uop/ops.bend`, which is not this unit's file.

**WHETHER THE TWO COMPOSE IS UNMEASURED, AND IT CANNOT BE MEASURED FROM HERE.** Two
independent reasons, both structural:

1. `opshapes` is landing in `ops.bend` RIGHT NOW -- 407,671 B at 06:49, 410,516 B at 07:04,
   and transiently uncompilable in between. There is no stable commit of it to compose
   against.
2. **THIS UNIT'S OWN CORPUS MEASUREMENT IS NOT THE DIFFER'S VERDICT.** `gcmp.bend` prints
   the port's rows; `checks/differ.py` compares them against CPython's, and the brief puts
   `runs/graphcmp/D/` and `checks/differ.py` off limits. So "the 21 other graphs are
   byte-identical" is a statement about the PORT MOVING NOTHING ELSE, and it is NOT a
   statement that 21 graphs AGREE.

**WHAT THE PORT-SIDE MEASUREMENT DOES ESTABLISH, PRECISELY:** on the frozen tree, this
unit's change moved exactly 1 node of 304 across 22 graphs, and that node is `loop`'s node
25, whose two columns now read `4:void` and `R` -- which is what CPython reads there.

---

## 8. BYTE COUNTS, `ALL PROOFS CHECK`, PEAK RSS

`ALL PROOFS CHECK` -- **NOT** `SOME PROOFS FAIL`. MEASURED with the exit code AND the token,
and checked for emptiness afterwards because `bend --check-only` answers `ALL PROOFS CHECK`
for a **0-byte** file:

```
$ … bounded.py --seconds 900 --mb 2048 -- ./bin/bend tinybendygrad/uop/fold.bend --check-only
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=402 MB (ceiling 2048)
stdout 58 B:  ALL PROOFS CHECK / Use --verdict for mathematical validity.
```

| file | before | after |
|---|---|---|
| `tinybendygrad/uop/fold.bend` | 385,810 | **389,047** (+3,237 bytes) |
| `tinybendygrad/helpers.bend` | 130,719 | **130,719** -- UNTOUCHED, and NOT 0 |
| `.agents/slop/graphcmp.bend` | 91,132 | **91,132** -- UNTOUCHED |

**AND THE +3,237 BYTES ARE NOT CODE.** The file's line classes, counted not estimated:

| | total | comment | code |
|---|---|---|---|
| `fold-old.bend` | 6,742 | 2,860 | **3,882** |
| `fold-new.bend` | 6,777 | 2,901 (+41) | **3,876 (−6)** |

**SIX FEWER LINES OF CODE**, because three defs that were two identical copies plus one
near-copy became one def plus three one-line readers, and `cfun_ds.shape`'s four lines went
away entirely. Every added line is a `#`. LOCs is the measure and it went DOWN.

**`helpers.bend` IS NOT ZERO AND WAS NEVER OPENED BY THIS UNIT.** It has been truncated to
0 bytes four times by units that then saw green, so the number is reported rather than
assumed.

PEAK RSS, every bend invocation, from the `[bounded]` records -- and the token, never the
exit code, because a memory kill and a printing refusal are both rc 3 in that guard's table:

| what | token | peak |
|---|---|---|
| `gcmp` build, old fold | `WITHIN-LIMITS` | 1,732 MB |
| `gcmp` build, new fold | `WITHIN-LIMITS` | 1,720 MB |
| `gcmp` build, final | `WITHIN-LIMITS` | 1,840 MB |
| `gcmp` build, final (v2) | `WITHIN-LIMITS` | 1,590 MB |
| `gcmp` build, live tree, before the edit | `WITHIN-LIMITS` | 1,757 MB |
| `fold.bend` build, old | **`KILLED-ON-MEMORY` rc=-9 peak 2,052 MB** | killed |
| `fold.bend` build, old, retry | `WITHIN-LIMITS` | 2,013 MB |
| `fold.bend` build, live tree, before the edit | `WITHIN-LIMITS` | 2,017 MB |
| `fold.bend` build, new | `WITHIN-LIMITS` | 1,509 MB |
| `fold.bend` build, probe-rewritten | `WITHIN-LIMITS` | 1,344 MB |
| `fold.bend` build, final ×6 | **4 of 6 `KILLED-ON-MEMORY`, peaks 2,070-2,177 MB** | then 2,004 / 1,946 MB |
| `insprobe` build, old / final | `WITHIN-LIMITS` | 583 MB / 587 MB |
| `fold.bend --check-only` | `WITHIN-LIMITS` | 402-430 MB |

**THE SELF-TEST BUILD IS A COIN FLIP AND THAT IS A MEASUREMENT OF THE LANE, NOT OF THIS
CHANGE** -- full ledger in `rss-ledger.rows`: six attempts, **four killed**, and the
PRE-EDIT `fold.bend` was killed once too.

**AND THE STALE-EXE TRAP WAS MEASURED, NOT AVOIDED BY CAREFULNESS.** Every build `rm -f`'d
its output first, so the kill after attempt 6 left NOTHING; invoking the exe then answered
`[bounded] NOT-STARTED rc=5` and **0 bytes of stdout**, whose sha256 is `e3b0c442…` -- the
sha256 of the empty string. A reader who trusted the exit code, or counted rows without
checking emptiness, would have recorded a **0-row self-test as a pass**. The guard's token
caught it. **`timeout` is not installed and `rc=142` was never seen**; the kills are
`-9`/SIGKILL from `checks/bounded.py`, which says so in words.

The 334-row run that closed this section is the **fifth** with that sha256:

```
232be7fe302e80b94b69f3ab04912e81c601a9374de940910aeb3dda8c6e0530  selftest-v3.rows  (final tree)
```

---

## 9. `jj` HAZARD THIS DIRECTORY CREATES -- FOR WHOEVER COMMITS

`jj status` reports **`C {tinybendygrad/uop/fold.bend => .agents/slop/loopfix/tree/tinybendygrad/uop/fold-new.bend}`**:
rename detection pairs this unit's real file with the frozen copy. Nothing is lost, but a
`jj commit` over this working copy must name `tinybendygrad/uop/fold.bend` explicitly or it
may take the rename pair with it. `tree/tinybendygrad/uop/fold-old.bend` is the second
half of that pairing and is the pre-edit file -- **do not commit it as a deletion of the
real one.**

**`tree/` IS THE REPRODUCTION.** `cp` the live `tinybendygrad/` over it, put `fold-old.bend`
(or any revision) at `tree/tinybendygrad/uop/fold.bend`, build
`tree/drivers/one/gcmp.bend`, and run `<graph>`.