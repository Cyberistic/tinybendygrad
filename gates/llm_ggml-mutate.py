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
   "iq.gbyte(byte(g, r), byte(g, U32.add(r, 1)), U32.mod(i, 8))",
   "iq.gbyte(byte(g, r), byte(g, r), U32.mod(i, 8))"),
  ("typ_ladder", "`ggml_type` 8 answers the Q4_0 tag (a transcription slip)", PORT,
   "    case 8: Some{TQ8_0{}}", "    case 8: Some{TQ4_0{}}"),
  ("lut_typo", "one `kvalues_iq4nl` entry is wrong in the driver", DRIVER,
   "[4294967169, 4294967192, 4294967213,", "[4294967192, 4294967169, 4294967213,"),
)


def lane():
    r = subprocess.run([str(BEND), str(LANE)], capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()], r


def main():
    base, r = lane()
    if len(base) != ROWS:
        print(f"the unmutated lane emitted {len(base)} rows, not {ROWS}: {r.stderr[-400:]}")
        return 1
    source = {p: (ROOT / p).read_text() for p in (PORT, DRIVER)}
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

    name, _, path, old, new = MUTATIONS[1]
    (ROOT / path).write_text(source[path].replace(old, new, 1))
    try:
        g = subprocess.run([str(PY), str(GATE)], capture_output=True, text=True)
    finally:
        (ROOT / path).write_text(source[path])
    said = [l.strip()[:220] for l in g.stderr.splitlines() if "DISAGREE" in l]
    print(f"-- gate on the {name} mutation: rc={g.returncode} {said[:1]}")
    return 1 if holes or g.returncode == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
