#!/usr/bin/env python3
"""llm_ggml-gate.py -- THE GATE for `tinybendygrad/llm/ggml.bend`, the quant DECODE.

    .venv/bin/python gates/llm_ggml-gate.py

57 ROWS, TWO LANES -- CPython's `ggml_data_to_tensor` and the port's `ggml.dec` -- over one
property: **the same bytes decode to the same numbers**.

THE SUBJECT IS `ggml_data_to_tensor` WITHOUT ITS `Tensor` (`gguf.py:29-185`). MEASURED, and
it is why the split is honest: every ladder in :42-184 is `bitcast`, arithmetic, `where`,
`reshape` and a GRID INDEX; `Tensor` appears only as the container the answer is written
into. So the port answers `List<&2, F32>` and constructs nothing, and this gate compares
`tolist()` against that list. No device, no kernel, no dtype object.

THE FIXTURE IS A REAL `.gguf`, and that is load-bearing twice over: the .bend lane finds
each block the way `gguf_load` would (the READER gives the offset and the length, the slice
gives the bytes), so the gate measures the decode AND the byte geometry; and the header is
what carries the element count, so NO offset or length is transcribed on either side.

WHAT IT COVERS, one row per block, all values:
  * 0 float32, 1 float16, 30 bfloat16 -- the three float natives. The f16/bf16 payloads are
    CURATED bit patterns (denormal, max, -0, sign) and never a NaN, because a NaN's payload
    is a fact about NaN and not about this port;
  * 2 Q4_0, 8 Q8_0 -- the two legacy block formats, whose nibble order is the thing that
    is easy to get backwards. It IS backwards-looking: `q_to_uint8` produces SIXTEEN LOW
    nibbles and then sixteen HIGH ones, not alternate pairs, and the port's comment records
    the measurement;
  * 12 Q4_K -- the six-bit sub-block scales, which is the k-quant the brief named as a
    "grid quant". MEASURED: it is NOT one. `Q4_K` (:79-87) never mentions `_ggml_iq_grid`;
    the grid family is the `IQ*` codes;
  * 20 IQ4_NL -- the grid family, and its whole grid is the sixteen `kvalues_iq4nl`, which
    arrives as an ARGUMENT (`gates/llm_ggml.bend`'s `lut`), not as an import;
  * `iqs` -- the 128 sign bytes, COMPUTED on both sides (`gguf.py:17`); `grid` -- the
    `_ggml_iq_grid` byte table from four synthetic entries of two 32-bit words each, the
    same argument on both sides;
  * `err` -- `gguf.py:185`'s refusal, and `ty_00..ty_45` -- the port's SUPPORTED SET, one
    row per `ggml_type` code, so a type that silently stopped decoding is a red row instead
    of a missing one.

WHAT THIS GATE CANNOT SEE, stated rather than left to be found:
  * SEVENTEEN of the twenty-one quant types are NOT PORTED: 3 Q4_1, 6 Q5_0, 7 Q5_1, 10
    Q2_K, 11 Q3_K, 13 Q5_K, 14 Q6_K, 16 IQ2_XXS, 17 IQ2_XS, 18 IQ3_XXS, 19 IQ1_S, 21
    IQ3_S, 22 IQ2_S, 23 IQ4_XS, 29 IQ1_M, 39 MXFP4, 41 Q1_0. Their `ty_*` rows read `-`.
    They are NOT a wall: each is the same `iq.grid`/`iq.signs` machinery this gate already
    exercises, plus per-type index arithmetic.
  * the GRIDS THEMSELVES are not shipped. `_ggml_iq_grid`'s three arguments are a device,
    a constant and a `Tensor`; `iq.grid` needs only the constant, so the day a caller can
    hold `iq2xxs_grid` the decode has a place to put it -- and until then this gate proves
    the expansion on a synthetic four-entry grid, which is the same code path.
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


FX = load("llm_ggml_fixture", "llm_ggml-fixture.py")

# Regenerate with `gates/llm_ggml-fixture.py` and move this line in the SAME commit, or
# this gate refuses.
FIXTURES = {
  "gates/llm_ggml-fixture.gguf": "7799b68fd67ab7e68a664a67457c4cd3f91477fff3e6a30325cd97509cb290d6",
  # THE GENERATOR'S OUTPUT, PINNED. `ggml_common-gen.py` prints these ten; regenerate and
  # move them in the SAME commit, or a regenerated-but-different constant REFUSES here
  # instead of quietly changing what 4,096 words mean.
  "tinybendygrad/runtime/autogen/ggml_common.bend":
    "83c028492f00bcdeb8c0894d0c043b658e45cc42531b7739b4943d119b6214be",
  "tinybendygrad/runtime/autogen/ggml_common_p1.bend":
    "4846376de3ada1060669a1f6af0de688a21c09bf07b6e8d4b7cb9280da676083",
  "tinybendygrad/runtime/autogen/ggml_common_p2.bend":
    "18b2d6dc74d126bde12649cff6f1673c7c717ea1e042b4ef3c026fa509210302",
  "tinybendygrad/runtime/autogen/ggml_common_p3.bend":
    "c984398146495606d4ce726f7dbc64d691bfdedbbbafeb34dbca6b7a74d4a0de",
  "tinybendygrad/runtime/autogen/ggml_common_p4.bend":
    "ff24a65bb805b424c6456a4a021ac047265ecf9f815ed136f9a5e566572baa0c",
  "tinybendygrad/runtime/autogen/ggml_common_p5.bend":
    "abba15c12dbb2d942321223b7a6812b87850a51dd877b57b53e84abab42976e6",
  "tinybendygrad/runtime/autogen/ggml_common_p6.bend":
    "3406cb3f06f61534ab6adeed952a7f26ac52911c4f8b15c59c2d9b33dd0d187d",
  "tinybendygrad/runtime/autogen/ggml_common_p7.bend":
    "59546ff994f82436fde2c7c0675d393b1b0e991f815b424d9a443003dcbd4612",
  "tinybendygrad/runtime/autogen/ggml_common_p8.bend":
    "70cadc13ed9f911500bfc8fb7374f43b97a50e6c5a4c712153b6777b7be9b48c",
  "tinybendygrad/runtime/autogen/ggml_common_p9.bend":
    "ef6559f783b86464726b18a9cecb9a9683ec76e8c6dbbc208c6a42f59efb087a",
}

# The rows that would move if one of the decode's decisions were wrong: one per PORTED
# type, the two grid helpers, the transcribed LUT, and the refusal.
PINNED = ("v_f32.w", "v_f16.w", "v_bf16.w", "v_q4_0.w", "v_q4_1.w", "v_q5_0.w",
          "v_q5_1.w", "v_q8_0.w", "v_q2k.w", "v_q3k.w", "v_q4k.w", "v_q5k.w", "v_q6k.w",
          "v_mxfp4.w", "v_q1_0.w", "v_iq4nl.w", "v_iq4xs.w", "v_iq1s.w", "v_iq2xxs.w",
          "v_iq2xs.w", "v_iq3xxs.w", "v_iq3s.w", "v_iq2s.w", "v_iq1m.w",
          "iqs", "grid", "lut", "err", "ty_41",
          "g_iq3xxs_grid", "g_iq2xxs_grid", "g_iq2xs_grid", "g_iq3s_grid",
          "g_iq2s_grid", "g_iq1s_grid")

GATE = Gate(
  "llm_ggml-gate",
  bend="gates/llm_ggml.bend",
  oracle="gates/llm_ggml-oracle.py",
  rows=FX.ROWS,
  pins=[(lane, row) for lane in ("py", "bd") for row in PINNED],
)

if __name__ == "__main__":
  drift = oracle_drift(FIXTURES)
  if drift:
    print("== REFUSED, NOT A VERDICT: the fixture moved under the pin:\n  "
          + "\n  ".join(drift), file=sys.stderr)
    sys.exit(REFUSED)
  sys.exit(main(GATE, f"llm_ggml-gate: {FX.ROWS} rows, 2 lanes -- `ggml_data_to_tensor`'s "
                      f"DECODE over {len(FX.TENSORS)} blocks, the 128 sign bytes, a 4-entry "
                      f"grid, the GENERATED iq4nl LUT and the six grids, the refusal, and the supported "
                      f"set over all {FX.NCODES} ggml type codes"))
