import os, enum
os.environ["DEV"]="CPU"
from tinygrad.codegen.opt import OptOps
print("vars(OptOps.TC) type :", type(vars(OptOps.TC)), "->", vars(OptOps.TC))
d = vars(OptOps.TC)
for k, v in d.items():
    try:
        r = vars(v)
        print(f"  vars(member[{k!r}] = {v!r}) -> OK, type {type(r).__name__}, {len(r)} entries")
    except TypeError as e:
        print(f"  vars(member[{k!r}] = {v!r}) -> TypeError: {e}   <== THE CRASH")
print()
print("Is the MEMBER missing __dict__?  ", 'member' , hasattr(OptOps.TC, '__dict__'))
print("type(vars(OptOps))              :", type(vars(OptOps)).__name__)
try:
    vars(OptOps)
except TypeError as e:
    print("vars(OptOps) -> TypeError:", e)
print("isinstance(vars(OptOps), dict)  :", isinstance(vars(OptOps), dict))
print("isinstance(vars(OptOps.TC),dict):", isinstance(vars(OptOps.TC), dict))
