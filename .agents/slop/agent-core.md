# Agent core brief — porting a tinygrad .py file to Bend

Read this first, then your unit-specific sections. Everything here is measured in this
repo, not advice. Numbers are real and were obtained by porting.

## FIRST ACTION: STUB, BEFORE READING ANYTHING

Write the imports plus a `main` that prints nothing, confirm with
`./bin/bend <file> --check-only`, and only then read the Python.

Servers here restart without warning and kill agents silently. **Four agents have died
today.** Two died after creating a good stub and simply stopping, which is why a stub is
resumable and an absent file is nothing. If a stub already exists, GROW IT — do not
recreate it. Budget your time to get real defs on disk early and keep the file checking as
you go, rather than reading for a long time first.

**Never commit.** The coordinator verifies and commits.

## READS, IN THIS ORDER

1. `.agents/slop/agent-core.md` (this file)
2. `.agents/slop/brief-port.md`
3. `.agents/TODO.md` — the entries for your file, and any wall your file is named in
4. `tinybendygrad/runtime/ops_webgpu.bend` — COMMITTED AND GREEN, your structural template
5. `tinybendygrad/runtime/ops_metal.bend` — COMMITTED, the most complete device
6. `tinybendygrad/device.bend` — consume it, do not re-derive it
7. `.agents/slop/notes/bend2-constraints.md` — 190+ measured Bend rules. **The INDEX AT
   ITS TOP exists because rule NUMBERS REPEAT across units. Cite line POSITIONS, never
   numbers.**

Also: `grep -n "<your py module>" tinybendygrad/**/*.bend` to find committed code that
already cites your file. Those citations currently point at nothing, so they are your
scope — already scoped for you.

## THE SHAPE AND THE NAMES — owner ruling, both are hard rules

**1. ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH.** `tinygrad/foo/bar.py` gets
`tinybendygrad/foo/bar.bend`. No flattening, no merging, no prefixes standing in for a
directory. If you need something from `ops_cuda.py`, put it in `ops_cuda.bend`. This is not
negotiable and it is not a style preference — it is what makes the port navigable.

**2. DEF NAMES MATCH UPSTREAM EXACTLY, WHEREVER POSSIBLE.** The standard is explicit:
**anyone familiar with tinygrad should feel at home here and not have to map anything.** So
port `Schedule.kernelize` as `kernelize`, not `sch_kernelize`. Do not invent a prefix to
avoid a collision — a collision means two files are merged that should not be, and rule 1 is
the fix. Prefix only where the name is genuinely unavailable.

MEASURED, so you do not have to rediscover it: **2,419 of the 2,421 core tinygrad def and
class names are valid Bend identifiers verbatim.** Exactly **two** collide with Bend keywords
— **`match` and `where`** (confirmed by probing the compiler and iterating to a fixed point,
because a batch parse stops at the first error and hides the rest). If your name is not one of
those two, use it unchanged.

If you must rename for one of the two, or for a Bend type/arity constraint, then and only then
deviate — and **say so in your report, naming the upstream name and the one you used.**

THE PORT HAS DEVIATED FROM BOTH RULES AT SCALE, and you should know it so you do not copy the
habit: of24,583 port defs in files that declare an upstream source, only **724 (3%)** carry the
upstream name. Common prefixes include `t_` (1,813 uses), `g_`, `dc_`, `r_`, `tx_`, `ix_`,
`onx_`, `lt_`, `ra_`, `gt_`. **BUT DO NOT TRUST THAT 3% AS THE COST.** A later check showed
much of it is not renamed ports at all: `codegen/late.bend` has 502 defs, 0 matching upstream
and only 3 matching after the prefix is stripped, because most of them (`es`, `k`, `v`,
`tb_get`, `hit`, `go`, `cat`) are port-local record types and accessors with **no upstream
counterpart**. A real cost figure needs a per-def correspondence analysis, which has not been
done. **So: measure before you claim a number, and expect that a large share of port defs are
local constructs that the rule simply does not apply to.**

## THE SPLIT — the one rule that makes gates possible

A def EITHER builds the argument of ONE device call (pure; the gate checks it) OR records
that call in the trace (the gate checks ORDER and IDENTITY). **There is no third kind.**
That is what puts the `raise` in the trace, so a refusal appears as a truncated trace and
no step needs a guard of its own.

**The trace is also the seam, not an `@extern`.** Seven devices are `ALL PROOFS CHECK` with
zero `SOME PROOFS FAIL` (`ops_webgpu`, `ops_metal`, `ops_cpu_null`, `ops_cl`, `ops_amd`,
`ops_rdma`/`ops_npy`/`torch`, `ops_dsp`, `amdev`, `hcq2`) because a `dtype.bend` seam is a
`def ... -> IO(R)` with two `import "./x.c"` lines while a trace-following port declares NO
foreign effect. And the trace stays greppable: the symbol is a literal, not an opaque
body. Aim for that lane; it is the proven default. `dtype.bend`'s 14 permanently-red laws
are the outlier, not the rule.

## THE GATE — what a row must be

- **Four facts plus the answer as ONE string** for UOp graphs: node count, root op, root
  nsrc, and the **src op sequence**. A count is not a gate. Swapping a movement's two
  shape args leaves op, nsrc, the src sequence and the toposort ALL identical.
- **Field order and field NAMES, never field counts.** `ops_cl`'s unit found `Sig`'s field
  names INVERTED. A wrong field order is a silently wrong register write.
- **Refusals as truncated traces**, which is why the split above exists.
- **Negative cases** for every cache/eviction/recycle rule: the entry that must NOT be
  evicted, sitting one row from its opposite at the same size.

**Generate every `py=` expectation BY CALLING CPYTHON. Never type one.** This has bitten
five separate times and the last was the worst:

| file | hand-typed | outcome |
|---|---|---|
| `renderer/cstyle.bend` | 17 of 215 wrong | twelve real port bugs |
| `runtime/ops_nv.bend` | 33 of 219 constants wrong | 590 green rows, all eleven `CLASS_*` ids |
| `runtime/ops_rdma.bend` | `BNXT_VENDOR` 5356 vs 5348 | one hex digit-pair |
| `runtime/support/am/amdev.bend` | 7 of 80 wrong | caught BEFORE the file compiled |
| `runtime/ops_qcom.bend` | `~0x6996` as 24425 | one table entry |

And the sharpest one: `nv_query_litter` was wrong in the PORT **and** in the ORACLE — both
said 2, the truth was 3 — so the differ reported "0 disagreements" over an error made twice.
**Agreement between a port and a hand-typed oracle is not corroboration; it is one mistake
copied.**

Two related rules: a row whose expected value is a **def of the thing under test** is not a
test. And a row that **encodes a bug** is worse than no row: `device.bend` shipped
`sig=0 4 5` with a comment naming CPython's `0 4 8` "as a variation", and it survived
because it was internally consistent — every mutation moved nothing, since the row asserted
the port's own behaviour. That is now fixed (`7f170f64`).

## MUTATIONS

One entry per ported rule, measured, reported **with the rows it moved by name**. Report
mutations that move nothing as **blind spots with reasons** rather than closing them with
rows that encode the bug.

- **A `0` is a REQUEST FOR A FIXTURE, not a coverage claim.** `ops_nv` M30 moved nothing
  because all six of its fixtures were exact multiples of the rounding.
- Some zeros are **theorems** and must be reported as such: `ops_amd`'s
  `floor(floor(a/b)/c) == floor(a/(b*c))` identically, so two spellings are the same
  function and no fixture can separate them.
- Some are **genuinely unfixable**: `pc.find` answers `len` on a miss and an index below it
  on a hit, so `found < len` and `found != len` are the same predicate over every possible
  answer — a test that cannot fail.
- An **unexplained** zero is still a zero. Do not invent a theorem for it.
- Three mutations at `schedule/indexing.bend` found three functions that were written,
  commented, and **never called** — a def nothing calls is invisible to every other check.
- **Your harness must diff whole `name=value` lines, not row NAMES.** A name-comparing
  harness reported 0 for all 30 mutations in one unit and 0 for all 68 in another.

## TRAPS THAT HAVE COST REAL TIME

- `bend --check-only` **exits 1 even when the file is fine**, because `dtype.bend` has 14
  permanently unfilled laws (no `F16`/`I64`/`F64`/`U64` in Bend 2.0.34). **Never gate on the
  exit status.** Read the first line; expect `SOME PROOFS FAIL` naming only those 14. The
  file run itself exits 0. One agent lost a 10-minute retry loop to this.
- `U32.shl` is a **ONE-BIT** shift. `U32.shln(a, n: Nat)` is the n-bit one, so every shift
  **amount** is a `Nat` literal — a bit-packer whose field positions are runtime values is
  **unwritable**.
- `1 << 34` in a `U32` **saturates to 0**. Found twice (a SQTT pointer, a palloc high
  word), and the second one made the top of an allocator's free list zero-sized.
- A **record binder shadows a same-named parameter** and nothing says so. A leading `+` does
  not help; rename the parameter.
- A `case 1n+m:` arm **spends the scrutinee `n` too**, so the working fuel is a
  destructured `List.range` index list.
- `Bool.pick` **chooses** an arm; it does not **sequence** one. Using it as an `if` around a
  recursive call silently drops the rest of the list.
- `List.append(x, A, xs, ys)` is `xs ++ ys` — an append does not preserve the order its
  arguments were *written* in. This was a head/tail swap.
- `List.get` over `List<&2, Bool>` answers `None` for every index.
- No `value.field` sugar, and no auto-generated projection. One compile cycle per field read.
  This killed `cstyle.bend` (43 reads + 22 hand-written readers).
- `volatile` is reserved — use `volatile_`. `def X.of` must precede `def X`.
- `Nil{}` means what the code says it means. In one file `Nil{}` was read as "no axes" where
  `range(ndim)` meant "all axes", so a loss divided by a mask instead of by its sum.
- A match on a counter starting at `0n` takes the `case 0n` arm immediately — three walks
  had this and one returned the identity for every input.
- A `$TMPDIR` scratch copy cannot resolve a relative import. It produced 22 phantom blind
  spots in one unit.
- A scripted block move must assert `end > start`. One agent lost 841 lines to this.

## CONCURRENCY

Other agents edit other files. Two consequences:

1. **Capture a baseline immediately before any mutation run, and wait for the substrate to
   settle between steps.** `fold.bend` and `movement.bend` went transiently uncompilable
   three times from a concurrent agent, which silently corrupted one baseline and made a row
   appear to move on every mutation.
2. If you hit a cold-compile failure naming a def that is not in your file, you have found
   another agent mid-edit. **Say so in your report and use a local reader** rather than
   editing their file — but mark it as a workaround to be flipped back, not a design.

If a read-only file has a bug, **report it, do not fix it.** `ops_amd`'s agent reported my
own `device.bend` bug back to me and that was worth more than a local patch. And if your
port **contradicts** a wall a sibling port recorded, report it and gate BOTH answers rather
than reconciling — that is how two ports catch each other's bugs. `amdev`'s agent found that
`ops_amd.bend` recorded a `setup_ring` TODO against a file that has no `setup_ring` at all.

## BOOKKEEPING

- Oracles in `.agents/slop/`, **never in `$TMPDIR`**. One unit put its oracle there and it
  was gone before the commit, so its CPython comparison is unreproducible.
- Append general rules to `.agents/slop/notes/bend2-constraints.md` — **append-only, at the
  end, do NOT renumber**, and say where your numbering continues from. Numbers have collided
  three times already; cite positions.
- Report honestly. A measured "this architecture does not work and here is why" is worth
  more than a partial implementation. If most of a file is genuinely FFI, say so with Python
  lines rather than inventing rows. **Never fake a row.**

## A dtype rename is a SILENT semantic change wherever a pattern matches a dtype NAME

Measured today, and it is the most dangerous thing in this file.

`LAWS/spec.bend` was renamed mid-session (`"int"` -> `"i32"`, `"float8_e4m3"` -> `"fp8e4m3"`)
and that **silently broke two name-based `match` patterns in `uop/fold.bend`**:
`promo_mask`'s four fp8 masks and `bnd_lim`'s four fp8 maxima.

**A pattern that stops matching does not fail. It falls through** — and in both cases the
next arm was `bnd_flt`, so **all three fp8 maxima became `NInf`/`PInf` with no error
anywhere.** Green gate, 195 rows, zero `False`, wrong answers.

The underlying reason is not accidental: `S.Dt`'s first three fields **cannot distinguish
`fp8e4m3` from `fp8e4m3fnuz`** (both are priority 10), so the *name* is load-bearing.

**So, whenever a dtype name changes:**
- every `match`/`case` on a dtype NAME is a silent fall-through, not a compile error;
- a fall-through lands on whatever arm is next, which is usually a *different* answer rather
  than an obvious one;
- **grep for the old name in `case` position specifically** — a grep for the name anywhere
  will find comments and prose and drown the real hits;
- if a file has a table of dtype names, the table is the fix and the use sites follow.

Do not trust a green gate here. A gate that passed before the rename and passes after it has
told you nothing about whether the arms still match.
