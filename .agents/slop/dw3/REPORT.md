# THE `dw >= 3` ARM OF `nn_dot` -- CPython's `:389` GUARD, THE `ws[axis_w:]` TERM, AND THE TRANSPOSE AXIS

**HEAD `c3c4120f4556dadde82511f6bd96cd6a2c3bd5ab` (`c3c4120f4`), 2026-10-20.**
MEASURED 2026-10-20T17:42Z–18:05Z. `tinybendygrad/nn/layers.bend` WAS **BYTE-IDENTICAL
TO HEAD** THE WHOLE TIME (`git hash-object` == `git rev-parse HEAD:<path>` ==
`9fa65b3801c47c8275358b4f92009dfee4d57aee`), SO `dw3.diff` APPLIES CLEANLY TO IT
(`patch -p1 --dry-run` -> rc=0).

**THE PATCH IS `dw3.diff`. IT IS NOT LANDED -- I DID NOT EDIT ANY FILE OUTSIDE
`.agents/slop/dw3/`. THE ORCHESTRATOR LANDS IT.**

---

## 0. THE BRIEF'S CITATION IS WRONG, AND THE FILE IT NAMES HAS NO `dot` IN IT

THE BRIEF SAID *"CPython's `:386` guard"* IN `tinygrad/uop/ops.py`.
**`tinygrad/uop/ops.py` HAS NO `dot` IN IT.** MEASURED:

```
grep -rn "axis_w" tinygrad/          -> tinygrad/mixin/op.py:389 AND :391, AND NOWHERE ELSE
grep -rn "def dot\|def matmul" tinygrad/ -> tinygrad/mixin/op.py:367, :394
```

**THE GUARD IS AT `tinygrad/mixin/op.py:389`** IN THE VENDORED UPSTREAM
(`86c4f1343` RE-VENDORED `002630241`). THE PORT'S OWN HEADER COMMENT CITED
`:383`–`:390` FOR THE SAME BLOCK, **SO THE PORT'S CITATIONS WERE STALE BY THREE
LINES AND NAMED THE WRONG FORMULA** (BELOW). THE PATCH CORRECTS BOTH.

---

## 1. THE GUARD, QUOTED EXACTLY

`tinygrad/mixin/op.py:387-392`, THE WHOLE OF CPython's `dot` BODY:

```python
387:    x, dx, dw = self, self.ndim, w.ndim
388:    if not (dx > 0 and dw > 0): raise RuntimeError(f"both tensors need to be at least 1D, got {dx}D and {dw}D")
389:    if x.shape[-1] != w.shape[axis_w:=-min(w.ndim,2)]: raise RuntimeError(f"cannot dot {x.shape} and {w.shape}")
390:    x = x.reshape(*x.shape[0:-1], *[1]*min(dx-1, dw-1, 1), x.shape[-1])
391:    w = w.reshape(*w.shape[0:-2], *[1]*min(dx-1, dw-1, 1), *w.shape[axis_w:]).transpose(-1, axis_w)
392:    return (x*w).sum(-1, dtype=dtype).cast(least_upper_dtype(x.dtype, w.dtype) if dtype is None else dtype)
```

### WHAT IT REFUSES, AND WHY

**`axis_w = -min(w.ndim, 2)`.** IT IS **NOT** THE `-w.ndim if w.ndim > 1 else 0`
THE PORT'S HEADER CLAIMED (`:278-281`), AND THAT STALE CLAIM IS WHAT MADE
`nn_dot.order` WRONG FOR `dw >= 3`.

**AND THE TWO SPELLINGS OF `axis_w` ARE NOT THE SAME EXPRESSION:**

- **`:389` IS `w.shape[axis_w:=-min(w.ndim,2)]` -- A SINGLE DIM, NOT A SLICE.**
  PYTHON'S GRAMMAR MAKES `a ':' b` WITH `a` A `named_expression`, SO THE WALRUS
  CONSUMES `axis_w := -min(w.ndim,2)` **AND THE SLICE'S LOWER BOUND, WITH NO
  UPPER BOUND** -- BUT THE `:` IS *INSIDE* THE WALRUS, SO THERE IS NO SECOND
  `:` AND THE SUBSCRIPT IS ONE INDEX. **MEASURED, `.venv/bin/python`:**

  ```
  w.shape=(3,)          -> w.shape[axis_w:=-min(dw,2)] = 3   type=int
  w.shape=(3,4)         -> 3   type=int
  w.shape=(3,4,1)       -> 4   type=int
  w.shape=(3,4,5,6)     -> 5   type=int
  ```

  **SO THE GUARD READS `w.shape[axis_w]`, NOT `w.shape[axis_w:]`.**
  (THE PRIOR UNIT MEASURED THIS TOO, IN `.agents/slop/dotfix/REPORT.md:35-42`.
  **I RE-MEASURED IT INDEPENDENTLY AND IT IS THE SAME.**)
  **SO THE GUARD IS `x.shape[-1] != w.shape[-1]` FOR `dw == 1` AND
  `x.shape[-1] != w.shape[-2]` FOR `dw >= 2`.**

- **`:391` IS `w.shape[axis_w:]` WITH `axis_w` A PLAIN NAME, SO IT IS A SLICE**
  AND ANSWERS **THE LAST `min(dw,2)` DIMS**: `(w0,)` FOR `dw == 1`,
  `(w0,w1)` FOR `dw == 2`, `(w1,w2)` FOR `dw == 3`.

**THE TWO MUST BE SPELLED SEPARATELY, AND THE PORT SPELLED NEITHER.**

---

## 2. THE RULE -- MEASURED, NOT LISTED

**`dot` ACCEPTS IFF BOTH HOLD:**

> **(G)** `x.shape[-1] == w.shape[-min(dw,2)]` -- THE `:389` GUARD.
> **(B)** THE TWO RESHAPED SHAPES BROADCAST: ALIGN RIGHT, AND IN EACH DIM PAIR
> ONE IS `1` OR THEY ARE EQUAL.

**AND IT REFUSES IN TWO DIFFERENT WAYS:**

| CPython's refusal | when |
|---|---|
| `RuntimeError: cannot dot (xs) and (ws)` | (G) FAILS |
| `IndexError: shape mismatch: objects cannot be broadcast to a single shape ((x'), (w'))` | (G) HOLDS AND (B) FAILS |

**MEASURED OVER 14,040 SHAPE PAIRS** (`dw` IN {2,3,4} x `dx` IN {1,2,3,4} x DIMS IN
{1,2,3}, THE ORACLE PREDICTING FROM THE SOURCE TEXT ALONE AND COMPARING WITH
CPython's OWN `Tensor.dot`):

```
enumerated=14040 rule-mismatches=0
dw=2 cpython=ACCEPT  predicted-mechanism=-        : 360 cases
dw=2 cpython=REFUSE  predicted-mechanism=GUARD    : 720 cases
dw=3 cpython=ACCEPT  predicted-mechanism=-        : 864 cases
dw=3 cpython=REFUSE  predicted-mechanism=GUARD    : 2160 cases
dw=3 cpython=REFUSE  predicted-mechanism=BROADCAST: 216 cases
dw=4 cpython=ACCEPT  predicted-mechanism=-        : 2214 cases
dw=4 cpython=REFUSE  predicted-mechanism=GUARD    : 6480 cases
dw=4 cpython=REFUSE  predicted-mechanism=BROADCAST: 1026 cases
```

**THE ROW THAT MATTERS MOST: AT `dw == 2` EVERY SINGLE REFUSAL IS A `GUARD`
REFUSAL AND NOT ONE IS A BROADCAST REFUSAL.** SO **FOR `dw <= 2` THE GUARD IS
THE WHOLE RULE** -- AND THAT IS WHY THE PORT'S `dw <= 2` BEHAVIOUR IS A
*REGRESSION CHECK* AND NOT A REDESIGN.

---

## 3. THE THREE CAUSES THE PRIOR UNIT NAMED, AND A FIFTH IT DID NOT

THE PRIOR UNIT (`.agents/slop/dotfix/REPORT.md` §7) NAMED THREE CAUSES FOR THE
`dw >= 3` FAILURE. **TWO OF THE THREE ARE ABOUT `nn_dot`, ONE WAS ALREADY
LANDED, AND THERE IS A FIFTH.**

| # | named cause | status |
|---|---|---|
| 1 | "the same head/tail defect" (IN `nn_dot.xshape`) | **TRUE, AND ALREADY LANDED** -- `c958d7b0b` "nn: a HEAD drop where CPython has a TAIL slice". NOT MINE, NOT IN MY DIFF. |
| 2 | "the `ws[axis_w:]` term" | **TRUE, AND IT WAS **TWO** WRONGS, NOT ONE.** `nn_dot.wshape` SPELLED `ws[0:-2]` AS A **HEAD** DROP (`List.drop(ws, 2n)` ANSWERS `ws[2:]`) **AND** SPELLED `ws[axis_w:]` AS **THE WHOLE LIST**. FOR `dw == 3` CPython'S FIRST SLICE IS `(w0,)` AND THE PORT ANSWERED `(w2,)`; CPython'S SECOND IS `(w1,w2)` AND THE PORT ANSWERED `(w0,w1,w2)`. |
| 3 | "`order`'s axis" | **TRUE.** THE PORT EXCHANGED POSITIONS `len-dw` AND `len-1`; CPython'S `.transpose(-1, axis_w)` EXCHANGES `len-1` AND `len-min(dw,2)`. **THE TWO COINCIDE FOR `dw == 2` AND FOR NO OTHER `dw`.** |
| 4 | "CPython's `:386` guard never ported" | **TRUE.** `nn_dot.rd` IMPLEMENTED ONLY `dx > 0 and dw > 0`. THE FILE'S OWN HEADER SAID *"AND THE TWO RAISES AT :385-386 ARE PORTED AS A `Maybe`"* -- **ONE OF THE TWO WAS NOT.** |
| 5 | **NOT NAMED: CPython's SECOND REFUSAL IS ALSO NOT PORTED.** | **TRUE.** THE PORT'S FOLD REFUSES A BAD BROADCAST THE SAME WAY CPython DOES -- IT ANSWERS NO SHAPE -- **BUT THE PORT HANDED BACK THE DEAD GRAPH INSTEAD OF A REFUSAL.** THE PORT'S `Maybe` IS ITS SPELLING OF "CPython RAISES", SO A DEAD GRAPH IS A LIE IN THE PORT'S OWN VOCABULARY. **THIS IS THE FIFTH CAUSE AND IT IS THE ONE THAT MAKES `E`, `F` AND `M` REFUSE.** |

**THE PORT'S `axis_w` CLAIM WAS WRONG IN A THIRD PLACE:** THE HEADER SAID
*"ON THE RESHAPED `w` OF LENGTH `len` THE AXIS `axis_w` IS `len - dw`"*. THE
VENDORED UPSTREAM SAYS `len - min(dw,2)`. **THE PATCH CORRECTS THE HEADER.**

---

## 4. THE PORT'S COUNTERPART, AND WHAT IS MISSING

`tinybendygrad/nn/layers.bend` AS IT STANDS (HEAD `c3c4120f4`):

```bend
# `w.shape[0:-2]` ++ `[1]*k` ++ `w.shape[axis_w:]` -- :388. The last term IS
# `w.shape` on BOTH arms of :383 ...
def nn_dot.wshape(+ws: List<&2, U32>, k: U32) -> List<&2, U32>:
  List.concat(&2, U32, [List.drop(&2, U32, ws, 2n), H.make_tuple_rep(1, k), ws])
```

```bend
def nn_dot.order(+len: U32, +dw: U32) -> List<&2, U32>:
  +ids = nn_range(len)
  List.set(&2, U32, List.set(&2, U32, ids, U32.to_nat(U32.sub(len, dw)), U32.sub(len, 1)),
    U32.to_nat(U32.sub(len, 1)), U32.sub(len, dw))
```

```bend
# `dx > 0 and dw > 0` (:385). A `Bool` and not a `Maybe`, because it selects
# between two answers that both exist.
def nn_dot.rd(+ax: List<&2, U32>, +bw: List<&2, U32>) -> Bool:
  Bool.and(U32.is_gt(nn_len32(ax), 0), U32.is_gt(nn_len32(bw), 0))
```

**WHAT IS MISSING, NAMED:**

1. **THE `:389` GUARD.** `nn_dot.rd` HAS NO SHAPE HALF. `nn_dot.guard` IS NEW.
2. **`w.shape[axis_w:]`.** THE PORT'S LAST TERM IS THE WHOLE LIST.
3. **`w.shape[0:-2]`.** THE PORT SPELLS IT AS A HEAD DROP.
4. **THE TRANSPOSE AXIS.** `len-dw` WHERE CPython SAYS `len-min(dw,2)`.
5. **CPython'S SECOND REFUSAL.** NOTHING READS THE PRODUCT'S SHAPE.

---

## 5. THE PATCH

`dw3.diff` -- `a/tinybendygrad/nn/layers.bend` -> `b/tinybendygrad/nn/layers.bend`,
**192 LINES**, `patch -p1 --dry-run` -> rc=0. FIVE PARTS:

| part | what | where |
|---|---|---|
| **HEADER** | THE STALE `axis_w` FORMULA AND THE STALE LINE NUMBERS `:383`-`:390` -> `:387`-`:392`, AND THE FACT THAT `:389` IS A SINGLE DIM WHILE `:391` IS A SLICE. | the `dot` header block |
| **GUARD** | `nn_dot.guard` + `nn_dot.guard.ans` (NEW), AND `nn_dot.rd` NOW ANDS THE SHAPE HALF. | `nn_dot.rd` |
| **WSHAPE** | `nn_dot.wshape` NOW SPELLS `ws[0:-2]` WITH THE EXISTING `nn_tail_drop` AND `ws[axis_w:]` WITH A HEAD DROP OF `dw-min(dw,2)`. | `nn_dot.wshape` |
| **ORDER** | `nn_dot.order` NOW EXCHANGES `len-1` WITH `len-min(dw,2)`; `nn_umin` IS NEW. | `nn_dot.order` |
| **BROADCAST** | `nn_dot.mul` (NEW) READS THE PRODUCT'S SHAPE AND REFUSES AN EMPTY ONE; `nn_dot.tail` TAKES THE PRODUCT; `nn_dot.pair` RETURNS A `Maybe`; `nn_dot.body` PASSES IT THROUGH. | `nn_dot.tail`/`pair`/`body` |

**THE THREE ANSWERS THE PORT GIVES, AND WHY THEY ARE THREE:**

- A SHAPE -- THE PORT ANSWERED.
- `NONE` -- THE PORT REFUSED. **THIS IS CPython's `raise`.**
- `<DEAD>` -- THE PORT BUILT A GRAPH WHOSE SHAPE DOES NOT FOLD. **NOT A REFUSAL:
  A WRONG GRAPH HANDED BACK AS IF IT WERE AN ANSWER.** (THE PROBE NAMES IT, SO
  THE DIFFERENCE IS VISIBLE IN THE ROWS.)

---

## 6. THE PROOF -- EVERY FIX ABLATED, EVERY CELL AN INSTRUMENT READ

`cases.rows` HAS EVERY CELL. **THE PORT'S ANSWER FOR EACH CASE AT EACH STEP:**

| case | x . w | CPython | **S0** AS IT STANDS | **S1** +GUARD | **S2** +WSHAPE | **S3** +ORDER | **S4** +BROADCAST |
|---|---|---|---|---|---|---|---|
| A | (2,3) . (3,4) | (2,4) | 2,4 | 2,4 | 2,4 | 2,4 | **2,4** |
| B | (2,4,3) . (3,4) | (2,4,4) | 2,4,4 | 2,4,4 | 2,4,4 | 2,4,4 | **2,4,4** |
| C | (8,64,7,7) . (7,16) | (8,64,7,16) | 8,64,7,16 | 8,64,7,16 | 8,64,7,16 | 8,64,7,16 | **8,64,7,16** |
| D | (2,3) . (3,) | (2,) | 2 | 2 | 2 | 2 | **2** |
| P | (2,3) . (4,5) | **REFUSE** (GUARD) | `<DEAD>` | `NONE` | `NONE` | `NONE` | **`NONE`** |
| E | (2,3,4) . (3,4,5) | **REFUSE** (BROADCAST) | `<DEAD>` | `<DEAD>` | `<DEAD>` | `<DEAD>` | **`NONE`** |
| F | (2,3,4) . (3,4,1) | **REFUSE** (BROADCAST) | `<DEAD>` | `<DEAD>` | `<DEAD>` | `<DEAD>` | **`NONE`** |
| **G** | **(3,3,4) . (3,4,1)** | **(3,3,1)** | `<DEAD>` | `<DEAD>` | **(3,3,4)** | **(3,3,1)** | **(3,3,1)** |
| H | (3,3,4) . (3,5,1) | **REFUSE** (GUARD) | `<DEAD>` | `NONE` | `NONE` | `NONE` | **`NONE`** |
| I | (3,3,4) . (3,4,2) | (3,3,2) | `<DEAD>` | `<DEAD>` | `<DEAD>` | (3,3,2) | **(3,3,2)** |
| M | (2,2,4) . (3,3,4,5) | **REFUSE** (BROADCAST) | `<DEAD>` | `<DEAD>` | `<DEAD>` | `<DEAD>` | **`NONE`** |
| N | (2,4) . (3,3,4,5) | (3,3,2,5) | `<DEAD>` | `<DEAD>` | `<DEAD>` | (3,3,2,5) | **(3,3,2,5)** |
| O | (2,4) . (3,3,5,5) | **REFUSE** (GUARD) | `<DEAD>` | `NONE` | `NONE` | `NONE` | **`NONE`** |

**ALL 13 CASES AGREE WITH CPYTHON AT S4** (`*_port_after_matches_cpython=true`
FOR ALL 13, MEASURED BY `mkrows.py`).

### WHAT EACH FIX IS WORTH -- READ THE TABLE COLUMN BY COLUMN

- **THE GUARD (S1) BUYS EXACTLY `P`, `H`, `O`:** THE THREE CASES CPython
  REFUSES **BY THE GUARD**. **IT CHANGES NOTHING ELSE -- NOT ONE `dw <= 2`
  ANSWER MOVED.**
- **THE `ws[axis_w:]` TERM (S2) IS NECESSARY BUT NOT SUFFICIENT:** IT MOVES
  `G` FROM `<DEAD>` TO **`(3,3,4)` -- A WRONG SHAPE, NOT AN EMPTY ONE.**
  **THIS IS THE MOST IMPORTANT ROW IN THE TABLE: WITHOUT THE ORDER FIX THE PORT
  ANSWERS A CONFIDENT WRONG ANSWER INSTEAD OF AN EMPTY ONE.** THE "RIGHT COUNT,
  WRONG GRAPH" HOLE, ONE LEVEL DOWN.
- **THE ORDER AXIS (S3) IS WHAT MAKES THE `dw >= 3` ANSWERS RIGHT:** IT MOVES
  `G` TO `(3,3,1)`, `I` TO `(3,3,2)` AND `N` TO `(3,3,2,5)` -- **ALL THREE OF
  CPython's dw>=3 ACCEPTED ANSWERS.**
- **THE BROADCAST REFUSAL (S4) BUYS EXACTLY `E`, `F`, `M`:** THE THREE CASES
  CPython REFUSES **BY THE BROADCAST**. **IT CHANGES NOTHING ELSE.**

**SO NO FIX IS REDUNDANT, AND EACH ONE IS EXACTLY LOCALIZED. THAT IS WHY THE
PATCH IS FOUR SMALL THINGS AND NOT ONE BIG ONE.**

### THE PORT'S OWN ROWS -- THE REGRESSION CHECK, MEASURED

`./bin/bend scratch*/nn/layers.bend` -- **THE SAME 31 ROWS BEFORE AND AFTER:**

| row | S0 | S4 | want |
|---|---|---|---|
| `dot_2d` | 2,4 | **2,4** | (2,4) |
| `dot_1d` | 2 | **2** | (2,) |
| `linear` | 2,10 | **2,10** | (2,10) |
| `linear_nobias` | 2,10 | **2,10** | (2,10) |
| `dbg_dot_sig` | n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE | **same** | |
| `fold_sm` | 2,4 | **2,4** | 2,4 |

**THE SIX RESIDUAL EMPTY ROWS ARE UNCHANGED AND ARE NOT MINE:** `fold_smk`
(`mo_at`), `conv_p1_s1`, `conv_p0_s1`, `conv_p1_s2`, `conv_seq`, `conv_bias`
(`nn_expand`/`cr_expand`). THEY WERE EMPTY BEFORE AND AFTER. THE PRIOR UNIT
NAMED BOTH DEFECTS AND SO DOES THE REPORT IT LEFT.

### THE COMPILER

```
./bin/bend --check-only .agents/slop/dw3/scratchfix/nn/layers.bend            -> ALL PROOFS CHECK
./bin/bend --check-only .agents/slop/dw3/scratchfix/extra/models/resnet.bend  -> ALL PROOFS CHECK
./bin/bend --check-only .agents/slop/dw3/scratchfix/extra/models/vit.bend     -> ALL PROOFS CHECK
./bin/bend --check-only .agents/slop/dw3/scratchfix/extra/models/bert.bend    -> ALL PROOFS CHECK
```

---

## 7. THE CONTROL -- THE GUARD DISCRIMINATES, IT DOES NOT ALWAYS REFUSE

**TWO CASES AT `dw == 3` WITH THE **SAME** `x` AND A ONE-DIM DIFFERENCE IN `w`:**

| case | x . w | `x.shape[-1]` | `w.shape[axis_w]` | CPython | PORT S0 | PORT S4 |
|---|---|---|---|---|---|---|
| **G** | (3,3,4) . (3,4,1) | 4 | **4** | **ACCEPT -> (3,3,1)** | `<DEAD>` | **(3,3,1)** |
| **H** | (3,3,4) . (3,5,1) | 4 | **5** | **REFUSE -> `RuntimeError: cannot dot (3, 3, 4) and (3, 5, 1)`** | `<DEAD>` | **`NONE`** |

**THE SECOND DIM OF `w` IS 4 IN G AND 5 IN H, AND THAT IS THE WHOLE DIFFERENCE
BETWEEN AN ANSWER AND A REFUSAL.** THE PORT NOW ANSWERS (3,3,1) FOR G AND
REFUSES H. **THE GUARD IS A COMPARISON, NOT A BLANKET REFUSAL.**

**A SECOND CONTROL AT `dw == 2`:** `A`/`B`/`C`/`D` ARE ACCEPTED AND `P` IS
REFUSED, **AND `P` WAS REFUSED BY THE GUARD BEFORE THE PATCH TOO -- BUT THE PORT
ANSWERED A DEAD GRAPH INSTEAD OF A REFUSAL.** THE PATCH CHANGES THE *REPRESENTATION*
OF THE REFUSAL, NOT THE SET.

**A THIRD CONTROL, THE ONE THAT MATTERS MOST:** `E`, `F` AND `M` PASS THE GUARD
AND STILL REFUSE -- **SO THE BROADCAST REFUSAL IS NOT THE GUARD IN DISGUISE.**

---

## 8. THE BLAST RADIUS

**WHAT THE PATCH TOUCHES:** `tinybendygrad/nn/layers.bend` ONLY. **FOUR DEFS
CHANGED AND TWO ADDED:** `nn_dot.wshape`, `nn_dot.order`, `nn_dot.tail`,
`nn_dot.body`, `nn_dot.pair`; ADDED `nn_dot.guard`, `nn_dot.guard.ans`,
`nn_dot.mul`, `nn_umin`; AND `nn_dot.rd`.

**EVERY ONE OF THOSE NAMES IS FILE-LOCAL.** MEASURED, FOR EACH OF
`nn_dot.wshape`, `nn_dot.order`, `nn_dot.rd`, `nn_dot.guard`, `nn_dot.tail`,
`nn_dot.mul`, `nn_dot.pair`, `nn_dot.body`, `nn_dot.go`, `nn_dot.xshape`,
`nn_dot.dts`:

```
grep -rn "<name>" tinybendygrad/ gates/ checks/ extra/ | grep -v nn/layers.bend   ->  NOTHING
```

- **`nn_dot.pair`'s RETURN TYPE CHANGED** (`T.Tensor` -> `Maybe<&2, T.Tensor>`)
  AND **`nn_dot.tail`'s FIRST PARAMETER CHANGED** (THE PRE-MUL `x` -> THE
  PRODUCT). BOTH ARE CALLED ONLY FROM INSIDE THIS FILE. **NO CALLER CAN BREAK.**
- **`nn_dot` ITSELF** IS CALLED FROM `nn_linear` (`layers.bend:495`, WHICH
  PROPAGATES THE `Maybe` THROUGH `Maybe.bind`) AND FROM THE FILE'S OWN ROWS.
- **`nn_dot.dts` IS UNCHANGED**, SO `nn_conv2d` (WHICH USES IT) IS UNCHANGED.
- **THE MODEL FILES** ONLY *MENTION* `nn_dot` IN COMMENTS -- MEASURED, EXACTLY
  FIVE OF THEM: `extra/models/{transformer,t5,bert,clip,rnnt}.bend` -- AND THEY
  CALL `nn_linear`. `--check-only` ON resnet/vit/bert: **ALL PROOFS CHECK.**
- **NO GATE AND NO CHECK NAMES `nn_dot`** (MEASURED:
  `grep -rln "nn_dot" gates/ checks/` -> NOTHING). **NO LAW AND NO PROOF
  NAMES THE OLD BEHAVIOUR** (`grep -rn "nn_dot" tinybendygrad/LAWS.bend
  tinybendygrad/PROOF.bend` -> NOTHING).

**WHAT ELSE THE PATCH COULD AFFECT -- NAMED, NOT GUESSED:**

1. **`nn_dot` NOW REFUSES MORE.** EVERY CASE WHOSE GUARD FAILS, AND EVERY
   `dw >= 3` CASE WHOSE BROADCAST FAILS, NOW ANSWER `None` INSTEAD OF A DEAD
   GRAPH. **A CONSUMER THAT TREATED AN EMPTY SHAPE AS "SOMETHING" NOW GETS
   `None`** -- WHICH IS THE PORT'S OWN VOCABULARY FOR "CPython RAISES".
2. **A REFUSED `dot` NOW COSTS A FOLD.** `nn_dot.mul` READS THE PRODUCT'S
   SHAPE, SO THE REFUSAL PATH FOLDS A GRAPH IT THROWS AWAY.
   **`nn_dot.go`'s `Bool.pick` ALREADY EVALUATED `nn_dot.body(...)` EAGERLY, SO
   THE GRAPH WAS ALWAYS BUILT; THE FOLD IS NEW.** FIXING THAT WOULD ADD A DEF
   AND CHANGE `nn_dot.go`'S SHAPE, SO IT IS **REPORTED, NOT DONE.**
3. **THE HEADER'S LINE-NUMBER CITATIONS MOVE FROM `:383`-`:390` TO `:387`-`:392`.**
   ANYTHING THAT CITED THE OLD NUMBERS (ONLY THIS FILE) IS CORRECTED HERE.
4. **NOTHING ELSE.** `nn_relu`, `nn_conv2d`, THE POOLS, THE PADS, THE DTYPES,
   THE `LAWS` AND THE `PROOFS` ARE UNTOUCHED.

---

## 9. WHAT I DID **NOT** DO, AND WHY

- **NO FILE OUTSIDE `.agents/slop/dw3/` WAS EDITED.** NO COMMIT. NO MUTATING GIT
  COMMAND. THE ONLY GIT COMMANDS WERE `git rev-parse HEAD`, `git status
  --porcelain` (WITH `env -u GIT_INDEX_FILE`), `git hash-object`,
  `git rev-parse HEAD:<path>` AND `git diff HEAD --stat` -- **ALL READS.**
  **VERIFIED: `git hash-object tinybendygrad/nn/layers.bend` ==
  `git rev-parse HEAD:tinybendygrad/nn/layers.bend` == `9fa65b38...`, SO I DID
  NOT TOUCH IT.** (THE `MM` IN `git status` IS THE ARMED-INDEX ARTIFACT
  `AGENTS.md` DOCUMENTS, NOT A CHANGE.)
- **I DID NOT RUN** `checks/differ.py`, ANYTHING UNDER `gates/`, `checks/e2e*`,
  `checks/sweep.py`, `checks/bounded.py`, ANY CORPUS-WIDE RUN, `pytest`, `mypy`
  OR `ruff`. **THE ONLY `bend` PROCESSES WERE `--check-only` AND THE PROBES ON
  SCRATCH COPIES.**
- **I DID NOT FIX** THE `mo_at` / `mo_reduced` / `nn_expand` DEFECTS (THE
  RESIDUAL EMPTY ROWS).
- **I DID NOT LAND** `dw3.diff`. **THE ORCHESTRATOR OWNS THAT CALL.**
- **I DID NOT EDIT `.agents/TODO.md` OR `.agents/TOOLS.md`** -- **THEY ARE
  OUTSIDE MY WRITE AREA.** FLAGS FOR THE ORCHESTRATOR:
  **`.agents/TODO.md` SHOULD CARRY A LINE FOR THE `dw >= 3` ARM OF `nn_dot`
  (NOW MEASURED, FIXED IN `dw3.diff`, UNLANDED), AND `.agents/TOOLS.md` SHOULD
  NAME `tinygrad/mixin/op.py:389` AS THE `dot` GUARD -- THE CITATION IN THE
  PORT'S OWN HEADER NAMED `:383`-`:390` AND THE WRONG FORMULA.**
- **NO `.txt` FILE WAS CREATED.** (`find .agents/slop/dw3 -name '*.txt'` -> 0.)

---

## 10. THE FILES

| file | what |
|---|---|
| **`dw3.diff`** | **THE PATCH.** `a/tinybendygrad/nn/layers.bend` -> `b/...`. 192 lines. `patch -p1 --dry-run` -> rc=0. |
| **`cases.rows`** | **THE PROOF TABLE.** EVERY CELL AN INSTRUMENT READ, AT FIVE ABLATION STEPS. |
| `REPORT.md` | THIS FILE. |
| `cpython_oracle.py` | THE ORACLE. MEASURES THE GUARD EXPRESSION'S PARSE, ENUMERATES 14,040 SHAPE PAIRS AGAINST THE RULE PREDICTED FROM THE SOURCE, AND PRINTS THE 13 NAMED CASES. |
| `cpython.out` | ITS CAPTURED OUTPUT. |
| `mkvariants.py` | **BUILDS THE FOUR ABLATION TREES** FROM THE TREE'S OWN FILE BY APPLYING NAMED FIXES IN A NAMED ORDER, AND **ASSERTS THAT S4 IS BYTE-IDENTICAL TO `scratchfix.hand.bend`**, SO THE DIFF AND THE VARIANTS CANNOT DRIFT. |
| `variants.out` | ITS CAPTURED OUTPUT. |
| `probe.bend`, `probe_g.bend`, `probe_gw.bend`, `probe_gwo.bend`, `probe_fix.bend` | THE PORT PROBES. **ONE LINE DIFFERS BETWEEN THEM (THE IMPORT PATH).** `diff` SAYS SO. |
| `port*.out` | THE PORT'S ANSWERS, ONE FILE PER ABLATION STEP. |
| `rows_*.out` | THE PORT'S OWN 31 ROWS, ONE FILE PER ABLATION STEP. |
| `mkrows.py` | TURNS THE CAPTURED OUTPUTS INTO `cases.rows`. **TYPES IN NOTHING.** |
| `collect.sh` | RUNS ALL OF IT, IN ORDER, AND REBUILDS `cases.rows`. |
| `scratch/` | A COPY OF THE WHOLE PORT, **BEFORE** (S0). |
| `scratchg/` | **S1** = S0 + THE `:389` GUARD. |
| `scratchgw/` | **S2** = S1 + THE `ws[axis_w:]` TERM. |
| `scratchgwo/` | **S3** = S2 + THE TRANSPOSE AXIS. |
| `scratchfix/` | **S4** = S3 + THE BROADCAST REFUSAL + THE HEADER. **THE PATCHED TREE.** |
| `scratchfix.hand.bend` | THE HAND-EDITED S4, KEPT SO `mkvariants.py` CAN COMPARE IT WITH ITS OWN OUTPUT. |

**COMMANDS (ALL CHEAP, ALL SEQUENTIAL, ALL UNDER 20 s AND UNDER 200 MB):**

```
.venv/bin/python .agents/slop/dw3/cpython_oracle.py
.venv/bin/python .agents/slop/dw3/mkvariants.py
./bin/bend .agents/slop/dw3/probe.bend
./bin/bend .agents/slop/dw3/probe_g.bend
./bin/bend .agents/slop/dw3/probe_gw.bend
./bin/bend .agents/slop/dw3/probe_gwo.bend
./bin/bend .agents/slop/dw3/probe_fix.bend
./bin/bend .agents/slop/dw3/scratch/nn/layers.bend
./bin/bend .agents/slop/dw3/scratchg/nn/layers.bend
./bin/bend .agents/slop/dw3/scratchgw/nn/layers.bend
./bin/bend .agents/slop/dw3/scratchgwo/nn/layers.bend
./bin/bend .agents/slop/dw3/scratchfix/nn/layers.bend
./bin/bend --check-only .agents/slop/dw3/scratchfix/nn/layers.bend
.venv/bin/python .agents/slop/dw3/mkrows.py .agents/slop/dw3/cases.rows
sh .agents/slop/dw3/collect.sh          # ALL OF THE ABOVE, IN ORDER
```
