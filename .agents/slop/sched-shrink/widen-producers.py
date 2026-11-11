#!/usr/bin/env python3
"""widen-producers.py -- THE PROVEN PRODUCERS TOOL, WITH **A WIDER PRODUCER
CLASSIFIER**.

    .venv/bin/python .agents/slop/sched-shrink/widen-producers.py --apply <file.bend> [...]

**WHY A SECOND FILE AND NOT A REWRITE.** IT **LOADS THE PROVEN TOOL **BY PATH**
(`extract-gate-rows-producers.py`, WHICH ITSELF LOADS `extract-gate-rows.py` BY
PATH), **SO THE QUALIFICATION, THE REBASE, THE ORDERING, THE EXTERNAL-USER RULE
AND THE COMPILE CHECKS ARE **THE PROVEN** ONES AND NOT A REWRITE OF THEM.**
**ONLY THE PRODUCER CLASSIFIER IS REPLACED.**

**WHAT THE PROVEN CLASSIFIER SEES AND WHAT THIS ONE SEES.** THE PROVEN ONE
ANSWERS "IS THIS DEF A PRODUCER" BY "DOES ITS BODY CALL `row`/`srow`/`urow`".
**MEASURED 2026-11-10 ON `tinybendygrad/schedule/indexing.bend`: **NINE**
PRODUCERS ARE CALLED BY **EIGHT** DEFS THAT THE PROVEN CLASSIFIER DOES **NOT**
COUNT AS PRODUCERS** -- **AND EVERY ONE OF THE EIGHT IS A **WRAPPER** THAT
PRINTS THROUGH A PRODUCER IT CALLS** (`g_expand` PRINTS THROUGH
`ix_mv_expand_row`, `g_ss` THROUGH `ix_ss_h_row` AND `ix_ss_top_row`, ...).

**AND THE PROVEN TOOL **REFUSED** THE FILE BECAUSE OF IT** -- `REFUSED:
producers called by the implementation` -- **AND THE REFUSAL WAS **TRUE OF THE
TOOL's POPULATION** AND **FALSE OF THE FILE**: **THE IMPLEMENTATION NEVER
CALLS THOSE PRODUCERS**; **THE WRAPPERS DO**, **AND THE WRAPPERS ARE **ONLY**
CALLED BY `main`.**

**AND THE WIDENED CLASSIFIER IS **THE SAME RULE**, **INVERTED**: A DEF IS
ROW-SIDE IFF **EVERY DEF THAT CALLS IT IS ROW-SIDE OR `main`** -- **AND THE
ROW-SIDE SET IS THE **FIXPOINT** THAT BEGINS AT THE PRODUCERS.** **AND A
PRODUCER IS A DEF THAT PRINTS**: ITS BODY CALLS A DEF WHOSE NAME IS **ONE OF**
THE PRINTING NAMES** (`row`, `rowu`, `rowi`, `rowb`, `srow`, `urow`).

**AND THE PRINTING NAMES ARE **DISCOVERED**, NOT GUESSED**: A NAME IS A
PRINTING NAME IFF **SOME DEF IN THE FILE **DEFINES** IT** **AND **ITS BODY
CALLS `IO.print`** -- **SO `rowu` AND `rowi` AND `rowb` ARE FOUND BECAUSE THEY
PRINT, AND **A NAME THAT **DOES NOT PRINT** IS **NOT** IN THE SET.**

**AND THE **SAFETY PROPERTY** IS **CHECKED**, NOT ASSUMED: **AFTER THE
FIXPOINT, NO DEF **OUTSIDE** THE ROW-SIDE SET MAY CALL A DEF **INSIDE** IT** --
**AND THAT IS **THE MOVE'S OWN FAILURE MODE** (THE PORT WOULD CALL A DEF THAT
LEFT), **SO THE TOOL **REFUSES** WHEN IT HOLDS.**
"""

import argparse
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location(
    "xgrp", ROOT / ".agents/slop/loc/extract-gate-rows-producers.py")
xgrp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(xgrp)

DEF = re.compile(r"^def ([A-Za-z_][A-Za-z0-9_.]*)\(")
PRINT_CALL = re.compile(r"(?<![\w.])IO\.print\s*\(")
# **AND THE MARKER **IS **THE PORT's OWN SPELLING** -- **AND IT IS **THE
# **SAME** SPELLING `checks/marker-audit.py` READS** (`MARKER_FORMS =
# ('TODO(p3)', 'WALL(p3)')`) -- **AND **A SECOND LIST** WOULD BE **A SECOND
# COPY** **AND THAT IS **THE CLASS** -- **SO THE PATTERN IS **THE **SAME
# SHAPE** THE INSTRUMENT USES, **AND THE INSTRUMENT IS **THE ONE THAT COUNTS
# THEM.**
# **AND THE MARKER **IS **ANCHORED** -- **AND THAT IS **THE INSTRUMENT's
# OWN PATTERN** (`checks/marker-audit.py`: `MARKER =
# re.compile(r'^\s*#\s*(?:TODO\(p3\)|WALL\(p3\))')`) -- **AND AN **UNANCHORED**
# PATTERN **MATCHES **THE PROSE** THAT **NAMES** THE MARKER** (`# this header
# used to say `# TODO(p3)` ...`) **AND THAT IS **A FALSE POSITIVE** **AND IT
# **WOULD HAVE **KEPT **THE WHOLE PORT** -- **MEASURED 2026-11-10 ON
# `schedule/multi.bend`: `main`'s BLOCK CARRIES **THE FILE's OWN HEADER**,
# **AND THE HEADER **NAMES** THE MARKER **IN PROSE**, **AND THE UNANCHORED
# PATTERN MATCHED IT** -- **AND THE TOOL REFUSED THE FILE**."""
MARKER = re.compile(r"^\s*#\s*(?:TODO|WALL)\(p3\)")
# **AND THE **CITED NAME** IS **THE INSTRUMENT's OWN FORM** -- **AND
# `symbol=<name>` IS **THE DURABLE FORM** (`gates/bendcite-gate.py`: *"THE
# DURABLE FORM IS `symbol=<name>`"*) -- **AND **THE BACKTICKED **NAME** IS
# **THE **SECOND** FORM** -- **AND **BOTH **ARE **READ**."""
SYMBOL = re.compile(r"symbol=([A-Za-z_][A-Za-z0-9_.]*)")
BACKTICK = re.compile(r"`([A-Za-z_][A-Za-z0-9_.]*)`")


def printing_names(code: list[str], blocks: dict[str, tuple[int, int]]) -> set[str]:
    """**THE NAMES THAT PRINT** -- **DISCOVERED** BY READING THE BODIES.**

    **AND A NAME IS A PRINTING NAME IFF **ITS BODY CALLS `IO.print`** -- **SO
    `row` PRINTS AND `rowu` PRINTS AND `eq` DOES NOT**, **AND THE SET IS
    FOUND, NOT NAMED.**
    """
    out: set[str] = set()
    for name, (i, e) in blocks.items():
        if PRINT_CALL.search("\n".join(code[i:e])):
            out.add(name)
    return out


def analyse(path: Path) -> dict:
    """**THE PROVEN TOOL's ANALYSIS, WITH **THE WIDER PRODUCER SET**."""
    lines = path.read_text().splitlines()
    code = xgrp.strip_comments(lines)
    blocks = xgrp.def_blocks(code)
    byname = {n: (i, e) for n, i, e in blocks}
    prints = printing_names(code, byname)
    # **AND `main` IS **THE ENTRY POINT**, NOT A PRIMITIVE -- **AND IT
    # PRINTS ITS OWN SUMMARY ROW**, **SO IT IS IN `prints`** -- **AND THAT
    # MATTERS: **IF `main` WERE TREATED AS A PRIMITIVE, **EVERY DIRECT CALLEE
    # OF `main` WOULD SATISFY THE ROW-SIDE FIXPOINT** (THEIR CALLERS ARE ALL
    # `main`), **AND THE **IMPLEMENTATION** WOULD MOVE.**
    #
    # **MEASURED 2026-11-10 ON `schedule/allreduce.bend`: `red_row` IS THE
    # ONLY PRIMITIVE, `main` CALLS IT DIRECTLY, **AND THE FIXPOINT WITH
    # `main` IN `prints` PUT **114** DEFS ON THE ROW SIDE** -- **AND THE
    # PORT WOULD HAVE KEPT **110** LINES OF A **663**-LINE FILE.**
    #
    # **SO THE PRIMITIVES ARE **THE PRINTERS **MINUS** `main`**, **AND
    # `main` IS **A PRODUCER** WHEN IT CALLS ONE.**
    prims = prints - {"main"}
    prods: set[str] = set()
    for name, (i, e) in byname.items():
        if name in prims:
            continue
        body = "\n".join(code[i:e])
        if any(re.search(r"(?<![\w.])" + re.escape(p) + r"\s*\(", body) for p in prims):
            prods.add(name)
    # **AND **A PRINTER'S **OWN WRAPPER** IS **A PRODUCER** -- **AND THAT IS
    # **THE `rowu`/`rowi` SHAPE**.
    #
    # **MEASURED 2026-11-10 ON `tinybendygrad/schedule/indexing.bend`:
    # `rowu` PRINTS **THROUGH `row`** (IT IS `row(nm, U32.show(v))`) **AND
    # `rowi` PRINTS **THROUGH `rowu`** -- **AND SO **NEITHER** CALLS
    # `IO.print`**, **AND SO **THE PRINTER SET (WHICH IS **DISCOVERED** BY
    # `IO.print` IN THE BODY) **HELD **ONLY** `row`** -- **AND THE
    # REFUSAL NAMED `rowi` AND `rowu` AS **IMPLEMENTATION DEFS** **CALLING
    # **THE ROW SECTION** -- **AND THAT WAS **TRUE** OF THE TOOL's POPULATION
    # **AND **FALSE** OF THE FILE.**
    #
    # **SO THE PRODUCER SET IS **THE PRINTERS **AND **THEIR WRAPPERS** --
    # **AND A WRAPPER IS **A DEF THAT **CALLS **A PRINTER** (DIRECTLY **OR
    # **THROUGH **A **CHAIN**) **AND **THAT IS **A **FIXPOINT** OVER **THE
    # **CALLER-SIDE** EDGE.**
    #
    # **AND THE FIXPOINT IS **BOUNDED BY **THE PRINTERS' OWN SET** -- **IT
    # GROWS **ONLY** **THE PRINTERS' WRAPPERS**, **AND IT NEVER TOUCHES **THE
    # PORT's OWN LAYER** -- **AND THAT IS **WHY `multi.bend`'s **639** DEF
    # CASCADE DID NOT HAPPEN HERE.**"""
    prods |= {n for n in prims}
    changed = True
    while changed:
        changed = False
        for name, (i, e) in byname.items():
            if name in prods:
                continue
            body = "\n".join(code[i:e])
            if any(re.search(r"(?<![\w.])" + re.escape(p) + r"\s*\(", body) for p in prods):
                prods.add(name)
                changed = True
    # **AND `main` IS **A PRODUCER** WHEN IT CALLS **A PRINTER** -- **AND IT
    # IS **THE ROW-SIDE ROOT** -- **AND IT IS **NOT** A PRIMITIVE**."""
    if any(re.search(r"(?<![\w.])" + re.escape(p) + r"\s*\(", "\n".join(code[byname["main"][0]:byname["main"][1]]))
           for p in prims):
        prods.add("main")
    # **AND THE **PRINTERS' **OWN WRAPPERS** ARE **A SEPARATE SET** -- **AND
    # THEY ARE **THE **ROW-SECTION** DEFS THAT **CALL **A PRINTER** -- **AND
    # THE FIXPOINT's BOUND ("A DEF THAT CALLS **NO** PRINTER NEVER JOINS")
    # MUST USE **THIS** SET, **NOT **THE **WHOLE** PRODUCER SET** -- **OR
    # **EVERY** DEF WOULD JOIN, **BECAUSE **THE PRODUCER SET NOW **CONTAINS
    # **THE PRINTERS** THEMSELVES**."""
    printers = set(prims)
    changed = True
    while changed:
        changed = False
        for name, (i, e) in byname.items():
            if name in printers or name == "main":
                continue
            body = "\n".join(code[i:e])
            if any(re.search(r"(?<![\w.])" + re.escape(p) + r"\s*\(", body) for p in printers):
                printers.add(name)
                changed = True
    # **AND `main` IS **THE ROW-SIDE ROOT** -- **AND IT IS NOT PART OF THE
    # FIXPOINT's STARTING SET**, **AND THE FIXPOINT's ALLOWANCE FOR `main`
    # IS **THE CALLERS SIDE**: A DEF WHOSE **CALLERS** ARE ALL ROW-SIDE **OR
    # `main`** IS ROW-SIDE -- **AND THAT IS HOW A DEF CALLED **ONLY** BY
    # `main` BECOMES ROW-SIDE.**
    #
    # **AND WITH `main` AS A PRODUCER, **THE FIXPOINT IS CORRECT** -- **AND
    # THE **SAFETY PROPERTY** BELOW IS WHAT PROVES IT.**
    calls: dict[str, set[str]] = {}
    for n, i, e in blocks:
        body = "\n".join(code[i:e])
        calls[n] = {m for m in byname if m != n
                    and re.search(r"(?<![\w.])" + re.escape(m) + r"\s*\(", body)}
    callers_of: dict[str, set[str]] = {n: set() for n in calls}
    for n, called in calls.items():
        for m in called:
            callers_of[m].add(n)
    # **AND THE **CROSS-FILE** CONSTRAINT IS **COMPUTED **BEFORE** THE
    # FIXPOINT, **NOT AFTER IT** -- **AND THAT IS **THE ORDER** THAT MATTERS.**
    #
    # **MEASURED 2026-11-10 ON `tinybendygrad/schedule/indexing.bend`:
    # `ix_mv_permute` IS **AN IMPLEMENTATION DEF** (IT IS `indexing.py`'s OWN
    # WALK) **AND `tinybendygrad/schedule/rangify.bend` CALLS IT** -- **AND
    # THE FIXPOINT PUT IT ON THE ROW SIDE** (BECAUSE **ONLY** THE ROWS CALL
    # IT), **AND THE MOVE TOOK IT OUT OF THE PORT**, **AND THE DRIVER FOR
    # `rangify.bend` SAID "expected : a defined name / observed :
    # IX.ix_mv_permute".**
    #
    # **AND **A DEF **ANOTHER FILE** REACHES **IS **THE PORT's API**, NOT
    # **THE GATE's FIXTURE** -- **SO IT STAYS IN THE PORT** -- **AND THE
    # CROSS-FILE RULE IS **A CONSTRAINT ON THE FIXPOINT**, **NOT A CHECK ON
    # ITS RESULT.**
    ext = xgrp.external_users(path, set(calls), {
        m.group(2): m.group(1)
        for m in (re.match(r"^import (\S+) as (\w+)$", l) for l in lines) if m})
    # **AND THE ROW SECTION IS **THE PRODUCERS **PLUS** THE **WRAPPERS** --
    # **AND A WRAPPER IS **A DEF THAT CALLS A PRODUCER** **AND **WHOSE CALLERS
    # ARE **ALL** ROW-SIDE** -- **AND THE FIXPOINT IS **THE **CALLER-SIDE**
    # ONE, **NOT **THE **CALLEE-SIDE** ONE** -- **AND THAT IS **THE
    # DIFFERENCE BETWEEN **THE PORT** AND **THE GATE**.**
    #
    # **MEASURED 2026-11-10 ON `schedule/multi.bend`: **THE **CALLEE-SIDE**
    # FIXPOINT PUT **639** DEFS ON THE ROW SIDE -- **INCLUDING `mu_own`,
    # `mu_table`, `mu_count`, `mu_axes`** -- **AND THOSE ARE **THE PORT's OWN
    # DECISION LAYER**, **AND MOVING THEM TO `gates/` LEAVES A **402-LINE**
    # FILE THAT IS **NO LONGER **THE PORT** -- **AND THE TREE's OWN CONVENTION
    # (`gates/README.md:173`) SAYS **THE PORT FILE CARRIES THE PORT **AND THE
    # GATE FILE CARRIES THE INSTRUMENT** -- **AND A GATE FILE CARRYING THE
    # PORT IS **THE CONVENTION INVERTED**.**
    #
    # **AND THE **CALLER-SIDE** FIXPOINT ON `schedule/multi.bend` PUTS **NO**
    # DEF ON THE ROW SIDE **BESIDES `main`** -- **AND THAT IS **RIGHT**:
    # **`main` IS THE ONLY CALLER OF `row`**, **AND EVERY `t_*` DEF IS CALLED
    # BY `main` **AND IS **A **ROW** ITSELF** -- **SO THEY MOVE BY **THE
    # PROVEN TOOL's OWN BOUND** (THE IMPLEMENTATION CALLS THEM AT MOST ONCE),
    # **NOT** BY THE FIXPOINT.**
    #
    # **AND **THE CALLER-SIDE FIXPOINT IS **THE PROVEN TOOL's OWN REFUSAL
    # READ BACKWARDS** -- **AND IT IS **BOUNDED** BY ITS OWN ALLOWED SET:
    # **A DEF JOINS ONLY IF **EVERY** DEF THAT CALLS IT IS **ALREADY** ON THE
    # ROW SIDE** -- **AND A DEF THAT **CALLS **NO PRODUCER** NEVER JOINS**,
    # **AND THAT IS **THE BOUND** THAT KEEPS **THE PORT's OWN LAYER** IN **THE
    # PORT**."""
    rowside = set(prods) | {"main"}
    changed = True
    while changed:
        changed = False
        for n in calls:
            if n in rowside:
                continue
            # **AND **A DEF **ANOTHER FILE** CALLS **NEVER** JOINS** --
            # **AND THAT IS **THE PORT's API** AND NOT **THE GATE's**."""
            if n in ext:
                continue
            # **AND **A DEF THAT **CALLS **NO PRINTER** NEVER JOINS** --
            # **AND THAT IS **THE BOUND**."""
            if not (calls[n] & printers):
                continue
            cs = callers_of[n]
            if cs and cs <= rowside:
                rowside.add(n)
                changed = True
    # **AND `main` **STAYS** IN THE **CLOSURE's SEED** -- **AND THAT IS
    # **THE PROVEN TOOL's OWN SHAPE** (`moved = set(section)` **AND `main` IS
    # **A **PRODUCER**) -- **AND IT IS **WHAT MAKES **THE `t_*` DEFS MOVE**:
    # **`t_own_n` IS CALLED BY `main` **AND BY NOTHING ELSE**, **AND
    # `callers_of[t_own_n] & moved` IS **{main}`** -- **AND WITHOUT `main` IN
    # THE SEED **THE CLOSURE IS EMPTY** -- **MEASURED 2026-11-10 ON
    # `schedule/multi.bend`: **0** HELPERS INSTEAD OF **322**.**
    #
    # **AND `main` IS **NOT** IN **THE MOVE SET** -- **AND THAT IS **A
    # SEPARATE MATTER** -- **AND THE PROVEN TOOL's `build` **DROPS** THE
    # `main` BLOCK **AND **MOVES** IT **INTO THE DRIVER** ITSELF.**
    #
    # **AND THE **SAFETY PROPERTY**: NO DEF OUTSIDE THE ROW-SIDE SET MAY
    # CALL A DEF INSIDE IT -- **AND THAT IS THE MOVE's OWN FAILURE MODE.**
    # **AND THE CHECK IS **AGAINST **THE **ROW SECTION** (WHICH **INCLUDES**
    # `main`), **NOT** AGAINST **THE MOVE SET** -- **AND A DEF THE MOVE SET
    # **REACHES** BUT **THE ROW SECTION DOES NOT** IS **A **ROW-ONLY HELPER**,
    # **AND IT IS **THE PROVEN TOOL's OWN CLASS.**"""
    outside = set(calls) - rowside
    breach = {n: sorted(calls[n] & rowside) for n in outside if calls[n] & rowside}
    if breach:
        raise SystemExit(f"  REFUSED: {path}: implementation calls row-side: {breach}")
    # **AND THE **ROW-ONLY CLOSURE** IS THE PROVEN TOOL's OWN RULE: A DEF
    # THE ROW SECTION CALLS AND THE IMPLEMENTATION NEVER CALLS MOVES WITH THE
    # ROWS -- **AND THE IMPLEMENTATION TEXT IS **THE CODE** OF THE NON-ROW-SIDE
    # DEFS, **SO A COMMENT CANNOT COUNT.**
    impl_names = set(calls) - rowside
    impl_text = "\n".join("\n".join(code[a:e]) for n, a, e in blocks if n in impl_names)
    impl_call_count: dict[str, int] = {}
    for n in calls:
        impl_call_count[n] = len(re.findall(r"(?<![\w.])" + re.escape(n) + r"\b", impl_text))
    moved = set(rowside)
    changed = True
    while changed:
        changed = False
        for n in calls:
            if n in moved or n == "main":
                continue
            if not (callers_of[n] & moved):
                continue
            if impl_call_count[n] > 1:
                continue
            if n in ext:
                continue
            moved.add(n)
            changed = True
    helpers = sorted(moved - rowside)
    # **AND **THE PORT's OWN **BACKLOG** NEVER MOVES** -- **AND THAT IS
    # **THE `WALL(p3)` / `TODO(p3)` MARKERS** -- **AND IT IS **A CONSTRAINT ON
    # **THE MOVE SET**, **NOT A CHECK ON IT**.
    #
    # **MEASURED 2026-11-10 ON `tinybendygrad/schedule/rangeify.bend`: THE
    # FILE'S FOOT CARRIES **A CONTIGUOUS COMMENT SECTION** -- **"THE WALLS"** --
    # **AND **30** `# WALL(p3)` MARKERS** -- **AND THE TOOL's COMMENT-PULL
    # ATTACHED IT **TO THE DEF THAT FOLLOWS IT**, **AND THE WHOLE SECTION
    # MOVED INTO `gates/rangeify-gate.bend`.**
    #
    # **AND **THAT IS **A LOSS**, AND **THE INSTRUMENT SAYS SO**:
    # `checks/marker-audit.py`'s **OWN DOCSTRING** NAMES THIS FILE'S COUNT --
    # *"MEASURED 2026-11-10: `tinybendygrad/` CARRIES 149 `WALL(p3)`
    # OCCURRENCES IN 17 FILES ... `schedule/rangeify.bend` ALONE HAS 30"** --
    # **AND THE CENSUS FELL FROM **621** TO **599** WALLS** -- **AND A
    # POPULATION THAT MOVES IS **A POPULATION THE INSTRUMENT CANNOT SEE**.**
    #
    # **AND A MARKER **IS **THE PORT's OWN STANDING WORK LIST** -- **AND THE
    # LIST BELONGS TO **THE PORT**, NOT TO **THE INSTRUMENT** -- **AND A GATE
    # DRIVER IS **THE INSTRUMENT**.**
    #
    # **SO A DEF **WHOSE PRECEDING COMMENT CARRIES A MARKER** DOES NOT
    # MOVE** -- **AND THE COMMENT STAYS IN THE PORT** -- **AND THE DEF STAYS
    # TOO**, **BECAUSE A DEF **WITHOUT ITS COMMENT** IS **A DIFFERENT DEF**,
    # **AND THE PORT's OWN COMMENT **IS **THE DEF's PROSE**.**
    marked = set()
    for n, (i, e) in byname.items():
        # **AND THE **WHOLE BLOCK** IS SCANNED, **NOT **ONLY **THE COMMENT
        # ABOVE THE DEF** -- **AND THAT IS **THE PROVEN TOOL's OWN BLOCK
        # SHAPE**: `def_blocks` GIVES A DEF **THE LINES UP TO **THE NEXT
        # DEF**, **AND SO **THE COMMENTS **AFTER** A DEF **AND BEFORE THE NEXT
        # ONE ARE **INSIDE **THE DEF's BLOCK**.
        #
        # **MEASURED 2026-11-10 ON `tinybendygrad/schedule/rangeify.bend`:
        # `t_ranges_miss` IS AT LINE **2651** **AND **THE NEXT DEF IS AT
        # **2805** -- **AND THE **30** `# WALL(p3)` MARKERS ARE AT
        # **2690-2737**, **IN BETWEEN** -- **AND SO THE MARKERS ARE **INSIDE**
        # `t_ranges_miss`'s BLOCK** -- **AND THE **COMMENT-ONLY** SCAN
        # MISSED THEM** -- **AND **25** WALLS MOVED INTO THE DRIVER** --
        # **AND `checks/marker-audit.py`'s CENSUS FELL FROM **613** TO
        # **591**."""
        s = xgrp.block_start(lines, i)
        if any(MARKER.search(lines[k]) for k in range(s, e)):
            marked.add(n)
    if marked & moved:
        # **AND A MARKED DEF **THAT IS **THE ROW SECTION** ITSELF **CANNOT
        # BE UNDONE** -- **AND THAT IS **A REFUSAL**, **NOT A WARNING** --
        # **BECAUSE THE ROWS **MUST** MOVE **AND **THE MARKERS **MUST** STAY,
        # **AND A DEF **CANNOT **BE IN **BOTH** PLACES.**"""
        both = marked & rowside
        if both:
            # **AND `main` IS **THE ONE** DEF THAT **MUST** MOVE **AND
            # **CARRIES A MARKER** -- **AND **THE MARKER IS **THE PORT's OWN
            # BACKLOG** **AT THE FOOT** -- **AND THE FIX IS **THE MARKER's OWN
            # LINES STAY** -- **AND `main`'s BODY MOVES** -- **AND A COMMENT
            # IS **NOT CODE**, **AND A PORT FILE **WITH **THE BACKLOG **AND
            # **NO `main`** IS **A FILE THE DRIVER IMPORTS** -- **AND THE
            # BACKLOG IS **WHERE THE NEXT UNIT LOOKS FOR IT**."""
            if both != {"main"}:
                raise SystemExit(
                    f"  REFUSED: {path}: a marked def is a row producer: {sorted(both)}")
            # **AND THE MARKER LINES **AND **THE ENTRY BESIDE THEM** ARE
            # **REMOVED FROM **THE MOVED TEXT** -- **AND THE ENTRY IS **THE
            # CONTIGUOUS COMMENT BLOCK** -- **AND `checks/marker-audit.py`'s
            # OWN `reason_text(t)` READS **THE MARKER's OWN ENTRY**, **AND A
            # MARKER **WITHOUT **ITS ENTRY** IS **A MARKER THE INSTRUMENT
            # CANNOT CLASSIFY**."""
            keep = set()
            for k, l in enumerate(lines):
                if not MARKER.search(l):
                    continue
                keep.add(k)
                j = k + 1
                while j < len(lines) and lines[j].strip().startswith("#"):
                    keep.add(j)
                    j += 1
            info_protected = keep
        else:
            info_protected = set()
    else:
        info_protected = set()
    moved -= marked
    # **AND **A DEF **ANOTHER FILE **CITES** STAYS IN THE PORT** -- **AND
    # **A CITATION IS **A POINTER TO **A CONSTRUCT** -- **AND **THE POINTER
    # **NAMES **THE CONSTRUCT** -- **AND **IF **THE CONSTRUCT **MOVES OUT OF
    # **THE PORT**, **THE POINTER **NOW NAMES **A FILE **THAT **IS NOT THE
    # **PORT** -- **AND **THE TREE's OWN CONVENTION CITES **PORT FILES**.**
    #
    # **MEASURED 2026-11-10 ON `tinybendygrad/schedule/indexing.bend`: THE
    # TABLES `grm_table`, `par_table` AND `pfd_table` **ARE **THE PORT's OWN
    # DATA** -- **AND `schedule/rangify.bend` CITES **ALL THREE** (`indexing.
    # bend:1274 symbol=grm_table`, `:1303 symbol=par_table`, `:1310 symbol=
    # pfd_table`) -- **AND `uop/ops.bend` CITES `g_nr`** -- **AND THE MOVE
    # TOOK **ALL FOUR** OUT OF THE PORT**, **AND THE POINTERS HAD TO BE
    # RE-POINTED **INTO `gates/`**, **AND **THE DRIVER's OWN LINE NUMBERS
    # **ARE UNSTABLE** (THE DRIVER GROWS **WHEN **THE POINTERS **POINT BACK
    # INTO IT**) -- **AND THE TOOL OSCILLATED** -- **MEASURED: **417** BROKEN
    # POINTERS **ACROSS **THREE** PASSES, **WITH **10** RE-POINTS **EACH**."
    #
    # **AND THE FIX IS **THE OTHER WAY**: **THE CONSTRUCT STAYS**, **AND THE
    # POINTER STAYS** -- **AND A CONSTRUCT **THAT **IS **CITED** IS **NOT **THE
    # INSTRUMENT's** -- **AND **THE INSTRUMENT **IS **THE ROWS**, **AND **THE
    # ROWS **CALL** THE CONSTRUCT **WITHOUT **MOVING IT**."""
    cited = cited_names(path, ROOT)
    if cited & moved:
        moved -= (cited & moved)
    helpers = sorted(moved - rowside)
    # **AND THE **AGGREGATORS** ARE **THE WRAPPERS** -- **AND `main` IS **A
    # PRODUCER** AND NOT AN AGGREGATOR** -- **AND `main` IS **THE DRIVER's**
    # **AND NOT **THE PORT's**."""
    aggs = sorted(n for n in rowside - prods if n != "main")
    return {"lines": lines, "code": code, "prods": prods, "aggs": set(aggs),
            "helpers": helpers, "blocks": blocks, "byname": byname, "calls": calls,
            "ext": ext, "rowside": rowside, "protected": info_protected}


def build(path: Path, info: dict) -> tuple[list[str], list[str]]:
    """**THE PROVEN TOOL's OWN BUILD, UNCHANGED.**

    **AND IT IS **THE PROVEN ONE** AND NOT A REWRITE BECAUSE **IT READS THE
    SAME KEYS** (`prods`, `aggs`, `helpers`, `byname`, `blocks`, `calls`) **AND
    `analyse` **POPULATES EXACTLY THOSE** -- **AND THE PROVEN BUILD's **TYPE
    HANDLING**, **ITS `main` HANDLING**, **ITS **ORDERING** AND **ITS
    **COMMENT-PULL** ARE **THE ONES THAT WERE MEASURED** ON `ops_qcom.bend` AND
    `system.bend`.**
    """
    impl, moved = xgrp.build(path, info)
    # **AND THE **PROTECTED LINES** -- **THE PORT's OWN BACKLOG** -- **STAY
    # IN THE PORT** -- **AND THEY DO NOT GO INTO THE DRIVER** -- **AND THAT IS
    # **THE WHOLE POINT**: **THE BACKLOG BELONGS TO **THE PORT**, **AND A GATE
    # DRIVER IS **THE INSTRUMENT**."
    #
    # **MEASURED 2026-11-10 ON `tinybendygrad/schedule/multi.bend`: THE
    # `# TODO(p3)` MARKER IS AT LINE **3455** -- **INSIDE `main`'s BLOCK**
    # (**3032** TO **3456**) -- **AND `main` **MUST** MOVE** -- **AND THE
    # MARKER'S OWN LINE **AND **THE COMMENT LINES BESIDE IT** ARE **THE
    # PORT's BACKLOG** -- **AND **THE PORT KEEPS THEM**, **AND THE DRIVER
    # DOES NOT CARRY THEM**."
    #
    # **AND THE LINES ARE **PUT BACK** **AT THE PORT's OWN FOOT** -- **AND
    # **THE FOOT IS **WHERE THE NEXT UNIT LOOKS** -- **AND THE MARKER's OWN
    # ENTRY (THE CONTIGUOUS COMMENT BLOCK) GOES WITH IT**, **BECAUSE
    # `checks/marker-audit.py`'s `reason_text(t)` READS **THE MARKER's OWN
    # ENTRY** AND **A MARKER WITHOUT ITS ENTRY IS A MARKER THE INSTRUMENT
    # CANNOT CLASSIFY**."
    protected = info.get("protected") or set()
    if protected:
        lines = info["lines"]
        keep = [lines[k] for k in sorted(protected)]
        # **AND THE PROTECTED LINES ARE **NOT **IN THE PORT** ANY MORE** --
        # **THE PROVEN BUILD DROPPED **THE WHOLE `main` BLOCK** -- **AND THEY
        # ARE **PUT BACK** **AT THE PORT's FOOT**."
        impl = [l for l in impl if l not in keep]
        impl = impl + [""] + keep
        # **AND THE DRIVER DOES NOT CARRY THEM** -- **AND A DRIVER THAT
        # CARRIES **THE PORT's BACKLOG** IS **A DRIVER THAT LOOKS LIKE **THE
        # PORT**."
        moved = [l for l in moved if l not in keep]
    return impl, moved


def driver_text(path: Path, info: dict, moved: list[str], impl: list[str]) -> str:
    """**THE PROVEN TOOL's DRIVER TEXT, WITH **THE COLLISION-AWARE NAME**."""
    text = xgrp.driver_text(path, info, moved, impl)
    # **AND THE PROVEN TOOL's HEADER NAMES **THE DRIVER FILE** -- **AND THE
    # NAME IS **THE COLLISION-AWARE ONE** -- **SO THE HEADER IS **RE-POINTED**
    # AND **NOT **THE WHOLE DRIVER REBUILT.**
    name = driver_name(path)
    bare = f"{path.stem}-gate.bend"
    return text.replace(f"gates/{bare}", f"gates/{name}")


def cited_names(port: Path, root: Path) -> set[str]:
    """**THE DEFS OF **THIS FILE** THAT **ANOTHER `.bend` FILE **CITES** --
    **AND THE CITATION IS **THE **INSTRUMENT's OWN FORM**: **`<path>:<line>`
    **PLUS **THE `symbol=<name>`** OR **THE **BACKTICKED **NAME** ON **THE
    CITING LINE** -- **AND **THE POPULATION IS **DISCOVERED** BY **A DIRECTORY
    WALK** (DOCTRINE 1).**

    **AND **A CITATION **MAY **NAME **THE FILE **BY **THE **BARE STEM**
    **OR **BY **THE **FULL PATH** -- **AND BOTH **ARE **ACCEPTED** -- **AND
    **THE FILE **MUST BE **THE **ONE **BEING **MOVED** -- **AND **A CITATION
    **INTO **A **DIFFERENT `memory.bend`** IS **NOT **A CITATION **INTO THIS
    ONE**."""
    stem = port.name
    out: set[str] = set()
    for base in ("tinybendygrad", "gates"):
        d = root / base
        if not d.is_dir():
            continue
        for p in d.rglob("*.bend"):
            if p.resolve() == port.resolve():
                continue
            try:
                text = p.read_text()
            except OSError:
                continue
            for i, line in enumerate(text.split("\n")):
                if stem + ":" not in line and "/schedule/" + stem + ":" not in line:
                    continue
                if f"{port.relative_to(root / 'tinybendygrad')}:".replace("schedule/", "schedule/") not in line \
                        and stem + ":" not in line:
                    continue
                for m in SYMBOL.findall(line):
                    out.add(m)
                for m in BACKTICK.findall(line):
                    out.add(m)
    return out


def driver_name(port: Path) -> str:
    """**THE DRIVER's NAME -- **AND IT **REFUSES** A **COLLISION**.

    **AND **A COLLISION IS **A REAL THING IN THIS TREE**: MEASURED
    2026-11-10, `gates/memory-gate.bend` **ALREADY EXISTS** **AND IT IS THE
    DRIVER FOR `tinybendygrad/runtime/support/memory.bend`** -- **AND THE
    BARE STEM OF `tinybendygrad/schedule/memory.bend` IS **THE SAME WORD**,
    **SO THE BARE NAME WOULD **OVERWRITE** A LIVE DRIVER.**

    **AND THE PROVEN TOOL's OWN RULE IS "**THE PARENT DIRECTORY IS ADDED
    **ONLY WHEN **THE BARE STEM SAYS NOTHING OR **COLLIDES****"** -- **AND
    ITS OWN `driver_name` IMPLEMENTS THE "SAYS NOTHING" HALF** (THE
    `_`-PREFIXED STEM) **AND NOT THE "COLLIDES" HALF.**

    **SO THE COLLISION HALF IS HERE**, **AND IT IS **A COMPARISON** AND NOT
    A LIST**: A DRIVER **THAT EXISTS** AND **THAT IS **THE DRIVER FOR A
    **DIFFERENT** PORT FILE** IS A COLLISION** -- **AND A DRIVER **THAT IS
    **THIS TOOL's OWN** OUTPUT FOR **THIS** PORT FILE IS NOT** -- **AND THE
    OWN OUTPUT IS RECOGNISED BY **ITS OWN HEADER**, **WHICH NAMES **THE PORT
    FILE IT IS FOR** -- **SO THE TEST IS **A READ**, NOT A NAME SHAPE.**
    """
    base = xgrp.xgr.driver_name(port, ROOT)
    candidate = ROOT / "gates" / base
    if not candidate.exists():
        return base
    text = candidate.read_text()
    rel = str(port.relative_to(ROOT))
    # **AND **THE DRIVER's OWN HEADER** NAMES **THE PORT FILE IT IS FOR** --
    # **AND A DRIVER THAT ALREADY NAMES **THIS** PORT FILE IS **THIS TOOL's
    # OWN OUTPUT** -- **AND IT IS NOT A COLLISION.**
    if f"THE GATE DRIVER for `{rel}`" in text:
        return base
    # **AND OTHERWISE IT IS **A COLLISION** -- **AND THE PARENT DIRECTORY
    # JOINS THE NAME** -- **AND THE PARENT'S WORDS ARE THE PORT's OWN
    # LOCATION, **SO THE NAME SAYS **WHICH** `memory.bend` IT IS.**
    parent = port.parent.relative_to(ROOT / "tinybendygrad")
    prefix = "-".join(parent.parts)
    return f"{prefix}-{port.stem}-gate.bend"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", nargs="*", default=[])
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if not args.apply:
        print(__doc__)
        return 0
    for rel in args.apply:
        path = ROOT / rel
        info = analyse(path)
        impl, moved = build(path, info)
        name = driver_name(path)
        driver = ROOT / "gates" / name
        print(f"  {rel}: {len(info['prods'])} producers, {len(info['aggs'])} wrappers, "
              f"{len(info['helpers'])} row-only helpers")
        print(f"    port: {len(info['lines'])} -> {len(impl)} lines;  driver: {len(moved)} lines"
              f"  ->  gates/{name}")
        if args.dry_run:
            continue
        driver.write_text(driver_text(path, info, moved, impl))
        path.write_text("\n".join(impl) + "\n")
        mem_a, bend_a = xgrp.compile_of(path)
        mem_b, bend_b = xgrp.compile_of(driver)
        print(f"    port file: {mem_a} / {bend_a}   driver: {mem_b} / {bend_b}")
        if bend_a.startswith("SOME") or bend_a == "ERROR" or bend_a == "NO-VERDICT" \
           or bend_b.startswith("SOME") or bend_b == "ERROR" or bend_b == "NO-VERDICT":
            print("    **REFUSED: one of the two did not compile -- RESTORE BOTH.**")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
