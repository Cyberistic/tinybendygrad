# graphcmp — a canonical graph normal form both sides emit, and a differ over it

**Third pass, 2026-10-04 (the program graphs).** `graphcmp-LIMITS.md` carries the state;
this file carries the design. What changed: the corpus grew from thirteen graphs / 104
nodes / 23 of 77 ops to **sixteen graphs / 189 nodes / 34 of 77 ops**, and the three new
graphs are the first whose **PY side is a call into tinygrad's own scheduler and codegen**
rather than a hand-built expression. They are `lin`
(`full_rewrite_to_sink(schedule_linear(matmul))`, 46 nodes), `loop` (`hcq_fence(...)`, 25
nodes — tinygrad's OWN HCQ2 poll-loop kernel) and `gate` (a gated STORE through the real
`pm_linearize_cleanups`, 14 nodes). They reach **`ENDIF`, `BACKEDGE`, `LOAD` and `STORE`**,
which thirteen hand-built graphs could not, because those four are properties of a SCHEDULE
and not of an expression.

The BEND side of all three is still hand-built node for node, and the reason is a port gap
rather than a choice: `tinybendygrad/schedule/__init__.bend` DEFERRs
`tinygrad/schedule/__init__.py:82-301` ("every rule is a `graph_rewrite` with a PYTHON ctx
DICT"), so **the port cannot build a schedule at all**.

Six more defects in this harness's own normal form were found by the widening and are
numbered 17-21 in `graphcmp-LIMITS.md` §6. Two of them would have kept lying: a SINK with
`arg=None` **crashed** the emitter (17), and the `tag` column **could not be read at all**,
because every one of the thirteen earlier graphs had `tag is None` on every node (18). The
twenty-first finding is about the CHECK rather than the differ: the two-run byte-identity
claim was backed by `find | md5 -q`, which on macOS takes exactly ONE file and prints
nothing given several — and when the check was written properly it found a real
nondeterminism on its first run.

`sh .agents/slop/graphcmp-run.sh` regenerates every file in `runs/graphcmp/D/`.
`sh .agents/slop/graphcmp-repro.sh` measures reproducibility: **154 of 154 files
byte-identical across two clean runs.**

**THREE MORE FINDINGS FROM THE CHECKS RATHER THAN THE DIFFER, and the chain between them is
the point.** A stability pair can report `BYTE-IDENTICAL` when *both* members are the same
one-line 0-row failure — two identical failures compare equal — so a one-line side is now
labelled FAILED and re-run, and the run summary counts the NEGATIVES beside the positive.
Making a differing pair visible then found the next one: `sym: 2 runs DIFFER`, `32d31 <
rc=0`, i.e. the second file was thirty-one lines because `run()` appended `rc=$?` to the
file the child had just written and a kill in that window left no tail. Output is now
written to a dot-named temp and `mv`d into place, which is atomic. Neither finding was
reachable from the other.

**A LIMIT WAS CLOSED WHILE THIS ROUND RAN, AND THE THREE PINNED NUMBERS THAT CLAIMED IT
MOVED WITH IT.** `sym` was the corpus's one DISAGREE-on-purpose graph because the port could
not mint a symbolic dim at all (`uop/fold.bend`'s `ssimplify` wall). MEASURED late on
2026-10-04: the wall is CLOSED — `fold.bend`'s `sym_dim.pa` (`fold.bend:1296`, the `AParam`
arm of `sym_dim.of`) landed from the `fold` unit — and `sym` reads `?=0` and `VERDICT: AGREE`
at 12 of 12 with `SYMBOLIC DIMS py=2/12 bend=2/12`. `selfcheck`'s `?=6` row,
`graphcmp-run.sh`'s `sym:DISAGREE` and `graphcmp-repro.sh`'s `graphs-agree=13` all had to
move in the same direction. **The third one is the instructive one: the repro health gate
reported "not healthy" for a run that was entirely CORRECT and sat retrying it**, which is
the cost of pinning a gate to a verdict count. Nothing in this unit caused the fix and
nothing in this unit could have made it; what this unit contributed is the fixture and the
denominator that made the closure visible and checkable.

Measured 2026-10-03. Harness: `.agents/slop/graphcmp.py` (the differ and the CPython
emitter) and `.agents/slop/graphcmp.bend` (the port-side emitter). Artifacts:
`runs/graphcmp/`. No port file was edited. No live tree was patched.

**Second pass, 2026-10-03 (the five residuals).** Section 5 is rewritten; the four
residual claims that survived measurement are listed there with their owners. Three things
the first version of this report asserted turned out to be **wrong on measurement** and are
corrected in place rather than quietly: the realized-BUFFER row was **emitting a device
object's `repr`** and comparing a `slot` that does not exist; `KernelInfo.applied_opts`
made the emitter **crash**, and there is no `Option` class in this tree; and there are
**two** bend-only `AxisType` members, not three — `PLACEHOLDER` exists upstream. Section 5.6
is a sixth finding that was not on the list: the shape column's third value was a letter
collision, found only because a fixture with a shape-less node now exists. The device
resolver landed from the other unit during this pass, so `diff` reads `VERDICT: AGREE` with
no `--dev-map` and nothing here binds a device at a prompt.

**`tinybendygrad/uop/render.bend` was NOT touched.** `pretty_print` (`render.bend:1903`'s
`PORTED IN PART`) was the suggested anchor and is still unportable for this purpose — see
"Why not `pretty_print`" below. `uop/ops.bend` (63 importers) untouched. `helpers.bend`,
`LAWS/**`, `PROOF*.bend`, `codegen/**`, `runtime/**`, `renderer/**` (beyond
`graphcmp.bend`, which is new), `rebase-gate.py` and `naming-gate.py` all untouched.

---

## 1. Why a normal form and not a text diff

A pretty diff over two graph printers compares the **printers**, not the graphs, and the
printers are not stable. Measured in `.agents/slop/pin-tree-oracle-report.md`: the *same*
logical node renders four different ways across upstream commits —

| node | at the pin | at head |
|---|---|---|
| `CallInfo(...)` | `(None, 'f', False, False, dtype=dtypes.int)` | `(None, 'f', False, False)` |
| `Ops.CUSTOM_FUNCTION` arg | `'myfn'` | `CustomFunction(name='myfn', dtype=dtypes.void)` |
| a RANGE | `UOp.range(4, AxisType.WEAK, 0, 1)` | `UOp(Ops.RANGE, (c1,), (AxisType.WEAK, 0, 1))` |
| a CONST dtype | `dtypes.float` / `dtypes.int` | `dtypes.f32` / `dtypes.i32` |

So a raw diff answers "which tinygrad commit is this?" — twice — and never "does the port
build the same graph?". The deliverable is a **normal form** both sides emit, and the diff is
over that.

## 2. The normal form

One record per node, eight fields, in this order:

```
id  op  dtype  shape  depth  tag  arg  src
```

On the wire each field is a **self-delimiting chunk** `<bytecount>:<bytes>`, eight chunks per
line. The reader *walks the counts*, so whitespace is never structural — that is the answer to
`^(\S+) = `, which the pin/HEAD study measured dropping 216 of 228 rows because row names
contain spaces (`PTX tensor_cores sm_75`), and to the `name=value` vs `name = [value]` lane
mismatch that reports a clean zero.

**The atom table.** One letter per value kind, no letter reused (`selfcheck` asserts it): `N`
none · `i<n>` U32 · `l<hi>:<lo>` I64 · `f<v>` float · `b0`/`b1` bool · `s<str>` string · `y<len>`
bytes · `D<name>` dtype · `O<name>` op · `X<name>` axis type · `S<name>` addr space · `v` invalid
· `t<n>` interned device index · `n(...)` tuple/list · `P(...)` `ParamArg` · `rg(...)` RANGE arg
· `rd(...)` REDUCE arg · `wm(...)` WMMA arg · `in(...)` INS arg · `al(...)` ALLREDUCE arg ·
`cF(...)` CustomFunction · `cI(...)` CallInfo · `kI(...)` KernelInfo · `pI(...)` ProgramInfo.

### Each rule and its citation

| # | rule | justification, measured |
|---|---|---|
| **R1** | `id` is the side's own arena index, **reporting only, never identity** | CPython's ucache has no index; the port's arena spends index 0 on its bottom node (`ops.bend:1162-1168`). Both sides count from 1 so the two files are byte-comparable — but the differ pairs structurally, so a node-numbering change moves nothing. |
| **R2** | `op` = `Ops.name`, the **bare** member name (`ADD`, not `Ops.ADD`) | `Ops.__str__` is `Enum.__str__`, so CPython has two spellings per member. `ops.bend:284-288` records that getting this wrong was a real port bug. The bare spelling also serves `AxisType` (`ops.bend:662`), so one spelling covers both enums. |
| **R3** | `dtype` = `DType.name` — `f32`, never `dtypes.f32`, never `float` | `DType.__repr__` is `f"dtypes.{self.name}"` (`tinygrad/dtype.py:67`); `name` is the bare member. The decorator is dropped because the decorator is the thing that moved between commits. |
| **R4** | `shape` = `UOp.shape` (`ops.py:454`), `R` when it raises, `N` when `_shape` is `None` | Three-valued because "has no shape" (the ten ops at `ops.py:331-338`) and "shape raised" are different facts. A dim is a `sint` (`ops.py:1925`) = `int`\|`UOp`: an int prints as its exact `hi:lo` I64 (`H.i64_text` = `i64_show` = `U32.show` `":"` `U32.show`, `helpers.bend:1696-1699`) and a UOp prints as `U` — never as a number, because a symbolic dim read as 0 is a silent wrong shape. |
| **R5** | `depth` = how many times a RANGE's `axis_id` is **nested** | `UOp.range` builds `arg=(axis_type, axis_id)` (`ops.py:643`) with `axis_id` either an int or a tuple; `axis_id` is `self.arg[1:]` (`ops.py:498-500`). So `(WEAK,0,1)` and `(WEAK,(0,1))` share a `str(arg)` and are **different ucache keys** — the key is `(op, src, arg, tag, type(arg))` (`ops.py:201`) and it carries no dtype but does carry `type(arg)`. The port carries the count as `Arena.shp` (`ops.bend:1092-1100`). Without this field the differ calls two different graphs equal. |
| **R6** | `tag` = structured, `N` for absent | `UOp.tagstr` is `f", tag={self.tag}"` (`ops.py:277`) — a repr of an `Any` that may be a bool, str, int or a tuple of UOps. `tag is not None` is upstream's own absence test. |
| **R7** | `arg` = a **structural** recursive encoding, never `UOp.argstr()` | `argstr` is `repr(self.arg)` (`ops.py:274-276`) and `ParamArg.__repr__` (`ops.py:43-50`) **omits every field equal to its default** and rewrites `buffer` as `UOp.new_buffer(...).buffer` — a device object no second process can rebuild. A form that omits defaults cannot see a default change; a form that prints a device object can never match. So `ParamArg` is **all thirteen fields, in declaration order** (`ops.py:26-42`), by NAME. `pyrender` itself refuses a BUFFER carrying a device Buffer (`render.py:159-160`), so `buffer` reduces to `realized<slot>`/`unrealized`. `CallInfo` (`ops.py:1400`) is not even a dataclass — a plain class whose `__repr__` prints `id(self.grad_fxn)`, a per-process address (`ops.py:1408-1410`) — so it is field-by-field too. |
| **R8** | `src` = the **ordered** child indices | Not a multiset: the differ must see a commutative-child swap, and `UOp.key` (`ops.py:269`) concatenates `s.key for s in self.src` **in order**, so upstream's own node identity is order-sensitive. |

### The identity key, and why it is not the whole record

```
core = sha256( op, depth, tag, structural-arg, ordered child cores )
```

This is `UOp.key` (`ops.py:269`) with two deliberate departures:

* `str(arg)` → the structural arg. Upstream's key is stable only because the *printer* is
  stable, which is the premise being rejected here.
* `dtype` and `shape` are **out of** `core` and compared as **fields**. In identity, a
  one-dtype change would present as "a node on one side and not the other". Keeping them as
  fields is strictly more informative.

**What rung 1 can and cannot find — a measured theorem.** `UOp.dtype` is
`dtype_from_uop(self.op, self.src, self.arg)` (`ops.py:247`) and `UOp.shape` is `self._shape`
(`ops.py:454`); both read only op/src/arg, i.e. only the core's constituents. So a field
mismatch on a node whose core MATCHED **cannot mean the graphs differ** — it means the two
*implementations* of `dtype_from_uop`/`_shape` disagree about the same node. That is a real
class of port bug (the port computes both in one FOLD, `fold.bend`'s `DtShape`, a different
implementation that can fail — which is why `fold.shape` can answer `R`). **It has not fired on
any graph measured today.**

A dtype-only plant on a CONST is a **theorem**, and the obvious reading of `ops.py:199` is
wrong. MEASURED: `UOp.const(4)` and `UOp.const(4, dtypes.i32)` are *different objects with
different keys*, because `UOp.const` (`ops.py:629-635`) ends in `.cast(dtype)` and so builds a
`CAST`, not a second `CONST`. A CONST's dtype really is derived (`ops.py:184-190`) and cannot
be set independently. No row can exercise this, and none pretends to.

### Pairing, three rungs

1. equal `core` → SHARED node; every field compared and each disagreement printed **by field
   name**.
2. leftovers paired **one-to-one** on `loose = (op, depth, tag, arg-with-dtype-erased, sorted
   child ops)`: best candidate by count of agreeing fields, **no claim when the best is not a
   unique argmax** (both then fall through).
3. still unpaired → ONLY-`<side>`, printed **in full**.

Two of those three choices were measured wrong first and are recorded in
`bend2-constraints.md` positions 15205 and 15213: child ops **in order** cannot pair a
commutative-child swap at all, and pairing every leftover with every other leftover sharing a
key paired all five RESHAPEs of the matmul with each other.

## 3. The graph: `(Tensor.empty(4,3) @ Tensor.empty(3,5)).uop`, 18 nodes, built on both sides

Real, and **lazy** (never realized), because a realized BUFFER carries a device `Buffer` the
port cannot name. ALLOC, CONST, STACK, RESHAPE, PERMUTE, MUL, REDUCE — every op in it is a
constructor the port has, which is why `graphcmp.bend` can build it node for node.

Both sides emit **18 rows, 8 fields, byte for byte identical** once the device binding is
applied (`runs/graphcmp/10-canon-byte-diff.txt`, `rc=0`):

```
2:i1  5:ALLOC  3:f32     7:(l0:12)          2:i0 1:N 55:P(i0,Df32,i12,N,N,N,SGLOBAL,sNULL,b0,N,unrealized,b1,N) 3:n()
2:i2  5:CONST  7:weakint 2:()               2:i0 1:N  4:l0:4                                             3:n()
...
3:i18 6:REDUCE 3:f32     11:(l0:4,l0:5)     2:i0 1:N 11:rd(OADD,i1)                                     6:n(i17)
```

and the differ over the same two streams:

```
# py rows=18  bend rows=18  plant=none
# dev-map {0: 'NULL'}  (DECLARED, not derived -- see the S.Dev note in R7)
# SHARED cores=18  ONLY-PY=0  ONLY-BEND=0  field-mismatches=0  rung2-pairs=0
# VERDICT: AGREE
```

`runs/graphcmp/04-diff-clean.txt`.

## 4. It discriminates — four checks, all run

**`control`** — each side against itself (`03-control.txt`). `py` vs `py` and `bend` vs `bend`,
both `AGREE`, `rc=0`. A differ never seen to agree with itself is not known to work.

**`cross`** — two DIFFERENT graphs: `matmul` against `Tensor.empty(4,8).sum(axis=1)`
(`08-cross-different-graphs.txt`). 18 rows vs 7 rows, `ONLY-PY=14`, `ONLY-BEND=3`,
`SHARED cores=1` (the `CONST 1`), 3 rung-2 pairs each naming a real `shape` or `src`
difference. `VERDICT: DISAGREE`. A differ that answers AGREE to two different graphs is worse
than no differ, and the only way to know it is not that one is to ask.

**`--plant srcswap`** — the two children of the MUL, which is commutative in tinygrad, so a
**semantic no-op** and exactly what a differ that only counts nodes would miss
(`06-plant-srcswap.txt`):

```
# SHARED cores=15  ONLY-PY=0  ONLY-BEND=0  field-mismatches=0  rung2-pairs=3
MISMATCH PERMUTE   py#17 vs bend#17  (no shared core; paired one-to-one ...)
    src  py=['6af3c6bf'] bend=['a3707272']
MISMATCH MUL       py#16 vs bend#16  (no shared core; paired one-to-one ...)
    src  py=['29e326cf', '52bd0806'] bend=['52bd0806', '29e326cf']
MISMATCH REDUCE    py#18 vs bend#18  (no shared core; paired one-to-one ...)
    src  py=['0a2cb52b'] bend=['6d49643c']
# VERDICT: DISAGREE
```

**The required half: the reordered pair's OWN fields are not flagged.** The MUL's `dtype`
(`f32`), `shape` (`(l0:4,l0:5,l0:3)`), `depth` (`i0`), `tag` (`N`) and `arg` (`N`) are absent
from the report — only `src` is named, and as a pure ORDER (`29e326cf,52bd0806` against
`52bd0806,29e326cf`). The two consumers are named through `src` only, with their own fields
clean. `ONLY-PY=0 / ONLY-BEND=0`: not one node is reported as present on one side only.

**`--plant dtype`** — the two ALLOCs retyped to int32, so every node downstream changes dtype
(`07-plant-dtype.txt`): `ONLY-PY=0 / ONLY-BEND=0`, 10 rung-2 pairs, `dtype` named on **all
ten**, and `arg` additionally named on the two ALLOCs (whose `ParamArg` embeds the dtype):

```
MISMATCH ALLOC  py#1 vs bend#1  ...
    dtype py=i32 bend=f32
    arg   py=P(i0,Di32,i12,...) bend=P(i0,Df32,i12,...)
```

**`--plant shape`** (`09-plant-shape.txt`) — the `(4,3)` shape STACK's two CONST children
reversed. 6 rung-2 pairs, one of which names `shape`:

```
MISMATCH RESHAPE py#5 vs bend#5 ...
    shape py=(l0:3,l0:4) bend=(l0:4,l0:3)
    src   py=['e9ce1f34', 'a923cbbb'] bend=['e9ce1f34', 'c7634b1f']
```

Honest note: it reaches rung **2**, not rung 1, because swapping the STACK's CONST children
moves its `src` and `src` **is** in the core. That is what it establishes — a shape field is
named as a *shape field*, not folded into identity and not summarised as a node difference.

**Every plant edits one side's COPY** (`_rebuild_with` over the toposort). No live file was
patched. And three of these four plants were wrong on the first attempt in ways worth
recording, all in `bend2-constraints.md` positions 15191 / 15205 / 15213: the toposort rebuild
returned its input unchanged (`pl is ast`, so a plant reported `AGREE`); `Tensor.empty` mints
a **fresh `ParamArg.slot` every call** (measured: 0,1 then 2,3), so a clean and a planted emit
that each built their own graph differed in two slot fields before the plant did anything; and
`erase` found no dtype inside `P(i0,Di32,...)` because the first `)` was `P`'s own.

## 5. The five residuals — classified, closed or made visible

Second pass, 2026-10-03. Every number below is measured by calling CPython or `bend`;
the consolidated evidence file is **`runs/graphcmp/probe/p12-residual-evidence.txt`**,
regenerate it with `env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python
runs/graphcmp/probe/p12-residual-evidence.py`. Two of the five classifications in the
previous version of this section were **wrong**, and the measurements say so.

### The mechanism: a LEDGER, printed on every report

Each residual is now a **marker** in the normal form, counted on both sides of every
report, with the non-zero ones called out in a `# RESIDUALS IN THIS RUN:` line **above**
the verdict:

| marker | field | meaning |
|---|---|---|
| `z` | arg | a realized BUFFER: presence only |
| `y` | arg | a bytes arg: length only |
| `u` | arg | a UOp nested in an arg: identity not compared |
| `q` | arg | an applied option the port cannot resolve: count only |
| `X!` | arg | an `AxisType` member with no counterpart at this tree |
| `BAD` | arg | the port's arena bottom |
| `E` | arg | an enum member outside `{Ops, AxisType, AddrSpace}` |
| `?` | shape | the port's fold produced no shape at all |

A `0/0` is printed too, because it is a measurement: it answers *"did that path run?"*,
which is the question a residual list otherwise never answers. `selfcheck` asserts every
marker is a spelling the emitter can produce, and `.agents/slop/graphcmp-probe-optq.bend`
calls the three emitters no graph reaches today so their rows are measured, not assumed:

```
Q-KI-DEFAULT kI(stest,n(),N,i0)      Q-AXIS-LIVE   XWEAK
Q-KI-REFUSAL kI(splant,n(q,q),n(q),i2)  Q-AXIS-DEAD   X!REDUCE
Q-KI-OTA-None kI(sprobe,n(),N,i0)    Q-AXIS-DEAD   X!UNROLL
Q-BUF-YES     z                      Q-SHAPE-NONE  ?
Q-BUF-NO      N                      Q-SHAPE-NOSHAPE R
```

**The precedent this follows is the DEBUG unit's**, not a new idea: a residual is closed by
a measurement over the space where it would have appeared, or it is left visible. None of
the five below is closed by copying the port's answer into the oracle.

---

### 1. A realized BUFFER's `buffer` — **CLOSED (as far as it can be), and it was a live bug**

**Classification: a PORT limitation in the middle of a NORMAL-FORM BUG, and the bug was
worse than the residual.**

The previous version of this report claimed `buffer` "reduces to `realized<slot>` /
`unrealized`: presence **and slot** are compared". The code said
`f"realized{u(pa.buffer)}"`, and `u(x)` is `"i" + str(x)` — so on a realized graph the
normal form was emitting

```
realizedi<buf real:False device:CPU size:12 dtype:dtypes.f32>
```

**52 characters of device object inside the normal form**, including `dtypes.f32` — the
exact token R3 exists to drop because it moves between upstream commits — and `real:`, an
allocation state. The header's own rule ("a form that prints a device object can never
match") was being broken by the code two hundred lines below it.

And the "slot" was never there. **MEASURED: `Buffer` has no `slot` attribute.** There was
nothing to compare.

**What is comparable, and is compared:** `size`, `dtype`, `device`, `offset` are already
`ParamArg` fields 3, 2, 8 and are already compared. `trace_num` is a per-process counter
and is never read. So presence is the finest split both sides can make, and both sides now
emit `z` / `N`.

**It is now exercised by a real diff, not asserted by a comment.** `--graph buffer` is a
new fixture on both sides, and MEASURED facts it encodes:

```
Tensor.empty(4,3)   -> ALLOC , ParamArg.slot=0
.realize()          -> BUFFER, ParamArg.slot=1   <-- A DIFFERENT SLOT
```

Realize **mints a fresh `ParamArg`** (`UOp.new_buffer`, ops.py:1208,
`if slot is None: slot = next(UOp.unique_num)`), and a BUFFER's `bind_on_realize` is
`False` where an ALLOC's is `True`. Writing `slot=0` in the fixture because "it was 0
before the realize" is exactly the reading that measurement forbids.

```
$ graphcmp.py diff --graph buffer
# py rows=5  bend rows=5  plant=none
# RESIDUALS IN THIS RUN: z=1/1 (a realized BUFFER: device-object PRESENCE only) -- agreement below does NOT cover these.
# SHARED cores=5  ONLY-PY=0  ONLY-BEND=0  field-mismatches=0  rung2-pairs=0
# VERDICT: AGREE
```

The two canonical files are also byte-identical (5 rows), so the cheapest check in the file
still works.

**One text change on the matmul, on both sides:** `unrealized` → `N`. Same information —
absence — now spelled the way the other six `Maybe` fields of the same record already
spell it. The reason is measured, not aesthetic: `unrealized` **contains `realized` as a
substring** and **starts with the ledger's `u`**, so at a value position — exactly where
it sat — any scan counted the absent case as a present one *and* counted a nested UOp that
was not there. The before/after is `runs/graphcmp/C11-superset.txt` and it is two lines.

### 2. `KernelInfo.applied_opts` — **the emitter CRASHED. Now closed for the reachable half, refusal for the rest**

**Classification: a NORMAL-FORM BUG (a hard failure, not a comparison gap) sitting on top
of a PORT limitation.**

The previous report said these "are emitted from the port's `U32` ids and from CPython's
`Option` dataclasses, and will not agree". Both halves of that are wrong:

* **there is no `Option` class in this tree.** `grep -rn "class Option" tinygrad/` finds
  nothing. The class is `Opt` (`tinygrad/codegen/opt/__init__.py:11`,
  `@dataclass(frozen=True, order=True)` with `op: OptOps`, `axis`, `arg`), and `OptOps` is a
  plain `Enum` (`TC, SPLIT, PADTO, SWAP`).
* **the emitter did not emit anything at all.** `carg(Ops.SINK, <a KernelInfo with a
  non-empty applied_opts>)` **died**:

  ```
  File ".agents/slop/graphcmp.py", line 361, in _carg
  File ".agents/slop/graphcmp.py", line 360, in _carg
      d = {k: v for k, v in vars(x).items() if k != "grad_fxn"}
  TypeError: vars() argument must have __dict__ attribute
  ```

  A kernelized graph could not be emitted at all. The residual was written up as a
  comparison limit; it was a traceback.

**The crash chain, because the obvious explanation is wrong and cost a probe.** Not "an
enum member has no `__dict__`" — MEASURED, `vars(OptOps.TC)` returns a real `dict` whose
`_value_` (1), `_name_` ("TC") and `_sort_order_` (0) all render fine through the arms
above the fallback. The fourth entry is `__objclass__`, **the enum class**. `vars()` on a
class is its `mappingproxy` (17 entries for `OptOps`), the fallback walks that namespace,
and the first entry that reaches the `vars()` arm and is not a class is **`_new_member_`,
a `builtin_function_or_method`** — no `__dict__`, `TypeError`. (`_member_map_`, a `dict`,
is the second.) So the defect was never "enums are special": it was that **the generic
`vars()` fallback follows `__objclass__` out of the value and into its class**, and had it
survived it would have emitted a text full of dunder names and a recursive walk back
through `OptOps.TC` — the printer instability this whole file exists to remove, arriving
through the back door.

Two independent guards, both load-bearing: the new `enum.Enum` arm stops the walk at the
value, and the `__dict__ is None` guard at the bottom catches the descriptors had the arm
not existed.

**Three structural fixes, each with its own measurement:**

| was | is | why |
|---|---|---|
| py: 3 slots `kI(name, applied, beam)` | **4** `kI(name, applied, ota, beam)` | `KernelInfo`'s declaration order (ops.py:1342-1347) minus `estimates` |
| bend: **2** slots `kI(name, beam)` | **4** | a 2-vs-3 arity accident can only ever report "the port renders fewer fields", which is not about the graph |
| both: `opts_to_apply` **dropped** | both emit it | see below |

**`opts_to_apply` was the residual nobody was looking at**, because it was dropped on
*both* sides and a field neither side carries cannot be seen by either. `KernelInfo`
(ops.py:1345) declares it; `tinygrad/llm/kernels/amd.py` (nine sites) and
`nn/__init__.py:363` write `opts_to_apply=()` on **every** SINK they build — an **EMPTY
TUPLE, not `None`** — while the port's `KernelInfo.of()` answers `None` (MEASURED, probe
Q1b). So the two sides genuinely differ on a field this gate could not name in either
direction. Note also that `uop/render.bend:664` hard-codes `opts_to_apply=None` in its
`KernelInfo` repr, so it prints `None` where upstream prints `()` — **a port output bug,
reported, not fixed** (`render.bend` is not this unit's file).

**The reachable half is now a real diff.** `--graph sink` is a new fixture:

```
$ graphcmp.py diff --graph sink
# py rows=2  bend rows=2  plant=none
# RESIDUALS IN THIS RUN: none -- every ledger entry is 0 on both sides.
# SHARED cores=2  ONLY-PY=0  ONLY-BEND=0  field-mismatches=0  rung2-pairs=0
# VERDICT: AGREE
```

with `kI(stest,n(),N,i0)` on both sides — the one `kI` text both sides can produce, and
`shape=R` on both sides (see finding 6 below).

**The unreachable half is a refusal, and it is not the port's answer.** The port types both
lists `List<&2,U32>` (ops.bend:978) and upstream's elements are `Opt` dataclasses, so the
bend side emits **one `q` per option** — the count compares, the content is a named
refusal. Copying `U32.show` of the port's indices into the oracle would have been exactly
the failure this project has paid for, and there is a measured reason it would have been
wrong: `uop/render.bend:655` calls those U32s "UOp INDICES", and **no port file ever writes
a non-empty list** (the only writer is `KernelInfo.of()` → `Nil{}`; the only other reader is
`engine/realize.bend:1200` passing it through), so that reading is UNVERIFIED — there is no
construction site to verify it against.

**The non-empty case is a reported mismatch, and it is the regression row for the crash:**

```
$ graphcmp.py diff --plant opt
# RESIDUALS IN THIS RUN: E=3/0 (an enum member outside {Ops, AxisType, AddrSpace}: NAME only)
# ONLY-PY=1
  py#19 SINK dtype=void shape=R depth=i0 tag=N arg=kI(splant,n(Opt(op=EOptOps.TCaxis=i0arg=i4),Opt(op=EOptOps.SWAPaxis=Narg=N)),n(Opt(op=EOptOps.PADTOaxis=i1arg=N)),i2) src=['18']
# VERDICT: DISAGREE
```

**Owner, unchanged:** P5 / `codegen/opt/__init__.bend`. `ops.bend`'s `KernelInfo` is 63
importers' business and is not this unit's to change.

### 3. `bytes` by length only — **a PORT BUG, not a normal-form limitation, and it is reported**

**Classification: PORT limitation, with a measured correctness consequence on the port's
IDENTITY.** The previous report called it "not fixable without a byte string", which is
true and is the least interesting part.

**MEASURED, both sides, on the same two blobs:**

```
upstream  UOp(Ops.BINARY, (), b"aaaa") is UOp(Ops.BINARY, (), b"bbbb")  -> False
upstream  their keys are equal                                          -> False
upstream  UOp(Ops.BINARY, (), b"aaaa") is UOp(Ops.BINARY, (), b"aaaa")  -> True   (interned)
PORT      ABlob{4} twice -> arena indices 1 and 1, Arena.next = 2                (ONE node)
```

`ops.py:201` keys on `arg`, so **upstream's node identity includes the bytes content** and
the port's does not: the port **interns two different blobs of the same length as the same
node**. That is a port-level false-interning bug, and it is in `ops.bend`'s `eq_arg.ABlob`
— 63 importers, **reported, not fixed**.

So this residual is stronger than "we compare less than the printer would": two graphs
upstream calls different, this gate can only report as equal. Upstream's own renderer is
also length-only (`viz/serve.py:134` prints `<{len(u.arg)} bytes>`, `spec.py:96` only tests
`isinstance`), which is why it went unnoticed — but the interning is not upstream's
behaviour and the port is not upstream's renderer.

**Made visible three ways:** the `y` ledger row with the measurement in its reason; a
`--plant bytes` that builds two equal-length different-content BINARIES and gets them
reported; and the probe above. The plant:

```
$ graphcmp.py diff --plant bytes
# RESIDUALS IN THIS RUN: y=2/0 (a bytes arg: LENGTH only) -- agreement below does NOT cover these.
# SHARED cores=18  ONLY-PY=3  ONLY-BEND=0
  py#19 BINARY dtype=u8 shape=(l0:4) depth=i0 tag=N arg=y4 src=[]
  py#20 BINARY dtype=u8 shape=(l0:4) depth=i0 tag=N arg=y4 src=[]
  py#21 SOURCE dtype=void shape=R depth=i0 tag=N arg=N src=['18', '19', '20']
# VERDICT: DISAGREE
```

Note the two BINARIES print **identically** (`arg=y4`) — that is the hole, shown rather than
described — and the port cannot express the second one at all, so it is reported one-sided.

### 4. A `UOp` nested in an `arg` — **the justification for it was false; now a counted refusal and a reported node**

**Classification: NORMAL-FORM LIMITATION, on both sides, genuinely unreachable here — but
the comment that excused it was a claim and the claim was false.**

The old comment: *"the arg's identity is already carried by the graph's `src` edges"*.
**MEASURED, and it is not true:**

```
p = UOp(Ops.PYLITERAL, (), (UOp.const(4),))
p.arg[0] is c4        -> True      (the same object)
len(p.src)            -> 0         <== the comment said src carried it
p.toposort()          -> ['PYLITERAL']
c4 in p.toposort()    -> False
```

The nested UOp is in **neither** `src` nor `toposort`, so it has no index in the toposort
this file numbers arenas by, and there is nothing for the differ to compare it against. The
port's only carriers are `ATuple`/`TTuple` of `U32`, and `ATuple` **also spells PERMUTE's
literal ints** (`graphcmp.bend`'s own matmul builds `O.ATuple{[0, 2, 1]}` for a PERMUTE),
so the two readings cannot be told apart from the value.

**It was also rendering as a STRING.** The old text was `ATOMS["str"] + "<uop>"` — the `s`
atom — so a PYLITERAL holding a UOp was byte-identical to one holding the five-character
string `<uop>`, and `selfcheck`'s distinctness claim did not cover it because both sides
made the same substitution. `u` is its own letter now.

**Made visible:** the `u` ledger row and a plant.

```
$ graphcmp.py diff --plant pyuop
# RESIDUALS IN THIS RUN: u=1/0 (a UOp nested in an arg: identity NOT compared)
# SHARED cores=18  ONLY-PY=1
  py#19 PYLITERAL dtype=void shape=R depth=i0 tag=N arg=n(u) src=['18']
# VERDICT: DISAGREE
```

### 5. Three BEND-ONLY `AxisType` members — **it is TWO, and they are now marked**

**Classification: PORT retention of deleted upstream members. Reported wrong before; now
measured and marked.**

The previous report listed `AxisType.PLACEHOLDER / REDUCE / UNROLL` as port-only.
**MEASURED at `3138973dc`, calling CPython, twice:**

```
list(AxisType) -> ['DEVICE','GLOBAL','LOCAL','WARP','WEAK','LOOP','UPCAST','PLACEHOLDER']  (8)
hasattr(AxisType,'PLACEHOLDER') -> True      hasattr(AxisType,'REDUCE') -> False
hasattr(AxisType,'UNROLL')     -> False      hasattr(AxisType,'LOOP')     -> True
```

`PLACEHOLDER` **exists** here. The port's `type AxisType` (ops.bend:641-654) declares
**ten**: the eight live ones plus `AXIS_REDUCE` and `AXIS_UNROLL`, deleted upstream by
`78d482262` and retained for six committed files. **So it is two, not three.** The report
was wrong and the port's own comment ("these two", ops.bend:650-652) was right.

**Now marked, not just commented.** `AxisType.name` answers the bare `"REDUCE"`, a name no
CPython enum can have, so a node carrying one reports as ONLY-ON-THE-BEND — loud enough
today, but **not** if upstream ever adds a `REDUCE` back with different meaning: then the
two would render identically and agree for the wrong reason. `axis1` emits `X!REDUCE` and
`X!UNROLL`, spellings no other reading can produce, so "is this member real?" is in the
text rather than in a comment. The ledger counts them (`X!`), and it reads `0/0` on every
graph measured today, which is the honest answer: no graph either side builds reaches them.

### 6. **NEW, not on the list: the shape column's third value was a COLLISION**

Found by `--graph sink`, and reported rather than hidden, because it is exactly the failure
this project has hit repeatedly — a rule that stops discriminating.

`--graph sink` is the first fixture with a shape-less node, and the differ reported:

```
MISMATCH SINK  py#2 vs bend#2  shape py=R bend=N
```

a **rung-1 field mismatch on a node whose CORE MATCHED**, which by this file's own measured
theorem cannot mean the graphs differ — it means the two `_shape` implementations disagree.

**MEASURED which one is wrong.** `UOp.shape` is a property that raises **iff** `_shape is
None` (ops.py:455), so it **never returns `None`**. Probed over all ten ops in the upstream
no-shape list (ops.py:331-338) plus a void `INS` and a `PYLITERAL` — twelve ops,
`_shape is None` **and** `shape` raises in all twelve. So:

* the normal form's `N` is **dead on the CPython side**, and
* the bend side was using `N` **meaningfully** (its `Some{None}` = "this op has no shape"),
* i.e. one letter for two different facts, invisible until a graph existed that used it.

The bend side's `Some{None}` now renders `R`, the same as a raise. The port's **other**
no-Derived state — the fold produced nothing for this node — is a port-only fact with no
upstream counterpart and gets its own atom, `?`, so a fold that stops settling reads as a
hole rather than as an agreement. The dead py-side `N` arm is **kept and counted**, because
a deleted branch is a claim and a counter is a measurement:

```
# shape-N hits py=0 (expected 0: `UOp.shape` RAISES instead of returning None, ops.py:455 -- probed over all 12 no-shape ops)
```

printed on every report.

---

### Still residual, unchanged, with the owner named

| # | residual | why it cannot close here | owner |
|---|---|---|---|
| A | a realized buffer's **identity** | `Buffer` has no `slot` (measured); the port's is a P6 allocator slot with no runtime (ops.bend:913). `z=1/1` on `--graph buffer` — presence is compared, identity is not, and the report says so. | the P6 runtime |
| B | `applied_opts` / `opts_to_apply` **contents** | the port holds `List<U32>` and no port file writes a non-empty list, so the "UOp indices" reading of `render.bend:655` is unverifiable. `q` = count compared, content refused. | `codegen/opt/__init__.bend` + whoever may type those fields |
| C | a bytes arg's **content** | the port has no byte string, and — measured — the port's *identity* does not see it either (`ABlob{4}` interned twice). | `ops.bend`'s `eq_arg.ABlob` (63 importers) |
| D | a nested UOp's **identity** | not in `src`, not in `toposort`, so no arena index; and `ATuple` is ambiguous with PERMUTE. | needs a distinct `Arg` variant — `ops.bend`'s `Arg` |
| E | `KernelInfo.estimates` | dropped by `ops.bend` (P5). **Named, not counted**: a count would be 0 by construction. | P5 |
| F | `AxisType.REDUCE` / `UNROLL` | deleted upstream by `78d482262`, retained for six committed files. Now `X!`-marked. | `ops.bend`'s owner |

**New port findings this pass produced, both REPORTED and NOT FIXED** (neither file is this
unit's, and `ops.bend` has 63 importers):

1. **`ops.bend`'s `eq_arg.ABlob` false-interns.** Two different byte blobs of equal length
   become the same arena node; upstream keys them apart. `runs/graphcmp/probe/pb-buf-binary.bend`
   Q1 and `p7-binary-upstream.py`.
2. **`uop/render.bend:664` prints `opts_to_apply=None`** where every `llm/kernels/amd.py`
   and `nn/__init__.py` SINK writes `opts_to_apply=()`. An empty tuple is not `None`.

**And one correction to this file's own previous text:** residual #3 in the old version
claimed `CallInfo` "will report as a named `arg` mismatch". It will not — `arg` is in
`core`, so a differing text means a differing core, which means rung 3, i.e. ONLY-`<side>`,
not a named field. The same applies to every `arg`-carrying residual above: they are
one-sided nodes, and the ledger says *why* they could not be matched.

**What is NOT residual, re-measured rather than assumed:** `PYTHONPATH` is not a blocker
(tinygrad is an editable install); `DEBUG` appears nowhere in `uop/ops.py` or
`codegen/__init__.py`, so the indexed dump is not gated there.

## 6. The comparability traps, and what answers each

| trap | answer, by construction |
|---|---|
| Row names with spaces (`^(\S+) = ` dropped 216 of 228) | eight `<bytecount>:<bytes>` chunks; the reader walks the counts. `selfcheck` round-trips `"PTX tensor_cores sm_75"`, `"a b"`, `"x:y"`, `"name = [value]"`, `""` |
| Lane-specific row shapes (`name=value` vs `name = [value]`) | one reader, one shape; there is no second lane |
| Locale-colated sort/comm fabricating diffs, **including on a control** | this differ **never calls `sort` or `comm`** — every ordering is Python's own `sorted`/dict order — and every child gets `LC_ALL=C` anyway. `control` is the assertion |
| A 0-row result indistinguishable from "not started" | `emit_bend` re-runs 5× and then **raises**. MEASURED 20 consecutive raw runs: 20 × 18 rows, so the trap never fired naturally — so the guard was **fired on purpose** against `.agents/slop/graphcmp-empty.bend`, which prints no rows: `emit bend: 0 rows after 5 attempts -- a FAILURE, not a verdict` (`11-repeat-stability.txt`) |
| UCache identity is not structural identity (`ops.py:201` does not separate `(WEAK,0,1)` from `(WEAK,(0,1))`) | `depth` is its own **field** (R5) *and* is embedded in the `rg(...)` arg |
| `--check-only` exits 1 on a clean file | nothing here gates on bend's exit status; `runs/graphcmp/README.txt` records the check's **first line**, not its rc |
| `PYTHONPATH` contaminating a control | `env -u PYTHONPATH` on every child; the tree is read from `tinygrad.__file__`, not assumed |
| A harness comparing whole lines vs row names | the differ compares **fields**, by name |

Also: `runs/graphcmp/11-repeat-stability.txt` holds **8 consecutive clean diffs**, all
`AGREE`. A 0-row event was not observed in them.

## 7. Why not `pretty_print` (`tinybendygrad/uop/render.bend:1903`, `PORTED IN PART`)

I did not touch it. Two measured reasons:

* **`pretty_print` is not a normal form.** It prints `type(x).__name__(op, arg=…, tag=…,
  src=(…))` — the arg through `repr`, i.e. through the very `ParamArg.__repr__`
  (`ops.py:43-50`) that omits defaults and prints a device object. Nothing in it is
  comparable.
* **Its `dfs` is the blocker, and it is the blocker `render.bend` already names.** The cache
  is `cache.setdefault(s, [len(cache), 0, False])[1] += 1` over a **cyclic** graph, so the
  cache is a second store beside the arena and the walk needs a fuel CPython's does not — and
  `ctx_get` answers `""` for an unwritten src, which the file's own `to_render` note says
  produced SHAPE-wrong output rather than merely different output.

`pyrender` **is** landed and is used by nothing here: `pyrender` renders only a *subset*
(`render.py:147-163` skips CONSTs and single-consumer nodes), so it cannot be the normal form
of a graph.

## 8. Outside this unit's files

* **`tinybendygrad/helpers.bend` was transiently broken during this session and was fixed by
  another agent, not by me.** `graphcmp.bend` failed with `SOME PROOFS FAIL … observed: gi_nz
  (an unfilled law)` and then `observed: st (consumed more than once)` at
  `tinybendygrad/helpers.bend:246-250`; `jj status` showed `M tinybendygrad/helpers.bend` in
  the shared working copy. Every `graphcmp.py` run re-runs `bend` up to 5× on an empty stream,
  so it recovered, but **a concurrent edit to `helpers.bend` can make this probe go red for
  reasons that have nothing to do with it.** Owner: the `helpers.bend` agent.
* **`.agents/slop/graphcmp.bend` was DELETED from under this session once**, roughly 40
  minutes after I wrote it, by something in `.agents/slop/` — it was simply gone (`ls` failed)
  and I rewrote it. `.agents/slop/` has 860+ entries and concurrent agents; a file there is
  not durable until committed. Worth knowing before anyone treats an absent
  `.agents/slop/graphcmp.*` as "never written".
* `tinybendygrad/uop/render.bend` — **not touched**, so `pretty_print` stays `PORTED IN PART`
  and the six `TODO(p3) render.py` lines stay as they were.
* `tinybendygrad/uop/ops.bend` (63 importers), `helpers.bend`, `LAWS/**`, `PROOF*.bend`,
  `codegen/**`, `runtime/**`, `renderer/**`, `rebase-gate.py`, `naming-gate.py` — untouched.
* The seven `DEBUG >= 2` sites — untouched, as instructed.

## 9. Commands

```
E() { env -u PYTHONPATH LC_ALL=C .venv/bin/python .agents/slop/graphcmp.py "$@"; }

E selfcheck
E diff                                   # matmul, the real comparison
E diff --graph reduce
E diff --graph buffer                    # a REALIZED BUFFER, residual 1
E diff --graph sink                      # a SINK + the R shape value, residual 2
E diff --graph lin                       # A REAL LINEARIZED PROGRAM: 46 nodes, LOAD+STORE
E diff --graph loop                      # hcq_fence, upstream's own poll loop: BACKEDGE
E diff --graph gate                      # the real pm_linearize_cleanups: IF/ENDIF (AGREE)
E control --graph gate                   # the widest fan-in in the corpus, against itself
E control --graph loop                   # a DISAGREEING graph, against itself
E diff --graph lin --equiv               # --equiv on a real kernel: STILL DISAGREE,
                                         # because `lin`'s only difference is in `arg`
                                         # (the applied_opts count) and --equiv forgives a
                                         # `src` REORDERING and nothing else
E control                                # each side against itself
E cross                                  # two different graphs, BOTH sides
E diff --plant srcswap                   # the reordered pair's OWN fields must stay clean
E diff --plant dtype
E diff --plant shape
E diff --plant bytes                     # residual 3: two same-length blobs
E diff --plant pyuop                     # residual 4: a UOp inside an arg
E diff --plant opt                       # residual 2: the emitter-crash regression row
E diff --bend-probe runs/graphcmp/graphcmp-empty.bend   # the 0-row guard, fired on purpose

# the five residuals, one measurement each:
env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python runs/graphcmp/probe/p12-residual-evidence.py
bin/bend runs/graphcmp/probe/pb-buf-binary.bend      # the ABlob false-interning, port side
bin/bend .agents/slop/graphcmp-probe-optq.bend      # the three refusal spellings

# WHAT A REAL SCHEDULED PROGRAM CONTAINS -- the probes round three was built on:
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-p14-sched.py
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-p14b.py
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-p14c.py
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-p14d.py
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-p14e.py

# THE WHOLE ARTEFACT, AND ITS REPRODUCIBILITY:
sh .agents/slop/graphcmp-run.sh      # regenerates every file in runs/graphcmp/D/
sh .agents/slop/graphcmp-repro.sh    # 154 of 154 files identical across two clean runs
```

There is **no `--dev-map`**. The device name is not bound at a prompt: the port resolves its
interned tag through its own table (`uop/render.bend:363`) and both sides carry a NAME.

Exit status: `0` agree, `1` disagree, `2` a side produced nothing (a failure, never a verdict).

Four Bend-specific rules the port side taught and this file records: a record pattern binds
**positionally with bare names** (`case ADt{y1}`, `ops.bend:1715`) — there is no `field:
binder` form and no `x.field`; a binder or parameter used more than once needs a leading `+`;
`match` can scrutinise only a *parameter* or a *pattern binder*, never a local binder and
never a computed value (give the value its own def and pass it as a parameter); and a `do`
block must end in a bare TERM, not a `<-` binding (`bend2-constraints.md`, end of file).
