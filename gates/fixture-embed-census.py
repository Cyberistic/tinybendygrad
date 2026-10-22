#!/usr/bin/env python3
"""fixture-embed-census.py -- THE `py=` CELLS WHOSE VALUE IS FROZEN IN A FIXTURE.

    .venv/bin/python gates/fixture-embed-census.py
    .venv/bin/python gates/fixture-embed-census.py --rows OUT.rows

WHAT THIS CENSUS IS FOR, AND THE CLASS IT FINDS
------------------------------------------------
`gates/pycell-census.py` classifies every `py=` cell in the port by PROVENANCE: a cell
whose value was TYPED is a TRANSCRIPTION, and one the port computes is DERIVED.  The
census resolves the `py=` slot's value THROUGH THE CALL CHAIN -- and it STOPS at the
first call into the port:

    if callee in self.ctx.port_defs or callee.split(".")[-1] in self.ctx.port_defs:
        return DERIVED, PORT_CALL, callee

**A PORT CALL IS NOT A PROVENANCE.**  A def that is a pure ACCESSOR of a data record
returns a FIELD, and the field's value comes from wherever the record was CONSTRUCTED.
So a chain that reaches such a def has not reached a generator -- it has reached a
PLACE -- and the census has to keep going.

**THE CLASS, IN ONE SENTENCE: a `py=` cell whose value is a LITERAL held in a DATA
FIXTURE, where the fixture is a frozen copy of a generated answer.**

MEASURED, AND IT IS ONE FILE
----------------------------
`renderer/ptx.bend` holds the class.  Its rows are `<suffix, answer, LITERAL>`, the
LITERAL lives in a `Wt` record's `want` field, and the `Wt` records are built by a
GENERATOR -- the file's own header says so:

    "A ROW IS (its suffix, the answer, the LITERAL). `Wt.want` is generated from
     the oracle's rows by `.agents/slop/ptx-s3-gen.py` and is NEVER typed"

and that generator is DELETED, and the port declares the region it wrote:

    # ==== BEGIN GENERATED FIXTURES      (line 674)
    # ==== END GENERATED FIXTURES        (line 1194)

**MEASURED: 268 `Wt{...}` records inside that region, EVERY ONE of them carrying a
LITERAL `want` -- 268 frozen copies of CPython's answers.  THE CENSUS COUNTS ONE
CELL.**  `gates/pycell-census.py` reports `renderer/ptx.bend` as 15 cells, 14 DERIVED,
1 TRANSCRIPTION, and the 14th of the 14 is the one whose `py=` slot is `Wt.want(w)`.
So the census UNDERSTATES the rot by 267 in that file alone, and it does not know it
is understating anything.

**AND TWO MORE MEASUREMENTS, BOTH OF THEM NEGATIVE RESULTS, WHICH ARE RESULTS.**
`runtime/ops_dsp.bend` has two cells whose `py=` slot is `Tr.refused(t)` -- also a
record accessor -- and NEITHER is in a generated region, because `Tr` is the port's
own trace record and its `refused` field is a `True{}`/`False{}` the port's own state
machine writes.  So an accessor is NOT the class: **the class is an accessor whose
record is CONSTRUCTED inside the port's own DECLARED generated region**, and the two
`Tr.refused` cells are the instrument saying so.  And the first version of the
record parser found **264** of the 268, because four of the `Wt` records carry a `}`
INSIDE A STRING (`Wt{".rows", "9"}]`) and a hand-rolled brace counter closed the
record there -- **a parser that counts four fewer is a parser that UNDERSTATES, and
understating is the defect this file exists to catch.**

HOW THE CENSUS MUST BE TAUGHT, AND IT IS TWO CLAUSES
-----------------------------------------------------
1. **THE CHAIN MUST CONTINUE THROUGH A RECORD ACCESSOR.**  A def whose body is
   `match p: case T{...}: f` returns the field `f`; the chain's next step is the
   CONSTRUCTION SITE of the `T`, not a generator.  The census must follow it there.
2. **THE CONSTRUCTION SITE'S REGION IS THE PORT'S OWN DECLARATION.**  A port that
   says `# ==== BEGIN GENERATED FIXTURES` has said, in its own source, that the values
   inside are GENERATED -- and a generated value whose generator is gone is a frozen
   copy.  **THE POPULATION IS THE PORT'S OWN DECLARATION, LOADED BY PATH, AND NOT A
   HAND LIST** (`AGENTS.md`, doctrine 1): the region is found by the markers in the
   source, and a file with no markers contributes nothing.

WHAT THIS CANNOT SEE, AND IT SAYS SO
-------------------------------------
The chain is followed through the port's own defs, and it stops at a def whose RETURN
VALUE it cannot locate.  A def that builds its answer by ACCUMULATING into a parameter
(`+acc = ...`) is not followed, because the value is not a single expression there.  A
`match` that BINDS a list element (`case w <> +t:`) is not followed either: the bound
name is an ELEMENT of a list, and the census does not know which element.  **So this
census is a LOWER BOUND, and it says so on every run**, the way `gates/gendirs.py`
says its population is a lower bound.  The class it reports is a class it can PROVE;
the class it cannot see is a class it says nothing about, and a census that reported
its own blindness as a clean bill would be worse than no census.

THE VERDICT
-----------
**EXIT 1 WHILE THE CLASS IS NON-EMPTY.**  The class IS rot: a frozen expectation with
no generator, compared against a port that computes.  A census that printed the count
and exited 0 would be a LABEL, and `gates/README.md`'s own rule is that a row which
cannot go red is worse than no row.  The class goes green when the fixtures are
generated from a live oracle again -- `gates/ptx_render_census-gen.py` is the shape of
that generator, and it exists.
"""
import argparse
import importlib.util
import os
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PORT = ROOT / "tinybendygrad"

#: THE CENSUS'S OWN MODULE, LOADED BY PATH.  Its file name has no dash, so it could be
#: imported by name, but it lives beside the gate and the house rule is to load a
#: sibling by path -- and the lexer, the row-builder discovery and the provenance
#: resolver are SHARED LOGIC, not something to copy.
CENSUS = HERE / "pycell-census.py"

#: THE PORT'S OWN DECLARATION OF ITS GENERATED FIXTURES.  The markers are in the
#: SOURCE, and the region between them is what a generator wrote.  **THESE ARE NOT A
#: HAND LIST OF FILES AND NOT A HAND LIST OF REGIONS**: the markers are the port's own
#: words, and a file that does not say them contributes nothing.
BEGIN = re.compile(r"^#\s*=+\s*BEGIN GENERATED FIXTURES\s*=*\s*$", re.M)
END = re.compile(r"^#\s*=+\s*END GENERATED FIXTURES\s*=*\s*$", re.M)

#: A RECORD ACCESSOR: `def NAME(+P: T) -> U:` whose body is `match P:` /
#: `case T{f1, f2, ...}: FIELD`.  The def RETURNS THE FIELD, so the chain's next step
#: is the record's CONSTRUCTION SITE.
ACCESSOR = re.compile(
    r"^def\s+([A-Za-z_][A-Za-z0-9_.]*)\(\s*\+(\w+)\s*:\s*(\w+)\s*\)\s*->[^\n]*:\n"
    r"\s*match\s+\2\s*:\n"
    r"\s*case\s+(\w+)\{([^}]*)\}\s*:\s*(\w+)\s*$", re.M)

#: A RECORD TYPE: `type T is Data:` and the next line's `T{field: Type, ...}`.
RECORD_TYPE = re.compile(r"^type\s+(\w+)\s+is\s+Data:\s*\n\s*\1\{([^}]*)\}\s*$", re.M)


def load_census():
    spec = importlib.util.spec_from_file_location("pycell_census", CENSUS)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def generated_regions(raw):
    """`[(first_line, last_line)]` of the port's OWN generated-fixture declarations.

    **THE MARKERS ARE COMMENTS, SO THEY ARE READ OUT OF THE RAW TEXT AND NOT OUT OF
    THE SCANNED CODE.**  `pycell-census.scan()` BLANKS every comment -- which is right
    for the census's own work, because a comment is not code -- and a marker that is a
    comment is therefore INVISIBLE in the scanned text.  A census that read the
    markers from the scanned code would find ZERO regions and report a clean bill on a
    tree that has 268 frozen copies in it.  **THE LINE NUMBERS STILL LINE UP**, because
    `scan()` replaces a comment with spaces and keeps its newlines.
    """
    out = []
    for m in BEGIN.finditer(raw):
        e = END.search(raw, m.end())
        if e:
            out.append((raw.count("\n", 0, m.start()) + 1,
                        raw.count("\n", 0, e.start()) + 1))
    return out


def record_fields(decl):
    """The field NAMES of a record declaration, in order."""
    out = []
    for part in decl.split(","):
        part = part.strip()
        if not part:
            continue
        out.append(part.split(":")[0].strip())
    return out


def constructions(code, typename, C):
    """`[(line, [field values])]` for every CONSTRUCTION of `typename`.

    A construction is a record LITERAL in an expression.  It is NOT the type
    DECLARATION (`type T is Data:` and the next line) and it is NOT a PATTERN
    (`case T{...}:`) -- and a census that counted those two would report the type's
    own shape as a frozen copy of an answer, which is the wrong kind of wrong.

    **THE BRACKET MATCH IS THE CENSUS'S OWN, AND IT IS STRING-AWARE.**  MEASURED: a
    hand-rolled brace counter found **264** of the 268 `Wt` records, because four of
    them carry a `}` INSIDE a string literal -- `Wt{".rows", "9"}]` -- and the counter
    closed the record at the `}` in the string.  `pycell-census.match_close` skips
    string literals, so it closes the record at the right brace.  **A PARSER THAT
    COUNTS FOUR FEWER IS A PARSER THAT UNDERSTATES, AND A CENSUS THAT UNDERSTATES IS
    THE DEFECT THIS FILE EXISTS TO CATCH.**
    """
    out = []
    for m in re.finditer(r"(?<![\w.])" + re.escape(typename) + r"\{", code):
        line = code.count("\n", 0, m.start()) + 1
        before = code[:m.start()]
        head = before.rsplit("\n", 1)[-1]
        prev = before.rsplit("\n", 2)[-2] if before.count("\n") >= 2 else ""
        if re.search(r"\bcase\s+$", head):
            continue                                  # a PATTERN
        if re.search(r"^type\s+" + re.escape(typename) + r"\s+is\s+Data:\s*$", prev):
            continue                                  # the DECLARATION
        end = C.match_close(code, m.end() - 1)
        body = code[m.end():end - 1]
        out.append((line, split_top(body)))
    return out


def split_top(text):
    """Split a record body on its top-level commas."""
    out, depth, cur, instr = [], 0, [], False
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if instr:
            cur.append(c)
            if c == "\\":
                cur.append(text[i + 1] if i + 1 < n else "")
                i += 2
                continue
            if c == '"':
                instr = False
            i += 1
            continue
        if c == '"':
            instr = True
            cur.append(c)
            i += 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    tail = "".join(cur).strip()
    if tail or out:
        out.append(tail)
    return out


def is_literal(text):
    """Is this a LITERAL -- a string, a number, a boolean?  The census's own rule."""
    t = text.strip()
    if len(t) >= 2 and t.startswith('"') and t.endswith('"'):
        return True
    if t in ("True", "False", "True{}", "False{}"):
        return True
    if re.fullmatch(r"-?\d+(?:\.\d+)?", t):
        return True
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rows", help="write the census as rows")
    args = ap.parse_args()
    C = load_census()
    files = C.bend_files(str(PORT))
    ctxs = {}
    for path in files:
        raw = open(path, encoding="utf-8", errors="replace").read()
        code, _spans = C.scan(raw)
        ctxs[path] = (raw, code)

    # ---- THE PORT'S OWN DECLARATIONS, and the accessors they are read through.
    accessors = {}          # accessor name -> (typename, field)
    for path, (_raw, code) in ctxs.items():
        for (name, _p, typename, _tn, fields, field) in ACCESSOR.findall(code):
            accessors[name] = (typename, field)
            accessors[name.split(".")[-1]] = (typename, field)
    regions = {path: generated_regions(raw) for path, (raw, _code) in ctxs.items()}
    declared = {p for p, rs in regions.items() if rs}

    # ---- THE CELLS, from the census's OWN machinery.
    rows, _per_file, _files, _defs = C.census_port(str(PORT))

    # ---- THE CLASS.  A cell the census calls DERIVED whose value is supplied by a
    # RECORD ACCESSOR, where the accessor's type is CONSTRUCTED with a LITERAL inside
    # a GENERATED region.
    frozen = []            # (file, builder, site, row name, type, field, value)
    cells = []             # (file, builder, site, row name, type, field)
    for r in rows:
        if r["form"] != "PORT-CALL":
            continue
        callee = r["value"]
        if callee not in accessors:
            continue
        typename, field = accessors[callee]
        path = str(PORT / r["file"])
        raw, code = ctxs[path]
        fields = None
        for (t, decl) in RECORD_TYPE.findall(code):
            if t == typename:
                fields = record_fields(decl)
        if not fields or field not in fields:
            continue
        idx = fields.index(field)
        cells.append((r["file"], r["builder"], r["site"], r["name"], typename, field))
        for (line, vals) in constructions(code, typename, C):
            if len(vals) <= idx:
                continue
            if not any(a <= line <= b for (a, b) in regions.get(path, [])):
                continue
            if not is_literal(vals[idx]):
                continue
            frozen.append((r["file"], r["builder"], r["site"], r["name"], typename, field,
                           vals[idx]))

    # ---- THE REPORT
    print(f"PORT                 : {PORT}")
    print(f"FILES                : {len(files)} `.bend` files (DISCOVERED by os.walk + endswith)")
    print(f"FILES WITH A DECLARED GENERATED-FIXTURE REGION: {len(declared)}")
    for p in sorted(declared):
        for (a, b) in regions[p]:
            print(f"  {os.path.relpath(p, PORT)}: lines {a}..{b}")
    print(f"CELLS                : {len(rows)} (the census's own count)")
    print(f"CELLS FED BY A RECORD ACCESSOR: {len(cells)}")
    print(f"FROZEN COPIES        : {len(frozen)}")
    print("")
    by_file = {}
    for f in frozen:
        by_file.setdefault(f[0], []).append(f)
    census_by_file = {}
    for r in rows:
        census_by_file.setdefault(r["file"], Counter())[r["kind"]] += 1
    for f in sorted(by_file):
        c = census_by_file.get(f, Counter())
        print(f"  {f}: {len(by_file[f])} frozen copies, "
              f"{len({c[2] for c in by_file[f]})} cell(s); the census says "
              f"{c.get('DERIVED', 0)} DERIVED and {c.get('TRANSCRIPTION', 0)} TRANSCRIPTION "
              f"for this file -- so the DELTA is {len(by_file[f]) - c.get('TRANSCRIPTION', 0)}")
    if not frozen:
        print("  none")
    # ---- THE ACCESSOR-FED CELLS THAT ARE **NOT** FIXTURE-EMBEDDED.  A NEGATIVE RESULT
    # IS A RESULT, and naming them is what stops a reader from assuming the census saw
    # only what it reported.
    clean = [c for c in cells if (c[0], c[2]) not in {(f[0], f[2]) for f in frozen}]
    if clean:
        print("")
        print("ACCESSOR-FED CELLS THAT ARE NOT IN A GENERATED REGION (so NOT frozen "
              "expectations):")
        for (f, b, s, n, t, fl) in clean:
            print(f"  {f} builder={b} site={s} {t}.{fl} -- the record is the port's own "
                  f"state, not a generated answer")
    print("")
    print("THE DELTA, AND IT IS THE POINT: the census counts the CELLS, and the rot is")
    print("the FROZEN COPIES.  A cell that reads one fixture record is ONE row in the")
    print("census and N frozen answers, and the census cannot see the difference because")
    print("it stops at the accessor.")

    if args.rows:
        Path(args.rows).write_text(
            "".join(f"file={f} builder={b} site={s} type={t} field={fl} value={v}\n"
                    for (f, b, s, _n, t, fl, v) in sorted(frozen)))
        print(f"wrote {args.rows}")

    if frozen:
        print(f"\n== FAIL: {len(frozen)} FIXTURE-EMBEDDED TRANSCRIPTIONS in "
              f"{len(by_file)} file(s) -- the census calls them DERIVED and they are "
              f"frozen copies of a generator that is gone.")
        return 1
    print("\n== PASS: no fixture-embedded transcription the census cannot see")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
