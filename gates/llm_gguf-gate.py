#!/usr/bin/env python3
"""llm_gguf-gate.py -- THE GATE for `tinybendygrad/llm/gguf.bend`, the GGUF file reader.

    .venv/bin/python gates/llm_gguf-gate.py

143 ROWS, TWO LANES -- CPython (`tinygrad.llm.gguf` itself) and the port -- over ONE
property: **the same bytes parse to the same numbers**.

WHY THIS GATE IS THE STRONGEST SHAPE THIS TREE HAS. `gguf.py` is a FILE FORMAT READER,
so it is pure data transformation: no device, no compiler, no timing, and no float
tolerance. The comparison is of PARSED VALUES, and both lanes read the same three
`.gguf` files that `gates/llm_gguf-fixture.py` writes. There is nothing to be flaky.

WHAT IT COVERS, and each block exists because a defect of that shape has no other row:
  * all 19 `kv` pairs, IN FILE ORDER, with a `kvseq` row for the ORDER itself -- a dict
    whose keys are right and whose order is wrong is a different dict, and only the
    sequence row can see it;
  * all thirteen `readers` types (`gguf.py:193-195`), including type 0 (`bytes`, one
    byte), type 7 (`bool`), type 8 with 2-, 3- and 4-byte UTF-8 sequences, and type 9
    as an array of str, of i32 and of f32;
  * every tensor's `(reversed shape, ggml_type, offset, start, nbytes)`. `start` and
    `nbytes` are read OUT OF UPSTREAM'S OWN GRAPH -- `gguf.py:230`'s slice is a SHRINK
    whose `src[1]`/`src[2]` ARE those two numbers -- so they are the reference's answer
    and not a formula this file retyped;
  * `general.alignment` present and 32, so `gguf_parse:224`'s `round_up(tell())` is
    exercised on a NON-ZERO remainder (the header is 800 bytes, the divisor 32);
  * 64-bit metadata whose high word is not zero (`t.u64`, `t.i64`), an f64 whose bits are
    not an exact f32 (`t.f64`), and a quantised tensor, so the three places a port
    silently narrows are three visible rows;
  * all FOUR error spellings `gguf_parse` has: the good file, a mutated magic, a mutated
    version, an unknown tensor ggml type (99) and an unknown metadata type (13);
  * EVERY ggml type code 0..45 and EVERY metadata type code 0..15. Those three tables
    are `U32` arm ladders in the port, and bend's numeric arms are PREFIX matches, so a
    ladder written in the wrong order answers a NEIGHBOURING code and every other row
    would still be green. `fmt_*`/`nat_*`/`qnt_*` are what make a mis-ordered ladder red.

THE ORACLE DOES NOT TRANSCRIBE THE TABLES: `readers`, `_GGML_NATIVE` and `_GGML_QUANT`
are IMPORTED from upstream and read as objects, so those 108 rows compare the port's
ladders against the dicts they were copied from.

THE FIXTURES ARE PINNED BY sha256 AND THEIR ROW COUNT IS DERIVED, not transcribed:
`gates/llm_gguf-fixture.py` owns `KV` and `TENSORS` and computes `ROWS` from them, so a
fourteenth metadata pair is one row on all three of the fixture, the count and the lanes.
A fixture that moves without the pin moving REFUSES (exit 3, `gatekit.REFUSED`).

WHAT THIS GATE CANNOT SEE, stated rather than left to be found:
  * `ggml_data_to_tensor` (`gguf.py:29-185`) is NOT PORTED and is not gated here. The
    port's header for `gguf.bend` names the wall: five quant decode ladders index
    constant grids from `tinygrad.runtime.autogen.ggml_common`, which the port does not
    have.
  * the `Tensor` branch (`gguf.py:230`'s slice), `gguf_load` and `gguf_shard` are not
    ported, so no row says anything about a tensor VIEW -- only about the integers that
    define one.
  * a read PAST THE END of a truncated file answers short in the port and raises
    `struct.error` upstream; no row covers it, and the header for `gguf.bend` says so.
"""
import importlib.util
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, REFUSED, main, oracle_drift

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FX = load("llm_gguf_fixture", "llm_gguf-fixture.py")

# THE FIXTURES' sha256, as built by `gates/llm_gguf-fixture.py` -- regenerate them with
# that script and move these three lines in the SAME commit, or this gate refuses.
FIXTURES = {
  "gates/llm_gguf-fixture.gguf": "bc193da736ee0b1a06ebfcd2e8e041bceb83711a1d59e99c0a3e9d586a656d2e",
  "gates/llm_gguf-badmeta.gguf": "84a176587b24b433ad9feee2bf76205c2e04661d969d24039c8c5c1d1de51a21",
  "gates/llm_gguf-badtype.gguf": "0dbf9d91b0db8e51dbeff7501a908a94adcb06aca91117b0dfbf97a88dd73d55",
}

# A pin is a claim a diff cannot express: that these rows still EXIST. Each is the row
# that would move if one of the three narrowing walls were crossed.
PINNED = ("kv.t.u64", "kv.t.f64", "kv.t.i8", "err_blk", "err_magic", "err_meta",
          "t.blk.0.q4k.weight", "fmt_09", "nat_28", "qnt_41", "kvseq", "ds")

GATE = Gate(
  "llm_gguf-gate",
  bend="gates/llm_gguf.bend",
  oracle="gates/llm_gguf-oracle.py",
  rows=FX.ROWS,
  pins=[(lane, row) for lane in ("py", "bd") for row in PINNED],
)

if __name__ == "__main__":
  drift = oracle_drift(FIXTURES)
  if drift:
    print("== REFUSED, NOT A VERDICT: the fixtures moved under the pin, so this gate "
          "would compare the port against a different file:\n  " + "\n  ".join(drift),
          file=sys.stderr)
    sys.exit(REFUSED)
  sys.exit(main(GATE, f"llm_gguf-gate: {FX.ROWS} rows, 2 lanes -- the GGUF reader "
                      f"(`tinygrad/llm/gguf.py:187-231`) over {len(FX.KV)} kv pairs, "
                      f"{len(FX.TENSORS)} tensors, all {FX.FMTCODES} metadata type codes, "
                      f"all {FX.NCODES} ggml type codes and all 4 error spellings"))
