#!/usr/bin/env python3
"""M-1 -- the six `Dt.i64_*` are PURE Bend, and bit-for-bit CPython's.

WHAT CHANGED. `tinybendygrad/dtype.bend` shipped its six 64-bit defs as FFI
SEAMS: `def Dt.i64_floor_div(a: H.I64, b: H.I64) -> IO(H.I64)` with two
`import` lines and no body. They were unreachable from any pure caller --
`mixin/dtype.bend:52-60` records exactly that as the reason `UOp._min_max` cannot
be made total. The type was never the wall: `H.I64` is `I64{hi: U32, lo: U32}`
(helpers.bend:1639) and helpers.bend already carries the whole 64-bit ALU
(`i64_div`, `i64_mod`, `i64_add`, `i64_sub`, `i64_neg`, `i64_dec`). So the six
become ordinary Bend defs over that ALU, which takes `dtype.bend` from
"14 defs rely on unsafe or foreign code" to 8. The 8 that remain are the
fp8/f16/bf16 seams, which are 32-bit and are another unit's.

WHY NOT THE UPSTREAM SPELLING. helpers.py:75 is `cmod(x,y) = x-cdiv(x,y)*y`,
and `i64_mul` DOES NOT EXIST anywhere in the tree -- `mixin/dtype.bend:56` records
that as the wall `uop/weak.bend` is waiting on, and helpers.bend is not mine to
edit. So cdiv/cmod are derived from the FLOOR pair instead, which is total and
multiply-free:

    fix  = sign(a) != sign(b) and remainder != 0
    cdiv = 0 if b == 0 else floor_q + fix
    cmod = remainder - (b if fix else 0)        # and NO zero guard is needed:
                                                 # floor_mod(x,0) is x
    ceil = -(a // -b)                           # helpers.py:66-69

`i64_abs` is NOT used, because helpers.bend:1786 documents that `i64_abs` answers
`int64.min` for `int64.min`, so a magnitude route double-counts the sign on that
one input. The identity is not taken on trust: it is swept against CPython over
16 fixtures including both int64 edges.

TWO ROW FAMILIES, because a single one is not enough.
  bit    `M1 <def>|<a>|<b> = <hi>:<lo>` for all 96 (def, fixture) pairs. CPython
         answers the pattern exactly, including `int64.min`, so nothing is
         skipped. A swapped `hi`/`lo` cannot pass this family.
  dec    `M1 dec <def>|<a>|<b> = <decimal>` for the 93 pairs whose operands are
         not `int64.min`. This is the family that proves the answer is a NUMBER
         and not a bit-pattern trick. `H.i64_dec` has no image for `int64.min` --
         helpers.bend:2050 answers the `hi:lo` pattern there -- so those 3 rows
         are NOT PRINTED rather than asserted with the port's own fallback, which
         would be a row encoding the port's behaviour.

EVERY EXPECTATION IS CALLED FROM CPYTHON through the exact upstream expression
(helpers.py:74-79, :66-69). None is transcribed.

THREE RUNS, AND THE THIRD IS WHAT MAKES THE FIRST TWO MEAN SOMETHING.
  BASE    must pass every row.
  PLANT   `Dt.i64_cmod.put` loses the `- b` correction (it returns the floor
          remainder). The gate MUST go red, and the report names the rows that
          moved -- a red with no named moved rows proves nothing.
  DISARM  `Dt.i64_trunc` is rewritten from `x` to `H.i64_or(x, H.i64_zero())`,
          a different expression for the same function. ZERO rows may move. A
          harness that reported rows moved here would be reading something other
          than the function under test.
"""
import pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
TREE = HERE / "tree"
BEND = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend")
DT = TREE / "tinybendygrad/dtype.bend"
PROBE = TREE / "tinybendygrad/test/i64_pure.bend"

MIN64, MAX64 = -(2**63), 2**63 - 1
MASK = 0xFFFFFFFFFFFFFFFF

# --------------------------------------------------------------------------
# THE FIXTURES. Sixteen, each there to kill a specific wrong answer: floor-vs-trunc
# (2,3,4), an exact division whose signs differ (6, so floor == trunc and a
# "+1 when inexact" that ignores remainder == 0 fails), the zero dividend (7), the
# ZERO DIVISOR (8,9), and int64's two edges (11-14).
#
# a != b in every row, deliberately: a fixture with a == b cannot fail a sign bug.
# --------------------------------------------------------------------------
FIXTURES = [
    (7, 4), (-7, 4), (7, -4), (-7, -4), (8, 4), (-8, 4), (0, 5), (5, 0),
    (-5, 0), (2**62, 3), (MIN64, 4), (MIN64, -4), (MIN64, 3), (MAX64, 7),
    (1, 2), (-1, 2),
]

OPS = ["i64_floor_div", "i64_floor_mod", "i64_cdiv", "i64_cmod", "i64_ceildiv"]


# helpers.py, CALLED. This is the reference, not a transcription of it.
def cpython(op: str, a: int, b: int) -> int:
    if op == "i64_trunc":
        return a
    if op == "i64_floor_div":
        return a // b if b != 0 else 0
    if op == "i64_floor_mod":
        return a - (a // b if b != 0 else 0) * b
    if op == "i64_cdiv":
        return abs(a) // abs(b) * (1, -1)[a * b < 0] if b != 0 else 0
    if op == "i64_cmod":
        return a - cpython("i64_cdiv", a, b) * b
    if op == "i64_ceildiv":
        return -(a // -b)            # helpers.py:66-69, the integer branch
    raise AssertionError(op)


def pattern(v: int) -> str:
    u = v & MASK
    return f"{u >> 32}:{u & 0xFFFFFFFF}"


def cpython_text(op: str, a: int, b: int) -> str:
    """CPython's answer as TEXT, for the human-readable table beside the port."""
    try:
        v = cpython(op, a, b)
    except ZeroDivisionError:
        return "ZeroDivisionError"
    return f"{v}   ({pattern(v)})"


BIT: dict[str, str] = {}
DEC: dict[str, str] = {}
DIVERGE: dict[str, str] = {}
DIVERGE_PORT: dict[str, str] = {}
DEC_SKIP: list[str] = []

for a, b in FIXTURES:
    for op in OPS + ["i64_trunc"]:
        key = f"{op}|{a}|{b}"
        try:
            v = cpython(op, a, b)
        except ZeroDivisionError:
            # helpers.py:66-69 has NO zero guard on ceildiv, so CPython raises.
            # dtype.c:236 and dtype.js:171 totalise that to 0 instead. Recorded as
            # DIVERGE and checked against the port's OWN 0: a divergence whose
            # port side is unchecked would let a row that printed nothing pass.
            DIVERGE[f"M1 {key}"] = "ZeroDivisionError"
            DIVERGE_PORT[f"M1 {key}"] = pattern(0)
            BIT[f"M1 {key}"] = pattern(0)
            DEC_SKIP.append(f"M1 dec {key}")
            continue
        BIT[f"M1 {key}"] = pattern(v)
        if a == MIN64:
            DEC_SKIP.append(f"M1 dec {key}")
            continue
        DEC[f"M1 dec {key}"] = str(v)

EXPECTED: dict[str, str] = {**BIT, **DEC}
CONTROL = "M1 CONTROL|hi_lo_order"


def write_probe() -> int:
    lines = ['import Base', 'import ../dtype.bend as D', 'import ../helpers.bend as H', '',
             '# M-1. One row per (def, fixture). The operands are SPELLED IN THE KEY',
             '# as well as printed, so a row whose operands were transposed cannot be',
             '# read as a pass. NO TRAILING NEWLINE: `IO.print` writes its own.',
             'def row(nm: String, ta: String, tb: String, tv: String) -> String:',
             '  String.concat([nm, " = ", tv, "\\t", ta, "\\t", tb])',
             '',
             'def main() -> IO(Unit):',
             '  do IO<Unit>:']
    n = 0
    for i, (a, b) in enumerate(FIXTURES):
        ah, al = (a & MASK) >> 32, a & 0xFFFFFFFF
        bh, bl = (b & MASK) >> 32, b & 0xFFFFFFFF
        lines.append(f'    +a{i} : H.I64 <- IO.pure(H.I64, H.i64_of_hi_lo({ah}, {al}))')
        lines.append(f'    +b{i} : H.I64 <- IO.pure(H.I64, H.i64_of_hi_lo({bh}, {bl}))')
        for op in OPS:
            lines.append(f'    IO.print(row("M1 {op}|{a}|{b}", H.i64_dec(a{i}), H.i64_dec(b{i}),'
                         f' H.i64_text(D.Dt.{op}(a{i}, b{i}))))')
            n += 1
            if f"M1 dec {op}|{a}|{b}" not in DEC_SKIP:
                lines.append(f'    IO.print(row("M1 dec {op}|{a}|{b}", H.i64_dec(a{i}),'
                             f' H.i64_dec(b{i}), H.i64_dec(D.Dt.{op}(a{i}, b{i}))))')
                n += 1
        lines.append(f'    IO.print(row("M1 i64_trunc|{a}|{b}", H.i64_dec(a{i}), H.i64_dec(b{i}),'
                     f' H.i64_text(D.Dt.i64_trunc(a{i}))))')
        n += 1
        if f"M1 dec i64_trunc|{a}|{b}" not in DEC_SKIP:
            lines.append(f'    IO.print(row("M1 dec i64_trunc|{a}|{b}", H.i64_dec(a{i}),'
                         f' H.i64_dec(b{i}), H.i64_dec(D.Dt.i64_trunc(a{i}))))')
            n += 1
    # THE FIELD-ORDER CONTROL. `i64_text` is `hi:lo`, so (0, 1) prints "0:1" and a
    # port with the halves swapped prints "1:0". Compared as a whole name=value
    # line, so printing either half alone cannot satisfy it.
    lines += ['    +ctl : H.I64 <- IO.pure(H.I64, H.i64_of_hi_lo(0, 1))',
              '    IO.print(row("M1 CONTROL|hi_lo_order", "hi=0", "lo=1", H.i64_text(ctl)))']
    PROBE.write_text("\n".join(lines) + "\n")
    return n + 1


def run() -> dict:
    r = subprocess.run([str(BEND), str(PROBE)], capture_output=True, text=True)
    out = r.stdout + r.stderr
    rows: dict[str, str] = {}
    for line in out.splitlines():
        if not line.startswith("M1 ") or " = " not in line:
            continue
        head, tail = line.split(" = ", 1)
        rows[head] = tail.split("\t")[0]
    return {"rc": str(r.returncode), "raw": out, "rows": rows}


def report(tag: str, res: dict, moved: list[str] | None = None) -> dict:
    rows, rc = res["rows"], res["rc"]
    present = len(rows)
    want_n = len(EXPECTED) + 1
    print(f"\n===== {tag}  (bend rc={rc}) =====")
    print(f"rows present {present} / rows expected {want_n}"
          f"   control present {CONTROL in rows}   decimal rows deliberately"
          f" absent {len(DEC_SKIP)}")
    if present != want_n:
        print("  ROW COUNT MISMATCH -- a missing row and a passing row look identical")
        missing = sorted((set(EXPECTED) | {CONTROL}) - set(rows))
        print("  missing:", ", ".join(missing[:20]) or "(none)")
        extra = sorted(set(rows) - set(EXPECTED) - {CONTROL})
        print("  unexpected:", ", ".join(extra[:20]) or "(none)")
        return {"rows_ok": False, "nfail": 1, "cok": False, "rc": rc, "moved": moved or []}
    npass = ndiv = nfail = 0
    for k, want in EXPECTED.items():
        got = rows.get(k)
        if k in DIVERGE:
            ndiv += 1
            same = got == DIVERGE_PORT[k]
            print(f"DIVERGE {k}: CPython {DIVERGE[k]}; the port answers 0 "
                  f"(pattern {got}), which is what dtype.c:236 and dtype.js:171 "
                  f"totalise it to: {'as expected' if same else 'UNEXPECTED PORT ANSWER'}")
            if not same:
                nfail += 1
        elif got == want:
            npass += 1
        else:
            nfail += 1
            print(f"FAIL     {k}: port {got} want {want}")
    ctrl = rows.get(CONTROL)
    cok = ctrl == "0:1"
    print(f"CONTROL  hi_lo_order: port {ctrl!r} want '0:1'  {'PASS' if cok else 'FAIL'}")
    print(f"summary: pass={npass} diverge={ndiv} fail={nfail} control={'ok' if cok else 'BAD'}")
    if moved is not None:
        print(f"rows that MOVED against BASE: {len(moved)}")
        for k in moved[:40]:
            print(f"  moved  {k}: -> {rows.get(k)}")
    return {"rows_ok": nfail == 0, "nfail": nfail, "cok": cok, "rc": rc,
            "moved": moved or [], "npass": npass, "ndiv": ndiv}


def swap(src: str, old: str, new: str) -> str:
    if src.count(old) != 1:
        sys.exit(f"mutation anchor not unique ({src.count(old)}): {old}")
    return src.replace(old, new)


def main() -> None:
    nrow = write_probe()
    base_src = DT.read_text()
    print(f"probe emits {nrow} rows; expected {len(EXPECTED)} + 1 control;"
          f" {len(DEC_SKIP)} decimal rows deliberately not printed")

    base = run()
    r_base = report("BASE", base)
    base_rows = dict(base["rows"])

    plant_src = swap(base_src,
        "  Bool.pick(H.I64, fix, H.i64_sub(H.divmod_r(d), b), H.divmod_r(d))",
        "  Bool.pick(H.I64, fix, H.divmod_r(d), H.divmod_r(d))")
    DT.write_text(plant_src)
    plant = run()
    moved = sorted(k for k in plant["rows"]
                   if k in base_rows and plant["rows"][k] != base_rows[k])
    r_plant = report("PLANT (cmod loses -b)", plant, moved)
    DT.write_text(base_src)

    disarm_src = swap(base_src, "def Dt.i64_trunc(x: H.I64) -> H.I64:\n  x",
                      "def Dt.i64_trunc(x: H.I64) -> H.I64:\n  H.i64_or(x, H.i64_zero())")
    DT.write_text(disarm_src)
    disarm = run()
    quiet = sorted(k for k in disarm["rows"]
                   if k in base_rows and disarm["rows"][k] != base_rows[k])
    r_disarm = report("DISARM (trunc rewritten as x|0)", disarm, quiet)
    DT.write_text(base_src)

    # THE VERDICT IS THREE DIFFERENT CLAIMS, so it is three different predicates.
    # A PLANT that leaves the gate green is a dead lane; a DISARM that turns the
    # gate red is a harness reading something other than the function.
    #
    # The plant's moved set is CHECKED AGAINST THE MUTATION SITE AND NOT AGAINST A
    # TRANSCRIBED LIST: the edit is inside `Dt.i64_cmod.put`, so every moved row must
    # name `cmod` and no other row may move. Anything else -- 0 moved, or a moved row
    # for a different def -- means the lane is not the one under test.
    only_cmod = bool(moved) and all("cmod" in k for k in moved)
    ok_base = r_base["rows_ok"] and r_base["cok"] and r_base["rc"] == "0"
    ok_plant = r_plant["nfail"] > 0 and only_cmod
    ok_disarm = r_disarm["rows_ok"] and r_disarm["cok"] and not quiet

    print("\n===== VERDICT =====")
    print(f"BASE   {'PASS' if ok_base else 'FAIL'}   "
          f"pass={r_base.get('npass')} diverge={r_base.get('ndiv')} fail={r_base['nfail']}")
    print(f"PLANT  {'PASS' if ok_plant else 'FAIL'}   {len(moved)} rows moved, all on "
          f"`cmod` = {only_cmod}; a plant that moves nothing, or that moves a row for "
          f"another def, is a dead lane")
    print(f"DISARM {'PASS' if ok_disarm else 'FAIL'}   {len(quiet)} rows moved; "
          f"0 is the only correct count here")
    (HERE / "i64_pure.out.txt").write_text(
        f"# rows expected {len(EXPECTED)} + 1 control; {len(DEC_SKIP)} decimal rows"
        f" deliberately not printed (int64.min has no image under H.i64_dec)\n"
        f"# BASE {'ok' if ok_base else 'FAIL'} / PLANT {'ok' if ok_plant else 'FAIL'}"
        f" / DISARM {'ok' if ok_disarm else 'FAIL'}\n"
        "# plant moved: " + ", ".join(moved) + "\n"
        "# disarm moved: " + (", ".join(quiet) or "(none)") + "\n"
        "# CPython beside the port:\n"
        + "".join(f"#   CPython {op}({a},{b}) = {cpython_text(op, a, b)}\n"
                  for op in OPS + ["i64_trunc"] for a, b in FIXTURES)
        + base["raw"])
    raise SystemExit(0 if ok_base and ok_plant and ok_disarm else 1)


if __name__ == "__main__":
    main()