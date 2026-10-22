# THE METADATA LANE -- tensor.py:567-589, and the three markers that named it

The unit's slice was `tinybendygrad/tensor.bend`'s metadata lane: `_ContextVar`
(the marker said `tensor.py:570`), `_metadata_wrapper` (`:578`) and "the TRACEMETA
loop" (`:588`). This file is the measurement behind that port. It is NOT a gate:
the tree has 297 of those and it did not need another one. The port's own rows
live in `tinybendygrad/tensor.bend` and the tree's own gate compares them.

## THE MARKERS, READ AT THE PIN `5c2bf39d6c4b`

The vendored `tinygrad/` IS that revision -- `git hash-object tinygrad/tensor.py`
and `git rev-parse 5c2bf39d6c4b:tinygrad/tensor.py` are the same blob
(`57ad1915a7585169eefa2356136bde9ab46b491d`) -- so the pin's lines are the lines
in the tree, and no other revision is in play.

| the marker said | the pin's line IS | the right anchor | verdict |
| --- | --- | --- | --- |
| `tensor.py:570 _ContextVar` | `def get(self) -> T: return self.state` | the CLASS is at **568** | NAME RIGHT, LINE TWO LATE |
| `tensor.py:578 _metadata_wrapper` | `if TRACEMETA < 1 or _METADATA.get() is not None: return fn(*args, **kwargs)` | the DEF is at **576** | NAME RIGHT, LINE TWO LATE |
| `tensor.py:588 the TRACEMETA loop` | `if name in ["__class__", "__del__", "__init__", "__new__", "__repr__", "backward", "sequential", "gradient"]: continue` | the loop's HEAD is at **586** | NAME RIGHT, LINE TWO LATE |
| `tensor.py:553 decode_hevc_frame` | `Creates a Tensor by decoding an HEVC frame chunk.` (a DOCSTRING line) | the DEF is at **551** | NAME RIGHT, LINE TWO LATE |
| `tensor.py:73 UOp.const` | `elif isinstance(data, get_args(ConstType)):` | the `UOp.const(0.0, _dtype)` is at **72** | NAME RIGHT, LINE TWO LATE |
| `tensor.py:74 a float ConstType` | `data = UOp.const(data, _dtype)` | the `elif` is at **73** | NAME RIGHT, LINE TWO LATE |
| `tensor.py:107 all_metadata` | `# directly create the Tensor` | the writer is at **106** | NAME RIGHT, LINE ONE LATE |

**THE DRIFT IS A UNIFORM `+2` FOR THE METADATA LANE AND `+1` FOR THE `:106`
WRITER**, and every FUNCTION NAME in every marker is RIGHT. So the block was
written against a `tensor.py` two lines shorter above 568, and the port's own
text ("tensor.py:570-591") has the same drift.

**AND THE PORT'S TEXT ABOUT THE SUBSTRATE WAS WRONG IN A DIFFERENT WAY:** the
`:107` marker said the metadata is "the `Maybe<&2, Metadata>` ops.bend already
carries on a `Found` (ops.bend:1996)". IT DOES NOT: `ops.bend`'s `Found` is
`Found{ar: Arena, i: U32}` -- two fields, no metadata -- at HEAD and in the
working copy alike. `ops.bend:1996` is `eq_pynest.CBool`, which is nothing to do
with metadata. The reader that DOES exist is `O.UOp.metadata`, which takes the
`Maybe` AS AN ARGUMENT and returns it.

## THE PORT

`tinybendygrad/tensor.bend` gains the lane as three types and eleven defs:

* `MetaCell` -- upstream's `_ContextVar` is a MUTABLE class with one field, and
  Bend has no mutable class state, so the cell is a VALUE (the `Tensors` idiom
  of WALL 1, applied to a module global). `tn_meta_get` is `:570`.
* `MetaSwap` -- `_ContextVar.set` RETURNS THE OLD STATE, and that return is the
  token the wrapper restores at `:582`, so the port's `set` returns it too.
* `MetaScope` -- the wrapper. Bend has no CLOSURE, so the wrapper is the SCOPE
  and the CALL is the caller's; what the wrapper DECIDES (the guard, the
  install, the token, the restore) is all here.
* `tn_meta_skip` -- the reflection loop's portable content: the eight names
  upstream's own literal skips. `__init__` is in it, and that is why a plain
  `Tensor(5)` carries no metadata.
* `tn_meta_carries` -- what a tensor built by a given method carries.

## THE THIRTEEN SHARED ROWS, AND THE EDGES

The CPython lane asks the REAL `_ContextVar` and the REAL `_metadata_wrapper`
(`tinygrad/tensor.py` at the pin). `TRACEMETA` DEFAULTS TO 1
(`tinygrad/helpers.py:240`), so the reflection loop at `:586` RAN AT IMPORT
TIME and the machinery is live in the default configuration.

| row | the edge | CPython | the port |
| --- | --- | --- | --- |
| `tn_meta_rest` | NO METADATA SET, and a cell explicitly set to `None` | `none` | `none` |
| `tn_meta_set_old` | the FIRST set's old value | `none` | `none` |
| `tn_meta_set_now` | the state after it | `a` | `a` |
| `tn_meta_set2_old` | SET TWICE: the SECOND set returns the FIRST's state | `a` | `a` |
| `tn_meta_set2_now` | the state after it | `b` | `b` |
| `tn_meta_enter` | the wrapper at rest INSTALLS the method's name | `alu` | `alu` |
| `tn_meta_enter_set` | a metadata ALREADY in effect is NOT overwritten (the OUTER name wins) | `outer` | `outer` |
| `tn_meta_enter_empty` | **SET TO AN EMPTY VALUE**: the empty name SURVIVES | `` (empty) | `` (empty) |
| `tn_meta_enter_tm0` | `TRACEMETA < 1`: the guard's FIRST term | `none` | `none` |
| `tn_meta_exit` | the RESTORE to the token | `none` | `none` |
| `tn_meta_never` | **A TENSOR THAT NEVER HAD IT** (`__init__` is skipped) | `none` | `none` |
| `tn_meta_excl` | is `__init__` skipped? | `True` | `True` |
| `tn_meta_excl2` | is `alu` skipped? | `False` | `False` |

and ONE Bend-only row, `tn_meta_isolated`: upstream's cell is ONE MODULE
GLOBAL, so there is only ever one lane there; the port's cell is a VALUE, so
two lanes are two cells and one lane's state cannot leak into another's. The
gate's exclusion list names it, so the exclusion is visible on BOTH sides.

## THE PLANT, AND IT IS `plant.py`

`python .agents/slop/metagate/plant.py` applies each named failure mode to the
SCRATCH copy of `tinybendygrad/tensor.bend`, compiles it, and diffs the rows.
The real file is never edited. MEASURED, and every arm moves a row:

| arm | the edit | the rows that MOVED |
| --- | --- | --- |
| P1 -- an EMPTY-NAMED metadata read as ABSENT (the sentinel mistake) | `tn_meta_is_set` treats an empty name as not-set | `tn_meta_enter_empty` `""` -> `"inner"` |
| P2 -- the ContextVar READ returns a DEFAULT | `tn_meta_get` answers a default when the cell is absent | `tn_meta_rest` `tn_meta_enter` `tn_meta_enter_tm0` `tn_meta_isolated` |
| P3 -- a metadata KEY silently renamed | the row's method name `alu` -> `alu_v2` | `tn_meta_enter` `"alu"` -> `"alu_v2"` |
| P4 -- the installed metadata SURVIVES the call | the token is the EFFECT | `tn_meta_exit` `"none"` -> `"alu"` |

**P1 IS THE ARM NOBODY PLANTS AND IT IS THE ONE THAT BITES:** the port's absent
state and an empty-named metadata are DIFFERENT states, and the row that says so
is `tn_meta_enter_empty`.

**THE FIFTH ARM IS A TYPE ERROR, AND THAT IS THE PLANT:** the lane's value type
is `Maybe<&2, O.Metadata>`, so a LIST, a DICT or a TENSOR is refused by the
compiler. `sh .agents/slop/metagate/refuse-nonmetadata.bend` is the refusal,
measured: `expected : O.Metadata / observed : List`, rc=1. **CPython's lane is
dynamically typed and accepts all three** (MEASURED: a list, a dict and a
Tensor are all stored verbatim in `all_metadata`, and only `None` is special,
because `None` means ABSENT and the wrapper then installs). So this refusal is a
DIVERGENCE, and it is the port's answer: the type forbids what upstream's own
annotation forbids (`_METADATA: _ContextVar[Metadata|None]`).

## WHAT WAS FOUND AND NOT DONE

* **THE TREE'S CPYTHON LANE WAS RED AT REST, AND IT WAS NOT THE METADATA LANE.**
  `.agents/slop/tensor-gate.py` died at `tn_mop_flip` with `AttributeError:
  type object 'Ops' has no attribute 'FLIP'` -- `Ops.FLIP` does not exist at the
  pin -- so it printed ELEVEN rows and stopped, and every row after that one was
  UNMEASURED. Deleting that one line made the lane run to the end.
* **THREE ROWS THE CPYTHON LANE NEVER GAINED** are the gate's remaining red:
  `tn_asparam`, `tn_bwd_row` and `tn_bwd_grad`. They are the `as_param` and the
  `backward` spine's rows, they are a different slice's work, and they were
  absent from the lane before this unit arrived.
* **THE `:106` WRITER IS STILL A WALL.** `all_metadata[new_uop] = (metadata,)`
  needs a scope threaded through `_apply_uop`, and the lane now SUPPLIES that
  scope -- but threading it through every method is the next slice's job, not
  this one's. The port's `tn_meta_carries` is the lane's answer for the tensor,
  computed where the writer would record it.
* **`decode_hevc_frame` (`:551`) WAS NOT PORTED.** It needs `Variable.unbound`
  (`ops.py`'s `Variable` and its `is_bound_var`), `Ops.CUSTOM_FUNCTION`,
  `UOp.custom_function` and `fn.call(...)` -- an encoder/decoder call graph --
  and `Tensor.empty` and `Tensor.contiguous` on top. That is a video decoder,
  it is a separate job, and the marker stays.
* **`tensor.py:72/74` WERE NOT PORTED.** `UOp.const(0.0, _dtype)` needs an `F32`
  LITERAL, and `F32` is `F32{data: Word(32n)}` with `Word` not exported and
  `U32.to_f32` an unfilled LAW -- so the port has no float const at all. The
  `elif isinstance(data, get_args(ConstType)):` arm needs a `ConstType` test
  over a Python dynamic type, which is `isinstance`, and the port's `Const` is
  an enum with three cases, so the arm is an enum dispatch rather than a
  dynamic one. The markers stay.
