#!/bin/sh
# L-11: a .venv copied out of the tree points at the ORIGINAL tinygrad via an absolute
# path in __editable___tinygrad_0_14_0_finder.py.  This refuses, strictly.
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
export LC_ALL=C DEV=NULL
unset PYTHONPATH
"$ROOT/.venv/bin/python" -c 'import tinygrad,sys; sys.stderr.write("RESOLVED=%s\n"%tinygrad.__file__)'
