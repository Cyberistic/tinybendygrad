#!/usr/bin/env python3
"""MEASUREMENT 1: of autogen.py's 289 lines, how many are LOGIC and how many
are MECHANICAL EMISSION?  Counted, not estimated.

The classifier is mechanical and stated up front so it can be argued with:

  LOGIC      -- a line that COMPUTES something: a branch, a comparison, a
                loop, an index, a mutation of generator state, a lookup.
  EMISSION   -- a line whose only job is to CONCATENATE a fixed template with
                already-computed values, i.e. an f-string that appears inside
                a `lines.append(...)` / `lines.extend(...)` / `extras +=` /
                `return` and contributes no branch of its own.
  FFI        -- a line that calls a `clang_*` / ctypes / os / open function.
                Counted separately, because it is WALL 1 and neither logic nor
                emission.
  BLANK/COMMENT/DECL -- blank lines, comments, and top-level `class`/`def`
                headers plus their signatures (the header is not logic and the
                body is counted line by line).

Run: python3 ag-meas1.py
"""
import sys, re
SRC = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/runtime/support/autogen.py"
lines = open(SRC).read().split("\n")
if lines and lines[-1] == "": lines.pop()

def classify(i, l):
    s = l.strip()
    if s == "": return "blank", ""
    if s.startswith("#"): return "comment", ""
    # signature / decorator / class header: no trailing colon-body
    if re.match(r"^(def |class )", s):
        return "decl", s[:70]
    if re.match(r"^(elif|case |except |for |while |if |else|try:|with )", s):
        return "logic", s[:70]
    # FFI wins over emission: a line that CALLS libclang is WALL 1, not a
    # template join, even when the template join is what it returns.
    if re.search(r"\b(clang_[A-Za-z_]+|clang\.|ctypes\.|os\.fspath|open\(|functools\.|keyword\.)", s):
        return "ffi", s[:70]
    # EMISSION: the line's whole job is to CONCATENATE a fixed template with
    # already-computed values.  It must (a) be a return or a lines/extras
    # append, (b) contain an f-string or a quote-join, and (c) contain NO
    # branch of its own (`if`, `else`, `case`, `and`, `or`, `not`, `:=`).
    emits = re.search(r"\b(lines\.append|lines\.extend|extras \+=|lines\[ln\] =|main =|return)\b", s)
    templ = ('f"' in s) or ("f'" in s) or re.search(r"""["']\.join\(""", s)
    # the branch test runs on the line with STRING LITERALS BLANKED, so the
    # ` and ` / ` or ` / ` not ` that base_rules SUBSTITUTES IN do not read as
    # a branch in the line that substitutes them.
    nostr = re.sub(r"""('[^']*'|"[^"]*")""", '""', s)
    branch = re.search(r"\b(if|else|case|and|or|not)\b|:=", nostr)
    if emits and templ and not branch:
        return "emission", s[:70]
    # a plain expression: assignment/return/continuation of a computation
    return "logic", s[:70]

buckets = {"logic": [], "emission": [], "ffi": [], "blank": [], "comment": [], "decl": []}
for i, l in enumerate(lines):
    k, txt = classify(i, l)
    buckets[k].append((i + 1, txt))

tot = len(lines)
print(f"TOTAL source lines (file, minus trailing newline): {tot}")
for k in ("logic", "emission", "ffi", "decl", "comment", "blank"):
    print(f"  {k:9s} {len(buckets[k]):4d}   {100.0*len(buckets[k])/tot:5.1f}%")
print()
core = len(buckets["logic"]) + len(buckets["emission"])
print(f"CORE (logic + emission, the two kinds that a Bend port must reproduce): {core}")
print(f"  logic     {len(buckets['logic'])}  ({100.0*len(buckets['logic'])/core:.1f}% of core)")
print(f"  emission  {len(buckets['emission'])}  ({100.0*len(buckets['emission'])/core:.1f}% of core)")
print(f"  ffi       {len(buckets['ffi'])}  ({100.0*len(buckets['ffi'])/tot:.1f}% of file, WALL 1)")
print()
print("### every EMISSION line, numbered, so the count can be argued with")
for n, t in buckets["emission"]: print(f"  {n:4d}  {t}")
print()
print("### every DECL line (a def/class header or signature)")
for n, t in buckets["decl"]: print(f"  {n:4d}  {t}")
