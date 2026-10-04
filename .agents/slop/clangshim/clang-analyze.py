#!/usr/bin/env python3
"""clang-analyze.py -- classify all 324 trampolines by what they cost to CALL.

Reads the committed input and prints the class census. No generation here: this
file exists so the marshalling policy in clangshim-gen.py is a policy over a
MEASURED census rather than a policy over an assumption.

Inputs (all committed, all read-only):
  .agents/slop/ag-libclang.tramp                      324 rows, ctypes spellings
  tinygrad/runtime/autogen/libclang.py                TypeAlias + struct SIZE
  tinybendygrad/runtime/autogen/libclang.bend         the Bend signatures

The ctypes resolver is IMPORTED from ffi-port-cost.py, not copied: two
resolvers for one TypeAlias graph is exactly the kind of drift that made
ag-order.py corrupt the emitter three times.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / ".agents" / "slop"))

_spec = importlib.util.spec_from_file_location(
    "ffi_port_cost", REPO / ".agents" / "slop" / "ffi-port-cost.py")
fpc = importlib.util.module_from_spec(_spec)
sys.modules["ffi_port_cost"] = fpc  # dataclasses resolves via sys.modules
_spec.loader.exec_module(fpc)

TRAMP = REPO / ".agents" / "slop" / "ag-libclang.tramp"
PYBIND = REPO / "tinygrad" / "runtime" / "autogen" / "libclang.py"
BEND = REPO / "tinybendygrad" / "runtime" / "autogen" / "libclang.bend"


def rows() -> list[dict]:
    out = []
    for line in TRAMP.read_text().splitlines():
        if not line.strip():
            continue
        f = line.split("|")   # name|retbind|rethint| then (pname|pbind|phint)*
        assert len(f) >= 3 and (len(f) - 3) % 3 == 0, line
        params = [(f[3 + 3 * i], f[4 + 3 * i], f[5 + 3 * i])
                  for i in range((len(f) - 3) // 3)]
        out.append({"name": f[0], "ret": f[1], "rethint": f[2], "params": params})
    return out


def main() -> int:
    T = fpc.Types(PYBIND.read_text())
    R = rows()
    print(f"trampoline rows            : {len(R)}")
    print(f"distinct names             : {len({r['name'] for r in R})}")

    def cls(sp: str, is_ret: bool) -> str:
        t = T.resolve(sp)
        if t in ("None", ""):
            return "VOID"
        if t.startswith("*"):
            return "STR_OUT" if is_ret and t == "*char" else (
                "STR_IN" if t == "*char" else "PTR")
        if t.startswith("CB:"):
            return "CB"
        m = re.match(r"^\w+\[(\d+)\]$", t)
        if m:
            return f"BYVAL{m.group(1)}"
        low = t.lower()
        if low in ("ctypes.c_double",):
            return "F64"
        if low in fpc._CTYPES_INT:
            return "I64" if fpc._CTYPES_INT[low] > 32 else "INT"
        if low in ("int", "unsigned", "unsigned int"):
            return "INT"
        return f"?{t}"

    ret_c = Counter(cls(r["ret"], True) for r in R)
    arg_c = Counter(cls(p[1], False) for r in R for p in r["params"])
    hint_c = Counter(r["rethint"] for r in R)

    print("\nRETURN classes:")
    for k, n in ret_c.most_common():
        print(f"  {k:12s} {n:4d}")
    print("\nPARAMETER classes (all params of all 324):")
    for k, n in arg_c.most_common():
        print(f"  {k:12s} {n:4d}")

    print(f"\nzero-parameter functions   : "
          f"{sum(1 for r in R if not r['params'])}")

    # Which C type names will need an opaque declaration in the generated C?
    names = set()
    for r in R:
        for sp, isret in [(r["ret"], True)] + [(p[1], False) for p in r["params"]]:
            t = T.resolve(sp)
            b = t.replace("*", "")
            if re.match(r"^\w+\[\d+\]$", t):
                names.add(b)
    print(f"by-value struct types      : {len(names)}")

    # Cross-check: does every trampoline name appear as a def in libclang.bend,
    # with the same parameter COUNT? The brief says name/arity/order agree with
    # 0 disagreements; that is the licence to generate, so MEASURE it.
    bend_defs = {}
    for m in re.finditer(r"^def (clang_\w+)\(([^)]*)\) -> ([^:]+):",
                         BEND.read_text(), re.M):
        bend_defs[m.group(1)] = (m.group(2), m.group(3))
    missing = [r["name"] for r in R if r["name"] not in bend_defs]
    arity = [(r["name"], len(r["params"]),
              0 if bend_defs[r["name"]][0].strip() == "" else
              len([x for x in bend_defs[r["name"]][0].split(",") if x.strip()]))
             for r in R if r["name"] in bend_defs]
    bad = [a for a in arity if a[1] != a[2]]
    print(f"\nlibclang.bend clang_ defs  : {len(bend_defs)}")
    print(f"tramp names missing a def  : {len(missing)} {missing[:5]}")
    print(f"arity disagreements       : {len(bad)} {bad[:5]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())