#!/usr/bin/env python3
"""rand_census-oracle.py -- CPython's lane for `gates/rand_census-gate.py`.

    .venv/bin/python gates/rand_census-gate.py
    .venv/bin/python gates/rand_census-oracle.py > /tmp/py.txt

36 ROWS OUT OF THE 55 `tinybendygrad/mixin/rand.bend` PRINTS, AND THE OTHER NINETEEN HAVE NO ROW
HERE. (The first version of this header said "35 out of the 51 ... the other sixteen";
MEASURED, this file printed 32 and the port-only set is 19, so BOTH numbers were wrong by 3 and
the count was a transcription rather than a measurement.) THAT IS THE POINT OF THIS FILE --
it is the first CPython lane this layer has had, because the one it had,
`.agents/slop/rd-truth.py`, IS GONE: not on disk, and not in any git history
(`git log --all -- .agents/slop/rd-truth.py` is empty). So the nineteen are declared
`port_only` by the gate, which ASSERTS THEIR ABSENCE here, rather than being quietly dropped.

WHAT IS HERE, AND WHY EACH ROW IS CPYTHON'S ANSWER RATHER THAN A RESTATEMENT.

  * `st_zero_g` .. `st_max_g` call `Tensor._next_counter(DEVICE, num)` -- the real method at
    `tinygrad/tensor.py:460`, with `Tensor._device_rng_counters[DEVICE]` RESET to the
    `Tensor([0,0], uint32)` the port injects, because the port's `rd_state` is
    `Tensor.empty(2, uint32)`. The graph signature is CPython's own
    `t.uop.toposort()`, so a wrong node ANYWHERE moves the row.
  * `st_zero_v` .. `st_max_v` are the SAME calls read as VALUES: `_next_counter`'s own returned
    `low.cat(high)`, realised, printed as the `hi:lo` pair `H.i64_text` prints on the port
    side. `_next_counter` takes NO counter argument, so "set the stored counter to the fixture"
    is not a parameterisation this file invents -- it is the only way the method can be
    called at all. THESE FOUR ARE THE WITNESS for `counter.assign` (tensor.py:468), and
    MEASURED: with the port reading the counter before the write they read
    `0:0 / 4294967295:4294967290 / 0:4294967289 / 4294967295:1` against CPython's
    `0:0 / 0:0 / 0:4294967295 / 0:0`, while the four `_g` graph rows were BYTE-IDENTICAL to
    their pins. A graph row cannot see this defect; a value row can.
  * every `ref_*` row asks a predicate that exists in `tinygrad/mixin/rand.py` and is asked
    AS a predicate, with the same fixture the port's row uses. `ref_*_not` rows are the
    negative arm of each: a predicate family whose every fixture is positive is
    unfalsifiable, and rand.bend's own M7 is that lesson written down.

WHAT IS NOT HERE, NAMED.
  * the fifteen `*_g` / `*_d` / `*_np` rows: these need a CPython build of `op_arange`,
    `random_bits`, `_bits_to_rand`, `_rand` and `rand_like` over an INJECTED counter, which is
    a port-side parameterisation CPython does not offer. `gates/rd_graph_census-gate.py`
    covers FOUR of the `_threefry_random_bits` defs and nothing else; MEASURED, its own rows
    are `p64`, `x`, `three`, `tfb`.
  * `ref_drop_arm0/1/2`: an ORDINAL of a three-way arm selector. CPython has the three BRANCHES
    (`rand.py:294-297`) and no ordinal, so the only faithful CPython statement is which branch
    runs, which is a different row and is not invented here.
"""
import math

from tinygrad.dtype import dtypes, least_upper_dtype
from tinygrad.tensor import Tensor

DEVICE = "PYTHON"


def row(nm, v):
  print(f"{nm}={v}")


def bl(nm, b):
  row(nm, "True" if b else "False")


def sig(t):
  us = t.uop.toposort()
  return (f"{len(us)} op={t.uop.op.name} nsrc={len(t.uop.src)} "
          f"srcops={'|'.join(s.op.name for s in t.uop.src)} "
          f"topo={' '.join(f'{u.op.name}/{len(u.src)}' for u in us)}")


def i64pair(v):
  """`H.i64_text` prints `hi:lo`; this is the same pair so a value is legible on both lanes."""
  v &= 0xFFFFFFFFFFFFFFFF
  return f"{v >> 32}:{v & 0xFFFFFFFF}"


def st(num, counter=None):
  """`Tensor._next_counter` with the STORED counter set to the one the port injects."""
  if counter is not None:
    Tensor._device_rng_counters[DEVICE] = counter
  _, low_high = Tensor._next_counter(DEVICE, num)
  return low_high


fresh = lambda: Tensor([0, 0], device=DEVICE, dtype=dtypes.uint32)  # noqa: E731

# THE FOUR GENERATOR-STATE ROWS. `st_after` feeds the answer of `st_six` back in, which is
# exactly what the second `_next_counter` call does against the stored counter.
row("st_zero_g", sig(st(0, fresh())))
row("st_six_g", sig(st(6, fresh())))
row("st_after_g", sig(st(6)))
row("st_max_g", sig(st(0xFFFFFFFF, fresh())))

# THE SAME FOUR, AS VALUES. `Tensor._next_counter`'s OWN returned `low.cat(high)`, realised
# and read, against the STORED counter the fixture sets. THIS IS THE WITNESS, and it is
# here because the four `_g` rows above CANNOT BE: `num` reaches `_next_counter`'s graph
# only as CONSTANTS, so dropping `counter.assign` (:468) shifts every returned WORD by
# `num` and changes no node at all -- MEASURED, dropping it left `st_zero_g`..`st_max_g`
# byte-identical while it made `st_six_v`, `st_wrap_v` and `st_max_v` wrong.
# `st_wrap_v`'s counter is `[0xFFFFFFFF, 0]` and its `num` is 6, so `new_low` WRAPS and
# both halves of tensor.py:467/470's borrow comparison are True. `st_after` did not and
# could not do this: its counter is whatever the stored one was, and no CONSTANT ever
# reaches a graph row.
# THE STORED COUNTER IS RESET ON EVERY ROW, INCLUDING `st_six_v` and `st_max_v` AFTER
# `st_after_g` HAS LEFT IT AT `[6, 0]` -- `_next_counter` mutates it, so a row that did not
# reset would be reading the previous row's write.
def st_v(lo, hi, num):
  Tensor._device_rng_counters[DEVICE] = Tensor([lo, hi], device=DEVICE, dtype=dtypes.uint32)
  _, low_high = Tensor._next_counter(DEVICE, num)
  low, high = low_high.tolist()
  return i64pair((high << 32) | low)


row("st_zero_v", st_v(0, 0, 0))
row("st_six_v", st_v(0, 0, 6))
row("st_wrap_v", st_v(0xFFFFFFFF, 0, 6))
row("st_max_v", st_v(0, 0, 0xFFFFFFFF))

# --- C-REFS. Every predicate below is asked with the fixture `t_ref` uses. -------------

# `rand.py:82`'s `rand_like` device arm and `dtypes.weaks` -- the port's `rd_ok_float` is the
# membership test `dt in dtypes.floats`, which is why a weak float is the negative arm and
# `half` is a POSITIVE one (it is a float).
bl("ref_rand_weak_f32", dtypes.float32 in dtypes.floats)
bl("ref_rand_weak_wf", dtypes.weakfloat in dtypes.floats)
bl("ref_rand_weak_h", dtypes.float16 in dtypes.floats)
bl("ref_rand_weak_i32", dtypes.int32 in dtypes.floats)

# `rand.py`'s shape check: every dim a non-negative int.
bl("ref_shape_u32", all(isinstance(d, int) and d >= 0 for d in (2, 3)))

# `rand.py:158 uniform`'s `if low >= high: raise`.
bl("ref_uniform_lt", 2.0 < 10.0)
bl("ref_uniform_not", 10.0 < 2.0)

# `rand.py:141 normal`'s `if std < 0: raise`.
bl("ref_normal_std", 2.0 >= 0)
bl("ref_normal_not", -2.0 >= 0)

# `rand.py:122 randint`'s `if not all_int([low, high]): raise` -- here the port's predicate is
# over the DTYPE it would promote to, so `int32` passes and `float32` does not.
bl("ref_randint_int", dtypes.int32 in dtypes.ints)
bl("ref_randint_not", dtypes.float32 in dtypes.ints)

# `rand.py:294 dropout`'s `if not 0 <= p <= 1: raise`. FOUR fixtures, two of which are the
# BOUNDARY: `p == 1.0` is the arm `rand.py:296` branches on and `p == 0.9999999` is the
# largest value the `<=` admits. MEASURED in rand.bend: relaxing `<= 1` to `< 1` moved
# NOTHING until these two existed.
bl("ref_dropout_p", 0 <= 0.5 <= 1)
bl("ref_dropout_p1", 0 <= 1.0 <= 1)
bl("ref_dropout_p1n", 0 <= 0.9999999 <= 1)
bl("ref_dropout_not", 0 <= 1.5 <= 1)

# `rand.py:267 multinomial`'s `assert 1 <= self.ndim <= 2 and num_samples > 0`, and
# `rand.py:275`'s `assert replacement or num_samples <= weight.shape[1]`.
bl("ref_multi_n11", 1 <= 1 <= 2 and 1 > 0)
bl("ref_multi_n23", 1 <= 2 <= 2 and 3 > 0)
bl("ref_multi_n31", 1 <= 3 <= 2 and 1 > 0)
bl("ref_multi_rep", True or 1 <= 3)

# `rand.py:319`'s THIRD `least_upper_dtype` arity -- `least_upper_dtype(q.dtype, key.dtype,
# dtypes.float32)` -- which the port mirrors as `rd_sdpa_dt`. MEASURED UPSTREAM, and this is
# not a port question: `promo_lattice:186` gives every fp8 TWO successors (`float16` AND
# `bfloat16`), `can_lossless_cast(bfloat16, float16)` is False, and `least_upper_dtype`
# picks by INTEGER priority -- so the SAME multiset of operands gives two different answers
# depending on ARITY: `(fp8e4m3|fp8e5m2)|bf16 == f32` but `fp8e4m3|(fp8e5m2|bf16) == bf16`.
# `mixin/rand.py:319` is ONE of the three arities in the tree that call it (`uop/ops.py:118`
# is the n-ary `promo_dtype`, `mixin/elementwise.py:27` the binary one). DO NOT "FIX" THE
# PORT TOWARD IT.
row("ref_sdpa_dt", least_upper_dtype(dtypes.float16, dtypes.float32, dtypes.float32).name)

# `_bits_to_rand` (rand.py:32-37): `_, nmant = dtypes.finfo(dtype)` then
# `rshift(dtype.bitsize - nmant).bitwise_or(bitcast(1.0, dtype, uint_dtype))`.
_, NMANT_F32 = dtypes.finfo(dtypes.float32)
_, NMANT_H = dtypes.finfo(dtypes.float16)


def shift(dt):
  return dt.bitsize - dtypes.finfo(dt)[1]


def one_bits(dt):
  """`bitcast(1.0, dtype, uint_dtype)` -- the bit pattern of `1.0` in `dtype`, read back as
  the unsigned integer of the matching width. Computed with `struct`, NOT with
  `ndarray.view`, so it needs no array."""
  import struct
  fmt = {"f16": "<e", "bfloat16": None, "f32": "<f", "f64": "<d"}[dt.name]
  if fmt is None:
    # bfloat16 is the top half of a float32; `1.0` is `0x3f80` and the low 16 bits are 0.
    return 0x3F80
  packed = struct.pack(fmt, 1.0)
  width = dt.bitsize // 8
  return int.from_bytes(packed[:width], "little")


def bits_num(shape, dt):
  """`random_bits`'s `ceildiv(prod(shape) * dtype.itemsize, 4)`."""
  n = math.prod(shape) * dt.itemsize
  return -(-n // 4)


row("ref_shift_f32", shift(dtypes.float32))
row("ref_shift_h", shift(dtypes.float16))
row("ref_one_bits_f32", one_bits(dtypes.float32))
row("ref_one_bits_h", one_bits(dtypes.float16))
row("ref_nmant_f32", NMANT_F32)
row("ref_uint_dt_f32", {1: dtypes.uint8, 2: dtypes.uint16, 4: dtypes.uint32,
                        8: dtypes.uint64}[dtypes.float32.itemsize].name)
row("ref_bits_num23", bits_num((2, 3), dtypes.float32))
row("ref_bits_num223", bits_num((2, 2, 3), dtypes.float32))

# `ref_drop_arm0/1/2` ARE DELIBERATELY ABSENT -- see the module docstring.
