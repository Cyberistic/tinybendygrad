#!/bin/zsh
# STAGE 3 -- the falsifiable row, run TWICE. Every comparison is C-vs-Bend on
# the SAME object in the SAME process, or a PLANT paired with a DISARM. Nothing
# is compared to a constant, because clang_createIndex returns an ASLR-varying
# heap pointer and run-all.sh's `BEND_NAT 4307773504` was that mistake.
#
# Reproduce:  zsh $TMPDIR/clangshim/s3.sh
set -u
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
B=$REPO/bin/bend
CLIB=/Library/Developer/CommandLineTools/usr/lib
W="$TMPDIR/clangshim"
cd "$W" || exit 1
rm -f s3.gen.c s3.out s3.o s3.r1.out s3.r2.out

print -r -- "step1 bend -o"
"$B" s3.bend -o s3.gen.c 2>s3.bend.err || { print -r -- "FAIL step1"; sed -n '1,14p' s3.bend.err; exit 1; }
[[ -s s3.gen.c ]] || { print -r -- "FAIL step1: no output"; exit 1; }
print -r -- "  ok"

print -r -- "step2 cc"
cc -c s3.gen.c -o s3.o 2>s3.cc.err || { print -r -- "FAIL step2"; sed -n '1,14p' s3.cc.err; exit 1; }

print -r -- "step3 link -lclang (with -Wl,-rpath: Apple's dylib is @rpath)"
cc s3.gen.c -L$CLIB -lclang -Wl,-rpath,$CLIB -o s3.out 2>s3.link.err \
  || { print -r -- "FAIL step3"; sed -n '1,14p' s3.link.err; exit 1; }

print -r -- "step4 run, TWICE"
./s3.out >s3.r1.out 2>s3.r1.err; r1=$?
./s3.out >s3.r2.out 2>s3.r2.err; r2=$?
print -r -- "  run1 rc=$r1"
sed 's/^/  1| /' s3.r1.out; sed 's/^/  1| /' s3.r1.err
print -r -- "  run2 rc=$r2"
sed 's/^/  2| /' s3.r2.out; sed 's/^/  2| /' s3.r2.err

# ---- the verdict, from the two runs' bytes ----
get() { sed -n "s/.*$2 //p" "$1" | head -1; }
c1=$(get s3.r1.err 'C_SAW HANDLE'); b1=$(get s3.r1.out 'BEND_HANDLE')
c2=$(get s3.r2.err 'C_SAW HANDLE'); b2=$(get s3.r2.out 'BEND_HANDLE')
two1=$(get s3.r1.out 'TWO_LIVE_DIFFER')
p0=$(get s3.r1.out 'PLANT_0'); p5=$(get s3.r1.out 'PLANT_5')
d5=$(get s3.r1.out 'DISARM_5_AGAIN'); p7=$(get s3.r1.out 'PLANT_7')
ok=0
row() { if [[ "$2" == "$3" ]]; then print -r -- "PASS $1  ($2)"; ok=$((ok+1));
        else print -r -- "FAIL $1  got=$2 want=$3"; fi }

print -r -- ""
print -r -- "== the rows, and what a DISARMED row would look like =="
row "SAME_OBJ   run1 C reading == Bend reading" "$c1" "$b1"
row "SAME_OBJ   run2 C reading == Bend reading" "$c2" "$b2"
row "TWO_RUNS   the two runs' addresses DIFFER" \
    "$([[ $c1 != $c2 ]] && print differ || print same)" "differ"
row "TWO_LIVE   two live handles differ in-process" "$two1" "1"
row "PLANT      set 0 -> get 0"  "$p0" "0"
row "PLANT      set 5 -> get 5"  "$p5" "5"
row "PLANT      set 7 -> get 7"  "$p7" "7"
row "DISARM     set 5 twice agrees" "$d5" "$p5"
print -r -- ""
print -r -- "$ok/8 rows pass"
print -r -- "ADDRESSES  run1 C=$c1  run2 C=$c2   (these are the numbers that must NOT be pinned)"
exit $((ok == 8 ? 0 : 1))