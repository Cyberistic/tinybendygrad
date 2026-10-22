#!/usr/bin/env python3
"""oracle.py -- CPython's answers to the two CONST-IDENTITY divergences.

Run:  .venv/bin/python .agents/slop/constid/oracle.py

THE MERGE: upstream keeps `0.1` (a double) and `0.10000000149011612` (the f32 nearest 0.1)
apart -- different doubles, so different `ConstFloat.bits`, so different hashes, so two keys
in upstream's `ucache`.

THE SPLIT: upstream's `ConstFloat.__eq__` says `nan == nan` for ANY two nans, while
`ConstFloat.__hash__` is `hash(self.bits)`, so two nans with DIFFERENT payloads have
DIFFERENT hashes.  This file measures both halves of that, and -- the part that decides
whether the port is wrong -- what upstream's OWN HASH TABLE does with them.

Every number printed here is measured; nothing is read off a diff.
"""
import struct
import sys

from tinygrad.dtype import ConstFloat, dtypes
from tinygrad.uop.ops import UOp, Ops


def bits(v: float) -> int:
    return struct.unpack("<Q", struct.pack("<d", v))[0]


def f32bits(v: float) -> int:
    return struct.unpack("<I", struct.pack("<f", v))[0]


def row(k, v):
    print(f"{k}={v}")


def main():
    print("# --- THE MERGE: upstream keeps two doubles apart ---")
    a, b = 0.1, 0.10000000149011612
    ca, cb = ConstFloat(a), ConstFloat(b)
    row("up_double_0p1_bits", hex(ca.bits))
    row("up_double_0p1_f32bits", hex(f32bits(a)))
    row("up_double_0p1neighbour_bits", hex(cb.bits))
    row("up_double_0p1neighbour_f32bits", hex(f32bits(b)))
    row("up_double_bits_differ", ca.bits != cb.bits)
    row("up_double_hash_differ", hash(ca) != hash(cb))
    row("up_double_eq", ca == cb)
    # the f32 nearest 0.1 IS b, so b is what an f32 const holds upstream
    row("up_f32nearest_is_neighbour", f32bits(a) == f32bits(b))

    print("# --- THE MERGE: the CONST nodes upstream's ucache mints ---")
    # weakfloat keeps the double; float32 truncates to the f32 and then the CONST is CAST.
    w_a = UOp.const(a, dtypes.weakfloat)
    w_b = UOp.const(b, dtypes.weakfloat)
    f_a = UOp.const(a, dtypes.float32)
    f_b = UOp.const(b, dtypes.float32)
    row("up_weakfloat_a_arg_bits", hex(w_a.arg.bits))
    row("up_weakfloat_b_arg_bits", hex(w_b.arg.bits))
    row("up_f32_a_arg_bits", hex(f_a.src[0].arg.bits))
    row("up_f32_b_arg_bits", hex(f_b.src[0].arg.bits))
    row("up_weakfloat_a_is_b", w_a is w_b)
    row("up_f32_a_is_b", f_a is f_b)
    row("up_weakfloat_a_is_f32_a", w_a is f_a)
    # the two CONST ARG VALUES that upstream distinguishes
    row("up_distinct_const_args", len({w_a.arg.bits, w_b.arg.bits}))
    # a dict over upstream's own key shape
    d = {w_a.arg: "a", w_b.arg: "b"}
    row("up_dict_of_two_doubles", len(d))
    # the ucache itself
    key_a = (Ops.CONST, (), w_a.arg, None, type(w_a.arg))
    key_b = (Ops.CONST, (), w_b.arg, None, type(w_b.arg))
    row("up_ucache_keys_differ", hash(key_a) != hash(key_b))

    print("# --- THE SPLIT: two nan payloads ---")
    p1 = 0x7FF8000000000000  # math.nan / the quiet nan
    p2 = 0x7FF0000000000001  # a signalling nan with a payload
    n1 = struct.unpack("<d", struct.pack("<Q", p1))[0]
    n2 = struct.unpack("<d", struct.pack("<Q", p2))[0]
    cn1, cn2 = ConstFloat(n1), ConstFloat(n2)
    row("up_nan_p1_bits", hex(cn1.bits))
    row("up_nan_p2_bits", hex(cn2.bits))
    row("up_nan_bits_differ", cn1.bits != cn2.bits)
    row("up_nan_eq", cn1 == cn2)              # ConstFloat.__eq__ -> nan == nan
    row("up_nan_hash_differ", hash(cn1) != hash(cn2))  # ConstFloat.__hash__ -> hash(bits)
    # THE DECIDING MEASUREMENT: upstream's own hash table
    dn = {cn1: "p1", cn2: "p2"}
    row("up_dict_two_nan_payloads", len(dn))
    dn2 = {cn1: "p1", ConstFloat(n1): "p1-again"}
    row("up_dict_same_nan_payload", len(dn2))
    # and in the ucache
    k1 = (Ops.CONST, (), cn1, None, type(cn1))
    k2 = (Ops.CONST, (), cn2, None, type(cn2))
    row("up_ucache_two_nan_payloads", len({k1, k2}))

    print("# --- THE SPLIT: what the REACHABLE const path does with a nan ---")
    # dtype.py:81-82 canonicalises a nan to math.nan BEFORE ConstFloat wraps it
    row("up_const_nan_arg_bits", hex(UOp.const(float("nan"), dtypes.float32).src[0].arg.bits))
    row("up_const_nan2_arg_bits", hex(UOp.const(n2, dtypes.float32).src[0].arg.bits))
    row("up_const_nan_canonicalised",
        UOp.const(float("nan"), dtypes.float32).src[0].arg.bits
        == UOp.const(n2, dtypes.float32).src[0].arg.bits)
    row("up_const_nan_is_one_node",
        UOp.const(float("nan"), dtypes.float32) is UOp.const(n2, dtypes.float32))
    # and the f32 of a nan
    row("up_f32_nan_bits", hex(f32bits(float("nan"))))
    row("up_f32_nan2_bits", hex(f32bits(n2)))
    row("up_f32_nan_payloads_differ", f32bits(float("nan")) != f32bits(n2))

    print("# --- THE WALL: what a double would take upstream ---")
    row("up_f64_const_bits", hex(UOp.const(a, dtypes.float64).src[0].arg.bits))
    row("up_weakfloat_const_bits", hex(UOp.const(a, dtypes.weakfloat).arg.bits))
    row("up_f64_is_weakfloat_arg",
        UOp.const(a, dtypes.float64).src[0].arg.bits == UOp.const(a, dtypes.weakfloat).arg.bits)
    # the value the const HOLDS, which is the graph-visible half
    row("up_weakfloat_value", repr(float(UOp.const(a, dtypes.weakfloat).arg)))
    row("up_f32_value", repr(float(UOp.const(a, dtypes.float32).src[0].arg)))
    row("up_f64_value", repr(float(UOp.const(a, dtypes.float64).src[0].arg)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
