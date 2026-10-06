"""EVERY environment variable either side of the graphcmp comparison can read, and for each,
WHETHER IT CAN MOVE A VERDICT -- MEASURED, one subprocess per flag.

TWO LANES, because a flag has TWO ways to speak and one hash conflates them:

  LANE A -- IN-PROCESS, 25 graphs, HASH OVER ROW-SHAPED LINES ONLY (`hashall.py`).
            Answers "did the comparison's INPUT change?".

  LANE B -- SUBPROCESS, `graphcmp.py emit --side py --graph lin`, HASH OVER THE WHOLE STDOUT
            plus a non-row count.  This is byte-for-byte what `checks/differ.py:452` writes
            into `runs/graphcmp/D/D2-canon-py-lin.txt`, so it is the artifact and not a proxy.
            Answers "did the ARTIFACT change?", and it is the ONLY lane that can see stdout
            contamination -- MEASURED WHY LANE A CANNOT: `emit_py` RETURNS the rows, so
            `DEBUG=1`'s `opened device CPU` never enters lane A at all.

THE FLAG LIST IS THE UNION OF FOUR READABLE SOURCES -- AST-counted off the tree, not AGENTS.md.
Run:  .venv/bin/python .agents/slop/devpin/envsweep.py
"""
from __future__ import annotations
import ast
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PY = str(ROOT / ".venv/bin/python")
HASH = ROOT / ".agents/slop/devpin/hashall.py"
GCMP = ROOT / ".agents/slop/graphcmp.py"
ROW = re.compile(r"^\d+:")

EXCLUDED = {
    "VIZ": "opens a browser and a viz server",
    "PROFILE": "starts the profiler; differ's dbg step sets DEBUG explicitly with --levels",
    "BROWSER": "viz-only", "PORT": "viz-only",
    "CAPTURE_PROCESS_REPLAY": "writes kernel pickles to disk",
    "TRACK_MATCH_STATS": "writes a stats pickle to disk",
    "DEBUGONNX": "parser-only; no ONNX in this corpus",
    "REWRITE_DATA": "viz path input", "PROFILE_DATA": "viz path input",
}

EXTRA_PROBES = {
    "DEFAULT_FLOAT": ("bfloat16", "float64"),
    "DEFAULT_INT": ("int64", "uint8"),
    "SUM_DTYPE": ("float32", "bfloat16"),
    "EMULATED_DTYPES": ("bfloat16", "float16"),
    "DEV": ("CPU", "METAL"),
    "REGEN": ("0", "2"), "TC": ("0", "1"), "JIT": ("0", "1"), "DEBUG": ("1", "4"),
}

CTX = re.compile(r'ContextVar\(\s*"([A-Z_0-9]+)"')
GET = re.compile(r'(?:os\.environ\.get\(|os\.getenv\(|os\.environ\[|getenv\(\s*)"([A-Z_0-9]+)"')


def py_flags() -> set[str]:
    out: set[str] = set()
    for p in (ROOT / "tinygrad").rglob("*.py"):
        try:
            t = ast.parse(p.read_text())
        except SyntaxError:
            continue
        for n in ast.walk(t):
            if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "ContextVar" \
                    and n.args and isinstance(n.args[0], ast.Constant):
                out.add(str(n.args[0].value))
            elif isinstance(n, ast.Subscript) and isinstance(n.value, ast.Attribute) \
                    and n.value.attr == "environ" and isinstance(n.slice, ast.Constant):
                out.add(str(n.slice.value))
            elif isinstance(n, ast.Call) and getattr(n.func, "id", "") == "getenv" \
                    and n.args and isinstance(n.args[0], ast.Constant):
                out.add(str(n.args[0].value))
    return out


def harness_flags() -> set[str]:
    return set(GET.findall((ROOT / "checks/differ.py").read_text())) \
        | set(GET.findall(GCMP.read_text()))


def port_flags() -> set[str]:
    """NON-COMMENT `getenv` spellings only, so a wall note is not counted as a read."""
    out: set[str] = set()
    for p in list((ROOT / "tinybendygrad").rglob("*.bend")) + [ROOT / ".agents/slop/graphcmp.bend"]:
        for ln in p.read_text().splitlines():
            out |= set(re.findall(r'getenv(?:_str)?\(\s*"([A-Z_0-9]+)"', ln.split("#", 1)[0]))
    return out


def base_env() -> dict[str, str]:
    return {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"LC_ALL": "C"}


def lane_a(extra: dict[str, str]) -> tuple[str, str]:
    p = subprocess.run([PY, str(HASH)], env=base_env() | extra,
                       capture_output=True, text=True, timeout=90)
    if p.returncode != 0:
        return f"rc={p.returncode}", (p.stderr.strip().splitlines() or [""])[-1][:110]
    m = re.search(r"(\w{64}) rows=(\d+) nonrows=(\d+)", p.stdout)
    return ("OK", f"{m.group(1)[:12]} rows={m.group(2)}") if m else ("NOHASH", p.stdout[:110])


def lane_b(extra: dict[str, str]) -> tuple[str, str]:
    p = subprocess.run([PY, str(GCMP), "emit", "--side", "py", "--graph", "lin"],
                       env=base_env() | extra, capture_output=True, text=True, timeout=90)
    if p.returncode != 0:
        return f"rc={p.returncode}", (p.stderr.strip().splitlines() or [""])[-1][:110]
    lines = p.stdout.splitlines()
    noise = sum(1 for ln in lines if not ROW.match(ln))
    return "OK", f"{len(p.stdout):>6}B rows={len(lines) - noise} nonrows={noise}"


def main() -> int:
    py, hf, pf = py_flags(), harness_flags(), port_flags()
    ba, ha = lane_a({"DEV": "CPU"})
    bb, hb = lane_b({"DEV": "CPU"})
    print(f"BASELINE DEV=CPU   lane A {ba} {ha}\n             lane B {bb} {hb}\n")

    rows, crashed, clean, excluded = [], [], [], []
    for f in sorted(py | hf | pf):
        if f in EXCLUDED:
            excluded.append(f)
            continue
        for probe in EXTRA_PROBES.get(f, ("1", "2")):
            sa, va = lane_a({"DEV": "CPU", f: probe})
            if sa != "OK":
                crashed.append((f, probe, sa, va))
                break
            sb, vb = lane_b({"DEV": "CPU", f: probe})
            if sb != "OK":
                crashed.append((f, probe, sb, vb))
                break
            if va != ha or vb != hb:
                rows.append((f, probe, va, vb))
                break
        else:
            clean.append(f)

    print(f"FLAGS DISCOVERED           : {len(py | hf | pf)}")
    print(f"  readable by the PY side  : {len(py)}")
    print(f"  named by the HARNESS     : {len(hf)} {sorted(hf)}")
    print(f"  read by the PORT (.bend) : {len(pf)} {sorted(pf)}")
    print(f"EXCLUDED, each with a REASON: {len(excluded)} {sorted(excluded)}")

    print(f"\nCAN MOVE A VERDICT ({len(rows)}) -- lane A = inputs, lane B = the artifact:")
    for f, p, va, vb in rows:
        a = "ROWS" if va != ha else "    "
        b = "ARTIFACT" if vb != hb else "       "
        print(f"  {f}={p:<9} laneA:{a} {va:<22} laneB:{b} {vb}")
    print(f"\nREFUSE / CRASH ({len(crashed)}) -- a flag that makes the side unbuildable:")
    for f, p, st, out in crashed:
        print(f"  {f}={p:<9} {st}  {out}")
    print(f"\nCANNOT MOVE ({len(clean)}) -- measured inert over the 25 graphs:")
    print("  " + " ".join(clean))
    print("\nDEV, swept by NAME rather than by a numeric probe:")
    for dev in ("CPU", "NULL", "METAL", "PYTHON"):
        sa, va = lane_a({"DEV": dev})
        sb, vb = lane_b({"DEV": dev})
        print(f"  DEV={dev:<7} A {sa} {va:<22} B {sb} {vb}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
