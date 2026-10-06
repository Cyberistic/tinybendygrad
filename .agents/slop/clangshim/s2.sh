#!/bin/zsh
# STAGE 2+4 -- all mechanically derivable bindings: ONE .c, ONE import, ONE cc.
# Four named steps; a failure says WHICH one. Nothing touches the repo tree.
#
# The link step is a LOOP, because Apple's libclang.dylib is 17.0.0 while the
# bindings were generated against CINDEX_VERSION 0.64: three symbols postdate the
# dylib on this machine. Those three are named and excluded, and the exclusion is
# printed -- never silently dropped.
#
# Reproduce:  zsh $TMPDIR/clangshim/s2.sh
set -u
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
B=$REPO/bin/bend
GEN=$REPO/.agents/slop/clangshim/clangshim-gen.py
CLIB=/Library/Developer/CommandLineTools/usr/lib
W="$TMPDIR/clangshim"
cd "$W" || exit 1
EXCL=()

gen() {
  rm -rf g; mkdir -p g
  rm -f g/shim.gen.c g/shim.out g/shim.o
  python3 "$GEN" --out g --probe "${(@)EXCL}" | sed 's/^/   /'
}

steps123() {
  "$B" g/shim.bend -o g/shim.gen.c 2>g/bend.err
  # distinct return codes: cc exits 1 on a LINK failure too, so a single rc
  # cannot tell "bend refused the file" from "the dylib lacks a symbol".
  [[ -s g/shim.gen.c ]] || { print -r -- "FAIL step1 bend -o"; sed -n '1,20p' g/bend.err; return 10; }
  cc -c g/shim.gen.c -o g/shim.o 2>g/cc.err || {
    print -r -- "FAIL step2 cc"; grep -m 12 error: g/cc.err | sed 's/^/   /'; return 11; }
  cc g/shim.gen.c -L$CLIB -lclang -Wl,-rpath,$CLIB -o g/shim.out 2>g/link.err || return 12
  return 0
}

print -r -- "== step0 generate, from the committed bindings (read-only)"
gen || exit 1

print -r -- "== steps1-3  bend -o, cc, link -lclang"
attempt=0
z=0
while :; do
  attempt=$((attempt + 1))
  steps123; rc=$?
  [[ $rc -eq 0 ]] && break
  [[ $rc -eq 12 ]] || exit 1
  # link failed: name the undefined symbols and drop exactly those
  undef=$(grep -o ' "_clang_[A-Za-z0-9_]*",' g/link.err | tr -d '",' | sed 's/^ //' | sort -u)
  n=$(print -r -- "$undef" | grep -c .)
  if [[ $n -eq 0 || -z $undef ]]; then
    print -r -- "FAIL step3 link, and nothing undefined to drop:"; sed -n '1,15p' g/link.err; exit 1
  fi
  print -r -- "   step3 LINK: $n symbol(s) absent from $CLIB/libclang.dylib:"
  print -r -- "$undef" | sed 's/^/     /'
  print -r -- "   CINDEX_VERSION in the bindings: $(grep -m1 CINDEX_VERSION_MINOR \
    $REPO/tinygrad/runtime/autogen/libclang.py | tr -d ' ')"
  for s in ${(f)undef}; do EXCL+=(--exclude ${s#_}); done
  z=1
  print -r -- "   regenerating without them"
  gen || exit 1
  [[ $attempt -gt 4 ]] && { print -r -- "FAIL: link still failing after 4 rounds"; exit 1; }
done
print -r -- "   step1 bend -o ok ($(wc -c < g/shim.gen.c | tr -d ' ') bytes)"
print -r -- "   step2 cc      ok ($(wc -c < g/shim.o | tr -d ' ') bytes)"
print -r -- "   step3 LINK    ok"

print -r -- "== step4 run  (the CALL census, 305 forks)"
./g/shim.out >g/stdout.txt 2>g/stderr.txt
print -r -- "   rc=$?"
print -r -- "   stdout rows: $(grep -c '^V' g/stdout.txt)   stderr CALL rows: $(grep -c '^CALL' g/stderr.txt)"
print -r -- "   ok=1 $(grep -c 'ok=1$' g/stderr.txt)   ok=0 $(grep -c 'ok=0$' g/stderr.txt)"