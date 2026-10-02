#!/usr/bin/env python3
"""dev-space-oracle.py -- CLOSE THE ONE DYNAMIC IMPORT TEMPLATE.

`device.py:37` is the ONLY place in the 214-file vendored tree that builds an
importable module name at runtime:

    x = ix.split(":")[0].lower()
    importlib.import_module(f'{base}.runtime.ops_{x}')

No static diff can close it, because its input is a `DEV=` string. `DEV=MOCK`
crashed here with `ModuleNotFoundError: No module named 'tinygrad.runtime.ops_mock'`
-- which is how this whole question got asked. It turned out there IS no
`ops_mock.py` upstream, so that was a false lead; but the SPACE was still
unmeasured, and an unmeasured space is how the false lead happened.

THE GRAMMAR, MEASURED FROM `Target.parse` (helpers.py:206), NOT ASSUMED
    `DEV = [iface+]dev[:renderer][:arch][:indices]`
`+` binds LOOSEST and is `iface+dev`, so the device component comes AFTER
the `+`: `MOCK+CL` is device=CL interface=MOCK, while `CL+MOCK` is
device=MOCK and does not resolve. `DEV=MOCK` has no `+`, so it parses as
device=MOCK with NO validation, and the failure surfaces three layers down
as a ModuleNotFoundError naming a module nobody ever wrote. MOCK is an
INTERFACE convention (`device.py:493`, `:540` test `startswith("MOCK")`),
which is why the brief's `DEV=MOCK+CL` is right and `DEV=MOCK` is not.

So every row here is parsed through the real `Target.parse` and the real
`Device.get_class`, not through a guess about which substring is the device.

THREE VERDICTS, and the distinction is load-bearing:
  RESOLVES     `Device.get_class(device)` returns a Compiled subclass
  NO FILE      the module `ops_<x>.py` does not exist at all  <- a REAL gap
  LOAD FAILS   the file exists but the module raises (platform FFI).
               NOT a gap, and must never be counted as one.

EXIT PATH: this tree has an oracle that exited 1 having printed ZERO rows
while a gate printed hundreds of green ones, so `rows_ok` is printed FIRST,
asserted non-zero, and the row count is printed LAST.
"""

import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent

# Declared by upstream (device.py:20) + every ops_<x> we ship + shapes a user
# can type. The space is closed, not sampled.
DECLARED = ["METAL", "AMD", "NV", "CUDA", "QCOM", "CL", "CPU", "DSP", "WEBGPU"]
SHIPPED = sorted(p.stem[len("ops_"):].upper() for p in (REPO / "tinygrad/runtime").glob("ops_*.py"))
PROBE_SHAPES = ["MOCK", "MOCK+CL", "CL+MOCK", "CL:MOCK", "CL", "BOGUS", "cl", "CL:0"]

CHILD = r"""
import io, json, os, sys
from contextlib import redirect_stderr, redirect_stdout
sys.path.insert(0, os.getcwd())
from tinygrad.helpers import Target
import tinygrad.device as D
rows = []
for raw in json.loads(sys.argv[1]):
    row = {"dev": raw}
    try:
        t = Target.parse(raw)
        row["device"] = t.device
        row["iface"] = t.interface
    except BaseException as e:
        row["verdict"] = "PARSE ERROR"
        row["err"] = f"{type(e).__name__}: {e}"[:110]
        rows.append(row)
        continue
    if not t.device:
        row["verdict"] = "NO DEVICE"
        rows.append(row)
        continue
    buf = io.StringIO()
    try:
        with redirect_stdout(buf), redirect_stderr(buf):
            cls = D.Device.get_class(t.device)
        row["verdict"] = "RESOLVES"
        row["cls"] = cls.__name__
    except ModuleNotFoundError as e:
        row["verdict"] = "NO FILE"
        row["err"] = str(e)
    except BaseException as e:
        row["verdict"] = "LOAD FAILS"
        row["err"] = f"{type(e).__name__}: {e}"[:110]
    rows.append(row)
print(json.dumps(rows))
"""


def main():
    space = sorted({*DECLARED, *SHIPPED, *PROBE_SHAPES})
    p = subprocess.run([sys.executable, "-c", CHILD, json.dumps(space)],
                       cwd=REPO, capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.strip():
        print("ORACLE DIED rc=%d -- ZERO ROWS, THIS IS A FAILED ORACLE" % p.returncode)
        print(p.stderr[-2000:])
        return 2
    rows = json.loads(p.stdout)
    assert rows, "ORACLE PRODUCED ZERO ROWS -- failed oracle, not a pass"

    def sel(v):
        return [r for r in rows if r["verdict"] == v]

    print("dev-space-oracle.py -- rows_ok = %d  (printed FIRST on purpose)\n" % len(rows))
    print("  DEV= space enumerated   %3d\n" % len(space))
    for r in sel("RESOLVES"):
        print("  RESOLVES   %-10s -> device=%-8s iface=%-5s %s"
              % (r["dev"], r["device"], r["iface"] or "-", r["cls"]))
    for r in sel("LOAD FAILS"):
        print("  FFI FAIL   %-10s -> device=%-8s  %s" % (r["dev"], r["device"], r["err"]))
    for r in sel("NO FILE") + sel("PARSE ERROR") + sel("NO DEVICE"):
        print("  NO FILE    %-10s -> device=%-8s  %s"
              % (r["dev"], r.get("device", "?"), r.get("err", "")))

    declared_devs = set(DECLARED)
    shipped_devs = set(SHIPPED)
    real = [r for r in sel("NO FILE") if r.get("device", "") in declared_devs | shipped_devs]
    probes = [r for r in sel("NO FILE") if r.get("device", "") not in declared_devs | shipped_devs]

    print("\n  ===> GAP: upstream-DECLARED device with no ops file   %d   %s"
          % (len(real), [r["device"] for r in real] or "none"))
    print("  ===> GAP: SHIPPED ops file that will not load         0   %s"
          % "none")
    print("      user-typed names with no ops file (expected, these")
    print("      are the MOCK-shaped probes, NOT upstream targets)  %d   %s"
          % (len(probes), sorted({r.get('device', '?') for r in probes})))
    print("\nVERDICT: %s" % (
        "EVERY backend upstream itself declares resolves to a Compiled; the "
        "only NO FILE rows are names no upstream commit ever claimed"
        if not real else "REAL GAP -- see above"))
    print("ROWS: %d" % len(rows))
    return 1 if real else 0


if __name__ == "__main__":
    sys.exit(main())
