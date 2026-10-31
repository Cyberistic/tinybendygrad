#!/usr/bin/env python3
"""llm_gguf-fixture.py -- the three `.gguf` files `gates/llm_gguf-gate.py` parses, BUILT HERE.

    .venv/bin/python gates/llm_gguf-fixture.py            # rewrite them
    .venv/bin/python gates/llm_gguf-fixture.py --sha      # print their sha256s

THE FIXTURES ARE A GENERATOR'S OUTPUT, NOT A HAND LIST. `gates/llm_gguf-gate.py` takes
its ROW COUNT from `ROWS` below -- derived from `KV` and `TENSORS`, which are the very
lists this file writes -- so the count cannot drift from the file. The gate also pins
each file's sha256, because a parse gate whose input can move is a gate on nothing.

WHAT IT COVERS, and every entry is here because a row needs it:
  * all THIRTEEN `readers` types of gguf.py:193-195, including type 0 (`bytes`, one
    byte), 7 (`bool`), 8 (`str`, with 2-, 3- and 4-byte UTF-8 sequences) and 9 (`array`
    of str, of i32 and of f32);
  * `general.alignment` PRESENT and 32, so `gguf_parse:224` rounds a non-zero
    remainder instead of an identity;
  * three tensors: a NATIVE f32, a NATIVE f16 whose dims make `prod` non-trivial, and a
    QUANTISED Q4_K whose dims are exactly one block, so `prod//block*size` is exact;
  * 64-bit metadata whose high word is NOT zero (`t.u64`, `t.i64`), so a port that read
    only the low word diverges rather than passing;
  * an f64 whose bits are not an exact f32, so `GVF64`'s eight bytes are load-bearing;
  * TWO BROKEN FILES, one per `gguf_parse` raise: `badmeta` puts 13 in a metadata type
    (CPython's uncaught `KeyError`) and `badtype` puts 99 in a tensor's ggml type
    (`ValueError: GGML type '99' is not supported!`).
"""
import hashlib
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GOOD = HERE / "llm_gguf-fixture.gguf"
BADMETA = HERE / "llm_gguf-badmeta.gguf"
BADTYPE = HERE / "llm_gguf-badtype.gguf"

# (key, type code, value) in FILE ORDER -- `gguf_parse` answers a dict in insertion
# order and the gate prints the keys in that order, so the order is the row order.
KV = (
  ("general.architecture", 8, "llama"),
  ("general.name", 8, "tinybendygrad\u00b7\u2713\U0001f9ea"),
  ("general.alignment", 4, 32),
  ("llama.block_count", 4, 2),
  ("llama.attention.head_count", 4, 4),
  ("t.u8", 0, 0xFF),
  ("t.i8", 1, -7),
  ("t.u16", 2, 65535),
  ("t.i16", 3, -300),
  ("t.i32", 5, -70000),
  ("t.u64", 10, (1 << 40) + 5),
  ("t.i64", 11, -3),
  ("t.f32", 6, 1.5),
  ("t.f64", 12, -0.1),
  ("t.bool_t", 7, True),
  ("t.bool_f", 7, False),
  ("tokenizer.ggml.tokens", 9, (8, ("a", "\u00e9", "\U0001f9ea"))),
  ("t.ints", 9, (5, (-1, 0, 2147483647))),
  ("t.f32s", 9, (6, (0.5, -2.0))),
)

# (name, dims, ggml_type) -- dims in FILE ORDER (`gguf_parse` reverses them).
TENSORS = (
  ("blk.0.attn_norm.weight", (100,), 0),
  ("blk.0.ffn_up.weight", (32, 64), 1),
  ("blk.0.q4k.weight", (256,), 12),
)

NATIVE = {0: 4, 1: 2, 24: 1, 25: 2, 26: 4, 27: 8, 28: 8, 30: 2}
QUANT = {2: (32, 18), 3: (32, 20), 6: (32, 22), 7: (32, 24), 8: (32, 34),
         10: (256, 84), 11: (256, 110), 12: (256, 144), 13: (256, 176), 14: (256, 210),
         16: (256, 66), 17: (256, 74), 18: (256, 98), 19: (256, 50), 20: (32, 18),
         21: (256, 110), 22: (256, 82), 23: (256, 136), 29: (256, 56), 39: (32, 17),
         41: (128, 18)}

# THE ROW SET, AS AN ARITHMETIC OVER THE TWO LISTS ABOVE. The gate reads THIS, so a
# fourteenth kv pair is one row on all three of `rows`, the FILE, and the lanes.
NCODES = 46          # ggml type codes 0..45: 42 are in the tables and 4 are holes
FMTCODES = 16        # metadata type codes 0..15: 13 are in `readers` and 3 are holes
ROWS = (5                                  # fx_len fx_sum n_kv n_ts ds
        + 1 + len(KV)                      # kvseq, then one row per kv pair
        + 4                                # align, align_none, align_one, tseq
        + len(TENSORS)                     # one row per tensor
        + 5                                # err_good err_magic err_ver err_blk err_meta
        + FMTCODES + 2 * NCODES)           # fmt_*, nat_*, qnt_*


def s(text):
    b = text.encode("utf-8")
    return struct.pack("<Q", len(b)) + b


def val(code, v):
    """One metadata value, in `readers`' spelling (gguf.py:193-195)."""
    if code == 8: return s(v)
    if code == 9:
        sub, items = v
        return struct.pack("<iQ", sub, len(items)) + b"".join(val(sub, x) for x in items)
    if code == 0: return struct.pack("<B", v)
    if code == 1: return struct.pack("<b", v)
    if code == 2: return struct.pack("<H", v)
    if code == 3: return struct.pack("<h", v)
    if code == 4: return struct.pack("<I", v)
    if code == 5: return struct.pack("<i", v)
    if code == 6: return struct.pack("<f", v)
    if code == 7: return struct.pack("<?", v)
    if code == 10: return struct.pack("<Q", v)
    if code == 11: return struct.pack("<q", v)
    if code == 12: return struct.pack("<d", v)
    raise ValueError(code)


def nbytes(typ, dims):
    """`prod(dims)//block*size`, gguf.py:226-229."""
    n = 1
    for d in dims: n *= d
    if typ in NATIVE: return n * NATIVE[typ]
    return n // QUANT[typ][0] * QUANT[typ][1]


def build(meta_bad=False, ten_bad=False):
    align = 32
    for k, _, v in KV:
        if k == "general.alignment": align = v
    head = b"GGUF" + struct.pack("<i", 3) + struct.pack("<q", len(TENSORS)) + struct.pack("<q", len(KV))
    for i, (k, code, v) in enumerate(KV):
        head += s(k) + struct.pack("<i", 13 if (meta_bad and i == 0) else code) + val(code, v)
    offsets, off = [], 0
    for name, dims, typ in TENSORS:
        offsets.append(off)
        off = (off + nbytes(typ, dims) + align - 1) // align * align
    for (name, dims, typ), off in zip(TENSORS, offsets):
        head += s(name) + struct.pack("<I", len(dims))
        head += b"".join(struct.pack("<Q", d) for d in dims)
        head += struct.pack("<i", 99 if (ten_bad and name == "blk.0.q4k.weight") else typ)
        head += struct.pack("<Q", off)
    head += b"\x00" * ((-len(head)) % align)
    data = b""
    for name, dims, typ in TENSORS:
        chunk = bytes((i * 7 + 3) & 0xFF for i in range(nbytes(typ, dims)))
        data += chunk + b"\x00" * ((-len(chunk)) % align)
    return head + data


def main():
    files = ((GOOD, build()), (BADMETA, build(meta_bad=True)), (BADTYPE, build(ten_bad=True)))
    if "--sha" in sys.argv:
        for p, blob in files: print(f"{p.name} {hashlib.sha256(blob).hexdigest()}")
        return 0
    for p, blob in files:
        p.write_bytes(blob)
        print(f"{p.name}: {len(blob)} bytes, sha256 {hashlib.sha256(blob).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
