#!/usr/bin/env python3
# .agents/slop/nv_gate.py -- append THE GATE block to nvdev.bend, idempotently.
#
# It is a separate script because the gate is long and re-running the whole
# construction is how a truncated file happened once already. The marker row
# `nvdev-done=1` is the sentinel: if it is present the gate is already in.
import sys, re

P = "tinybendygrad/runtime/support/nv/nvdev.bend"
GATE = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/gate.bend"

src = open(P).read()
if 'nvdev-done=1' in src:
    print("gate already present"); sys.exit(0)
g = open(GATE).read()
if "def main" not in g:
    print("GATE FILE HAS NO MAIN -- refusing to append"); sys.exit(1)
open(P, "w").write(src.rstrip("\n") + "\n\n" + g)
print(f"appended {len(g.splitlines())} lines")