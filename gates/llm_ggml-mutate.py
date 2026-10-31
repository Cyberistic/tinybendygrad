#!/usr/bin/env python3
"""llm_ggml-mutate.py -- does `gates/llm_ggml-gate.py` go RED when the decode is wrong?

    .venv/bin/python gates/llm_ggml-mutate.py           # measure, print the table
    .venv/bin/python gates/llm_ggml-mutate.py --write   # also write the `.rows` table

A NEW PORT HAS NO "BEFORE" TO REVERT TO, so each of the decode's load-bearing decisions is
replaced by the plausible WRONG one and the row count that moves is recorded. `q4k_sc_off`
is not invented: it is the off-by-four that the ORACLE caught on the port's first run
(`s[8..12]` is block bytes 12..15, not 8..11), which is the evidence that this gate reads a
number it could disagree with.

Every mutation is ONE substitution, and every mutated file is restored in a `finally`.
"""
import importlib.util
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PORT = "tinybendygrad/llm/ggml.bend"
DRIVER = "gates/llm_ggml.bend"
GEN = "tinybendygrad/runtime/autogen/ggml_common_p1.bend"
GEN4 = "tinybendygrad/runtime/autogen/ggml_common_p4.bend"
BEND = ROOT / "bin" / "bend"
LANE = HERE / "llm_ggml.bend"
GATE = HERE / "llm_ggml-gate.py"
PY = ROOT / ".venv" / "bin" / "python"
TABLE = HERE / "llm_ggml-mutations.rows"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ROWS = load("llm_ggml_fixture", "llm_ggml-fixture.py").ROWS

# (name, what the wrong version is, which file, the substring, its replacement)
MUTATIONS = (
  ("nib_order", "the nibble halves are swapped (HIGH nibbles first)", PORT,
   "Nat.mul(U32.to_nat(U32.div(j, 16)), 4n)", "Nat.mul(U32.to_nat(U32.sub(1, U32.div(j, 16))), 4n)"),
  ("q4k_sc_off", "the 6-bit scale's high half reads bytes 8..11 instead of 12..15", PORT,
   "U32.and(byte(bs, U32.add(12, U32.sub(sub, 4))), 15)",
   "U32.and(byte(bs, U32.add(8, U32.sub(sub, 4))), 15)"),
  ("q8_0_sx", "Q8_0's quants are read unsigned", PORT,
   "case TQ8_0{}: F32.mul(f16at(bs, 0), i32f(G.sc.sx8(byte(bs, U32.add(2, i)))))",
   "case TQ8_0{}: F32.mul(f16at(bs, 0), i32f(byte(bs, U32.add(2, i))))"),
  ("bf16_shift", "bfloat16 is widened by 8 bits instead of 16", PORT,
   "F.F32.from_bits(U32.shln(le2(bs, i), 16n))", "F.F32.from_bits(U32.shln(le2(bs, i), 8n))"),
  ("iqs_parity", "the sign byte's top bit is set on EVEN parity", PORT,
   "Bool.pick(U32, pc.odd(i), U32.or(i, 128), i)", "Bool.pick(U32, pc.odd(i), i, U32.or(i, 128))"),
  ("grid_word", "the grid byte table reads word 0 twice", PORT,
   "iq.gbyte(byte(g, b), byte(g, U32.add(b, U32.sub(wpe, 1))), c)",
   "iq.gbyte(byte(g, b), byte(g, b), c)"),
  ("typ_ladder", "`ggml_type` 8 answers the Q4_0 tag (a transcription slip)", PORT,
   "    case 8: Some{TQ8_0{}}", "    case 8: Some{TQ4_0{}}"),
  ("iq2xs_scale16", "IQ2_XS's scale is read per THIRTY-TWO elements, not sixteen", PORT,
   "      +s = U32.div(i, 16)\n      +gi = U32.div(i, 8)", "      +s = U32.div(i, 32)\n      +gi = U32.add(U32.mul(s, 2), U32.div(U32.mod(i, 32), 8))"),
  ("q1s_shift", "IQ1_S's three high bits are taken at stride ONE instead of THREE", PORT,
   "+j = U32.mul(U32.mod(i, 4), 3)", "+j = U32.mod(i, 4)"),
  # A WRONG GENERATED WORD the payload does NOT index: only the hash row can see it, and the
  # pin turns it into a REFUSAL before either lane runs.
  ("gen_word", "one word of the generated `iq3xxs_grid` is off by one", GEN,
   "[67372036,", "[67372037,"),
  ("q4_1_bias", "Q4_1's offset reads the block scale", PORT,
   "F32.add(F32.mul(i32f(nib(bs, 4, i)), f16at(bs, 0)), f16at(bs, 2))",
   "F32.add(F32.mul(i32f(nib(bs, 4, i)), f16at(bs, 0)), f16at(bs, 4))"),
  ("q5_0_bias", "Q5_0's -16*d bias becomes -15*d", PORT,
   "F32.mul(F32.neg(16.0), f16at(bs, 0))", "F32.mul(F32.neg(15.0), f16at(bs, 0))"),
  ("q5_1_qh", "Q5_1 reads Q5_0's high-bit bytes", PORT,
   "U32.shln(bit.at(bs, 4, i), 4n)", "U32.shln(bit.at(bs, 2, i), 4n)"),
  ("q2k_pair", "Q2_K's two-bit pair is read from the wrong slot", PORT,
   "pair.at(bs, 16, pk2.byte(ii, U32.mod(i, 16)), pk2.pair(ii))",
   "pair.at(bs, 16, pk2.byte(ii, U32.mod(i, 16)), U32.mod(ii, 2))"),
  ("q3k_hm", "Q3_K's hmask byte is masked to four bits instead of five", PORT,
   "U32.shrn(byte(bs, U32.mod(e, 32)), U32.to_nat(U32.div(e, 32)))",
   "U32.shrn(byte(bs, U32.mod(e, 16)), U32.to_nat(U32.div(e, 32)))"),
  ("q5k_qh", "Q5_K's fifth bit is read from the wrong bit position", PORT,
   "byte(bs, U32.add(16, U32.mod(e, 32))), U32.to_nat(U32.div(e, 32)))",
   "byte(bs, U32.add(16, U32.mod(e, 32))), U32.to_nat(U32.div(e, 16)))"),
  ("q6k_xl", "Q6_K's low nibble takes the wrong half", PORT,
   "U32.is_eq(U32.div(U32.mod(e, 128), 64), 0)", "U32.is_eq(U32.div(U32.mod(e, 128), 32), 0)"),
  ("mxfp4_sign", "MXFP4's sign splits at code 7 instead of 8", PORT,
   "U32.is_lt(code, 8)", "U32.is_lt(code, 7)"),
  ("q1_0_sign", "Q1_0's -1/+1 is inverted", PORT,
   "U32.is_eq(bit.at(bs, 2, i), 1), 1.0, F32.neg(1.0)",
   "U32.is_eq(bit.at(bs, 2, i), 0), 1.0, F32.neg(1.0)"),
  ("iq3s_sc_base", "IQ3_S's scales start one byte early", PORT,
   "sc2.at(bs, 106, s)", "sc2.at(bs, 105, s)"),
  ("iq2s_scale", "IQ2_S's scale is read at the wrong stride", PORT,
   "U32.add(U32.mul(U32.mod(s, 2), 16), U32.div(s, 2))",
   "U32.add(U32.mul(U32.mod(s, 2), 16), U32.div(s, 4))"),
  ("iq1m_qi", "IQ1_M's grid row keeps three low bits instead of ALL three", PORT,
   "U32.shln(U32.and(q1m.qh(bs, t), 7), 8n)", "U32.shln(U32.and(q1m.qh(bs, t), 3), 8n)"),
  # A GENERATED WORD THE PAYLOAD ACTUALLY INDEXES: `iq3s_grid` row 14 is the FIRST word the
  # IQ3_S block reads, so this one moves `v_iq3s.w` and not only the hash row.
  ("gen_word_hit", "the generated `iq3s_grid` row the IQ3_S payload reads is off by one", GEN4,
   "[16843009,16843011,16843013,16843019,16843023,16843521,16843523,16843525,16843529,16843533,16844033,16844035,16844043,16844551,16845057,",
   "[16843009,16843011,16843013,16843019,16843023,16843521,16843523,16843525,16843529,16843533,16844033,16844035,16844043,16844551,16845058,"),

)


def lane():
    r = subprocess.run([str(BEND), str(LANE)], capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()], r


def main():
    base, r = lane()
    if len(base) != ROWS:
        print(f"the unmutated lane emitted {len(base)} rows, not {ROWS}: {r.stderr[-400:]}")
        return 1
    source = {p: (ROOT / p).read_text() for p in (PORT, DRIVER, GEN, GEN4)}
    out, holes = [], 0
    for name, why, path, old, new in MUTATIONS:
        if old not in source[path]:
            out.append(f"{name}\tMISSING\t0\t{why}")
            holes += 1
            continue
        (ROOT / path).write_text(source[path].replace(old, new, 1))
        try:
            got, _ = lane()
        finally:
            (ROOT / path).write_text(source[path])
        moved = sum(1 for a, b in zip(base, got) if a != b) + abs(len(base) - len(got))
        verdict = "RED" if (moved or len(got) != len(base)) else "GREEN"
        out.append(f"{name}\t{verdict}\t{moved}\t{why}")
        if verdict != "RED":
            holes += 1
        print(out[-1])
    if "--write" in sys.argv:
        TABLE.write_text("mutation\tverdict\trows_moved\twhy\n" + "\n".join(out) + "\n")
    print(f"-- {len(MUTATIONS)} mutations, {len(MUTATIONS) - holes} moved at least one row")

    for i, why in ((1, "a PORT mutation"), (12, "an UNINDEXED generated word"), (len(MUTATIONS) - 1, "an INDEXED generated word")):
        name, _, path, old, new = MUTATIONS[i]
        (ROOT / path).write_text(source[path].replace(old, new, 1))
        try:
            g = subprocess.run([str(PY), str(GATE)], capture_output=True, text=True)
        finally:
            (ROOT / path).write_text(source[path])
        said = [l.strip()[:200] for l in g.stderr.splitlines()
                if "DISAGREE" in l or "REFUSED" in l]
        print(f"-- gate on the {name} mutation ({why}): rc={g.returncode} {said[:1]}")
        bad_gate = g.returncode in (0,)
        holes += 1 if bad_gate else 0
    return 1 if holes else 0


if __name__ == "__main__":
    sys.exit(main())
