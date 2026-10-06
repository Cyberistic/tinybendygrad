#!/bin/sh
# one.sh <file.bend> <outdir> -- check and run exactly ONE bend file.
#
# NEVER read bend's exit status. `--check-only` EXITS 1 ON A CLEAN FILE: dtype.bend
# has 14 permanently unfilled laws and one agent lost a 10-minute retry loop to it.
# The verdict is bend's FIRST DIAGNOSTIC LINE, and WHICH STREAM IT ARRIVES ON DEPENDS ON
# THE VERDICT ITSELF (measured): success prints to STDOUT, failure to STDERR. So the
# verdict is read from `check.err` and falls back to `check.out`. That same split is what
# makes `rows` countable: the error block is on stderr, so everything on stdout is a
# proof row except bend's own two success messages, which are subtracted explicitly.
#
# WHY THE RUN IS REPEATED. A ROW COUNT IS NOT A SETTLED FACT. bend's machine stack
# overflows on ~1 run in 20 and can then print nothing, so a 0-ROW RESULT IS
# INDISTINGUISHABLE FROM "NOT STARTED". Worse, and measured on
# `tinybendygrad/runtime/support/elf.bend` in this repo: bend printed 353 rows on one run
# and 331 on the next -- same file, same command, no edit in between (mtime 14:59:55, both
# runs after 16:00). A single run is therefore NOT evidence for a row count, and a harness
# that reports one is reporting a coin flip.
#
# So the run repeats until two consecutive attempts AGREE, and a ZERO-row attempt is NEVER
# allowed to BE the agreement: 0 is retried to the cap, because 0 can mean "no main in
# scope" and "did not start" and nothing on the wire distinguishes them. What is reported
# is the MODAL count plus how many distinct counts were seen, so a file bend disagrees
# about is labelled rather than quietly reported at whatever it said last.
#
# Prints one TAB-separated record (see the printf at the end):
#   rows <TAB> attempts <TAB> distinct-counts <TAB> void-attempts <TAB> verdict
# `-` stands in for an absent verdict, so the record always has five fields: a file bend
# printed NOTHING for emits an empty verdict, and a consumer that splits on tabs would
# otherwise silently lose the last field.
#
# Artifacts land in $outdir, never in the tree: nothing here is opened for writing under
# tinybendygrad/ or tinygrad/.
set -u
# $BEND_ROOT points this at a COPY of the tree, which is how a negative control is run
# without ever opening the live tree for writing. Spelled as an `if` rather than
# `${BEND_ROOT:-...}` because the command substitution inside that form is evaluated
# eagerly by this /bin/sh and silently sent a control run back to the live repo.
if [ -n "${BEND_ROOT:-}" ]; then cd "$BEND_ROOT"; else cd "$(dirname "$0")/../.."; fi

f="$1"; d="$2"; A="${ONE_ATTEMPTS:-6}"
mkdir -p "$d"; : > "$d/good.txt"; : > "$d/void.txt"

n=0; prev=""
while [ "$n" -lt "$A" ]; do
  n=$((n + 1))
  ./bin/bend "$f" --check-only >"$d/check.out" 2>"$d/check.err"
  ./bin/bend "$f"              >"$d/run.out"   2>"$d/run.err"
  rows=$(grep -vc -e '^$' \
               -e '^ALL PROOFS CHECK$' \
               -e '^Use --verdict for mathematical validity\.$' "$d/run.out")
  # Both check streams silent means bend died; a stack overflow means the run was void.
  # A void attempt is recorded SEPARATELY: it can leave partial rows behind, so counting
  # it would put a truncated total into the mode. Measured: renderer/amd/generate.bend
  # overflows ~1 run in 6 (see the GA4 block in notes/bend2-constraints.md), and a sweep
  # that lets void attempts vote reports a truncated row count as if it were settled.
  if ! { [ -s "$d/check.err" ] || [ -s "$d/check.out" ]; } ||
     grep -q 'machine stack overflowed' "$d/run.err"; then
    echo "$rows" >> "$d/void.txt"
    continue
  fi
  echo "$rows" >> "$d/good.txt"
  [ "$rows" -gt 0 ] && [ "$rows" = "$prev" ] && break   # 0 never counts as agreement
  prev="$rows"
done

# No settled attempt at all: say 0 and say so via attempts, never invent a row count.
if [ -s "$d/good.txt" ]; then
  tally=$(sort "$d/good.txt" | uniq -c | sort -rn | head -1)
  rows=$(echo "$tally" | awk '{print $2}')
  distinct=$(sort -u "$d/good.txt" | wc -l | tr -d ' ')
else
  rows=0; distinct=1
fi
printf '%s\t%s\t%s\t%s\t%s\n' "$rows" "$n" "$distinct" \
  "$(wc -l < "$d/void.txt" | tr -d ' ')" \
  "$( { cat "$d/check.err" "$d/check.out" | grep -m1 . || echo '-'; } | tr -d '\r')"
