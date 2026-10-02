#!/usr/bin/env python3
"""x86-asmdbg.py -- print what `Asm.line` produces for a chosen assembly line, as a
throwaway `main` in a scratch copy of the file.

`asm.L*` rows are `Bool` rows against CPython's own line, which is right for a gate and
useless for finding out WHY one is False: the diff says the line differs and not where.
This writes `main` that prints the raw strings so the two can be compared side by side.

    .venv/bin/python .agents/slop/x86/x86-asmdbg.py 2 3 7 10
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "tinybendygrad/renderer/isa/x86.bend"
OUT = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/asmdbg.bend")

ns = {"__file__": str(Path(__file__).resolve()), "__name__": "xo"}
exec(compile(Path(__file__).with_name("x86-oracle.py").read_text().split(
    'if __name__ == "__main__":')[0], "x86-oracle.py", "exec"), ns)
OPS = ns["ASM_OPS"]

idx = [int(a) for a in sys.argv[1:]] or [0]
body = "def main() -> IO(Unit):\n  do IO<Unit>:\n"
for i in idx:
  body += f'    IO.print(AsmLine.at(asm_str("kern", [{OPS}]), {i}n))\n'
OUT.write_text(SRC.read_text().split("def main() -> IO(Unit):")[0] + body)
print(OUT)
