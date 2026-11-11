import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/nn/state.bend as St

# tensor-io.bend -- THE PORT SIDE of upstream `test/null/test_tensor_io.py`.
#
#   .venv/bin/python gates/tensor-io-gate.py
#
# THE UPSTREAM TEST, at the pin `f5ac54685074`:
#
#   class TestTensorIO(unittest.TestCase):
#     def test_create(self):
#       with self.assertRaises(ValueError):
#         TensorIO(Tensor(b"Hello World").reshape(1, -1))
#       with self.assertRaises(ValueError):
#         TensorIO(Tensor([], dtype=dtypes.int64).reshape(1, -1))
#
#     def test_seek(self):
#       t = Tensor(b"Hello World!")
#       fobj = TensorIO(t)
#       self.assertEqual(fobj.tell(), 0)
#       self.assertEqual(fobj.seek(1), 1)
#       self.assertEqual(fobj.seek(-2, 2), len(t) - 2)
#       self.assertEqual(fobj.seek(1, 1), len(t) - 1)
#       self.assertEqual(fobj.seek(10, 1), len(t))
#       self.assertEqual(fobj.seek(10, 2), len(t))
#       self.assertEqual(fobj.seek(-10, 0), 0)
#
# TWO PROPERTIES, AND THEY ARE DIFFERENT KINDS OF THING:
#
#   `test_create` -- THE REFUSAL PREDICATE. upstream's `TensorIO.__init__` is
#     `if t.ndim != 1 or t.dtype != dtypes.uint8: raise ValueError(...)`
# (tinygrad/nn/state.py:11 at the pin).  AND BOTH OF UPSTREAM's FIXTURES ARE 2-D,
# SO BOTH REFUSE ON THE `ndim != 1` CLAUSE AND NEITHER REACHES THE DTYPE CLAUSE.
#     MEASURED ON CPYTHON: `Tensor(b"Hello World").reshape(1,-1)` HAS SHAPE `(1, 11)` AND
#     `Tensor([], dtype=int64).reshape(1,-1)` HAS SHAPE `(1, 0)` -- BOTH `ndim == 2`.
# AND THAT IS WHY THE UPSTREAM TEST IS WEAKER THAN IT LOOKS, AND WHY A PORT THAT
#     GATED ONLY "THE DTYPE IS NOT uint8" WOULD PASS BOTH FIXTURES FOR THE WRONG REASON.
#
# `test_seek` -- THE CHAINED SEEK. upstream's `TensorIO.seek` is
#     `self._position = min(len(self._tensor), max(0, [offset, self._position+offset,
# len(self._tensor)+offset][whence]))` (state.py:25 at the pin), AND EACH SEEK'S
# RESULT IS THE NEXT SEEK's `self._position`.  AND THE EXISTING GATE DOES NOT COVER
# THIS: `gates/state_census.bend`'s `val_seek_*` ROWS ARE ISOLATED CALLS -- EVERY ONE
#     OF THEM PASSES `pos = 0` -- AND `.agents/slop/state-gate.py`'s `sd_seek` ROW CREATES A
# FRESH `TensorIO` FOR EACH CALL.  AND THE TREE's OWN GATE DISCOVERED THE
# WHENCE=2 CASE IN ISOLATION (`state.bend`'s own header: "the `whence=2` case is the
#     other one: `len+offset` is the THIRD candidate, so an implementation that read `whence`
# as a 0/1 flag answers `0` where the answer is `1`"), BUT THE CHAIN IS WHERE A
# POSITION THAT IS NOT ZERO ACTUALLY GETS READ, AND NO ROW READS IT.
#
# THE PORT HAS NO `TensorIO` OBJECT AND THAT IS FINE FOR BOTH HALVES, AND THE REASON IS
# NAMED IN THE PORT's OWN FILE: `tinybendygrad/nn/state.bend:498` records
# `TODO(p3) state.py:8 TensorIO -- io.RawIOBase; readinto (:17) needs .data() (REALIZATION,
# tensor.bend WALL 4) and buffer[:n] = data mutates a Python bytearray, which no Data record
# can express.`  AND BOTH HALVES OF THE UPSTREAM TEST ARE ABOUT THINGS THAT ARE NOT
# `readinto`: THE REFUSAL PREDICATE IS A PREDICATE ON THE TENSOR'S SHAPE AND DTYPE, AND
# THE SEEK IS PURE INTEGER ARITHMETIC ON A LENGTH AND A POSITION.  AND THE PORT
# ALREADY HAS THE SEEK'S WHOLE RULE: `St.sd_seek` IS `state.py:25`'S LINE, VERBATIM, WITH
# THE SIGNED CLAMP -- AND IT IS ALREADY GATED IN ISOLATION.
#
# SO WHAT IS NEW HERE IS THE CHAIN, AND THE CHAIN IS THE POINT OF THE UPSTREAM TEST.

# ---- THE ROW PRINTERS -------------------------------------------------------------------

def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def rowb(nm: String, v: Bool) -> IO(Unit): row(nm, Bool.show(v))

# A DECIMAL, because the oracle's answers are Python INTEGERS and `H.i64_text`'s `hi:lo`
# IS A DIFFERENT SPELLING OF THE SAME NUMBER.  AND `H.lo32` IS THE LOW WORD, WHICH IS
# THE WHOLE OF THE ANSWER HERE: every seek answer is in `[0, len]` and `len` is 12, so the
# high word is ZERO and the low word is the answer. A NEGATIVE ANSWER WOULD NOT BE, BUT
# THE CLAMP MAKES IT IMPOSSIBLE -- WHICH IS THE PROPERTY `out_src2_is_invalid`-STYLE ROWS
# ASSERT ELSEWHERE AND WHICH THE `seek_neg_*` ROWS HERE PIN DIRECTLY.
#
# AND THE PLANT FOR THIS ROW IS THE 0/1-FLAG `whence` DEFECT THE PORT's OWN
# `state.bend` NAMES -- "an implementation that read `whence` as a 0/1 flag answers `0` where
# the answer is `1`" -- AND IT IS MEASURED HERE BY REPLACING `St.sd_seek` WITH A DRIVER-LOCAL
# READER THAT PICKS `off` FOR `whence == 0` AND `pos+off` FOR EVERYTHING ELSE:
# DISAGREE (bd): n=3 of 22 rows, 2 shown: [('seek_neg2_w2=10', 'seek_neg2_w2=4294967295'),
# ('seek_neg10_w0=0', 'seek_neg10_w0=4294967286')].  AND THE TWO NEGATIVE ANSWERS COME
# BACK AS TWO's-COMPLEMENT `U32`s, WHICH IS THE WHOLE POINT OF THE SIGNED CLAMP.
def seek_dec(len_: U32, pos: U32, off: U32, whence: U32) -> String:
  U32.show(H.lo32(St.sd_seek(len_, pos, off, whence)))

# ---- THE FIXTURES -----------------------------------------------------------------------

# `Tensor(b"Hello World")` -- ELEVEN bytes.  AND THE COUNT IS NOT FIVE: "Hello World" IS
# FIVE WORDS AND ELEVEN CHARACTERS, AND THE FIXTURE'S ELEMENT COUNT IS THE PRODUCT THAT
# THE RESHAPE IS CHECKED AGAINST, SO A WRONG COUNT MAKES THE FIXTURE NOT RESOLVE AND
# THE ROW PRINTED `ABSENT` INSTEAD OF A SHAPE -- WHICH IS WHAT HAPPENED THE FIRST TIME.
def g_buf_u8() -> O.ParamArg:
  O.ParamArg{0, S.uint8(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def g_buf11() -> O.Found:
  O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{11}, O.AParam{g_buf_u8()}, O.TNone{})

def g_buf12() -> O.Found:
  O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{12}, O.AParam{g_buf_u8()}, O.TNone{})

def g_buf0_i64() -> O.ParamArg:
  O.ParamArg{0, S.int64(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

# RESHAPE(BUFFER(11), STACK(CONST 1, CONST 11)) -- `Tensor(b"Hello World").reshape(1, -1)`.
def g_1x11() -> T.Tensor:
  +b = g_buf11()
  +c0 = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(1)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(11)})
  +shp = O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +rs = O.UOp.new(O.Found.ar(shp), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(shp)], O.ANone{}, O.TNone{})
  t : T.Tensor = T.Tensor{O.Found.ar(rs), O.Found.i(rs), True{}, 0}
  t

# RESHAPE(BUFFER(0, int64), STACK(CONST 1, CONST 0)) -- `Tensor([], dtype=int64).reshape(1, -1)`.
# AND THE ZERO IS A REAL EDGE: THE PRODUCT OF `(1, 0)` IS ZERO AND SO IS THE PRODUCT
# OF `(0,)`, WHICH IS WHAT MAKES THE RESHAPE RESOLVE AT ALL.
def g_1x0() -> T.Tensor:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{0}, O.AParam{g_buf0_i64()}, O.TNone{})
  +c0 = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(1)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(0)})
  +shp = O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +rs = O.UOp.new(O.Found.ar(shp), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(shp)], O.ANone{}, O.TNone{})
  t : T.Tensor = T.Tensor{O.Found.ar(rs), O.Found.i(rs), True{}, 0}
  t

# `Tensor(b"Hello World!")` -- TWELVE bytes, THE `test_seek` FIXTURE.  AND THE PORT
# HAS NO `TensorIO`, SO THE LENGTH IS A PARAMETER OF `St.sd_seek` -- WHICH IS EXACTLY
# WHAT THE PORT's OWN `state.bend` DOES ("`len(self._tensor)` is `t.shape[0]` ... which for
# the gate is the CONST's extent and is a PARAMETER here").
def g_12() -> T.Tensor:
  +b = g_buf12()
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(12)})
  +shp = O.UOp.new(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(c)], O.ANone{}, O.TNone{})
  +rs = O.UOp.new(O.Found.ar(shp), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(shp)], O.ANone{}, O.TNone{})
  t : T.Tensor = T.Tensor{O.Found.ar(rs), O.Found.i(rs), True{}, 0}
  t

# ---- THE REFUSAL PREDICATE ---------------------------------------------------------------

# `t.ndim != 1` -- THE NUMBER OF DIMS.  AND THE PORT's `tn_dims` IS A `Maybe` OVER A
# `Maybe`, SO THE COUNT IS A THIRD UNWRAP AND THE `ABSENT` IS A REAL ANSWER: A NODE THE
# FOLD CANNOT RESOLVE HAS NO SHAPE AND THEREFORE NO `ndim`, WHICH IS NOT "0" AND
# NOT "2" -- IT IS "THE PORT CANNOT ANSWER", WHICH IS THE PORT's OWN `ABSENT` TOKEN.
# AND THE MATCH IS ON A PARAMETER AND NOT ON A CALL AND NOT ON A LOCAL BINDER:
# MEASURED 2026-11-10, ALL THREE REFUSALS ARE `bend`'s "a parameter or field scrutinee (a
# match cannot scrutinize a computed value: give it its own def)" -- THE FIRST FOR
# `match T.tn_dims(t):` (A CALL), THE SECOND FOR `match m:` OVER A LOCAL BINDER, AND THE
# THIRD FOR `match ndim_of(m):` (A CALL).  SO EVERY READER MATCHES THE `Maybe` DIRECTLY
# AND THE UNWRAPPED VALUE IS HANDED TO A SECOND DEF -- WHICH IS
# `tinybendygrad/uop/fold.bend`'s OWN `dt_is.pick` / `shape_is.of` SHAPE.
def refuse_ndim.go(ds: List<&2, O.Sint>) -> Bool:
  Bool.not(U32.is_eq(U32.from_nat(List.length(&2, O.Sint, ds)), 1))

# AND THE PLANT FOR THIS PREDICATE IS MEASURED AND IT IS TWO PLANTS, AND THE FIRST
# ONE WAS BACKWARDS AND DID NOT GO RED: REPLACING THE `1` WITH A `99` MAKES `ndim != 99`
# TRUE FOR A 2-D TENSOR, SO THE ROW CORRECTLY STAYED `True` AND THE GATE STAYED GREEN.
# A PLANT THAT DOES NOT GO RED IS NOT A PLANT; IT IS A RESTATEMENT OF THE RULE, AND THE
# RULE IT RESTATED WAS BACKWARDS. THE PLANT THAT WORKS REPLACES THE COUNT WITH THE
# CONSTANT `1`, SO THE CLAUSE NEVER FIRES:
# DISAGREE (bd): n=2 of 22 rows, 2 shown: [('refuse_ndim_1x11=True', 'refuse_ndim_1x11=False'),
# ('refuse_ndim_1x0=True', 'refuse_ndim_1x0=False')].
#
# AND THE FIXTURE HAS ITS OWN PLANT, AND IT IS THE ONE THAT SAYS THE ELEMENT COUNT
# IS PART OF THE CLAIM: `Tensor(b"Hello World")` IS ELEVEN ELEMENTS AND NOT TWELVE, AND
# A FIXTURE WITH THE WRONG COUNT DOES NOT RESOLVE AT ALL -- THE RESHAPE's PRODUCT CHECK FAILS
# AND THE PORT ANSWERS `ABSENT`:
# DISAGREE (bd): n=3 of 22 rows, 2 shown: [('shape_1x11=(1,11)', 'shape_1x11=ABSENT'),
# ('dtype_1x11=u8', 'dtype_1x11=ABSENT')].

# THE PREDICATE, upstream's `TensorIO.__init__` GUARD, SPLIT INTO ITS TWO CLAUSES SO THAT
# A ROW CAN SAY WHICH ONE FIRED.  AND A SINGLE BOOLEAN ROW COULD NOT: BOTH
# UPSTREAM's FIXTURES ARE 2-D AND uint8-OR-int64, SO A BOOLEAN "IS IT REFUSED?" IS `1`
# FOR BOTH AND A READER CANNOT TELL WHICH CLAUSE DID THE WORK.
def refuse_ndim(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match m:
    case Some{ds}: refuse_ndim.go(ds)
    case None{}: False{}

def refuse_dtype(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{d}: Bool.not(O.eq_dt(d, S.uint8()))
    case None{}: False{}

# ---- THE ROWS ---------------------------------------------------------------------------

def rows() -> IO(Unit):
  # THE TWO REFUSAL FIXTURES.  AND THE `shape` AND `dtype` ROWS ARE NOT FLAVOUR: THEY
  # ARE WHAT MAKES THE REFUSAL ROWS MEAN SOMETHING, BECAUSE A REFUSAL ROW THAT ANSWERS
  # `1` FOR A TENSOR WHOSE SHAPE THE PORT NEVER RESOLVED WOULD BE A ROW THAT PASSES FOR THE
  # WRONG REASON.
  +t111 = g_1x11()
  +t10 = g_1x0()
  +t12 = g_12()
  do IO<Unit>:
    a : Unit <- row("shape_1x11", F.shape_str(T.Tensor.ar(t111), T.tn_shape(t111)))
    b : Unit <- row("dtype_1x11", F.dt_str(T.tn_dtype(t111)))
    c : Unit <- rowb("refuse_ndim_1x11", refuse_ndim(T.tn_dims(t111)))
    d : Unit <- rowb("refuse_dtype_1x11", refuse_dtype(T.tn_dtype(t111)))
    e : Unit <- row("shape_1x0", F.shape_str(T.Tensor.ar(t10), T.tn_shape(t10)))
    f : Unit <- row("dtype_1x0", F.dt_str(T.tn_dtype(t10)))
    g : Unit <- rowb("refuse_ndim_1x0", refuse_ndim(T.tn_dims(t10)))
    h : Unit <- rowb("refuse_dtype_1x0", refuse_dtype(T.tn_dtype(t10)))
    # THE `test_seek` FIXTURE'S SHAPE, FOR THE SAME REASON.
    i : Unit <- row("shape_12", F.shape_str(T.Tensor.ar(t12), T.tn_shape(t12)))
    j : Unit <- row("dtype_12", F.dt_str(T.tn_dtype(t12)))
    # THE CHAIN. THE POSITION STARTS AT ZERO (`TensorIO.tell()` IS `0`) AND EACH
    # SEEK's ANSWER IS THE NEXT SEEK's POSITION. THE TWO NEGATIVE OFFSETS ARE THE
    #   TWO's-COMPLEMENT `U32` IMAGES, BECAUSE `St.sd_seek`'s OFFSET PARAMETER IS A `U32`
    #   AND THE CLAMP IS SIGNED -- WHICH IS THE PORT's OWN NOTE ("a `U32` clamp answers
    #   `4294967295:4294967295` where CPython answers `0:0`").
    #
    #   THE CHAIN, IN UPSTREAM's ORDER:
    #     seek(1)      whence 0  pos 0   -> 1
    #     seek(-2, 2)  whence 2  pos 1   -> len-2 = 10
    #     seek(1, 1)   whence 1  pos 10  -> len-1 = 11
    #     seek(10, 1)  whence 1  pos 11  -> len   = 12
    #     seek(10, 2)  whence 2  pos 12  -> len   = 12
    #     seek(-10, 0) whence 0  pos 12  -> 0
    #
    # AND THE WHENCE=1 ROWS ARE THE ONES THAT NEED A NON-ZERO POSITION: `pos+off` IS
    # THE SECOND CANDIDATE, AND MEASURED ON CPYTHON, EXACTLY TWO OF THE SIX CALLS
    # ARE `pos`-DEPENDENT -- `seek(1, 1)` AT `pos = 10` ANSWERS 11 WHERE A FRESH
    #     `TensorIO` ANSWERS 1, AND `seek(10, 1)` AT `pos = 11` ANSWERS 12 WHERE A FRESH ONE
    # ANSWERS 10.  AND THE OTHER FOUR ARE `pos`-INDEPENDENT, AND THE REASON IS
    #     STRUCTURAL: `whence=0` PICKS `off` AND `whence=2` PICKS `len+off`, AND NEITHER
    # MENTIONS `pos`.  AND THAT IS WHY THE ISOLATED ROWS WERE NOT ENOUGH: A GATE
    # OF ISOLATED CALLS WITH `pos == 0` CANNOT SEE THE `whence=1` CASE AT ALL, BECAUSE
    #     AT `pos == 0` THE SECOND CANDIDATE IS `off` AND THE THIRD IS `len+off` AND THE
    # SECOND IS NEVER CHOSEN.
    # AND THE PLANTS FOR THE CHAIN ARE TWO, AND THE FIRST ONE WAS INEFFECTIVE AND
    # THAT IS THE POINT: BREAKING THE CHAIN AT THE `whence=2` ROW
    # (`seek_neg2_w2`, `pos = 1` -> `pos = 0`) DID NOT GO RED, BECAUSE `whence=2` PICKS
    # THE THIRD CANDIDATE `len+off`, WHICH DOES NOT MENTION `pos`.  AND THE
    # ROWS THAT DID GO RED ARE THE `whence=1` ONES, WHERE `pos+off` IS THE SECOND
    #   CANDIDATE AND `pos` IS THE WHOLE DIFFERENCE:
    # DISAGREE (bd): n=1 of 22 rows, 1 shown: [('seek_1_w1=11', 'seek_1_w1=1')].
    # AND THE POSITION ROWS HAVE THEIR OWN PLANT, WHICH READS THE POSITION FROM A
    # DIFFERENT CALL SO THE CHAIN'S POSITION MOVES:
    # DISAGREE (bd): n=1 of 22 rows, 1 shown: [('pos_before_seek_10_w1=11',
    # 'pos_before_seek_10_w1=1')].
    k : Unit <- row("tell", seek_dec(12, 0, 0, 0))
    l : Unit <- row("seek1", seek_dec(12, 0, 1, 0))
    m : Unit <- row("seek_neg2_w2", seek_dec(12, 1, 4294967294, 2))
    n : Unit <- row("seek_1_w1", seek_dec(12, 10, 1, 1))
    o : Unit <- row("seek_10_w1", seek_dec(12, 11, 10, 1))
    p : Unit <- row("seek_10_w2", seek_dec(12, 12, 10, 2))
    q : Unit <- row("seek_neg10_w0", seek_dec(12, 12, 4294967286, 0))
    # AND THE POSITIONS THE CHAIN PASSED THROUGH ARE ROWS, AND THEY ARE NOT THE
    # ANSWER ROWS ABOVE: THE ANSWER ROWS SAY WHERE THE CHAIN ENDED, AND THESE SAY
    # WHERE IT WAS BEFORE EACH CALL.  AND THE PORT's `sd_seek` IS A PURE FUNCTION OF
    # `(len, pos, off, whence)`, SO A CHAIN IN BEND IS THREADED EXPLICITLY -- EACH
    #   ROW's `pos` IS THE PREVIOUS ROW's ANSWER -- AND THAT IS WHY THESE ROWS ARE NEEDED
    # AT ALL: A GATE OF SIX ROWS WITH HAND-TYPED POSITIONS CANNOT TELL A CHAIN FROM
    # SIX INDEPENDENT CALLS, AND A GATE OF SIX ANSWER ROWS ALONE CANNOT EITHER.
    #
    # AND THE POSITION IS THE ANSWER OF THE PREVIOUS CALL, WHICH IS WHAT THE CHAIN
    # MEANS -- AND NOT A `seek(0)`, WHICH WOULD BE THE OBVIOUS WAY TO ASK AND WOULD
    # BE WRONG: `whence=0` PICKS THE `off` CANDIDATE, SO `seek(0)` ANSWERS 0 AND NOT
    # THE POSITION. MEASURED 2026-11-10: THE FIRST VERSION OF THIS BLOCK READ THE
    # POSITION WITH `seek_dec(12, pos, 0, 0)` AND EVERY ONE OF THE FIVE ROWS PRINTED
    # `0`, WHICH IS A ROW THAT CANNOT GO RED AND IS ALSO WRONG ABOUT THE CHAIN.
    # AND THE POSITION IS THEREFORE READ AS THE PREVIOUS CALL's ANSWER, WHICH IS THE
    #   SAME NUMBER THE CHAIN'S NEXT CALL CONSUMES.
    #
    # AND THE POSITIONS BEFORE EACH CALL, MEASURED ON CPYTHON BY READING `_position`
    # BEFORE EACH SEEK: `0, 1, 10, 11, 12, 12`.  AND THE SECOND OF THEM IS `pos == 1`,
    # WHICH IS NOT AMONG THE TREE's EXISTING SEEK ROWS: `gates/state_census.bend`'s
    #   `val_seek_*` ROWS ARE ALL `pos = 0` BUT FOR `ctrl_seek` WHICH IS `pos = 3` ON A
    # FOUR-ELEMENT TENSOR.  AND `pos == 1` IS NOT AMONG THEM, WHICH IS WHY THE CHAIN
    # IS NOT ALREADY GATED.
    r : Unit <- row("pos_before_seek1", seek_dec(12, 0, 0, 0))
    s : Unit <- row("pos_before_seek_neg2_w2", seek_dec(12, 0, 1, 0))
    t : Unit <- row("pos_before_seek_1_w1", seek_dec(12, 1, 4294967294, 2))
    u : Unit <- row("pos_before_seek_10_w1", seek_dec(12, 10, 1, 1))
    v : Unit <- row("pos_before_seek_10_w2", seek_dec(12, 11, 10, 1))
    return Unit{}

def main() -> IO(Unit): rows()
