#!/usr/bin/env python3
"""llm_gguf-oracle.py -- CPython's answers to `gates/llm_gguf.bend`'s 143 rows.

The two lanes share no code: the Bend lane runs the port's `gguf.parse` over the
fixture's bytes, and this lane runs UPSTREAM's `tinygrad.llm.gguf.gguf_parse` over the
same file and asks the same questions.

TWO READERS, AND EACH IS A CONTROL ON THE OTHER. This file does NOT re-derive what
upstream already answers:

  * the `kv` dict, the reversed `shape` and the `ggml_type` come from upstream's
    `gguf_parse`, which is `gguf.py:198-231` itself;
  * each tensor's `start` and `nbytes` come from upstream's OWN graph -- `gguf.py:230`
    is `tensor[start:start+nbytes]`, and the DISK tensor it produces is a `SHRINK`
    whose `src[1]` is the begin and `src[2]` is the length, so the two numbers the port
    computes are read off the thing upstream built rather than out of a formula this
    file would have to retype;
  * the `readers`, `_GGML_NATIVE` and `_GGML_QUANT` tables ARE upstream's objects, so
    the port's thirteen-type, eight-native and twenty-one-quant ladders are compared
    against the dicts they were transcribed from and not against a second copy.

AND ONE THING UPSTREAM DOES NOT EXPOSE: the tensor's `off`, the raw file offset that
`data_start + off` turns into `start`. That IS re-derived here, by a `struct` walk of
the header, and it is not a second opinion on upstream -- it is a CHECK: the assertion
below fails unless `data_start + off == start` for all three tensors, so a bug in
either reader makes this lane exit non-zero (gatekit's REFUSED) instead of printing a
number that happens to agree.

SPELLING, and both lanes say the same thing:
  * an int of 32 bits or less prints as SIGNED DECIMAL, which is CPython's `int`;
  * a 64-bit field prints as `hi:lo` (helpers.bend's `i64_text`), because 2^63 has no
    `U32` image -- the rows `kv.t.u64` and `kv.t.i64` exist to make the high word
    visible;
  * an f32 prints as its BIT PATTERN and an f64 as its eight bytes, because neither
    lane can print a float exactly and the bits ARE the value;
  * a type-0 metadata value is a Python `bytes` of length one and prints as its byte.

THE ERROR ROWS. `err_good` and `err_meta` print `none`: `gguf_parse` raises an uncaught
`KeyError` for an unknown METADATA type -- there is no message to mirror -- and `none`
is the one spelling both lanes can print. `err_magic` and `err_ver` are both upstream's
`Invalid GGUF format!` and `err_blk` is its `GGML type '99' is not supported!`.
"""
import importlib.util
import struct
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FX = load("llm_gguf_fixture", "llm_gguf-fixture.py")
from tinygrad.llm import gguf as U


def num64(v):
    return f"{(v >> 32) & 0xFFFFFFFF}:{v & 0xFFFFFFFF}"


def f32_bits(v):
    return struct.unpack("<I", struct.pack("<f", v))[0]


def f64_bits(v):
    return num64(struct.unpack("<Q", struct.pack("<d", v))[0])


def show(code, v, sub=None):
    """One metadata value, in the spelling the port's `gv.show` produces.

    `sub` is the ELEMENT type of a type-9 array, which upstream's dict has already
    dropped: a Python list of floats does not say whether it held f32 or f64, and the
    port's row for one is a bit pattern and for the other eight bytes. The subtype comes
    from the `struct` walk below, and the VALUES come from upstream.
    """
    if code == 9: return "[" + ",".join(show(sub, x) for x in v) + "]"
    if code == 7: return "True" if v else "False"
    if code == 8: return v
    if code == 0: return str(v[0] if isinstance(v, bytes) else v)
    if code == 6: return str(f32_bits(v))
    if code == 12: return f64_bits(v)
    if code in (10, 11): return num64(v)
    return str(v)


def norm(code, v, sub=None):
    """`struct`'s value and a Python dict's value, made comparable."""
    if code == 9:
        if isinstance(v, tuple): sub, v = v
        return [norm(sub, x) for x in v]
    if code == 0 and isinstance(v, bytes): return v[0]
    return v


def hdr(path):
    """The header, read by THIS file: `(kv[(k, code, value)], tensors[(name, dims, typ, off)], align)`."""
    b, i = Path(path).read_bytes(), 0

    def take(n):
        nonlocal i
        v = b[i:i + n]
        i += n
        return v

    def scalar(code):
        f = {0: "<B", 1: "<b", 2: "<H", 3: "<h", 4: "<I", 5: "<i", 6: "<f", 7: "<?",
             10: "<Q", 11: "<q", 12: "<d"}[code]
        return struct.unpack(f, take(struct.calcsize(f)))[0]

    def string():
        return take(struct.unpack("<Q", take(8))[0]).decode("utf-8")

    assert take(4) == b"GGUF"
    assert struct.unpack("<i", take(4))[0] in (2, 3)
    n_ten, n_kv = struct.unpack("<qq", take(16))
    kv = []
    for _ in range(n_kv):
        k, code = string(), struct.unpack("<i", take(4))[0]
        if code == 8: v = string()
        elif code == 9:
            sub, n = struct.unpack("<iQ", take(12))
            v = (sub, tuple(string() if sub == 8 else scalar(sub) for _ in range(n)))
        else: v = scalar(code)
        kv.append((k, code, v))
    ts = []
    for _ in range(n_ten):
        name, nd = string(), struct.unpack("<I", take(4))[0]
        dims = tuple(struct.unpack("<Q", take(8))[0] for _ in range(nd))
        typ = struct.unpack("<i", take(4))[0]
        ts.append((name, dims, typ, struct.unpack("<Q", take(8))[0]))
    align = dict((k, v) for k, _, v in kv).get("general.alignment", 32)
    ds = (i + align - 1) // align * align
    return kv, ts, align, ds


def parsed(path):
    return U.gguf_parse(Path(path))


def shrink(t):
    """`(start, nbytes)` as upstream BUILT them: `gguf.py:230`'s slice, as a SHRINK."""
    u = t.uop
    assert u.op is not None and u.src is not None, u
    return u.src[1].arg, u.src[2].arg


def err(path):
    try:
        parsed(path)
    except ValueError as e:
        return str(e)
    except KeyError:
        return "none"
    return "none"


def main():
    good = HERE / "llm_gguf-fixture.gguf"
    blob = good.read_bytes()
    kv_up, sd = parsed(good)
    kv_raw, ts_raw, align, ds = hdr(good)

    sub = {k: v[0] for k, code, v in kv_raw if code == 9}

    # THE CONTROL. Two readers of the same file, one of them upstream's graph.
    assert list(kv_up) == [k for k, _, _ in kv_raw], (list(kv_up), [k for k, _, _ in kv_raw])
    for k, code, v in kv_raw:
        assert norm(code, kv_up[k], sub.get(k)) == norm(code, v), (k, kv_up[k], v)
    for name, dims, typ, off in ts_raw:
        t, shape, ty = sd[name]
        start, nbytes = shrink(t)
        assert ty == typ, (name, ty, typ)
        assert shape == tuple(reversed(dims)), (name, shape, dims)
        assert start == ds + off, (name, start, ds, off)
        assert nbytes == t.shape[0], (name, nbytes, t.shape)
        assert nbytes == max(1, (lambda n: (n * FX.NATIVE[typ]) if typ in FX.NATIVE
                                else (n // FX.QUANT[typ][0] * FX.QUANT[typ][1]))(
                    __import__("functools").reduce(lambda a, b: a * b, dims, 1))), (name, nbytes)

    rows = [f"fx_len={len(blob)}", f"fx_sum={sum(blob) & 0xFFFFFFFF}",
            f"n_kv={len(kv_up)}", f"n_ts={len(sd)}", f"ds={ds}",
            "kvseq=" + ",".join(kv_up)]
    rows += [f"kv.{k}={show(code, kv_up[k], sub.get(k))}" for k, code, _ in kv_raw]
    # THE DEFAULT `general.alignment` (:224) is a claim no fixture can exercise, because
    # every file here declares it. These two rows pin the fallback itself.
    def aalign(kv):
        return kv.get("general.alignment", 32)

    rows += [f"align={align}", f"align_none={aalign({})}",
             f"align_one={aalign({'general.alignment': 16})}",
             "tseq=" + ",".join(n for n, _, _, _ in ts_raw)]
    for name, dims, typ, off in ts_raw:
        t, shape, ty = sd[name]
        start, nbytes = shrink(t)
        rows.append(f"t.{name}=" + ",".join(num64(d) for d in shape)
                    + f"|{typ}|{num64(off)}|{num64(start)}|{nbytes}")

    rows += [f"err_good={err(good)}"]
    for tag, i, b in (("err_magic", 0, b"\x00"), ("err_ver", 4, b"\x07\x00\x00\x00")):
        with tempfile.NamedTemporaryFile(suffix=".gguf") as f:
            f.write(blob[:i] + b + blob[i + len(b):]); f.flush()
            rows.append(f"{tag}={err(f.name)}")
    rows += [f"err_blk={err(HERE / 'llm_gguf-badtype.gguf')}",
             f"err_meta={err(HERE / 'llm_gguf-badmeta.gguf')}"]

    # THE TABLES ARE UPSTREAM'S OWN OBJECTS, so this is a comparison against the dicts
    # the port transcribed and not against a second transcription.
    fmts = {}
    for code, fn in U.readers.items():
        if fn is U.read_str: fmts[code] = "str"
        elif fn is U.read_arr: fmts[code] = "arr"
        else: fmts[code] = fn.args[0].lstrip("<")
    rows += [f"fmt_{c:02d}={fmts.get(c, '-')}" for c in range(FX.FMTCODES)]
    rows += [f"nat_{c:02d}=" + (str(U._GGML_NATIVE[c].itemsize) if c in U._GGML_NATIVE else "-")
             for c in range(FX.NCODES)]
    rows += [f"qnt_{c:02d}=" + (f"{U._GGML_QUANT[c][0]}x{U._GGML_QUANT[c][1]}"
                               if c in U._GGML_QUANT else "-") for c in range(FX.NCODES)]

    assert len(rows) == FX.ROWS, (len(rows), FX.ROWS)
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
