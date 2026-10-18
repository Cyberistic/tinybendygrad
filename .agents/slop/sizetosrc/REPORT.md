# size -> src[0]: the `ParamArg` migration, measured

Scope note: this report is the deliverable; `.agents/TODO.md` was not edited (brief).

## 0. WHAT I FOUND BEFORE CHANGING ANYTHING, AND IT CORRECTED THE BRIEF TWICE

**THE BRIEF DESCRIBES HEAD, NOT THE TREE I WAS HANDED.** `git show HEAD:tinybendygrad/uop/ops.bend`
has the THIRTEEN-field record with `size` third, exactly as the brief says. The WORKING COPY
already had the twelve-field record. That migration was **uncommitted and unstaged** -- a
previous unit left it in the working tree and did not commit it. MEASURED:

```
$ git show HEAD:tinybendygrad/uop/ops.bend | sed -n '869,876p'
type ParamArg is Data:
  ParamArg{slot: U32, dtype: S.Dt,
    # number of elements in the buffer. always a concrete int (never symbolic), None for scalars (shape ())
    size: Maybe<&2, U32>,
    vmin_vmax: Maybe<&2, PyRange>,
```

and `shape_to_shape_arg` / `param_src` are **absent from HEAD** (`grep -c` = 0 each), so they
arrived with the same uncommitted change.

**CONSEQUENCE, AND IT SETS THE SCOPE.** A partial commit is a build break, not a partial
result: committing only my own edits would leave `ops.bend` at 12 fields and `mxw_buf` at
HEAD's 13-field `ParamArg`. So the commit is the WHOLE migration: 33 files.

## 1. THE OLD RECORD AND THE NEW ONE, FIELD BY FIELD

HEAD (13 fields, `git show HEAD:tinybendygrad/uop/ops.bend:869-884`) vs now (12):

| # | HEAD | now |
|---|---|---|
| 1 | slot | slot |
| 2 | **size** | **vmin_vmax** |
| 3 | vmin_vmax | multiple_of |
| 4 | multiple_of | name |
| 5 | name | addrspace |
| 6 | addrspace | device |
| 7 | device | volatile |
| 8 | volatile | image |
| 9 | image | buffer |
| 10 | buffer | bind_on_realize |
| 11 | bind_on_realize | val |
| 12 | val | **(absent)** |
| 13 | -- | -- |

Upstream is 13 (`git show upstream:tinygrad/uop/ops.py:24-40`): `slot, dtype, vmin_vmax,
multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val, spec`.
**The one field still missing on both sides is `spec`** (`BufferSpec`, upstream ops.py:39).

Read out at run time by the untouched instrument, not by a hand list
(`gates/paramarg-shape-gate.py`, `port_fields()`/`upstream_fields()`):

```
port fields (12)=slot,dtype,vmin_vmax,multiple_of,name,addrspace,device,volatile,image,buffer,bind_on_realize,val
upstream fields (13)=slot,dtype,vmin_vmax,multiple_of,name,addrspace,device,volatile,image,buffer,bind_on_realize,val,spec
DIVERGE index=12 port=- upstream=spec
```

## 2. `shape_to_shape_arg` -- BODY, TWO CASES, AND PROOF

Upstream, read not remembered (`git show upstream:tinygrad/uop/ops.py:103-107`):

```python
def shape_to_shape_arg(arg:tuple[sint, ...]) -> UOp:
  src = tuple(x if isinstance(x, UOp) else UOp.const(x) for x in arg)
  for x in src:
    if not dtypes.is_int(x.dtype): raise RuntimeError(...)
  return src[0] if len(src) == 1 else UOp(Ops.STACK, src=src)
```

The port's (`tinybendygrad/uop/ops.bend:2997-3003`, inherited, correct):

```bend
def shape_to_shape_arg.of(+ar: Arena, +made: Arena, n: Maybe<&2, U32>) -> Found:
  match n:
    case Some{k}: UOp.const(made, CInt{H.i64_of_i32(k)})
    case None{}: UOp.new(made, OpsSTACK{}, Nil{}, ANone{}, TNone{})

def shape_to_shape_arg(+ar: Arena, n: Maybe<&2, U32>) -> U32:
  Found.i(shape_to_shape_arg.of(ar, ar, n))
```

`Some{k}` is upstream's 1-tuple (which becomes that element itself); `None{}` is upstream's
EMPTY tuple (which becomes `UOp(Ops.STACK)` with no src) -- the `shape ()` scalar case.

### 2a. THE DEFECT THE MOVE LEFT BEHIND, MEASURED

`shape_to_shape_arg.of` returns a `Found` -- arena AND index. `shape_to_shape_arg` keeps only
the index and **discards the arena**. An `Arena` is an immutable `Data` value
(`ops.bend:1255`), so a caller doing `UOp.new(ar, K, param_src(ar, n), ...)` interns the size
node into a throwaway arena and then interns the node into an arena where that index names
nothing. `Arena.src(ar, i, 0)` answers `Maybe.default(..., 0)` (`ops.bend:1369`), so there is
no error -- the node ends up pointing at **itself**.

MEASURED, both spellings on one BUFFER (`.agents/slop/sizetosrc/paramsrc_probe.bend`):

```
idiom_Some12    nsrc=1 next=2 op=BUFFER src0=1 src0_op=BUFFER src0_nsrc=1 size=N
idiom_None      nsrc=1 next=2 op=BUFFER src0=1 src0_op=BUFFER src0_nsrc=1 size=N
threaded_Some12 nsrc=1 next=3 op=BUFFER src0=1 src0_op=CONST  src0_nsrc=0 size=12
threaded_Some0  nsrc=1 next=3 op=BUFFER src0=1 src0_op=CONST  src0_nsrc=0 size=0
threaded_None   nsrc=1 next=3 op=BUFFER src0=1 src0_op=STACK  src0_nsrc=0 size=N
mxw_buf         nsrc=1 next=2 op=BUFFER src0=1 src0_op=BUFFER src0_nsrc=1 size=N
```

`next=2` says the size CONST was never interned. `src0_op=BUFFER` says the BUFFER is its own
parent. `mxw_buf` is `mixin/movement.bend:1229`, the port's own bottom-of-every-graph
builder -- **not a fixture** -- and it measured broken. That self-loop is why `F.Kahn.settled`
goes false and `rows.of` emits nothing.

THE FIX, one new def in `ops.bend`, which reuses `shape_to_shape_arg.of`'s `Found`:

```bend
def UOp.new.param(+ar: Arena, +op: Op, n: Maybe<&2, U32>, arg: Arg, tag: Tag) -> Found:
  +f = shape_to_shape_arg.of(ar, ar, n)
  UOp.new(Found.ar(f), op, [Found.i(f)], arg, tag)
```

## 3. THE SITE COUNT

Arity census over the WHOLE tree, git-tracked files only
(`.venv/bin/python .agents/slop/sizetosrc/census.py`):

| arity | sites | files |
|---|---|---|
| **12 (migrated)** | **104** | 33 |
| 13 (un-migrated) | 101 | 22 |

**Of the 101 arity-13 sites, ZERO are in `tinybendygrad/`.** Every one is in `.agents/slop/`
archives (`sched-fixture` 39, `argowner/*` 20, `linfix` 7, `strays/*` 18, `rf2root` 2,
`speccite` 3, `twopass` 1, `symh` 1) or in a gate driver (`realize_graph_census` 4,
`fold_graph_census` 2, `ops-core` 1, `sym_graph_census` 1, `wk-eval` 1).

Node-construction census, same run:

| class | sites | files |
|---|---|---|
| `new.param` (migrated, correct) | **52** | 3 |
| `param_src` (**SELF-LOOP**, measured) | 62 | 17 |
| `Nil{}` (no size node) | 207 | 31 |
| explicit src list | 68 | ~14 |
| **total** | **389** | |

The 52 migrated: `.agents/slop/graphcmp.bend` 50, `gates/paramarg_shape.bend` 1,
`examples/beautiful_mnist.bend` 1.

### THE `*-mut.bend` FILES (the brief's question), ANSWERED

They are **untracked mutation-harness scratch**, not generated siblings:

* NOT in HEAD -- `git cat-file -e HEAD:<path>` fails for `dtype-mut.bend`,
  `realize-mut.bend`, `.linearizer-mut.bend`.
* Written by `gates/*-mutate.py`: `gates/decomp_graph_census-mutate.py:80-81`
  `MUT_PORT = PORT.with_name("dtype-mut.bend")`.
* They mirror their sibling's site count because a harness **COPIES** the file
  (`dtype.bend` 3072 lines / `dtype-mut.bend` 3072 lines, 6 differing lines).
* Both existing instruments already exclude them: `gates/paramarg-shape-gate.py:95,147`
  (`f.endswith("-mut.bend")`) and `gates/allcopies-census.py`'s R1 rule, which intersects
  `os.walk` with `git ls-tree -r HEAD`.

**So they do not move with a generator and must not be hand-edited.** They are debris the
next harness run overwrites. My census intersects with `git ls-tree -r HEAD` for exactly
this reason, and counts them only under `--all`.

## 4. THE THREE NAMED `ParamArg.size` READERS

| reader | HEAD | now |
|---|---|---|
| `renderer/__init__.bend` | `:122` `O.ParamArg{O.ParamArg.slot(pa), dt, O.ParamArg.size(pa), ...}` | `with_storage.arg` reads **12 fields and no size**; the comment at `:120-123` says why -- the size is `src[0]`, and `with_storage` never rewrites `src`, so a dtype replacement can no longer drop the storage size |
| `schedule/memory.bend` | `:272` `case Some{+pa}: mem_size_of(O.ParamArg.size(pa))` | `:276` `case Some{+pa}: mem_size_of(O.ParamArg.size(ar, self))` -- **takes the arena and the owner index**, because `size` lives in the OWNER's `src[0]` |
| `uop/fold.bend` | `:417` `param_shape.of.img(O.ParamArg.image(pa), O.ParamArg.size(pa))` | `:422` `param_shape.of.img(O.ParamArg.image(pa), size)` -- the size is a **parameter**, supplied by the caller from `src[0]` |

## 7. `size = 0` ON BOTH LANES AFTER THE CHANGE

CPython, from `gates/paramarg-site-gate.py`'s `zero_rows()` (BOTH lanes are CPython there by
design; MEASURED, not transcribed):

```
zeroshape_stack=()                          shape_to_shape_arg(()).as_shape
zeroshape_zero=(0,)                         shape_to_shape_arg((0,)).as_shape
zeroshape_equal=False                       shape_to_shape_arg(()) == shape_to_shape_arg((0,))
zeroshape_one=False                         (0,) == (1,)?
zerobuf_maxnumel_0=0   zerobuf_shape_0=(0,)
zerobuf_maxnumel_1=1   zerobuf_shape_1=(1,)
zerobuf_maxnumel_4=4   zerobuf_shape_4=(4,)
zerobuf_distinct_0_1=False                  UOp._buffer(0,...) is UOp._buffer(1,...)   -> DIFFERENT
zerobuf_distinct_4_6=False                  UOp._buffer(4,...) is UOp._buffer(6,...)   -> DIFFERENT
fail_keyword_raises=TypeError: ParamArg.__init__() got an unexpected keyword argument 'size'
fail_pos_lands=0        fail_pos_is_tuple=False          positional is SILENT and a type violation
fail_delete_same_node=True                  DELETING size = ONE NODE FOR EVERY SIZE
fail_delete_shape=IndexError: tuple index out of range
```

The row NAMES say "distinct" and the VALUES say `False`; `False` here means **not the same
node**, which is the correct answer. The brief read `pa_distinct_0_1=False` as a failure; it
is the pass.

The PORT side, `paramsrc_probe.bend`:

```
threaded_Some0   size=0                      (0,) is its own CONST
reintern_4_4=True  distinct_4_6=True  distinct_0_1=True  distinct_0_none=True
```

**Both lanes agree on all three.** 0 is `(0,)` and distinct from `(1,)` and from `()`;
`f(4) is f(6)` is False on both; `f(4) is f(4)` is True (hash-consing works).

## 5. THE CORPUS, BEFORE AND AFTER, WITH ITS DENOMINATOR

`runs/` is `.gitignore`d (`.gitignore:262 /runs/`, and `git ls-tree -r HEAD -- runs/` = 0
committed entries, `.gitignore:187-190`), so the corpus verdict is generated output and is
recorded here and in the commit message, not in the tree.

**BEFORE** (read from `runs/graphcmp/D/D0-run-summary.txt` before any edit):

```
graphs=34  graphs-answered=34  graphs-unset=0  expect-moved=30
graphs-agree=4  graphs-disagree=29  byte-identical=4  not-comparable=0
substrate-start=8871b71f320e15096a5c69eee2b1ce72b082a962cdad1611757a2a4313a681da
substrate-end  =8871b71f...   (identical)
```

**AND THAT READING WAS ALREADY STALE WHEN I STARTED.** `checks/differ.py`'s substrate digest
over its own eight declared inputs reads `deb3c45b67b0a0c3c89a6ecc86e8375eb15a47468f2aadb19f495f7c5c353cf3`
today, not `8871b71f...`:

```
$ .venv/bin/python -c "import sys;sys.path.insert(0,'checks');import differ;print(differ.substrate_digest())"
deb3c45b67b0a0c3c89a6ecc86e8375eb15a47468f2aadb19f495f7c5c353cf3
```

and worse, **`.agents/slop/graphcmp.bend` did not compile at all** (below), so `agree=4
disagree=29` describes a tree state that no longer existed.

**AFTER** (`checks/differ.py repro`, the gated mode):

```
graphs=34  graphs-answered=34  graphs-unset=0  expect-moved=3
graphs-agree=31  graphs-disagree=2  byte-identical=20  not-comparable=0
stable-pairs=4 of 5  stable-failed=1 of 5  stable-differ=0 of 5
plants-disagree=7 of 7  cross=1 of 1  conflations=4 of 4  controls=5 of 5
selfcheck=# SELFCHECK: OK
oracle-selfcheck=# ORACLE SELFCHECK: FAIL      <- unchanged, pre-existing
census-rc=rc=1                                 <- unchanged, pre-existing
substrate-start=5b8f1f87d4d1cc5069d13f913a1c5c3db987b4c182d0b4aa1e44ac2f02d7e6b0
substrate-end  =5b8f1f87...                    <- identical: no mid-run substrate drift
```

| | BEFORE | AFTER | denominator |
|---|---|---|---|
| **agree** | **4** | **31** | 34 |
| **disagree** | **29** | **2** | 34 |
| byte-identical | 4 | **20** | 34 |
| refused (`loop`, rc=2, not a verdict) | 1 | 1 | 34 |

**27 of the 29 disagreements are gone.** Per-graph, read out of the artefacts:

```
AGREE (31): allred alu binblob bit buffer bw cast cdiv commute custom_function flip
            getaddr group indexed late lin?--NO-- matmul move mstack mselect mulacc
            range rangeflate reduce sink special stage sym threefry unshard where wmma
DISAGREE (2): gate  lin
NO VERDICT (1): loop  (rc=2, NOT-WELL-POSED)
```

### THE TWO THAT REMAIN ARE NOT SIZE DEFECTS

* **`gate`** -- `LINEAR py#15 vs bend#15`: CPython carries **14** srcs, the port carries
  **13**, and the missing one is the FIRST (`py=[...,'07be746d', ...]` vs
  `bend=['8b07055a', ...]`). A LINEAR arity defect.
* **`lin`** -- a cascade rooted in one tag: `SINK py#50 vs bend#49` differs in
  `tag py=N bend=i1`, and every rung-2 `MISMATCH` below it is a `src` core difference
  downstream of it.
* **`loop`** -- unchanged and **not** a symptom of this migration, contrary to the brief. The
  refusal names the DEVICE LIST and no size content at all:
  `# devices py=['N','sCPU'] bend=['sCPU'] -- NOT WELL-POSED ... the port's graph fixture is
  pinned at the arena tag 0 and the py graph is on ['N','sCPU']`. It is a fixture/device
  question. **It was REFUSED before my change and is REFUSED now.**

### WHAT I DID NOT GET: THE REPRODUCIBILITY VERDICT

**I did not complete the two-run byte comparison, and I am not going to quote the number that
is on disk.** `runs/graphcmp/D/D0-repro.txt` reads `repro-files=242 / repro-identical=242 /
repro-rc=rc=0`, and it is tempting -- but it is dated **Oct 17 01:50** and is HEAD's file, from
the previous unit's run on the OLD substrate. `git diff HEAD -- runs/graphcmp/D/D0-repro.txt`
is empty. The `repro` wrapper was killed by its own 600 s timeout while the second pass was
still going (`bun` processes still live at 23 s elapsed when I last looked).

**What I have is ONE complete run**, and it is internally consistent: `answered=34`,
`unset=0`, `substrate-start == substrate-end`. A second unit should re-run
`checks/differ.py repro` to completion in the background and record its own verdict.

## 6. THE GATES, MEASURED AND NOT EDITED

`gates/paramarg-shape-gate.py` and `gates/paramarg-site-gate.py` are read-only for me. The
`.bend` DRIVERS are not instruments -- they are inputs, and `gates/paramarg_shape.bend` could
not compile against the migrated record, so the gate was REFUSED rather than red.

| | before | after |
|---|---|---|
| `paramarg-shape-gate` verdict | **REFUSED** (rc=3), `bend said: SOME PROOFS FAIL / expected : a ParamArg with 12 fields` | **FAIL** (rc=1) |
| its two lanes | never produced | **BYTE-IDENTICAL** -- `cmp gates/artifacts/paramarg-shape-gate/bd.out .../py.rows` rc=0, all 6 rows including `nsrc=1` |
| `paramarg-site-gate` | `FAIL: KEYWORD-DEAD=1 POS-SHIFT=21 SAFE=15` | **UNCHANGED** (see below) |

`paramarg-site-gate` cannot move: `walk_py()` walks **`.py` files**, so its 37 sites are the
CPython lane (`gates/.wgsl-mut-oracle.py:321`, `checks/.tmp-tc_ptx_render-oracle.py:149`, ...)
and **not one `.bend` construction is in its population**. The brief's "that gate reads
POS-SHIFT=21 because Bend accepts a 13-argument positional construction" is not what this
instrument measures.