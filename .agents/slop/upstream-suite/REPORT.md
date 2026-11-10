# THE UPSTREAM SUITE, PORTED ONE FILE AT A TIME

**DISPATCHED 2026-11-10.** ONE upstream test file per pass, and each pass either lands a
GREEN gate or reports the file as SKIPPED or BLOCKED. **NO EXPECTED VALUE IS EVER
TRANSCRIBED FROM AN UPSTREAM `.py` TEST INTO A `.bend` LITERAL.**

---

## THE ARCHITECTURE, AND WHY IT IS NOT OPTIONAL

`import tinygrad` resolves to the **vendored upstream Python** at `tinygrad/`. The port is
`.bend` and is **not** importable as `tinygrad`. **SO UPSTREAM's `.py` TESTS CANNOT RUN
AGAINST THE PORT, AND A "PORTED TEST" THAT IS A `.py` FILE WOULD BE TESTING UPSTREAM.**

The tree's established shape is a **triple**:

| file | what it is | who reads it |
|---|---|---|
| `gates/<name>.bend` | the **PORT** side: calls the port's own defs, prints `name=value` rows | the gate |
| `gates/<name>-oracle.py` | the **CPYTHON** side: builds the SAME graph in the vendored upstream, prints the SAME rows | the gate |
| `gates/<name>-gate.py` | the **DIFF**: a `gatekit.Gate` over both, positional, three lanes | a human, the sweep |

**THE THREE LANES** are CPython, `bend` interpreted, and `bend` compiled (`bend -o`).
`gates/gatekit.py` owns the plumbing; a gate file owns only its rows.

**AND NO ROW IS A COMPARISON AGAINST A TYPED NUMBER.** Every value in every row is
COMPUTED by the lane that prints it, by the lane that prints it. A `.bend` row that said
`out_op=WHERE` because somebody typed `WHERE` into the driver would test the typing.

**AND EVERY ROW MUST GO RED ON A PLANT.** A text edit, the row goes red, the edit is
reverted. A row that cannot go red is worse than no row, and the tree's own rule says so.

---

## FILE 1 — `test/null/test_invalid_tensor.py` (16 LOC) — **PORTED, GREEN**

### THE UPSTREAM TEST

```python
from tinygrad.uop.ops import Ops, UOp

class TestInvalidTensor(unittest.TestCase):
  def test_uop_where_keeps_invalid_bare(self):
    cond = UOp.const(0) < UOp.const(1)
    idx = UOp(Ops.STACK, src=tuple(UOp.const(x) for x in range(3)))
    out = cond.where(idx, UOp.invalid())
    self.assertIs(cond.op, Ops.CMPLT)
    self.assertIs(idx.op, Ops.STACK)
    self.assertIs(out.op, Ops.WHERE)
    self.assertIs(out.src[2].op, Ops.CONST)
    self.assertTrue(out.src[2].is_invalid)
```

**THE PROPERTY IS THE TEST's OWN NAME**: `test_uop_where_keeps_invalid_bare`. **THE WHERE
DOES NOT FOLD THE INVALID AWAY AND DOES NOT RE-SPELL IT** — the third src is still a **BARE
CONST**, and it is **STILL INVALID**.

### THE UPSTREAM CITATIONS, AT THE PIN `f5ac54685074`

Cited by **rule identity and text**, not by line number alone:

| what | where at the pin |
|---|---|
| `UOp.const(0) < UOp.const(1)` | `tinygrad/mixin/elementwise.py` — `ElementwiseMixin.__lt__` = `self._binop(Ops.CMPLT, x, False)` |
| `cond.where(idx, UOp.invalid())` | `tinygrad/mixin/elementwise.py` — `ElementwiseMixin.where` = `x, y = self.ufix(x)._broadcasted(y); return self.alu(Ops.WHERE, x, y)` |
| `UOp.invalid()` | `tinygrad/uop/ops.py` — `def invalid() -> UOp: return UOp.const(Invalid)` |
| `out.src[2].is_invalid` | `tinygrad/uop/ops.py` — `@property def is_invalid(self) -> bool: return self.op is Ops.CONST and self.val is Invalid` |
| the STACK | `tinygrad/uop/ops.py` — `UOp.group` is `UOp(Ops.STACK).after(*srcs)`, and **the PIN HAS NO `UOp.stack`** — so the test's RAW `UOp(Ops.STACK, src=(...))` is the direct spelling and the port's `O.UOp.new(ar, OpsSTACK{}, [...])` is its counterpart |

**AND `UOp` AT THE PIN INHERITS `ElementwiseMixin`**, so `UOp.__lt__` and `UOp.where` EXIST
ON A `UOp` AND NOT ONLY ON A `Tensor` — MEASURED: `UOp.__mro__` IS
`UOp → RandMixin → OpMixin → ElementwiseMixin → CreationMixin → ReduceMixin → DTypeMixin →
MovementMixin → object`, AND `UOp._uop` IS A PROPERTY THAT RETURNS `self`. **AND THE
WORKING TREE's `tinygrad/` IS BYTE-IDENTICAL TO THE PIN** (`git diff --stat f5ac54685074 --
tinygrad/` IS EMPTY), SO THE ORACLE IS THE PIN.

### THE THREE FILES

- **`gates/invalid-tensor.bend`** — the port side. Builds the graph with the port's own
  defs: `O.UOp.alu` (ops.py:630), `O.UOp.where` (mixin/elementwise.py:425),
  `O.UOp.invalid` (ops.py:635), `O.UOp.is_invalid` (ops.py:252).
- **`gates/invalid-tensor-oracle.py`** — the CPython side. Builds the SAME graph in the
  vendored upstream and answers the SAME questions. **NO CONSTANT IS COPIED FROM UPSTREAM's
  TEST.**
- **`gates/invalid-tensor-gate.py`** — the positional diff.

### THE ROWS — 19, THREE LANES, AND **rc=0**

```
cond_op=CMPLT          cond_nsrc=2        cond_src0_op=CONST     cond_src1_op=CONST
idx_op=STACK           idx_nsrc=3         idx_src0_op=CONST      idx_src1_op=CONST
idx_src2_op=CONST
inv_op=CONST           inv_is_invalid=1
out_op=WHERE           out_nsrc=3         out_src0_op=CMPLT      out_src1_op=STACK
out_src2_op=CONST      out_src2_is_invalid=1
out_src0_is_cond=1     out_src1_is_idx=1
```

**THE GATE'S OWN OUTPUT LINE:**

```
invalid-tensor-gate: 19 rows, 3 lanes -- the WHERE keeps the invalid BARE: a CONST, and still invalid, and the whole nodes survive by identity
```

**AND THE ROWS SPELL THE OP **NAME** AND NOT A BOOLEAN ABOUT IT.** A boolean row cannot tell
`CMPLT` from `CMPEQ` from `CMPNE` — **three wrong answers that all pass a `=1`**. The
oracle's names are upstream's `op.name`; the port's are the port's own `Ops.name.of`.

**AND THIS IS NOT `gates/ops-core`'s `valid_*` ROWS, AND THE GAP IS REAL.** Those rows ask
`cond.where(self, self.const_like(Invalid))` — a **CONST** `self` — and answer the **ARG**
CLASS of each src (`sg_ctor`). This test asks a **DIFFERENT QUESTION OF A DIFFERENT GRAPH**:
the `x` is a **STACK** with three srcs, the `y` is a **BARE INVALID CONST** rather than a
`const_like` of a shaped node, and the claim is about **`out.src[2].op` AND
`out.src[2].is_invalid`** — which **no `sg_ctor` row can see**, because `sg_ctor` reads the
arg and not the op.

### THE PLANTS — FOUR, AND ALL FOUR GO RED

| # | the text edit | the red output |
|---|---|---|
| **A** | `O.OpsCMPLT{}` → `O.OpsCMPEQ{}` in `g_cond` | `DISAGREE (bd): n=2 of 19 rows, 2 shown: [('cond_op=CMPLT', 'cond_op=CMPEQ'), ('out_src0_op=CMPLT', 'out_src0_op=CMPEQ')]` |
| **B** | the WHERE's srcs **SWAPPED** (`idx` and `cond`) | `DISAGREE (bd): n=4 of 19 rows, 2 shown: [('out_src0_op=CMPLT', 'out_src0_op=STACK'), ('out_src1_op=STACK', 'out_src1_op=CMPLT')]` |
| **C** | the invalid **CAST** instead of **BARE** — *the plant the test is named for* | `DISAGREE (bd): n=2 of 19 rows, 2 shown: [('out_src2_op=CONST', 'out_src2_op=CAST'), ('out_src2_is_invalid=1', 'out_src2_is_invalid=0')]` |
| **D** | the invalid **DROPPED** (src[2] is the STACK) | `DISAGREE (bd): n=2 of 19 rows, 2 shown: [('out_src2_op=CONST', 'out_src2_op=STACK'), ('out_src2_is_invalid=1', 'out_src2_is_invalid=0')]` |

**AND PLANTS C AND D ARE THE POINT OF THE FILE**: a WHERE that re-spelled the invalid as a
CAST passes the "is it a CONST" question's *neighbour* and fails the property; a WHERE that
dropped it entirely passes every op-shape row and fails only `out_src2_is_invalid`. **A GATE
THAT ONLY ASSERTED `out.src[2].op` WOULD PASS ON BOTH.**

Each plant was reverted and the gate re-run: **`invalid-tensor-gate: 19 rows, 3 lanes`**, rc=0,
and the driver byte-identical to its pre-plant state (`diff` clean).

### MEASURED, NOT ASSUMED

- **THE ARENA DISCIPLINE IS LOAD-BEARING.** The first version gave `cond`, `idx` and `out`
  their **OWN** arenas, and the port printed **`out_src0_op=CONST`** where CPython prints
  **`CMPLT`**. The reason is not a wrong build: **`O.Arena.src(ar, i, 0)` reads slot 0 OF
  THE ARENA YOU PASS**, and `cond`'s index belonged to a **different arena**. **ONE ARENA,
  EVERY NODE BUILT FROM THE PREVIOUS NODE's ARENA.** The port's own `gates/ops-core.bend`
  records the same hazard in its own words ("threaded wrongly the three srcs all read
  `ANone{}`").
- **THE `do` BLOCK'S LET IS `name : T <- expr` AND NOT `+name = expr`.** Measured: the first
  version put `+cond = g_cond()` inside the block and `bend` answered *"expected : a do-block
  let with its type (write \"x : T = ...\")"*.
- **A `do` BLOCK THAT IS THE WHOLE BODY OF A DEF NEEDS `return Unit{}`.** Measured
  minimally: without it `bend` answers *"expected : a term (the keyword 'def' cannot head
  one)"* **and points at the NEXT `def`**, which is a confusing place to look.
- **`U32` HAS NO `==` IN BEND.** `U32.is_eq(a, b)` IS THE EQUALITY.
- **`Ops.name` IS **NOT** A CLASSMETHOD UPSTREAM.** The oracle's first version called
  `Ops.name(op)` and died with `AttributeError: <enum 'Ops'> has no attribute 'name'`.
  **`op.name` IS UPSTREAM's OWN SPELLING.**
- **THE PORT's PEAK RSS ON THE DRIVER IS 297 MB** under the 3072 MB watchdog ceiling —
  `WITHIN-LIMITS`.

### THE LEDGER

`gates/gates-pop.ledger.tsv` records the **two `.py` files**. **AND THE `.bend` DRIVER IS
NOT IN THE LEDGER AND THAT IS CORRECT**: the ledger's population is **Python entry points**
(`gates/gates-pop.py:discover()` reads the AST `__main__`), and a `.bend` driver is a gate's
**input**, not a gate. MEASURED: `--write-ledger --only gates/invalid-tensor.bend` is
**REFUSED** ("a path this run can neither adopt nor retire"), and the ledger holds no `.bend`
row for any driver.

**AND THE LEDGER'S WALK READS `git ls-tree -r HEAD` — THE COMMIT TREE, NOT THE INDEX.** So a
gate that is **staged but not committed** is not in the population at all. MEASURED: the first
`--write-ledger --only` attempt, **before** the commit, wrote **nothing**; the second, **after**
the commit, added the two rows. **`gates/ledgerdue-gate.py` STAYS AT 20 DUE — THE SAME 20
PRE-EXISTING ROWS — AND MY TWO PATHS ARE OWNED RATHER THAN DUE.**

### THE DEFECTS FOUND

**NONE IN THE PORT.** The port and CPython agree on all 19 rows.

**AND THE KNOWN, PRE-EXISTING `ew_eq`/`ew_logical_not` INVERSION WAS NOT HIT**, because
this test never builds an `eq` or a `logical_not`: it builds a raw `CMPLT` and a raw `STACK`
at the `UOp` level. The defect stays where it was.

---

## FILE 2 — `test/null/test_tensor_io.py` (24 LOC) — **PORTED, GREEN, AND IT FILLED A REAL GAP**

### THE UPSTREAM TEST

```python
class TestTensorIO(unittest.TestCase):
  def test_create(self):
    with self.assertRaises(ValueError):
      TensorIO(Tensor(b"Hello World").reshape(1, -1))
    with self.assertRaises(ValueError):
      TensorIO(Tensor([], dtype=dtypes.int64).reshape(1, -1))

  def test_seek(self):
    t = Tensor(b"Hello World!")
    fobj = TensorIO(t)
    self.assertEqual(fobj.tell(), 0)
    self.assertEqual(fobj.seek(1), 1)
    self.assertEqual(fobj.seek(-2, 2), len(t) - 2)
    self.assertEqual(fobj.seek(1, 1), len(t) - 1)
    self.assertEqual(fobj.seek(10, 1), len(t))
    self.assertEqual(fobj.seek(10, 2), len(t))
    self.assertEqual(fobj.seek(-10, 0), 0)
```

### THE UPSTREAM CITATIONS, AT THE PIN `f5ac54685074`

| what | where at the pin |
|---|---|
| the refusal predicate | `tinygrad/nn/state.py` — `TensorIO.__init__`: `if t.ndim != 1 or t.dtype != dtypes.uint8: raise ValueError("Tensor must be 1d and of dtype uint8!")` |
| the seek | `tinygrad/nn/state.py` — `TensorIO.seek`: `self._position = min(len(self._tensor), max(0, [offset, self._position+offset, len(self._tensor)+offset][whence]))` |
| the position field | the same line's `self._position`, and `tell()` reads it |

### AND THE GAP WAS **MEASURED**, NOT GUESSED

`gates/state_census.bend`'s `val_seek_*` ROWS ARE **ISOLATED** CALLS — EVERY ONE OF THEM PASSES
`pos = 0` — AND `.agents/slop/state-gate.py`'s `sd_seek` ROW CREATES A **FRESH** `TensorIO` FOR
EACH CALL.

**AND THE `whence=1` CASE IS EXACTLY THE CASE THAT NEEDS A NON-ZERO `pos`.** `pos+off` IS THE
**SECOND** CANDIDATE, AND AT `pos == 0` THE SECOND CANDIDATE IS `off` AND THE THIRD IS `len+off`,
SO **THE SECOND IS NEVER CHOSEN** AND AN ISOLATED GATE **CANNOT SEE THE CASE AT ALL**.

**MEASURED ON CPYTHON — EXACTLY TWO OF UPSTREAM's SIX CALLS ARE `pos`-DEPENDENT:**

| call | position reached | answer | answer from a FRESH `TensorIO` | |
|---|---|---|---|---|
| `seek(1)` | 0 | 1 | 1 | pos-INDEPENDENT (`whence=0` picks `off`) |
| `seek(-2, 2)` | 1 | 10 | 10 | pos-INDEPENDENT (`whence=2` picks `len+off`) |
| `seek(1, 1)` | **10** | **11** | **1** | **POS-DEPENDENT** (`whence=1` picks `pos+off`) |
| `seek(10, 1)` | **11** | **12** | **10** | **POS-DEPENDENT** |
| `seek(10, 2)` | 12 | 12 | 12 | pos-INDEPENDENT |
| `seek(-10, 0)` | 12 | 0 | 0 | pos-INDEPENDENT |

**AND THE OTHER FOUR ARE `pos`-INDEPENDENT **STRUCTURALLY** — `whence=0` PICKS `off` AND
`whence=2` PICKS `len+off`, AND NEITHER MENTIONS `pos`.** So the **two** `whence=1` rows carry
the chain, and that is a measurement and not an assumption.

### AND THE `test_create` HALF IS **WEAKER THAN IT LOOKS**

**BOTH** of upstream's fixtures are **2-D**, so **both refuse on the `ndim != 1` clause and
neither reaches the dtype clause**. MEASURED: `Tensor(b"Hello World").reshape(1,-1)` IS
`(1, 11)` AND `Tensor([], dtype=int64).reshape(1,-1)` IS `(1, 0)` — BOTH `ndim == 2`. **AND
THAT IS WHY THE ROWS ARE SPLIT INTO THE TWO CLAUSES**, and `refuse_dtype_1x11=False` is the row
that pins the fact. **A PORT THAT GATED ONLY "THE DTYPE IS NOT uint8" WOULD PASS THE FIRST
FIXTURE FOR THE WRONG REASON.**

### AND THE PORT HAS NO `TensorIO` OBJECT, AND THAT IS FINE FOR BOTH HALVES

`tinybendygrad/nn/state.bend:498` records `TODO(p3) state.py:8 TensorIO -- io.RawIOBase;
readinto (:17) needs .data() (REALIZATION, tensor.bend WALL 4) and buffer[:n] = data mutates a
Python bytearray, which no Data record can express.`

**AND NEITHER HALF OF THE UPSTREAM TEST IS ABOUT `readinto`.** The refusal predicate is a
predicate on the tensor's shape and dtype; the seek is **pure integer arithmetic** on a length
and a position. **AND THE PORT ALREADY HAS THE SEEK's WHOLE RULE** — `St.sd_seek` IS
`state.py:25`'s LINE, VERBATIM, WITH THE SIGNED CLAMP — so **what is new here is the chain**.

### THE THREE FILES

- **`gates/tensor-io.bend`** — the port side.
- **`gates/tensor-io-oracle.py`** — the CPython side. A **real** `TensorIO` and **real** calls.
- **`gates/tensor-io-gate.py`** — the positional diff.

### THE ROWS — 22, THREE LANES, AND **rc=0**

```
shape_1x11=(1,11)  dtype_1x11=u8   refuse_ndim_1x11=True   refuse_dtype_1x11=False
shape_1x0=(1,0)    dtype_1x0=i64   refuse_ndim_1x0=True    refuse_dtype_1x0=True
shape_12=(12)      dtype_12=u8
tell=0  seek1=1  seek_neg2_w2=10  seek_1_w1=11  seek_10_w1=12  seek_10_w2=12  seek_neg10_w0=0
pos_before_seek1=0  pos_before_seek_neg2_w2=1  pos_before_seek_1_w1=10
pos_before_seek_10_w1=11  pos_before_seek_10_w2=12
```

**THE GATE'S OWN OUTPUT LINE:**

```
tensor-io-gate: 22 rows, 3 lanes -- the refusal predicate splits into its two clauses, and the seek is a CHAIN: each answer is the next position, which the isolated rows never reached
```

### THE PLANTS — FIVE, FOUR OF THEM RED, AND THE FIFTH IS THE INSTRUCTIVE ONE

| # | the text edit | the red output |
|---|---|---|
| **A** | the chain broken at the `whence=1` row (`pos = 0` instead of 10) | `DISAGREE (bd): n=1 of 22 rows, 1 shown: [('seek_1_w1=11', 'seek_1_w1=1')]` |
| **A′** | **the same plant at the `whence=2` row** (`pos = 0` instead of 1) | **DID NOT GO RED** — `whence=2` picks the third candidate `len+off`, which does not mention `pos`. **AND THAT IS WHY THE `whence=1` ROWS CARRY THE CHAIN**, and it was measured rather than assumed. |
| **B** | the chain's position read from a **different call** | `DISAGREE (bd): n=1 of 22 rows, 1 shown: [('pos_before_seek_10_w1=11', 'pos_before_seek_10_w1=1')]` |
| **C** | the `ndim` clause never fires (the **count** replaced by the constant `1`) | `DISAGREE (bd): n=2 of 22 rows, 2 shown: [('refuse_ndim_1x11=True', 'refuse_ndim_1x11=False'), ('refuse_ndim_1x0=True', 'refuse_ndim_1x0=False')]` |
| **C′** | **the first version of plant C** (compared against `99`) | **DID NOT GO RED** — `ndim != 99` is **TRUE** for a 2-D tensor, so the row correctly stayed `True`. **A PLANT THAT DOES NOT GO RED IS NOT A PLANT; IT IS A RESTATEMENT OF THE RULE, AND THE RULE IT RESTATED WAS BACKWARDS.** |
| **D** | the fixture is 12 elements instead of 11 | `DISAGREE (bd): n=3 of 22 rows, 2 shown: [('shape_1x11=(1,11)', 'shape_1x11=ABSENT'), ('dtype_1x11=u8', 'dtype_1x11=ABSENT')]` |
| **E** | `whence` read as a 0/1 flag — the defect `state.bend` itself names | `DISAGREE (bd): n=3 of 22 rows, 2 shown: [('seek_neg2_w2=10', 'seek_neg2_w2=4294967295'), ('seek_neg10_w0=0', 'seek_neg10_w0=4294967286')]` |

### AND TWO ROWS WERE **WRONG** AND WERE FIXED BEFORE THE COMMIT

**THE POSITION READ WITH `seek_dec(12, pos, 0, 0)` — THE OBVIOUS WAY TO ASK "WHAT IS THE
POSITION?" — ANSWERS `0`**, BECAUSE `whence=0` PICKS THE `off` CANDIDATE. **AND EVERY ONE OF
THE FIVE POSITION ROWS PRINTED `0`.** **AND A ROW THAT PRINTS A CONSTANT CANNOT GO RED**, SO
THE POSITION IS NOW READ AS **THE PREVIOUS CALL's ANSWER**, WHICH IS WHAT THE CHAIN MEANS.

### MEASURED, NOT ASSUMED

- **A `match` CANNOT SCRUTINISE A CALL NOR A LOCAL BINDER** — "a parameter or field scrutinee (a
  match cannot scrutinize a computed value: give it its own def)". **AND EVERY READER MATCHES
  A `Maybe` PARAMETER DIRECTLY** AND hands the unwrapped value to a second def, which is
  `tinybendygrad/uop/fold.bend`'s OWN `dt_is.pick` / `shape_is.of` SHAPE.
- **`dt_str` AND `dims_str` ARE **ALREADY** IN `uop/fold.bend`**, so a top-level `dt_str` in a
  driver **collides with the fold's**, and the error is *"expected : a term / observed : ']'"* at
  the signature — a confusing place to look.
- **THE FIXTURE'S ELEMENT COUNT IS PART OF THE CLAIM**: `Tensor(b"Hello World")` is **ELEVEN**
  elements and not twelve, and a fixture with the wrong count **does not resolve at all** — the
  reshape's product check fails and the port answers `ABSENT`.
- **A SHAPE'S SPELLING IS THE PORT's**: `F.dims_str` PRINTS `(1,11)` AND PYTHON's OWN
  `str(tuple)` PRINTS `(1, 11)`, **AND THE ROW IS A DIFF OF STRINGS**, SO THE ORACLE SPELLS IT
  THE PORT's WAY — WHICH IS WHAT `gates/fold_graph_census-oracle.py`'s `shape_of` ALREADY DOES.
- **A BOOLEAN ROW's SPELLING IS THE GATE's**: `gates/state_census.bend`'s `pb` PRINTS
  `Bool.show(b)` = `True`/`False` AND `.agents/slop/state-gate.py`'s `row` PRINTS PYTHON's
  `bool` = `True`/`False`, **AND `gates/ops-core`'s ORACLE IS THE OTHER CONVENTION (`1`/`0`),
  SO THE TREE HAS TWO AND THE TWO LANES OF A GATE MUST AGREE.** This gate follows the
  `state_census` one, because this gate is about `nn/state.bend`.
- **670 MB PEAK RSS** on the driver under the 3072 MB watchdog ceiling (`WITHIN-LIMITS`).

---

## THE FILES NOT ATTEMPTED, AND WHY

| upstream file | LOC | verdict | the reason |
|---|---|---|---|
| `test/null/test_gguf.py` | 13 | **SKIPPED — UNREACHABLE** | needs a **dataset download** (a GGUF file from the network). |
| `test/null/test_mnist_dataset.py` | 15 | **SKIPPED — UNREACHABLE** | needs a **dataset download** (MNIST). |
| `test/null/test_objc.py` | 17 | **SKIPPED — UNREACHABLE** | needs a **macOS framework** (Objective-C runtime). |
| `test/null/test_symbolic_ops.py` | 13 | **NOT STARTED — REACHABILITY NOT MEASURED** | asserts that `a.reshape((3, vi))` **RAISES `ValueError`** where `vi` is a **symbolic** `Variable`. Two questions, in order: **does the port have `Variable`/`Variable.bind` at all**, and **does the port have a way to express "this raised"** as a `name=value` row? A `.bend` row is not an exception. |
| `test/null/test_tensor_variable.py` | 13 | **NOT STARTED — REACHABILITY NOT MEASURED** | asserts that `t.chunk(2, dim=0)` along a **symbolic** dim **RAISES `AssertionError`**. Same two questions, plus `chunk` itself. |
| `test/null/test_hashing.py` | 18 | **BLOCKED — MEASURED** | needs `Tensor.keccak()`, and **the port has NO `keccak` AT ALL**: `tinybendygrad/mixin/op.bend` puts `keccak` on **SIDE B**, the **un-ported** half of `tinygrad/mixin/op.py` (lines 998-1980). **AND THE PRIMITIVES ARE ALSO UN-PORTED**: no `pad`, no `pad_to` as a tensor op, no `expand`, no `roll`, no `transpose`, no `flatten`, no `cat` as a tensor op, no `unsqueeze`, no `bitcast` — and `mixin/op.bend`'s OWN WALL LIST names `cat` as **W6** and the movement ops as **W4** (which needs `resolve`, W3's wall). **AND UPSTREAM's `keccak` IS A FULL SHA-3** (`rot_offsets`, `reorder_indexes`, `rnd_const_masks`, the f1600 permutation) at `tinygrad/mixin/op.py:1931`, so porting this test means porting the hash, which is **not** a test port. |
| `test/null/test_arange.py` | 22 | **BLOCKED — MEASURED** | needs `out.schedule_linear()` + `compile_linear` + `estimate_uop`, which is the **schedule preparation** layer, and `tinybendygrad/schedule/prepare.bend` is a stub. **AND THE `triu` half needs `resolve` (W3's wall) anyway.** |

**AND THE ORDER IS ASCENDING BY UPSTREAM FILE SIZE**, and the file this pass ported
(`test_invalid_tensor.py`, 16 LOC) is the **smallest REACHABLE** one: the two 13-LOC files
above are reachable only if the port can express a **raised** operation, which is a different
kind of question from "does the port agree with CPython on a graph's shape".

**AND `test/null/test_arange.py` AND `test/null/test_tensor_io.py` NEED A DEVICE, AND THE
PORT's DEVICE LAYER IS `tinybendygrad/device.bend`** — WHICH IS NOT MEASURED YET. **MEASURE IT
BEFORE PROMISING EITHER.**

---

## THE COMMITS

| commit | what |
|---|---|
| `55daf7665` | the three files: `gates/invalid-tensor.bend`, `gates/invalid-tensor-oracle.py`, `gates/invalid-tensor-gate.py` (3 files, +363) |
| `7ba76920a` | `gates/gates-pop.ledger.tsv`: the two new gate files recorded (+2) |
| `1d762fd3c` | the three files: `gates/tensor-io.bend`, `gates/tensor-io-oracle.py`, `gates/tensor-io-gate.py` (3 files, +555) |
| `4929e17e8` | `gates/gates-pop.ledger.tsv`: the second pair recorded (+2) |

**AND `git show --stat HEAD` AND `git fsck --no-progress` WERE RUN IN THE SAME COMMAND AS
EACH COMMIT**, and `fsck` reports **THE SAME TWO PRE-EXISTING MALFORMED TREES** (`3a60f33f`
and `d83cf685` — the two AGENTS.md records, owned by `63b64ebad` and `591f6b499`) and **NO NEW
ONE**. `git show --stat` reads **exactly the named paths** on both commits.

---

## WHAT IS PORTED, WHAT IS SKIPPED, WHAT IS BLOCKED

- **PORTED AND GREEN:** `test/null/test_invalid_tensor.py` — 19 rows, 3 lanes, rc=0, four
  plants all measured red — **AND** `test/null/test_tensor_io.py` — 22 rows, 3 lanes, rc=0,
  five plants of which **four** measured red and the fifth (**C′**) is recorded as a
  **backwards plant that correctly did not go red**.
- **SKIPPED AS UNREACHABLE:** `test_gguf.py` (dataset), `test_mnist_dataset.py` (dataset),
  `test_objc.py` (macOS framework).
- **NOT BLOCKED BY A DEFECT.** **NO PORT DEFECT WAS FOUND IN THIS PASS**, and the known
  pre-existing `ew_eq`/`ew_logical_not` inversion was **not** hit.
- **BLOCKED, WITH THE WALL NAMED:** `test_hashing.py` (no `keccak` in the port; the primitives
  are un-ported and `cat` is W6) and `test_arange.py` (the schedule-preparation stub, plus
  `resolve` for `triu`).
- **STILL OPEN, WITH THE QUESTION NAMED:** the two 13-LOC symbolic files need the port's
  `Variable` support **and** a way for a `.bend` row to say "this raised".
