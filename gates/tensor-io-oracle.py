#!/usr/bin/env python3
"""tensor-io-oracle.py -- CPython's answers to `gates/tensor-io.bend`'s rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tensor-io-oracle.py

THE UPSTREAM TEST THIS PORTES. `test/null/test_tensor_io.py` at the pin `f5ac54685074`:

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

TWO PROPERTIES, AND THEY ARE **DIFFERENT KINDS** OF THING.

`test_create` -- THE REFUSAL PREDICATE. upstream's `TensorIO.__init__` at the pin is

    if t.ndim != 1 or t.dtype != dtypes.uint8: raise ValueError("Tensor must be 1d and of dtype uint8!")

**⇒ AND BOTH OF UPSTREAM's FIXTURES ARE **2-D**, SO BOTH REFUSE ON THE `ndim != 1` CLAUSE AND
NEITHER REACHES THE DTYPE CLAUSE.** MEASURED HERE: `Tensor(b"Hello World").reshape(1,-1)` HAS
SHAPE `(1, 11)` AND `Tensor([], dtype=dtypes.int64).reshape(1,-1)` HAS SHAPE `(1, 0)` -- BOTH
`ndim == 2`. **⇒ AND THAT IS WHY THE UPSTREAM TEST IS WEAKER THAN IT LOOKS**, AND WHY A PORT
THAT GATED ONLY "THE DTYPE IS NOT uint8" WOULD PASS BOTH FIXTURES FOR THE WRONG REASON. THE
ROWS ARE THEREFORE SPLIT INTO THE TWO CLAUSES, SO A READER CAN SEE WHICH ONE FIRED.

`test_seek` -- THE **CHAINED** SEEK. upstream's `TensorIO.seek` at the pin is

    self._position = min(len(self._tensor), max(0, [offset, self._position+offset, len(self._tensor)+offset][whence]))

**⇒ AND EACH SEEK's RESULT IS THE NEXT SEEK's `self._position`.** THE EXISTING TREE GATE
(`gates/state_census.bend`'s `val_seek_*` ROWS, AND `.agents/slop/state-gate.py`'s `sd_seek`
ROW) COVERS **ISOLATED** CALLS ONLY -- EVERY ONE OF THEM WITH `pos == 0`, OR WITH A FRESH
`TensorIO` PER CALL -- **SO THE CHAIN IS WHAT IS NEW HERE**, AND IT IS WHAT THE UPSTREAM TEST
IS ACTUALLY ABOUT.

NO EXPECTED VALUE IS TRANSCRIBED HERE. Every row is an answer CPython COMPUTES from its own
`tinygrad`, and the port's lane is a second implementation of the same property.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tinygrad import Tensor, dtypes
from tinygrad.nn.state import TensorIO


def b(value: bool) -> str:
    """A 1-cell Bool as the row's value.

    **⇒ AND IT PRINTS PYTHON's OWN `bool` AND NOT `1`/`0`,** because that is the tree's
    EXISTING CONVENTION FOR A BOOLEAN ROW: `gates/state_census.bend`'s `pb` PRINTS
    `Bool.show(b)` -- WHICH IS `True`/`False` -- AND `.agents/slop/state-gate.py`'s `row`
    PRINTS PYTHON's `bool`, WHICH IS ALSO `True`/`False`. **⇒ AND `gates/ops-core`'s ORACLE
    IS THE OTHER CONVENTION (`1`/`0`), SO THE TREE HAS TWO AND THE TWO LANES OF A GATE MUST
    AGREE.** THIS ORACLE FOLLOWS THE `state_census` ONE, BECAUSE THIS GATE IS ABOUT
    `nn/state.bend`.
    """
    return str(value)


def shape_of(t) -> str:
    """A shape in **THE PORT's SPELLING**, AND THE SPELLING IS A DECISION.

    **⇒ AND THE PORT's SPELLING IS `F.dims_str`'s**: `gates/fold_graph_census-oracle.py`'s
    `shape_of` DOES EXACTLY THIS -- `"(" + ",".join(dim_str(x) for x in s) + ")"` -- AND
    PYTHON's OWN `str(tuple)` SPELLS IT `(1, 11)` **WITH A SPACE**. **⇒ AND THE ROW IS A
    DIFF OF STRINGS**, SO THE SPACING IS PART OF THE CONTRACT AND THE ORACLE HAS TO SPELL
    IT THE PORT's WAY, WHICH IS WHAT THE FOLD GATE's ORACLE ALREADY DOES.
    """
    return "(" + ",".join(str(d) for d in t.shape) + ")"


def _pos_name(args) -> str:
    """A CALL's ROW-NAME SUFFIX, DERIVED FROM THE CALL ITSELF.

    **⇒ AND THE SUFFIX IS `seek1` / `neg2` / `1w1` / `10w1` / `10w2`,** WHICH ARE THE
    PORT's OWN ROW NAMES, AND **THEY ARE DERIVED FROM THE CALL RATHER THAN TYPED**, SO A
    ROW AND ITS CALL CANNOT DRIFT APART: THE PORT's DRIVER NAMES THE SAME FIVE CALLS AND
    THE ORACLE's `f"pos_before_{_pos_name(args)}"` NAMES THEM FROM THE SAME SHAPE.
    """
    if len(args) == 1:
        return "seek1" if args[0] == 1 else f"seek{args[0]}"
    # A NEGATIVE OFFSET IS SPELLED `neg<N>` AND NOT `-<N>w<W>`, BECAUSE THE ROW NAME IS A
    # WORD AND NOT A NUMBER: THE PORT's DRIVER SPELLS IT `seek_neg2_w2` AND THE ORACLE's
    # NAME HAS TO MATCH IT EXACTLY, SO THE SIGN IS FOLDED INTO THE WORD.
    off = f"neg{-args[0]}" if args[0] < 0 else str(args[0])
    return f"seek_{off}_w{args[1]}"


def refuse_ndim(t) -> bool:
    """`t.ndim != 1` -- upstream's FIRST clause of `TensorIO.__init__`'s guard."""
    return t.ndim != 1


def refuse_dtype(t) -> bool:
    """`t.dtype != dtypes.uint8` -- upstream's SECOND clause."""
    return t.dtype != dtypes.uint8


def main() -> None:
    # THE TWO REFUSAL FIXTURES. "Hello World" is ELEVEN characters, and the count MATTERS:
    # the reshape is checked against the src's product, so a fixture with the wrong element
    # count does not resolve.
    t_1x11 = Tensor(b"Hello World").reshape(1, -1)
    t_1x0 = Tensor([], dtype=dtypes.int64).reshape(1, -1)
    # THE `test_seek` FIXTURE: TWELVE bytes.
    t_12 = Tensor(b"Hello World!")

    rows = [
        ("shape_1x11", shape_of(t_1x11)),
        ("dtype_1x11", t_1x11.dtype.name),
        ("refuse_ndim_1x11", b(refuse_ndim(t_1x11))),
        ("refuse_dtype_1x11", b(refuse_dtype(t_1x11))),
        ("shape_1x0", shape_of(t_1x0)),
        ("dtype_1x0", t_1x0.dtype.name),
        ("refuse_ndim_1x0", b(refuse_ndim(t_1x0))),
        ("refuse_dtype_1x0", b(refuse_dtype(t_1x0))),
        ("shape_12", shape_of(t_12)),
        ("dtype_12", t_12.dtype.name),
    ]

    # ⇒ **THE CHAIN.** A REAL `TensorIO` AND REAL CALLS, IN UPSTREAM's ORDER, AND **EACH
    #   CALL's ANSWER IS THE NEXT CALL's POSITION** -- which is the property, and which the
    #   isolated rows cannot express.
    f = TensorIO(t_12)
    n = len(t_12)
    rows.append(("tell", str(f.tell())))
    rows.append(("seek1", str(f.seek(1))))
    rows.append(("seek_neg2_w2", str(f.seek(-2, 2))))
    rows.append(("seek_1_w1", str(f.seek(1, 1))))
    rows.append(("seek_10_w1", str(f.seek(10, 1))))
    rows.append(("seek_10_w2", str(f.seek(10, 2))))
    rows.append(("seek_neg10_w0", str(f.seek(-10, 0))))

    # ⇒ AND THE **POSITIONS THE CHAIN PASSED THROUGH** ARE ROWS, AND **THEY ARE NOT THE
    #   ANSWER ROWS ABOVE**: THE ANSWER ROWS SAY WHERE THE CHAIN **ENDED**, AND THESE SAY
    #   WHERE IT **WAS** BEFORE EACH CALL. **⇒ AND THE POSITION IS READ FROM **`_position`**,
    #   WHICH IS UPSTREAM's OWN FIELD NAME (state.py:25 at the pin), AND NOT FROM A SECOND
    #   `tell()` CALL, BECAUSE `tell()` IS `io.RawIOBase`'s AND READS THE SAME FIELD.
    #
    # ⇒ AND THE POSITION IS READ **BEFORE** EACH CALL, WHICH IS WHY THE REPLAY IS WRITTEN
    #   AS A LOOP RATHER THAN AS SIX COPIED LINES: A CHAIN IS A SEQUENCE AND A LIST OF SIX
    #   HAND-COPIED CALLS IS **NOT** A CHAIN, IT IS SIX INDEPENDENT CALLS WITH SIX HAND-TYPED
    #   POSITIONS -- WHICH IS EXACTLY THE DEFECT THIS GATE EXISTS TO CATCH.
    g = TensorIO(t_12)
    for args in ((1,), (-2, 2), (1, 1), (10, 1), (10, 2)):
        rows.append((f"pos_before_{_pos_name(args)}", str(g._position)))
        g.seek(*args)
    # ⇒ AND THE LAST POSITION THE CHAIN REACHED IS A ROW TOO, BECAUSE IT IS THE POSITION
    #   THE **FINAL** CALL (`seek(-10, 0)`) IS REACHED WITH, AND THAT CALL IS THE ONE WHOSE
    #   ANSWER IS `0` **BECAUSE OF THE CLAMP** RATHER THAN BECAUSE OF THE CANDIDATE.

    for name, value in rows:
        print(f"{name}={value}")


if __name__ == "__main__":
    main()
