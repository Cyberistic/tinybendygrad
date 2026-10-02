"""bnxtdev.bend -- WHICH DEF IS BROKEN. Truncation at a `def` cannot tell a
fault from a cut body, so this DELETES one whole def (from its `def`/`type`
line to the next one at column 0) and re-checks. The offending def is the one
whose removal turns ERR into OK.

    python3 .agents/slop/whodefs.py tinybendygrad/runtime/support/rdma/bnxtdev.bend
"""
import re
import subprocess
import sys

P = sys.argv[1] if len(sys.argv) > 1 else 'tinybendygrad/runtime/support/rdma/bnxtdev.bend'


def status(src):
    open('/tmp/wd.bend', 'w').write(src)
    r = subprocess.run(['./bin/bend', '/tmp/wd.bend', '--check-only'],
                       capture_output=True, text=True)
    out = r.stdout + r.stderr
    return ('OK' if 'ALL PROOFS CHECK' in out else 'ERR'), out


src = open(P).read()
lines = src.split('\n')
base, base_out = status(src)
print(f"BASELINE: {base}")
if base == 'OK':
    print("already clean")
    sys.exit(0)
starts = [i for i, l in enumerate(lines) if re.match(r'^(def|type) ', l)]
# only try defs that come after the last one known-good, to keep it fast
for idx in range(len(starts)):
    a = starts[idx]
    b = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
    trial = '\n'.join(lines[:a] + lines[b:])
    st, _ = status(trial)
    if st == 'OK':
        print(f"REMOVING def #{idx} line {a + 1} makes it OK:")
        print(f"    {lines[a][:100]}")
        print(f"    baseline error was: {base_out.strip().split(chr(10))[1][:100]}")
        break
else:
    print("no single def removal fixes it -- more than one fault, or the fault "
          "is at the end of the file")
sys.exit(0)