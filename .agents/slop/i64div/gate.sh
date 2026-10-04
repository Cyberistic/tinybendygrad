#!/bin/bash
# I64DIV gate. rows-present vs rows-expected, whole `name=value` lines diffed.
# ROWS ARE CLASSIFIED, never lumped:
#   agree    - port == upstream
#   disagree- port != upstream, and the row is NOT a documented wrap
#   wrap     - the EXACT upstream answer is outside the i64 range, so a differing
#              port answer is the documented 64-bit wrap, counted separately
#   diverge  - the zero-divisor rows, which upstream answers by GUARDING; reported
#              on their own line and never folded into `agree`
set -u
cd "$(dirname "$0")"
BEND=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend
OUT="${1:-got.txt}"

python3 gen_gate.py > gen.out 2>&1 || { echo "GENERATOR FAILED"; cat gen.out; exit 1; }
cat gen.out
: > "$OUT"
for f in $(ls gate*.bend | sort -V); do
  perl -e 'alarm 900; exec @ARGV' "$BEND" "$f" 2>/dev/null | grep -E '^[dcmkgt]_' >> "$OUT"
done

python3 - "$OUT" <<'PY'
import sys
got = {}
for ln in open(sys.argv[1]):
    k, _, v = ln.strip().partition("=")
    if k:
        got[k] = v
exp = {}
for ln in open("expected.txt"):
    k, _, v = ln.strip().partition("=")
    if k:
        exp[k] = v
wrap = {l.strip() for l in open("wrap.txt") if l.strip()}
zero = {l.strip() for l in open("zero.txt") if l.strip()}

missing = sorted(set(exp) - set(got))
extra   = sorted(set(got) - set(exp))
bad = {k for k in exp if k in got and got[k] != exp[k]}
bad_nw  = {k for k in bad if k not in wrap and k not in zero}
bad_w  = {k for k in bad if k in wrap}
bad_z  = {k for k in bad if k in zero}
ok     = {k for k in exp if k in got and got[k] == exp[k] and k not in zero}
ok_z   = {k for k in exp if k in got and got[k] == exp[k] and k in zero}
zdiv   = {k for k in exp if k in zero}

print(f"rows_expected={len(exp)}  rows_present={len(got)}  missing={len(missing)}  extra={len(extra)}")
print(f"  agree(exact, non-zero-divisor) = {len(ok)}")
print(f"  agree(exact, zero-divisor)     = {len(ok_z)} / {len(zdiv)}")
print(f"  DIVERGE (zero-divisor rows)    = {len(bad_z)}")
print(f"  WRAP  (documented 64-bit wrap) = {len(bad_w)}")
print(f"  DISAGREE (real defects)        = {len(bad_nw)}")
print(f"  VERDICT: {'GREEN' if not bad_nw and not missing and not extra else 'RED'}")
if missing: print("  MISSING:", missing[:8])
if extra:   print("  EXTRA:", extra[:8])
for lbl, s in (("DISAGREE", bad_nw), ("WRAP", bad_w), ("DIVERGE", bad_z)):
    for k in sorted(s)[:400]:
        print(f"  {lbl:8} {k:44} port={got.get(k,'-'):>24} upstream={exp[k]:>24}")
PY
