#!/usr/bin/env python3
"""**PRINT **THE **COMMENT **BLOCKS **OF **ONE **FILE **WITH **THEIR **VERDICT**, **SO **A
**UNIT **CAN **READ **THEM**."""
import importlib.util, pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
only = sys.argv[1]
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    if len(blk) < 6: continue
    print(f"--- {rel}:{ln} [{cc.verdict(' '.join(blk))}] {len(blk)}L")
    for b in blk: print(b)
