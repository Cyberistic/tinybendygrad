#!/usr/bin/env python3
"""compare.py -- THE PORT's OWN NUMBERS AGAINST CPython's OWN NUMBERS.

    .venv/bin/python .agents/slop/cpuseam/compare.py                     # the real run
    .venv/bin/python .agents/slop/cpuseam/compare.py --plant              # the real run AND the plant
    .venv/bin/python .agents/slop/cpuseam/compare.py --kernel r_10_98_4

WHAT IT COMPARES, AND WHY IT IS NOT A LABEL:

  * The PORT's OWN SEAM (`/tmp/launch <kernel> <cc>`) renders the C WITH THE
    PORT's OWN `cstyle.bend`, COMPILES IT WITH `cc`, `dlopen`s IT AND CALLS
    IT.  The bytes it prints back are the OUTPUT BUFFERS.
  * The ORACLE is `bufs/<kernel>.rows`, WHICH CPython's OWN DEVICE WROTE: the
    `bufN <hex>` LINES ARE THE INPUTS AND THE `# bufN after <hex>` LINES ARE
    WHAT CPython's OWN `CPUProgram` PRODUCED FROM THOSE INPUTS.

⇒ THE ROW IS A COMPARISON OF TWO SETS OF BYTES THAT WERE COMPUTED BY TWO
DIFFERENT MACHINES.  IT IS RED WHEN THEY DIFFER.

⇒ AND THE CONTROL IS IN THE SAME ROW: `changed` COUNTS THE BUFFERS WHERE THE
PORT's OUTPUT DIFFERS FROM THE *INPUT*.  A ROW THAT SAID "output matches"
WITHOUT THAT COUNT WOULD BE SATISFIED BY A SEAM THAT DID NOTHING.

⇒ AND THE PLANT IS THE ROW THAT PROVES THE COMPARISON CAN GO RED: THE PLANT
IS A WRAPPER `cc` (THE SEAM's OWN `cc` PARAMETER) THAT REWRITES ONE TOKEN OF
THE RENDERED C, SO NEITHER THE PORT NOR THE HARNESS CARRIES A TEST-ONLY
BRANCH.  THE PLANT'S ROW MUST BE `FAIL`.
"""
import os
import pathlib
import struct
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
KERNELS = ["r_10_98_4", "r_2_14_14_4_4_3_3", "r_4_28_7_4_3_3",
            "r_56_14_2_2", "r_56_7_2_2"]
CC = "/usr/bin/cc"

# THE PLANT: ONE TOKEN OF THE RENDERED C, PER KERNEL.  THE WRAPPER REFUSES IF
# THE TOKEN IS ABSENT, SO A PLANT CANNOT SILENTLY DO NOTHING.
PLANT = {
    "r_10_98_4": ("((*(buf0+0))+val2)", "((*(buf0+0))-val2)"),
    "r_2_14_14_4_4_3_3": ("*(data0_1568+(alu16+196)) = alu22;",
                          "*(data0_1568+(alu16+196)) = alu23;"),
    "r_4_28_7_4_3_3": ("(float4){alu13,alu10,alu11,alu12}",
                       "(float4){alu10,alu11,alu12,alu13}"),
    "r_56_14_2_2": ("((val1[0]<val1[1])?val1[1]:val1[0])",
                    "((val1[0]<val1[1])?val1[0]:val1[1])"),
    "r_56_7_2_2": ("((val1[0]<val1[1])?val1[1]:val1[0])",
                   "((val1[0]<val1[1])?val1[0]:val1[1])"),
}


def read_fixture(name: str):
    """the oracle: (inputs, outputs, sizes) as bytes."""
    ins, outs, sizes = [], [], []
    for ln in (HERE / "bufs" / f"{name}.rows").read_text().splitlines():
        if ln.startswith("sizes "):
            sizes = [int(x) for x in ln.split(" ")[1].split(",")]
        elif ln.startswith("# buf") and " after " in ln:
            outs.append(bytes.fromhex(ln.split(" after ")[1]))
        elif ln.startswith("buf"):
            ins.append(bytes.fromhex(ln.split(" ")[1]))
    return ins, outs, sizes


def run(launch: str, name: str, cc: str):
    p = subprocess.run([launch, name, cc], capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"the seam failed rc={p.returncode}: {p.stderr.strip()}")
    lines = p.stdout.splitlines()
    if len(lines) != 2 or not lines[0].startswith("sizes="):
        raise RuntimeError(f"the seam's output is not two lines: {p.stdout[:200]!r}")
    sizes = [int(x) for x in lines[0][len("sizes="):].split(",")]
    blob = bytes.fromhex(lines[1])
    out, off = [], 0
    for n in sizes:
        out.append(blob[off:off + n])
        off += n
    if off != len(blob):
        raise RuntimeError(f"the hex is {len(blob)} bytes but the sizes sum to {off}")
    return out, sizes


def f32_maxerr(a: bytes, b: bytes):
    """the largest absolute and relative difference over the f32 values."""
    if len(a) != len(b) or len(a) % 4:
        return None, None
    xs = struct.unpack(f"<{len(a) // 4}f", a)
    ys = struct.unpack(f"<{len(b) // 4}f", b)
    amax, rmax = 0.0, 0.0
    for x, y in zip(xs, ys):
        d = abs(x - y)
        amax = max(amax, d)
        den = max(abs(x), abs(y))
        if den > 0:
            rmax = max(rmax, d / den)
    return amax, rmax


def row(nm: str, got, ins, outs, sizes, label: str) -> str:
    changed = sum(1 for g, i in zip(got, ins) if g != i)
    match = sum(1 for g, o in zip(got, outs) if g == o)
    amax, rmax = 0.0, 0.0
    for g, o in zip(got, outs):
        a, r = f32_maxerr(g, o)
        if a is not None:
            amax, rmax = max(amax, a), max(rmax, r)
    ok = match == len(outs)
    return (f"{nm} {label} bufs={len(outs)} sizes={sizes} output_match={match}/{len(outs)} "
            f"changed_vs_input={changed}/{len(outs)} max_abs={amax:.6g} max_rel={rmax:.6g} "
            f"verdict={'PASS' if ok else 'FAIL'}")


def main() -> int:
    argv = sys.argv[1:]
    plant = "--plant" in argv
    launch = "/tmp/launch"
    names = list(KERNELS)
    if "--launch" in argv:
        launch = argv[argv.index("--launch") + 1]
    if "--kernel" in argv:
        names = [argv[argv.index("--kernel") + 1]]

    rows, prows = [], []
    bad = 0
    for nm in names:
        ins, outs, sizes = read_fixture(nm)
        try:
            got, got_sizes = run(launch, nm, CC)
            if got_sizes != sizes:
                raise RuntimeError(f"the sizes differ port={got_sizes} oracle={sizes}")
            r = row(nm, got, ins, outs, sizes, "real")
            rows.append(r)
            print(r)
            if not r.endswith("verdict=PASS"):
                bad += 1
        except RuntimeError as e:
            print(f"{nm} real: {e}")
            bad += 1
        if not plant:
            continue
        old, new = PLANT[nm]
        os.environ["PLANT_OLD"], os.environ["PLANT_NEW"] = old, new
        try:
            got, _ = run(launch, nm, str(HERE / "plant-cc.py"))
            r = row(nm, got, ins, outs, sizes, "plant")
            prows.append(r)
            print(r)
            if not r.endswith("verdict=FAIL"):
                print(f"{nm}: THE PLANT DID NOT GO RED")
                bad += 1
        except RuntimeError as e:
            print(f"{nm} plant: {e}")
            prows.append(f"{nm} plant ERROR {e}")
            bad += 1
    os.environ.pop("PLANT_OLD", None)
    os.environ.pop("PLANT_NEW", None)

    (HERE / "compare.rows").write_text(
        "# compare.py -- the port's own numbers against CPython's own numbers\n"
        + "\n".join(rows) + "\n")
    print(f"# wrote compare.rows  fail={bad}")
    if plant:
        (HERE / "compare-plant.rows").write_text(
            "# compare.py -- THE PLANT: one token of the rendered C, per kernel\n"
            + "\n".join(prows) + "\n")
        print(f"# wrote compare-plant.rows  fail={bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
