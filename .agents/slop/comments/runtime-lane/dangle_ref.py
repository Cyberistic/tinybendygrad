#!/usr/bin/env python3
"""**THE **DANGLING-LINE **DETECTOR** -- **A **COMMENT **BLOCK **THAT **ENDS **ON **A
**LINE **THAT **IS **NOT **A **SENTENCE **AND **IS **NOT **A **TABLE **ROW **IS **A
**TRUNCATION**, **⇒⇒† AND **A **TRUNCATION **IS **A **LIE** (RULE 7).

**⇒⇒† AND **THE **TEST**: **A **COMMENT **LINE **ENDS **A **SENTENCE **IF **IT **ENDS
**WITH **`.`/`!`/`?`/`:` **OR **WITH **A **COMMA**/**OR**/**AND**/**BUT**/**THE**/**A**/**AN**/**
**OF**/**TO**/**FOR**/**WITH**/**IS**/**WAS**/**THAT**/**IT**, **⇒⇒† AND **A **TABLE **BLOCK
**(THREE **OR **MORE **PIPE **ROWS**, **OR **A **`----` **RULE) **IS **A **ROW **DUMP**,
**⇒⇒† AND **ITS **LAST **LINE **IS **A **ROW **AND **NEEDS **NO **FULL **STOP**.

**⇒⇒† AND **THE **POPULATION **IS **DISCOVERED** (DOCTRINE 1): **A **WALK **OVER
**`tinybendygrad/` **FOR **THE **`.bend` **FILES**, **⇒⇒† AND **THE **LANE **IS **THE
**`runtime/` **PREFIX**."""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
only = sys.argv[1] if len(sys.argv) > 1 else ""
CONT = re.compile(r"[.!?:,]\s*$|[\)\]\}`'\"_]\s*$|\b(AND|OR|BUT|THE|A|AN|OF|TO|FOR|WITH|IS|WAS|THAT|IT)\s*$", re.I)
PIPE = re.compile(r"^\s*#\s*\|")
DASHDASH = re.compile(r"^\s*#\s*-{3,}\s*\S")
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if only and not rel.startswith(only): continue
    if len(blk) < 2: continue
    if sum(1 for l in blk if PIPE.match(l)) >= 3: continue
    if any(DASHDASH.match(l) for l in blk): continue
    last = blk[-1].strip()
    body = last.lstrip("#").strip()
    if not body: continue
    if CONT.search(body): continue
    print(f"{rel}:{ln+len(blk)-1}  SUSPECT: {last[:140]}")
