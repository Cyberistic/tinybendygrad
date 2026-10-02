#!/usr/bin/env python3
"""tcptx_wants.py -- migrate the CPython `want` column of tc_ptx.bend's tc rows.

`r1(nm, "di"|"do", <the port's dt_name(...)>, "<want>")` -- the FOURTH argument
is what CPython printed, and CPython prints `DType.name`, which tinygrad 793abbb
moved onto the rust spellings. So every one of those literals moves.

The FIRST argument of `r_types1`/`r_mem_types1`/`r_cast_types1` is a row LABEL,
not an answer, and labels are left alone: renaming a label changes a row's NAME
without changing what it asserts, which is churn that hides a real move.
"""
import re
import sys

NAMES = {
    "signed char": "i8", "unsigned char": "u8", "short": "i16",
    "unsigned short": "u16", "int": "i32", "unsigned int": "u32",
    "long": "i64", "unsigned long": "u64", "half": "f16",
    "__bf16": "bf16", "float": "f32", "double": "f64",
    "float8_e4m3": "fp8e4m3", "float8_e5m2": "fp8e5m2",
    "float8_e4m3fnuz": "fp8e4m3fnuz", "float8_e5m2fnuz": "fp8e5m2fnuz",
}
# r1(<nm>, "<field>", <expr>, "<want>")
ROW = re.compile(r'(r1\([^,]+,\s*"(?:di|do)",\s*[^,]+,\s*)"([^"]*)"')

path = sys.argv[1]
src = open(path).read()
n = 0


def sub(m):
    global n
    if m.group(2) in NAMES:
        n += 1
        return m.group(1) + '"' + NAMES[m.group(2)] + '"'
    return m.group(0)


out = ROW.sub(sub, src)
if "--apply" in sys.argv[2:]:
    open(path, "w").write(out)
print("%s: %d `want` literals migrated" % (path, n))