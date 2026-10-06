# THE SECOND DEFECT IS NAMED AND LOCATED

**IT IS NOT `CallInfo.dtype`, AND IT IS NOT A CANONICAL-FORM LIMIT. IT IS ONE `some_if`
IN `tinybendygrad/uop/fold.bend`. `?` IS NOT "UNSPELLABLE" — IT IS "THE FOLD REFUSED",
WHICH IS A *WALL*, AND THE WALL HAS A NAME.**

## 1. WHAT PRODUCES A LITERAL `?` — TWO SITES, EXHAUSTIVE

`?` is a two-character string literal in the row writer, so it cannot be synthesised by
`chunk`, `i`, `bo`, `bstr`, `us`, `dimlist`, `dname`, `tagstr`, `argstr` or `srclist`.

    .agents/slop/graphcmp.bend:488    shape_str   case None{}: "?"   # the OUTER None
    .agents/slop/graphcmp.bend:514    dt_str      case None{}: "?"

Both take a `Maybe<&2, ...>` and `?` is the OUTER `None`. `.agents/slop/graphcmp.py:2048`
registers the marker and **defines it in the ledger's own words**:

    ("?", (2, 3), "the port's fold produced no Derived for this node, in BOTH columns", …)

## 2. WHAT THE `?` MEANS — AND IT IS NOT "UNSPELLABLE"

**MEASURED, by reading the port's own `?`-registry and then reproducing it:**

    # UNMODIFIED REPO
    $ ./bin/bend .agents/slop/graphcmp.bend loop
    # root=25 nodes=26 settled=False
    …
    3:i25 4:CALL 1:? 1:? 2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid) 18:n(i23,i24,i24,i24)

The driver header prints `settled=False`. `Kahn.settled` is `Table.len(tb) == Arena.next(ar)`
(`fold.bend:2664`), so **exactly one node of 26 is absent from the fold table, and it is #25.**
Both `?`s are the same absence, read twice: `UOp.dtype` = `fold.dt` = `Kahn.get(i, tb)`
(`fold.bend:4379`), and `UOp.shape` = `Kahn.get(i, tb)` (`fold.bend:4363`). One missing table
entry, two columns.

**SO THE `?` MEANS *REFUSED*, NOT *UNSPELLABLE* AND NOT *UNKNOWN*.** The distinction matters
because it names the fault: an unspellable value is a TYPE gap (a wrong shape), a refused
value is a WALL (a rule this file defers). `graphcmp.py:2052-2054` says `?` is "PORT-ONLY, no
upstream counterpart" and that upstream "cannot be produced by the py side" — **so `loop`'s
`?` is NOT a canonical-form limit and NOT a port defect in the serialisation.** The
serialisation is *correctly reporting a hole in the fold*.

## 3. THE WALL'S NAME: `fold.bend:741-742`, `call_ds.go`

    741: def call_ds.go(+dt: S.Dt, vd: S.Dt) -> Maybe<&2, DtShape>:
    742:   some_if(&2, DtShape, Bool.not(O.eq_dt(dt, vd)), dt_of_nil(dt))

    1142: def call_dt(arg: O.Arg) -> S.Dt:
    1143:   match arg:
    1144:     case O.ACall{ci}: O.CallInfo.dtype(ci)
    1145:     case _: S.void()

`some_if` is `fold.bend:497` — `if ok then Some{x} else None`. **When `dt == void` the arm is
`False` and `call_ds.go` returns the OUTER `None`.** That outer `None` flows:

    dt_shape(OpsCALL) -> None            fold.bend:2263
    derived.put(None) -> None            fold.bend:2479-2483
    Kahn.ans.of(None) -> Kahn{pend,rest,tb}   fold.bend:4295-4298   # NODE NOT PUT IN THE TABLE
    Kahn.get(25, tb) -> None             fold.bend:4317
    dt_str(None) -> "?"                  graphcmp.bend:514
    shape_str(None) -> "?"                graphcmp.bend:488

**THE NODE IS SIMPLY NEVER ENTERED IN THE TABLE.** `fold.bend:4293` says so in its own words:
"the node the fold CANNOT answer is not in the table, and it propagates nothing".

And `g_loop` (`graphcmp.bend:1005`) **hard-codes the illegal value**:
`O.CallInfo{Some{"hcq_fence"}, False{}, False{}, **S.void()**}`. So the field's *value* drives
the refusal — which is exactly why `opshapes`' field-delete plant **could not move the `?`**:
deleting the field changed what `argstr` PRINTS and left what `call_dt` RETURNS unexercised.

**AND THE HEADER ALREADY SAYS THE PORT KNOWS THIS IS WRONG.** `fold.bend:1147-1149`, quoting
upstream: "`return arg.dtype if isinstance(arg, CallInfo) else dtypes.void` in the dtype
ladder, and `return None if self.dtype is dtypes.void else ()` in `_shape`". **THE PORT
IMPLEMENTS THE `_shape` RULE AND THROWS AWAY ITS `_shape` ANSWER** — `call_ds.go`'s outer
`None` should be `Some{DtShape{void, None{}}}`, and there is already a def for exactly that:

    1104: def late() -> Maybe<&2, DtShape>:
    1105:   Some{DtShape{S.void(), None{}}}      # = `Some{void, None}` = `4:void 1:R`

## 4. WHOSE TYPE IS UNSPELLABLE — NEITHER. AND THE NARROWING SPELLING EXISTS.

**NEITHER `dtype` NOR `shape` IS UNSPELLABLE. BOTH HAVE A SPELLING AND BOTH ARE WRITTEN
DOWN IN CPYTHON'S OWN FILES.** No new type, no new constructor, no widening:

| | upstream | spelling |
|---|---|---|
| CALL dtype | `Ops.CALL: return src[0].dtype` — "a call has the dtype of its body, void for opaque bodies" (`ops.py:130-131`) | body `SINK#23` is void → `4:void` |
| CALL shape | `_shape` passthrough arm `… Ops.STORE \| Ops.END \| Ops.CALL: return self.src[0]._shape` (`ops.py:387`) | body has no shape → `_shape is None` → `R` |

**`late()` IS THE NARROWING.** It is the SAME `Maybe<&2, DtShape>` type with the SAME two
payload types — it replaces an outer `None` with `Some{void, None{}}`. It *narrows the meaning
of `None`*: after this edit the outer `None` in `call_ds.go` becomes **UNREACHABLE**, so the
port-only "the fold produced no `Derived`" state keeps exactly ONE producer class and `?`
means one thing again. That is the opposite of accepting more.

**AND IT IS THE FILE'S OWN ESTABLISHED FIX, ALREADY APPLIED TO THE SIBLING ARM.**
`fold.bend:1199-1207` — `custom_ds.of` — says:

> WHAT THIS IS NOT, and it is the defect this arm carried until 2026-10-05: the outer `None`
> is the PORT-ONLY "the fold produced no `Derived`", which the differ spells `?`
> (`graphcmp.bend`'s `shape_str`), while "no shape" is `Some{None{}}` -> `R`. Answering the
> outer `None` here made a node upstream is HAPPY to describe read as a node the port knows
> nothing about, which is the `?`/`R` conflation one level down in the ladder.

**`custom_ds` was fixed for exactly this on 2026-10-05. `call_ds.go` was NOT — it is the same
defect, the same file, 472 lines earlier.** **`grep` over the whole file for the body returns
exactly TWO copies**, and I said three before counting:

    741: def call_ds.go(+dt: S.Dt, vd: S.Dt)   some_if(..., Bool.not(O.eq_dt(dt, vd)), dt_of_nil(dt))
    744: def ins_ds.shape(+dt: S.Dt, vd: S.Dt) some_if(..., Bool.not(O.eq_dt(dt, vd)), dt_of_nil(dt))

**`ins_ds.shape` IS THE SECOND COPY, ITS ONLY CALLER IS `ins_ds.pick` (`fold.bend:749`), AND IT
IS THE IDENTICAL WALL ON A DIFFERENT OP.** Upstream's `INS` is in the same `late ops` list
(`ops.py:365-366`, "INS shape is always scalar" over `None if self.dtype is dtypes.void`),
so a void `INS` hits the identical refusal. **I HAVE NO ROW THAT EXERCISES IT** — see §9.1.

## 5. IS IT THE SAME WALL `lin` HITS — **NO**, AND THE TWO DIFFER IN KIND

**NO. AND THE CONFUSION IS THE TRAP THAT WOULD HAVE HIDDEN THIS FINDING.**

| | `loop` | `lin` |
|---|---|---|
| marker | `?` | `q` |
| emitted by | `graphcmp.bend:488` / `:514`, the `None` arm | `graphcmp.bend:327`, `opts.go`'s `_` arm — a value that is RENDERED, not a hole |
| column | `dtype` AND `shape` (2, 3) | `arg` only (6) |
| port-only? | yes, `?` has no upstream counterpart | yes, but as a **named refusal of the ORACLE'S content** — `graphcmp.bend:316-323` says so: "the OPTION LISTS ARE COUNTS, NOT CONTENTS, and that is a refusal rather than a comparison … nothing here copies the port's answer into the oracle" |
| why | the fold REFUSES to answer | the oracle REFUSES to compare, by design |
| fixable here? | yes — one `some_if` | no — it is the oracle's policy, plus the `List<U32>`-for-`Opt` type gap `opshapes` already owns |

`lin`'s `q` is a **comparator policy** in the oracle, deliberately narrow, and `opshapes`
measured it as a device pin. `loop`'s `?` is a **hole in the fold**, and nothing about it is
deliberate. **THEY ARE DIFFERENT WALLS IN DIFFERENT FILES AND MUST NOT BE MERGED.**

## 6. THE PLANT — MEASURED, LOAD-BEARING, DISARMED

The plant, in `fold.bend` only (`late()` is at `:1104`, so the arm must sit after it):

    - def call_ds.go(+dt: S.Dt, vd: S.Dt) -> Maybe<&2, DtShape>:
    -   some_if(&2, DtShape, Bool.not(O.eq_dt(dt, vd)), dt_of_nil(dt))
    + def call_ds.go.of(void: Bool, +dt: S.Dt) -> Maybe<&2, DtShape>:
    +   match void:
    +     case True{}: late()
    +     case _: Some{dt_of_nil(dt)}
    +
    + def call_ds.go(+dt: S.Dt, vd: S.Dt) -> Maybe<&2, DtShape>:
    +   call_ds.go.of(O.eq_dt(dt, vd), dt)

(Bend forbade two intermediate shapes of this, both worth recording: `match` cannot scrutinise
a *computed* value, so `O.eq_dt(dt, vd)` must be hoisted into a parameter — the same shape
`cfun_ds.shape` at `:1173` uses; and `late()` must be defined *above* the use.)

### 6a. THE PLANT MOVES THE ROW TO CPYTHON'S BYTES

    ARMED     # root=25 nodes=26 settled=True
              3:i25 4:CALL 4:void 1:R 2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid) 18:n(i23,i24,i24,i24)

    DISARMED  # root=25 nodes=26 settled=False
              3:i25 4:CALL 1:? 1:? 2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid) 18:n(i23,i24,i24,i24)

`settled=False` → `settled=True`. **ONE row of 25 differs, and it differs in exactly the two
chunks the plant names** (`diff` of the two `.rows`, byte for byte). The `Dvoid` remains — that
is `opshapes`' half and it is supposed to remain.

### 6b. DISARM IS EXACT

The disarmed scratch `fold.bend` **reproduces the unmodified repo's rows byte-identically**
(`diff -q base-loop.rows disarm-loop.rows` → identical). The plant is load-bearing, and the
plant is also removable.

### 6c. TWO BELTS, DIFFERENT TOKENIZERS, NO SHARED REGEX

Belt 1 is the raw-line `diff` above. Belt 2 tokenises on the **length prefix** and requires
the chunks to **consume the row exactly** — a tokenizer that ate a character could not leave
every declared length honest, so it cannot share belt 1's assumptions:

    chunk0 id     py=i25                   base=i25                   plant=i25                   ==
    chunk1 op     py=CALL                  base=CALL                  plant=CALL                  ==
    chunk2 dtype  py=void                  base=?                     plant=void                  ==
    chunk3 shape  py=R                     base=?                     plant=R                     ==
    chunk4 depth  py=i0                    base=i0                    plant=i0                    ==
    chunk5 tag     py=N                     base=N                     plant=N                     ==
    chunk6 arg     py=cI(shcq_fence,b0,b0)  base=cI(…,Dvoid)           plant=cI(…,Dvoid)            !!

    PLANT vs PY differ at chunks: [6]      (the arg — opshapes' half, untouched)
    BASE  vs PY differ at chunks: [2, 3, 6]

**CHUNKS 2 AND 3 CLOSE. THE ROW IS LEFT WITH EXACTLY THE ONE DISAGREEMENT THAT IS NOT MINE.**

### 6d. BLAST RADIUS — MEASURED, NOT ASSUMED

* **SIX OTHER GRAPHS BYTE-IDENTICAL**: `sym bw matmul sink lin reduce` — `diff -q` identical
  on every one, `?`-census 0 → 0 on all six. **`sym` in particular was the graph that first
  emitted a `?`, so this is the arm that already got fixed once not re-breaking.**
* **`fold.bend`'s OWN 334-ROW SELF-TEST BYTE-IDENTICAL**, including the two rows at
  `fold.bend:5966-5967` that are ABOUT this arm:

      rg_call_cf ranges=[R(0),R(1)]
      rg_call    ranges=[]

  **AND THIS IS THE FINDING'S MOST IMPORTANT NEGATIVE.** `fold.bend:4902-4906` says in its own
  words: "THE CALL CARRIES A NON-VOID `CallInfo`, and that is not decoration. `call_ds.go` is
  `some_if(not dt is void, ...)`, so a VOID CALL is a node `dt_shape` does not answer, and
  then `ended` is not in the table and the whole set is refused — measured, not assumed: both
  rows read ABSENT with an `ANone{}` arg."

  **THE PORT HAS A PROBE BUILT AROUND THIS WALL, AND ITS `CallInfo` CARRIES `S.int32()`
  *SPECIFICALLY SO THE PROBE CAN GET PAST IT*.** The plant does not move those rows — because
  they were never exercising the void path. **`fold.bend:4902` IS A DOCUMENTED DEPENDENCY ON
  THE BUG AND MUST BE REWRITTEN WITH IT**, or the next reader inherits a comment that says the
  opposite of the truth. **I DID NOT REWRITE IT: it is in my file but it is a measured claim
  about `ended`, and re-measuring `ended` is not this unit's job.**

### 6e. ALL PROOFS CHECK — AND THE EMPTINESS CENSUS AFTER IT

    $ bounded.py --seconds 900 --mb 2048 -- ./bin/bend <plant>/fold.bend --check-only
    ALL PROOFS CHECK          rc=0  WITHIN-LIMITS  peak-RSS=437 MB

    planted tree:   empty *.bend = 0    helpers.bend = 130,719 B
    repo tree:      empty *.bend = 0    helpers.bend = 130,719 B
    planted fold.bend = 385,918 B (from 385,810 B; +108 B)

**`ALL PROOFS CHECK` IS REPORTED ALONGSIDE THE EMPTINESS CENSUS, NOT INSTEAD OF IT.
`helpers.bend` IS 130,719 BYTES IN BOTH TREES — NOT ZERO.**

## 7. PEAK RSS — `fold.bend` IS NOW MEASURED, AND IT IS NOT `sz.bend`

`fold.bend` peak RSS, all under `checks/bounded.py --seconds 900 --mb 2048`, verdict read
from the **TOKEN** and not the exit code:

| run | peak |
|---|---|
| `bend tinybendygrad/uop/fold.bend` (unmodified repo, full 334-row self-test) | **714 MB** |
| `bend <plant>/tinybendygrad/uop/fold.bend` (planted, full self-test) | **773 MB** |
| `bend <plant>/tinybendygrad/uop/fold.bend --check-only` | **437 MB** |
| `bend graphcmp.bend loop` (unmodified) | 494 MB |
| `bend <plant>/graphcmp.bend loop` (armed) | 578 MB |
| `bend <disarmed>/graphcmp.bend loop` | 633 MB |

**`fold.bend`'s PEAK WAS UNMEASURED AND IS NOW 714 MB UNMODIFIED / 773 MB PLANTED.** That is
under half the 2,048 MB ceiling and well under `sz.bend`'s 1,468 MB, so the "never two at
once" rule is the right rule and not an OOM near-miss here. **All six runs were
`WITHIN-LIMITS`, and I read the token each time — I did not trust rc=0.** Every run was
serialised behind a `ps` count of zero `[b]end2/main.ts` processes, so no two `bend` processes
overlapped.

## 8. THE COUPLINGS — NAMED, NOT EDITED

* **`graphcmp.bend:1005` `g_loop` SUPPLIES THE ILLEGAL VALUE**, `S.void()`, rather than
  reading one. **THE PLANT MAKES THAT HARD-CODED VALUE CORRECT-BY-CONSTRUCTION RATHER THAN
  LOAD-BEARING**, so the plant does **not** need `graphcmp.bend` changed. **BUT**: the moment
  `CallInfo.dtype` is DELETED (`opshapes`' half), `:1005` **must** lose its fourth argument in
  the same commit, or it will not compile — and `:301`'s `callinfo` must lose `cdtype` with it.
  **THREE `O.CallInfo` SITES IN THAT FILE (`:298-301`, `:1005`, and the `CallInfo` projection),
  ALL IN A SETTLED FILE (`f541da0f1`). NAME ONLY — NOT EDITED.**
* **`tinybendygrad/uop/spec.bend:412` AND `:1092` CITE
  `isinstance(x.arg, CallInfo) and x.dtype is x.arg.dtype`** — a rule ADDED at `6f4bfde23`
  and REMOVED at `ad117c928`. **THAT IS A RULE CHANGE, NOT A FIELD DELETE, AND IT IS
  ANOTHER UNIT'S FILE. NOT EDITED.** **MY PLANT DOES NOT TOUCH IT AND DOES NOT NEED TO** —
  `call_dt` still reads `CallInfo.dtype`, so `spec.bend`'s cited rule still compiles and still
  says what it said.
* **`graphcmp.py:672` JOINS DATACLASS FIELDS WITH `""` NOT `","`** — the CPython side's
  ambiguous-parse arm, `Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))`. **A THIRD SITE AND IT
  IS NOT MINE. NOT TOUCHED.**
## 8a. THE LEDGER IS WRONG IN THREE PLACES, AND ONE OF THEM IS A STALE ADDRESS

**`?`'s CAUSE IS ATTRIBUTED TO `CallInfo.dtype` IN THREE WRITTEN PLACES. ALL THREE ARE
FALSIFIED BY `opshapes`' PLANT AND BY MINE.** I did not edit any of them — all three belong to
another unit — but whoever lands the plant must correct them or the tree will carry a wrong
cause in writing:

1. **`.agents/slop/graphcmp.py:2052-2055`** (the LEDGER) — "whose CALL has a different and
   still-open cause (`call_dt` reads `CallInfo.dtype`, which CPython's `CallInfo` does not
   have)". **The cause is `call_ds.go`, and deleting the field does not move the `?`.**
2. **`.agents/slop/graphcmp-LIMITS.md:275-287` (§2, "A CALL's dtype -- A PORT GAP")** — same
   wrong cause, and **it cites a STALE LINE NUMBER**: "`uop/fold.bend:1067-1070`". **`call_dt`
   IS AT `fold.bend:1142-1145`.** That is the `ops.bend:NNNN` trap in a second file: a
   citation in `LIMITS.md` that points 75 lines above the def it names. **A `grep` for
   `call_dt` at 1067 lands in `ops.bend`'s own prose about `CallInfo`.**
3. **`.agents/slop/graphcmp-LIMITS.md:405-413` (§3(c))** — "`loop`'s CALL is now the carrier
   (`?=2`, one node x two columns) because its wall has a DIFFERENT and still-open cause --
   `fold.bend`'s `call_dt` reads `CallInfo.dtype`". **SAME WRONG CAUSE.** This is the one that
   **MOST ACTIVELY MISLEADS**, because §3(c) is the entry that justifies moving the two-column
   `?` assertion from `sym` onto `loop` at all — so the assertion currently rests on a claim
   that is false, for a reason that is one `some_if` away from being closed.

**THE STALENESS IS ITS OWN SMALL FINDING.** §2 says "CPython's `CallInfo` has no dtype
attribute at all (MEASURED: `repr` is `CallInfo(None, 'hcq_fence', False, False)` — four
attributes, `grad_fxn`/`name`/`precompile`/`precompile_backward`)".

**I CHECKED THAT CITATION AGAINST THE TREE AND IT IS CORRECT, NOT STALE — and it is worth
recording that I checked, because I expected it to be wrong.** `tinygrad/uop/ops.py:1399-1410`
does still carry `__repr__`, and it does **not** consult `dtype`; the only `dtype` in that
region is `CustomFunction`'s (`ops.py:1396-1397`), a different dataclass. `CallInfo` has five
fields (`ops.py:1400-1405`) and none is `dtype`. **So §2's measurement is sound, and its
`fold.bend:1067-1070` citation is the only stale part of it.**

## 9. WHAT I DID NOT SETTLE

1. **`ins_ds.shape` (`fold.bend:744-745`) IS THE SECOND COPY OF THE SAME DEF** and has the same
   latent wall on `INS`. **NO `INS` APPEARS IN ANY OF THE SEVEN GRAPHS I EMITTED** (`INS=0` in
   `sym bw matmul sink lin reduce loop`, counted by scanning the emitted rows for an `INS`
   chunk, not by trusting a graph name) — so I have no row that exercises it and **I DID NOT
   PLANT IT.** It should land with this one, but landing an unexercised change on a shared tree
   is how a wall becomes a mystery. **MY INS CENSUS IS 7 OF 25 GRAPHS AND IS NOT THE CORPUS.**
2. **THE UPSTREAM PASSTHARM IS NOT WHAT I PLANTED.** Upstream's CALL dtype is
   `src[0].dtype` and its shape is `src[0]._shape` — the BODY, not the arg. **I planted
   `late()` because it is the NARROWING and it needs no new field, but a faithful port would
   read `ss[0]` and would then NOT need `CallInfo.dtype` at all** — which would make
   `opshapes`' field delete fall out for free instead of costing 11 sites in 7 files. **THAT IS
   A BIGGER CHANGE THAN MY PLANT AND I DID NOT MAKE IT.** **IT IS THE RIGHT ONE AND IT NEEDS
   `ss` AT `dt_shape`'s CALL ARM (`fold.bend:2263`), WHICH `call_ds` DOES NOT CURRENTLY
   TAKE.**
3. **`fold.bend:4902-4906`'s PROBE CLAIM IS NOW WRITTEN AGAINST THE FIX** (see 6d). I named it
   and did not rewrite it.
4. **`opshapes`' PLANT AND MINE COMPOSE?** Almost certainly — they touch disjoint chunks
   (`arg` vs `dtype`/`shape`) — **BUT I DID NOT MEASURE THE COMPOSITION**, because it needs
   `ops.bend` (a read-only file for me) and `spec.bend` (another unit's). **THE ROW CANNOT BE
   FULLY CLOSED BY EITHER UNIT ALONE.**
5. **`runs/graphcmp/D` WAS NOT READ, NOT WRITTEN, AND `checks/differ.py` WAS NOT RUN.** My
   `?`-census is over six graphs I emitted MYSELF. **WHETHER `not-comparable`'s COUNT MOVES IS
   UNMEASURED BY ME** — and that count is what `not-comparable=16` was meant to kill.
6. **THE PY ROW IS TRANSCRIBED** from `.agents/slop/opshapes/00-rows.md:103-104`, de-padded.
   `D` was off limits. **THE PLANT'S VERDICT DOES NOT DEPEND ON IT**: the port read
   `?`/`?`/settled=False and the plant read `void`/`R`/settled=True, and CPython's
   `void`/`R` is what `ops.py:130-131` and `:387` say a void-bodied CALL is.

## 10. THE ANSWER, IN ONE LINE

**`?` IS THE FOLD REFUSING, NOT A VALUE FAILING TO SPELL. THE WALL IS
`fold.bend:741-742`'s `some_if`, WHOSE `None` ARM THROWS AWAY THE `_shape` ANSWER THAT
`fold.bend:1147-1149` QUOTES IN ITS OWN HEADER. `late()` AT `:1104` IS THE SPELLING, IT
ALREADY EXISTS, AND PLANTING IT TURNS `settled=False` INTO `settled=True` AND THE ROW INTO
CPYTHON'S BYTES ON THE TWO CHUNKS THAT ARE MINE.**