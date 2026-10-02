#!/usr/bin/env python3
"""MEASUREMENT 2: of the 187,164 lines tinygrad/runtime/autogen/ makes, how
many are MECHANICALLY DERIVABLE (so a generator port covers them) and how many
are HAND-MAINTAINED (so a generator port LOSES them)?

The whole question turns on ONE thing: is a line derivable from something the
generator already computes, or is it a fact that exists only because a human
typed it?  So the classifier asks, per line:

  HEX        a 0x literal or a bare hex digit-run in a register/enum context.
             100% derivable from the C header by the generator.
  TABLE_ROW  a `NAME: TYPE = VALUE` / `NAME = VALUE` / `(K:=V): 'K'` binding.
             Derivable ONLY IF the generator emits that kind of binding; for
             the NV/AMD register files it does not, because those come from
             macros and designated initialisers that `readext` copies.
  FFI_CLASS  a `class X(c.Struct)` / `@c.record` / `@dll.bind` / `def f(...)`
             block.  Mechanically derivable -- that is what `tname` does.
  DECL       an import, a comment, a blank, a `dll = c.DLL(...)`, a `try:`.
  HAND       everything else: an arithmetic expression, a conditional, a
             hand-written constant list, a Python function body.

The split that decides the scope question is HEX+FFI_CLASS vs HAND.
"""
import re, os, sys, collections

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/runtime"
TARGETS = [os.path.join(ROOT, "autogen"),
           os.path.join(ROOT, "renderer", "amd"),
           os.path.join(ROOT, "am", "regs.py")]

HEXRE   = re.compile(r"\b0[xX][0-9a-fA-F]+\b|\b[0-9a-fA-F]{8,16}\b")
DECLRE  = re.compile(r"^\s*(#|$|from |import |dll = c\.DLL|try:|except|\)|\]|\}|@|\.\.\.)")
CLASSRE = re.compile(r"^\s*(class \w+\(|@c\.record|@dll\.bind|def \w+\(|  [A-Z_]+ = |  \w+: )")
TABLEROW= re.compile(r"^\s*[\w\.]+\s*(?::\s*[\w\[\], .]+\s*)?=\s*\S")
HANDRE  = re.compile(r"^\s*\w+\s*=\s*.*\b(if|else|for|while|return|len\(|sum\(|max\(|min\(|any\(|all\()")

counts = collections.Counter()
perfile = collections.Counter()
files = []
for t in TARGETS:
    if os.path.isfile(t): files.append(t)
    else:
        for d, _, fs in os.walk(t):
            for f in sorted(fs):
                if f.endswith(".py"): files.append(os.path.join(d, f))

def classify(l):
    s = l.rstrip("\n")
    st = s.strip()
    if st == "" or st.startswith("#"): return "blank/comment"
    if DECLRE.match(s):
        return "decl"
    if CLASSRE.match(s) and not TABLEROW.match(s): return "ffi_class"
    if HEXRE.search(s): return "hex"
    if HANDRE.match(s): return "hand"
    if TABLEROW.match(s): return "table_row"
    return "hand"

total = 0
for f in files:
    n = collections.Counter()
    for l in open(f, errors="replace"):
        n[classify(l)] += 1
        total += 1
    perfile[os.path.relpath(f, ROOT)] = n
    counts.update(n)

print(f"files scanned: {len(files)}   total lines: {total}")
for k in ("hex", "table_row", "ffi_class", "hand", "decl", "blank/comment"):
    print(f"  {k:14s} {counts[k]:8d}  {100.0*counts[k]/max(total,1):5.1f}%")
print()
mech = counts["hex"] + counts["ffi_class"] + counts["table_row"]
hand = counts["hand"]
print(f"MECHANICALLY DERIVABLE (hex + ffi_class + table_row): {mech}  ({100.0*mech/max(total,1):.1f}%)")
print(f"HAND-MAINTAINED  (hand)                              : {hand}  ({100.0*hand/max(total,1):.1f}%)")
print()
print("### the twenty largest files, with their split")
for name, n in sorted(perfile.items(), key=lambda kv: -sum(kv[1].values()))[:20]:
    tot = sum(n.values())
    print(f"  {name:46s} {tot:7d}  hex={n['hex']:6d} tbl={n['table_row']:6d} "
          f"cls={n['ffi_class']:6d} hand={n['hand']:5d}")
