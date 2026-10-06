# COLDNESS — raw measurements (work in progress)

Unit: `.agents/slop/coldness/`. **Nothing committed.** Owns this directory,
`agent-core.md` §2's table, and `COLDNESS.md`. No `.bend` touched.

Compiler: Bend 2.0.34 via `./bin/bend`.

## 1. WHAT THE GUARD MEANS BY `COLD` — quoted from `.agents/slop/substrate-check.sh`

Lines 199-206, HALF 1, the `bend` route:

```zsh
  bend) n_bend=$((n_bend+1))
    v=$(perl -e 'alarm 300; exec @ARGV' "$BEND" "$f" --check-only 2>&1 | head -1)
    if [ "$v" = "ALL PROOFS CHECK" ]; then
      print -r -- "WARM        $f  ($lines lines)  [$tag]"
    else
      print -r -- "COLD        $f  ($lines lines)  [$tag]  :: $v"
      fail=$((fail+1))
    fi ;;
```

So `COLD` is **exactly**: the first line of `bend --check-only <f>` (stdout+stderr
merged) is not the literal string `ALL PROOFS CHECK`. It is a **per-file,
string-equality** verdict. It is NOT an exit code (line 200 discards `$?`), and
it says nothing about importers.

Two neighbouring verdicts that are NOT `COLD` (lines 171-174, 196-198):

```zsh
  if [ "$lines" -eq 0 ] || [ "$bytes" -eq 0 ]; then
    print -r -- "EMPTY       $f  ($lines lines, $bytes bytes)  <-- THE VERDICT IS MEANINGLESS"
  ...
  none) n_none=$((n_none+1))
    print -r -- "NO INSTRUMENT  $f  ($lines lines)  :: $why -- **NOT JUDGED, AND NOT COLD**"
```

Zero-argument invocation (lines 257-263) exits 3 after printing
`REFUSED: no files given.` — so a bare `zsh substrate-check.sh` is not a
measurement and cannot be quoted as `COLD 0`.

`BAD`/`UNRESOLVED` (lines 434-445) are HALF 2, a different question: does every
`<alias>.<name>` this file references exist in a module this file imports.
`BAD` is a count of deduped problem SITES across the whole population, not files.

## STATUS

- [x] quoted COLD from the code
- [ ] re-measure the denominator
- [ ] per-file table
- [ ] one coldness number + definition