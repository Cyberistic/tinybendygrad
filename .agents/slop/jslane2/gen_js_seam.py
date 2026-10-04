#!/usr/bin/env python3
"""gen_js_seam.py -- the SAME 30 rows as w64mile/gen_seam.py, run under `node`.

Reproduce (from the repo root):
    python3 .agents/slop/jslane2/gen_js_seam.py

Row-for-row comparable with `.agents/slop/w64mile/gen_seam.py`: the same 6 DEFS,
the same 5 FIXTURES (including `int64.min`), the same `hi:lo` printing, and the
same oracle -- `tinygrad/helpers.py` called, never transcribed.

WHAT THIS ESTABLISHES THAT NOTHING ELSE HAD.  `bend <f.bend> -o <f>.js` emits
`Comp.js_book` (`references/bend/bend2/main.ts:361`) and every `import "./x.js"`
is embedded verbatim (`comp.ts:3385`, `effect_srcs(fl, ".js", ...)`), so the JS
lane is not a stub: it compiles and `node` runs it.  What it does is disagree.

THE FINDING.  A `H.I64` record crosses into JS as a JS OBJECT WITH ITS FIELD
NAMES -- `{"$":"...I64","hi":0,"lo":7}` -- not as positional `fst`/`snd`.
`dtype.js:136-137` reads `p.fst` / `p.snd`, both `undefined`, and
`undefined >>> 0 === 0`, so `i64_of` answers `0n` for EVERY input.
`Dt.i64_trunc` -- the identity -- is not the identity under this lane.
`pack64` then returns `io_tup(...)`, i.e. `{"$":"Tuple","fst":..,"snd":..}`,
where the Bend caller reads `{hi, lo}`, so even the `0n` does not come back.

FOUR ARMS, all on a `$TMPDIR` COPY; the live tree is never written.
  shipped  -- dtype.js exactly as committed.  THE MEASUREMENT.
  repaired -- scratch only: read `p.hi`/`p.lo`, answer `{hi, lo}`.  This is the
              DIAGNOSIS, and it is explicitly NOT applied to the tree, because
              the brief is report-do-not-edit and because declaring the ABI is
              the coordinator's call.
  PLANT    -- repaired with the pair order swapped to `lo << 32 | hi`.  This is
              the "nothing states or checks the order" hazard, made to move rows.
  DISARM   -- repaired with a DIFFERENT EXPRESSION for the SAME value, so the
              only correct moved-set against it is the empty one.

ROW FORM.  `SEAM <def> #<k> = <value>`.  The `#<k>` makes a row COUNTABLE even
when its value is garbage: "the row is absent" and "the row is present and
wrong" must not print the same thing, which is how a totalised-0 lane gets
reported as green.
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
MASK64 = (1 << 64) - 1
INT64_MIN = -(1 << 63)

DEFS = ["trunc", "floor_div", "floor_mod", "cdiv", "cmod", "ceildiv"]
FIXTURES = [(7, 4), (-7, 4), (-8, 4), (7, -4), (INT64_MIN, 3)]

# ---- dtype.js anchors. Each must be unique or this exits; a moved anchor means
# ---- the file changed under us and every number below is stale.
READ_SHIPPED = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.fst >>> 0) << 32n) | BigInt(p.snd >>> 0));
}"""
READ_REPAIRED = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.hi >>> 0) << 32n) | BigInt(p.lo >>> 0));
}"""
# The PLANT: same arithmetic, halves swapped. Nothing in either lane declares
# which word is high, so this is the mutation the missing ABI would forbid.
READ_SWAPPED = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.lo >>> 0) << 32n) | BigInt(p.hi >>> 0));
}"""
# The DISARM: a different EXPRESSION for the same value -- `(h << 32n) | l` and
# `h * 2n**32n + l` are the same function over h,l in [0, 2**32) -- and it stays in
# BigInt arithmetic, so 0 is the only correct moved-set.
READ_DISARM = """function i64_of(p) {
  return BigInt.asIntN(64, BigInt(p.hi >>> 0) * 4294967296n + BigInt(p.lo >>> 0));
}"""
# NOT A DISARM -- a SECOND PLANT, kept because it was mistaken for one.  This is
# the tempting `h * 2**32 + l` in ORDINARY `Number` arithmetic.  A double has 53
# mantissa bits and the spacing on [2**63, 2**64) is 2**11, so `hi * 4294967296`
# is only exact when `hi < 2**21` (or `hi` is a power of two).  It moves rows, and
# every row it moves is explained by that, not by luck.
READ_NUMPROD = """function i64_of(p) {
  return BigInt.asIntN(64, BigInt((p.hi >>> 0) * 4294967296 + (p.lo >>> 0)));
}"""

PACK_SHIPPED = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return io_tup(Number((u >> 32n) & 0xffffffffn), Number(u & 0xffffffffn));
}"""
PACK_REPAIRED = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return {$: "tinybendygrad/helpers.I64", hi: Number((u >> 32n) & 0xffffffffn),
          lo: Number(u & 0xffffffffn)};
}"""


def upstream(name: str, a: int, b: int) -> int:
    """CPython, by CALLING tinygrad's own helper. Never transcribed."""
    return {"trunc": lambda: a,
            "floor_div": lambda: floordiv(a, b),
            "floor_mod": lambda: floormod(a, b),
            "cdiv": lambda: cdiv(a, b),
            "cmod": lambda: cmod(a, b),
            "ceildiv": lambda: ceildiv(a, b)}[name]()


def inexact(hi: int) -> bool:
    """Is `hi * 2**32` exact in a double?  53 mantissa bits: the product is exact
    below 2**53, and above that only when `hi` is a power of two."""
    return hi != 0 and (hi >= (1 << 21)) and (hi & (hi - 1)) != 0


def pattern(v: int) -> str:
    return f"{((v >> 32) & U32)}:{v & U32}"


def patch(src: str, read: str, pack: str) -> str:
    for anchor in (READ_SHIPPED, PACK_SHIPPED):
        if src.count(anchor) != 1:
            sys.exit(f"anchor not unique ({src.count(anchor)}x) -- dtype.js moved:\n{anchor}")
    return src.replace(READ_SHIPPED, read).replace(PACK_SHIPPED, pack)


ARMS = {
    "shipped": (READ_SHIPPED, PACK_SHIPPED),
    "repaired": (READ_REPAIRED, PACK_REPAIRED),
    "plant": (READ_SWAPPED, PACK_REPAIRED),
    "disarm": (READ_DISARM, PACK_REPAIRED),
    "numprod": (READ_NUMPROD, PACK_REPAIRED),
}

BEND = REPO / "bin" / "bend"
ROW = re.compile(r"^SEAM (\w+) #(\d+) = (.*)$")


def emit_rows(k: int, hi_a: int, lo_a: int, hi_b: int, lo_b: int) -> str:
    body = ["import ./tinybendygrad/dtype.bend as D",
            "import ./tinybendygrad/helpers.bend as H", "",
            "def main() -> IO(Unit):", "  do IO<Unit>:"]
    for d in DEFS:
        if d == "trunc":
            call = f"D.Dt.i64_trunc(H.i64_of_hi_lo({hi_a}, {lo_a}))"
        else:
            call = (f"D.Dt.i64_{d}(H.i64_of_hi_lo({hi_a}, {lo_a}), "
                    f"H.i64_of_hi_lo({hi_b}, {lo_b}))")
        body.append(f"    r : H.I64 <- {call}")
        body.append(f'    IO.print("SEAM {d} #{k} = " ++ H.i64_text(r))')
    return "\n".join(body) + "\n"


def run(arm: str, work: pathlib.Path, target: str = "js") -> dict[str, str]:
    read, pack = ARMS[arm]
    (work / "tinybendygrad" / "runtime" / "dtype.js").write_text(
        patch((REPO / "tinybendygrad" / "runtime" / "dtype.js").read_text(), read, pack))
    bend = work / "seam.bend"
    rows: dict[str, str] = {}
    for k, (a, b) in enumerate(FIXTURES):
        ha, la = divmod(a & ((1 << 64) - 1), 1 << 32)
        hb, lb = divmod(b & ((1 << 64) - 1), 1 << 32)
        bend.write_text(emit_rows(k, ha, la, hb, lb))
        if target == "js":
            out, cmd = work / "seam.js", ["node", str(work / "seam.js")]
            r = subprocess.run([str(BEND), str(bend), "-o", str(out)],
                               capture_output=True, text=True)
            if r.returncode != 0 or not out.exists():
                sys.exit(f"bend failed ({arm}): {r.stdout}\n{r.stderr}")
        else:
            out = work / "seam.gen.c"
            r = subprocess.run([str(BEND), str(bend), "-o", str(out)],
                               capture_output=True, text=True)
            if r.returncode != 0 or not out.exists():
                sys.exit(f"bend failed ({arm}): {r.stdout}\n{r.stderr}")
            k2 = subprocess.run(["cc", "-O1", "-w", "-o", str(work / "seam.gen"), str(out)],
                                capture_output=True, text=True)
            if k2.returncode != 0:
                sys.exit(f"cc failed ({arm}): {k2.stderr}")
            cmd = [str(work / "seam.gen")]
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        for line in p.stdout.splitlines():
            m = ROW.match(line)
            if m:
                rows[f"{m[1]}|{a}|{b}"] = m[3]
    return rows


def table(keys: list[str], arms: dict[str, dict[str, str]], cpy: dict[str, str]) -> None:
    names = list(arms)
    print(f"\n| def | a, b | CPython | " + " | ".join(names) + " |")
    print("|---|---|---|" + "---|" * len(names))
    for k in keys:
        cells = " | ".join(f"`{arms[n][k]}`" for n in names)
        print(f"| `{k.split('|')[0]}` | `{k.split('|', 1)[1]}` | `{cpy[k]}` | {cells} |")


def main() -> None:
    keys = [f"{d}|{a}|{b}" for (a, b) in FIXTURES for d in DEFS]
    cpy = {k: pattern(upstream(k.split("|")[0], *[int(x) for x in k.split("|")[1:]]))
           for k in keys}

    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(REPO / "tinybendygrad", work / "tinybendygrad")
        shutil.copytree(REPO / "tinybendygrad", work / "c_only", dirs_exist_ok=True)
        arms = {a: run(a, work) for a in ARMS}
        # The C lane, from the SAME rows, for a lane-against-lane diff. dtype.c
        # is byte-unchanged by this script.
        lanes = {"node (shipped JS)": arms["shipped"],
                 "c (shipped C)": run("shipped", work, target="c")}

    print("ROWS PRESENT vs ROWS EXPECTED  (every arm, every run)")
    for a, r in arms.items():
        miss = [k for k in keys if k not in r]
        print(f"  {a:<9} present {len(keys) - len(miss):>2} / expected {len(keys)}"
              + (f"   MISSING {miss}" if miss else ""))
    for n, r in lanes.items():
        miss = [k for k in keys if k not in r]
        print(f"  {n:<18} present {len(keys) - len(miss):>2} / expected {len(keys)}"
              + (f"   MISSING {miss}" if miss else ""))

    table(keys, {**arms, "c": lanes["c (shipped C)"]}, cpy)

    print("\nAGREEMENT WITH CPYTHON (helpers.py, called)")
    for a, r in arms.items():
        ok = sum(r.get(k) == cpy[k] for k in keys)
        print(f"  {a:<9} {ok:>2}/{len(keys)}")
    ok = sum(lanes["c (shipped C)"].get(k) == cpy[k] for k in keys)
    print(f"  {'c':<9} {ok:>2}/{len(keys)}")

    def lanelike(name: str) -> int:
        return sum(arms[name].get(k) == lanes["c (shipped C)"].get(k) for k in keys)

    print("\nLANE vs LANE (node against cc, same 30 rows)")
    print(f"  shipped JS identical to shipped C on {lanelike('shipped')}/{len(keys)}")
    print(f"  repaired JS identical to shipped C on {lanelike('repaired')}/{len(keys)}"
          "  <- `asIntN(64,.)` vs `(s64)` over every reachable operand")

    plant = sorted(k for k in keys if arms["plant"][k] != arms["repaired"][k])
    unmoved = [k for k in keys if arms["plant"][k] == arms["repaired"][k]]
    print(f"\nPLANT (halves swapped, `lo << 32 | hi`) rows moved {len(plant)}/{len(keys)}")
    print(f"  rows it does NOT move: {unmoved}")
    print(f"  reason, to be CHECKED not assumed: swapping is invisible exactly when "
          f"hi == lo, and every unmoved row is")
    for k in unmoved:
        print(f"    {k}: CPython {cpy[k]}  (hi == lo == {cpy[k].split(':')[0]})")
    arm_moved = sorted(k for k in keys if arms["disarm"][k] != arms["repaired"][k])
    print(f"\nDISARM (`h * 2n**32n + l`, BigInt, same function) moved {len(arm_moved)} -- "
          f"{'0 is the only correct count' if not arm_moved else arm_moved}")

    npx = sorted(k for k in keys if arms["numprod"][k] != arms["repaired"][k])
    print(f"\nSECOND PLANT (`h * 2**32 + l` in Number arithmetic -- NOT a disarm) "
          f"moved {len(npx)}/{len(keys)}")
    print("  `hi * 4294967296` in doubles is exact iff hi == 0, hi < 2**21, or hi is a")
    print("  power of two. Attribute it per OPERAND, not per result:")
    for k in npx:
        d, a, b = k.split("|")
        ops = [("a", a)] if d == "trunc" else [("a", a), ("b", b)]
        bad = [n for n, v in ops if inexact((int(v) & MASK64) >> 32)]
        print(f"    {k:<36} operand {','.join(bad) or '-':<4} has an inexact hi half"
              f"  CPython {cpy[k]:<24} this arm {arms['numprod'][k]}")
    print("  this is the answer to 'can the JS lane differ where the C lane does not': NOT in"
          "\n  `asIntN(64,.)` vs `(s64)`, which are the same function, but in the ARITHMETIC"
          "\n  the operand arrives through. BigInt is load-bearing here, not stylistic.")

    print("\n===== VERDICT =====")
    live = (len(plant) == len(keys) - len(unmoved) and not arm_moved
            and arms["repaired"] == {k: cpy[k] for k in keys}
            and lanelike("repaired") == len(keys))
    base_red = sum(arms["shipped"].get(k) == cpy[k] for k in keys) < len(keys)
    print(f"gate is LIVE: {bool(live)}  (plant moves the ordered rows, the real disarm "
          f"moves none, repaired agrees with CPython and with the C lane)")
    print(f"shipped JS lane agrees with CPython on "
          f"{sum(arms['shipped'].get(k) == cpy[k] for k in keys)}/{len(keys)} -- "
          f"{'RED' if base_red else 'green'}")
    sys.exit(0 if live else 1)


if __name__ == "__main__":
    main()