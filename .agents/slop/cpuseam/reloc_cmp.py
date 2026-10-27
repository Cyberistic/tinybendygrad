#!/usr/bin/env python3
"""reloc_cmp.py -- THE PORT's OWN `jit_loader` AGAINST UPSTREAM's OWN.

    .venv/bin/python .agents/slop/cpuseam/reloc_cmp.py

IT RUNS THE PORT's OWN BEND CODE -- `.agents/slop/cpuseam/relocate.bend`, WHICH
CALLS `runtime/support/elf.bend`'s OWN `E.Ehdr.at` -> `E.elf_loader` ->
`E.jit_loader` -- AND COMPARES ITS RELOCATED IMAGE, BYTE FOR BYTE, WITH
UPSTREAM's OWN `jit_loader` OUTPUT ON THE SAME ELF OBJECT.

⇒ THE LANE IS THE JS ONE (`bun`), BECAUSE THE NATIVE ONE CANNOT EXEC ON THIS
MACHINE: EVERY LOCALLY-BUILT BINARY IS KILLED BY THE KERNEL'S
`AppleSystemPolicy` ("Security policy would not allow process"). SEE THE
REPORT. ⇒ THE PORT's BEND CODE IS THE SAME CODE IN BOTH LANES; ONLY THE
BACKEND DIFFERS.
"""
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
BUN = "/Users/cyberistic/.bun/bin/bun"
JS = "/tmp/relocate.js"
KERNELS = ["r_10_98_4", "r_2_14_14_4_4_3_3", "r_4_28_7_4_3_3",
            "r_56_14_2_2", "r_56_7_2_2"]

rows = []
bad = 0
for nm in KERNELS:
    want = (HERE / "elf" / f"{nm}.img").read_text().strip()
    p = subprocess.run([BUN, JS, nm], capture_output=True, text=True)
    if p.returncode != 0:
        print(f"{nm}: the port's relocator failed rc={p.returncode}: {p.stderr[:200]}")
        bad += 1
        continue
    got = p.stdout.strip()
    same = got == want
    if not same:
        bad += 1
    rows.append(f"{nm} port_bytes={len(got) // 2} upstream_bytes={len(want) // 2} "
                f"identical={'YES' if same else 'NO'}")
    print(rows[-1])

(HERE / "reloc.rows").write_text(
    "# reloc_cmp.py -- the port's own jit_loader against upstream's own\n"
    + "\n".join(rows) + "\n")
print(f"# wrote reloc.rows  fail={bad}")
raise SystemExit(1 if bad else 0)
