# MANIFEST.tsv: the restore column names files that no longer exist

Scope: `.agents/slop/oracles259/` only. `oracles/` was **not** written, renamed, or moved; no
commit, no `git add`/`git mv`. Every number below is a measurement with the command that made it.

Artifacts in this directory:

| file | what it is |
|---|---|
| `verify.out` | re-verification of the `sha256` column (`verify.py`) |
| `prove.out` | 10 rows, both restore forms, run verbatim (`prove.py`) |
| `measure.out` | line endings, `git diff --numstat`, byte accounting, debt (`measure.py`) |
| `debt.rows` | the 258 rows whose `path` is the OLD name and does not exist at HEAD |
| `build.py` / `verify.py` / `prove.py` / `measure.py` | the instruments |

The pins: pre-rename tree `b504abf77` — measured, `git ls-tree -r --name-only b504abf77 --
oracles/ | grep -c '\.txt$'` = **259**, so all OLD names live there; current `HEAD` = `705e7a644`
(one `.txt`, 277 `.rows`); `git merge-base --is-ancestor b504abf77 HEAD` = YES. (`b504abf77` is the
verified tree, not the rename commit's parent — `dcd97943e`'s parent is `21f98c20`.)

## 1. Re-verified digest column (did not trust the 258)

Claim under test: `sha256 == sha256(git show b504abf77:<path>)` for every row.
Instrument `verify.py` (`git cat-file blob b504abf77:<path>` per row, `hashlib.sha256`).

```
rows            : 259
matches         : 258
mismatches      : 0
empty-blob skip : 1
absent@b504abf77: 0
```

The `.txt` count on disk at `HEAD` is 1, so a `git cat-file` miss is itself a finding: **all 259
OLD paths resolve at `b504abf77`, 0 diverge.** The single skip is `oracles/rows-bd.txt`, bytes
`0`: its recorded digest is `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`,
which is `sha256(b"")` exactly, so it is a skip only because a non-empty comparison is undefined —
it is not a mismatch. **The 18 wrong rows the manifest used to carry are gone: mismatches = 0.**

## 2. The fix: chose (a), an added `restore_at_HEAD` column — the record keeps the OLD path

`restore` is pinned to the PRE-RENAME tree and keeps the OLD path:

```
git cat-file blob $(git rev-parse b504abf77:oracles/AFTER-pins.txt) > oracles/AFTER-pins.txt
```

`restore_at_HEAD` names the CURRENT path and restores it from `HEAD`:

```
git cat-file blob $(git rev-parse HEAD:oracles/AFTER-pins.rows) > oracles/AFTER-pins.rows
```

**Why (a):** the manifest is a record of 259 files and their bytes. Option (b) ("one command that
works at both revisions") **cannot exist here, because the rename changed the NAME and not only the
revision** — `git rev-parse HEAD:oracles/AFTER-pins.txt` fails at HEAD, so a revision parameter
alone restores nothing at HEAD. To make (b) work you must also put the new name inside the command,
which *is* option (a) with the mapping hidden inside a shell string instead of a readable column.
**What (a) costs that (b) would have bought:** two commands per row instead of one, and a caller must
pick the column for the revision they are restoring from. **What (a) protects that editing `restore`
would lose:** the old path stays literal in both `path` and `restore`, so the manifest records both
what the file *was* and what it *is* — *"a record you update to match reality is not a record."*
`oracles/schedule-bodies/rows-bd.txt` is renamed like the rest; the leftover empty file is
`oracles/rows-bd.txt`, whose two columns are necessarily identical.

`build.py` regenerates the file from the HEAD blob via `csv` with `newline=""` and
`lineterminator="\r\n"`. The old→new mapping is git's own: `git diff --name-status --find-renames
b504abf77 HEAD -- oracles/` → **258 `R100`** (exact-content renames; no `R0xx`, no duplicate new
paths), plus the one un-renamed empty file = 259.

## 3. Proof: 10 rows, both forms, run verbatim

`prove.py` selects 10 rows (one non-empty per OLD→NEW extension, then fillers), and for each runs
both manifest commands **exactly as written** in a fresh scratch tree, with `GIT_DIR` pointed at
this repo so the redirection lands in the scratch. Result (`prove.out`):

```
OLD @ b504abf77                   NEW @ HEAD                        sha256
oracles/AFTER-pins.txt            oracles/AFTER-pins.rows           MATCH
oracles/arglit/baseline.txt       oracles/arglit/baseline.md        MATCH
oracles/backward/oracle-cg.txt    oracles/backward/oracle-cg.err    MATCH
oracles/main_rows.txt             oracles/main_rows.tsv             MATCH
oracles/usb-arith-rows.bend.txt   oracles/usb-arith-rows.bend       MATCH
oracles/dd-const-oracle.txt       oracles/dd-const-oracle.rows      MATCH
oracles/jit-prune-oracle.txt      oracles/jit-prune-oracle.rows     MATCH
oracles/opssugar-bd.txt           oracles/opssugar-bd.rows          MATCH
oracles/rows-gate-py.txt          oracles/rows-gate-py.rows         MATCH
oracles/tc-rows-bend.txt          oracles/tc-rows-bend.rows         MATCH

PROVEN 10/10
```

**10/10.** Both forms restore a **non-empty** blob whose sha256 equals the manifest's digest. The
empty row is excluded from the 10 so the claim "non-empty" is exact; its two forms both emit the
empty blob (digest `e3b0…7852b855`), checked separately. Independently,
`restore_at_HEAD`'s target exists at HEAD for **259/259** rows and `restore`'s target exists at
`b504abf77` for **259/259**.

## 4. Line endings: the file is still CRLF; the diff is exactly the column edit

`measure.py` reads bytes (`MANIFEST.read_bytes()` and `git show` captured as bytes):

```
             CRLF   bare-LF   bytes
HEAD         260      0       78173
WORK         260      0      106424
nul byte present? no

DIFF  numstat: 260  260  .agents/slop/oracles259/MANIFEST.tsv
      stat   : 1 file changed, 260 insertions(+), 260 deletions(-)

BYTE ACCOUNTING  delta=28251  appended+tab=26940  rev_growth=1295  header=16  sum=28251  MATCH
```

- **CRLF preserved:** 260 CRLF, **0 bare-LF**, no NUL. A naive `read_text()`/`write_text()` rewrite
  would have translated `\r\n`→`\n` and shown the same line count with every line-ending byte
  changed; this file did not move a single line-ending byte.
- **`numstat` = 260/260.** Every line changed because **a column was appended to all 259 data rows
  and to the header** — a column cannot be added to a subset without producing ragged TSV, so the
  healthy row (`oracles/rows-bd.txt`) necessarily receives it too (identically to `restore`). 260 is
  the *total* line count of the file, so **no line was touched beyond the intended edit** — there is
  no other changed line for a CRLF rewrite to hide in.
- **Byte accounting MATCH** is the surgical proof: the file grew by exactly
  `Σ(len(restore_at_HEAD)+1) [appended field + tab] + 5×259 [HEAD→b504abf77] + 16 [header field]`.
  Nothing else changed. (`git diff --check` prints "trailing whitespace" on each added line; that is
  the `\r` of the CRLF, present in the HEAD blob too, not new content.)

## 5. The manifest's debt: 258 of 259 rows name a path absent at HEAD

Instrument: `git cat-file -e HEAD:<path>` per row (`measure.py`); list in `debt.rows`.

```
rows whose `path` does not exist at HEAD : 258 / 259
the one that DOES exist                   : oracles/rows-bd.txt   (bytes 0)
```

258/259 is the debt. It is the exact rename set (`git diff --name-status --find-renames` = 258
`R100`), and `restore_at_HEAD` is the field that pays it: the manifest now says both what the file
was (`path`/`restore`) and where it is (`restore_at_HEAD`).

## Note: the generator cannot be re-pointed

`.agents/slop/oracles259/manifest.py` built this file from a census taken **before** the rename, when
the paths were `.txt`; run today its census sees the `.rows` names, so it can no longer reproduce the
old-path column. It was left untouched rather than updated to match reality — the same rule as above.
Every other reader of this file (`checks/`, `.agents/slop/txt259/`, `.agents/slop/txtexec/`) uses
`csv.DictReader(delimiter="\t")`, so the added column is inert; no positional 7-column reader exists.
