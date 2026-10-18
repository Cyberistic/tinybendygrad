# `gate` — the LINEAR `src` is one child short, and the child is the SHAPE const

**Verdict: `MISSING_CASE`.** One missing child on ONE node. Not three missing rows, and not
a missing op — see §1, which corrects the premise of the brief.

| | |
|---|---|
| HEAD | `4b42c0ccf7e53bb140680a19bbcdaddad2f02bf4` (`arenaparam: the 62 self-parenting nodes are threaded, and the corpus is 31/34 BEFORE AND AFTER`) |
| read at | `2026-10-18T17:31:14Z` |
| corpus run | `runs/graphcmp/D/D0-run-summary.txt`, mtime `2026-10-18T17:26:49Z` |
| artifacts | `D2-canon-py-gate.txt` sha256 `82c6d94f18667dd7151e4fc8022ed130d590978937d78080e54fd3c5cf8f0f3b`, `D2-canon-bend-gate.txt` sha256 `0cd1b5f6ada8975a0aa000a640c93576469f335d58516e0a579c272f5c2dda3f` |
| denominators | `graphs=34  graphs-agree=31  graphs-disagree=2  byte-identical=20` |

**THE TREE MOVED UNDER THIS READING, AND IT IS RECORDED.** The first read of these files was
at `17:22:20Z` and showed mtimes of `Oct 18 05:49`; the run that produced the sha256 above
rewrote them at `17:28:57Z`–`17:28:59Z`. The divergence text in `D2-cmp-gate.txt` is
**character-for-character identical** across both readings, and `D0-run-summary.txt` reports
the same 31/2/20, so the diagnosis below survives the rewrite. It is still one run's reading,
not a property of the tree.

**Every file this report quotes was verified still-current at `2026-10-18T17:32:06Z`**:
`graphcmp.py` mtime `Oct 17 13:41:46`, `graphcmp.bend` `Oct 18 04:43:55`,
`tinygrad/codegen/late/linearizer.py` and `tinygrad/codegen/__init__.py` both
`Oct 17 07:12:10`, `tinybendygrad/uop/ops.bend` `Oct 18 05:14:37` — all older than this
session, and `sed` re-read the two quoted `graphcmp.bend` lines and both `tinygrad` snippets
verbatim. **I edited no file anywhere; the `MM` entries `git status` reports on
`graphcmp.bend` and the `tinybendygrad/` files are other units' work, not mine.**

---

## 1. THE `3` IS BYTES, NOT ROWS

The brief reads the row `49:n(...)` as "49 rows" and concludes the port "emits 46 rows and is
3 rows short". The leading integer is a **byte count of that field's text**, not a row count
and not a graph size. `.agents/slop/graphcmp.py:351-356`:

```python
def chunk(s: str) -> str:
  """`<bytecount>:<bytes>` -- BYTES, because bytes are what the reader walks."""
  b = s.encode()
  if any(c > 127 for c in b):
    raise ValueError(f"non-ASCII in a normal-form chunk: {s!r}")
  return f"{len(b)}:{b.decode()}"
```

and `row_of` (`:877-879`) is eight such chunks joined by spaces:

```python
def row_of(n: UOp, k: int, ix: dict) -> str:
  return " ".join(chunk(v) for v in [u(k), n.op.name, n.dtype.name, cshape(n), u(cdepth(n)),
                                     ctag(n.tag), carg(n.op, n.arg, n), tup([u(ix[id(s)]) for s in n.src])])
```

The eighth chunk is `src`. MEASURED, both sides, at `17:31:14Z`:

```
rows py=15 bend=15   rows 1..14 byte-identical = True   fields per row = 8 both sides
py   src = n(i1,i2,i3,i4,i5,i6,i7,i8,i9,i10,i11,i12,i13,i14)   49 bytes   14 children
bend src = n(i2,i3,i4,i5,i6,i7,i8,i9,i10,i11,i12,i13,i14)       46 bytes   13 children
49 - 46 = 3, and len(',i1') = 3
```

**So: 15 canonical rows on both sides. 0 rows missing. 0 ops missing.** The op census is
identical, node for node:

```
CONST=3  INDEX=2  PARAM=1  BUFFER=1  RANGE=1  CMPLT=1  IF=1  STORE=1  ENDIF=1  END=1  SINK=1  LINEAR=1
```

(12 distinct ops, 15 nodes.) `D2-cmp-gate.txt` says `15c15` — ONE changed line out of 15 —
which is consistent with this and with nothing else.

---

## 2. THE TWO DEFINITIONS, SIDE BY SIDE

### CPython — `.agents/slop/graphcmp.py:1290-1304`

```python
  buf = _storage(Ops.BUFFER, 1, dtypes.float, 16, device="CPU")
  val = _storage(Ops.PARAM, 0, dtypes.float, 16, device="CPU", name="v0")
  r = UOp.range(4, 0)
  st = buf.index(r).store(val.index(r), r < UOp.const(3)).end(r)
  sk = st.sink(arg=KernelInfo(name="gated"))
  lines = line_rewrite(linearize(sk), pm_linearize_cleanups)
  ...
  return UOp(Ops.LINEAR, src=tuple(lines))
```

The `src` is **computed**: `tuple(lines)`.

### the port — `.agents/slop/graphcmp.bend:1089-1111`

```
def g_gate() -> O.Found:
  +ar = O.Arena.empty()
  +p0 = O.UOp.new.param(ar, O.OpsPARAM{}, Some{16}, O.AParam{paramd(0, S.single(), Some{"v0"}, False{})}, O.TNone{})
  +bf = O.UOp.new.param(O.Found.ar(p0), O.OpsBUFFER{}, Some{16}, O.AParam{paramd(1, S.single(), None{}, False{})}, O.TNone{})
  ...
  O.UOp.new(O.Found.ar(sk), O.OpsLINEAR{},
    [O.Found.i(p0), O.Found.i(bf), O.Found.i(c3), O.Found.i(c4), O.Found.i(rg), O.Found.i(ix0),
      O.Found.i(ix1), O.Found.i(lt), O.Found.i(fi), O.Found.i(st), O.Found.i(ed),
      O.Found.i(en), O.Found.i(sk)], O.ANone{}, O.TNone{})
```

The `src` is **thirteen hand-written `O.Found.i(...)` references**, and the shape const is
not among them.

---

## 3. WHAT `i1` IS, AND WHO FEEDS IT

`i1` is on **both** sides as row 1, byte-identical:

```
2:i1 5:CONST 7:weakint 2:() 2:i0 1:N 5:l0:16 3:n()
```

— `CONST weakint ()`, `arg` = the i64 dim `l0:16`, no src. It is the **element count 16**,
minted by `_storage` as `src[0]` (`.agents/slop/graphcmp.py:1089-1091`):

```python
  from tinygrad.uop.ops import ParamArg
  return UOp(op, src=(UOp(Ops.STACK),) if size is None else (UOp.const(size),),
             arg=ParamArg(slot, dtype, **arg))
```

MEASURED, both sides name it in exactly two places:

```
who cites i1 py   : ['2:i2', '2:i3']      # PARAM and BUFFER
who cites i1 bend : ['2:i2', '2:i3']
```

The port mints it in the same place, inside `UOp.new.param` (`tinybendygrad/uop/ops.bend:3036-3038`):

```
def UOp.new.param(+ar: Arena, +op: Op, n: Maybe<&2, U32>, arg: Arg, tag: Tag) -> Found:
  +f = shape_to_shape_arg.of(ar, ar, n)
  UOp.new(Found.ar(f), op, [Found.i(f)], arg, tag)
```

with `shape_to_shape_arg.of` (`:2997-3000`) returning `UOp.const(made, CInt{H.i64_of_i32(k)})`
for `Some{k}`.

**So `i1` is not missing from the port. It is present, shared by `i2` and `i3`, and reachable.
The port's `LINEAR` simply does not name it as a direct child.**

## 4. WHY CPython NAMES IT AND THE PORT CANNOT

CPython's `src` is `tuple(lines)`, and `lines` comes from `linearize`
(`tinygrad/codegen/late/linearizer.py:8-11`):

```python
def linearize(sink:UOp) -> list[UOp]:
  # this is a toposort with priority
  lst = list(sink.toposort())
```

`sink.toposort()` walks `src`, and `i1` **is** a src (of `i2` and `i3`), so it is in `lst`;
`line_rewrite` (`tinygrad/codegen/__init__.py:411-417`) maps every element of `lst` to itself
unless a rule fires, so `i1` survives into `lines` as a **top-level line**. The two gated-store
rules add `IF` and `ENDIF`: 12 toposorted nodes + 2 = **14**, which is the `i1..i14` of the py
canonical file.

The port has **no `linearize` and no `line_rewrite`** — `grep -n "linearize\|line_rewrite"
.agents/slop/graphcmp.bend` returns three hits and **all three are comments** (`:772`, `:970`,
`:1083`). So `g_gate` cannot compute the list; it spells it out. And it cannot name `i1`,
because `UOp.new.param` interns the shape const internally and returns only the **PARAM's**
`Found` — the const's `Found` is consumed at `ops.bend:3037-3038` and never handed back.

## 5. ROOT CAUSE, WITH THE MEASUREMENT THAT NAMES IT

`graphcmp.py:1068-1091`, on the same function:

```
  """THE ONLY WAY THIS FILE MINTS A `BUFFER`/`ALLOC`/`PARAM` BY HAND, and it is here
  because the re-vendor of 2026-10-17 made the obvious spelling a SILENT WRONG ANSWER.

  Upstream `72f98ffe0` DELETED `size` from `ParamArg` and moved the element count to
  `src[0]`. A hand-written `UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.float, 16,
  ...
  where the node HAS a `src`, nothing raises at all and the graph is simply WRONG.
```

**Before that re-vendor a PARAM had `src=()` and there was no shape const at all, so the
SINK's toposort was 12 and `lines` was 12 + IF + ENDIF = 14 nodes that the port could enumerate
as `p0 … sk`. After it there is a 15th node, and CPython picks it up for free because
`linearize` toposorts. The port's literal list did not grow with it.**

The two prose claims in the two files are both stale in the same direction, and they are the
evidence that the list was never revisited:

- `graphcmp.py:1258-1259` — *"MEASURED at **13 nodes** under the SINK: PARAM BUFFER CONST
  CONST RANGE INDEX INDEX CMPLT IF STORE ENDIF END SINK."* That enumeration is **13 items and
  has no shape CONST**. `sink.toposort()` today is **12** (the 13th, `ENDIF`, is unreachable
  from the SINK — nothing points at it), and `lines` is **14**.
- `graphcmp.bend:1083` — *"FOURTEEN nodes and the root is the `LINEAR`"*. Fourteen is right
  for CPython's `lines`; the list three lines below it has **thirteen** entries.

## 6. MISSING CASE / DELIBERATE / UNKNOWN

**`MISSING_CASE`.**

- **Not DELIBERATE.** No comment anywhere claims the shape const is excluded, and none
  explains the 13-vs-14. The nearest comment (`graphcmp.bend:1086-1088`) argues the
  *opposite* — that the LINEAR's src list is load-bearing and must hold every line:
  > *"The LINEAR's src list is the only thing holding every line, so it is also the only root
  > that reaches ENDIF — and it makes the root's `src` field the PROGRAM ORDER of the kernel,
  > which no other graph in the corpus has."*
- **Not UNKNOWN.** The cause is readable off the source in three hops (§4) and dated by
  `_storage`'s own docstring (§5). No measurement is missing; nothing here needed a run.
- **The corpus itself expects AGREE.** `graphcmp.py:200-206`: *"`sym` is AGREE now and
  `graphcmp-run.sh`'s `$WANT` asserts it. **Every other graph here is AGREE.**"* — `gate` is
  therefore a recorded DISAGREE (`D1-graph-gate.txt` → `# VERDICT: DISAGREE`) with no
  expectation to move it.

## 7. WHAT A FIX WOULD REQUIRE, AND WHAT WOULD VERIFY IT — NOT RUN

The fix is in the FIXTURE, `.agents/slop/graphcmp.bend:1108-1111`, not in the port library:
`g_gate` must name the shape const. `shape_to_shape_arg.of` already returns it
(`ops.bend:2997-3000`), and it must be interned **once** and shared, because CPython's
`UOp.const(16)` is one node for both the PARAM and the BUFFER (`i1` is cited by `i2` and `i3`,
not by `i1` and `i2'`). Two shapes of the change, both inside `g_gate`:

1. capture the const and build the two storages on it directly —
   `+sh = O.shape_to_shape_arg.of(ar, ar, Some{16})` then `O.UOp.new(O.Found.ar(sh),
   O.OpsPARAM{}, [O.Found.i(sh)], ...)` and likewise for the BUFFER, prepending
   `O.Found.i(sh)` to the LINEAR's list. This inlines the two-line idiom `UOp.new.param`
   already is (`ops.bend:3036-3038`), so it does not create a second way to build a PARAM.
2. or add a `linearize`-shaped helper to the corpus driver that derives the LINEAR `src` from
   the arena, so no hand-written list can fall behind the toposort again.

Option 2 is the one that removes the class; option 1 fixes this instance. **I did not
evaluate either, and I edited nothing.**

**Verification, all of it a run and none of it done here:**

| check | what would settle it |
|---|---|
| `emit --side py/bend --graph gate`, then `diff` the two canonical files | 15 rows each and the pair **byte-identical** — that is the `D2-cmp-gate.txt` step (`checks/differ.py:600-617`), whose pass arm is `f"{g} BYTE-IDENTICAL ({len(py)} bytes both sides)"` |
| the run summary | `byte-identical` must move 20 → **21 of 34**, and `graphs-disagree` 2 → **1 of 34** |
| the op census | must **not move**: 12 distinct ops, `CONST=3` on both sides. A `CONST=4` would mean the fix minted a second const instead of sharing one |
| `i1`'s parents | `i1` must still be cited by exactly `i2` and `i3` — two parents, not three |
| the whole corpus | 34 graphs, `graphs-agree` 31 → **32**, with `lin` still the other DISAGREE |

**A `SKIP IS NOT PASS`, and neither of these was run, so both are `DEAD` here, not green.**

## 8. LIMITS OF THIS REPORT

- `lin` is the **other** DISAGREE and is **not** this defect: `D2-cmp-lin.txt` reads
  `9,50c9,49` — a 41-vs-42-node divergence with `AFTER`, a second `RANGE`, `ADD`, `CAST`,
  `LOAD` and `MUL` all moving. It is a different subject and I did not diagnose it. Do not
  carry anything from §3–§5 over to it.
- `loop`'s refusal is out of scope and **UNREAD**: at `17:31Z` `D1-graph-loop.txt` carried no
  `VERDICT:` line and the run was mid-flight. I assert nothing about it.
- `checks/both-rows-gate-{py,bend}.rows` exist in this tree and **do not describe this run**:
  14 rows, no shape-const node, `LINEAR` `src = n(i1,...,i13)` with 13 children, and the two
  sides byte-identical. That is the PRE-re-vendor shape of §5. Anyone reading them for `gate`
  is reading a stale artifact.
- The 17:26Z run's own summary is internally mixed: `selfcheck=# SELFCHECK: OK` and
  `controls=5 of 5` green, but `oracle-selfcheck=# ORACLE SELFCHECK: FAIL` and `census-rc=rc=1`,
  and `substrate-start=9528bb…` ≠ `substrate-end=a842e8…` — **the tree changed under that run's
  own substrate pin.** None of that bears on `gate`, and none of it was investigated.