# THE UPSTREAM SUITE, PORTED ONE FILE AT A TIME

**DISPATCHED 2026-11-10.** ONE upstream test file per pass, and each pass either lands a
GREEN gate or reports the file as SKIPPED or BLOCKED. **NO EXPECTED VALUE IS EVER
TRANSCRIBED FROM AN UPSTREAM `.py` TEST INTO A `.bend` LITERAL.**

---

## THE ARCHITECTURE, AND WHY IT IS NOT OPTIONAL

`import tinygrad` resolves to the **vendored upstream Python** at `tinygrad/`. The port is
`.bend` and is **not** importable as `tinygrad`. **⇒ SO UPSTREAM's `.py` TESTS CANNOT RUN
AGAINST THE PORT, AND A "PORTED TEST" THAT IS A `.py` FILE WOULD BE TESTING UPSTREAM.**

The tree's established shape is a **triple**:

| file | what it is | who reads it |
|---|---|---|
| `gates/<name>.bend` | the **PORT** side: calls the port's own defs, prints `name=value` rows | the gate |
| `gates/<name>-oracle.py` | the **CPYTHON** side: builds the SAME graph in the vendored upstream, prints the SAME rows | the gate |
| `gates/<name>-gate.py` | the **DIFF**: a `gatekit.Gate` over both, positional, three lanes | a human, the sweep |

**THE THREE LANES** are CPython, `bend` interpreted, and `bend` compiled (`bend -o`).
`gates/gatekit.py` owns the plumbing; a gate file owns only its rows.

**⇒ AND NO ROW IS A COMPARISON AGAINST A TYPED NUMBER.** Every value in every row is
COMPUTED by the lane that prints it, by the lane that prints it. A `.bend` row that said
`out_op=WHERE` because somebody typed `WHERE` into the driver would test the typing.

**⇒ AND EVERY ROW MUST GO RED ON A PLANT.** A text edit, the row goes red, the edit is
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

**⇒ AND `UOp` AT THE PIN INHERITS `ElementwiseMixin`**, so `UOp.__lt__` and `UOp.where` EXIST
ON A `UOp` AND NOT ONLY ON A `Tensor` — MEASURED: `UOp.__mro__` IS
`UOp → RandMixin → OpMixin → ElementwiseMixin → CreationMixin → ReduceMixin → DTypeMixin →
MovementMixin → object`, AND `UOp._uop` IS A PROPERTY THAT RETURNS `self`. **⇒ AND THE
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

**⇒ AND THE ROWS SPELL THE OP **NAME** AND NOT A BOOLEAN ABOUT IT.** A boolean row cannot tell
`CMPLT` from `CMPEQ` from `CMPNE` — **three wrong answers that all pass a `=1`**. The
oracle's names are upstream's `op.name`; the port's are the port's own `Ops.name.of`.

**⇒ AND THIS IS NOT `gates/ops-core`'s `valid_*` ROWS, AND THE GAP IS REAL.** Those rows ask
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

**⇒ AND PLANTS C AND D ARE THE POINT OF THE FILE**: a WHERE that re-spelled the invalid as a
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

`gates/gates-pop.ledger.tsv` records the **two `.py` files**. **⇒ AND THE `.bend` DRIVER IS
NOT IN THE LEDGER AND THAT IS CORRECT**: the ledger's population is **Python entry points**
(`gates/gates-pop.py:discover()` reads the AST `__main__`), and a `.bend` driver is a gate's
**input**, not a gate. MEASURED: `--write-ledger --only gates/invalid-tensor.bend` is
**REFUSED** ("a path this run can neither adopt nor retire"), and the ledger holds no `.bend`
row for any driver.

**⇒ AND THE LEDGER'S WALK READS `git ls-tree -r HEAD` — THE COMMIT TREE, NOT THE INDEX.** So a
gate that is **staged but not committed** is not in the population at all. MEASURED: the first
`--write-ledger --only` attempt, **before** the commit, wrote **nothing**; the second, **after**
the commit, added the two rows. **`gates/ledgerdue-gate.py` STAYS AT 20 DUE — THE SAME 20
PRE-EXISTING ROWS — AND MY TWO PATHS ARE OWNED RATHER THAN DUE.**

### THE DEFECTS FOUND

**NONE IN THE PORT.** The port and CPython agree on all 19 rows.

**⇒ AND THE KNOWN, PRE-EXISTING `ew_eq`/`ew_logical_not` INVERSION WAS NOT HIT**, because
this test never builds an `eq` or a `logical_not`: it builds a raw `CMPLT` and a raw `STACK`
at the `UOp` level. The defect stays where it was.

---

## THE FILES NOT ATTEMPTED, AND WHY

| upstream file | LOC | verdict | the reason |
|---|---|---|---|
| `test/null/test_gguf.py` | 13 | **SKIPPED — UNREACHABLE** | needs a **dataset download** (a GGUF file from the network). |
| `test/null/test_mnist_dataset.py` | 15 | **SKIPPED — UNREACHABLE** | needs a **dataset download** (MNIST). |
| `test/null/test_objc.py` | 17 | **SKIPPED — UNREACHABLE** | needs a **macOS framework** (Objective-C runtime). |
| `test/null/test_symbolic_ops.py` | 13 | **NOT STARTED — REACHABILITY NOT MEASURED** | asserts that `a.reshape((3, vi))` **RAISES `ValueError`** where `vi` is a **symbolic** `Variable`. Two questions, in order: **does the port have `Variable`/`Variable.bind` at all**, and **does the port have a way to express "this raised"** as a `name=value` row? A `.bend` row is not an exception. |
| `test/null/test_tensor_variable.py` | 13 | **NOT STARTED — REACHABILITY NOT MEASURED** | asserts that `t.chunk(2, dim=0)` along a **symbolic** dim **RAISES `AssertionError`**. Same two questions, plus `chunk` itself. |
| `test/null/test_hashing.py` | 18 | **NOT STARTED** | the next candidate; not yet measured. |
| `test/null/test_arange.py` | 22 | **NOT STARTED** | needs the port's **device layer**, whose state is not measured. |
| `test/null/test_tensor_io.py` | 24 | **NOT STARTED** | needs the port's **device layer**. |

**⇒ AND THE ORDER IS ASCENDING BY UPSTREAM FILE SIZE**, and the file this pass ported
(`test_invalid_tensor.py`, 16 LOC) is the **smallest REACHABLE** one: the two 13-LOC files
above are reachable only if the port can express a **raised** operation, which is a different
kind of question from "does the port agree with CPython on a graph's shape".

**⇒ AND `test/null/test_arange.py` AND `test/null/test_tensor_io.py` NEED A DEVICE, AND THE
PORT's DEVICE LAYER IS `tinybendygrad/device.bend`** — WHICH IS NOT MEASURED YET. **MEASURE IT
BEFORE PROMISING EITHER.**

---

## THE COMMITS

| commit | what |
|---|---|
| `55daf7665` | the three files: `gates/invalid-tensor.bend`, `gates/invalid-tensor-oracle.py`, `gates/invalid-tensor-gate.py` (3 files, +363) |
| `7ba76920a` | `gates/gates-pop.ledger.tsv`: the two new gate files recorded (+2) |

**⇒ AND `git show --stat HEAD` AND `git fsck --no-progress` WERE RUN IN THE SAME COMMAND AS
EACH COMMIT**, and `fsck` reports **THE SAME TWO PRE-EXISTING MALFORMED TREES** (`3a60f33f`
and `d83cf685` — the two AGENTS.md records, owned by `63b64ebad` and `591f6b499`) and **NO NEW
ONE**. `git show --stat` reads **exactly the named paths** on both commits.

---

## WHAT IS PORTED, WHAT IS SKIPPED, WHAT IS BLOCKED

- **PORTED AND GREEN:** `test/null/test_invalid_tensor.py` — 19 rows, 3 lanes, rc=0, four
  plants all measured red.
- **SKIPPED AS UNREACHABLE:** `test_gguf.py` (dataset), `test_mnist_dataset.py` (dataset),
  `test_objc.py` (macOS framework).
- **NOT BLOCKED BY A DEFECT.** **NO PORT DEFECT WAS FOUND IN THIS PASS**, and the known
  pre-existing `ew_eq`/`ew_logical_not` inversion was **not** hit.
- **STILL OPEN, WITH THE QUESTION NAMED:** the two 13-LOC symbolic files need the port's
  `Variable` support **and** a way for a `.bend` row to say "this raised".
