# EVERY ARTIFACT IN THIS DIRECTORY, and the exact command that made it.
# env -u PYTHONPATH is REQUIRED (it contaminates a control) and LC_ALL=C is REQUIRED
# (a locale-colated sort fabricates diffs). DEV=NULL is the rebase gate's own setting.
# E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py
#
# generated: 2026-10-03T16:13:59Z
# tree:     /Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/__init__.py
# bend:     ALL PROOFS CHECK
#
00  E selfcheck
01  E emit --side py                     > 01-canon-py.txt   (.hdr is stderr)
02  E emit --side bend --dev-map 0=NULL   > 02-canon-bend.txt
03  E control --dev-map 0=NULL            # each side against ITSELF
04  E diff --dev-map 0=NULL               # THE real comparison, clean -> AGREE
05  E diff                                # the same with NO dev binding -> DISAGREE
06  E diff --dev-map 0=NULL --plant srcswap   # commutative MUL children reversed
07  E diff --dev-map 0=NULL --plant dtype    # the two ALLOCs retyped to i32
08  E cross --dev-map 0=NULL              # matmul vs sum(axis=1): two DIFFERENT graphs
09  E diff --dev-map 0=NULL --plant shape   # the (4,3) shape STACK reversed
10  diff 01-canon-py.txt 02-canon-bend.txt  -> BYTE-IDENTICAL (rc=0 in the file)
11  8x the clean diff, 20x raw bend rows, and the 0-row guard FIRED ON PURPOSE
