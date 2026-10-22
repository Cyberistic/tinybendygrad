# `nn/item.bend` -- `Tensor.item()` PORTED, AND THE ONE THING THAT IS NOT

**MEASURED** 2026-10-22 05:00-05:02Z (UTC).
**HEAD** `35e6aa986c0b2a04de0227ac52b05c5b037b5acd` (2026-10-22 08:03 local). The tree MOVED FOUR TIMES during this unit (`0383a5579` -> `4d0f29cb3` -> `5bcef37da6` -> `35e6aa98`); the substrate copy the rows were run against is `git archive 35e6aa98 tinybendygrad` and the check was RE-RUN against it after the last move. Every HEAD named above was a real substrate the rows were verified on.
**TOOLS** `bin/bend` (the pinned `references/bend` at `v2.0.37`; the compiler prints "bend 2.0.38 is available") and `.venv/bin/python` (3.12.10) with this repo's own `tinygrad` on `sys.path`.
**FILES** `tinybendygrad/nn/item.bend` (the implementation + the rows), `.agents/slop/nnitem/probe.bend` (the probe), `.agents/slop/nnitem/probe.out` (captured), `.agents/slop/nnitem/probe_native.out` (the native lane), `.agents/slop/nnitem/control_a.out`, `.agents/slop/nnitem/control_b.out`, `.agents/slop/nnitem/rows.rows`.

---

## 1. UPSTREAM'S CONTRACT, QUOTED

`tinygrad/mixin/op.py:22-32`:

```python
  def item(self) -> PyConst:
    """
    Returns the value of this tensor as a standard Python number.
    ...
    """
    assert self.numel() == 1, "must have one element for item"      # :31
    return self.data()[(0,) * len(self.shape)]                        # :32
```

Three things are in that, and they are three DIFFERENT requirements:

| # | requirement | upstream |
|---|---|---|
| 1 | **the precondition**: `numel() == 1`, else `AssertionError` | `mixin/op.py:31`; `numel()` is `prod(self.shape)` at `mixin/movement.py:38-46` |
| 2 | **the read**: a realized device buffer, copied to the host, reinterpreted through the dtype's `fmt` | `tensor.py:285-301` (`data()`), `tensor.py:274-283` (`_buffer()`) |
| 3 | **the index**: the first element, which in a one-element tensor is the only element | `mixin/op.py:32` |

`data()` is where the dtype's BYTE WIDTH and the WEAK-DTYPE COMMIT live:

```python
  def data(self) -> memoryview:                                      # tensor.py:285
    if self.dtype in dtypes.weaks: return self.cast(self.commit_dtype()).data()   # :294
    ...
    return buf.as_memoryview().cast(fmt, self.shape)                  # :301
```

`fmt` is the struct code for the dtype, so `cast(fmt, shape)` reads `dtype.itemsize` BYTES per element -- `tinygrad/dtype.py:63`, `def itemsize(self) -> int: return (self.bitsize + 7) // 8`. And `commit_dtype` (`tinygrad/mixin/dtype.py:16-17`) is what turns a weak dtype into a concrete one: `commit_int(vmin, vmax, default_int)` (`tinygrad/dtype.py:171-174`) for a weakint, `strong_dtype(dtype)` for a weakfloat.

**THE PARAGRAPH.** In Bend terms `item` must (a) read the tensor's shape from the fold, multiply its dims, and REFUSE with upstream's own literal `"must have one element for item"` unless that product is exactly one, because upstream's `assert` is the FIRST line of `item` and `data()` is never reached otherwise; (b) then READ THE ONE SCALAR, which upstream does by realizing a contiguous buffer, copying it to the host, and reinterpreting its bytes through the dtype's format -- so the port needs a live allocated buffer, a device-to-host copy, and the dtype's byte width, and it must commit a weak dtype to its `commit_dtype()` before the read; and (c) return the scalar as a Python number. The port has (a) and the dtype half of (b) PORTED, and it has NO WAY to do the buffer half at all: `tinybendygrad/uop/ops.bend:5296` says "NO LIVE `Buffer` -- there is no `type Buffer is Data` anywhere in the port and ZERO `Buffer{` constructors", `tinybendygrad/engine/realize.bend:60` lists `realize.py:145 exec_copy -- allocators, _transfer, host[:]` in the FOREIGN-EFFECT bucket `[b]`, and `tinybendygrad/nn/onnx.bend:49` says it in the port's own words -- "Nothing in this port can read a byte out of a tensor". So the port's `item` reads the value from the ONE place a value exists (a CONST node's `APy{v}` arg, `uop/ops.bend:1197`, whose payload is an `O.Const`, `uop/ops.bend:799-803`) and REFUSES, BY NAME, everywhere else.

## 2. THE PORT'S PRIMITIVES, AND THE THREE THE BRIEF NAMED

| primitive | `file:line` | what it IS |
|---|---|---|
| `Buf.at` | `runtime/ops_python.bend:836` | **NOT a buffer element read.** `def Buf.at(fs: List<&2, Buf>, +b: U32) -> Buf` -- it answers the `b`-th BUFFER IN A LIST OF BUFFERS (the PYTHON backend's kernel-argument binding) and it answers a `Buf`, not a scalar. It is the ONLY `def X.at(` in the whole port whose receiver is `Buf` (`grep -rn "^def [A-Za-z_0-9]*\\.at(" tinybendygrad/`); the other `Buf` receivers are `size`/`id` (`runtime/ops_webgpu.bend:930,939`, `runtime/ops_cl.bend:776,780`) and a renderer's own `Buf` (`renderer/wgsl.bend:707-719`). |
| `Dt.itemsize` | `LAWS/spec.bend:176-181` | **IS what it says**: `(bitsize + 7) // 8`, exactly `tinygrad/dtype.py:63`. |
| `mo_at` | `mixin/op.bend:316-317` | **NOT a tensor index.** `def mo_at(+ds: List<&2, O.Sint>, +t: List<&2, O.Sint>) -> U32: U32.from_nat(List.length(&2, O.Sint, t))` -- it is the INDEX OF A HEAD ELEMENT of a SHAPE, i.e. `enumerate(self.shape)`'s `i`. Its three call sites (`mixin/op.bend:696,779,874`) all pass a SHAPE list. |

What the implementation actually uses:

| primitive | `file:line` | used for |
|---|---|---|
| `M.mo_dims` | `mixin/op.bend:281` | the shape, from the fold |
| `M.mo_dim_u32` | `mixin/op.bend:297` | the dim -> `U32` projection (0 for a SYMBOLIC dim) |
| `H.prod_u32` | `helpers.bend:483` | `prod(shape)` = upstream's `numel()` |
| `M.mo_const_t` | `mixin/op.bend:350` | a CONST node in a tensor's arena |
| `MX.mxw_buf` | `mixin/movement.bend:1231` | a BUFFER node (a fixture, and the port's stand-in for a device buffer) |
| `F.const_i64.go` | `uop/fold.bend:1401` | a CONST's value as an `I64` -- the `vmin`/`vmax` of the commit |
| `MD.md_weak` | `mixin/dtype.bend:121` | `dtype in dtypes.weaks` |
| `MD.commit_dtype` | `mixin/dtype.bend:326-328` | `commit_dtype` (`tinygrad/mixin/dtype.py:16-17`) |
| `S.Dt.itemsize` | `LAWS/spec.bend:176` | the dtype's byte width |
| `H.i64_dec` | `helpers.bend:2178` | `str(int)` |
| `H.f32_show` | `helpers.bend:1027` | the port's float spelling (see the caveat in §5) |
| `F32.bits` | (Base) | the exact float32 bit pattern |

## 3. THE IMPLEMENTATION

`tinybendygrad/nn/item.bend`. The result is a SUM TYPE, not a `Maybe`, because the three outcomes are three different things:

```
type Itm is Data:
  ItmVal{dt: S.Dt, v: O.Const}   # the scalar, read, under the dtype it was read under
  ItmNotOne{n: U32}               # upstream's AssertionError: n elements, not one
  ItmNoRead{at: String}           # the port's wall, named
```

`Itm` and not `Item`: `viz/cli.bend:94` already owns the constructor `Item`, and Bend has ONE constructor namespace across modules.

The ORDER is upstream's order: the precondition is checked FIRST, so a multi-element tensor is an `AssertionError` and NOT a read refusal. **The port does NOT silently return the first element of a multi-element tensor.** It refuses with upstream's own literal.

The dtype is CARRIED because upstream carries it too: `data()` casts a weak dtype to its commit dtype BEFORE the read, so `Tensor(3.5).item()` is a float32 read and `Tensor(7).item()` is an int32 read.

## 4. THE PROBE, AND THE CPython ANSWERS THE `want`s CAME FROM

`probe.bend` calls `nn_item_rows()` and prints the rows. The rows are in the implementation file, in the house style of `nn/layers.bend:971-972`:

```python
def nn_row.line(nm: String, got: String, want: String) -> IO(Unit):
  IO.print(String.concat([nm, " got=", got, " want=", want]))
```

(this file does not IMPORT `layers.bend`: that file is owned by another unit right now, and a file that imports a file being rewritten is a file that breaks when the other unit lands. The line is one line and it is reprinted.)

**THE CPython COMMANDS** (this repo's `.venv`, this repo's `tinygrad`), run 2026-10-22:

```
$ .venv/bin/python -c 'from tinygrad import Tensor, dtypes; ...'
Tensor(3.5).item()        = 3.5          struct.pack('<f', 3.5) bits = 1080033280
dtypes.float32.itemsize   = 4
Tensor(7).item()          = 7            dtypes.int32.itemsize = 4
Tensor(True).item()       = True         dtypes.bool.itemsize   = 1
Tensor([1.0,2.0]).numel() = 2            shape = (2,)
Tensor([1.0,2.0]).item()  -> AssertionError: must have one element for item
Tensor([3.5]).item()      = 3.5          numel = 1   shape = (1,)
```

**THE ROWS** (`.agents/slop/nnitem/rows.rows`, TAB-separated name/got/want; the captured run is `probe.out`):

```
item_f32	3.500000	3.500000
item_f32_bits	1080033280	1080033280
item_f32_size	4	4
item_i32	7	7
item_i32_size	4	4
item_bool	True	True
item_bool_size	1	1
item_multi	AssertionError: must have one element for item	AssertionError: must have one element for item
item_multi_numel	2	2
item_buffer_divergence	NO-READ: no live Buffer in the port (uop/ops.bend:5296); realize.py:145 exec_copy -- the device-to-host _copyout -- is a foreign effect (engine/realize.bend:60 [b])	3.5
```

**WHERE EACH `want` COMES FROM** (none of them is a copy of an observed `got`):

| row | `want` | its source |
|---|---|---|
| `item_f32` | `3.500000` | CPython's `3.5`, spelled by `H.f32_show`, whose DEFINITION (`helpers.bend:1000-1004`) is "an integer-valued float prints as an integer, every other float with SIX decimals". So `3.5` -> `3.500000`. |
| `item_f32_bits` | `1080033280` | CPython's `struct.unpack('<I', struct.pack('<f', 3.5))[0]`. EXACT, and no rounding can move it. |
| `item_f32_size` | `4` | CPython's `dtypes.float32.itemsize`. |
| `item_i32` | `7` | CPython's `str(Tensor(7).item())`. |
| `item_i32_size` | `4` | CPython's `dtypes.int32.itemsize`. |
| `item_bool` | `True` | CPython's `str(Tensor(True).item())`. |
| `item_bool_size` | `1` | CPython's `dtypes.bool.itemsize`. |
| `item_multi` | `AssertionError: must have one element for item` | UPSTREAM'S OWN LITERAL, `tinygrad/mixin/op.py:31`. The port prints it VERBATIM. |
| `item_multi_numel` | `2` | CPython's `Tensor([1.0,2.0]).numel()`. |
| `item_buffer_divergence` | `3.5` | CPython's `Tensor([3.5]).item()`. **THIS IS THE DIVERGENCE AND IT IS RED BY DESIGN.** |

**THE FLOAT SPELLING IS A FINDING, NOT A CHOICE.** `helpers.bend:997` says "The shortest decimal that reads back, the way Python's repr does" and the code under that comment (`helpers.bend:1000-1004`) prints SIX decimals. So the port's float spelling is NOT Python's `repr` (`repr(3.5)` is `"3.5"`, `repr(float32(0.1))` is `"0.10000000149011612"`). The port has no shortest-round-trip float formatter, so the VALUE claim for a float is carried by `item_f32_bits`, which is exact, and `item_f32` pins the port's own spelling on top of it.

## 5. THE DTYPE TABLE

| fixture | upstream (CPython) | the port | MATCH? |
|---|---|---|---|
| **1-element float32** -- `Tensor(3.5)`, a weakfloat const committed to float32 | `3.5`, read under float32, 4 bytes | `3.500000` (and bits `1080033280`), read under float32, 4 bytes | **YES** |
| **1-element int32** -- `Tensor(7)`, a weakint const committed to int32 | `7`, read under int32, 4 bytes | `7`, read under int32, 4 bytes | **YES** |
| **1-element bool** -- `Tensor(True)`, `boolean` is not weak | `True`, 1 byte | `True`, 1 byte | **YES** |
| **multi-element** -- `Tensor([1.0,2.0])`, shape (2,), numel 2 | `AssertionError: must have one element for item` | `AssertionError: must have one element for item` (upstream's literal, verbatim) | **YES** |
| **1-element DEVICE BUFFER** -- `Tensor([3.5])`, a one-element realized buffer | `3.5` -- upstream READS the buffer | `NO-READ: ...` -- the port REFUSES, and names the wall | **NO. THIS IS THE DIVERGENCE.** |

**THE PORT DOES NOT SILENTLY RETURN THE FIRST ELEMENT OF A MULTI-ELEMENT TENSOR.** It refuses with upstream's message, and the `numel` it computed (2) is a row of its own (`item_multi_numel`).

**THE DIVERGENCE, NAMED.** Upstream's `item` on a one-element tensor that is NOT a constant reads the device buffer's bytes. The port has no buffer: `uop/ops.bend:5296` (no `type Buffer is Data` anywhere in the port, zero `Buffer{` constructors), `engine/realize.bend:60` (`realize.py:145 exec_copy -- allocators, _transfer, host[:]` is a FOREIGN EFFECT), `nn/onnx.bend:49` ("Nothing in this port can read a byte out of a tensor"). So the port's `item` is a REAL GAP, not a wrapper: `grep -rnE "read_scalar|to_host|d2h|o2h" tinybendygrad/` finds nothing, and there is nothing under another name either -- the port's `Tensor` is `{ar: Arena, uop: U32}` (`tensor.bend:200-211`), a graph node, with no storage at all.

**THE DOMAIN OF THE PORT'S `item`, STATED PLAINLY:** a one-element CONST tensor is READ; a multi-element tensor is REFUSED with upstream's message; everything else is REFUSED with the wall named. Upstream reads every one-element tensor. The port reads the ones whose value it holds.

## 6. THE CONTROL -- THE ROWS CAN GO RED

Two perturbations, each on a COPY of the implementation in the scratch tree, each run through its own probe:

* **Control A** -- `item_i32`'s want `7` -> `8` (`control_a.out`):
  `item_i32 got=7 want=8` -- RED, and every other row is untouched.
* **Control B** -- `item_f32_bits`'s want `1080033280` -> `1080033288` (`control_b.out`):
  `item_f32_bits got=1080033280 want=1080033288` -- RED, and every other row is untouched.

and the unperturbed run is GREEN again (`probe.out`). The perturbations are reverted by construction: the real `tinybendygrad/nn/item.bend` was never edited.

**THE NATIVE LANE AGREES.** `./bin/bend probe.bend -o probe_native && ./probe_native` prints byte-identical rows to the interpreted lane (`probe_native.out` vs `probe.out`, `diff` clean once the compiler's "bend 2.0.38 is available" banner is excluded).

## 7. THE SUBSTRATE WAS BROKEN, AND WHAT WAS MEASURED

**THE WORKING TREE DID NOT COMPILE DURING THIS UNIT, AND THAT IS NOT MY FILE.** At 04:28-05:00Z, `bin/bend <any file that imports uop/ops.bend> --check-only` failed with errors inside `tinybendygrad/uop/ops.bend`, in another unit's IN-FLIGHT edit (the file's mtime moved every few minutes: 07:25, 07:30, 07:43, 07:49, 07:58 local). The errors MEASURED, in the order they were met:

1. `uop/ops.bend:8960` -- "a match cannot scrutinize a computed value": `match Char.is_digit(c):`. (bend 2.0.37 refuses a CALL in the scrutinee position.)
2. `uop/ops.bend:9056,9061,9083` -- the same class, `match eq_op(Arena.op(ar, u), OpsPARAM{}):` and two more.
3. `uop/ops.bend:8873` -- "a parameter or field scrutinee (pa consumed more than once)" in `fs.pinfo.of`.

I did NOT edit `uop/ops.bend` -- it is not my file and it is another unit's live work.

**WHAT I VERIFIED AGAINST, INSTEAD.** A substrate copy: `git archive 35e6aa986c0b2a04de0227ac52b05c5b037b5acd tinybendygrad` into `.agents/slop/nnitem/scratch/`, plus MY `tinybendygrad/nn/item.bend` copied in. **NO PATCH: the substrate copy is HEAD's tree, byte for byte.** On that copy:

```
$ ./bin/bend .agents/slop/nnitem/scratch/tinybendygrad/nn/item.bend --check-only
ALL PROOFS CHECK
$ ./bin/bend .agents/slop/nnitem/scratch/probe.bend
<the ten rows above>
```

**THE TWO EARLIER HEADs DID NOT COMPILE EITHER, AND THE FIX WAS ANOTHER UNIT'S.** At `0383a5579` the tree failed with "expected : ../uop/fold.Derived with 8 fields / observed : F.Derived{6 args}" -- `uop/fold.bend`'s `Derived` had grown `unbase`/`sbase` and `uop/weak.bend`'s `wk_derived` had not been updated with them. A scratch-only patch (two `0`s) was applied to get past it while I worked; by `4d0f29cb3` another unit had committed the real fix (`uop/weak.bend`'s `wk_derived` now builds all eight fields), so the final substrate needed NO patch at all. The scratch copy I finally ran against is HEAD's tree with NO patch.

**THE PROBE'S IMPORT PATH IS ONE LINE DIFFERENT IN THE SCRATCH.** `.agents/slop/nnitem/probe.bend` imports `../../../tinybendygrad/nn/item.bend` (the REAL tree -- that is the artifact a reader runs once the tree compiles). The scratch copy, `.agents/slop/nnitem/scratch/probe.bend`, imports `./tinybendygrad/nn/item.bend` instead, because the scratch tree IS the substrate copy. One line; both files are in the deliverable.

**THE REAL PROBE'S IMPORT RESOLVES.** MEASURED: `./bin/bend .agents/slop/nnitem/probe.bend --check-only` on the WORKING TREE gets past the import and stops inside the substrate -- "expected : s / observed : s (consumed more than once)" at `uop/ops.bend:8916` (`fs.buf_slot`), the other unit's in-flight edit, and NOT in `nn/item.bend`. So the probe is wired correctly and the only thing between it and ten green rows is the other unit's edit to `uop/ops.bend`.

## 8. WHAT IS LEFT

* `Tensor.item` is now PORTED for the domain the port can express (a one-element CONST), with upstream's precondition and upstream's refusal message, and with the weak-dtype commit and the dtype's byte width.
* The BUFFER read is still the wall, and it is the wall for the whole eval path: `examples/test_pkl_imagenet.bend:176` (the file's `:17` comment) names `p.to('cpu').argmax().item()` as the last step before `hit += y == t`.
* Nothing here was committed. `git` was used only to READ (`rev-parse`, `log`, `show`, `archive`), always with `env -u GIT_INDEX_FILE`.
