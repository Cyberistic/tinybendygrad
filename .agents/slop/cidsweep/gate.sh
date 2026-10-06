#!/bin/sh
# .agents/slop/cidsweep/gate.sh -- CIDS: per-seam BUILD gate.
#
# WHY A BUILD AND NOT A SYNTAX CHECK.  `bend -o out.c` is rc 0 for every case in
# this gate, before and after every fix: it emits C and does not compile it.  The
# instrument that can see this defect class is `cc -fsyntax-only` on the emit.
#
# WHY NOT THE TREE'S OWN `#define CID(x) 0` SHIM.  `#ifdef` does not macro-expand
# its operand, so with that shim EVERY `#ifdef CID(...)` is TRUE -- maximally
# permissive.  It can only ever add permissiveness, so it cannot report a missing
# guard either.  (Measured by SZLANE §5: a syntax error injected inside a guarded
# region is still COLD, guarded or not.)
#
# USAGE:  sh .agents/slop/cidsweep/gate.sh
# Rule prefix CIDS-.
set -u
cd "$(dirname "$0")/../../.." || exit 2
R=.agents/slop/cidsweep
W="${TMPDIR:-/tmp}/cidsweep-gate"
mkdir -p "$W"
FAIL=0

# build <label> <probe.bend> <extra -I dir or empty>
build() {
  L=$1; P=$2; INC=${3:-}
  B=$(basename "$P" .bend)
  ./bin/bend "$P" -o "$W/$B.c" >"$W/$B.bend.log" 2>&1; BR=$?
  if [ ! -f "$W/$B.c" ]; then
    printf '  %-38s bend rc=%s  NO EMIT            cc rc=n/a\n' "$L" "$BR"
    FAIL=$((FAIL+1)); return
  fi
  # shellcheck disable=SC2086
  cc -fsyntax-only $INC "$W/$B.c" >"$W/$B.cc.log" 2>&1; CR=$?
  ERRS=$(grep -c 'error:' "$W/$B.cc.log" 2>/dev/null || echo 0)
  IDS=$(grep -c '^#define CID_' "$W/$B.c" 2>/dev/null || echo 0)
  REGS=$(cc -E $INC "$W/$B.c" 2>/dev/null | grep 'io_eff(' | grep -v 'static void io_eff' \
         | grep -o 'io_eff([0-9]*' | sed 's/io_eff(//' | sort -n | tr '\n' ',' )
  V=ok; [ "$CR" != 0 ] && { V=COLD; FAIL=$((FAIL+1)); }
  # NOTE: registrations-landing counts EVERY io_eff call in the emit, bend's own
  # IO.args/IO.print included -- not only the seam's.  Read the seam's own id off
  # the emit; the point of the column is that the count DROPS when a guard lands.
  printf '  %-38s bend rc=%s emit=%6sL #define CID_*=%-3s cc rc=%s err=%-2s [%s] registrations-landing=%s\n' \
    "$L" "$BR" "$(wc -l < "$W/$B.c" | tr -d ' ')" "$IDS" "$CR" "$ERRS" "$V" "${REGS:-none}"
}

echo "== C1  dtype.c  -- 10 registrations, 10 guards, 0 constructor ids       [expect WARM]"
build "dtype: reaches ONE dtype.c seam" "$R/probe-dtype-one.bend"
build "dtype: reaches NO seam"           "$R/probe-dtype-none.bend"

echo "== C2  sz.c     -- 2 registrations, 2 guards, CID(Nil)/CID(Con) INSIDE  [expect WARM]"
build "sz: reaches NOTHING"  "$R/probe-sz-none.bend"
build "sz: reaches Sz.is_dir"    .agents/slop/szlane/probe-isdir.bend
build "sz: reaches Sz.read_dir" .agents/slop/szlane/probe-readdir.bend

echo "== C3  libclang-tramp.c -- 325 registrations, 325 guards                [expect WARM]"
build "libclang: reaches ONE tramp effect" "$R/probe-libclang-tramp-one.bend" "-I .agents/slop/clangshim"

echo "== C4  libclang-ffi.c   -- 10 registrations, 0 guards      *** CIDS-1 *** [expect COLD]"
build "libclang: reaches NOTHING"       "$R/probe-libclang-none.bend"    "-I .agents/slop/clangshim"
build "libclang: reaches ONE ffi effect" "$R/probe-libclang-ffi-one.bend" "-I .agents/slop/clangshim"

echo "== C5  JS lane -- no conditional compilation exists; node is the instrument [expect PASS]"
./bin/bend "$R/probe-dtype-one.bend" -o "$W/dt.js" >/dev/null 2>&1
printf '  js: #ifdef=%s #endif=%s defined(=%s   node --check: ' \
  "$(grep -c '#ifdef' "$W/dt.js" || echo 0)" "$(grep -c '#endif' "$W/dt.js" || echo 0)" \
  "$(grep -c 'defined(' "$W/dt.js" || echo 0)"
node --check "$W/dt.js" >/dev/null 2>&1 && printf 'PASS   ' || { printf 'COLD   '; FAIL=$((FAIL+1)); }
node "$W/dt.js" >/dev/null 2>&1 && printf 'node-runs=rc0\n' || printf 'node-runs=rc%s\n' "$?"

echo
if [ "$FAIL" = 0 ]; then
  echo "GATE PASS  (0 cold seams)"
else
  echo "GATE FAIL  $FAIL cold seam(s) -- see CIDS-1 in .agents/slop/CIDSWEEP.md"
fi
exit "$FAIL"
