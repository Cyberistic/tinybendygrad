#!/usr/bin/env python3
"""checks.py -- THE MUTATION READINGS FOR FINDINGS B AND C.

    .venv/bin/python .agents/slop/opsfind/checks.py

Finding A was a row that did not read its input, so its mutation is a PLANT in the
port and the reading is the row. Findings B and C are CLAIMS IN PROSE and DEAD
DEFS, and the shape that checks them does not need `bend` at all: each is a
re-measured assertion about the port's text. So the mutation here is to put the
defect BACK and read the gate's own check, not to re-run three lanes.

Each plant is applied at the real path, the check is called, and the file is put
back in a `finally`. A reading that says OK for a planted defect is not a reading.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad" / "runtime" / "ops_python.bend"

spec = importlib.util.spec_from_file_location("g", str(ROOT / "gates" / "ops_python_census-gate.py"))
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)

PLANTS = [
    ("B  the header disclaims the pyc_* rows AGAIN",
     "def compile.transform() -> String:",
     "# A row that disagrees with CPython is a row that encodes a bug, so there are NO\n"
     "# `pyc_*` rows here at all.\n"
     "def compile.transform() -> String:",
     g.pyc_rows_hold),
    ("C1 `B64_EQ` is back",
     "def b64.transform() -> String: \"base64.b64decode\"\n",
     "def b64.transform() -> String: \"base64.b64decode\"\ndef B64_EQ() -> U32: 61\n",
     g.dead_defs_hold),
    ("C2 `prog.init` is back",
     "# `uop_to_index` and `loop_ends`",
     "def prog.init(us: List<&2, Uop>) -> List<&2, U32>: Nil{}\n\n# `uop_to_index` and `loop_ends`",
     g.dead_defs_hold),
    ("A  a NINTH constant row: `pyd_ctor_len` is a bare 4 again",
     'urow("pyd_ctor_len", U32.from_nat(List.length(&1, U32, DEV_ARGS())))',
     'urow("pyd_ctor_len", 4)',
     g.literal_rows_hold),
    ("E  `op_of` learns a BINARY arm, and dispatch has no case for it",
     '    case "BUFFER": Some{O.OpsBUFFER{}}',
     '    case "BUFFER": Some{O.OpsBUFFER{}}\n    case "BINARY": Some{O.OpsBINARY{}}',
     g.interpreter_hold),
    ("E2 `Uop.refused` stops refusing at kind 14",
     "def Uop.refused(+u: Uop) -> Bool: U32.is_ge(Uop.kind(u), 14)",
     "def Uop.refused(+u: Uop) -> Bool: U32.is_ge(Uop.kind(u), 13)",
     g.interpreter_hold),
]


def call(fn):
    """The gate's checks print their verdict; this is what they said."""
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stderr(buf):
        ok = fn()
    return "OK" if ok else "RED -- " + " | ".join(l.strip() for l in buf.getvalue().splitlines())


def main():
    clean = PORT.read_text()
    print("UNPLANTED, once per distinct check")
    for fn in dict.fromkeys(fn for _, _, _, fn in PLANTS):
        print(f"   {fn.__name__}: {call(fn)}")
    try:
        for label, anchor, sub, fn in PLANTS:
            if anchor not in clean:
                print(f"\n== {label}\n   THE ANCHOR IS NOT IN THE FILE -- the reading "
                      f"is NOT a reading")
                continue
            PORT.write_text(clean.replace(anchor, sub, 1))
            print(f"\n== {label}\n   {fn.__name__}: {call(fn)}")
    finally:
        PORT.write_text(clean)
    print("\nthe port is restored; a plant never survives this script")


if __name__ == "__main__":
    main()