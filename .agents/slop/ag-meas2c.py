#!/usr/bin/env python3
"""MEASUREMENT 2 (final): of the lines autogen.py ACTUALLY GENERATES, how many
are mechanically derivable and how many are hand-maintained?

Scope is the `load(...)` name set of `autogen/__init__.py` PLUS the three
dynamic `load(nm, ...)` arms (nv_570/nv_580/nv_610) and the two `load(f"...")`
arms.  Everything else under autogen/ (am/regs.py, am/pmc.py, amd/*/enum.py,
nv_regs/*, am/sdma_*, ...) comes from extra/ scripts and ISA databases and is
OUT OF SCOPE for the generator-port question entirely.
"""
import re, os, collections

R = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/runtime"
src = open(os.path.join(R, "autogen", "__init__.py")).read()
gen = {n + ".py" for n in re.findall(r'load\(\s*"([a-z0-9_]+)"', src)}
gen |= {"nv_570.py", "nv_580.py", "nv_610.py"}

HEXRE   = re.compile(r"\b0[xX][0-9a-fA-F]+\b|\b[0-9a-fA-F]{8,16}\b")
DECLRE  = re.compile(r"^\s*(#|$|from |import |dll = c\.DLL|try:|except|\)|\]|\}|@|\.\.\.)")
CLSRE   = re.compile(r"^\s*(class \w+\(|@c\.record|@dll\.bind|def \w+\(|  [A-Za-z_]+ = |  \w+: \S)")
TABRE   = re.compile(r"^\s*[\w\.]+\s*(?::\s*[\w\[\], .]+\s*)?=\s*\S")
HANDRE  = re.compile(r"^\s*[\w\.]+\s*=\s*.*\b(if|else|for|while|return|len\(|sum\(|max\(|min\(|any\(|all\()")

# `register_fields([...])` is autogen.py:153 verbatim -- `tname`'s record arm
# and nothing else -- so it is mechanical, and it is a LOT of lines.
# `('name', TYPE, [args]),` is autogen.py:199-202 verbatim, `parse_objc_spec`.
REGRE   = re.compile(r"^\s*\w+\.register_fields\(\[")
OBJCRE  = re.compile(r"^\s*\('.*\),\s*$")

def classify(s):
    st = s.strip()
    if st == "" or st.startswith("#"): return "blank/comment"
    if re.match(r"^\s*@(c\.record|dll\.bind)", s): return "ffi_class"
    if DECLRE.match(s): return "decl"
    if REGRE.match(s): return "ffi_class"
    if OBJCRE.match(s): return "ffi_class"
    if CLSRE.match(s) and not TABRE.match(s): return "ffi_class"
    if HEXRE.search(s): return "hex"
    if HANDRE.match(s): return "hand"
    if TABRE.match(s): return "table_row"
    return "hand"

tot = collections.Counter(); per = {}
for f in sorted(gen):
    p = os.path.join(R, "autogen", f)
    if not os.path.exists(p): print("MISSING", f); continue
    n = collections.Counter()
    for l in open(p, errors="replace"): n[classify(l)] += 1
    per[f] = n; tot.update(n)

T = sum(tot.values())
print(f"GENERATED SET: {len(per)} files, {T} lines")
for k in ("hex", "table_row", "ffi_class", "hand", "decl", "blank/comment"):
    print(f"  {k:14s} {tot[k]:7d}  {100.0*tot[k]/T:5.1f}%")
mech = tot["hex"] + tot["ffi_class"] + tot["table_row"]
print()
print(f"MECHANICALLY DERIVABLE (hex + ffi_class + table_row): {mech}  ({100.0*mech/T:.1f}%)")
print(f"HAND-MAINTAINED (hand)                             : {tot['hand']}  ({100.0*tot['hand']/T:.1f}%)")
print()
print("### per file, sorted by size")
for f, n in sorted(per.items(), key=lambda kv: -sum(kv[1].values())):
    t = sum(n.values())
    print(f"  {f:22s} {t:7d}  hex={n['hex']:6d} tbl={n['table_row']:6d} cls={n['ffi_class']:6d} hand={n['hand']:5d} decl={n['decl']:5d}")
