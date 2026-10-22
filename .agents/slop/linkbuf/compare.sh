#!/bin/sh
# THE COMPARISON. The port's rows against the CPython oracle's rows, over the
# keys they SHARE.  ONE bend at a time: the lock is held for the whole
# invocation and released immediately after.
#
#   sh .agents/slop/linkbuf/compare.sh
#
# The port is `tinybendygrad/device.bend` -- the path the brief named,
# `tinybendygrad/runtime/device.bend`, DOES NOT EXIST, and this is the file
# upstream's `tinygrad/device.py` is the oracle for.
set -e
cd "$(dirname "$0")/../../.."
LOCK=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/bend.lock
SCRATCH=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode
OUT=$(mktemp -d "$SCRATCH/linkbuf-cmp-XXXXXX")
trap 'rm -rf "$OUT"; rmdir "$LOCK" 2>/dev/null' EXIT
t0=$(date +%s)
while ! mkdir "$LOCK" 2>/dev/null; do sleep 2; done
t1=$(date +%s)
echo "bend lock waited $((t1-t0))s"
./bin/bend tinybendygrad/device.bend > "$OUT/port.rows" 2> "$OUT/port.err" || true
t2=$(date +%s)
echo "bend ran $((t2-t1))s"
rmdir "$LOCK" 2>/dev/null || true
.venv/bin/python .agents/slop/linkbuf/oracle.py > "$OUT/cpython.rows"
.venv/bin/python - "$OUT/port.rows" "$OUT/cpython.rows" <<'EOF'
import sys
def load(p):
    d = {}
    for ln in open(p):
        ln = ln.strip()
        if "=" in ln:
            k, v = ln.split("=", 1)
            d[k] = v
    return d
port, cpy = load(sys.argv[1]), load(sys.argv[2])
shared = [k for k in port if k in cpy]
bad = [k for k in shared if port[k] != cpy[k]]
print(f"shared={len(shared)} agree={len(shared)-len(bad)} differ={len(bad)}")
for k in sorted(shared):
    print(f"{'OK ' if port[k]==cpy[k] else 'DIFF'} {k}: port={port[k]} cpython={cpy[k]}")
sys.exit(1 if bad else 0)
EOF
