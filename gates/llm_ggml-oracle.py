#!/usr/bin/env python3
"""llm_ggml-oracle.py -- CPython's answers to `gates/llm_ggml.bend`'s 57 rows.

The two lanes share no code: the Bend lane finds each block through the PORT's
`gguf_parse`, slices `start..start+nbytes` and decodes it with the port's `ggml.dec`; this
lane hands the same bytes to UPSTREAM's `ggml_data_to_tensor` and prints `tolist()`.

WHY `tolist()` AND NOT A `Tensor` COMPARISON. The subject of the gate is the DECODE, and
`Tensor.tolist()` is the one place upstream states the decoded numbers without a device,
a kernel or a dtype object in between. `ggml_data_to_tensor` returns a `Tensor`; the
port returns a `List<&2, F32>`. The numbers are the comparison.

BITS, NOT DECIMALS. Every value prints as its IEEE-754 f32 bit pattern, because neither
lane can print a float exactly and the bits are the value: `struct.pack("<f", x)` is exact
for the f32 that `tolist()` already produced.

THE TWO `ggml_common` CONSTANTS ARE ARGUMENTS IN THE PORT AND OBJECTS HERE.
`iq.signs` is not: `gguf.py:17` COMPUTES the 128 sign bytes, and so does the port, so this
lane calls `_ggml_iq_signs` and compares two computations. `_ggml_iq_grid` is called with
the SAME four-entry synthetic grid both lanes use.
"""
import importlib.util
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FX = load("llm_ggml_fixture", "llm_ggml-fixture.py")
from tinygrad import Tensor, dtypes
from tinygrad.llm.gguf import ggml_data_to_tensor, gguf_parse, _GGML_NATIVE, _GGML_QUANT
from tinygrad.llm import gguf as U
from tinygrad.runtime.autogen import ggml_common as GC


def fnv(ws):
    """FNV-1a 32, the same fold `gates/llm_ggml.bend`'s `hfnv` runs over the same words."""
    h = 2166136261
    for w in ws:
        h = ((h ^ (w & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    return h


def grow(name, ws):
    return (f"g_{name}={len(ws)}w:{fnv(ws)}:"
            + ",".join(str(w) for w in ws[:4]) + ":"
            + ",".join(str(w) for w in ws[-4:]))


def bits(v):
    return str(struct.unpack("<I", struct.pack("<f", float(v)))[0])


def flatten(xs):
    out = []
    for x in xs:
        out.extend(flatten(x)) if isinstance(x, list) else out.append(x)
    return out


def values(path):
    """`(name, ggml_type, values)` per tensor, in FILE ORDER."""
    _, sd = gguf_parse(Path(path))
    out = []
    for name, (t, shape, typ) in sd.items():
        n = 1
        for d in shape: n *= d
        out.append((name, typ, flatten(ggml_data_to_tensor(t.to('CPU'), n, typ).tolist())))
    return out


def err():
    try:
        ggml_data_to_tensor(Tensor([0, 0], dtype=dtypes.uint8), 1, 99)
    except ValueError as e:
        return str(e)
    return "none"


def main():
    # THE CONTROL. The four-entry grid this lane hands `_ggml_iq_grid` IS the port's
    # eight words, joined two-at-a-time -- so a transcription slip in `gates/llm_ggml.bend`
    # changes BOTH the grid argument and nothing else, and this assertion catches it.
    entries = tuple(FX.GRID_WORDS[2 * r] | (FX.GRID_WORDS[2 * r + 1] << 32) for r in range(4))
    for _, _, typ in FX.TENSORS:
        assert typ in _GGML_NATIVE or typ in _GGML_QUANT, typ
    assert set(FX.SUPPORTED) <= (set(_GGML_NATIVE) | set(_GGML_QUANT)), FX.SUPPORTED

    rows = []
    for name, typ, vs in values(HERE / "llm_ggml-fixture.gguf"):
        assert typ == dict((n, t) for n, _, t in FX.TENSORS)[name], name
        rows.append(f"v_{name}=" + ",".join(bits(v) for v in vs))
    rows.append("iqs=" + ",".join(str(int(v)) for v in flatten(U._ggml_iq_signs(None).tolist())))
    rows.append("grid=" + ",".join(str(int(v)) for v in
                                   flatten(U._ggml_iq_grid(None, entries, (4, 8)).tolist())))
    rows.append("lut=" + ",".join(str(v & 0xFFFFFFFF) for v in GC.kvalues_iq4nl))
    rows.append(f"err={err()}")
    # ONE ROW PER GRID, from `ggml_common` ITSELF: the generator's output is compared
    # against the module it was derived from, so a wrong generated word is one red row.
    for name, attr, nb in FX.GRIDS:
        rows.append(grow(name, FX.words(getattr(GC, attr), nb)))
    rows += [f"ty_{c:02d}={FX.SUPPORTED.get(c, '-')}" for c in range(FX.NCODES)]

    assert len(rows) == FX.ROWS, (len(rows), FX.ROWS)
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
