#!/usr/bin/env python3
"""Per-gate cost, with a hard cap, so 'slow' and 'hangs' are told apart.

`run.py --run` exceeded 600s wall. That is the answer to "what does the runner cost", but it
is only actionable if the gate that eats the time is named, so each is timed alone. The cap
is a parameter because 60s is a MEASUREMENT BOUND, not a verdict: anything over it is
reported as OVER-CAP and its true cost is unknown, which is SKIP, not PASS.
"""
import ast
import importlib.util
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CAP = int(sys.argv[1]) if len(sys.argv) > 1 else 60


def pop():
    spec = importlib.util.spec_from_file_location("gp", ROOT / "gates" / "gates-pop.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def declares(p):
    try:
        for node in ast.parse(p.read_text()).body:
            if isinstance(node, ast.Assign) and any(
                getattr(t, "id", None) == "VERDICTS" for t in node.targets
            ):
                return True
    except Exception:
        pass
    return False


def main():
    entries, _libs = pop().discover(ROOT)
    gates = [p for p in entries if declares(p)]
    gates.append(ROOT / "gates" / "gate-surface.py")
    print(f"cap={CAP}s per gate; {len(gates)} gates (the 13 that declare VERDICTS, "
          f"+ gate-surface as the auditor)\n")
    total, over, rows = 0.0, [], []
    for p in gates:
        rel = str(p.relative_to(ROOT))
        extra = ["--report"] if p.name == "gate-surface.py" else []
        t0 = time.monotonic()
        try:
            r = subprocess.run([sys.executable, str(p), *extra], capture_output=True,
                               text=True, cwd=str(ROOT), timeout=CAP, stdin=subprocess.DEVNULL)
            dt, rc, out = time.monotonic() - t0, r.returncode, (r.stdout + r.stderr)
        except subprocess.TimeoutExpired:
            dt, rc, out = time.monotonic() - t0, "TIMEOUT", ""
        over_cap = rc == "TIMEOUT"
        total += dt
        rows.append((rel, rc, dt, over_cap))
        head = out.strip().splitlines()[0][:52] if out.strip() else "<SILENT>"
        print(f"  {'OVER-CAP' if over_cap else str(rc):>8}  {dt:6.1f}s  {rel:<34} {head}")
        if over_cap:
            over.append(rel)
    print(f"\nTOTAL {total:.1f}s over {len(gates)} gates; {len(over)} over the {CAP}s cap "
          f"(their true cost is UNKNOWN, which is SKIP)")
    if over:
        print("over cap: " + ", ".join(over))
    (HERE / "cost.tsv").write_text(
        "gate\trc\tseconds\nover-cap\n" + "".join(f"{r}\t{c}\t{d:.1f}\t{o}\n"
                                                  for r, c, d, o in rows))


if __name__ == "__main__":
    sys.exit(main())
