# RESTORE — three graphs, and what restoring them does and does not say

`.agents/slop/graphrestore/`, 2026-10-05. Not committed. Owned: `graphcmp.py`, this directory.

## 0. THE TWO INSTRUMENTS, SIDE BY SIDE, AND WHICH SIDE EACH ONE MEASURES

**THE FIRST THING ON DISK.** `union.py` prints the 22-graph union and the 25-graph union in one
table, one row per op, with the mints; `portside.py` prints the same graphs for the port. Both pin
`--dev`, and both refuse to be read without saying which side they measured.

    DEV=CPU .venv/bin/python .agents/slop/graphrestore/union.py [--sources]
    DEV=CPU .venv/bin/python .agents/slop/graphrestore/portside.py [--tries 1]

| | instrument | side it builds | 22 graphs | 25 graphs |
|---|---|---|---|---|
| before | `checks/corpus-figure.py:99` `gc.build(gc.emit_py(g, None), "py")` | **CPYTHON only** | **53 of 77** | — |
| after | same, `GRAPHS` restored | **CPYTHON only** | — | **61 of 77** |
| — | `graphrestore/portside.py` `gc.emit_bend(dev, g)` | **THE PORT** | **0 of 77** | **0 of 77** |

> **RESTORING GRAPHS RESTORES CPYTHON-SIDE REACHABILITY. THAT IS A REAL CLAIM AND IT IS NOT PORT
> COVERAGE.** `61` and `53` are the same kind of number and both are *not* about the port. The
> port's number is **0 of 77** and it has been 0 for the whole recorded run.

**`61 - 53 = 8` REPRODUCES EXACTLY, ON `DEV=CPU`** — the device `graphcmp.py` pins for the differ.
GAINED, all eight: `ALLREDUCE CDIV CMPEQ CMOD COPY FDIV NEG SUB`.

**AND THE SAME SCRIPT ON THIS HOST'S OWN DEVICE SAYS 60, NOT 61.** `g_late`'s fourth op is
`FDIV`, and `FDIV` is minted only if the *device's own renderer table* lists it. MEASURED:

| `DEV` | renderer | `code_for_op` keys | `NEG SUB CMPEQ` | `FDIV` | `g_late` census |
|---|---|---|---|---|---|
| `CPU` | `ClangRenderer` | 18 | yes | **yes** | 12 nodes, `FDIV=1` |
| `METAL` (this host's default) | `MetalRenderer` | 21 | yes | **no** | 13 nodes, `MUL=1 RECIPROCAL=1` |
| `NULL` | `NullRenderer` | 23 | yes | **no** | 13 nodes, `MUL=1 RECIPROCAL=1` |

**`checks/corpus-figure.py` NEVER PINS `DEV`.** It reads whatever the host resolves to, so the
figure it prints is **a function of the host device** and a restore that is worth 8 ops on the
differ's device is worth 7 on this one. This is a defect in the instrument; I am not allowed to
edit it and it is REPORTED, not fixed. See §6.

## 1. THE 22-vs-16, EXPLAINED, WITH `file:line`

**THE DIFFER DOES NOT ITERATE THE CORPUS. IT ITERATES A HAND-WRITTEN TABLE OF SIXTEEN NAMES.**

- `checks/differ.py:89-103` — `WANT` is a **literal dict of 16 graph names → expected verdict**.
- `checks/differ.py:250` — `for g in WANT:` → `run(f"D1-graph-{g}.txt", "diff", "--graph", g)`.
  **`graphcmp.GRAPHS` IS NEVER READ BY THE RUN LOOP.**
- `checks/differ.py:351` — `graphs={len(list(D.glob('D1-graph-*.txt')))}`, so `D0-run-summary.txt`'s
  `graphs=16` is a count of **artifacts `WANT` produced**, not of the corpus.
- `.agents/slop/graphcmp.py:2752` — `--graph choices=sorted(GRAPHS)`, so `diff --graph flip` has
  been *available* on the command line the whole time and simply was never in `WANT`.

MEASURED:

    graphcmp.GRAPHS        : 25
    checks/differ.py WANT  : 16
    in GRAPHS, NOT in WANT : allred alu bit bw cdiv flip late move where
    in WANT, NOT in GRAPHS : (none)
    D1-graph-*.txt on disk : 16

`git log -S'"flip": "AGREE"' -- checks/differ.py` returns **nothing**: `flip` was never in `WANT`.
So the six (`bw alu bit where move flip`) and now the nine were **never in any run**, not dropped
from one. `b104786b3`'s own message names the five (`alu bit where move flip`) and calls `bw` an
earlier unit's. **`RUN HEALTH: 0 of 16` HAS ALWAYS BEEN A COUNT OF A SIXTEEN-NAME TABLE.**

## 2. WHICH OF THE 25 BUILD ON THE PORT SIDE: NONE OF THEM

`.agents/slop/graphrestore/portside.py`, one `bend` at a time, `--tries 1`:

    PORT-SIDE UNION over 25 graphs : 0 of 77
    CPYTHON-SIDE UNION over the same: 61 of 77

**ALL 25 EMIT ZERO BEND ROWS, AND THE CAUSE IS ONE COMPILE ERROR:**

    .venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- \
        ./bin/bend .agents/slop/graphcmp.bend --check-only
    SOME PROOFS FAIL
    - expected : cases for ../../tinybendygrad/uop/ops.AOpLit
    - observed : \{\}
    Location: argstr
    373 | def argstr(a: O.Arg, depth: U32) -> String:
    374>|   match a:
    375>|     case O.ANone{}: "N"
    [bounded] WITHIN-LIMITS  rc=1  peak-RSS=455 MB (ceiling 2048)  1s
    bend: 2.0.34

**`graphcmp.bend:373-401` `argstr` has 19 of the 20 `Arg` arms. The missing one is `AOpLit`.**
`tinybendygrad/uop/ops.bend:1063-1088` declares `type Arg` with 20 constructors and
`tinybendygrad/uop/ops.bend:1079` is `AOpLit{op: Op}`, added — per its own comment at `:1074-1078` —
**solely so the port can spell `UOp(Ops.PYLITERAL, arg=<a bare Ops>)` at all** (`upat.py:26` passes
`self.op[0]`). So **the one `Arg` constructor that makes `PYLITERAL` representable is the one the
differ's own printer cannot print**, and Bend's exhaustiveness check refuses the file rather than
letting it print a lie.

**SO: `not-comparable=16` IS NOT A SEMANTIC DISAGREEMENT. THE PORT EMITTED NOTHING TO DISAGREE
WITH.** `runs/graphcmp/D/D1-graph-matmul.txt` is the 5 bytes `rc=1`, and its `.err` is the same
compile error 5 times. Every `D1-graph-*.txt` is `rc=1` with **no `# VERDICT:` line at all**, which
is why `D0-run-summary.txt` reads `graphs-agree=0` and why `D1-verdicts.txt` reads
`VERDICT= EXPECTED=AGREE` — an empty verdict, sixteen times.

**`graphcmp.bend` IS NOT IN MY OWNERSHIP GRANT, SO I DID NOT FIX IT.**

## 3. THE 8 NEWLY-REACHED OPS, EACH WITH THE `tinygrad/` SITE THAT ACTUALLY MINTS IT

Traced, not grepped: `UOp.alu` and `UOp.__init__` were wrapped and each hit's **live call stack**
was recorded. A site in a grep is a site that CAN mint; only a stack is a site that DID.

| op | MINT — traced, in the restored graph | eager spelling that does NOT reach it |
|---|---|---|
| `ALLREDUCE` | `tinygrad/uop/ops.py:679` `UOp.allreduce` → `UOp(Ops.ALLREDUCE, src=(self,), arg=(op, device))` | none — needs a tuple device |
| `COPY` | `tinygrad/uop/ops.py:765` `UOp.copy_to_device` → `UOp(Ops.COPY, src=(inp, *UOp.device_range_src(device)), arg=device)` | none — no eager graph crosses a device |
| `CDIV` | `tinygrad/mixin/elementwise.py:251` `.div(…, rounding_mode="trunc")` → `a.alu(Ops.CDIV, b)` | int dtype only; float spells it `MUL`+`RECIPROCAL` |
| `CMOD` | `tinygrad/mixin/elementwise.py:226` `.fmod` → `a.alu(Ops.CMOD, b)` | int dtype only |
| `NEG` | `tinygrad/codegen/decomp/op.py:105` `x.alu(Ops.NEG)` (gated `:104 if Ops.NEG in ops`) | `a.neg()` is `MUL(a, CONST -1)` |
| `SUB` | `tinygrad/codegen/decomp/op.py:106` `x.alu(Ops.SUB, y)` | `a - b` is `ADD(a, MUL(b, CONST -1))` |
| `CMPEQ` | `tinygrad/codegen/decomp/op.py:117` `x.alu(Ops.CMPEQ, y)` (gated `:117 if Ops.CMPEQ in ops`) | `a.eq(b)` is `CMPNE(a,b).logical_not()` |
| `FDIV` | `tinygrad/codegen/decomp/op.py:124`/`:125` (gated `:123 if Ops.FDIV in ops`) | `a/b` is `MUL(a, reciprocal(b))` |

Every mint goes through `tinygrad/uop/ops.py:627` `UOp.alu`, called from
`tinygrad/uop/ops.py:1592` (`entry[1](uop, ctx)`, the pattern-matcher fold) for the four `late` ops
and from `tinygrad/tensor.py:116` `Tensor.alu` / `:106` `_apply_uop` for `CDIV`/`CMOD`.

**SITES THAT NAME AN OP AND CONSTRUCT NOTHING, listed so nobody cites them as mints:**
`ops.py:150` (`Ops.MSTACK | Ops.MSELECT | Ops.ALLREDUCE | …`, a guard arm), `ops.py:387`,
`ops.py:717`, `ops.py:896`, `ops.py:1110` (`if self.op is Ops.SUB`), `ops.py:1117`, `ops.py:1122`,
`ops.py:1430-1431` (`Ops.CMOD: cmod, Ops.CDIV: cdiv, … operator.eq}` — the *implementation* table),
`codegen/decomp/op.py:104`, `:123`, and every `tinygrad/renderer/**` site: a renderer
**consumes** an op, it never mints one. `tinygrad/uop/render.py:107-108` is the trap —
`Ops.CDIV` sits **inside an f-string** in the pretty-printer's template, so a naive
`grep 'alu(Ops.CDIV'` reads a printed template as the call `a.alu(Ops.CDV…)`. `union.py --sources`
blanks string literals before matching for exactly this reason.

## 4. FOUR OF THE 24 BLOCKED BY THE DIFFER, NOT BY THE PORT — REPORTED, NOT FIXED

**`CUSTOM` `CUSTOMI` `PYLITERAL` — one arm, three ops.** All three are minted only inside the
pattern compiler's acceptance test, which `tinygrad/uop/upat.py:66` makes `AND`-rooted by
construction:

- `tinygrad/uop/upat.py:25` `UOp(Ops.CUSTOM, src=(base, UOp(Ops.PYLITERAL, arg=…)), arg=("…", dtypes.void))`
- `tinygrad/uop/upat.py:66` `return UOp(Ops.AND, src=tuple(and_clause)) if and_clause else UOp(Ops.CUSTOMI, arg=("True", dtypes.void))`

`AND` **is** in `GroupOp.Broadcastable` (MEASURED: `Ops.AND in GroupOp.Broadcastable` → `True`),
its clauses are shapeless, and so **`tinygrad/uop/ops.py:444`** raises

    AssertionError: None input shape not supported for Ops.AND

while **`.agents/slop/graphcmp.py:749`** — `except RuntimeError:` in `cshape` — cannot catch it.
MEASURED: `issubclass(AssertionError, RuntimeError)` is `False`. Reproduced for a shapeless
`SINK`, `BARRIER`, `ENDIF`, `PYLITERAL`, `PROGRAM` and `SOURCE` clause. **A one-arm widening at
`graphcmp.py:749` retires all three.** NOT MINE.

**`MULACC` — device-gated, and it is a DIFFERENT defect wearing the same coat.**
`tinygrad/codegen/decomp/op.py:118` `if Ops.MULACC in ops:` is its only rule, where `ops` is the
backend's `code_for_op`. MEASURED: **`ClangRenderer`, `MetalRenderer` and `NullRenderer` all lack
it** — there is no `tinygrad/codegen/renderer/ptx.py` in this tree — so `MULACC` cannot be reached
on any device here. It needs a **backend**, not a different graph and not a widened `except`.
*(`DENOMINATOR.md:102-105` cites `renderer/ptx.py:33`; that path does not exist — the search for
MULACC across `tinygrad/codegen/` returns only `op.py:61,118,119,121`.)*

## 5. `REWRITE_ERROR` — CONFIRMED NOT PORTABLE, AND THE PORT HAS A RECOGNISER WITH NO PRODUCER

Its entire payload is a Python traceback **string**: `traceback.format_exc()` at
`tinygrad/viz/serve.py:197` and an `err_str` at `tinygrad/uop/ops.py:1722`. MEASURED by census:
**2 `UOp(Ops.REWRITE_ERROR` construction sites, both inside `except`/viz-tracing paths, against 7
lines that only reference it** — `viz/serve.py:57` (a colour table), `viz/serve.py:656,659,664`
(sink dispatch), `uop/spec.py:236` (`isinstance(x.arg, str)`), `uop/ops.py:127` and `:334`
(no-shape lists). *(The brief's "0 construction sites vs 15 lines" does not reproduce on this
tree; there are 2 and 7, and neither number changes the verdict.)* The port has the recogniser and
no producer, **because a Bend match that does not apply returns `Nothing`** and there is no
upstream path that mints one outside the debugger: **the only way to build a `REWRITE_ERROR` is to
cause a failure and catch it**, which is not a graph a corpus can carry.

`PYLITERAL` is the contrast case and it **IS** portable — its upstream payload is
`frozenset(self.op)` / `self.arg` (`upat.py:25`) and the port gives it a finite `Lit` type
(`tinybendygrad/uop/ops.bend:1079` `AOpLit{op: Op}`); `PYLITERAL` is blocked only by the differ's
missing `argstr` arm (§2), not by the port.

## 6. SHOULD THE FIGURE BE RESTATED? **YES — IN KIND BEFORE IN VALUE**

1. **Restate `CORPUS.md`'s figure block to `61 of 77` over 25 graphs.** `53/22` is now wrong
   because `graphcmp.py:1388` has 25 entries; the block at `CORPUS.md:7-9` is the authority and an
   authority that disagrees with its own instrument is worse than no authority.
2. **Restate it IN KIND: it must carry `DEV=CPU`.** A figure whose value changes with an
   environment variable nobody set is not a figure. `checks/corpus-figure.py` reads `DEV` from the
   environment and this host resolves to `METAL`, so on this host the restore looks like **nothing
   happened** (`53 → 60`, and `60` vs `61` with no explanation anywhere). **INSTRUMENT FIX, NEEDED
   AND NOT MINE:** pin `DEV=CPU` before `load_graphcmp()`.
3. **The block's prose is now STALE IN ITS OWN BODY, and the file is mine to fix but the text is not
   mine to invent.** `CORPUS.md:14` still reads `` `22 graphs [SUPERSEDED: was 25] ` ``. **The
   25 was never superseded — it was LOST, and this is the first time the two have been told apart.**
4. **`checks/corpus-figure.py:122` NOW PRINTS A LIE IN ITS OWN OUTPUT**: the literal text
   `...OVER THE 22 GRAPH DEFINITIONS` is hardcoded while the same script prints
   `graphs declared : 25`. Reported, not edited.
5. **DO NOT restate it as port coverage, in any number.** The port figure is `0 of 77` and its
   cause is named above. `61 of 77` on the port's account is the single most likely way this
   becomes the ninth form of this figure.
6. **`differ.py:89-103` `WANT` IS THE SAME CLASS OF DEFECT AND IT IS THE WORSE ONE**, because it is
   what makes the run's own denominator lie: a graph absent from `WANT` is invisible, and the run
   reports `graphs=16` as though 16 were the corpus. Either `WANT` must be derived from
   `graphcmp.GRAPHS` with a per-graph expected verdict stored beside the generator, or the run must
   print `graphs-declared=25 graphs-compared=16 graphs-never-compared=9` and refuse on the gap.
7. **`checks/no-txt.py` IS UNAFFECTED.** `oracles/rows-{allred,cdiv,late}-{py,bend}.txt` already
   exist and are read BY ARTIFACT NAME under the sha256 pin at `checks/differ.py:58`, so the three
   restored graphs have their recorded py **and** bend oracles already on disk. Nothing to rename.

## 7. WHAT IS ON DISK, AND WHAT IS NOT RESTORED

**RESTORED (uncommitted, additive, no existing line changed):** `.agents/slop/graphcmp.py` —
`def g_allred`, `def g_cdiv`, `def g_late` and three `GRAPHS` entries.

**NOT RESTORED, AND NOT MINE:**

- `.agents/slop/graphcmp.bend` — the recorded `db95da7bf` version carries `g_allred`/`g_cdiv`/
  `g_late` fixtures and their three `Bool.pick(…, String.eq(name, …), …)` dispatch arms
  (`graphcmp.bend:1425-1427` in that commit). The working tree has none. **Restoring them is
  inert until §2 is fixed**, because the file does not compile.
- `checks/differ.py:89-103` `WANT` — needs the three names (and the six older ones) with expected
  verdicts. **Until it does, `not-comparable` grows from 16 to 19 and the run's denominator gets
  smaller, not larger.**
- `checks/corpus-figure.py` — two defects reported above (§6.2 pin `DEV`, §6.4 stale literal).

**MEASURED AFTER THE RESTORE, WITH `checks/corpus-figure.py` UNMODIFIED:**

    graphs declared   : 25
    graphs built      : 25
    graphs FAILED     : 0
    denominator len(Ops) : 77
    CPYTHON-SIDE UNION   : 61 of 77
    RUN HEALTH        : **FAILED** -- 0 of 16 graphs agree, 16 not comparable.
    per-graph SUM        : 181   <- NOT the figure
    NOT reached (16): REWRITE_ERROR PROGRAM SOURCE GETADDR WMMA THREEFRY MULACC CUSTOM
                      CUSTOMI INS STAGE MSELECT MSTACK CUSTOM_FUNCTION UNSHARD PYLITERAL
    EXIT=1

**The instrument's refusal is PRESERVED — it still exits 1, on the same run health, for the same
reason.**