#!/usr/bin/env python3
"""code-table-probe.py -- THE PORT's NUMERIC CODE TABLES AGAINST THE STRING TABLES THEY REPLACE.

`tinybendygrad/renderer/live.bend`'s `dt_of` / `addr_of` / `arg_of` MATCH ON CHAR CODES, because a
`match` on a String in Bend is a CHARACTER TRIE (the generated code slices the first character and
slices the rest to test the length -- two slices and two `char_len` per call) and a `match` on a `U32`
is an INTEGER COMPARE. **AND A COMPUTED ARM KEY IS REFUSED** ("expected : a pattern"), so the table
cannot derive its own keys, which makes the numeric keys A SECOND SOURCE OF TRUTH.

**SO THE SECOND SOURCE IS CHECKED BY A PROBE, NOT BY READING.** This builds the live renderer, runs
the probe over every code, and exits non-zero on any mismatch. The probe's STRING table is RE-TYPED
(the port's own, before the change), because a probe that compares a table with itself proves nothing.

    .venv/bin/python .agents/slop/parity/code-table-probe.py
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
PROBE = HERE / "code-table-probe.js"


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        js = pathlib.Path(td) / "live.js"
        build = subprocess.run([str(ROOT / "bin/bend"),
                                str(ROOT / ".agents/slop/cpuseam/serve.bend"), "-o", str(js)],
                               cwd=ROOT, capture_output=True, text=True)
        if build.returncode != 0:
            print(f"code-table-probe: the renderer did not build: {build.stderr.strip()[:300]}", file=sys.stderr)
            return 2
        run = subprocess.run([str(pathlib.Path.home() / ".bun/bin/bun"), str(PROBE), str(js)],
                             cwd=ROOT, capture_output=True, text=True)
        sys.stdout.write(run.stdout)
        if run.stderr.strip():
            sys.stderr.write(run.stderr)
        # **=> AND THE PROBE's EXIT CODE IS THE GATE's EXIT CODE.** MEASURED: THE FIRST RUN OF THIS
        # PROBE PRINTED THE MISMATCH AND EXITED 0, BECAUSE `bun` ON A `.js` FILE UNDER THIS TREE's
        # `package.json` LOADS IT AS ESM AND THE `process.exit(bad ? 1 : 0)` NEVER RAN -- SO A PROBE THAT
        # CANNOT GO RED IS NOT A PROBE.
        if "PROBE:" not in run.stdout:
            print("code-table-probe: the probe printed no verdict", file=sys.stderr)
            return 1
        return run.returncode


if __name__ == "__main__":
    sys.exit(main())
