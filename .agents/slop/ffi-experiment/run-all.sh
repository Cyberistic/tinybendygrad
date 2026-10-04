#!/bin/zsh
# Reproduce every result in the bend-shared-library FFI report, end to end.
# Run from anywhere:  zsh .agents/slop/ffi-experiment/run-all.sh
# Nothing here touches the repo tree; all scratch goes to $TMPDIR/ffix-run.
set -u
BEND=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend
SRC=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/ffi-experiment
CLIB=/Library/Developer/CommandLineTools/usr/lib
W="$TMPDIR/ffix-run"
rm -rf "$W"; mkdir -p "$W"; cp "$SRC"/*.c "$SRC"/*.bend "$SRC"/nop.c "$W"/
cd "$W" || exit 1

# step, name, expected-stdout, then the actual four-step run
run() {
  local name=$1 want=$2; shift 2
  local s1 s2 s3 s4
  "$BEND" "$name.bend" -o "$name.c" >/dev/null 2>&1; s1=$?
  if [[ $s1 -ne 0 || ! -f $name.c ]]; then
    echo "FAIL[$name] step1 bend -o (rc=$s1)"; return; fi
  echo "  step1 bend -o   ok  ($(wc -c < $name.c | tr -d ' ') bytes)"
  if ! cc -x objective-c "$name.c" -framework Metal -framework Foundation \
       -o "$name.out" 2>/dev/null; then
    # not every case needs Metal
    if ! cc "$name.c" -o "$name.out" 2>/dev/null; then
      echo "FAIL[$name] step3 LINK"; return; fi
  fi
  echo "  step2 cc compile ok"
  echo "  step3 LINK      ok"
  local got; got=$(./"$name.out" 2>&1)
  s4=$?
  if [[ $got == *"$want"* ]]; then
    echo "  step4 run       ok  | $got"
    print -r -- "PASS [$name] expected '$want'"
  else
    echo "FAIL[$name] step4 RUN rc=$s4"
    print -r -- "   expected: $want"
    print -r -- "   observed: $got"
  fi
}

print -r -- "=== E1 libc strlen, C-local ==="
run e1  "SLEN 13"

print -r -- "\n=== E3 libc both directions (getenv out, Bend String in) ==="
FOO=barbaz run e3 "ENV barbaz"
FOO=barbaz run e3 "MARSHAL 13"

print -r -- "\n=== E5 three laws, ONE shim.c, one import, one link ==="
run e5  "19"

print -r -- "\n=== E4 libclang via -lclang + rpath ==="
"$BEND" e4.bend -o e4.c >/dev/null 2>&1 && echo "  step1 bend -o ok ($(wc -c < e4.c | tr -d ' ') bytes)" || echo "FAIL step1"
cc -c e4.c -o /dev/null 2>/dev/null && echo "  step2 cc compile ok" || echo "FAIL step2"
cc e4.c -L$CLIB -lclang -Wl,-rpath,$CLIB -o e4.out 2>/dev/null \
  && echo "  step3 LINK ok" || echo "FAIL step3 LINK"
e4out=$(./e4.out 2>&1)
[[ $e4out == *"clang version"* ]] \
  && print -r -- "PASS [e4] | $e4out" || print -r -- "FAIL [e4] | $e4out"

print -r -- "\n=== E13 Metal: C fn, ObjC send, raw objc runtime, property read ==="
run e13 "QUEUE_PROTOCOL 1"
run e13 "QUEUE_OBJC_RUNTIME 1"
run e13 "BUFFER_LENGTH 1024"

print -r -- "\n=== E8 a 64-bit driver handle, C and Bend in ONE process ==="
# The address is ASLR-dependent, so a literal is the WRONG expectation. The
# invariant is that C and Bend report the SAME pointer. Compare them to each
# other; do not compare either to a constant.
run e8 "BEND_GOT" >/dev/null
e8out=$(./e8.out 2>&1)
c_full=$(print -r -- "$e8out" | sed -n 's/.*C_SAW.*full=\([0-9]*\).*/\1/p')
b_nat=$(print -r -- "$e8out" | sed -n 's/^BEND_NAT \([0-9]*\)$/\1/p')
c_lo=$(print -r -- "$e8out" | sed -n 's/.*C_SAW.*lo=\([0-9]*\).*/\1/p')
b_lo=$(print -r -- "$e8out" | sed -n 's/.*BEND_GOT lo=\([0-9]*\).*/\1/p')
print -r -- "   C   read full=$c_full lo=$c_lo"
print -r -- "   Bend read nat=$b_nat lo=$b_lo"
if [[ -n $c_full && $c_full == $b_nat && $c_lo == $b_lo ]]; then
  print -r -- "PASS [e8] C and Bend agree on the same 64-bit handle"
else
  print -r -- "FAIL [e8] C and Bend DISAGREE"
fi

print -r -- "\n=== counts (denominators) ==="
print -r -- "libclang exported symbols : $(nm -gU $CLIB/libclang.dylib | awk '$2~/^[TDBR]$/{print $3}' | grep -c '^_clang_')"
print -r -- "libclang sig'd decls      : $(grep -cE '^def clang_[A-Za-z0-9_]+\(' /Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/runtime/autogen/libclang.py)"
MH=$(xcrun --show-sdk-path)/System/Library/Frameworks/Metal.framework/Headers
print -r -- "Metal headers            : $(ls $MH/*.h | wc -l | tr -d ' ')"
print -r -- "Metal MTL_EXTERN C fns   : $(grep -hE 'MTL_EXTERN' $MH/*.h | grep -oE '\bMTL[A-Za-z0-9_]+\(' | tr -d '(' | sort -u | wc -l | tr -d ' ')"
print -r -- "Metal @protocols         : $(grep -hE '^@protocol MTL' $MH/*.h | grep -oE 'MTL[A-Za-z0-9_]+' | sort -u | wc -l | tr -d ' ')"
print -r -- "Metal ObjC methods       : $(cat $MH/*.h | grep -cE '^\s*-\s*\(')"
print -r -- "Metal @property          : $(cat $MH/*.h | grep -cE '^\s*@property')"