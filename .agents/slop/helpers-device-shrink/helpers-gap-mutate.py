#!/usr/bin/env python
"""helpers-gap-mutate.py -- **DO THE NEW ROWS GO RED?** A GATE WHOSE ROWS CANNOT
MOVE IS NOT A GATE.

    .venv/bin/python .agents/slop/helpers-device-shrink/helpers-gap-mutate.py

**THE QUESTION.** `.agents/slop/helpers-device-shrink/helpers-gap-gate.sh` GATES
**90 ROWS** OVER THE `helpers.bend` DEFS THAT NO OTHER GATE COVERS -- `i64_mul`,
`gcd`, `u64_divmod`, `i64_abs`, `i64_not`, `i64_neg`, `cdiv_i64`, `cmod_i64`,
`floordiv_i32`, `floormod_i32`, `cdiv_i32`, `cmod_i32`, `ceildiv_i32`,
`round_up_i32`, `round_down_i32` AND `next_power2`. **AND A GATE WHOSE ROWS
CANNOT GO RED IS WORSE THAN NO GATE** -- THE TREE's OWN RULE, AND `differ.py`'s
OWN PLANT 3: "if it does not go red, the row is a label."

**SO THIS FILE MUTATES THE PORT IN A SCRATCH COPY AND ASKS WHETHER THE GATE
GOES RED.** **AND THE SCRATCH IS **OUTSIDE `tinybendygrad/`** SO A MUTATION
NEVER MOVES THE SUBSTRATE DIGEST's POPULATION.**

**THE MUTATIONS ARE THE ONES THAT WOULD MOVE A ROW IF THE DEF WERE WRONG:**
THE `i64_mul` SIGN, THE `gcd` MAGNITUDE, THE `u64_divmod` ZERO-DIVISOR ARM,
THE `floor`/`truncate` SPELLING, AND THE `next_power2` COMPARISON.
"""

import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PORT = os.path.join(ROOT, "tinybendygrad", "helpers.bend")
DRIVER = os.path.join(ROOT, ".agents", "slop", "helpers-device-shrink", "helpers-gap.bend")
ORACLE = os.path.join(ROOT, ".agents", "slop", "helpers-device-shrink", "helpers-gap-oracle.py")
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"

# (name, the text to find, the text to put in its place)
MUTATIONS = [
    (
        "i64_mul negates on the wrong sign",
        "  i64_neg(Bool.xor(i64_is_neg(a), i64_is_neg(b)), u64_mul(i64_abs(a), i64_abs(b)))",
        "  i64_neg(i64_is_neg(a), u64_mul(i64_abs(a), i64_abs(b)))",
    ),
    (
        "gcd steps with the SIGNED division instead of the unsigned one",
        "def gcd(a: I64, b: I64) -> I64:\n  gcd.go(128n, i64_abs(a), i64_abs(b))",
        "def gcd(a: I64, b: I64) -> I64:\n  gcd.go(128n, a, b)",
    ),
    (
        "u64_divmod's zero-divisor arm answers 0 instead of the dividend",
        "def u64_divmod.of(zero: Bool, a: I64, d: DivMod) -> DivMod:\n  match zero:\n    case True{}: DivMod{i64_zero(), a}",
        "def u64_divmod.of(zero: Bool, a: I64, d: DivMod) -> DivMod:\n  match zero:\n    case True{}: DivMod{i64_zero(), i64_zero()}",
    ),
    (
        "floordiv_i32 steps DOWN on the wrong sign",
        "        case True{}: floordiv_i32.trunc.put(neg, U32.add(q, 1))",
        "        case True{}: floordiv_i32.trunc.put(neg, q)",
    ),
    (
        "cdiv_i32 stops negating on a sign mismatch",
        "  cdiv_i32(U32.is_zero(y), cdiv_sign(x, y),\n    U32.div(i32_abs(i32_is_neg(x), x), i32_abs(i32_is_neg(y), y)))",
        "  cdiv_i32(U32.is_zero(y), False{},\n    U32.div(i32_abs(i32_is_neg(x), x), i32_abs(i32_is_neg(y), y)))",
    ),
    (
        "next_power2's comparison is off by one",
        "  next_power2.go(33n, U32.is_lt(1, x), x, 1)",
        "  next_power2.go(33n, U32.is_lt(2, x), x, 1)",
    ),
]


def rows_of(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for ln in text.splitlines():
        ln = ln.strip()
        if "=" in ln and " " not in ln.split("=", 1)[0]:
            k, v = ln.split("=", 1)
            out[k] = v
    return out


def main() -> int:
    port_src = open(PORT).read()
    expected = rows_of(subprocess.run(
        [".venv/bin/python", ORACLE], cwd=ROOT, capture_output=True, text=True, check=True).stdout)
    root = tempfile.mkdtemp(prefix="helpers-gap-mut-", dir=SCRATCH)
    bad = 0
    try:
        mut_root = os.path.join(root, "mut")
        os.makedirs(mut_root)
        # **THE DRIVER'S IMPORT IS REBASED ON THE SCRATCH** -- it reaches the port
        # at `./../../../tinybendygrad/helpers.bend` and the scratch has no
        # `tinybendygrad/`.
        driver = open(DRIVER).read().replace(
            "import ./../../../tinybendygrad/helpers.bend as H",
            "import ./helpers.bend as H")
        with open(os.path.join(mut_root, "helpers-gap.bend"), "w") as f:
            f.write(driver)

        print("| mutation | rows moved | how many |")
        print("| --- | --- | --- |")
        for name, find, repl in MUTATIONS:
            if port_src.count(find) != 1:
                print(f"| {name} | ANCHOR NOT UNIQUE ({port_src.count(find)}) | 0 |")
                bad += 1
                continue
            with open(os.path.join(mut_root, "helpers.bend"), "w") as f:
                f.write(port_src.replace(find, repl))
            p = subprocess.run(
                ["./bin/bend", os.path.join(mut_root, "helpers-gap.bend")],
                cwd=ROOT, capture_output=True, text=True)
            if p.returncode != 0:
                print(f"| {name} | MUTANT DID NOT RUN | 0 |")
                print(p.stdout[-1200:], p.stderr[-1200:])
                bad += 1
                continue
            got = rows_of(p.stdout)
            moved = sorted(k for k in set(expected) | set(got) if expected.get(k) != got.get(k))
            print(f"| {name} | {', '.join(moved[:6]) if moved else 'NOTHING'}"
                  f"{' ...' if len(moved) > 6 else ''} | {len(moved)} |")
            if not moved:
                bad += 1
        return 1 if bad else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
