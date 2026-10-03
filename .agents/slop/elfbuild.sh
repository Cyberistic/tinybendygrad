#!/bin/sh
# rebuild the probe copy (helpers_local shim) and report the first error
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
python3 .agents/slop/elfbuild.py > /tmp/elfgen.bend
sed 's|import ./../../helpers.bend as H|import ./helpers_local.bend as H|' /tmp/elfgen.bend > .agents/slop/elfprobe/elf_local.bend
./bin/bend .agents/slop/elfprobe/elf_local.bend --check-only 2>&1 | sed -n '1,10p'
