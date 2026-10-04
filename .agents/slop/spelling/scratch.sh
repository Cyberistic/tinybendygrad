#!/bin/sh
# S-scratch: a $TMPDIR tree in which libclang.bend's relative import resolves.
#   $W/tinybendygrad/runtime/autogen/libclang.bend  ->  ../../../.agents/slop/clangshim/
# so $W must carry BOTH tinybendygrad/ and .agents/slop/clangshim/.
set -e
R=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
W=$TMPDIR/spelling
rm -rf "$W"
mkdir -p "$W/.agents/slop"
cp -R "$R/tinybendygrad" "$W/tinybendygrad"
cp -R "$R/.agents/slop/clangshim" "$W/.agents/slop/clangshim"
echo "$W"