# THE ENUM TABLES -- the negative-diff's finding F6.  MEASURED, 2026-11-17.

## (a) THE COUNTS

| thing | count | where |
|---|---|---|
| `Ops.name.of` arms | **76** | `tinybendygrad/uop/ops.bend` |
| `Ops.value` arms | **76** | same |
| `all_ops` entries | **76** | same |
| port `type Op is Data:` members | **76** | same |
| vendored `tinygrad/uop/__init__.py` `Ops` members | **76** | the pin |
| upstream **github master** `Ops` members (2026-11-17) | **76** | `raw.githubusercontent.com/tinygrad/tinygrad/master` |
| `GroupOp` set-membership functions in the port | **12** (+1 emitted) | `ops.bend` |
| `GroupOp` `True{}` arms in the port | **66** | |
| the two `Ops` tables' LOC | **167** | 79 + 79 + 9 |

## (b) DO THEY AGREE?

**The port's `Ops` member list == the vendored tree's, IN THE SAME ORDER: YES.**
MEASURED, `port == vendored` -> `True`, 0 members either way.

**The port's `Ops` member list == upstream GITHUB MASTER: NO, and the difference
is NOT the port's fault.**  Upstream master has **76** members too, but a
DIFFERENT 76:

- upstream-only: `ASM`, `EXTERN`
- vendored-only: `CUSTOM`, `CUSTOMI`

So the port is exactly at its pin, and the pin is behind upstream master.
**This is the tree's own lesson, not a port bug**: a driver pinned to an older
upstream is a fixture against nobody.

**The port's `GroupOp` sets == the vendored tree's: NO.  TWO REAL DIVERGENCES.**

| group | upstream (vendored) | port | difference |
|---|---|---|---|
| `Associative` | 6 | 5 | port **MISSING `XOR`** |
| `Defines` | 5 | 4 | port **MISSING `BINARY`** |
| `Unary` `Binary` `Ternary` `ALU` `Broadcastable` `Elementwise` `Irreducible` `Movement` `Commutative` `Idempotent` `Reduce` `Comparison` | | | **all EQUAL** |
| `Effect` | 4 | **absent** | upstream has it, 4 upstream call sites use it |

And `tinybendygrad/uop/spec.bend:2118` **still QUOTES the PRE-RE-VENDOR**
`Defines = {Ops.PARAM, Ops.BUFFER, Ops.ALLOC}` -- so the port's `defines` was
PARTIALLY updated (`REFPARAM` was added) and the PROSE was not.

**These two are load-bearing upstream.**  `GroupOp.Defines` is read at
`tinygrad/uop/spec.py:207` (`GroupOp.All-GroupOp.Defines`),
`tinygrad/schedule/indexing.py:24` (`ALWAYS_CONTIGUOUS`),
`tinygrad/codegen/decomp/dtype.py:146,168`; `GroupOp.Associative` at
`tinygrad/uop/symbolic.py:173`.

## (c) WHAT WAS BUILT, AND WHY

**A GENERATOR for the `GroupOp` sets only**, at
`.agents/slop/enum-tables/groupop-gen.py`, emitting a marked region of
`tinybendygrad/uop/ops.bend`.

**WHY NOT THE `Ops` TABLES.**  `Ops.name.of`, `Ops.value` and `all_ops` are
DERIVABLE from the port's own `type Op is Data:` block, and
`gates/opseven-gate.py`'s `ops_value_is_declaration_order()` **already holds
all three against it** -- in declaration order, with `Ops.value` numbering them
`1..N` and no gap.  A generator there would be a SECOND instrument for one
property, which is the tree's own warning against a hand list pretending to be
a population.

**WHY THE `GroupOp` SETS.**  They are **NOT** derivable from the enum: upstream
SPELLS them, as a class of sets over `Ops` members, and they were the half that
was **unguarded by anything** and that had **two real divergences**.

**THE ORDER IS UPSTREAM'S, NOT SORTED.**  MEASURED: with the members SORTED,
ten of the twelve functions came out byte-different from the port's, because
the port's arms follow upstream's spelling order.  With upstream's order, ten
of twelve are byte-identical and the only differences are the two missing
members.

**THE DIFF IS EXACTLY:**

- the region markers and a header that names the generator by path;
- `defines`: `+ case OpsBINARY{}`  (upstream's member, missing);
- `associative`: `+ case OpsXOR{}`  (upstream's member, missing);
- `effect`: a new 6-line function for upstream's `Effect`, which the port had
  not at all;
- the "derived set cannot drift" comment moved INTO the generated header.

`25 insertions(+), 4 deletions(-)` on a 8,504-line file.

## (d) THE MEASUREMENTS THAT ARE NOT ABOUT THIS TARGET

`gates/opseven-gate.py` is **RED** on this tree, and it was red BEFORE this
change:

    ops_value_holds: the port declares ['CUSTOM', 'CUSTOMI'] at port positions [59, 60]
    and upstream does NOT -- the claim is that the two declare the SAME Ops

because `_upstream_ops()` reads `git show upstream:tinygrad/uop/__init__.py`, and
the `upstream` REMOTE is a **shallow snapshot at `6295132eb`** whose enum has
**74** members (no `CUSTOM`/`CUSTOMI`).  Upstream's actual master today has
**76** (`ASM`/`EXTERN` instead).  **Not caused by, and not fixed by, this
change.**

## (e) WHAT IS STILL OPEN, AND NOT IN THIS TARGET'S SCOPE

`tinybendygrad/uop/spec.bend:2118` quotes the PRE-RE-VENDOR
`Defines = {Ops.PARAM, Ops.BUFFER, Ops.ALLOC}`.  It is now wrong twice over:
upstream's set has five members including `BINARY`.  `spec.bend` is another
unit's file and was not touched.

## (f) THE VERIFICATIONS, AND WHAT THEY SAID

Run in a CLEAN `git worktree` at `69fa871c6` with `bin/bend`, `.venv` and
`references/` symlinked in.

| check | verdict |
|---|---|
| `bin/bend tinybendygrad/uop/ops.bend --check-only` | **`ALL PROOFS CHECK`** (rc=0) |
| generator re-run | **`REGION IS CURRENT: 144 lines, byte-identical`** (idempotent) |
| `checks/differ.py run` | **`graphs=38 graphs-answered=38 graphs-agree=38 graphs-disagree=0 byte-identical=38 graphs-refused=0`** |
| substrate digests | **`substrate-start == substrate-end == live == repro-substrate == 8158ceb3e012e470458fee808deaee15610c543d88eceac1cb06e9806983217f`**, `substrate-head=69fa871c6` |
| `checks/differ.py repro` | **`REPRO: 339 of 339 files identical across two clean runs`** |
| `differ.unhealthy()` / `artefacts_ok()` / `repro_bad()` | **`[]` / `[]` / `[]`** |
| `gates/corpuswitness-gate.py` | **`PASS -- the claim is ESTABLISHED`**, all seven readings OK, `claim=REPRODUCIBLE` |
| `gates/opseven-gate.py` `spec_program_holds` | **OK**, 12 of 12 agree -- IDENTICAL before and after |
| `gates/opseven-gate.py` `ops_value_holds` | **FAIL, PRE-EXISTING** (see (d)) |
| `git fsck --no-progress` | 790 dangling objects, and **2 malformed trees** -- `d83cf685`, `3a60f33f`, the SAME two AGENTS.md names as PRE-EXISTING ORPHANS; neither is an ancestor of HEAD |

The BASELINE, at `c7f0f1cc6` in a clean worktree, was the same 38/38/38/0/38/0
with `substrate == 17f7ec725c1fbe173c8df8f252087087d9290112edf283e2e85bda24ddf8bff3`
and the same `339 of 339` repro.  **The digest moved because a `.bend` file
moved, and the verdict did not.**

## (g) THE OPS TABLES WERE NOT TOUCHED, AND THAT IS MEASURED

`Ops.name.of`'s 76 arms, `Ops.value`'s 76 arms and `all_ops`'s 76 entries are
**byte-identical** before and after the change.  MEASURED by re-parsing both
revisions of the file.

