#!/bin/sh
# ddcheck.sh -- the LOCAL COMPILE WORKAROUND, and a workaround to be flipped back.
#
# `tinybendygrad/helpers.bend` is ANOTHER AGENT'S FILE and it is mid-edit: its
# `ansistrip` block (the ANSI stripper, `helpers.py:48`) does not compile, and
# EVERY file in `tinybendygrad/` imports `helpers.bend`, so nothing in the tree
# compiles. This mirrors `tinybendygrad/` into `.agents/slop/ddcheck/tree/` with
# a stubbed `helpers.bend` and builds the decomp file there. NOTHING under
# `tinybendygrad/` is written.
#
# WHY A FULL COPY AND NOT SYMLINKS: bend resolves a symlinked file's directory to
# its REAL parent, so a symlinked `uop/ops.bend` still imports the REAL
# `tinybendygrad/helpers.bend`. That was measured, not guessed.
#
# WHEN `tinybendygrad/helpers.bend` COMPILES AGAIN, DELETE THIS SCRIPT AND
# `.agents/slop/dd-patch-helpers.py` AND COMPILE
# `tinybendygrad/codegen/decomp/dtype.bend` DIRECTLY.
set -e
R=$(cd "$(dirname "$0")/../.." && pwd)
D=$R/.agents/slop/ddcheck
rm -rf $D/tree
mkdir -p $D/tree
cp -R $R/tinybendygrad/. $D/tree/
python3 $R/.agents/slop/dd-patch-helpers.py "$D/tree/helpers.bend" >/dev/null
cd $D/tree/codegen/decomp
exec $R/bin/bend dtype.bend "$@"