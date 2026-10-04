#!/usr/bin/env bash
# nv-qmd-mutate.sh -- DOES EACH CONVERTED ROW MOVE WHEN THE PORT IS WRONG?
#
# A conversion that only changes provenance is not yet a test. The bar the brief
# sets is that the converted row must be shown to FAIL when the port is wrong,
# because otherwise a literal has been swapped for a call that is just as
# unverified.
#
# NOTHING HERE TOUCHES THE LIVE TREE. `md5 -q` on macOS takes exactly ONE file
# and prints nothing given several, so each digest is a separate invocation and
# the whole file is named every time. The digest of `tinybendygrad/runtime/
# ops_nv.bend` is taken before and after and asserted equal, because a harness
# that patches the live port silently converts a mutation experiment into a
# permanent change to someone else's file.
#
# The copy is the whole `tinybendygrad/` TREE, not the one file: a Bend import is
# relative, so a lone `ops_nv.bend` in $TMPDIR cannot resolve `./x.bend` and the
# run fails for a reason that has nothing to do with the mutation. That mistake
# produced 22 phantom blind spots in one unit.
#
#     bash .agents/slop/nv-qmd-mutate.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="tinybendygrad/runtime/ops_nv.bend"
WORK="$ROOT/.agents/slop/.mutwork/qmd"
ORACLE="$ROOT/.agents/slop/nv-oracle.py"

before="$(md5 -q "$ROOT/$PORT")"
echo "live port md5 BEFORE : $before"

rm -rf "$WORK"; mkdir -p "$WORK"
cp -R "$ROOT/tinybendygrad" "$WORK/tinybendygrad"
cp -R "$ROOT/bin" "$WORK/bin" 2>/dev/null || true
cp "$ORACLE" "$WORK/oracle.py"

# The oracle's rows, once, as name=value. Keyed on the NAME because the differ
# keys on the name; a name-comparing harness reported 0 for all 30 mutations in
# one unit and 0 for all 68 in another.
"$ROOT/.venv/bin/python" "$ORACLE" > "$WORK/cpython.rows" || { echo "ORACLE FAILED"; exit 1; }
echo "cpython rows         : $(grep -c '' "$WORK/cpython.rows")"

run_port() {  # $1 = label ; the mutated copy must exist already
  # The REAL `bin/bend`, run against the COPY's port. `bin/bend` resolves
  # `../references/bend/bend2/main.ts` relative to ITSELF, so a copied `bin/`
  # looks for a `references/` that was not copied and every run comes back with
  # zero rows and exit 1 -- which reads as "the mutation moved nothing" and is
  # the 0-rows-means-nothing trap wearing a costume.
  local rc n
  for rc in 1 2 3; do   # `bend` stack-overflows ~1 run in 20; RETRY, never report a 0
    ( cd "$WORK" && "$ROOT/bin/bend" tinybendygrad/runtime/ops_nv.bend ) > "$WORK/$1.bend" 2>"$WORK/$1.err"
    [ $? = 0 ] && break
    sleep 1
  done
  n=$(grep -c '' "$WORK/$1.bend")
  echo "$1 exit=$rc bend_rows=$n"
  [ "$n" = 0 ] && { echo "  !! ZERO ROWS -- a failed run, NOT a measurement"; head -4 "$WORK/$1.err"; }
  return 0
}

# ---------- baseline: the unmutated COPY, not the live file ----------
run_port baseline
cmp -s "$WORK/baseline.bend" <( cd "$ROOT" && ./bin/bend "$PORT" 2>/dev/null ) && echo "  copy == live port rows: YES" || echo "  copy == live port rows: NO"
cp "$WORK/baseline.bend" "$WORK/base.rows"
echo "  baseline rows: $(grep -c '' "$WORK/base.rows")"

mutate() {  # $1 = label, $2 = python snippet doing the edit
  cp "$ROOT/$PORT" "$WORK/tinybendygrad/runtime/ops_nv.bend"
  "$ROOT/.venv/bin/python" - "$WORK/tinybendygrad/runtime/ops_nv.bend" <<PY
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
$2
PY
}

report() {  # $1 = label, $2 = expected row name
  "$ROOT/.venv/bin/python" - "$WORK/base.rows" "$WORK/$1.bend" "$WORK/cpython.rows" "$2" <<'PY'
import sys, pathlib
base_p, mut_p, cpy_p, want = sys.argv[1:5]
base, mut, cpy = (pathlib.Path(p).read_text().splitlines()
                  for p in (base_p, mut_p, cpy_p))
def rows(ls):
  d = {}
  for l in ls:
    if "=" in l:
      k, v = l.rsplit("=", 1); d[k] = v
  return d
b, m, c = rows(base), rows(mut), rows(cpy)
mv, cv, bv = m.get(want), c.get(want), b.get(want)
moved = (mv != bv)
agrees = (mv == cv)
print(f"  {want:28} base={bv!s:>10} mutated={mv!s:>10} cpython={cv!s:>10} "
      f"MOVED={moved} still_agrees={agrees}")
PY
}

echo
echo "=== BASELINE sanity: the copy must reproduce the live port exactly"

echo
echo "=== M1  qmd.ver.of: >= BLACKWELL_COMPUTE_A  ->  > BLACKWELL_COMPUTE_A"
mutate M1 '
old = "def qmd.ver.of(compute: U32) -> U32:\n  Bool.pick(U32, U32.is_ge(compute, CLASS_BLACKWELL_COMPUTE_A()), QMD_VER5(), QMD_VER3())"
new = "def qmd.ver.of(compute: U32) -> U32:\n  Bool.pick(U32, U32.is_gt(compute, CLASS_BLACKWELL_COMPUTE_A()), QMD_VER5(), QMD_VER3())"
assert old in t, "M1 anchor not found"
p.write_text(t.replace(old, new, 1))'
run_port M1
for r in nv_qmd_ver_ada nv_qmd_ver_bwb nv_qmd_ver_bwa nv_qmd_ver_ampere; do report M1 "$r"; done

echo
echo "=== M2  qmd.cbuf_shift: the >= 4 test  ->  >= 5  (see the verdict below)"
mutate M2 '
old = "def qmd.cbuf_shift(+v: U32) -> U32: Bool.pick(U32, U32.is_ge(v, 4), 6, 0)"
new = "def qmd.cbuf_shift(+v: U32) -> U32: Bool.pick(U32, U32.is_ge(v, 5), 6, 0)"
assert old in t, "M2 anchor not found"
p.write_text(t.replace(old, new, 1))'
run_port M2
for r in nv_qmd_cbuf_shift3 nv_qmd_cbuf_shift5; do report M2 "$r"; done

echo
echo "=== M3  qmd.prog_shift: 4  ->  3"
mutate M3 '
old = "def qmd.prog_shift(v: U32) -> U32: Bool.pick(U32, U32.is_ge(v, 4), 4, 0)"
new = "def qmd.prog_shift(v: U32) -> U32: Bool.pick(U32, U32.is_ge(v, 4), 3, 0)"
assert old in t, "M3 anchor not found"
p.write_text(t.replace(old, new, 1))'
run_port M3
for r in nv_qmd_prog_shift3 nv_qmd_prog_shift5; do report M3 "$r"; done

echo
echo "=== M4  qmd.rel_size: the SIGNAL arm 2  ->  0"
mutate M4 '
old = "  Bool.pick(U32, tstamp, 0, 2)"
new = "  Bool.pick(U32, tstamp, 2, 0)"
assert old in t, "M4 anchor not found"
p.write_text(t.replace(old, new, 1))'
run_port M4
for r in nv_qmd_rel_size_signal nv_qmd_rel_size_timestamp; do report M4 "$r"; done

echo
echo "=== M5  qmd.payload64b: the >= 4 test  ->  >= 5  (see the verdict below)"
mutate M5 '
old = "def qmd.payload64b(v: U32) -> Bool: Bool.not(U32.is_ge(v, 4))"
new = "def qmd.payload64b(v: U32) -> Bool: Bool.not(U32.is_ge(v, 5))"
assert old in t, "M5 anchor not found"
p.write_text(t.replace(old, new, 1))'
run_port M5
for r in nv_qmd_payload64b_3 nv_qmd_payload64b_5; do report M5 "$r"; done

echo
echo "=== M6  qmd.slot: the busy1 arm's inner pick  1  ->  2"
mutate M6 '
old = "  Bool.pick(U32, busy0, Bool.pick(U32, busy1, 3, 1), 0)"
new = "  Bool.pick(U32, busy0, Bool.pick(U32, busy1, 3, 2), 0)"
assert old in t, "M6 anchor not found"
p.write_text(t.replace(old, new, 1))'
run_port M6
for r in nv_qmd_slot_free nv_qmd_slot_0 nv_qmd_slot_1 nv_qmd_slot_both; do report M6 "$r"; done

echo
echo "=== M7  qmd.slot.ok: not(and(b0,b1))  ->  not(or(b0,b1))"
mutate M7 '
old = "def qmd.slot.ok(busy0: Bool, busy1: Bool) -> Bool: Bool.not(Bool.and(busy0, busy1))"
new = "def qmd.slot.ok(busy0: Bool, busy1: Bool) -> Bool: Bool.not(Bool.or(busy0, busy1))"
assert old in t, "M7 anchor not found"
p.write_text(t.replace(old, new, 1))'
run_port M7
for r in nv_qmd_release_ok_free nv_qmd_release_ok_one nv_qmd_release_refuses; do report M7 "$r"; done

after="$(md5 -q "$ROOT/$PORT")"
echo
echo "live port md5 AFTER  : $after"
[ "$before" = "$after" ] && echo "LIVE TREE UNTOUCHED: YES" || echo "LIVE TREE CHANGED: NO -- STOP"