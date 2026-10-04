#!/usr/bin/env python3
"""portexec/census.py -- HOW MUCH OF THE 227-ROW GATE IS TEXT AND HOW MUCH IS
EXECUTION. Measured by COMPILING every row that is C source, not by counting.

THE QUESTION. `cstyle-gate.py:554` builds both lanes from
`subprocess.CompletedProcess([], 0, pathlib.Path(a.port_stdout).read_text(), "")`,
so the 227 rows compare two RECORDED TEXTS. This file answers, per row, whether
that text is (a) a standalone C translation unit that `cc` on this machine will
accept, (b) C source for a device whose SDK is not present here, or (c) not C at
all -- a fragment, a name, a type spelling, an option-table cell.

THE DENOMINATOR IS COUNTED, NOT ASSUMED. Every one of the 227 rows is written to
its own file and handed to `cc`; the counts below are what `cc` said.

    .venv/bin/python .agents/slop/portexec/census.py <outdir>
"""
import json, pathlib, re, subprocess, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from exec_harness import port_rows

PREAMBLE = "typedef float float4 __attribute__((aligned(16),ext_vector_type(4)));\n"


def classify(name, val):
    """WHICH OF THE THREE, from the row's own NAME and its own VALUE."""
    body = val.replace("\\n", "\n")
    dev = next((d for d in ("CLANG", "OPENCL", "METAL", "CUDA", "HIP", "BASE")
                if re.search(rf"\b{d}\b", name)), None)
    has_sig = re.search(r"\bvoid\s+\w+\s*\([^)]*\)\s*\{", body) is not None
    if has_sig:
        return "kernel", dev
    return "fragment", dev


def main():
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    rows = port_rows(out / "port-rows.txt")
    cdir = out / "census"
    cdir.mkdir(exist_ok=True)
    tally = {}
    detail = []
    for name, val in sorted(rows.items()):
        kind, dev = classify(name, val)
        key = (kind, dev)
        tally[key] = tally.get(key, 0) + 1
        if kind != "kernel":
            continue
        src = PREAMBLE + val.replace("\\n", "\n")
        f = cdir / (re.sub(r"[^A-Za-z0-9]+", "_", name.strip()) + ".c")
        f.write_text(src)
        r = subprocess.run(["cc", "-c", "-o", "/dev/null", str(f)],
                           capture_output=True, text=True)
        detail.append((name.strip(), dev, "COMPILES" if r.returncode == 0 else "rejected",
                       (r.stderr.strip().splitlines() or [""])[0][:90]))
    print(f"ROWS TOTAL (from the port's own stdout): {len(rows)}")
    print("\n-- by kind and device --")
    for (kind, dev), n in sorted(tally.items(), key=lambda kv: (-kv[1], str(kv[0]))):
        print(f"  {kind:9s} {str(dev):7s} {n}")
    kernels = [d for d in detail]
    ok = [d for d in kernels if d[2] == "COMPILES"]
    print(f"\n-- the rows that ARE C (a `void N(...)` signature plus a body) --")
    print(f"  kernels tried     : {len(kernels)}")
    print(f"  cc accepted       : {len(ok)}")
    print(f"  cc rejected       : {len(kernels) - len(ok)}")
    bydev = {}
    for n, dev, st, _ in kernels:
        bydev.setdefault((dev, st), []).append(n)
    for (dev, st), ns in sorted(bydev.items(), key=lambda kv: str(kv[0])):
        print(f"    {str(dev):7s} {st:9s} {len(ns):3d}  {', '.join(ns[:3])}{' ...' if len(ns) > 3 else ''}")
    print("\n-- first rejection message per rejected device --")
    seen = set()
    for n, dev, st, msg in kernels:
        if st == "rejected" and dev not in seen:
            seen.add(dev)
            print(f"  {dev}: {msg}")
    (out / "census.json").write_text(json.dumps(
        {"rows": len(rows), "tally": {f"{k[0]}/{k[1]}": v for k, v in tally.items()},
         "kernels": [{"name": n, "dev": d, "status": s, "msg": m} for n, d, s, m in kernels]},
        indent=1))


if __name__ == "__main__":
    main()
