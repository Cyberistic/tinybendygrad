#!/usr/bin/env python3
"""pipeline.py -- THE PORT's OWN CODE, END TO END, WITH A PLANT AS THE CONTROL.

    .venv/bin/python .agents/slop/cpuseam/pipeline.py

THE FOUR STAGES, AND WHO DOES EACH:

  1. THE PORT's OWN RENDERER. `bun /tmp/render.js <kernel>` IS THE PORT's OWN
     `renderer/cstyle.bend` (`C.render`) COMPILED TO THE JS LANE. ITS OUTPUT IS
     COMPARED, WHOLE FILE, WITH UPSTREAM's OWN `ClangRenderer` OUTPUT
     (`csrc/<kernel>.c`).
  2. `cc` WITH UPSTREAM's OWN ARGV (support/compiler_cpu.py:21-22), WHICH IS ALSO
     THE PORT's OWN SPELLING (`support/compiler_cpu.bend:268`). THE ELF OBJECT
     GOES TO `elf/<kernel>.hex`.
  3. THE PORT's OWN RELOCATOR. `bun /tmp/relocate.js <kernel>` IS THE PORT's OWN
     `runtime/support/elf.bend` (`E.Ehdr.at` -> `E.elf_loader` -> `E.jit_loader`).
     ITS IMAGE IS COMPARED, BYTE FOR BYTE, WITH UPSTREAM's OWN `jit_loader`
     (support/elf.py:52-86) ON THE SAME ELF OBJECT.
  4. THE CALL. THE IMAGE IS MMAPPED AND CALLED, EXACTLY AS UPSTREAM's
     `CPUProgram` DOES (ops_cpu.py:29-35, :46, :61), AND THE OUTPUT BUFFERS ARE
     COMPARED WITH CPython's OWN CPU DEVICE's OUTPUT.

⇒ STAGE 4 IS THE ONLY STAGE NOT SPELLED IN THE PORT's OWN SOURCE, AND IT IS
THE 30 LINES OF `runtime/ops_cpu.c` -- WHICH CANNOT RUN ON THIS MACHINE: EVERY
LOCALLY-BUILT BINARY IS KILLED BY THE KERNEL's `AppleSystemPolicy` ("Security
policy would not allow process"), MEASURED AND WRITTEN UP IN THE REPORT. ⇒ SO
STAGE 4 IS SPELLED IN PYTHON HERE, AND IT IS SPELLED AS UPSTREAM SPELLS IT.

⇒ AND THE PLANT IS THE CONTROL: THE SAME FOUR STAGES WITH A WRAPPER `cc` THAT
REWrites ONE TOKEN OF THE RENDERED C. THE PLANT's ROW MUST BE `FAIL` -- THE
PLANTED OUTPUT MUST DIFFER FROM CPython's -- OR THE COMPARISON IS A LABEL.
"""
import ctypes
import mmap
import os
import pathlib
import struct
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent.parent))

MAP_JIT = 0x0800
BUN = "/Users/cyberistic/.bun/bin/bun"
RENDER_JS = "/tmp/render.js"
RELOC_JS = "/tmp/relocate.js"
KERNELS = ["r_10_98_4", "r_2_14_14_4_4_3_3", "r_4_28_7_4_3_3",
            "r_56_14_2_2", "r_56_7_2_2"]
CC = os.environ.get("CC", "clang")

# UPSTREAM's OWN ARGV (support/compiler_cpu.py:21-22) WITH `arch`'s OWN FLAGS
# (support/compiler_cpu.py:13-16) FOR THIS MACHINE: `platform.machine()` IS
# "arm64" AND UPSTREAM APPENDS ",native" (ops_cpu.py:76).
ARGV = [CC, "-c", "-x", "c", "-O2", "-fPIC", "-ffreestanding", "-fno-math-errno",
        "-nostdlib", "-fno-ident", "--target=arm64-none-unknown-elf",
        "-ffixed-x18", "-mcpu=native", "-", "-o", "-"]

# THE PLANT: ONE TOKEN OF THE RENDERED C, PER KERNEL. THE WRAPPER REFUSES IF
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

from tinygrad.runtime.support.elf import jit_loader  # noqa: E402


def port_render(nm: str) -> str:
    p = subprocess.run([BUN, RENDER_JS, nm], capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"the port's renderer failed rc={p.returncode}: {p.stderr[:200]}")
    return p.stdout


def port_relocate(nm: str) -> str:
    p = subprocess.run([BUN, RELOC_JS, nm], capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"the port's relocator failed rc={p.returncode}: {p.stderr[:200]}")
    return p.stdout.strip()


def compile_elf(src: str, cc: str) -> bytes:
    argv = list(ARGV)
    argv[0] = cc
    return subprocess.check_output(argv, input=src.encode())


def oracle_buffers(nm: str):
    ins, outs = [], []
    for ln in (HERE / "bufs" / f"{nm}.rows").read_text().splitlines():
        if ln.startswith("# buf") and " after " in ln:
            outs.append(bytes.fromhex(ln.split(" after ")[1]))
        elif ln.startswith("buf"):
            ins.append(bytes.fromhex(ln.split(" ")[1]))
    return ins, outs


def call_image(image: bytes, ins):
    """mmap the image and call it, exactly as upstream's CPUProgram does."""
    mem = mmap.mmap(-1, len(image), mmap.MAP_ANON | mmap.MAP_PRIVATE | MAP_JIT,
                    mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
    addr = ctypes.addressof(ctypes.c_char.from_buffer(mem))
    rt = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    rt.pthread_jit_write_protect_np.argtypes = [ctypes.c_int]
    rt.pthread_jit_write_protect_np(0)
    mem.write(image)
    rt.pthread_jit_write_protect_np(1)
    rt.__clear_cache(ctypes.c_void_p(addr), ctypes.c_void_p(addr + len(image)))
    bufs = [(ctypes.create_string_buffer(b), len(b)) for b in ins]
    fn = ctypes.CFUNCTYPE(None, *(ctypes.c_void_p for _ in bufs))(addr)
    fn(*[ctypes.cast(b, ctypes.c_void_p) for b, _ in bufs])
    return [b.raw[:n] for b, n in bufs]


def maxerr(a: bytes, b: bytes):
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


def main() -> int:
    bad = 0
    rows, prows = [], []
    for nm in KERNELS:
        src = port_render(nm)
        oracle_c = (HERE / "csrc" / f"{nm}.c").read_text()
        if src != oracle_c:
            print(f"{nm}: THE PORT's C DIFFERS FROM UPSTREAM's")
            bad += 1
            continue
        ins, outs = oracle_buffers(nm)

        lib = compile_elf(src, CC)
        (HERE / "elf" / f"{nm}.hex").write_text(lib.hex())
        img_port = port_relocate(nm)
        img_up = jit_loader(lib, base=0).hex()
        if img_port != img_up:
            print(f"{nm}: THE PORT's RELOCATED IMAGE DIFFERS FROM UPSTREAM's")
            bad += 1
            continue
        got = call_image(bytes.fromhex(img_port), ins)
        match = sum(1 for g, o in zip(got, outs) if g == o)
        changed = sum(1 for g, i in zip(got, ins) if g != i)
        amax, rmax = 0.0, 0.0
        for g, o in zip(got, outs):
            a, r = maxerr(g, o)
            if a is not None:
                amax, rmax = max(amax, a), max(rmax, r)
        ok = match == len(outs)
        if not ok:
            bad += 1
        rows.append(f"{nm} real c=IDENTICAL reloc=IDENTICAL bufs={len(outs)} "
                    f"output_match={match}/{len(outs)} changed_vs_input={changed}/{len(outs)} "
                    f"max_abs={amax:.6g} max_rel={rmax:.6g} verdict={'PASS' if ok else 'FAIL'}")
        print(rows[-1])

        # THE PLANT.
        old, new = PLANT[nm]
        os.environ["PLANT_OLD"], os.environ["PLANT_NEW"] = old, new
        try:
            lib2 = compile_elf(src, str(HERE / "plant-cc.py"))
            img2 = jit_loader(lib2, base=0)
            got2 = call_image(img2, ins)
            m2 = sum(1 for g, o in zip(got2, outs) if g == o)
            a2, r2 = 0.0, 0.0
            for g, o in zip(got2, outs):
                a, r = maxerr(g, o)
                if a is not None:
                    a2, r2 = max(a2, a), max(r2, r)
            red = m2 != len(outs)
            if not red:
                bad += 1
            prows.append(f"{nm} plant c=IDENTICAL bufs={len(outs)} "
                         f"output_match={m2}/{len(outs)} max_abs={a2:.6g} max_rel={r2:.6g} "
                         f"verdict={'FAIL' if red else 'PASS'}")
            print(prows[-1])
        finally:
            os.environ.pop("PLANT_OLD", None)
            os.environ.pop("PLANT_NEW", None)

    (HERE / "pipeline.rows").write_text(
        "# pipeline.py -- the port's own code, end to end\n" + "\n".join(rows) + "\n")
    (HERE / "pipeline-plant.rows").write_text(
        "# pipeline.py -- THE PLANT: one token of the rendered C, per kernel\n"
        + "\n".join(prows) + "\n")
    print(f"# wrote pipeline.rows and pipeline-plant.rows  fail={bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
