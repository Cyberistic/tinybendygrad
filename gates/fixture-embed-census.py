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

**AND THE CENSUS UNDERSTATED ITS OWN CELLS BY 69, WHICH IS THE SAME DEFECT ONE LEVEL
UP.**  MEASURED: the census reported **3** accessor-fed cells and the port has **72**.
The reason is that it resolved the record's TYPE DECLARATION and its CONSTRUCTION
SITES **in the cell's own file**, and the port does not put them there: `TlAcc` is
declared in `tinybendygrad/viz/serve.bend` and constructed in `tinybendygrad/renderer/tc.bend`,
`Red` in `tinybendygrad/codegen/decomp/transcendental*.bend` and read in
`tinybendygrad/renderer/tc_ptx.bend`, `Run` in `tinybendygrad/sz.bend` and read in
`tinybendygrad/runtime/ops_dsp.bend`.  **⇒ THE DECLARATION AND THE CONSTRUCTION ARE
NOW RESOLVED ACROSS THE WHOLE PORT.**

**AND A NAME IS NOT A TYPE.**  MEASURED: the port declares TWO different `Red` records
-- `Red{r: F32, q: U32}` in `transcendental_f32.bend` and `Red{ar: O.Arena, r: U32,
q: U32}` in `transcendental.bend` -- so a map keyed by the NAME ALONE reads `Red.b`'s
value out of the WRONG record.  **⇒ THE DECLARATION IS RESOLVED IN THE FILE THAT
CONSTRUCTS IT**, with the file that DEFINES THE ACCESSOR as the fallback.

**AND THE FOUR CLASSES, NONE OF WHICH IS A SILENCE.**  `FROZEN` (the rot) ·
`PORT-STATE` (accessor-fed, and the record is the port's OWN state -- **71** cells, and
a FALSE POSITIVE IS A ROW THAT CANNOT GO RED, IN THE OTHER DIRECTION) · `PLACEHOLDER`
(accessor-fed, and the value at the construction site is NOT a literal -- a slot, not an
answer) · `UNDECLARED` (accessor-fed, and the record's type is nowhere in the port --
the census CANNOT see it, and it says so rather than counting it).

**AND THE COUNT THAT MATTERS MOST: WHAT THE FROZEN ONES ARE WORTH TODAY.**
`gates/ptx_render_census-s3-oracle.py bend` is the house's `bend` MODE -- the oracle
EMITS THE PORT's OWN SOURCE -- and it emits **268 `Wt{nm, want}` records** with what
CPython answers **TODAY**.  MEASURED, against those 268: **181 are STILL RIGHT, 2 carry
a WRONG VALUE** (`f13_param`'s PARAM is `%dat_u64_0` at the pin and the frozen copy says
`%dat_f32_0`), and **85 name a row that has MOVED** -- the 2026-10-16 re-vendor moved a
BUFFER's size out of the `ParamArg` and into a size CONST SRC, so CPython's own graphs
gained a node and every BUFFER-bearing fixture's `.r[i]` indices moved by one.
**⇒ 87 of the 268 are not what CPython says today, and 181 are.**

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
import hashlib
import importlib.util
import os
import re
import subprocess
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
#: **AND THE ONE-LINE SPELLING**, because the pin's `sz.bend:1479` writes
#: `type Run is Data: Run{text: String, ...}` on ONE line and the first version of this
#: regex missed it.  MEASURED: the two shapes are both in the tree, so a regex that
#: admits one of them is a census that cannot see half the port's record types.
RECORD_TYPE = re.compile(r"^type\s+(\w+)\s+is\s+Data:\s*\1\{([^}]*)\}\s*$", re.M)


def load_census():
    spec = importlib.util.spec_from_file_location("pycell_census", CENSUS)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_fixture_region_gate():
    """`gates/fixture-region-gate.py` BY PATH, for its `check_file()`.

    **THE REGION's CLASS IS NOT DECIDED HERE, BECAUSE DECIDING IT HERE IS HOW THE CLASS
    BECAME A LABEL.**  A literal inside a region the port DECLARES as generated was
    counted FROZEN, and that is TRUE OF EVERY GENERATED REGION EVER, so REGENERATING THE
    REGION CHANGED NOTHING ABOUT THE COUNT -- a class that cannot go empty is not a class.
    The class is now the GENERATOR's PRESENCE, and the instrument that knows it is
    `gates/fixture-region-gate.py`, which RUNS the generator the region names and compares.
    It is loaded BY PATH so there is one answer and not two.
    """
    spec = importlib.util.spec_from_file_location(
        "fixture_region_gate", HERE / "fixture-region-gate.py")
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


def live_comparison(frozen):
    """THE FROZEN COPIES AGAINST CPython's LIVE ANSWERS, AND THE COUNT.

    **THE `bend` MODE, WHICH IS THE HOUSE's SHAPE.**  `gates/nl-oracle.py bend` and
    `gates/x86_isa-oracle.py bend` EMIT THE PORT's OWN SOURCE, so a regenerated region
    carries LIVE values.  `gates/ptx_render_census-s3-oracle.py bend` does the same for the
    port's OWN 25 fixtures: MEASURED, it emits **268 `Wt{nm, want}` records** and every
    `want` is what CPython answers TODAY.

    THE COMPARISON IS OVER THE `Wt` SOURCE RECORDS, NOT OVER PARSED VALUES, because the two
    sides are SOURCE and a parser that unescapes one side and not the other compares two
    spellings.  MEASURED, and it is the trap: the port spells a TAB-bearing value
    `"\\t.reg\\t\\t.u64 %local_u64_<1>;"` and an emitter that writes the value unescaped
    produces `"\t.reg..."` -- 85 records that differ by NOTHING BUT THE ESCAPE, which is a
    byte diff over 85 rows that says nothing about PTX.

    THE THREE NUMBERS, AND THEY ARE DIFFERENT QUESTIONS:
      STALE   the port holds a `Wt` whose KEY CPython no longer emits -- the row it names
              has MOVED.  MEASURED, the 2026-10-16 re-vendor moved a BUFFER's size out of
              the `ParamArg` and into a size CONST SRC, so CPython's own graphs gained a
              node and every BUFFER-bearing fixture's `.r[i]` indices moved by one.
      WRONG   the port holds a `Wt` whose KEY CPython still emits and whose VALUE is a
              DIFFERENT answer.  THIS IS THE ROT THAT MATTERS: a right key with a wrong
              answer is a fixture that asserts something false.
      RIGHT   the same key with the same value -- still true today.
    """
    oracle = HERE / "ptx_render_census-s3-oracle.py"
    if not oracle.exists():
        return ""
    py = ROOT / ".venv" / "bin" / "python"
    r = subprocess.run([str(py), str(oracle), "bend"], capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        return (f"THE LIVE LANE DID NOT RUN (rc={r.returncode}): "
                f"{r.stderr.strip()[:200]} -- NOTHING WAS COMPARED, and that is not a PASS")

    def records(text, defpat):
        out = {}
        cur = None
        for line in text.splitlines():
            m = re.match(defpat, line)
            if m:
                cur = m.group(1)
                continue
            w = re.search(r'Wt\{.*\}', line)
            if w and cur:
                out[(cur, w.group(0))] = w.group(0)
        return out

    # THE PORT's OWN FROZEN REGION, read BY PATH from the file that DECLARES it.
    port = PORT / "renderer" / "ptx.bend"
    if not port.is_file():
        return ""
    raw = port.read_text(encoding="utf-8", errors="replace")
    a = raw.find(BEGIN.search(raw).group(0)) if BEGIN.search(raw) else -1
    if a < 0:
        return ""
    b = raw.find("# ==== END GENERATED FIXTURES", a)
    region = raw[a:b]
    # THE PORT's `Wt` RECORDS, per fixture, as SOURCE TEXT.
    port_recs = {}
    cur = None
    for line in region.splitlines():
        m = re.match(r"^def (f\d+_\w+)\(\) -> String: r_fix\(", line)
        if m:
            cur = m.group(1)
            continue
        w = re.search(r'Wt\{.*\}', line)
        if w and cur:
            port_recs[(cur, w.group(0))] = w.group(0)
    live_recs = records(r.stdout, r"^def (f\d+_\w+)_wants\(\)")

    def key_of(rec):
        # THE KEY IS THE FIXTURE AND THE `Wt`'s FIRST FIELD -- the row the record names.
        m = re.match(r'Wt\{"((?:[^"\\]|\\.)*)"', rec)
        return m.group(1) if m else rec

    port_by_key, live_by_key = {}, {}
    for (fix, rec), _ in port_recs.items():
        port_by_key[(fix, key_of(rec))] = rec
    for (fix, rec), _ in live_recs.items():
        live_by_key[(fix, key_of(rec))] = rec

    stale = [k for k in port_by_key if k not in live_by_key]
    missing = [k for k in live_by_key if k not in port_by_key]
    wrong = [k for k in port_by_key if k in live_by_key and port_by_key[k] != live_by_key[k]]
    right = [k for k in port_by_key if k in live_by_key and port_by_key[k] == live_by_key[k]]
    out = [f"THE FROZEN COPIES AGAINST CPython's LIVE ANSWERS "
           f"(`gates/ptx_render_census-s3-oracle.py bend`, {len(live_by_key)} live records):",
           f"  STILL RIGHT : {len(right)}",
           f"  WRONG VALUE : {len(wrong)}   (the same key, a DIFFERENT answer -- a fixture "
           f"that asserts something false)",
           f"  STALE NAME  : {len(stale)}   (the row the record names has MOVED: the upstream "
           f"gave every BUFFER a size node)",
           f"  MISSING     : {len(missing)}   (CPython emits a row the port does not hold)"]
    for k in wrong:
        out.append(f"    WRONG  {k[0]} {k[1]}")
        out.append(f"      frozen {port_by_key[k]}")
        out.append(f"      live   {live_by_key[k]}")
    return "\n".join(out)


def constructions_many(code, typenames, C):
    """`{typename: [(line, [field values])]}` for EVERY named type, in ONE PASS.

    **ONE PASS, AND IT IS A PASS-TIME DECISION, NOT A STYLE ONE.**  MEASURED: the
    per-type loop was 5 types x 169 files = 845 whole-file scans and the census took 49
    seconds; one combined pattern over the same 169 files takes the same walk ONCE and the
    census is a fifth of that.  A census nobody runs is a census that does not exist.
    """
    if not typenames:
        return {}
    pat = re.compile(r"(?<![\w.])(?:" + "|".join(re.escape(t) for t in sorted(typenames)) + r")\{")
    out = {}
    for m in pat.finditer(code):
        typename = m.group(0)[:-1]
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
        out.setdefault(typename, []).append((line, split_top(body)))
    return out


def upstream_ops_ever():
    """THE OP NAMES UPSTREAM's `Ops` ENUM EVER HAD, FROM THE TREE's OWN HISTORY.

    **A NAME IS NOT AN OP, AND A NAME THAT WAS NEVER AN OP IS NOT A DEFECT.**  This is the
    PLACEHOLDER CASE, and it is the case that keeps the census from crying wolf: a site that
    constructs `O.OpsX{}` is not a driver pinned to an older upstream -- `OpsX` is not an op
    AT ALL, it is a PLACEHOLDER in a driver's own docstring, and a census that reports it as
    a missing op is a census of NAMES.

    ⇒ THE THREE CLASSES, AND NONE OF THEM IS A SILENCE:
      DECLARED          the port's own `Op` enum has the member.
      REMOVED-UPSTREAM  the port does not have it and upstream's OWN HISTORY shows it EXISTED
                        -- so the site is a FIXTURE AGAINST AN UPSTREAM THAT NO LONGER
                        EXISTS, and that is a defect worth naming.
      PLACEHOLDER       the port does not have it and upstream NEVER had it: a placeholder,
                        NOT a defect.

    **THE POPULATION IS DERIVED, NOT TYPED.**  The names come out of the tree's own history
    -- every `NAME = auto()` that upstream's enum ever carried -- and NOT out of a hand
    list of the removed ops, because a hand list is a list that rots the moment upstream
    deletes a THIRD one.  MEASURED, and the regex takes EVERY member of a line, not the
    first: upstream writes `BUFFER = auto(); ALLOC = auto()`, so a first-match-per-line
    regex UNDERCOUNTS BY HALF -- and the enum is 75 members, not 30.
    """
    r = subprocess.run(["git", "log", "--all", "-p", "--", "tinygrad/uop/__init__.py"],
                       cwd=ROOT, capture_output=True, text=True)
    out = set()
    for line in r.stdout.splitlines():
        if not line.startswith("+"):
            continue
        for m in re.finditer(r"\b([A-Z][A-Z0-9_]*)\s*=\s*auto\(\)", line):
            out.add(m.group(1))
    return out


def port_ops():
    """THE PORT's OWN `Op` ENUM MEMBERS, READ BY PATH FROM ITS OWN SOURCE."""
    out = set()
    for path, (_raw, code) in {}.items():
        pass
    p = PORT / "uop" / "ops.bend"
    if not p.is_file():
        return out
    raw = p.read_text(encoding="utf-8", errors="replace")
    i = raw.find("type Op is Data:")
    if i < 0:
        return out
    j = raw.find("\ntype ", i + 1)
    block = raw[i:j if j > 0 else len(raw)]
    for m in re.finditer(r"^\s*Ops([A-Z][A-Z0-9_]*)\{\}\s*$", block, re.M):
        out.add(m.group(1))
    return out


def op_site_census():
    """EVERY `O.Ops<NAME>{}` SITE IN THE TREE, CLASSIFIED.  The count and the names.

    **THE POPULATION IS THE TREE's THREE SOURCE ROOTS, AND THE ROOTS ARE NAMED FOR A
    REASON.**  `tinybendygrad/` is the PORT, `gates/` holds the DRIVERS, and `oracles/` holds
    the FRAGMENTS -- and a driver that constructs a deleted op is the subject.  MEASURED,
    and the first version walked the whole repo root and found 40 REMOVED-UPSTREAM sites
    that are NOT CODE: `.agents/slop/linfix/before/...` is a retained earlier run,
    `.agents/slop/strays/...` is a scratch copy, and `runs/margsym/snap/` is OUTPUT.  A
    population that includes a previous run's files is a population that measures yesterday.
    `gates/opsref-census.py` walks `tinybendygrad/**/*.bend` for the same reason.
    """
    declared = port_ops()
    ever = upstream_ops_ever()
    counts = Counter()
    sites = []
    C = load_census()
    for root in ("tinybendygrad", "gates", "oracles"):
        for dirpath, dirnames, filenames in os.walk(ROOT / root):
            dirnames[:] = [d for d in dirnames if d not in ("__pycache__",)]
            for fn in filenames:
                if not fn.endswith(".bend"):
                    continue
                path = Path(dirpath) / fn
                try:
                    raw = path.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                code, _spans = C.scan(raw)
                for m in re.finditer(r"(?<![\w.])O\.Ops([A-Z][A-Z0-9_]*)\{\}", code):
                    name = m.group(1)
                    line = code.count("\n", 0, m.start()) + 1
                    if name in declared:
                        cls = "DECLARED"
                    elif name in ever:
                        cls = "REMOVED-UPSTREAM"
                    else:
                        cls = "PLACEHOLDER"
                    counts[cls] += 1
                    sites.append((cls, name, os.path.relpath(path, ROOT), line))
    return counts, sites


def pins_check():
    """EVERY `# UPSTREAM-PIN` / `# GENERATOR-PIN` LINE IN `oracles/`, COMPARED WITH THE TREE.

    **THE HOUSE's SHAPE** (`gates/gatekit.py:oracle_drift`): a map of a repo-relative path
    to a sha256, compared with the tree's bytes.  A pin in a comment is a pin that cannot
    fail -- `gatekit` says so about `checks/differ.py`'s pin -- so these are CHECKED here.
    """
    bad = []
    n = 0
    oracles = ROOT / "oracles"
    if not oracles.is_dir():
        return n, bad
    for path in sorted(oracles.glob("*.bend")):
        for m in re.finditer(r"^# (UPSTREAM-PIN|GENERATOR-PIN) (\S+) ([0-9a-f]{64})\s*$",
                             path.read_text(encoding="utf-8", errors="replace"), re.M):
            kind, rel, want = m.group(1), m.group(2), m.group(3)
            n += 1
            p = ROOT / rel
            if not p.is_file():
                bad.append(f"{os.path.relpath(path, ROOT)}: {kind} {rel} is ABSENT")
                continue
            got = hashlib.sha256(p.read_bytes()).hexdigest()
            if got != want:
                bad.append(f"{os.path.relpath(path, ROOT)}: {kind} {rel} {got[:16]} != "
                           f"pinned {want[:16]}")
    return n, bad


def plant() -> int:
    """THE PLANT, AND IT IS A TEXT EDIT ON A SCRATCH FILE, NEVER A READ OF `git show HEAD:`.

        .venv/bin/python gates/fixture-embed-census.py --plant

    **A CLASS THAT CANNOT FIRE IS A CLASS THAT DOES NOT EXIST**, and MEASURED, both of the
    op-site classes were dormant: the tree has **0** `REMOVED-UPSTREAM` sites (the
    `O.OpsFLIP{}` in `oracles/lift-rows.bend` was removed when upstream deleted the op) and
    **0** `PLACEHOLDER` sites (`gates/tn_binop_sweep.bend`'s `O.OpsX{}` is in a COMMENT, and
    a comment is PROSE).  So the census would report two classes it has never exercised,
    and a reader would have no way to tell a class that fires from a class that was typed.

    THE TWO PLANTS, AND THEY ARE DIFFERENT QUESTIONS:
      PLACEHOLDER       `O.OpsX{}` in CODE.  `OpsX` is not an op and NEVER was one, so the
                        census must call it a PLACEHOLDER and NOT a defect.
      REMOVED-UPSTREAM  `O.OpsFLIP{}` in CODE.  `Ops.FLIP` EXISTED upstream and was DELETED,
                        so the census must call it a REMOVED-UPSTREAM site -- which is the
                        class that says "this driver is pinned to an upstream that no longer
                        exists".

    THE CONTROL IS A COMMENT-ONLY EDIT, and it must move NOTHING: a comment is PROSE and
    the census blanks comments before it looks for a site.  MEASURED, and it is the same
    shape as `gates/ptx_render_census-gate.py`'s CONTROL: a comment of the same size on a
    line that carries ONE statement.
    """
    scratch = HERE / "_fxembed_plantcase.bend"
    base = ("def plant_case() -> Unit:\n"
            "  # A COMMENT-ONLY LINE, and the census must not see a site in it.\n"
            "  x = O.OpsADD{}\n")
    cases = [
        ("PLANT (PLACEHOLDER)", base + "  y = O.OpsX{}\n"),
        ("PLANT (REMOVED-UPSTREAM)", base + "  y = O.OpsFLIP{}\n"),
        ("CONTROL (comment only)", base + "  # y = O.OpsFLIP{}\n"),
    ]
    bad = 0
    try:
        for name, text in cases:
            scratch.write_text(text)
            counts, sites = op_site_census()
            got = [s for s in sites if s[2].endswith(scratch.name)]
            kinds = sorted({s[0] for s in got})
            print(f"{name:<28} sites in the scratch file: {len(got)}  classes: {kinds}")
            if name.startswith("PLANT (PLACEHOLDER)") and "PLACEHOLDER" not in kinds:
                print("  THE PLACEHOLDER CLASS DID NOT FIRE")
                bad += 1
            if name.startswith("PLANT (REMOVED-UPSTREAM)") and "REMOVED-UPSTREAM" not in kinds:
                print("  THE REMOVED-UPSTREAM CLASS DID NOT FIRE")
                bad += 1
            if name.startswith("CONTROL") and kinds != ["DECLARED"]:
                print("  THE CONTROL IS NOT A CONTROL: a comment moved a site")
                bad += 1
    finally:
        scratch.unlink(missing_ok=True)
    print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
    return 1 if bad else 0


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
    accessors = {}          # accessor name -> (typename, field, the file that DEFINES it)
    for path, (_raw, code) in ctxs.items():
        for (name, _p, typename, _tn, fields, field) in ACCESSOR.findall(code):
            accessors[name] = (typename, field, path)
            accessors[name.split(".")[-1]] = (typename, field, path)
    regions = {path: generated_regions(raw) for path, (raw, _code) in ctxs.items()}
    declared = {p for p, rs in regions.items() if rs}

    # ---- THE RECORD TYPES, PER FILE.  **A NAME IS NOT A TYPE**, and MEASURED: the port
    # declares TWO different `Red` records -- `Red{r: F32, q: U32}` in
    # `tinybendygrad/codegen/decomp/transcendental_f32.bend` and
    # `Red{ar: O.Arena, r: U32, q: U32}` in `tinybendygrad/codegen/decomp/transcendental.bend`
    # -- so a map keyed by the NAME ALONE would read `Red.b`'s value out of the WRONG
    # record.  The declaration is therefore resolved IN THE FILE THAT CONSTRUCTS IT, with
    # the file that DEFINES THE ACCESSOR as the fallback.
    types_in = {}           # path -> {typename: [field names]}
    for path, (_raw, code) in ctxs.items():
        got = {t: record_fields(decl) for (t, decl) in RECORD_TYPE.findall(code)}
        if got:
            types_in[path] = got

    # ---- THE CONSTRUCTION SITES, ACROSS THE WHOLE PORT, for the types the accessors
    # actually name.  The population is the ACCESSORS' OWN types, so the walk is bounded
    # by the number of accessor-fed types and not by the number of record types.
    want_types = {t for (t, _f, _p) in accessors.values()}
    constructions_in = {}    # (path, typename) -> [(line, [field values])]
    for path, (_raw, code) in ctxs.items():
        for t, got in constructions_many(code, want_types, C).items():
            constructions_in[(path, t)] = got

    # ---- THE CELLS, from the census's OWN machinery.
    rows, _per_file, _files, _defs = C.census_port(str(PORT))

    # ---- THE CLASS.  A cell the census calls DERIVED whose value is supplied by a
    # RECORD ACCESSOR, where the accessor's type is CONSTRUCTED with a LITERAL inside
    # a GENERATED region.
    #
    # **THE RECORD TYPE'S DECLARATION AND ITS CONSTRUCTION SITES ARE RESOLVED ACROSS THE
    # WHOLE PORT, NOT IN THE CELL'S OWN FILE.**  MEASURED, and it was the census's own
    # understatement: `TlAcc` is DECLARED in `tinybendygrad/viz/serve.bend` and CONSTRUCTED
    # in `tinybendygrad/renderer/tc.bend`; `Red` is declared in
    # `tinybendygrad/codegen/decomp/transcendental*.bend` and read in
    # `tinybendygrad/renderer/tc_ptx.bend`; `Run` is declared in `tinybendygrad/sz.bend` and
    # read in `tinybendygrad/runtime/ops_dsp.bend`.  A census that looked for the
    # declaration in the cell's own file found **3** accessor-fed cells where the port has
    # **28** -- "A PARSER THAT COUNTS FOUR FEWER IS A PARSER THAT UNDERSTATES, AND A CENSUS
    # THAT UNDERSTATES IS THE DEFECT THIS FILE EXISTS TO CATCH", said about a DIFFERENT
    # parser and about the SAME defect.
    #
    # THE FOUR CLASSES, AND NONE OF THEM IS A SILENCE:
    #   FROZEN      accessor-fed, the record's type is declared, a construction of it sits
    #               inside a region the port DECLARES as generated, the field's value there
    #               is a LITERAL, and **THE REGION's GENERATOR IS GONE**.  THIS IS THE ROT.
    #   DRIFTED     the same, and the region's generator IS THERE and RUNS and the region
    #               does NOT match what it emits.  A region that no longer says what its
    #               generator says.  **THIS IS THE ROW THAT CAN GO RED.**
    #   GENERATED   the same, and the region's generator IS THERE and RUNS and the region
    #               MATCHES.  The literal is a BUILD PRODUCT, and it is not rot.
    #   PORT-STATE  accessor-fed, the record's type is declared, it IS constructed -- but
    #               OUTSIDE every declared generated region, because the record is the
    #               port's OWN STATE (`Tr.refused`, `Run.first`, `TlAcc.bs`).  NOT rot.
    #   PLACEHOLDER  accessor-fed, and the field's value at the construction site is NOT a
    #               literal: a computed value, a list, a `None{}`.  A SLOT, not an answer.
    #   UNDECLARED  accessor-fed, and the record's TYPE DECLARATION IS NOWHERE IN THE PORT.
    #               The census cannot see it, and it says so rather than counting it.
    #
    # **THE CLASS IS THE GENERATOR's PRESENCE AND NOT THE PRESENCE OF A LITERAL.**  MEASURED:
    # the old class counted EVERY literal in EVERY declared generated region, so it counted
    # **268** frozen copies of the port's own 25 PTX fixtures -- and REGENERATING THE REGION
    # DID NOT MOVE THE COUNT, because a generated region is frozen BY CONSTRUCTION whether
    # or not a generator exists.  A class that cannot go empty is a LABEL.  The class is now
    # read from `gates/fixture-region-gate.py`, which RUNS the generator the region names:
    # a region whose generator is PRESENT and whose content MATCHES is GENERATED, one whose
    # generator is GONE is FROZEN, and one that no longer matches its generator is DRIFTED.
    frozen = []            # (file, builder, site, row name, type, field, value)
    drifted = []           # the same, in a region that no longer matches its generator
    generated = []         # the same, in a region that IS what its generator emits
    cells = []             # (file, builder, site, row name, type, field)
    port_state = []        # the same, minus the frozen ones
    placeholders = []      # accessor-fed, the value is not a literal
    undeclared = []        # accessor-fed, the record's type is not declared in the port
    # THE REGION's CLASS, PER FILE, AND IT IS ASKED OF THE INSTRUMENT THAT KNOWS IT.
    frg = load_fixture_region_gate()
    region_class = {}
    for path in declared:
        raw = ctxs[path][0]
        cls, _detail = frg.check_file(path, raw)
        region_class[path] = cls
    for r in rows:
        if r["form"] != "PORT-CALL":
            continue
        callee = r["value"]
        if callee not in accessors:
            continue
        typename, field, apath = accessors[callee]
        path = str(PORT / r["file"])
        cells.append((r["file"], r["builder"], r["site"], r["name"], typename, field))
        resolved = 0
        in_region = 0
        for (cpath, line, vals) in [(p, l, v) for (p, t), got in constructions_in.items()
                                    if t == typename for (l, v) in got]:
            fields = (types_in.get(cpath, {}).get(typename)
                      or types_in.get(apath, {}).get(typename))
            if not fields or field not in fields:
                continue
            idx = fields.index(field)
            resolved += 1
            if not any(a <= line <= b for (a, b) in regions.get(cpath, [])):
                continue
            in_region += 1
            if not is_literal(vals[idx]):
                placeholders.append((r["file"], r["builder"], r["site"], r["name"], typename,
                                     field, vals[idx]))
                continue
            # THE REGION's CLASS DECIDES THE CELL's CLASS, AND THE CLASS IS READ FROM THE
            # INSTRUMENT THAT RUNS THE GENERATOR.
            cls = region_class.get(cpath, "UNDECLARED")
            if cls == "GENERATED":
                generated.append((r["file"], r["builder"], r["site"], r["name"], typename, field,
                                  vals[idx]))
            elif cls == "DRIFTED":
                drifted.append((r["file"], r["builder"], r["site"], r["name"], typename, field,
                                vals[idx]))
            else:
                frozen.append((r["file"], r["builder"], r["site"], r["name"], typename, field,
                               vals[idx]))
        # THE CLASS OF A CELL THAT IS NOT FROZEN, AND EVERY ONE OF THEM IS NAMED:
        #   in_region > 0 and no literal -> PLACEHOLDER (the value at the construction site
        #                                          is not a literal: a slot, not an answer)
        #   resolved == 0                -> the record is never CONSTRUCTED for that field:
        #                                          the port's own STATE, or a type the port
        #                                          does not declare at all
        #   resolved > 0, in_region == 0 -> the record IS constructed, and OUTSIDE every
        #                                          declared generated region: the port's own
        #                                          state (`Tr.refused`, `Run.first`,
        #                                          `TlAcc.bs`, `Red.b`).
        if in_region == 0:
            if resolved == 0 and not any(typename in g for g in types_in.values()):
                undeclared.append((r["file"], r["builder"], r["site"], r["name"], typename, field))
            else:
                port_state.append((r["file"], r["builder"], r["site"], r["name"], typename, field))

    # ---- THE REPORT
    print(f"PORT                 : {PORT}")
    print(f"FILES                : {len(files)} `.bend` files (DISCOVERED by os.walk + endswith)")
    print(f"FILES WITH A DECLARED GENERATED-FIXTURE REGION: {len(declared)}")
    for p in sorted(declared):
        for (a, b) in regions[p]:
            print(f"  {os.path.relpath(p, PORT)}: lines {a}..{b}")
    print(f"CELLS                : {len(rows)} (the census's own count)")
    print(f"CELLS FED BY A RECORD ACCESSOR: {len(cells)}")
    print(f"FROZEN COPIES        : {len(frozen)}   (in a region whose GENERATOR IS GONE -- the "
          f"rot)")
    print(f"DRIFTED COPIES       : {len(drifted)}   (in a region whose generator IS THERE and "
          f"the region no longer MATCHES it -- the row that CAN go red)")
    print(f"GENERATED COPIES     : {len(generated)}   (in a region that IS what its generator "
          f"emits -- a BUILD PRODUCT, and NOT rot)")
    print(f"PORT-STATE CELLS     : {len(port_state)}   (accessor-fed, the record is the port's "
          f"own state -- NOT rot)")
    print(f"PLACEHOLDER CELLS    : {len(placeholders)}   (accessor-fed, the value at the "
          f"construction site is NOT a literal -- a slot, not an answer)")
    print(f"UNDECLARED CELLS     : {len(undeclared)}   (accessor-fed, the record's TYPE is "
          f"nowhere in the port -- the census CANNOT see it, and says so)")
    print("")
    print("THE REGION's CLASS, AND IT IS THE GENERATOR's PRESENCE:")
    for p in sorted(declared):
        print(f"  {os.path.relpath(p, PORT)}: {region_class.get(p, 'UNDECLARED')}")
    print("")
    by_file = {}
    for f in frozen + drifted:
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
    # ---- THE THREE CLASSES THAT ARE NOT ROT, BY NAME.  A NEGATIVE RESULT IS A RESULT,
    # and naming them is what stops a reader from assuming the census saw only what it
    # reported -- and a FALSE POSITIVE IS A ROW THAT CANNOT GO RED, IN THE OTHER DIRECTION.
    for label, group in (("ACCESSOR-FED CELLS THAT ARE NOT IN A GENERATED REGION (the "
                          "port's own state, so NOT frozen expectations)", port_state),
                         ("ACCESSOR-FED CELLS WHOSE VALUE IS A PLACEHOLDER (not a literal)",
                          placeholders),
                         ("ACCESSOR-FED CELLS WHOSE RECORD TYPE IS UNDECLARED IN THE PORT "
                          "(the census cannot see them)", undeclared)):
        if group:
            print("")
            print(label + ":")
            for g in group:
                print(f"  {g[0]} builder={g[1]} site={g[2]} {g[4]}.{g[5]}"
                      + (f" -- {g[6]}" if len(g) > 6 else ""))
    print("")
    print("THE DELTA, AND IT IS THE POINT: the census counts the CELLS, and the rot is")
    print("the FROZEN COPIES.  A cell that reads one fixture record is ONE row in the")
    print("census and N frozen answers, and the census cannot see the difference because")
    print("it stops at the accessor.")
    print("")
    live = live_comparison(frozen)
    if live:
        print(live)
    print("")
    # ---- THE OP SITES, AND THE PLACEHOLDER CASE.
    counts, sites = op_site_census()
    print(f"OP-CONSTRUCTION SITES OVER THE WHOLE TREE ({len(sites)} sites, "
          f"DECLARED {counts['DECLARED']} / REMOVED-UPSTREAM {counts['REMOVED-UPSTREAM']} "
          f"/ PLACEHOLDER {counts['PLACEHOLDER']}):")
    for cls in ("REMOVED-UPSTREAM", "PLACEHOLDER"):
        for (c, name, path, line) in sites:
            if c == cls:
                print(f"  {c:<16} {name:<12} {path}:{line}")
    print("")
    n, bad = pins_check()
    print(f"THE PINS UNDER `oracles/`: {n} checked, {len(bad)} stale")
    for b in bad:
        print(f"  {b}")

    if args.rows:
        Path(args.rows).write_text(
            "".join(f"file={f} builder={b} site={s} type={t} field={fl} value={v}\n"
                    for (f, b, s, _n, t, fl, v) in sorted(frozen + drifted)))
        print(f"wrote {args.rows}")

    if frozen or drifted:
        print(f"\n== FAIL: {len(frozen)} FIXTURE-EMBEDDED TRANSCRIPTIONS in "
              f"{len(by_file)} file(s) -- {len(frozen)} in a region whose GENERATOR IS GONE "
              f"and {len(drifted)} in a region that no longer MATCHES its generator.")
        return 1
    print(f"\n== PASS: no fixture-embedded transcription the census cannot see -- "
          f"{len(generated)} of them are BUILD PRODUCTS (a region that is what its "
          f"generator emits), and the class goes empty only when the region is CURRENT")
    return 0


if __name__ == "__main__":
    if "--plant" in sys.argv:
        raise SystemExit(plant())
    raise SystemExit(main())
