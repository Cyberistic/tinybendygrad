#!/usr/bin/env python3
"""**FIND **THE **EXTENT **OF **EACH **"WHAT **IS **PORTED" **INVENTORY **TABLE**, **⇒⇒† AND
**PRINT **THE **RANGE**.

**⇒⇒† AND **THE **RULE**: **THE **TABLE **RUNS **FROM **THE **HEADER **TO **THE **FIRST
**COMMENT **LINE **THAT **IS **NOT **INDENTED **AND **NOT **A **BLANK **SEPARATOR**."""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
HEAD = re.compile(r"^#\s*(WHAT IS PORTED|WHAT IS NOT PORTED|WHAT SURVIVES)\b")
only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    if len(blk) < 10: continue
    if not HEAD.match(blk[0]): continue
    end = 0
    for i, l in enumerate(blk):
        if i == 0: continue
        s = l.strip()
        if s == "#": continue
        # **⇒⇒† AND **A **TABLE **ROW **IS **AN **INDENTED **COMMENT **LINE**, **⇒⇒† AND
        # **A **SECTION **HEADER **IS **NOT**.
        if not re.match(r"^#\s{2,}\S", l): break
        end = i
    print(f"{rel}:{ln}-{ln+end}  ({end+1}L)  {blk[0][:70]}")
