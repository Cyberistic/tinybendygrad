#!/usr/bin/env python3
"""The PREVIOUS UNIT'S 54, REPRODUCED.

`.agents/slop/i64mul/gen_cmod.py` is COPIED here UNMODIFIED in its fixture set and
its expectation source (it calls `cdiv`/`cmod` from tinygrad/helpers), so the number
54 can be quoted before and after without writing anything into that unit's tree.
Only the output directory and the header path differ.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0]]
src = open("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/i64mul/gen_cmod.py").read()
# retarget the two paths the copied generator writes to / reads from
src = src.replace('os.path.dirname(os.path.abspath(__file__))', repr(HERE))
open(os.path.join(HERE, "gen54_ran.py"), "w").write(src)
exec(compile(src, "gen54", "exec"), {"__name__": "__main__"})
