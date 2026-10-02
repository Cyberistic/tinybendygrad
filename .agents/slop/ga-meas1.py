#!/usr/bin/env python3
"""MEASUREMENT 1 for renderer/amd/generate.py: LOGIC vs MECHANICAL EMISSION.

Same classifier as .agents/slop/ag-meas1.py, with generate.py's OWN FFI surface
swapped in.  The classifier is mechanical and printed line by line so the count
can be argued with.

  LOGIC      -- a line that COMPUTES something: a branch, a comparison, a loop,
                an index, a mutation of generator state, a lookup.
  EMISSION   -- a line whose only job is to CONCATENATE a fixed template with
                already-computed values: an f-string inside a `lines.append`,
                or a `return`, contributing no branch of its own.
  FFI        -- a line that calls the outside world: `fetch`, `zipfile`,
                `ET.`, `re.`, `zlib`, `open`, `pathlib`, `sorted(...)[0]`
                is NOT ffi (it is logic).
  DECL       -- a `def`/`class` header or signature.

Run: python3 .agents/slop/ga-meas1.py
"""
import sys, re

SRC = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/renderer/amd/generate.py"
lines = open(SRC).read().split("\n")
if lines and lines[-1] == "":
    lines.pop()

# generate.py's FFI: the XML fetch/parse, the PDF fetch/parse, and file writes.
FFI_RE = r"\b(fetch\(|zipfile\.|ET\.|re\.(search|finditer|findall|sub|match)|zlib\.|open\(path|pathlib\.|etree)"


def classify(l):
    s = l.strip()
    if s == "":
        return "blank", ""
    if s.startswith("#"):
        return "comment", ""
    if re.match(r"^(def |class )", s):
        return "decl", s[:72]
    if re.match(r"^(elif|case |except |for |while |if |else|try:|with |@\w)", s):
        return "logic", s[:72]
    if re.search(FFI_RE, s):
        return "ffi", s[:72]
    emits = re.search(r"\b(lines\.append|lines\.extend|extras \+=|return)\b", s)
    templ = ('f"' in s) or ("f'" in s) or re.search(r"""["']\.join\(""", s)
    # branch test runs with STRING LITERALS BLANKED so the `, ` / ` and ` that
    # the templates SUBSTITUTE IN do not read as branches in the substituting line.
    nostr = re.sub(r"""('[^']*'|"[^"]*")""", '""', s)
    branch = re.search(r"\b(if|else|case|and|or|not)\b|:=", nostr)
    if emits and templ and not branch:
        return "emission", s[:72]
    return "logic", s[:72]


buckets = {k: [] for k in ("logic", "emission", "ffi", "blank", "comment", "decl")}
for i, l in enumerate(lines):
    k, txt = classify(l)
    buckets[k].append((i + 1, txt))

tot = len(lines)
print(f"TOTAL source lines (file, minus trailing newline): {tot}")
for k in ("logic", "emission", "ffi", "decl", "comment", "blank"):
    print(f"  {k:9s} {len(buckets[k]):4d}   {100.0*len(buckets[k])/tot:5.1f}%")
print()
core = len(buckets["logic"]) + len(buckets["emission"])
print(f"CORE (logic + emission, the two kinds a Bend port must reproduce): {core}")
print(f"  logic     {len(buckets['logic'])}  ({100.0*len(buckets['logic'])/core:.1f}% of core)")
print(f"  emission  {len(buckets['emission'])}  ({100.0*len(buckets['emission'])/core:.1f}% of core)")
print(f"  ffi       {len(buckets['ffi'])}  ({100.0*len(buckets['ffi'])/tot:.1f}% of file, WALL 1)")
print()
for k in ("emission", "ffi"):
    print(f"### every {k.upper()} line, numbered, so the count can be argued with")
    for n, t in buckets[k]:
        print(f"  {n:4d}  {t}")
    print()
print("### every DECL line (a def/class header or signature)")
for n, t in buckets["decl"]:
    print(f"  {n:4d}  {t}")