#!/bin/zsh
# Reorder the defs, share the consumed parameters, and report. Both tools are
# drivers, not editors: run this after every edit and read the compiler's own
# message for anything they could not fix.
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
F=${1:-tinybendygrad/uop/spec.bend}
count() { python3 -c "
import re
L=open('$F').read().split('\n')
print(sum(1 for l in L if re.match(r'^(def|type) ', l)), 'defs')"; }
count
python3 .agents/slop/tools/order.py "$F" ./bin/bend
python3 .agents/slop/tools/share.py "$F" ./bin/bend 2>&1 | tail -2
count
wc -l < "$F"
./bin/bend "$F" --check-only 2>&1 | head -12
