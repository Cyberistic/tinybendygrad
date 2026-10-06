# guardfix/RESULTS.md — the routing table, the plants, and every number behind them

Measured 2026-10-04 on `Bend 2.0.34` / Apple clang 21.0.0 / node v26.8.1.
The tree is being edited concurrently, so **re-run `guardfix/disarm.sh` and
`substrate-check.sh` for your own numbers rather than trusting these.**

## 1. The defect, stated in one measurement

The old half 1 ran `bend --check-only` on **every** file. Over the six non-`.bend`
files in `tinybendygrad/`:

```
$ ./.agents/slop/substrate-check.sh $(find tinybendygrad -type f ! -name '*.bend' | sort) | grep COLD
COLD  tinybendygrad/runtime/dtype.c  (297 lines)  :: SOME PROOFS FAIL
COLD  tinybendygrad/runtime/sz.c     (97 lines)  :: SOME PROOFS FAIL
COLD  tinybendygrad/runtime/dtype.js  (193 lines)  :: SOME PROOFS FAIL
COLD  tinybendygrad/runtime/sz.js     (32 lines)  :: SOME PROOFS FAIL
COLD  tinybendygrad/runtime/webgpu_call.js  (502 lines) :: SOME PROOFS FAIL
COLD  tinybendygrad/runtime/webgpu_call.mjs (6963 lines): SOME PROOFS FAIL
```

**Six of six red, and not one of them is a Bend file.** `SOME PROOFS FAIL` is bend's
answer to "this is not a Bend program", which is a statement about the *question*,
not about the file. `w64mile/STATUS.md:44` already recorded the caveat; the caveat is
now removed rather than documented.

## 2. The routing table that replaced it

| file class | instrument | verdicts | what it actually asks |
|---|---|---|---|
| `*.bend` | `bend <f> --check-only` | `WARM` / `COLD` | does this Bend file stand alone? |
| `*.c` | `cc -fsyntax-only`, over bend's own generated C context | `WARM` / `COLD` | does this C fragment parse in the context bend gives it? |
| `*.js`, `*.mjs` | `node --check` | `WARM` / `COLD` | does node parse this file? |
| anything else | — | `NO INSTRUMENT` | **not judged** |
| a class whose instrument is absent, or a `.c` whose context will not build | — | `NO INSTRUMENT` | **not judged** |

`MISSING` and `EMPTY` remain separate pre-gates and still run **ahead** of the
router — `bend --check-only` reports `ALL PROOFS CHECK` for a 0-byte file, which is
why half 1 exists.

**`NO INSTRUMENT` is a fourth verdict because three are not enough.** `EMPTY`,
`WARM`, `COLD` and `NO INSTRUMENT` are four different claims, and collapsing any pair
loses the one that matters: a file nobody measured is not a file that passed.

### The counts, printed beside the verdicts

Every verdict carries its instrument in brackets, and one line tallies the routing —
because an instrument that hides its own routing is the defect this project has
catalogued twenty times, and half 2 already prints an `unseen=` count for that reason.

```
ROUTE   bend=137  cc=2  node=4  no-instrument=0  (of 143 file(s))
```

## 3. Why `.c` needed a context, and why the obvious one is a category error too

`cc -fsyntax-only tinybendygrad/runtime/dtype.c`, alone, on its own:

```
190 error lines. Every distinct one is "bend's runtime is not here":
  22 unknown type name 'Term'     32 use of undeclared identifier 'u32'
  18 unknown type name 'u32'      12 unknown type name 'Env'
  10 unknown type name 'IoWork'    6 use of undeclared identifier 'intptr_t'
   1 unknown type name 'int64_t'   1 call to undeclared function 'ctr_take'
   1 call to undeclared function 'io_tup' / 'f32_rewrap'
  ... plus 60 undeclared *locals* that are merely downstream of the first unknown type.
```

**So the brief's own suggested invocation, taken literally, is the same category
error asked of a different tool**: it reports RED a file that bend's backend builds
and *runs* (agent-core.md records `bend -o` + `cc` rc 0, 5,503 lines emitted).

A `.c` file here is **not a translation unit**. bend pastes it verbatim into the C it
generates (`comp.ts` `effect_srcs` → `c_ids` → `runtime_c`), so `Term`, `IoWork`,
`u32` and `NULL` are declared by the *generator*.

**And the generated unit cannot be halved.** Lines 1..2839 of the emit carry
**44 `#if` opens against 43 `#endif` closes**: `#if !DEVICE` at line 1556 is closed
by the generated `main`, past the foreign block. So there is no self-contained
preamble to `-include` —

```
$ cc -fsyntax-only <lines 1..2839 of the emit>
pre.c:1556:2: error: unterminated conditional directive
```

`guardfix/probe-c.bend` reaches one `dtype.bend` seam so `bend -o` emits that runtime;
the guard cuts the emit at the probe's foreign block, **counts** the `#if`/`#endif`
deficit and appends the closure, compiles the finished context **on its own**, and
only then judges fragments. If the context does not compile, the instrument produced
nothing and the verdict is `NO INSTRUMENT` — never a pass, never a cold.

### `CID(...)` is not C, and a first cut of this instrument was wrong because of it

`sz.c:51,53` evaluate `term_pak(CID(Nil), 0)`. `CID` is an **emit-time substitution**,
not a macro; no generated C defines a `CID` function. A first cut of the context
therefore reported:

```
COLD  tinybendygrad/runtime/sz.c  :: 7 x "call to undeclared function 'CID'"
```

**That red was my instrument's incompleteness, not a defect in `sz.c`** — a result
that contradicted the tool (bend builds and runs the file) is a suspect result. The
context now carries `#define CID(x) 0`: a neutral stub, correct here because the id's
*value* is irrelevant to whether a fragment parses, and a wrong id could only ever
hide a duplicate-registration error, which is not this instrument's question.

With it: `dtype.c` 0 errors, `sz.c` 0 errors, and a broken fragment still stops the
compile. **Note the corollary: `CID` is the one thing this instrument cannot judge.**
A fragment can register an effect under an id bend will never define and this check
stays green. That blind spot is named here rather than left for the next reader.

## 4. The plants, and the disarm

`.agents/slop/guardfix/disarm.sh`, all plants in `$TMPDIR`, tree never written to.
**6/6, exit 0.**

| # | plant | must be | was |
|---|---|---|---|
| 1 | a byte copy of `runtime/dtype.c` | **WARM** | WARM — *the plant-to-pass this job exists to close* |
| 2 | that same copy + one broken line | **COLD** | COLD, `broken.c:298: error: use of undeclared identifier 'this'` |
| 3 | `const x = ;` | **COLD** | COLD, node's own caret diagnostic |
| 4 | `const ok = 1; export default ok;` | **WARM** | WARM — node is not red on everything |
| 5 | a `.py` file | **NO INSTRUMENT** | NO INSTRUMENT, counted apart, exit unaffected |
| 6 | a 0-byte `.bend` | **EMPTY** | EMPTY — the size gate still precedes the router |

#1 and #2 are the pair that matters: the *same* file, one line apart, opposite
verdicts, and #1's `ROUTE` line reads `cc=1` so the green cannot be green **by
accident via bend**.

## 5. The whole tree, after the change

```
$ ./.agents/slop/substrate-check.sh $(find tinybendygrad -type f | sort)

WARM  tinybendygrad/runtime/dtype.c        (297 lines)  [cc -fsyntax-only + bend's C context]
WARM  tinybendygrad/runtime/sz.c           (97 lines)  [cc -fsyntax-only + bend's C context]
WARM  tinybendygrad/runtime/dtype.js       (193 lines) [node --check]
WARM  tinybendygrad/runtime/sz.js          (32 lines)  [node --check]
WARM  tinybendygrad/runtime/webgpu_call.js (502 lines) [node --check]
WARM  tinybendygrad/runtime/webgpu_call.mjs(6963 lines)[node --check]

ROUTE   bend=137  cc=2  node=4  no-instrument=0  (of 143 file(s))
TOTALS refs=36407 exact=36407 suffix=0 unresolved=0 unseen=46966 missing_module=0 dead_import=37
BAD 0
SUBSTRATE NOT CLEAN: 14 finding(s) across 143 file(s)
```

**COLD by instrument: `14 [bend --check-only]`, and `0` from `cc`, `0` from `node`.**
The 14 are exactly the 14 `.bend` files `agent-core.md:138-150` documents, and half 2
(`BAD 0`) is unchanged.

### …and then the tree moved under it, and the route earned its keep

A later run over the same command, minutes afterwards, gave **15** findings:

```
COLD  tinybendygrad/runtime/dtype.js  (193 lines)  [node --check]
      :: SyntaxError: Unexpected token ')'
      :: tinybendygrad/runtime/dtype.js:96
```

`dtype.js:96` is a real unbalanced paren, introduced by a **concurrent agent**
(`jj status` shows `M tinybendygrad/runtime/dtype.js`) while this unit was measuring:

```js
  const v = exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias));   // <- one ')' too many
```

**This is the routing paying for itself.** The old guard reported this file as
`COLD … :: SOME PROOFS FAIL` — a statement about bend not understanding a `.js`
file, identical to what it said for the file when it was perfectly valid, and
therefore carrying **zero** information. The new route says `SyntaxError: Unexpected
token ')'` and **names line 96**, which is the whole distance between a red that
annoyed people and a red that can be acted on. Not this unit's file: reported, not
edited.

**So re-run before you trust either figure.** The tree is under concurrent repair and
these counts are a snapshot of a moving target.

## 6. One thing the router does not settle, and it is not the router's to settle

`sz.c` registers its effects with bare `io_eff(CID(Sz.read_dir), ...)` while
`dtype.c:250-297` wraps **every** registration in `#ifdef CID(Dt.<seam>)`. Measured
consequence: when a build reaches `Sz.is_dir` but not `Sz.read_dir`,
`c_ids` emits `CID__________TINYBENDYGRAD_SZ_SZ_READ_DIR` and **no emit ever defines
it** —

```
$ cc -fsyntax-only <the emit of a probe reaching only Sz.is_dir>
sz.c:2892:10: error: use of undeclared identifier 'CID__________..._SZ_SZ_READ_DIR'
        ; did you mean 'WL_FID__________..._SZ_SZ_IS_DIR'?
```

Two further `cc` errors from that same emit name `CID_NIL` and `CID_CON`, which are
**not defined in any emit measured** (`#define CID_NIL` count: **0**), while bend's
own preamble spells the list constructors `CID_SNIL` / `CID_SCON`.

`runtime/sz.c` is not this unit's file and was **not edited**. Reported, per
agent-core.md: "If a read-only file has a bug, report it, do not fix it." Whoever owns
`sz.bend`/`sz.c` should decide whether `CID(Nil)`/`CID(Con)` should be the `CID_SNIL`/
`CID_SCON` the preamble actually defines, and whether `sz.c` should guard its
registrations the way `dtype.c` does.