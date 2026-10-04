#!/usr/bin/env python3
"""Replace dtype.bend's six `Dt.i64_*` FOREIGN defs with pure Bend bodies."""
import pathlib, sys

TREE = pathlib.Path(sys.argv[1])
DT = TREE / "tinybendygrad/dtype.bend"
NEW = pathlib.Path(__file__).resolve().parent / "i64-pure.bend.txt"

old = []
for name, sig in [("i64_trunc", "x: H.I64"), ("i64_floor_div", "a: H.I64, b: H.I64"),
                  ("i64_floor_mod", "a: H.I64, b: H.I64"), ("i64_cdiv", "a: H.I64, b: H.I64"),
                  ("i64_cmod", "a: H.I64, b: H.I64"), ("i64_ceildiv", "a: H.I64, b: H.I64")]:
    old.append(f'def Dt.{name}({sig}) -> IO(H.I64):\n'
               '  import "./runtime/dtype.c"\n'
               '  import "./runtime/dtype.js"\n')
src = DT.read_text()
for o in old:
    if src.count(o) != 1:
        sys.exit(f"anchor not unique ({src.count(o)}): {o.splitlines()[0]}")
    src = src.replace(o, "")
DT.write_text(src + "\n" + NEW.read_text())
print("patched", DT)
