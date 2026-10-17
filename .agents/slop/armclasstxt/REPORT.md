# `no-txt.py`'s three HARD `.txt` — classification and verdict

MEASURED 2026-10-17T00:15:21Z at HEAD `9122a0d28c60055d45c07566715823af2f208680`, and
RE-MEASURED 2026-10-17T00:16:34Z at HEAD `7a826eb70a4599392e229b750782a5e9d76a2f24`
(the tree moved under this unit mid-session; both readings are below and they AGREE).

**NOTHING WAS RENAMED AND `checks/no-txt.py` WAS NOT EDITED.** Read-only, plus two files written
here. `.venv/bin/python` only; no `bend`, no `gates/*`, no `differ.py`, no corpus loop.

## 1. THE DENOMINATOR

`checks/no-txt.py` was run twice, unpiped, `env -u GIT_INDEX_FILE`:

| reading | rc | HARD | excused | total owned `.txt` |
|---|---|---|---|---|
| 00:15:21Z @ `9122a0d2` | **1** | **3** | **181** (176+2+1+2) | **184** |
| 00:16:34Z @ `7a826eb7` | **1** | **3** | **181** (176+2+1+2) | **184** |

The excused rows, verbatim from stdout — 5 generators are tried, **4** print (the fifth,
`.agents/slop/skipexit/repro.py`'s pre-fix lane, matched 0 of this tree's files, so it prints nothing):

```
  176 `.txt` EXCUSED: `checks/differ.py`'s graphcmp artifacts + `.tmp.` staging
    2 `.txt` EXCUSED: `.agents/slop/figure2/plant.py`'s forced plant summaries
    1 `.txt` EXCUSED: `.agents/slop/txtexec/rename.py`'s deliberate 0-byte remnant
    2 `.txt` EXCUSED: `checks/dup-census.py`'s `lanes` CACHE (`.txt` mandated by its own glob)
```

So the question asked is **3 of 184 owned `.txt`**, 1.6% of the population, and **all 3 sit in one
directory**: `.agents/slop/armclass/`. That directory's full extension census (14 files) is
`3 txt · 3 tree · 3 stage · 2 py · 1 out · 1 json` — the 3 `.txt` are **21% of the unit's own files**.

## 2. ARE THEY TRACKED, AND WHO READS THEM

**Tracked in HEAD — yes, all three, under BOTH HEADs** (`git ls-tree -r HEAD`, and
`git cat-file -e HEAD:<path>` per path; the index was never consulted, per the stale-index rule).
They were committed by a concurrent unit, not by this one.

**Consumers: NONE.** This is the load-bearing negative, so it was measured three ways, not asserted:

1. `git grep -n -I -e 'table-1837-frozen' -e 'table-now.txt' -e 'armclass/msg.txt' HEAD -- . ':(exclude)references' ':(exclude)tinygrad' ':(exclude)test'`
   over the whole **committed** tree: **2 hits, both inside `msg.txt:45-46`.** Nothing else.
2. `rg` over committed `.md` anywhere in the tree: **0 hits.**
3. `rg 'slop/armclass'` over the whole working tree excluding `tinygrad|references|test|node_modules|.venv`:
   **2 hits, both in `checks/index-arm-gate.py:37` and `:211`, and both name `plant-stat.py` — a DIFFERENT
   file in that directory, and not a `.txt`.**

`armclass/msg.txt` is named by **nothing at all**. The only two citations of the other two are
**prose inside the third** — `msg.txt` line 45 says `table-1837-frozen.txt` is "the 32-row
classification" and line 46 says `table-now.txt` is "the post-state". Nothing opens either file.

**EXCLUSIONS, STATED SO THEY ARE NOT READ AS SWEEPS:** `references/`, `tinygrad/` and `test/` were
excluded from searches 1 and 3 — they are `no-txt.py`'s own `SKIP`/`SKIP_PREFIX` (not this project's
files), and `test/` is upstream tinygrad's suite. `checks/txt-owners.py` and `checks/oracle-txt-census.py`
were READ, not run: the latter is hard-scoped to `oracles/**.txt` (`rglob("*.txt")`), so **no live
instrument classifies the SHAPE of any file in `.agents/slop/armclass/`** — there is no existing
classifier verdict that could contradict or support this one.

## 3. PER-FILE, WHAT THE BYTES ACTUALLY ARE

### 3a. `.agents/slop/armclass/msg.txt` — 3335 B, 46 lines — **PROSE**

Commit-message prose. It is **byte-identical to an already-committed commit message**:

```
$ git log -1 --format=%B 0275ff0ff | diff - .agents/slop/armclass/msg.txt
46,47c46
< classification, `table-now.txt` the post-state, `idx.stage`/`head.tree` the frozen census.
<
---
> classification, `table-now.txt` the post-state, `idx.stage`/`head.tree` the frozen census.
\ No newline at end of file
```

The only differences are git's trailing blank line and the missing final newline. `0275ff0ff` is
`index-arm: name EMPTIED, the fifth shape, and measure that a bare commit truncates` — its subject is
`msg.txt` line 1. **The file is a verbatim copy of a message git already holds immutably**, so
`git log -1 --format=%B 0275ff0ff` reproduces it exactly. Prose is `.md`.

### 3b. `.agents/slop/armclass/table-1837-frozen.txt` — 8798 B, 100 lines — **ROW DUMP**

Produced by redirecting `classify.py` (same directory) stdout. Its structure, measured:

| lines | content |
|---|---|
| 1–3 | `#` header: blob_sha selfcheck, `HEAD eae9ccb53f1a TREE 7347 INDEX 7968 ARMED 32`, and the column legend |
| 4–35 | **32 data rows** — `3 deletion` + `29 stale`, which **agrees with the `ARMED 32` its own line 2 prints** |
| 36 | blank |
| 37–100 | 64 lines: `PROVABLE-WRONG  <shape>  <path>` then an indented `-> reason`, for the same 32 |

`3+32+1+64 = 100`. Every one of the 32 rows reads `PROVABLE-WRONG`. It is **space-aligned and ragged,
not TSV** (columns are `{shape:9} {od:7} {sz:>7}  {h[:12]:14} …`), so `.tsv` is wrong; it is a table of
one row per path with a declared column legend, so `.out` (captured stream) would be the weaker fit —
compare the sibling `plant-stat.out`, which IS a genuine narrative console log and is already `.out`.
Row dump → `.rows`.

### 3c. `.agents/slop/armclass/table-now.txt` — 269 B, 4 lines — **ROW DUMP WITH ZERO ROWS**

Same generator, same shape, `ARMED 0`. 3 `#` header lines + the single blank line `classify.py:97`
emits. `tail -c 40 | od -c` confirms the file ends `VERDICT\n\n` — **there is nothing after the blank.**

**This is a MEASURED empty table, not a partial read** (the exact trap AGENTS.md records for `elf.bend`'s
`246`), and the emptiness is internally consistent: its line 2 reads `INDEX 7979` against `TREE 7347`, so
632 index entries are not in HEAD, and `classify.py:79` defines `foreign` as `set(idx) - set(head)` filtered
by `idx[p] != EMPTY` — those 632 are empty-blob entries, so `deletion=0, stale=0, foreign=0` and the table
has no rows by construction. It is the evidence for the commit's claim "at 18:45 `ARMED 0`", so **rename,
do not delete**. Row dump → `.rows`.

## 4. EXCUSE-ABLE, OR A GENUINE VIOLATION?

**Genuine violations. All three. And the carve-out mechanism is right and correctly declined.**

`no-txt.py` excuses a `.txt` only when a **generator's `declared()` set, loaded by path**, contains it.
Neither producer declares any of these three:

- `.agents/slop/armclass/classify.py` — **prints to stdout only.** `rg 'declared|\.txt|write_text|open\(|write_bytes'` on it returns **nothing**. The filename existed only in a shell redirect, so no generator can ever declare it.
- `.agents/slop/armclass/plant-stat.py` — writes **only into its own `tempfile.mkdtemp()` sandbox** (`A/keep.py`, `A/gone.py`) and into a copied `.git/index`. It writes no project file at all, and it does not produce any of the three.
- `msg.txt` has **no generator**: it is prose, and its content is already in git.

So adding a `declared()` to `classify.py` would be **forging a declaration for a name that script never
chose** — which is the "a second copy of the list is a contract with no generator" failure the docstring
and AGENTS.md's Doctrine 1 exist to prevent. **The carve-out is unavailable here, correctly.**

## 5. VERDICT

**`no-txt.py` is NOT mis-classifying. These are 3 real doctrine violations and they need renaming.**

The rule is `".txt` is NEVER an extension this project uses", enforced by a gate whose only carve-out is
a generator's imported `declared()`. These three files were created 2026-10-16 18:46–18:47, tracked into
HEAD, and declared by no generator — the exact shape of the defect the gate exists for. The gate's
negative is also load-bearing and correct: 181 excused files stay excused, and its rc is 1 with 3 named
paths out of 184.

## 6. THE RENAMES, AND EXACTLY WHO CONSUMES EACH PATH

Each is a pure `git mv` plus the citation edits listed. **Zero live instruments consume any of them**, so
none of these renames can break a gate, an oracle, or a sha256 pin.

| # | from | to | consumers of the OLD path that must move |
|---|---|---|---|
| 1 | `.agents/slop/armclass/msg.txt` | `.agents/slop/armclass/msg.md` | **none** |
| 2 | `.agents/slop/armclass/table-1837-frozen.txt` | `.agents/slop/armclass/table-1837-frozen.rows` | **one prose line**: `.agents/slop/armclass/msg.txt:45` — which is rename #1's target, so it becomes `msg.md:45` |
| 3 | `.agents/slop/armclass/table-now.txt` | `.agents/slop/armclass/table-now.rows` | **one prose line**: `.agents/slop/armclass/msg.txt:46` → `msg.md:46` |

**ONE HONEST CAVEAT, AND IT IS NOT A CONSUMER.** The identical prose is **already frozen in git** as
commit `0275ff0ff`'s message, where it will name `table-1837-frozen.txt` and `table-now.txt` after those
paths move. That is a **historical citation, not a reader** — no code executes a commit message, and
`AGENTS.md` forbids amending or rebasing to fix it. `checks/oracle-txt-census.py`'s own vocabulary
already has this case: a reader whose path has moved is `STALE` if the sub-tree survived and `ABSENT` if
only the basename is in common. Either way the correct handling is **leave it**, and it is recorded here
so a later census does not read it as a live break.

**OUT OF SCOPE BUT ADJACENT, FOR THE RECORD:** `checks/index-arm-gate.py:37` and `:211` cite
`.agents/slop/armclass/plant-stat.py` twice. That file is **already `.py`** and is not part of this
verdict; it is named because it is the only committed-tree citation of anything in this directory, and a
reader skimming `rg armclass` should not mistake it for one of the three.

## 7. WHAT WAS NOT DONE

No rename, no edit to `checks/no-txt.py`, no commit, no `jj` mutation, no `git add`. This directory holds
`.rows` and `.md` only — no `.txt` was created, which is the one thing this report could have failed at by
accident.