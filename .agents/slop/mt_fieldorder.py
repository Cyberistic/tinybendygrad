#!/usr/bin/env python3
"""FIELD-ORDER / TRANSPOSITION audit for `runtime/ops_metal.bend`.

WHY. `ops_nv`'s `struct_libusb_transfer` was a transposed field order, and agent-core
records that `ops_cl`'s unit found `Sig`'s field NAMES inverted. A count-based gate
cannot see either: `struct_libusb_transfer{k, sel, arg}` and
`struct_libusb_transfer{sel, k, arg}` have the same arity, the same field names and
the same number of rows. So this checks POSITION, not membership.

  1. READERS -- `case T{a, b, c}: <name>`: the destructured names must be the
     declaration's field order, and the returned name must be the one at THAT
     position. A reader that binds correctly and returns the neighbour is a silently
     wrong read, which is the whole failure class.
  2. CONSTRUCTIONS -- `T{v1, v2, v3}`: a literal or an expression must land in a slot
     whose declared type it can be. Two same-typed U32 fields swapped (`{k, sel}` ->
     `{sel, k}`) is invisible to any rule keyed on types, so constructions that are
     ALL field names are reported too and left to a human, and constructions mixing
     names and values are checked position by position.

Run: .venv/bin/python .agents/slop/mt_fieldorder.py
"""
import re, sys
from pathlib import Path

PORT = Path(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") \
       else Path(__file__).resolve().parents[2] / "tinybendygrad/runtime/ops_metal.bend"
SRC = PORT.read_text().splitlines()

# ---- the declarations. Field lists SPAN LINES, so gather until the braces balance.
def _split_top(s):
  """split on commas that are NOT inside `<>` or `()`. `Tr` declares
  `calls: List<&2, Call>`, and a plain `split(",")` reads that as two fields -- which
  is how a field-order checker ends up checking a field list nobody wrote."""
  out, buf, depth = [], "", 0
  for c in s:
    if c in "<(": depth += 1
    elif c in ">)": depth -= 1
    if c == "," and depth == 0:
      out.append(buf); buf = ""
    else:
      buf += c
  out.append(buf)
  return out


decls = {}
i = 0
while i < len(SRC):
    m = re.match(r"^type (\w+) is Data:\s*$", SRC[i])
    if m:
        j, buf, depth = i + 1, "", 0
        while j < len(SRC):
            buf += SRC[j].strip()
            depth += SRC[j].count("{") - SRC[j].count("}")
            if depth <= 0 and buf.endswith("}"): break
            j += 1
        head = re.match(r"^(\w+)\{(.*)\}$", buf)
        assert head, f"line {i+1}: could not read the field list of {m.group(1)}: {buf!r}"
        fields = []
        for part in _split_top(head.group(2)):
            part = part.strip()
            if not part: continue
            assert ":" in part, f"line {i+1}: field {part!r} has no type annotation"
            n, t = part.split(":", 1)
            fields.append((n.strip(), t.strip()))
        decls[m.group(1)] = (i + 1, fields)
        i = j
    i += 1

print(f"{PORT.name}: {len(decls)} `type ... is Data` declarations, field order read from source\n")
for n, (ln, fl) in sorted(decls.items(), key=lambda kv: kv[1][0]):
    print(f"  L{ln:<5} {n:9} " + ", ".join(f"{a}:{b}" for a, b in fl))

# ---- 1. readers
print("\n[1] READERS -- destructured names must equal the declaration's order, and the")
print("    returned name must be the field AT THAT POSITION")
bad = 0
seen = 0
for i, l in enumerate(SRC, 1):
    m = re.match(r"^\s*case (\w+)\{([^{}]*)\}:\s*(\w+)\s*$", l)
    if not m or m.group(1) not in decls: continue
    seen += 1
    t, names, ret = m.group(1), [x.strip() for x in m.group(2).split(",")], m.group(3)
    order = [a for a, _ in decls[t][1]]
    if len(names) != len(order):
        print(f"  !! L{i} {t}: destructures {len(names)} of {len(order)} fields"); bad += 1; continue
    if names != order:
        print(f"  !! L{i} {t}: destructures {names}\n            declares {order}  <- TRANSPOSED"); bad += 1; continue
    if ret not in order:
        print(f"  !! L{i} {t}: returns {ret!r}, which is not a field of {t}"); bad += 1; continue
    if names[order.index(ret)] != ret:
        print(f"  !! L{i} {t}: returns {ret!r} bound to position {order.index(ret)}"); bad += 1
print(f"  {seen} reader bindings checked, {bad} mismatches")

# ---- 2. constructions
# The decidable question is CATEGORY, not shape. `CALL_MSGSEND` and `sel_ix("new")`
# are both perfectly good U32 values, and a predicate that demanded a digit or a bare
# call reported 140 of them as suspicious -- an audit that cries wolf is an audit
# nobody reads. So only a value whose CATEGORY is visible (a Bool literal, a string
# literal, a list literal) is checked against the declared type of its slot.
print("\n[2] CONSTRUCTIONS -- a value whose category is visible must sit in a slot of")
print("    that category. Two U32 fields swapped are NOT decidable by type; those are")
print("    listed below for reading, not certified.")
CATEGORY = [("Bool", re.compile(r"^(?:True|False)\{\}$")), ("String", re.compile(r'^".*"$')),
            ("List", re.compile(r"^\[|^List<"))]
bad2 = allnames = mixed = catchecked = 0
for i, l in enumerate(SRC, 1):
    for m in re.finditer(r"(?<![\w.])([A-Z]\w*)\{([^{}]+)\}", l):
        t, body = m.group(1), m.group(2)
        if t not in decls or re.match(r"^\s*case ", l): continue
        vals = _split_top(body)
        order = decls[t][1]
        if len(vals) != len(order): continue
        if [v.strip() for v in vals] == [a for a, _ in order]:
            allnames += 1; continue          # a binder or an all-names copy: nothing to check
        mixed += 1
        for v, (fname, ftype) in zip((v.strip() for v in vals), order):
            if re.fullmatch(r"[a-z_]\w*", v): continue     # a field name in its own slot
            cat = next((c for c, rx in CATEGORY if rx.match(v)), None)
            if cat is None: continue
            catchecked += 1
            if not ftype.startswith(cat):
                print(f"  !! L{i} {t}{{{body}}}: {v} is a {cat}, slot {fname}:{ftype}"); bad2 += 1
print(f"  {allnames} all-name constructions (nothing positional to check), {mixed} mixed, "
      f"{catchecked} category-visible, {bad2} category violations")
print("\nMIXED CONSTRUCTIONS, for reading rather than certifying:")
for i, l in enumerate(SRC, 1):
    for m in re.finditer(r"(?<![\w.])([A-Z]\w*)\{([^{}]+)\}", l):
        t, body = m.group(1), m.group(2)
        if t not in decls or re.match(r"^\s*case ", l): continue
        vals = _split_top(body)
        order = decls[t][1]
        if len(vals) != len(order) or [v.strip() for v in vals] == [a for a, _ in order]: continue
        print(f"  L{i:<5} {t}{{{body}}}")

sys.exit(1 if (bad or bad2) else 0)