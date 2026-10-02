#!/bin/sh
# Run ONE row of generate.bend, with every other gate row removed.  `do IO<Unit>:`
# evaluates its whole body, so a hang anywhere hides behind any earlier row.
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
python3 - "$1" <<'PY'
import pathlib, sys
src = pathlib.Path("tinybendygrad/renderer/amd/generate.bend").read_text()
head, sep, _ = src.partition("def main() -> IO(Unit):")
row = sys.argv[1]
pathlib.Path(".agents/slop/li/one.bend").write_text(
    head + 'def main() -> IO(Unit):\n  do IO<Unit>:\n    ' + row + '\n')
PY
./bin/bend .agents/slop/li/one.bend 2>&1 | head -12
