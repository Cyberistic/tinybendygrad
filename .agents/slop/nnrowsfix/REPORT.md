# nnrowsfix -- closing the last thirteen rows of `tinybendygrad/nn/layers.bend`

**VERDICT: `13 of 31` BECAME `0 of 31`. THE GATE IS GREEN.**
`.venv/bin/python gates/nn-rows-gate.py` -> `PASS -- 31 of 31 rows match their
expectations, and the declared population is 31`, exit **0**.

- Unit: `nnrowsfix`
- Owned and edited: `tinybendygrad/nn/layers.bend` (ONE file), `.agents/slop/nnrowsfix/`
- **THE HEAD MOVED TWICE UNDER THIS UNIT, AND ALL THREE HEADS ARE NAMED.** Every
  measurement below was taken at **`95ab45bbacd232eea6c7618d010f79be6e38cbf9`**,
  except the last two, which were taken at **`e892a5aa72aea88fb4d5dd96812ae5dd57d9a4b3`**
  (18:50:43Z) and **`58140418c460800b0aaf341304f98f9e376b5514`** (18:51:14Z) -- other
  units committed while this unit was working. **NONE OF THE THREE MOVES TOUCHED
  THE SUBSTRATE**, MEASURED:
  `git diff --name-only 95ab45bb e892a5aa -- tinybendygrad/` is **0 paths**,
  `git diff --name-only e892a5aa 58140418 -- tinybendygrad/` is **0 paths**, and
  `git rev-parse <h>:tinybendygrad/nn/layers.bend` is the **SAME BLOB
  `1533fc8d2c6b5e9a0353d3881533c109259398d5`** at all three HEADs. (The two moves
  differ in 11 paths in all, none of them under `tinybendygrad/`.) So the BEFORE
  reading is the same on every HEAD, and the AFTER was RE-TAKEN on each of the two
  new ones.
- Wall clock of the measurements below: **2026-10-23T18:37:36Z .. 18:51:14Z** (`date -u`)
- **NO COMMIT WAS MADE.** No mutating git command was run. The only git commands
  were `rev-parse HEAD`, `status --porcelain=v2`, `diff`, `diff --stat`, `show HEAD:<path>`,
  all with `env -u GIT_INDEX_FILE`.
- No other `.bend` file was touched. `checks/`, `gates/`, `references/`, `AGENTS.md`,
  `.agents/TODO.md` and `.agents/TOOLS.md` were read but not written. The only gate
  run is `gates/nn-rows-gate.py` (this unit's instrument).

---

## 0. THE INSTRUMENT, AND WHAT IT JUDGES

`gates/nn-rows-gate.py`, 1060 lines (`wc -l gates/nn-rows-gate.py`).

**The population is derived from the harness's own source**, not from a hand list:
`parse_source` (line 263) reads the `nn_row.line(...)` call sites out of the copy's
`nn/layers.bend`, the function each site sits in (by indentation), and the
reachability closure from `main`. A string-literal name is a literal row; a
`String.concat([...])` of literals and `U32.show(x)` reads is a PATTERN with a digit
placeholder, and its multiplicity is the call count of the declaring function.

**The verdict is decided from the driver's stdout and the copy's own source**, and
nothing is transcribed into the gate. The port is COPIED first and read second
(`_materialize`, line 438), so the population and the rows cannot be a half-written
pair. **The expected values live only in the `.bend` file**: the gate reads them
from the printed `want=` column, so there is exactly ONE copy of every expectation
and this unit's edit is the only place a `want` can change.

The classes (`classify`, line 345):

| class | meaning |
|---|---|
| `MATCH` | `got == want`, exactly |
| `MISMATCH` | `want` is not empty and `got != want`; a subset carries the `[SPELLING]` mark |
| `UNCHECKABLE` | `want` is EMPTY and `got` is not -- **the row CANNOT FAIL** |
| `DEAD-ROW` | `want` is empty AND `got` is empty -- the row measured nothing |
| `SHRUNK` | declared by the source, not printed |
| `EXTRA` | printed and not declared by the source |
| `DUPLICATE` | printed more than once, or more times than declared |

The spelling rule (`canonical`, line 129): equal as TOKEN LISTS once punctuation is
dropped, case is folded, and `f32 == float32`. It holds **no expected value**; it is a
comparison rule and it is printed with every run so a reader can audit which rows it
forgave.

Exits are `gates/gatekit.py`'s: `PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5`.

---

## 1. THE THREE READINGS, AND WHY THERE ARE THREE

**THE BRIEF'S NUMBER IS THE HEAD NUMBER, AND THE TREE I INHERITED WAS ALREADY DIRTY.**
The brief quotes `MATCH=18/31 MISMATCH=8/31 UNCHECKABLE=5/31`. MEASURED at HEAD
(`git show HEAD:tinybendygrad/nn/layers.bend` carries the old `want`s) with the
gate's own `--baseline` option:

    .venv/bin/python gates/nn-rows-gate.py --baseline 95ab45bbacd232eea6c7618d010f79be6e38cbf9
    -> rows_declared=31 (28 literal name(s), 1 computed name(s) x 3 invocation(s))
    -> rows_printed=31
    -> MATCH=18/31 MISMATCH=8/31 UNCHECKABLE=5/31 DEAD-ROW=0/31 SHRUNK=0/31 EXTRA=0/31 DUPLICATE=0/31
    -> mismatching rows that differ only in SPELLING=8 of 8
    -> rows_not_passing_exact_comparison=13 of 31
    -> FAIL -- 13 of 31 rows do not pass under exact comparison (18 match, 8 mismatch of
          which 8 differ only in spelling, 5 uncheckable, 0 dead)      [exit 1]

That reproduces the brief EXACTLY. The full output is `gate-head.out`.

**BUT THE WORKING TREE I STARTED ON WAS NOT AT HEAD.** My first live run
(`gate-before.out`, 2026-10-23T18:37:57Z) read:

    -> MATCH=23/31 MISMATCH=3/31 UNCHECKABLE=5/31 DEAD-ROW=0/31 SHRUNK=0/31 EXTRA=0/31 DUPLICATE=0/31
    -> rows_not_passing_exact_comparison=8 of 31

**FIVE OF THE EIGHT SPELLING MISMATCHES HAD ALREADY BEEN CLOSED** by the previous
attempt at this unit, which died before writing a report: `git diff HEAD --
tinybendygrad/nn/layers.bend` showed `relu`, `dot_2d`, `dot_1d`, `linear` and
`linear_nobias` already re-spelled `"(1,4,8,8)" -> "1,4,8,8"` etc. **I did not
take those on trust**: the witness cross-check in §3 checks **ALL 31** `want`s
against CPython, the five included.

⇒ **MY WORK WAS THE EIGHT THAT REMAINED**: three DTYPE rows and five GRAPH rows.

---

## 2. CLASS ONE -- THE SPELLING MISMATCHES, AND WHERE EACH SPELLING COMES FROM

### 2.1 THE SPELLING IS THE PORT'S; THE VALUE IS CPython's

The port prints in three spellings, and each has ONE source in the port's own code.

**SHAPE -- `MX.mx_show`, `tinybendygrad/mixin/movement.bend:878`:**

    def mx_show(xs: List<&2, U32>) -> String: String.join(mx_shows.go(xs, Nil{}), ",")

The dims joined by a comma, **NO parentheses**. CPython's `Tensor.shape` is a TUPLE
and prints `(1, 4, 8, 8)`. So the shape rows' `want` is **CPython's dims in the
port's punctuation**. Five rows: `relu`, `dot_2d`, `dot_1d`, `linear`,
`linear_nobias`. (Closed by the previous attempt; verified by me.)

**DTYPE -- `E.ew_dtnm`, `tinybendygrad/mixin/elementwise.bend:1033`:**

    def ew_dtnm(dt: S.Dt) -> String:
      match dt:
        case S.Dt{pri, bits, cls, nm}: nm

It is the `nm` field of `S.Dt`, and the float32 dtype is
`S.single()` = `Dt{14, 32, CFloat{}, "f32"}` (`tinybendygrad/LAWS/spec.bend:741`).
**AND CPython's OWN NAME FOR float32 IS THE SAME STRING**: `tinygrad/dtype.py:136`
is `f32: Final[DType] = DType.new(14, 32, "f32", 'f')`, and `tinygrad/dtype.py:140`
is `float32 = half = f16; bfloat16 = bf16; float32 = float = f32; ...` -- **`float32`
is the ALIAS, `f32` is the NAME.** So for these three rows the port's spelling and
CPython's own name are one string, and `want="f32"` is BOTH.

**GRAPH -- `MX.mxw_sig`, `tinybendygrad/mixin/movement.bend:1380`:**

    def mxw_sig(+ar: O.Arena, +u: U32) -> String:
      String.concat(["n=", U32.show(mxw_count(ar, u)),
                      " op=", O.Ops.name(O.Arena.op(ar, u)),
                      " nsrc=", U32.show(O.Arena.nsrc(ar, u)),
                      " srcops=", String.join(mxw_srcops(ar, O.Arena.srcs(ar, u)), "|")])

`n=` is `mxw_count` = `List.length(O.UOp.toposort(...))` (movement.bend:1359) --
**the COMPILED ARENA's node count**. Five rows: `dbg_dot_sig`, `dbg_conv_sig`,
`dbg_x_sig`, `fold_cc_sig`, `fold_xw_sig`.

### 2.2 WHAT I CHANGED, AND HOW I KNOW THE VALUE IS CPython's

The three DTYPE rows (the whole edit, `git diff HEAD -- tinybendygrad/nn/layers.bend`):

    -    nn_row.line("where_xdt", nn_row_dt(T.tn_dtype(x)), "float32")
    +    nn_row.line("where_xdt", nn_row_dt(T.tn_dtype(x)), "f32")
    -    nn_row.line("where_wdt", nn_row_dt(T.tn_dtype(w)), "float32")
    +    nn_row.line("where_wdt", nn_row_dt(T.tn_dtype(w)), "f32")
    -    nn_row.line("where_dts", nn_row_dt(nn_dot.dts(T.tn_dtype(x), T.tn_dtype(w))), "float32")
    +    nn_row.line("where_dts", nn_row_dt(nn_dot.dts(T.tn_dtype(x), T.tn_dtype(w))), "f32")

**THE VALUE IS CPython's, AND THAT IS A MEASUREMENT, NOT A CLAIM.** The witness is
`.agents/slop/nnrowsfix/nn-oracle.py`, which imports `tinygrad` from this repo's
`.venv` and never reads the port. It prints `where_xdt=f32`, `where_wdt=f32`,
`where_dts=f32` (`nn-oracle.rows`). I RE-RAN IT and it is byte-identical to the
stored output (`diff nn-oracle.rows nn-oracle.rerun.rows` -> no output, rc=0).

**AND THE CHECK IS OVER ALL 31 ROWS, NOT ONLY OVER THE EIGHT I TOUCHED.**
`.agents/slop/nnrowsfix/mkrows.py` imports the gate BY PATH, calls the gate's own
`measure()`, and then asks a DIFFERENT question of every `want`: **is it byte-equal
to the witness's value for the same name?** MEASURED:

    .venv/bin/python .agents/slop/nnrowsfix/mkrows.py
    mkrows: gate_rc=0 rows_printed=31 rows_declared=31 duplicates=none
    mkrows: witness_rows=31 witness_names_not_in_the_port=[] port_names_not_in_the_witness=[]
    mkrows: wrote .../rows.rows with 31 rows
    mkrows: every one of the 31 `want`s is byte-equal to the witness's value for the same name

A `want` copied out of the port's own `got` would NOT be in the witness, so this is
what makes "the `want` is CPython's" a measurement. **THE CROSS-CHECK ALSO CONFIRMS
THE PREVIOUS ATTEMPT'S FIVE SHAPE ROWS.**

### 2.3 THE `fold_smk` ROW, CONFIRMED

`fold_smk` reads `got=2,4,1 want=2,4,1` and is GREEN after my edits:
`rows.rows` carries `fold_smk = [2,4,1] py=[2,4,1]`, and the gate's final verdict
has it in the `MATCH=31/31`. (Its old expectation `2,1,3` was CPython's answer for
axis `[1]`, not axis `[2]`.)

---

## 3. CLASS TWO -- THE FIVE GRAPH ROWS, AND THE SPEC-IR QUESTION

### 3.1 THE ORACLE'S OWN SIGNATURE CANNOT BE THE `want`, AND HERE IS THE PROOF

`gates/mixin-op-oracle.py:33-35` is the CPython oracle for `mixin/op.bend`, and its
signature is:

    def sig(t) -> str:
      us = t.uop.toposort()
      return f"{len(us)} " + " ".join(f"{u.op.name}/{len(u.src)}" for u in us) + " "

MEASURED side by side on the SAME fixture (the witness's own output prints both
formats for the same five graphs, `nn-oracle.rows`):

| | format | example (`dbg_x_sig`) |
|---|---|---|
| the ORACLE's own | `n OP/nsrc OP/nsrc ...` | `6 CONST/0 BUFFER/1 CONST/0 CONST/0 STACK/2 RESHAPE/2 ` |
| the PORT's `mxw_sig` | `n=<count> op=Ops.<root> nsrc=<n> srcops=<seq>` | `n=6 op=Ops.RESHAPE nsrc=2 srcops=Ops.BUFFER|Ops.STACK` |

**THESE ARE DIFFERENT FORMATS AND DIFFERENT LANGUAGES: `CONST` vs `Ops.CONST`,
`/1` vs `nsrc=1`, a whole node LIST vs a four-tuple summary.** The oracle's
signature cannot be the port's `want` because the port prints a different string,
and the gate compares EXACTLY (`row.got == row.want`). `gates/lanecmp.py` is the
tree's shape-agnostic COMPARATOR, not a signature format: it reads both shapes
(`F1` `name=value`, `F2` `name = [value] py=[value]`) and compares BY NAME AND BY
VALUE, and it says the same thing this section says -- *"the witness is the
ORACLE's row, and the question is 'does CPython's answer for this row equal the
port's answer for this row'"*.

⇒ **THE RIGHT WITNESS IS CPython's OWN GRAPH, RENDERED IN THE PORT'S SPELLING.**
That is what `nn-oracle.py` does:

    def sig(t):
        us = t.uop.toposort()
        root = t.uop
        srcops = "|".join("Ops." + s.op.name for s in root.src)
        return f"n={len(us)} op=Ops.{root.op.name} nsrc={len(root.src)} srcops={srcops}"

### 3.2 THE FIXTURE IS WHY, AND IT IS MEASURED

The port's fixture `nn_row.t(ns, slot, size)` is
`MX.mxw_reshape(MX.mxw_buf(O.Arena.empty(), slot, size), ns)` -- **a BUFFER and a
RESHAPE, with NO COPY**: `mxw_buf` (movement.bend:1231) builds
`O.UOp.new.param(ar, O.OpsBUFFER{}, Some{size}, ...)`.

Upstream's numpy path builds the same node -- `Tensor.__init__` calls `_fromnp`
(`tinygrad/tensor.py:37-40`), which is `UOp.new_buffer("NPY", x.size, ...)` -- **but
only while the requested device IS "NPY"**, because `tinygrad/tensor.py:93` is

    self.uop: UOp = data if data.device is None or data.device == _device else data.copy_to_device(_device)

so on the DEFAULT device the numpy buffer is COPIED and CPython's graph grows an
`Ops.COPY` the port has no node for. **MEASURED, both arms** (the witness's `sig`
on `device="NPY"`, and `.agents/slop/nnrowsfix/sig-oracle.py` on the default device,
whose output is `sig-oracle.rows`):

| fixture | default device | `device="NPY"` | the PORT's own `got` | COPYs |
|---|---|---|---|---|
| `dbg_x_sig` | `n=7 ... srcops=Ops.COPY\|Ops.STACK` | `n=6 ... srcops=Ops.BUFFER\|Ops.STACK` | `n=6 ... Ops.BUFFER\|Ops.STACK` | 1 |
| `dbg_dot_sig` | `n=22` | `n=20` | `n=20` | 2 (x, w) |
| `fold_xw_sig` | `n=20` | `n=18` | `n=18` | 2 (x, w) |
| `fold_cc_sig` | `n=22` | `n=20` | `n=20` | 2 (x, w) |
| `dbg_conv_sig` | `n=59` | `n=57` | `n=57` | 2 (xc, wc) |

**THE DIFFERENCE IS EXACTLY THE NUMBER OF BUFFERS.** The "NPY" arm is the one that
matches the port's fixture, and the port's own rows say `Ops.BUFFER`, so the "NPY"
arm is the right witness. **A witness built on the default device would have gone
red on a FIXTURE MISMATCH and called it a port defect.**

### 3.3 THE SPEC-IR QUESTION, AND ITS ANSWER

**THE QUESTION THE BRIEF ASKS: CAN `tinybendygrad/LAWS/spec.bend` RENDER THE
SIGNATURE? ANSWER: NO -- AND THE REASON IS PRECISE, NOT A GUESS.**

**WHAT `spec.bend` ACTUALLY IS.** `Sp` (spec.bend:422) is the SPECIFICATION IR: one
constructor per op in tinyspec.tex, an inductive **TREE**, with the derived
properties `Sp.shape` (:546) and `Sp.dtype` (:750). Its own header (spec.bend:3-14)
says what it is and what it is not:

    # This is the *specification* IR, not the compilation IR ...
    # The compilation IR (tinygrad/uop/ops.py) is a cyclic hash-consed graph in an
    # arena, because the range graph has back-edges and the test suite depends on
    # node identity. That IR cannot be a pure tree, so the laws cannot reach it.

**WHAT IT WOULD TAKE, AND WHAT IT CANNOT TAKE.** `mxw_sig` has four fields. Three
are mechanically addable to `spec.bend` and one is not:

1. `op=<root>` -- **ADDABLE**: one arm per constructor, `Sp.opname(s) -> String`.
2. `nsrc=<n>` -- **ADDABLE**: one arm per constructor, the arity is the constructor's.
3. `srcops=<seq>` -- **ADDABLE**: one arm per constructor, `Sp.srcs(s) -> List<&2, Sp>`.
4. `n=<count>` -- **NOT ADDABLE**, and this is the whole answer. `n=` is
   `mxw_count` = the **compiled arena's** toposort length. `Sp` is not that arena,
   for three measured reasons:

   a. **`Sp` IS A TREE AND THE ARENA IS HASH-CONSED.** The port's own fixture says
      it: *"The two CONSTs HASH-CONS to one node"* (`tinybendygrad/uop/fold.bend:4435`).
      Equal spec subtrees collapse to ONE arena node, so a tree count OVER-counts and
      no function of `Sp` can recover the arena's count.
   b. **`Sp` IS THE PRE-COMPILATION FORM.** `SpReshape` carries its target dims as a
      **VALUE** -- `dst: List<&2, Sdim>` (spec.bend:436) -- while the arena's RESHAPE
      carries a **STACK NODE** as its second source (*"A SHAPE ARG of ARBITRARY
      LENGTH, interned as a STACK of CONSTs"*, movement.bend:1234). **CONCRETE, AND
      MEASURED FROM THE PORT'S OWN OUTPUT:** the port's `dbg_x_sig` arena graph is
      **6 nodes** (`CONST(size) BUFFER CONST(2) CONST(3) STACK RESHAPE`) and the
      spec-level description of the same computation is
      `SpReshape{SpBuffer{6,...}, SpInvalid{}, [SN{2n},SN{3n}]}` -- **two `Sp` nodes
      and no node at all for the two CONSTs or the STACK.** 2 is not 6, and no
      function of `Sp` bridges that gap.
   c. **IT IS OUT OF REACH BY THAT FILE'S OWN DESIGN** (the header quoted above).

⇒ **THE PRECISE SPECIFICATION OF WHAT WOULD HAVE TO BE ADDED TO `spec.bend`**, if
one wanted a spec-IR witness for these rows: (i) `Sp.opname`, (ii) `Sp.srcs`, and
(iii) **a node count of the COMPILED graph** -- which requires modelling the
hash-consed arena (the compilation IR), i.e. exactly the thing spec.bend's header
declares it cannot reach. Without (iii) a spec-IR `want` could only be a
**DIFFERENT signature with no `n=`** -- and `mxw_sig` ALWAYS prints `n=`, so the row
could not use it: the `got` and the `want` would be two different strings and the
gate compares exactly.

⇒ **THIS UNIT IS NOT BLOCKED**, because the requirement is *"a source independent of
the fold being checked"*, and **CPython's own graph is one**: it is upstream
tinygrad's own graph construction, computed in this repo's `.venv`, and it never
reads the port. The five `want`s are that witness rendered in the port's spelling.

### 3.4 TWO OF THE FIVE `want`s ARE THE SAME STRING, AND THAT IS NOT A DEFECT

`dbg_dot_sig` and `fold_cc_sig` both answer
`n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE` -- **on BOTH sides**. The reason is
that they ARE the same computation: **upstream's `dot` IS a
reshape-transpose-multiply-sum-cast** (`tinygrad/mixin/op.py:367-392`: `x.reshape(...)`,
`w.reshape(...).transpose(...)`, `(x*w).sum(-1)`, `.cast(...)`), and the port's
`fold_cc` chain is that same computation spelled out of the port's own
`mxw_reshape`/`mxw_permute`/`tn_mul`/`nn_sum`/`mo_cast_t`. The port's `nn/layers.bend`
header says the same thing about `dot` in its own words: *"dot (op.py:367) is RESHAPE
+ RESHAPE + PERMUTE + MUL + REDUCE + CAST"*.

**⇒ THE TWO ROWS DIFFER IN THE CODE PATH THEY EXERCISE (the port's `nn_dot` against
the port's `nn_sum`+`tn_mul`+`mo_cast_t`) AND NOT IN THE GRAPH THEY PRODUCE, AND A
GRAPH SIGNATURE CANNOT TELL THEM APART.** A row whose `want` cannot distinguish its
sibling is a row that cannot say *which* path broke -- but it still says *that*
something broke, and the two rows together still cover both code paths. The other
three are distinct: `fold_xw_sig` is `n=18 ... Ops.MUL`, `dbg_x_sig` is
`n=6 ... Ops.BUFFER|Ops.STACK`, `dbg_conv_sig` is `n=57`.

**⇒ WHAT WOULD MAKE THEM DISTINGUISHABLE**, if that is wanted: the SIGNATURE is a
four-tuple summary and the whole NODE LIST is available on both sides -- see §4.

### 3.5 THE EDIT, IN FULL

    -    nn_row.line("dbg_dot_sig", nn_row.sig(nn_dot(x, w)), "")
    +    nn_row.line("dbg_dot_sig", nn_row.sig(nn_dot(x, w)), "n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE")
    -    nn_row.line("dbg_conv_sig", nn_row.sig(c), "")
    +    nn_row.line("dbg_conv_sig", nn_row.sig(c), "n=57 op=Ops.RESHAPE nsrc=2 srcops=Ops.RESHAPE|Ops.STACK")
    -    nn_row.line("dbg_x_sig", MX.mxw_sig(T.Tensor.ar(x), T.Tensor.u(x)), "")
    +    nn_row.line("dbg_x_sig", MX.mxw_sig(T.Tensor.ar(x), T.Tensor.u(x)), "n=6 op=Ops.RESHAPE nsrc=2 srcops=Ops.BUFFER|Ops.STACK")
    -    nn_row.line("fold_cc_sig", MX.mxw_sig(T.Tensor.ar(cc), T.Tensor.u(cc)), "")
    +    nn_row.line("fold_cc_sig", MX.mxw_sig(T.Tensor.ar(cc), T.Tensor.u(cc)), "n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE")
    -    nn_row.line("fold_xw_sig", MX.mxw_sig(T.Tensor.ar(xw), T.Tensor.u(xw)), "")
    +    nn_row.line("fold_xw_sig", MX.mxw_sig(T.Tensor.ar(xw), T.Tensor.u(xw)), "n=18 op=Ops.MUL nsrc=2 srcops=Ops.RESHAPE|Ops.PERMUTE")

---

## 4. THE STRONGER CROSS-CHECK: THE WHOLE NODE LIST, NOT THE FOUR-TUPLE

`mxw_sig` is a **four-tuple summary**, and two different graphs can share all four.
**THE PORT ALREADY HAS A PRINTER FOR THE WHOLE LIST**: `M.mo_valsig.of`
(`tinybendygrad/mixin/op.bend:1255`) prints `<n> OP/nsrc OP/nsrc ... ` **with the
CONST payloads** -- the same format the witness prints (`oracle_valsig`).

**MEASURED, with a SCRATCH DRIVER IN A COPY OF THE PORT** (no file in the repository
is written: the port is copied to a temporary directory, the driver is written INTO
THE COPY, `bin/bend` runs against the copy, `tempfile` removes it --
`.agents/slop/nnrowsfix/vsig.py`):

    .venv/bin/python .agents/slop/nnrowsfix/vsig.py
    vsig: THE WHOLE NODE LIST, the port's against the witness's:
    vsig: dbg_x_sig: IDENTICAL (6 tokens)
    vsig: dbg_dot_sig: IDENTICAL (20 tokens)
    vsig: dbg_conv_sig: IDENTICAL (57 tokens)
    vsig: fold_xw_sig: IDENTICAL (18 tokens)
    vsig: fold_cc_sig: IDENTICAL (20 tokens)
    vsig: all 5 node lists are IDENTICAL, node for node, CONST payloads included

**⇒ THE PORT'S COMPILED FOLD REPRODUCES CPYTHON'S GRAPH NODE FOR NODE ON ALL FIVE
FIXTURES, CONST PAYLOADS INCLUDED** -- e.g. `fold_cc_sig` is, on both sides,
`20 CONST/0=i6 BUFFER/1 CONST/0=i2 CONST/0=i3 STACK/2 RESHAPE/2 CONST/0=i1 STACK/3
RESHAPE/2 CONST/0=i12 BUFFER/1 CONST/0=i4 STACK/2 RESHAPE/2 STACK/3 RESHAPE/2
PERMUTE/1 MUL/2 PERMUTE/1 REDUCE/1 `.

**⇒ THIS IS WHAT MAKES THE FOUR-TUPE `want` NON-VACUOUS**: the four-tuple agrees
because the WHOLE graphs agree, and the whole graphs agree because they were
computed by two different implementations.

**⇒ AND IT ANSWERS §3.4's OPEN QUESTION**: the node list DOES distinguish the two
rows that the four-tuple cannot -- but not by name: `dbg_dot_sig` and `fold_cc_sig`
have the SAME node list too, because they are the same computation. The other three
are distinct.

---

## 5. THE GATE'S FULL VERDICT, BEFORE AND AFTER

**BEFORE, AT HEAD** (`--baseline 95ab45bb...`, exit **1**) -- the full output is in
`gate-head.out` and is quoted in §1: `MATCH=18/31 MISMATCH=8/31 UNCHECKABLE=5/31`,
`rows_not_passing_exact_comparison=13 of 31`, `FAIL`.

**BEFORE, ON THE TREE I INHERITED** (live, 2026-10-23T18:37:57Z, exit 1) --
`gate-before.out`:

    nn-rows-gate: measured_at=2026-10-23T18:37:57Z head=95ab45bbacd232eea6c7618d010f79be6e38cbf9
    nn-rows-gate: port=live copy of tinybendygrad (HEAD 95ab45bbacd2)
    nn-rows-gate: rows_declared=31 (28 literal name(s), 1 computed name(s) x 3 invocation(s))
    nn-rows-gate: computed-name pattern=conv_p\d+_s\d+ declared_by=nn_row_conv expected=3
    nn-rows-gate: rows_printed=31
    nn-rows-gate: MATCH=23/31 MISMATCH=3/31 UNCHECKABLE=5/31 DEAD-ROW=0/31 SHRUNK=0/31 EXTRA=0/31 DUPLICATE=0/31
    nn-rows-gate: mismatching rows that differ only in SPELLING=3 of 3 (the rule: punctuation dropped, case folded, f32==float32)
    nn-rows-gate: rows_not_passing_exact_comparison=8 of 31
    nn-rows-gate: MISMATCH where_xdt got='f32' want='float32' [SPELLING]
    nn-rows-gate: MISMATCH where_wdt got='f32' want='float32' [SPELLING]
    nn-rows-gate: MISMATCH where_dts got='f32' want='float32' [SPELLING]
    nn-rows-gate: UNCHECKABLE fold_cc_sig want is empty, so the row cannot fail (got='n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE')
    nn-rows-gate: UNCHECKABLE fold_xw_sig want is empty, so the row cannot fail (got='n=18 op=Ops.MUL nsrc=2 srcops=Ops.RESHAPE|Ops.PERMUTE')
    nn-rows-gate: UNCHECKABLE dbg_dot_sig want is empty, so the row cannot fail (got='n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE')
    nn-rows-gate: UNCHECKABLE dbg_conv_sig want is empty, so the row cannot fail (got='n=57 op=Ops.RESHAPE nsrc=2 srcops=Ops.RESHAPE|Ops.STACK')
    nn-rows-gate: UNCHECKABLE dbg_x_sig want is empty, so the row cannot fail (got='n=6 op=Ops.RESHAPE nsrc=2 srcops=Ops.BUFFER|Ops.STACK')
    nn-rows-gate: FAIL -- 8 of 31 rows do not pass under exact comparison (23 match, 3 mismatch of which 3 differ only in spelling, 5 uncheckable, 0 dead)

**AFTER** (live, 2026-10-23T18:50:43Z on HEAD `e892a5aa`, exit **0**; and
RE-TAKEN at 18:51:14Z on HEAD `58140418`, exit **0**) -- `gate-final.out`:

    nn-rows-gate: measured_at=2026-10-23T18:50:43Z head=e892a5aa72aea88fb4d5dd96812ae5dd57d9a4b3
    nn-rows-gate: port=live copy of tinybendygrad (HEAD e892a5aa72ae)
    nn-rows-gate: rows_declared=31 (28 literal name(s), 1 computed name(s) x 3 invocation(s))
    nn-rows-gate: computed-name pattern=conv_p\d+_s\d+ declared_by=nn_row_conv expected=3
    nn-rows-gate: rows_printed=31
    nn-rows-gate: MATCH=31/31 MISMATCH=0/31 UNCHECKABLE=0/31 DEAD-ROW=0/31 SHRUNK=0/31 EXTRA=0/31 DUPLICATE=0/31
    nn-rows-gate: mismatching rows that differ only in SPELLING=0 of 0 (the rule: punctuation dropped, case folded, f32==float32)
    nn-rows-gate: rows_not_passing_exact_comparison=0 of 31
    nn-rows-gate: PASS -- 31 of 31 rows match their expectations, and the declared population is 31

**THE GATE'S OTHER NUMBERS DID NOT MOVE.** `rows_declared=31` (28 literal + 1
computed x 3), `rows_printed=31`, `DEAD-ROW=0/31`, `SHRUNK=0/31`, `EXTRA=0/31`,
`DUPLICATE=0/31` -- identical at HEAD, on the tree I inherited, and after my edits.
**EVERY ROW THAT MOVED MOVED BECAUSE ITS `want` WAS CLOSED, AND NOTHING ELSE
MOVED**: `MATCH` 18 -> 23 -> 31, `MISMATCH` 8 -> 3 -> 0, `UNCHECKABLE` 5 -> 5 -> 0,
and 18+8+5 = 23+3+5 = 31+0+0 = 31 in all three readings.

**THE DEDUP IS NOT MINE AND IS NOT IN MY DIFF.** `nn_reduce.keepd` is absent and
`nn_reduce.keep` reads `M.mo_reduce.keep` in **HEAD as well as the working tree**
(`git show HEAD:tinybendygrad/nn/layers.bend | grep nn_reduce` and
`grep nn_reduce tinybendygrad/nn/layers.bend` agree), and
`git diff HEAD -- tinybendygrad/nn/layers.bend | grep -c nn_reduce` is **0**.

---

## 6. THE CONTROLS

**THE INSTRUMENT IS THE GATE'S OWN.** `gates/nn-rows-gate.py` is imported BY PATH and
its `measure()` -- the SHIPPED decision, the same function the gate's own
`run_gate` prints -- is what decides each control; the mutation is the gate's own
`_set_want`, which edits a COPY and never the live tree. `gates/README.md` records
the reason in one line: *"a plant that drives a helper is not a plant of the
decision"*. **THE GATE'S OUTPUT DIRECTORY IS REDIRECTED** into this unit's own
directory, because `measure()` clears its output directory on every call
(`gates/nn-rows-gate.py:522-525`) and `gates/artifacts/` is a SHARED path.

    .venv/bin/python .agents/slop/nnrowsfix/control.py       [exit 0, full output in control.out]

**C1 -- A CLASS ONE ROW (a DTYPE row) PERTURBED:**

    control: C1 row=where_xdt
    control: C1 mutation=the `want` was spelled `f32` ...; it is now a wrong-but-non-empty `f16`
    control: C1 before: rc=0 MATCH=31 MISMATCH=0 UNCHECKABLE=0 DEAD-ROW=0 SHRUNK=0 EXTRA=0 DUPLICATE=0
    control: C1 after:  rc=1 MATCH=30 MISMATCH=1 UNCHECKABLE=0 DEAD-ROW=0 SHRUNK=0 EXTRA=0 DUPLICATE=0
    control: C1 rows_that_went_red=[('MISMATCH', 'where_xdt')]
    control: C1 rows_that_stopped_being_red=NONE
    control: C1 rows_still_green=30 of 31
    control: C1 MISMATCH where_xdt got='f32' want='f16'

**C2 -- A CLASS TWO ROW (a GRAPH row) PERTURBED:**

    control: C2 row=fold_xw_sig
    control: C2 mutation=the `want` was the whole signature with `srcops=Ops.RESHAPE|Ops.PERMUTE`;
              it is now a wrong-but-non-empty signature whose `srcops` list is truncated
    control: C2 before: rc=0 MATCH=31 MISMATCH=0 UNCHECKABLE=0 DEAD-ROW=0 SHRUNK=0 EXTRA=0 DUPLICATE=0
    control: C2 after:  rc=1 MATCH=30 MISMATCH=1 UNCHECKABLE=0 DEAD-ROW=0 SHRUNK=0 EXTRA=0 DUPLICATE=0
    control: C2 rows_that_went_red=[('MISMATCH', 'fold_xw_sig')]
    control: C2 rows_that_stopped_being_red=NONE
    control: C2 rows_still_green=30 of 31
    control: C2 MISMATCH fold_xw_sig got='n=18 op=Ops.MUL nsrc=2 srcops=Ops.RESHAPE|Ops.PERMUTE' want='n=18 op=Ops.MUL nsrc=2 srcops=Ops.RESHAPE'

**C3 -- THE CONTROL ON THE CONTROL (the VACUITY class, and it must be a DIFFERENT
class from C2's WRONGNESS):**

    control: C3 row=fold_xw_sig
    control: C3 mutation=the `want` is EMPTY again -- this is the VACUITY class
    control: C3 after:  rc=1 MATCH=30 MISMATCH=0 UNCHECKABLE=1 DEAD-ROW=0 SHRUNK=0 EXTRA=0 DUPLICATE=0
    control: C3 rows_that_went_red=[('UNCHECKABLE', 'fold_xw_sig')]
    control: C3 rows_still_green=30 of 31
    control: C3 UNCHECKABLE fold_xw_sig want is empty, so the row cannot fail (got='n=18 op=Ops.MUL nsrc=2 srcops=Ops.RESHAPE|Ops.PERMUTE')

**⇒ EACH CONTROL: EXACTLY ONE ROW WENT RED, IT IS THE ROW THE CONTROL NAMES, THE
CLASS THAT FIRED IS THE CLASS THE CONTROL CLAIMS, THE OTHER 30 ROWS STAYED GREEN,
AND THE GATE WENT 0 -> 1.**

**⇒ THE CONTROL ON THE CONTROL, STATED PLAINLY: C1 AND C2 FIRED `MISMATCH` -- THE
WRONGNESS CLASS -- ON A **WRONG BUT NON-EMPTY** `want`, AND C3 FIRED `UNCHECKABLE`
-- THE VACUITY CLASS -- ON AN EMPTY ONE. THE TWO ARE DIFFERENT CLASSES WITH
DIFFERENT NAMES, SO THE GATE IS CATCHING WRONGNESS AND NOT MERELY EMPTINESS.**
**The thirteen closed rows would be worthless if the gate only caught emptiness,
and the two classes are what say it does not.**

**⇒ AND THE `want`s ARE NOT COPIED FROM THE `got`s**: `mkrows.py` (§2.2) checks all
31 `want`s byte-equal against a witness that never reads the port, and §4 shows the
underlying whole graphs agree node for node.

---

## 7. WHAT I DID NOT CLOSE, AND WHY

**NOTHING IS LEFT OPEN.** All 31 rows match under exact comparison; the gate exits 0.
There is no row I refused and no row I guessed.

**THREE THINGS I DID NOT DO, AND WHY, STATED RATHER THAN LEFT IMPLIED:**

1. **I DID NOT REPLACE THE FOUR-TUPLE `want` WITH THE NODE LIST.** The five rows
   could carry the whole node list -- the port's `M.mo_valsig.of` prints it and the
   witness prints it, and §4 MEASURES them identical -- and that would be a strictly
   stronger check than four numbers. **I DID NOT, because the row's `got` is
   `MX.mxw_sig` and the gate compares EXACTLY: changing the `got` would change the
   ROW, not close it, and the brief is to close the thirteen rows, not to redesign
   them.** The node-list equality is MEASURED and reported in §4 instead, so the
   claim is stronger than the row enforces, and nothing is lost -- the row is a
   four-tuple subset of a verified full-graph equality.

2. **I DID NOT MAKE THE FIVE `want`s DISTINGUISHABLE FROM EACH OTHER, BECAUSE THEY
   ARE NOT DISTINGUISHABLE.** `dbg_dot_sig` and `fold_cc_sig` are the same
   computation on both sides (§3.4), so their node lists are the same too (§4). A
   signature cannot separate them and no spelling can. **WHAT THE TWO ROWS DO
   SEPARATELY IS EXERCISE DIFFERENT PORT CODE** -- the port's `nn_dot` against the
   port's `nn_sum` + `tn_mul` + `mo_cast_t` -- which is why both are kept.

3. **I DID NOT ADD A SPEC-IR RENDERER TO `spec.bend`.** §3.3 says exactly what
   would have to be added and why the third piece (the compiled node count) is out
   of that file's reach by its own design. `LAWS/spec.bend` is not this unit's file
   to edit.

---

## 8. THE DELIVERABLES, AND HOW TO RE-RUN EVERYTHING

| file | what it is |
|---|---|
| `tinybendygrad/nn/layers.bend` | THE EDIT: three DTYPE `want`s, five GRAPH `want`s, and the header comment that names the spelling sources, the witness, the fixture fact and the spec-IR answer |
| `.agents/slop/nnrowsfix/REPORT.md` | this file |
| `.agents/slop/nnrowsfix/rows.rows` | **THE 31 ROWS**, house F2 shape `name = [port value] py=[CPython witness]`, the shape `gates/lanecmp.py:read_rows` reads |
| `.agents/slop/nnrowsfix/nn-oracle.py` | THE WITNESS: CPython's answers for all 31 rows, in the port's spelling |
| `.agents/slop/nnrowsfix/nn-oracle.rows` | the witness's output |
| `.agents/slop/nnrowsfix/nn-oracle.rerun.rows` | the witness re-run, `diff`-identical to the above (rc=0) |
| `.agents/slop/nnrowsfix/sig-oracle.py`, `sig-oracle.rows` | the DEFAULT-DEVICE arm -- the measurement that shows why the witness uses `device="NPY"` |
| `.agents/slop/nnrowsfix/mkrows.py` | writes `rows.rows` AND checks all 31 `want`s against the witness |
| `.agents/slop/nnrowsfix/control.py` | the three controls |
| `.agents/slop/nnrowsfix/vsig.py` | the node-list cross-check (scratch driver in a COPY) |
| `.agents/slop/nnrowsfix/vsig.port.rows` | the port's own node lists |
| `.agents/slop/nnrowsfix/mkrows.out` | the witness cross-check's output (exit 0) |
| `.agents/slop/nnrowsfix/gate-head.out` | the BEFORE at HEAD (exit 1) |
| `.agents/slop/nnrowsfix/gate-before.out` | the BEFORE on the inherited tree (exit 1) |
| `.agents/slop/nnrowsfix/gate-final.out` | the AFTER (exit 0), taken on HEAD `e892a5aa` and re-taken on `58140418` |
| `.agents/slop/nnrowsfix/control.out` | the three controls (exit 0) |
| `.agents/slop/nnrowsfix/vsig.out` | the node-list comparison (exit 0) |

**EVERY COMMAND, IN ORDER:**

    .venv/bin/python gates/nn-rows-gate.py --baseline 95ab45bbacd232eea6c7618d010f79be6e38cbf9
    .venv/bin/python gates/nn-rows-gate.py                       # exit 0
    .venv/bin/python .agents/slop/nnrowsfix/mkrows.py             # exit 0
    .venv/bin/python .agents/slop/nnrowsfix/control.py            # exit 0
    .venv/bin/python .agents/slop/nnrowsfix/vsig.py               # exit 0
    .venv/bin/python .agents/slop/nnrowsfix/nn-oracle.py          # exit 0, diff-identical to nn-oracle.rows

.agents/slop/nnrowsfix/artifacts/ IS REGENERATED OUTPUT, NOT A DELIVERABLE:
`mkrows.py` and `control.py` redirect the gate's output directory there so a
control run cannot delete another unit's `gates/artifacts/` (which IS a shared
path and IS gitignored, `.gitignore:214`). It is deleted here and comes back on
the next run.

**NO `.txt` FILE WAS CREATED.** `.rows` for the row dumps, `.out`/`.err` for the
captured streams, `.md` for this prose, `.py` for the instruments.

**NO COMMIT WAS MADE, AS INSTRUCTED.** The working tree carries the edit
(`git status --porcelain=v2 -- tinybendygrad/nn/layers.bend` -> `1 .M N...`) and this
unit's directory is untracked (`.agents/slop/nnrowsfix/`).
