#!/usr/bin/env python3
"""llm_ggml-fixture.py -- the `.gguf` whose blocks `gates/llm_ggml.bend` decodes.

    .venv/bin/python gates/llm_ggml-fixture.py           # rewrite it
    .venv/bin/python gates/llm_ggml-fixture.py --sha     # print its sha256

A REAL GGUF, DELIBERATELY. The .bend lane finds each block the way `gguf_load` would --
`gguf_parse` gives the offset and the length, the slice gives the bytes -- so the gate
measures the DECODE and the byte geometry together, and no offset is transcribed on
either side.

THE PAYLOADS ARE CURATED WHERE ARITHMETIC WOULD HIDE A DEFECT and pseudo-random where it
would not:
  * every f16/bf16 field is a chosen bit pattern (denormal, max, -0, sign) and NEVER a
    NaN or an infinity, because `DT.fp16_f32` and CPython may canonicalise a NaN payload
    differently and that is a fact about NaN, not about this port;
  * every quant block's SCALE field is a chosen finite f16, for the same reason: a NaN
    scale makes every element NaN and the row would then compare NaN payloads;
  * the quant PAYLOAD bytes are pseudo-random, so any nibble-order or sub-block-index
    error lands on a value that differs.
"""
import hashlib
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "llm_ggml-fixture.gguf"

F32 = (0x3F800000, 0xBF800000, 0x3F000000, 0x40490FDB, 0x00000001, 0x80000000,
       0x7F7FFFFF, 0x00000000, 0xC0490FDB, 0x461C4000, 0x3DCCCCCD, 0x42F6E979,
       0x33800000, 0xB3000000, 0x4B000000, 0x4E800000)
F16 = (0x0001, 0x03FF, 0x0400, 0x3555, 0x3C00, 0xBC00, 0x7BFF, 0x8000)
BF16 = (0x0001, 0x3F80, 0xBF80, 0x7F7F, 0x8000, 0x4048, 0x0000, 0x3F00)

D_ONE = 0x3C00        # 1.0
D_K = 0x3800          # 0.5
DMIN_K = 0x3400       # 0.25

# `kvalues_iq4nl` -- ggml-common.h's sixteen int8s, the whole "grid" of IQ4_NL.
KVALUES = (-127, -104, -83, -65, -49, -35, -22, -10, 1, 13, 25, 38, 53, 69, 89, 113)

# `_ggml_iq_grid`'s synthetic subject: FOUR entries of eight bytes, as the two 32-bit
# words per entry that `gguf.py:13` splits them into.
GRID_WORDS = (0x04030201, 0x08070605, 0x0C0B0A09, 0x100F0E0D,
              0x14131211, 0x18171615, 0x1C1B1A19, 0x201F1E1D)

# (name, dims, ggml_type) -- `prod(dims)` IS the element count `ggml_data_to_tensor` takes.
TENSORS = (
  ("f32.w", (16,), 0),
  ("f16.w", (8,), 1),
  ("bf16.w", (8,), 30),
  ("q4_0.w", (32,), 2),
  ("q8_0.w", (32,), 8),
  ("iq4nl.w", (32,), 20),
  ("q4k.w", (256,), 12),
)

NATIVE = {0: 4, 1: 2, 24: 1, 25: 2, 26: 4, 27: 8, 28: 8, 30: 2}
QUANT = {2: (32, 18), 3: (32, 20), 6: (32, 22), 7: (32, 24), 8: (32, 34),
         10: (256, 84), 11: (256, 110), 12: (256, 144), 13: (256, 176), 14: (256, 210),
         16: (256, 66), 17: (256, 74), 18: (256, 98), 19: (256, 50), 20: (32, 18),
         21: (256, 110), 22: (256, 82), 23: (256, 136), 29: (256, 56), 39: (32, 17),
         41: (128, 18)}

# WHICH CODES THIS GATE COVERS, by name, in both lanes. It is a PORT decision and not an
# upstream fact, so each side states it and the two must agree -- bend2-constraints'
# "two independent transcriptions of the same table that AGREE".
SUPPORTED = {0: "f32", 1: "f16", 2: "Q4_0", 8: "Q8_0", 12: "Q4_K", 20: "IQ4_NL",
             30: "bf16"}

NCODES = 46

# THE ROW SET, as arithmetic over the lists above: ONE `v_*` row per tensor (all of its
# decoded values), then `iqs`, `grid`, `lut` and `err`, then one `ty_*` row per ggml type
# code. A fourteenth tensor is one row on all three of `rows`, the FILE, and the lanes.
ROWS = len(TENSORS) + 4 + NCODES


def body(typ, dims):
    n = 1
    for d in dims: n *= d
    if typ in NATIVE: return n * NATIVE[typ]
    return n // QUANT[typ][0] * QUANT[typ][1]


def payload(typ, dims):
    """The block bytes, curated where the schema says so and pseudo-random elsewhere."""
    if typ == 0: return b"".join(struct.pack("<I", v) for v in F32)
    if typ == 1: return b"".join(struct.pack("<H", v) for v in F16)
    if typ == 30: return b"".join(struct.pack("<H", v) for v in BF16)
    if typ in (2, 8, 20):
        return struct.pack("<H", D_ONE) + bytes((i * 37 + 11) & 0xFF for i in range(body(typ, dims) - 2))
    if typ == 12:
        return (struct.pack("<HH", D_K, DMIN_K)
                + bytes((i * 37 + 11) & 0xFF for i in range(body(typ, dims) - 4)))
    raise ValueError(typ)


def s(text):
    b = text.encode("utf-8")
    return struct.pack("<Q", len(b)) + b


def build():
    align, kv = 32, (("general.architecture", 8, "llamatest"),)
    head = b"GGUF" + struct.pack("<i", 3) + struct.pack("<q", len(TENSORS)) + struct.pack("<q", len(kv))
    for k, code, v in kv:
        head += s(k) + struct.pack("<i", code) + s(v)
    offsets, off = [], 0
    for name, dims, typ in TENSORS:
        offsets.append(off)
        off = (off + body(typ, dims) + align - 1) // align * align
    for (name, dims, typ), off in zip(TENSORS, offsets):
        head += s(name) + struct.pack("<I", len(dims))
        head += b"".join(struct.pack("<Q", d) for d in dims)
        head += struct.pack("<i", typ) + struct.pack("<Q", off)
    head += b"\x00" * ((-len(head)) % align)
    data = b"".join(payload(typ, dims) + b"\x00" * ((-body(typ, dims)) % align)
                    for _, dims, typ in TENSORS)
    return head + data


def main():
    blob = build()
    if "--sha" in sys.argv:
        print(hashlib.sha256(blob).hexdigest())
        return 0
    FIXTURE.write_bytes(blob)
    print(f"{FIXTURE.name}: {len(blob)} bytes, sha256 {hashlib.sha256(blob).hexdigest()}")
    print(f"rows={ROWS}")
    print("kvalues_iq4nl as U32 two's complement:",
          " ".join(str(v & 0xFFFFFFFF) for v in KVALUES))
    print("grid words:", " ".join(str(w) for w in GRID_WORDS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
