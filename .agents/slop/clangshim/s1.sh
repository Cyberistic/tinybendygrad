#!/bin/zsh
# STAGE 1 -- one function, four steps, four named failure points.
# Reproduce: zsh $TMPDIR/clangshim/s1.sh
set -u
B=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend
CLIB=/Library/Developer/CommandLineTools/usr/lib
W="$TMPDIR/clangshim"; cd "$W" || exit 1
rm -f s1.gen.c s1.out                      # NEVER reuse: a stale .c prints like a pass

print -r -- "step1 bend -o"
"$B" s1.bend -o s1.gen.c 2>s1.bend.err
s1=$?
if [[ $s1 -ne 0 || ! -s s1.gen.c ]]; then
  print -r -- "FAIL step1 bend -o rc=$s1"; sed -n '1,12p' s1.bend.err; exit 1
fi
print -r -- "  ok ($(wc -c < s1.gen.c | tr -d ' ') bytes)"

print -r -- "step2 cc compile"
cc -c s1.gen.c -o s1.o 2>s1.cc.err || { print -r -- "FAIL step2 cc"; sed -n '1,20p' s1.cc.err; exit 1; }
print -r -- "  ok"

print -r -- "step3 link -lclang"
cc s1.gen.c -L$CLIB -lclang -Wl,-rpath,$CLIB -o s1.out 2>s1.link.err \
  || { print -r -- "FAIL step3 link"; sed -n '1,20p' s1.link.err; exit 1; }
print -r -- "  ok"

print -r -- "step4 run"
o=$(./s1.out 2>&1); s4=$?
print -r -- "  rc=$s4 | $o"
[[ $o == S1_NAT\ * ]] && print -r -- "PASS [s1] one libclang call returned a value" \
                     || print -r -- "FAIL [s1]"