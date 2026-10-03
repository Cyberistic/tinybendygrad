# graphcmp — a canonical graph normal form both sides emit, and a differ over it

Measured 2026-10-03. Harness: `.agents/slop/graphcmp.py` (the differ and the CPython
emitter) and `.agents/slop/graphcmp.bend` (the port-side emitter). Artifacts:
`runs/graphcmp/`. No port file was edited. No live tree was patched.

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

## 5. Today's honest residual mismatch list

The two graphs **match exactly** on the matmul, so this is a list of what the normal form
*cannot* compare and of what was true before `--dev-map`.

| # | residual | why | owner |
|---|---|---|---|
| **1** | **The device is an interned index on one side and a name on the other.** The port emits `t0`, CPython emits `sNULL`; with no binding the differ reports `UNBOUND-DEVTAG [0]` and the two ALLOCs land in ONLY-PY / ONLY-BEND (`05-diff-unbound-devtag.txt`). | `S.Dev` is `D1{tag}` (`spec.bend:85-87`) and the tag is a local interning index. **Three port files, three tables**: `schedule/__init__.bend:1095` "tag 0 stands for CPU"; `schedule/memory.bend:998-999` 0 = CPU, 1 = DISK; `device.bend:702` `dev_name` 7 = CPU, 11 = NULL. There is **no reader from a tag to a name**. `--dev-map 0=NULL` is a **declared binding, not a derived one**, and the report says so on every line. | whoever reconciles the three device tables |
| **2** | **A realized BUFFER's `buffer` cannot be compared.** Only presence + slot are. | `pyrender` itself refuses it (`render.py:159-160`); the port's `buffer` is a P6 allocator slot with no runtime behind it (`ops.bend:883`). | the P6 runtime |
| **3** | **`CallInfo` texts differ by one field.** CPython has `name, precompile, precompile_backward` (`ops.py:1400-1406`); the port has `name, precompile, precompile_backward, dtype` (`ops.bend:1059-1060`) — the `dtype` one is the pin's, dropped three commits later. A CALL node will report as a named `arg` mismatch. Not exercised by the matmul (no CALL in it). | pin vs head, per `UPSTREAM-PIN.md` | the rebase owner |
| **4** | **`KernelInfo.applied_opts` / `opts_to_apply` are emitted from the port's `U32` ids and from CPython's `Option` dataclasses, and will not agree.** Not exercised by the matmul (no SINK). | the port's option ids are a P5 cost-model table; CPython's are `Option` dataclasses | the P5 cost model |
| **5** | **A `bytes` arg is compared by LENGTH only.** | `ops.bend:913`: "bytes BINARY arg; only its length is read". There is no byte string in the port. | not fixable without a byte string |
| **6** | **A `UOp` inside an `arg` is recorded as `<uop>`, not by identity.** | `Ops.PYLITERAL`'s literal and `Ops.MSELECT`'s matcher can hold UOps (`ops.bend:938-941`). The arg's identity is already carried by the `src` edges, and a UOp's repr is the whole problem this file removes. Not exercised by the matmul. | — |
| **7** | **`AxisType.PLACEHOLDER` / `REDUCE` / `UNROLL` exist on the port and not at this tree** (`ops.bend:649-654`). No CPython row can ask for them, so those three arms of `AxisType.name` are BEND-ONLY and would read as a one-sided node. | deleted upstream by `78d482262`, retained for six committed files | `ops.bend`'s owner |
| **8** | **`Ops.ALPHA_REWRITE` and any op added to `ops.bend` after this measurement** would have no CPython counterpart and would surface as a one-sided node. The emitter is an exhaustive `match`, so this is a compile error rather than a silent omission — which is the right failure. | — | — |

**What is NOT residual, and was measured rather than assumed:** `PYTHONPATH` is not a blocker
(confirmed by the pin/HEAD import log and re-confirmed here — `tinygrad` is an editable
install and resolves from any cwd); `DEBUG >= 1` appears **nowhere** in
`tinygrad/uop/ops.py` or `tinygrad/codegen/__init__.py`, so the indexed dump is not gated
there and `print_uops` (`render.py:18`) is the only indexed dump in reach — this unit did not
need it and did not wire the `DEBUG >= 2` sites.

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
E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py

E selfcheck
E emit --side py                    > runs/graphcmp/01-canon-py.txt
E emit --side bend --dev-map 0=NULL  > runs/graphcmp/02-canon-bend.txt
diff runs/graphcmp/01-canon-py.txt runs/graphcmp/02-canon-bend.txt   # rc=0, BYTE-IDENTICAL
E control   --dev-map 0=NULL        # each side against itself
E diff      --dev-map 0=NULL        # the real comparison
E diff                                # the same, device binding absent
E diff      --dev-map 0=NULL --plant srcswap
E diff      --dev-map 0=NULL --plant dtype
E diff      --dev-map 0=NULL --plant shape
E cross     --dev-map 0=NULL        # matmul vs sum(axis=1)
E diff --bend-probe .agents/slop/graphcmp-empty.bend   # the 0-row guard, fired on purpose
```

Exit status: `0` agree, `1` disagree, `2` a side produced nothing (a failure, never a verdict).

Two Bend-specific rules the port side taught and this file records: a record pattern binds
**positionally with bare names** (`case ADt{y1}`, `ops.bend:1715`) — there is no `field:
binder` form and no `x.field`; and a binder or parameter used more than once needs a leading
`+` (`bend2-constraints.md` position ~627).