#!/usr/bin/env python3
"""MEASUREMENT 1, REFINED, for renderer/amd/generate.py.

ag-meas1.py's classifier called this file 390 "logic" because generate.py's
parsing is written as comprehensions and `for` loops rather than as calls, so
the FFI regex never fired on them.  That OVERSTATES the portable surface: the
two parsing functions (`parse_xml`, `extract_pdf_text`, `extract_pcode`) are
about 200 lines and almost every one of them is either an ElementTree descent
or a regex match, i.e. WALL 1.

So: regions, then a three-way split inside each region.

  LOGIC     -- a DECISION over already-decoded values: a branch, a comparison,
               an index, a name normalization, a mutation of generator state.
  EMISSION  -- concatenate a fixed template with computed values, no branch.
  FFI       -- reach outside: fetch/zipfile/ET/regex/zlib/open/bytes.fromhex,
               and any `findall`/`findtext`/`finditer`/`match(` descent.

Regions are the def blocks plus the `if __name__` main block, and the per-region
counts are what the report quotes -- a global ratio hides that three of the
six functions are one wall and three are one table.

Run: python3 .agents/slop/ga-meas2.py
"""
import re

SRC = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/renderer/amd/generate.py"
lines = open(SRC).read().split("\n")
if lines and lines[-1] == "":
    lines.pop()

# NOTE: `str.startswith/endswith/isdigit/removeprefix` are deliberately NOT
# here. ag-meas2's first draft put them in FFI and that was wrong: bend has
# `String.startsWith`/`endsWith` and they are ordinary ported logic. Only
# genuine outside-the-language reaches count as FFI.
FFI_RE = re.compile(
    r"(\bfetch\(|\bzipfile\.|\bET\.|\bzlib\.|\bpathlib\.|open\(path"
    r"|\bre\.(search|finditer|findall|sub|match|compile)\b|\.find(all|text)?\("
    r"|\bbytes\.fromhex\b|\bdata\[|\bobj\[|\braw\b|\.read_bytes\(\))"
)


def region_of(i):
    """The ENCLOSING top-level def (column 0), or the banner/config region.

    A column-0 scan, not a `def` scan: generate.py nests four closures
    (`_pv_val`, `get_stream`, `get_base_fmt`/`field_def`/`sort_fields`/`fmt_allowed`
    inside write_ins) and a plain nearest-`def` scan attributes 78 lines to
    `_pv_val` and 103 to `fmt_allowed`, which reads as though those two closures
    are the biggest functions in the file. They are not; write_ins is.
    """
    for j in range(i, -1, -1):
        s = lines[j]
        m = re.match(r"^def (\w+)", s)
        if m:
            return m.group(1)
        if s.startswith('if __name__'):
            return "__main__"
    return "module(banner+config)"


def classify(l):
    s = l.strip()
    if s == "":
        return "blank", ""
    if s.startswith("#"):
        return "comment", ""
    if re.match(r"^(def |class )", s):
        return "decl", s[:72]
    if re.match(r"^@\w", s):
        return "decorator", s[:72]
    if FFI_RE.search(s):
        return "ffi", s[:72]
    if re.match(r"^(elif|case |except |for |while |if |else|try:|with )", s):
        return "logic", s[:72]
    emits = re.search(r"\b(lines\.append|lines\.extend|extras \+=|return)\b", s)
    templ = ('f"' in s) or ("f'" in s) or re.search(r"""["']\.join\(""", s)
    nostr = re.sub(r"""('[^']*'|"[^"]*")""", '""', s)
    branch = re.search(r"\b(if|else|case|and|or|not)\b|:=", nostr)
    if emits and templ and not branch:
        return "emission", s[:72]
    return "logic", s[:72]


rows = [(i + 1, region_of(i), classify(l)) for i, l in enumerate(lines)]

tot = len(rows)
by = {}
for n, reg, (k, txt) in rows:
    by.setdefault(reg, {}).setdefault(k, []).append((n, txt))

print(f"TOTAL source lines: {tot}\n")
print(f"{'region':34s} {'tot':>4s} {'logic':>6s} {'emis':>5s} {'ffi':>5s} {'decl':>5s} {'cmt':>5s} {'blnk':>5s}")
grand = {k: 0 for k in ("logic", "emission", "ffi", "decl", "comment", "blank", "decorator")}
for reg, d in by.items():
    for k, v in d.items():
        grand[k] += len(v)
    print(f"{reg:34s} {sum(len(v) for v in d.values()):4d} {len(d.get('logic', [])):6d} "
          f"{len(d.get('emission', [])):5d} {len(d.get('ffi', [])):5d} {len(d.get('decl', [])):5d} "
          f"{len(d.get('comment', [])):5d} {len(d.get('blank', [])):5d}")
print(f"{'TOTAL':34s} {tot:4d} {grand['logic']:6d} {grand['emission']:5d} {grand['ffi']:5d} "
      f"{grand['decl']:5d} {grand['comment']:5d} {grand['blank']:5d}")

core = grand["logic"] + grand["emission"]
print()
print(f"CORE (logic + emission): {core}")
print(f"  logic    {grand['logic']}  ({100.0*grand['logic']/core:.1f}% of core)")
print(f"  emission {grand['emission']}  ({100.0*grand['emission']/core:.1f}% of core)")
print(f"LOGIC:EMISSION = {grand['logic']}:{grand['emission']} = "
      f"{grand['logic']/max(1,grand['emission']):.1f} : 1")
print(f"  ffi {grand['ffi']} ({100.0*grand['ffi']/tot:.1f}% of file, WALL 1)")
print()
print("### every EMISSION line, numbered")
for n, reg, (k, txt) in rows:
    if k == "emission":
        print(f"  {n:4d} {reg:26s} {txt}")
print()
print("### every FFI line, numbered, with its region -- the WALL 1 surface")
for n, reg, (k, txt) in rows:
    if k == "ffi":
        print(f"  {n:4d} {reg:26s} {txt}")