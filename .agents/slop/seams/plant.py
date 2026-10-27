#!/usr/bin/env python3
"""plant.py -- THE PLANT: a DELIBERATE DEFECT, and the gate turning red.

    .venv/bin/python .agents/slop/seams/plant.py

WHAT IT DOES.  It copies `kernel_mnist.bend`, changes ONE THING -- the first
convolution's tap count, from nine to eight -- writes the copy as
`plant_tapcount.bend`, runs it with the port's own compiler, and compares the
bytes it wrote against CPython's with `compare.py`.

WHY THAT MUTATION.  It is not an invented fault: it is the fault the kernel
HAD.  MEASURED, 2026-10-27: the first working run of `kernel_mnist.bend` was
bit-identical to an EIGHT-tap convolution on 3136 of 3136 conv1 outputs, and
the ninth tap's weight was never read.  `conv1.tap(k, ki, ..)` stops at
`k == 0`, so a call with `k = 8n` performs EIGHT taps with `ki = 0..7` and
never reaches `ki = 8`.  The plant re-introduces exactly that.

WHAT IT PROVES.  That `compare.py` is a GATE and not a LABEL: the same
comparator that reads GREEN on the port's own bytes reads RED on bytes one
tap short, and the red is QUANTIFIED (the measured worst relative difference
is 1.37e-01 against the good kernel's 1.37e-07).

ONE BEND PROCESS AT A TIME: this script runs exactly one.
"""
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent

KERNEL = HERE / "kernel_mnist.bend"
PLANT = HERE / "plant_tapcount.bend"
PLANT_OUT = HERE / "port_stages_plant.f32"

MUTATIONS = [
    # THE FAULT: nine taps become eight.
    ("conv1.tap(9n, 0n, w, im, o, y, x,",
     "conv1.tap(8n, 0n, w, im, o, y, x,"),
    # the plant writes beside the good artifact and never over it.
    ('def OS() -> String: ".agents/slop/seams/port_stages.f32"',
     'def OS() -> String: ".agents/slop/seams/port_stages_plant.f32"'),
]


def main() -> int:
    src = KERNEL.read_text()
    for old, new in MUTATIONS:
        if src.count(old) != 1:
            print(f"# FATAL: the mutation anchor {old!r} occurs {src.count(old)} times")
            return 3
        src = src.replace(old, new)
    PLANT.write_text(src)
    print(f"# planted {PLANT.name} from {KERNEL.name}: "
          f"{len(MUTATIONS)} substitutions, one of them the fault")

    run = subprocess.run(
        [str(ROOT / "bin" / "bend"), str(PLANT)],
        cwd=ROOT, capture_output=True, text=True,
        env={**__import__("os").environ, "BEND_NO_TELEMETRY": "1"})
    print(f"# plant run rc={run.returncode}")
    for line in run.stdout.splitlines()[-3:]:
        print(f"#   {line}")
    if run.returncode != 0:
        print(f"# plant stderr: {run.stderr.strip()[:400]}")
        return 3

    cmp_run = subprocess.run(
        [str(ROOT / ".venv" / "bin" / "python"), str(HERE / "compare.py"), str(PLANT_OUT)],
        cwd=ROOT, capture_output=True, text=True)
    print(cmp_run.stdout.rstrip())
    print(f"# compare rc={cmp_run.returncode} (1 means RED)")
    # THE GENERATED PROGRAM IS NOT LEFT BEHIND: it is a 421-line copy of the
    # kernel, and a generated copy of a file is not a second witness.  The
    # plant's ARTIFACT -- the bytes it wrote -- stays, so the RED can be read
    # again without running anything.
    PLANT.unlink()
    print(f"# removed the generated {PLANT.name}; kept {PLANT_OUT.name}")
    return 0 if cmp_run.returncode == 1 else 3


if __name__ == "__main__":
    raise SystemExit(main())
