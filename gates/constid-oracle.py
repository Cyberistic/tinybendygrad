#!/usr/bin/env python3
"""constid-oracle.py -- CPython's answers to `gates/constid.bend`'s seven rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/constid-oracle.py

THE COUNTING IS THE POINT, and it is the same counting on both sides.  Upstream's hash
table is `UOpMetaClass.ucache` (`ops.py:199-202`) and its key is

    (op, src, arg, tag, type(arg))

so "TWO KEYS IN ONE HASH TABLE" is measured here by putting the two CONST nodes' OWN key
tuples into ONE dict and counting the entries -- upstream's key, upstream's dict.  The port's
hash table is the ARENA, and its count is the number of distinct CONST nodes in it.

EVERY ROW is a question CPython can be asked directly; none of them is a transcription of a
number the port produced.

THE THREE DECLARED DIVERGENCES, and what each one is:

    merge_keys         0.1 and 0.10000000149011612 are TWO CONSTs upstream -- two doubles,
                       two `ConstFloat.bits` (`dtype.py:8-25`), two `hash`es -- and ONE in
                       the port, because the f32 nearest 0.1 IS the f32 nearest
                       0.10000000149011612.
    merge_keys_int     the same, for the pair whose VALUE the port's own formatter can see:
                       16777217.0 and 16777216.0 are two doubles upstream
                       (`0x4170000010000000` and `0x4170000000000000`) and one f32 here.
    merge_value_text   the constant HOLDS a different NUMBER: upstream holds the double
                       16777217.0, the port holds the f32 of it, which is 16777216.0.
"""
import struct
import sys

from tinygrad.dtype import ConstFloat, dtypes
from tinygrad.uop.ops import UOp, Ops


def const_node(u: UOp) -> UOp:
    """The CONST under a `UOp.const` result: bare for weakfloat, CASTed for every other dtype."""
    n = u
    while n.op is Ops.CAST:
        n = n.src[0]
    return n


def ucache_key(u: UOp):
    """Upstream's OWN `ucache` key for the CONST under `u` (`ops.py:201`)."""
    n = const_node(u)
    return (n.op, n.src, n.arg, n.tag, type(n.arg))


def keys_in_one_table(*us: UOp) -> int:
    """THE COUNT: the number of entries in ONE dict keyed by upstream's own key tuples."""
    d = {}
    for u in us:
        d[ucache_key(u)] = True
    return len(d)


def f32bits(v: float) -> int:
    return struct.unpack("<I", struct.pack("<f", v))[0]


def double_nan(bits: int) -> float:
    return struct.unpack("<d", struct.pack("<Q", bits))[0]


def main() -> None:
    # THE NAN PAYLOADS.  `0x7FF8000000000000` is `math.nan` -- the payload upstream's
    # `DType.const` canonicalises to (`dtype.py:81-82`), so it is the REACHABLE one.
    nan_p1 = ConstFloat(double_nan(0x7FF8000000000000))
    nan_p2 = ConstFloat(double_nan(0x7FF0000000000001))

    rows = (
        # 1: the f32 of 0.1 -- the port's 32 bits ARE the f32 of upstream's value.
        ("merge_f32_bits", f32bits(0.1)),
        # 2: THE CONTROL.  Two constants upstream keeps apart are two keys, so a count that
        #    reads 1 for every pair is a count that measured nothing.
        ("merge_keys_control", keys_in_one_table(UOp.const(0.1, dtypes.weakfloat),
                                                 UOp.const(0.5, dtypes.weakfloat))),
        # 3: the same nan payload twice is ONE key.  The reason is `__hash__` (`hash(self.bits)`),
        #    NOT `__eq__` -- and `__eq__` is what says two DIFFERENT payloads are equal.
        ("split_keys_same", keys_in_one_table(UOp(Ops.CONST, src=(), arg=nan_p1),
                                               UOp(Ops.CONST, src=(), arg=nan_p1))),
        # 4: the REACHABLE nan.  `DType.const` canonicalises a nan to `math.nan`, so both of
        #    these carry the SAME payload and are one key -- as they are in the port.
        ("split_keys_reachable", keys_in_one_table(UOp.const(float("nan"), dtypes.float32),
                                                   UOp.const(float("nan"), dtypes.weakfloat))),
        # 5-7: THE THREE DECLARED DIVERGENCES.
        ("merge_keys", keys_in_one_table(UOp.const(0.1, dtypes.weakfloat),
                                         UOp.const(0.10000000149011612, dtypes.weakfloat))),
        ("merge_keys_int", keys_in_one_table(UOp.const(16777217.0, dtypes.weakfloat),
                                              UOp.const(16777216.0, dtypes.weakfloat))),
        ("merge_value_text", f"{float(UOp.const(16777217.0, dtypes.weakfloat).arg):.6f}"),
    )
    for name, value in rows:
        print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
