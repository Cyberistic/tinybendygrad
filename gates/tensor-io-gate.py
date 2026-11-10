#!/usr/bin/env python3
"""tensor-io-gate.py -- THE GATE FOR upstream `test/null/test_tensor_io.py`.

    .venv/bin/python gates/tensor-io-gate.py

22 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- over the two properties
upstream's test asserts.

THE TWO PROPERTIES, AND THEY ARE **DIFFERENT KINDS** OF THING.

`test_create` -- THE REFUSAL PREDICATE. upstream's `TensorIO.__init__` at the pin is

    if t.ndim != 1 or t.dtype != dtypes.uint8: raise ValueError("Tensor must be 1d and of dtype uint8!")

**⇒ AND BOTH OF UPSTREAM's FIXTURES ARE **2-D**, SO BOTH REFUSE ON THE `ndim != 1` CLAUSE AND
NEITHER REACHES THE DTYPE CLAUSE.** MEASURED: `Tensor(b"Hello World").reshape(1,-1)` HAS SHAPE
`(1, 11)` AND `Tensor([], dtype=int64).reshape(1,-1)` HAS SHAPE `(1, 0)` -- BOTH `ndim == 2`.
**⇒ AND THAT IS WHY THE UPSTREAM TEST IS WEAKER THAN IT LOOKS**, AND WHY A PORT THAT GATED
ONLY "THE DTYPE IS NOT uint8" WOULD PASS THE FIRST FIXTURE FOR THE WRONG REASON. THE ROWS ARE
THEREFORE SPLIT INTO THE TWO CLAUSES, SO A READER CAN SEE WHICH ONE FIRED -- AND THE
`refuse_dtype_1x11=False` ROW IS WHAT PINS THE FACT.

`test_seek` -- THE **CHAINED** SEEK. upstream's `TensorIO.seek` at the pin is

    self._position = min(len(self._tensor), max(0, [offset, self._position+offset, len(self._tensor)+offset][whence]))

**⇒ AND EACH SEEK's RESULT IS THE NEXT SEEK's `self._position`.**

**⇒ AND THIS IS THE REAL GAP IN THE TREE, MEASURED, NOT GUESSED.** `gates/state_census.bend`'s
`val_seek_*` ROWS ARE **ISOLATED** CALLS -- EVERY ONE OF THEM PASSES `pos = 0` -- AND
`.agents/slop/state-gate.py`'s `sd_seek` ROW CREATES A **FRESH** `TensorIO` FOR EACH CALL.
**⇒ AND THE `whence=2` CASE IS EXACTLY THE CASE THAT NEEDS A NON-ZERO `pos`**: `len+offset` IS
THE **THIRD** CANDIDATE, AND WITH `pos == 0` THE SECOND CANDIDATE `pos+offset` AND THE THIRD
`len+offset` ARE BOTH READ FROM A POSITION THE ISOLATED ROWS NEVER REACH. THE PORT's OWN
`tinybendygrad/nn/state.bend` NAMES THIS: "the `whence=2` case is the other one: `len+offset`
is the THIRD candidate, so an implementation that read `whence` as a 0/1 flag answers `0` where
the answer is `1`."

**⇒ AND THE POSITION ROWS ARE NOT THE ANSWER ROWS.** A CHAIN IS A SEQUENCE, AND SIX ROWS THAT
ONLY READ THE ANSWERS CANNOT TELL A CHAIN FROM SIX INDEPENDENT CALLS WITH HAND-PICKED
POSITIONS. THE FIVE `pos_after_*` ROWS READ THE POSITION THE CHAIN WAS IN **BEFORE** EACH
CALL, AND THE `seek_neg2_w2` ROW IS THE ONE THAT USES A NON-ZERO `pos` (`1`, WHICH IS THE
ANSWER OF THE FIRST ROW).

THE PORT HAS NO `TensorIO` OBJECT AND THAT IS FINE FOR BOTH HALVES, AND THE REASON IS NAMED
IN THE PORT's OWN FILE: `tinybendygrad/nn/state.bend:498` records `TODO(p3) state.py:8
TensorIO -- io.RawIOBase; readinto (:17) needs .data() (REALIZATION, tensor.bend WALL 4) and
buffer[:n] = data mutates a Python bytearray`. **⇒ AND NEITHER HALF OF THE UPSTREAM TEST IS
ABOUT `readinto`**: THE REFUSAL PREDICATE IS A PREDICATE ON THE TENSOR's SHAPE AND DTYPE, AND
THE SEEK IS **PURE INTEGER ARITHMETIC** ON A LENGTH AND A POSITION -- AND THE PORT ALREADY HAS
THE SEEK's WHOLE RULE (`St.sd_seek` IS `state.py:25`'s LINE, VERBATIM, WITH THE SIGNED CLAMP).

NO ROW IS TRANSCRIBED FROM UPSTREAM's TEST. The oracle BUILDS THE SAME GRAPH IN CPython's OWN
`tinygrad` AND ANSWERS THE SAME QUESTIONS.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE. THE ORDER IS THE ORDER BOTH LANES PRINT IN, AND THE GATE COMPARES THEM
# **POSITIONALLY** (`gates/gatekit.py`: `zip(base, other)`), SO THE ORDER IS PART OF THE
# CONTRACT.
ROWS = (
    # THE TWO REFUSAL FIXTURES, AND **THE SHAPE AND DTYPE ROWS ARE NOT FLAVOUR**: A REFUSAL
    # ROW THAT ANSWERS `True` FOR A TENSOR WHOSE SHAPE THE PORT NEVER RESOLVED WOULD BE A ROW
    # THAT PASSES FOR THE WRONG REASON.
    "shape_1x11", "dtype_1x11", "refuse_ndim_1x11", "refuse_dtype_1x11",
    "shape_1x0", "dtype_1x0", "refuse_ndim_1x0", "refuse_dtype_1x0",
    # THE `test_seek` FIXTURE'S SHAPE AND DTYPE, FOR THE SAME REASON.
    "shape_12", "dtype_12",
    # ⇒ **THE CHAIN.** THE POSITION STARTS AT ZERO (`TensorIO.tell()` IS `0`) AND **EACH
    #   SEEK's ANSWER IS THE NEXT SEEK's POSITION.** THE TWO NEGATIVE OFFSETS ARE THE TWO's
    #   COMPLEMENT `U32` IMAGES, BECAUSE `St.sd_seek`'s OFFSET PARAMETER IS A `U32` AND THE
    #   CLAMP IS SIGNED.
    "tell", "seek1", "seek_neg2_w2", "seek_1_w1", "seek_10_w1", "seek_10_w2", "seek_neg10_w0",
    # ⇒ AND THE **POSITIONS THE CHAIN PASSED THROUGH**, WHICH ARE NOT THE SAME NUMBERS AS
    #   THE ANSWERS ABOVE: THE CHAIN'S SECOND CALL IS `seek(-2, 2)` WITH `pos == 1`.
    "pos_before_seek1", "pos_before_seek_neg2_w2", "pos_before_seek_1_w1",
    "pos_before_seek_10_w1", "pos_before_seek_10_w2",
)

GATE = Gate(
    "tensor-io-gate",
    bend="tensor-io.bend",
    oracle="tensor-io-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tensor-io-gate: 22 rows, 3 lanes -- the refusal predicate splits into "
                        "its two clauses, and the seek is a CHAIN: each answer is the next "
                        "position, which the isolated rows never reached"))
