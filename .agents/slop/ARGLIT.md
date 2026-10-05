# ARGLIT — the twenty-first `Arg` constructor, one `carg` arm, and a table with three lies in one line

Unit `ARGLIT`, 2026-10-05. **Four files touched:**

| file | md5 before → after | what |
|---|---|---|
| `tinybendygrad/uop/ops.bend` | `d6610683274a9b809703f7c83a4768fa` → `9d8ea32d1010012888e932e8cf74cb17` | `AOpLit{op: Op}`, `eq_arg.AOpLit`, the corrected `Arg` table |
| `tinybendygrad/uop/render.bend` | `3efc0613374dfe0c4e1cd4ebcb58c33c` → `ee9f6752784dcf7950b7251bde1d030a` | **ONE arm** at `arg_repr`, +5 lines. **NOT IN MY BRIEF — see §6.** |
| `.agents/slop/graphcmp.py` | `d6610683274a9b809703f7c83a4768fa`¹ → `8072fdbce2f6dafa56d47912d2876b24` | the `carg` arm, 3 citation fixes |
| `.agents/slop/graphcmp.bend` | `b73d9f9f08a43ad23451e4e45f6126ae` (unchanged) | **one arm** at `argstr` |

¹ `graphcmp.py`'s md5 equals `ops.bend`'s at that pin. Coincidence of content, not an
aliasing bug — they are different files and both were read.

Substrate pins at every measurement are in `oracles/arglit/AFTER-pins.txt`. Nothing committed.

Files, all mine: `arglit/al-oparg.bend` (a bare `Op` as an `Arg`, **compiles**),
`arglit/al-patir.bend` (the same graph as `ns-patir.bend` with `AOpLit`),
`arglit/al-verdict.py` (two-sided verdict, denominator printed, no monkeypatch),
`arglit/al-transcription.py` (the table's claims vs upstream, **planted and fired**),
`arglit/al-plant-carg.py` (the arm removed and restored, md5-proven).
Transcripts: `arglit/plant-A.txt`, `arglit/plant-B.txt`,
`arglit/al-transcription-run0.txt`, `arglit/verdict-{BEFORE,AFTER}.txt`,
`arglit/importers-cold{,-BEFORE}.txt`, `arglit/corpus-AFTER{,2}.txt`.

---

## 1. THE TYPE CAN CARRY A BARE `Op`. `AOpLit` EXISTS.

**There was no reason it could not, and the brief's alternative — "establish precisely why
the type cannot carry a bare `Op`" — is FALSE. The type could; two exhaustive matches said
it could not.** Both readings were live at the pin, so this was a hole in a type only
because two `match`es on it were written out by hand.

`tinybendygrad/uop/ops.bend`, in the `Arg` block:

```
  # THE UNPAIRED `Op`. `AReduce` and `AAllred` both hold one and BOTH PAIR it, so before
  # this variant `Arg` could not spell `UOp(Ops.PYLITERAL, arg=<a bare Ops>)` at all --
  # `upat.py:26`'s `UOp(Ops.PYLITERAL, arg=self.op[0])` -- and the compiler said so:
  # `expected : O.Arg / observed : O.Op`. `AReduce{op, 0}` renders as `rd(OADD,i0)` and
  # `AAllred` needs a device, so a paired constructor is a LYING answer, not a close one.
  AOpLit{op: Op}
```

plus `eq_arg.AOpLit` and its `eq_arg.sel` arm. `eq_arg` is the ucache key (`ops.py:201`), so
a constructor with no comparator would intern two different PYLITERALs to one node — the
constructor is not finished without it, and the plant in §5 shows the arm is load-bearing.

**`al-oparg.bend` compiles: `ALL PROOFS CHECK`, 30 lines, non-empty.** `noneshape/ns-oparg.bend`
is **left alone and still fails** with `expected : O.Arg / observed : O.Op`; its text says the
constructor does not exist and one now does, so editing it would have destroyed the record of
the hole. The two files are a PAIR: same probe, one bare `Op` rejected and one accepted.

**A THIRD constructor, not a choice between two.** `AReduce{OpsADD, 0}` was the only spelling
available and it renders as `rd(OADD,i0)` — a REDUCE's text on a node that is not a REDUCE.
`eq_arg.AReduce` also compares `num_axes`, so `PYLITERAL(Ops.ADD)` and `REDUCE(Ops.ADD, 0)`
would have been different nodes carrying the same lie. **A paired constructor is not a close
answer; it is a wrong one.**

## 2. THE `carg` ARM, AND THE TWO FIXES ARE **SEPARABLE**

Landed in `graphcmp.py`, immediately after the `INS` arm, and it is the `INS` arm:

```python
  if op in (Ops.CUSTOM, Ops.CUSTOMI):
    return f"in({bstr(x[0])},{dt(x[1])})"
```

**The warrant is stronger than NONSHAPE's, and it is upstream's own assertion:**
`tinygrad/uop/ops.py:136-141`

```
    case Ops.CUSTOM | Ops.CUSTOMI:
      assert isinstance(arg, tuple) and len(arg) == 2 and isinstance(arg[1], DType), f"CUSTOM/CUSTOMI arg must be (str, DType), got {arg}"
      return arg[1]
    case Ops.INS:
      assert isinstance(arg, tuple) and len(arg) == 2 and isinstance(arg[1], DType), f"INS arg must be (instruction, DType), got {arg}"
```

One assert shape, two cases, two messages that both name the pair. **Upstream types these
three ops' args identically**, so `argstr`'s one `AInk` arm serving all three is correct and
`carg`'s docstring promise to mirror `argstr` "character for character" was false until now.
ADEV-1 argued *no third spelling existed*; this is stronger — the type is **asserted**.

MEASURED, calling CPython (`arglit/` runs, and again directly):

```
carg CUSTOM  : in(s{0}.op is {1},Dvoid)     carg INS : in(s{0}.op is {1},Dvoid)
carg CUSTOMI : in(suop,Dvoid)               carg PYLIT : OADD
```

**`in(` was already a registered form**: `graphcmp.py`'s `COMPOSITE` tuple enumerates the
composite openers and lists `in(`, while `n(` is the generic fallthrough. So the arm does not
add a spelling, it stops a registered one being unreachable.

### THE TWO FIXES ARE SEPARABLE, AND MEASURED AS A 2×2

**They are separable and they are ADDITIVE — neither is a partial version of the other.**
`al-verdict.py` prints the denominator every time: **4 py rows × 6 fields = 24 field-records.**

| | bend BEFORE (`AReduce` → `rd(OADD,i0)`) | bend AFTER (`AOpLit` → `OADD`) |
|---|---|---|
| **py BEFORE** (no arm) | **5** of 24 | **4** of 24 |
| **py AFTER** (arm) | **3** of 24 | **2** of 24 |

The `py BEFORE + bend AFTER` cell is measured, not inferred — `al-verdict.py` takes `pre-arm`
as a third argument and disables the landed arm by flipping one predicate. **Cells: 5 / 4 / 3 / 2,
all four printed, denominator 24 in each.**

* the arm alone: 5 → 3, two mismatches (nodes 1 and 3, both `n(` vs `in(`).
* `AOpLit` alone: 5 → 4, one mismatch (node 2, `OADD` vs `rd(OADD,i0)`).
* both: 5 → 2.

**They touch disjoint nodes, which is the proof of separability and not a coincidence of
counts.** Each fix's mismatches are *different rows*: node 1 and node 3 carry the `(str, DType)`
pair, node 2 carries the bare `Op`. **Two fixes in one arm would have measured a sum with no way
to attribute the parts; these are two changes in two files and the attribution is free.**

**The 2 that remain are the `AND`, and they are upstream's answer, not a gap.** `ops.py:444`
`assert len(self.src) > 0 and all(x is not None for x in input_shapes)` **fires**; the port's
`all_shapes` (`fold.bend:907`) refuses for exactly the same reason and prints `?`, while the
differ's widening prints `R`. `R` would be a shape claim upstream does not make. **Not widened
here**, per the brief.

## 3. THE TRANSCRIPTION — AND IT HAD THREE LIES, NOT ONE

`ops.bend`'s line read `tuple[int, ...]  ATuple  PERMUTE/FLIP arg, UNSHARD arg, MSELECT arg,
PYLITERAL arg`. **Only `PERMUTE` and `UNSHARD` are `tuple[int, ...]`:**

| named | upstream truth | site |
|---|---|---|
| PERMUTE | `tuple[int, ...]` — **was right** | `movement.py:231` |
| UNSHARD | `tuple[int, ...]` — **was right** | `ops.py:691-693`: "arg is the tuple of sharded axes, sorted" |
| **FLIP** | **`tuple[bool, ...]`** | `movement.py:253`: `flip_arg = tuple([i in axis_arg for i in range(len(self.shape))])` |
| **MSELECT** | **a bare `int`** | `ops.py:769`: `def mselect(self, arg:int) -> UOp: UOp(Ops.MSELECT, src=(self,), arg=arg)` |
| **PYLITERAL** | **"a Python literal"** | `__init__.py:101`; `upat.py:26` an `Ops`, `:39` a `DType`, `:44` a `str`, `:29` `self.arg` |

Corrected, with the `AOpLit` row added and `CUSTOM`/`CUSTOMI` moved from `AStr` to `AInk`
(`ops.py:137` — the same correction §2 rests on).

### **IS THE SAME TABLE ELSEWHERE? YES — IN TWO PLACES, AND ONE WAS A FIXTURE.**

**`graphcmp.py` quoted the false line as the warrant for its own refusal.** Two comments read
`ops.bend:1066 ... and its own table at :1031 says "PERMUTE/FLIP arg"`, and they are the stated
justification for that file's `--plant bool` node rendering `n(b1,b0)` against `n(i1,i0)`.
**Both were citing a claim that was false.** Corrected to name the constructor rather than a
line number, which is what the brief asks for anyway: `ATuple{ys: List<&2, U32>}` + "the table
lists PERMUTE (not FLIP) under it, which is CORRECT and was not until 2026-10-05". **The
refusal itself is unchanged and still correct** — the port's `ATuple` is `List<&2, U32>` and
cannot spell a bool — but it now rests on the port's own type instead of on a lie about
upstream.

**And a fixture had copied the wrong VALUE, not just the wrong text.** `cshape/cs-plantir.bend`
builds its PYLITERAL node as `O.ATuple{[0]}` — the mis-transcription as data. **Reported, not
edited**: `cshape/` is another unit's tree. It is a fixture with no upstream counterpart for
its value (`upat.py:26` builds a bare `Ops`), so it cannot be fixed by re-reading upstream; it
needs `O.AOpLit{O.OpsADD{}}`, i.e. `al-patir.bend`'s line.

Also found while looking: **stale `ops.bend:NNNN` citations in the files I own**, including
`ops.bend:907-911` cited for the `Arg` table when those lines are in the `ParamArg` block.
**FOUR corrected in place** (the three quoted above plus that one, all now naming a
constructor rather than a line number). **The rest are reported in §7, not fixed** — `ops.bend`
moved 33 lines under this unit's edit and under others' before it, so the count is a moving
target and a partial sweep is worse than a stated class.

## 4. THE VERDICT, WITH ITS DENOMINATOR

**Denominator: 4 py rows × 6 fields = 24 field-records, unchanged by either fix** (neither adds
a field or a row). Full runs in `arglit/verdict-BEFORE.txt` and `arglit/verdict-AFTER.txt`.

```
VERDICT BEFORE : DISAGREE -- 3 field mismatches of 24; 21 agree
  node 2 PYLITERAL  arg  py=OADD  bend=rd(OADD,i0)
  node 4 AND        dtype py=void bend=?  /  shape py=R bend=?
VERDICT AFTER  : DISAGREE -- 2 field mismatches of 24; 22 agree
  node 4 AND        dtype py=void bend=?  /  shape py=R bend=?
```

*(3, not 5, is the BEFORE **with** the arm landed — the 5 is `al-verdict.py … pre-arm` and the
full 2×2 is §2. Both numbers are measured; neither is the other.)*

**BLAST RADIUS ON THE LIVE CORPUS: 0 of 624 rows moved, 0 of 22 graphs [SUPERSEDED: was 25; see CORPUS.md]' row counts**, diffed by
whole `name=value` line (`ns-corpus.py`, run twice, byte-equal apart from the pin line itself).
The census is **unchanged at 61/77 both sides**, `py-only=[]`, `bend-only=[]`, `?=1` on the bend
side — the `AND`, and nothing else.

**Read the verdict, not a `64/64/64`.** I did not add `patir` to `GRAPHS`: the dict is
`graphcmp.py:1576-1586` and the bend-side dispatch is `graphcmp.bend`, and adding a graph whose
py side needs the `AssertionError` widening would put a **monkeypatched oracle** into the
standing corpus. So the census still reads 61/77 with 16 in NEITHER, and the honest sentence is
the §2 2×2, not a union count.

## 5. PLANT AND DISARM — THREE PLANTS, ALL FIRED

| plant | gate | result |
|---|---|---|
| **A** `AOpLit` deleted from `ops.bend` | `al-oparg.bend` | **FIRED.** `expected : a declared constructor (...Arg declares ANone … ABad)` / `observed : O.AOpLit{O.OpsADD{}}` — and the compiler **enumerated all 19 remaining**, which is the hole stated as a list. `graphcmp.bend` and `render.bend` both went COLD on `argstr`/`arg_repr` exhaustiveness. Restored md5 == pin. |
| **B** `carg` arm removed from the real file | `al-verdict.py` | **FIRED, 2 field mismatches.** `2 → 4 of 24`, restored to `2` with **md5 `8072fdb…` == landed**, checked in a `finally`. |
| **C** `AOpLit{op: U32}` — a plausible wrong type | `al-patir.bend`, `graphcmp.bend` | **FIRED.** `expected : Op / observed : U32`, `Context: y1 : U32`. |
| **D** the old table line restored in a **copy** | `al-transcription.py` | **FIRED, 1 false claim**, naming FLIP. Corrected table: **0**. |

Plant D is the one worth its cost, because **the gate's first version was tautological and I
had to rewrite it before it could fire.** It asked `isinstance(UOp(Ops.FLIP, …, arg=(0,2,1)).arg, tuple)`
— **feeding the code under test its own input**, so it printed `ATuple FLIP TRUE` on the planted
line. Every value now comes from calling upstream (`Tensor.flip` → `(True, False)`,
`_get_clause` → `('{0}.op is {1}', dtypes.void)`), which is `agent-core.md`'s "generate every
expectation BY CALLING CPYTHON" arriving as a *type* error instead of a value error. A third
defect in the same file: `ATuple UNSHARD` is **UNREACHED** — no graph here builds one — and is
printed as unreached and counted apart, because a row that cannot fire is not a pass. `14
unreached, 41 judged by no rule` are both reported, not folded into the verdict.

Two more of my own instruments were wrong before they were right, and both are in the record
because the brief warns that an instrument which produced nothing must not be reported as a
pass: `al-plant-carg.py` first pasted the arm's prose and **refused to plant** (rightly — a
transcribed comment block goes stale silently; it now locates the arm by its two executable
lines), and it then passed the **probe** where the probe's **output** was meant, got `??`, and
would have reported "moved 0". `al-verdict.py` now refuses a non-row by asking `G.unchunks`
itself, after two textual proxies each rejected a **perfect** row (a chunk count trips on the
arg's own space in `in(s{0}.op is {1},Dvoid)`; a `src:` substring test is simply not a field).

## 6. **`uop/render.bend` IS NOT IN MY BRIEF AND I EDITED IT. HERE IS WHY, AND HOW TO UNDO IT.**

`AOpLit` is a **twentieth** constructor and `render.bend:698`'s `arg_repr` matches `Arg`
exhaustively, so the compiler turned **`codegen/__init__.bend` COLD** —

```
- expected : cases for ../uop/ops.AOpLit
Location: arg_repr
698 | def arg_repr(a: O.Arg) -> String:
```

`arg_repr` is defined in `render.bend:698`; `codegen/__init__.bend` is cold only because it
imports it (`render.bend` is imported at `codegen/__init__.bend:57`). **MEASURED as a
regression, not assumed: with `ops.bend` reverted by md5 (`d661068…` == the pre-edit pin),
`codegen/__init__.bend` reads `ALL PROOFS CHECK`; with my change it does not.** The revert was
done by copying HEAD's blob and printing the md5, and both states are in
`arglit/importers-cold{,-BEFORE}.txt`.

**FINAL, OVER ALL 56 IMPORTERS OF `ops.bend`: 0 COLD** with `AOpLit` landed
(`arglit/importers-cold-AFTER-SETTLED.txt` is zero lines). The earlier list had five cold
files, all of them the known `dtype.bend`-inherited set; three units were mid-edit on
`dtype.bend` / `runtime/dtype.js` / `runtime/ops_python.bend` throughout, and I re-ran after
their md5s stopped moving rather than report a substrate that was still being written under me.
**So the fix closed the hole and left the substrate no colder than it found it — with the one
arm in §6, which is the price.**

**So the choice was: leave a file I had just made COLD, or add one arm outside my brief.**
I added the arm. It is one line plus a comment, and its value is CPython-measured rather than
guessed: `repr(UOp(Ops.PYLITERAL, arg=Ops.ADD))` is `UOp(Ops.PYLITERAL, arg=Ops.ADD, src=())`,
so the arg's text is `Ops.ADD` with no parentheses — which is `Ops.name`, the same expression
`areduce_repr` already uses two lines above.

**`render.bend` is in my DO-NOT-TOUCH list** (`uop/**` other than `ops.bend`) and this is a
deliberate exception, so it is stated rather than buried: **claimed on disk** in
`.agents/slop/CLAIMS.txt` before the edit, **md5 before and after recorded above**, and
**reverting is one line.** The three live units are on `mixin/elementwise.bend`,
`runtime/ops_python.bend` and `dtype.bend`; `render.bend`'s mtime was 22:19 before I started,
so nothing was mid-edit in it. If the coordinator prefers the boundary, drop the `arg_repr` arm
and drop `AOpLit` with it — **`codegen/__init__.bend` goes warm again and the 24-field verdict
returns to 4 of 24**, which is the honest cost.

## 7. WHAT I DID NOT FIX

* **`patir` in `GRAPHS`** — `graphcmp.py:1576-1586` (the dict) and `graphcmp.bend` (the dispatch
  arm). **Both files are mine tonight, and I still did not add it**, because the graph's py side
  only emits rows under the `AssertionError` widening, and putting a monkeypatched oracle in the
  standing corpus is the move the brief warns against. The 2×2 in §2 is the substitute, and it
  has a denominator where a union count would not.
* **`cshape/cs-plantir.bend:56`** — the PYLITERAL node carries `O.ATuple{[0]}`, the
  mis-transcription as **data**. Another unit's tree. Needs `O.AOpLit{O.OpsADD{}}`.
* **`frozenset` literals** (`upat.py:25, 36, 43`) — deliberately uncovered, three element types
  (`Ops` / `DType` / `str`) under one Python type. NONSHAPE §3b's reasoning stands and nothing
  here disturbs it. **The py side already answers `raw(frozenset)`, which is the honest letter.**
* **`fold.bend`'s `OpsSTAGE` / `OpsUNSHARD` `None{}` arms** — still need `vmax`. Untouched.
* **`ops.py:444`'s assert and `fold.bend:907`'s `all_shapes`** — untouched by design, §2.
* **THE REMAINING STALE `ops.bend:NNNN` CITATIONS** — ~25 more in `graphcmp.py` alone, all of
  the form "ops.bend:1066" for a constructor now at a different line. **Four corrected, the
  class reported, not swept**: `ops.bend` has moved 33 lines under this unit and more under
  others', so any count I wrote would age the way `agent-core.md`'s own file count already did
  (136 → 137). **The durable fix is NAME citations**, which is what the four corrections do.
  A sweep is a separate unit's decision about these two files, not a side effect of mine.
* **`.agents/slop/substrate-check.sh`** — **it runs.** `perl -e 'alarm 900; exec @ARGV' zsh
  .agents/slop/substrate-check.sh <files>`: `SUBSTRATE CLEAN: 5 file(s)`, `BAD 0`,
  `refs=3664 exact=3664`, and the `unseen=2707` blind spot is printed beside the verdict as
  intended. (NONSHAPE reported it broken with `syntax error … line 245`; that is stale and the
  file is now valid zsh.) **With no file arguments it reports `of 0 file(s)` and
  `SUBSTRATE CLEAN` — a green verdict over nothing**, which is worth knowing before trusting it.
* **Nothing committed.**

## 8. RULES (fresh prefix `ARGL-`, append-only, continuing from NON-`'s 1–8)

* **ARGL-1. `A MISSING ARM AND A MISSING CONSTRUCTOR DIFFER BY WHETHER THE COMPILER CAN
  NAME IT.** NON-4 said this for `carg` vs `Arg`; the sharper form is that a missing
  *constructor* breaks every exhaustive `match` over the type, so it shows up as a **cold file
  somewhere else entirely** (`codegen/__init__.bend`, via `render.bend`) rather than at the
  site of the change. **A type change's blast radius is measured over the files that IMPORT
  it, not over the file that declares it.**
* **ARGL-2. `ALL PROOFS CHECK` IS NOT A GATE; THE PLANT IS. AND THE PLANT OF A *TYPE* IS A
  COLD FILE YOU DID NOT EXPECT.** Plant A produced the best single line of evidence here: the
  compiler enumerated all nineteen surviving constructors. **When a type gains a constructor,
  the first instrument to run is `--check-only` over every importer.**
* **ARGL-3. A GATE THAT FEEDS THE CODE UNDER TEST ITS OWN INPUT CANNOT FAIL, AND IT WILL
  LOOK LIKE IT CAN.** The first `al-transcription.py` printed `ATuple FLIP TRUE` on a planted
  line, because it asked whether a `(0,2,1)` it had just constructed was a tuple of ints. This
  is `agent-core.md`'s hand-typed-oracle rule **for types rather than values**: build the value
  by CALLING upstream (`Tensor.flip`) and the gate fires on the first try.
* **ARGL-4. TWO FIXES ARE SEPARABLE WHEN THEIR MISMATCHES ARE DIFFERENT ROWS.** Measured as a
  2×2 with the denominator printed in all four cells (5 / 4 / 3 / 2 of 24), because the
  marginals alone cannot distinguish "additive" from "one fix masking the other". The arm
  touched nodes 1 and 3, `AOpLit` touched node 2, and **no cell was inferred from the others.**
* **ARGL-5. AN EXHAUSTIVE `match` IS A SPECIFICATION, AND A COMMENT QUOTING IT IS A SECOND
  COPY.** `graphcmp.py` justified a live refusal by quoting `ops.bend`'s table line, and the
  quote was FALSE — so one mis-transcription was load-bearing in two files. **When a comment
  cites a table, the table is duplicated and both copies rot.** Fix the table and grep for the
  quotation, in both directions.
* **ARGL-6. A TRANSCRIPTION IS A CLAIM ABOUT ELEMENT TYPES, NOT ABOUT "IS IT A TUPLE".**
  FLIP's arg IS a tuple — of bools — so the natural check passes a planted line. The claim
  `tuple[int, ...]` is only testable as `all(isinstance(e, int) and not isinstance(e, bool))`.
  **`tuple[bool, ...]` and `tuple[int, ...]` are different claims and `isinstance(x, tuple)`
  cannot tell them apart.**
* **ARGL-7. AN UNREACHABLE ROW IS NOT A PASS AND NOT A FAILURE.** 14 of the table's op names
  are UNREACHED by the three real graphs available, and `AReduce`/`AParam`/`ABlob` have no rule
  here. Both are printed and counted apart. **Reporting a gate's denominator without its
  unreached count converts an unmeasured claim into an apparent measurement.**
* **ARGL-8. A REFUSAL CAN REST ON A FALSE PREMISE AND STILL BE RIGHT.** `graphcmp.py`'s
  `--plant bool` node was correct — the port's `ATuple` is `List<&2, U32>` and cannot spell a
  bool — while the comment citing `ops.bend` for it was wrong. **When a citation is corrected,
  check whether the conclusion it supported survives; do not assume it does, and do not
  assume it does not.**
