#!/usr/bin/env python3
"""gen_seam.py -- `runtime/dtype.c`'s 64-bit lane, before and after a 6-line fix.

Reproduce (from the repo root):
    python3 .agents/slop/w64mile/gen_seam.py

THE FINDING THIS PUTS A NUMBER ON.  `gen_wire.py` measured that an `H.I64`
ARGUMENT arrives at a foreign effect as ONE Term pointing at a 2-field record,
and that `runtime/dtype.c:205-206` reads `f[0], f[1]` flat -- i.e. it reads the
two OPERANDS, not the two halves of one.  `Dt.i64_trunc` is the identity, so
under that reader it answers two allocation addresses instead of its input.

This script patches a COPY of the tree (the live tree is never written), rebuilds
all six seams, and prints the port beside CPython for the broken reader and for
the fixed one.  CPython is not transcribed: the expectations are calls into
`tinygrad/helpers.py:65-75` itself -- `cdiv`, `cmod`, `floordiv`, `floormod`,
`ceildiv` -- which is the only implementation whose answers count.

THE PLANT is the un-fixed reader, and it must move rows.  THE DISARM is a
different expression for the SAME fixed reader (`(u64)x | 0` is x), so the only
correct moved-set is the empty one; a disarm that moved a row would mean the lane
is not the one under test.

ZERO DIVISORS ARE NOT IN THE TABLE.  `helpers.py` raises `ZeroDivisionError`
there while `dtype.c:191,227,232,236` and `dtype.js:171` answer a totalised 0 or
the dividend.  That divergence is real and is reported by name in
`.agents/slop/W64-MILE.md` item 7; folding it into a MATCH row here would make a
known disagreement look like a pass.
"""
from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO))
from tinygrad.helpers import cdiv, cmod, ceildiv, floordiv, floormod  # noqa: E402

U32 = 0xFFFFFFFF
INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1

DEFS = ["trunc", "floor_div", "floor_mod", "cdiv", "cmod", "ceildiv"]
FIXTURES = [(7, 4), (-7, 4), (-8, 4), (7, -4), (INT64_MIN, 3)]

# `i64_of` today: it reads the argument frame flat.
BROKEN = """static s64 i64_of(Term* f) {
  return (s64)(((u64)(u32)f[0] << 32) | (u32)f[1]);
}"""
# The fix: one Term per argument, and the pair is behind it.
FIXED = """static s64 i64_of(Env e, Term t) {
  Term o[2];
  ctr_take(e, t, 2, o);
  return (s64)((((u64)(u32)o[0]) << 32) | (u32)o[1]);
}"""
SITES = [("i64_of(f)", "i64_of(e, f[0])"), ("i64_of(f + 2)", "i64_of(e, f[1])")]

# The DISARM: a different EXPRESSION for the SAME fixed reader. `| 0u` is the
# identity on every u32, so this rewrites the program without changing a single
# answer, and the only correct moved-set against it is the empty one.
DISARM = FIXED.replace("(u32)o[0]", "(u32)(o[0] | 0u)").replace(
    "(u32)o[1]", "(u32)(o[1] | 0u)")


def upstream(name: str, a: int, b: int) -> int:
    """CPython, by CALLING tinygrad's own helper. Never transcribed."""
    return {"trunc": lambda: a,
            "floor_div": lambda: floordiv(a, b),
            "floor_mod": lambda: floormod(a, b),
            "cdiv": lambda: cdiv(a, b),
            "cmod": lambda: cmod(a, b),
            "ceildiv": lambda: ceildiv(a, b)}[name]()


def pattern(v: int) -> str:
    """A value as the port prints it: `hi:lo` of its two's complement bits."""
    return f"{((v >> 32) & U32)}:{v & U32}"


def i64(hi: int, lo: int) -> int:
    return ((hi & U32) << 32) | (lo & U32)


def patch(src: str, fixed: bool | str) -> str:
    """fixed=False ships it as-is; True applies the fix; a string is used verbatim."""
    if src.count(BROKEN) != 1:
        sys.exit("the `i64_of` anchor is not unique -- dtype.c moved")
    if fixed is False:
        return src
    body = FIXED if fixed is True else fixed
    out = src.replace(BROKEN, body)
    for old, new in SITES:
        if out.count(old) < 1:
            sys.exit(f"call site {old} is gone -- dtype.c moved")
        out = out.replace(old, new)
    return out


BEND = REPO / "bin" / "bend"


def emit_rows(hi_a: int, lo_a: int, hi_b: int, lo_b: int) -> list[str]:
    body = [
        "import ./tinybendygrad/dtype.bend as D",
        "import ./tinybendygrad/helpers.bend as H",
        "",
        "def main() -> IO(Unit):",
        "  do IO<Unit>:",
    ]
    for d in DEFS:
        if d == "trunc":
            call = f"D.Dt.i64_trunc(H.i64_of_hi_lo({hi_a}, {lo_a}))"
        else:
            call = (f"D.Dt.i64_{d}(H.i64_of_hi_lo({hi_a}, {lo_a}), "
                    f"H.i64_of_hi_lo({hi_b}, {lo_b}))")
        body.append(f"    r : H.I64 <- {call}")
        body.append(f'    IO.print("SEAM {d} = " ++ H.i64_text(r))')
    return "\n".join(body) + "\n"


def run(fixed: bool, work: pathlib.Path) -> dict[str, str]:
    src = REPO / "tinybendygrad" / "runtime" / "dtype.c"
    dst = work / "tinybendygrad" / "runtime" / "dtype.c"
    dst.write_text(patch(src.read_text(), fixed))
    bend = work / "seam.bend"
    rows: dict[str, str] = {}
    for (a, b) in FIXTURES:
        ha, la = divmod(a & ((1 << 64) - 1), 1 << 32)
        hb, lb = divmod(b & ((1 << 64) - 1), 1 << 32)
        bend.write_text(emit_rows(ha, la, hb, lb))
        c = work / "seam.gen.c"
        r = subprocess.run([str(BEND), str(bend), "-o", str(c)],
                           capture_output=True, text=True)
        if r.returncode != 0 or not c.exists():
            sys.exit(f"bend failed: {r.stdout}\n{r.stderr}")
        exe = work / "seam.gen"
        k = subprocess.run(["cc", "-O1", "-w", "-o", str(exe), str(c)],
                           capture_output=True, text=True)
        if k.returncode != 0:
            sys.exit(f"cc failed: {k.stderr}")
        p = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
        for line in p.stdout.splitlines():
            m = re.match(r"^SEAM (\w+) = (\d+:\d+)$", line)
            if m:
                rows[f"{m[1]}|{a}|{b}"] = m[2]
    return rows


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(REPO / "tinybendygrad", work / "tinybendygrad")
        # the guard test: does the C lane build AT ALL, before any of this?
        broken = run(False, work)
        fixed = run(True, work)
        disarm = run(DISARM, work)

    keys = [f"{d}|{a}|{b}" for (a, b) in FIXTURES for d in DEFS]
    present = [k for k in keys if k in broken and k in fixed and k in disarm]
    print(f"rows present {len(present)} / rows expected {len(keys)}")
    if len(present) != len(keys):
        sys.exit(f"FAIL missing rows {[k for k in keys if k not in broken]}")

    print("\n| def | a, b | CPython (helpers.py) | port, reader as shipped | port, fixed |")
    print("|---|---|---|---|---|")
    bad = agree_after_fix = 0
    for (a, b) in FIXTURES:
        for d in DEFS:
            want = pattern(upstream(d, a, b))
            got_b, got_f = broken[f"{d}|{a}|{b}"], fixed[f"{d}|{a}|{b}"]
            bad += got_b != want
            agree_after_fix += got_f == want
            print(f"| `{d}` | `{a}, {b}` | `{want}` | `{got_b}` | `{got_f}` |")
    print(f"\nshipped reader agrees with CPython on {len(keys) - bad}/{len(keys)} rows")
    print(f"fixed   reader agrees with CPython on {agree_after_fix}/{len(keys)} rows")

    # PLANT: the shipped reader against the fixed one. Every row must move,
    # except where the two agree BY LUCK -- reported, never assumed empty.
    plant = sorted(k for k in keys if broken[k] != fixed[k])
    print(f"\nPLANT (shipped flat reader) rows moved {len(plant)} of {len(keys)}")
    still_same = [k for k in keys if broken[k] == fixed[k]]
    print(f"  rows the plant does NOT move (must be examined, not assumed): {still_same}")

    # DISARM: a different expression for the SAME fixed reader.
    disarm_moved = sorted(k for k in keys if disarm[k] != fixed[k])

    print("\n===== VERDICT =====")
    ok = (agree_after_fix == len(keys) and len(plant) == len(keys)
          and not disarm_moved)
    print(f"PLANT (shipped flat reader) moved {len(plant)}/{len(keys)}")
    print(f"DISARM (`| 0u`, same function) moved {len(disarm_moved)} -- "
          f"{'0 is the only correct count' if not disarm_moved else disarm_moved}")
    print(f"{'PASS' if ok else 'FAIL'}  the 6-line `i64_of` fix takes the C lane's "
          f"64-bit defs from {len(keys) - bad}/{len(keys)} to {agree_after_fix}/{len(keys)} "
          f"against CPython")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()