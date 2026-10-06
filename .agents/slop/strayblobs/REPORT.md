# `.agents/slop/strayblobs/REPORT.md` — four stray blobs in the port, and the gate that never looked

Measured 2026-10-06 ~13:44. Every number below carries the command or file that produced it.
Instruments: `.agents/slop/strayblobs/analyze.py`, `match_history.py`, `delete.py`
(all run under `.venv/bin/python`).

## 0. TL;DR

| blob | bytes | lines | what it is | tracked at | readers in code |
|---|---:|---:|---|---|---:|
| `ops.staged-blob-36145` | 286,404 | 6297 | `ops.bend` **MUTANT** (M1: content→LENGTH) | `07cb5a85a` | 0 |
| `ops.staged-blob-64022` | 287,092 | 6306 | `ops.bend` **pristine mirror** | `07cb5a85a` | 0 |
| `ops.staged-blob-66397` | 286,321 | 6297 | `ops.bend` **MUTANT** (M4: content→ALWAYS) | `07cb5a85a` | 0 |
| `ops.staged-blob-97648` | 287,092 | 6306 | `ops.bend` **pristine mirror** (byte-identical to `64022`) | `07cb5a85a` | 0 |

They are the leftovers of `.agents/slop/blob-intern-mutate.py` (now deleted), a mutation harness
that staged a mirror of `ops.bend` beside it via `staged_mut.Staged(REAL, "blob")`. **All four
working-tree files are deleted (`os.remove`); the orchestrator's `git rm --cached` list is in §4.**
The 138-`.bend` census is unchanged at 138 (they were never counted); the port's total file count
fell 152 → 148.

## 1. WHAT THEY ARE, AND HOW THEY GOT THERE

`analyze.py` — hashes, sizes and line counts against the live file:

| file | bytes | vs live `ops.bend` (430,013 B / 8729 lines) |
|---|---:|---|
| `ops.bend` (live, = HEAD) | 430,013 | — |
| `ops.staged-blob-36145` | 286,404 | **OLDER**, 6297 lines, 260 lines only-in-blob |
| `ops.staged-blob-64022` | 287,092 | **OLDER**, 6306 lines, 259 only-in-blob |
| `ops.staged-blob-66397` | 286,321 | **OLDER**, 6297 lines |
| `ops.staged-blob-97648` | 287,092 | **OLDER**, byte-identical to `64022` |

**They are OLDER snapshots, not newer ones.** Live `ops.bend` is 430,013 B; the blobs are ~287 KB.
`64022`/`97648` are byte-equal to committed `ops.bend` at **149** revisions in history — newest
contributing revision **`4048afdcb` (2026-10-04)**, where `ops.bend` was exactly 287,092 B. So the
snapshot is the Oct-4 ops.bend; the file has since grown by ~143 KB.

**And two of the four are MUTANTS, not snapshots.** `difflib` of `64022` vs each shows exactly one
site changed — the `eq_arg.ABlob` arm, the same arm the harness's `MUTS` table mutates:

```
64022:  case ABlob{y1}: eq_u32(bs, y1)                    # pristine
36145:  case ABlob{y1}: U32.is_eq(List.length(&2,U32,bs), List.length(&2,U32,y1))   # = M1 LEN
66397:  case ABlob{y1}: True{}                            # = M4 ALWAYS
```

The `M1`/`M4` labels are `git show 07cb5a85a:.agents/slop/blob-intern-mutate.py:116-119`. So
`36145`/`66397` were killed **between** `g.write(mutant)` and the restore/unlink; `64022`/`97648`
are the pristine mirror, byte-identical to the committed `ops.bend` of the day.

### `git log --follow` — which commit added each

`--follow` **lies here**: rename detection walks the basename's history back through a rename into
`ops.bend` itself, so it reports every file as added by
`b8ff89be5 (2026-09-30) uop/ops.bend: the arena works, so the 30k-line plan stands`. The real
adding commit, from `git log --diff-filter=A --name-status` (no `--follow`):

> **all four** added in **`07cb5a85a` (2026-10-04 13:48:17 +0300)**
> `portexec: THE PORT'S C RAN. 2 of 227 gate rows are execution, not text.`

Its message never names the blobs. They were swept into that commit by a working-copy-wide add
while four killed harness runs had left them in the tree. Each was added exactly once and never
modified again (`git log --name-status -- <path>` = one `A` line each).

## 2. THE TOOL — found in history; gone from the working tree

The writer is the only expression of `<name>.staged-<tag>-<pid>` with `tag = "blob"`:

```
.agents/slop/blob-intern-mutate.py:199   with S.Staged(REAL, "blob") as g:
.agents/slop/blob-intern-mutate.py:62    REAL = ROOT / "tinybendygrad" / "uop" / "ops.bend"
.agents/slop/staged_mut.py:241           self.path = self.live.parent / ("%s.staged-%s-%d" % (self.live.stem, self.tag, os.getpid()))
.agents/slop/staged_mut.py:252-254       def __exit__: if ...exists(): self.path.unlink()
```

(those line numbers are the versions at `07cb5a85a`). The mirror is written from
`jj --ignore-working-copy file show -r @`, asserted `sha256(mirror)==sha256(live)`, and **unlinked
in `__exit__`** — so a file with a PID in its name is a run that was **KILLED before `__exit__`**.
`Staged.__enter__` even refuses to start if a leftover exists
(`"%s exists -- a previous run was killed; remove it"`), so each PID is a distinct killed process.
`64022`/`97648` died before the first mutation; `36145`/`66397` died mid-mutation.

**Both files are DELETED from the working tree**, by the sweep commit
`371cc64c9` (`.agents/slop/staged_mut.py` and `.agents/slop/blob-intern-mutate.py` last exist at
`0056b7845`, recoverable with `git show 0056b7845:<path>`). No harness in the tree calls
`Staged(..., "blob")` today (`grep -rn 'Staged([^)]*blob' .agents/slop/` = no rows).

## 3. NOTHING READS THEM — 0 of 4 live readers

`git grep -l -F <name>` over the tree returns only **audit artifacts**, never a reader:

- `.agents/slop/{residue/000-the-residue.md,residue/003-disagreements.md}` — classify them as `COPY`
- `.agents/slop/{emptyblob/summary.json,slopcopies/CITATIONS.tsv,canrun/census/*.out,bendsuite/git-status-before.rows,shadowtrees/REPORT.md}` — censuses/reports

No `.py`/`.sh`/`.bend`/`.mjs` under `checks/`, `gates/`, `tinybendygrad/`, `bin/`, `tools/` or
`.agents/` names any of the four (`grep -rIl` = no rows). **0 live readers out of 4.** The one
instrument that knows the *pattern* is `checks/sweep.py:452,705`, and it names a *fifth* PID
`ops.staged-blob-24323` as a tokenizer example — not a reader of these four.

## 4. DELETED, WITH THE REDUNDANCY PROOF

`delete.py` refused to delete anything until, per file, (1) the exact bytes are committed under the
same path at `07cb5a85a` (`git cat-file -e 07cb5a85a:<path>`), and (2) the blob object is in the
store. All four passed; `git status --porcelain` was empty for all four (working tree == HEAD), so
no uncommitted byte was lost. Then `os.remove`:

```
D tinybendygrad/uop/ops.staged-blob-36145
D tinybendygrad/uop/ops.staged-blob-64022
D tinybendygrad/uop/ops.staged-blob-66397
D tinybendygrad/uop/ops.staged-blob-97648
```

**Restore paths (the "restoring commit" for each) — nothing here is the only copy:**

| blob | committed at | byte-equal to a historical `ops.bend`? | restore |
|---|---|---|---|
| `-36145` | `07cb5a85a` | no (a mutant; never was committed ops.bend) | `git show 07cb5a85a:tinybendygrad/uop/ops.staged-blob-36145`; bytes also in `.agents/slop/{arghalf,loopfix}/tree/…` |
| `-64022` | `07cb5a85a` | **yes, 149 revisions**, newest `4048afdcb` | `git show 4048afdcb:tinybendygrad/uop/ops.bend` |
| `-66397` | `07cb5a85a` | no (a mutant) | `git show 07cb5a85a:tinybendygrad/uop/ops.staged-blob-66397`; bytes also in `.agents/slop/{arghalf,loopfix}/tree/…` |
| `-97648` | `07cb5a85a` | **yes, 149 revisions**, newest `4048afdcb` | `git show 4048afdcb:tinybendygrad/uop/ops.bend` |

Two are recoverable as a named historical `ops.bend`; the two mutants are recoverable as the
committed staged-blob files and as shadow-tree copies. `git rm --cached` list for the orchestrator:

```
git rm --cached tinybendygrad/uop/ops.staged-blob-36145 tinybendygrad/uop/ops.staged-blob-64022 tinybendygrad/uop/ops.staged-blob-66397 tinybendygrad/uop/ops.staged-blob-97648
```

## 5. CENSUS EFFECT — the 138 never counted them (doctrine 1)

The **138 `.bend` files** figure is `find tinybendygrad -name '*.bend' | wc -l`
(`.agents/slop/coldness/COLDNESS.md:99`) — a **suffix glob**, so an extension-less
`ops.staged-blob-*` is invisible to it. Re-measured after deletion: `.bend` on disk is **138 both
before and after**; total files under `tinybendygrad/` fell **152 → 148**.

| instrument | population declared by | saw the blobs? |
|---|---|---|
| `find tinybendygrad -name '*.bend'` (the 138) | suffix glob | **no** |
| `checks/substrate.py:114-126` `discover()` | `os.walk` **+ `endswith(POP_SUFFIXES)`** | **no** — and it says so: *"The `*.staged-*` scratch copies and `*.mut` mutants do not end in one of these, so they are excluded by the same rule that includes the real files"* |
| `checks/sweep.py` | `os.walk` over `SLOP`/`RUNS` only (`.agents/slop`, `runs`) | **no** — never walks `tinybendygrad/` |
| `checks/no-strays.py` | `ROOT.iterdir()` top-level root files only | **no** — root scope |
| `.agents/slop/emptyblob/summary.json`, `slopcopies/CITATIONS.tsv`, `shadowtrees/REPORT.md`, `residue/*` | whole-repo walks | **yes** (as `JUNK-TEMP`/`COPY`) |

**The doctrine-1 statement:** the only two instruments that walk `tinybendygrad/` — the `.bend`
census and `substrate.py` — both filter by suffix. `substrate.py` uses `os.walk`, which *could* see
any file, and then throws the visibility away with `endswith(POP_SUFFIXES)`. So the four sat in the
port, tracked, counted by no `.bend`-suffixed rule, and visible only to `.agents/slop/` audits that
have no authority to touch `tinybendygrad/`.

## 6. THE GUARD THAT SHOULD HAVE CAUGHT IT — none had this population

`checks/no-strays.py` is the stray-file gate, and **it could not have fired**:

- its population is `ROOT.iterdir()` — **top-level root files only** (`root_files()`, line 85);
  `tinybendygrad/uop/` is not in it. Re-run today: `no-strays: 14 files at the root, 0 to explain`,
  rc=0.
- it even *knows the shape* — `SCRATCH_NAME` (line 73) includes `\.staged-(mem|blob)-` — but the
  regex is only ever applied to root basenames. The knowledge existed; the population did not.

There is **no gate whose population is the non-source files of `tinybendygrad/`.** The two
instruments that walk that directory (`substrate.py`, the `.bend` census) filter by suffix, so an
extension-less stray is in no gate's population. **A gate's input being a suffix over a directory
it does walk, when the directory is exactly where the stray landed, is the doctrine-1 failure one
level down: the guard could not see the file it exists to forbid, and never had a denominator that
could contain it.** The `.agents/slop/strays/MANIFEST.tsv` unit (`strays/*`) walks the whole repo,
but it is a report, not a gate, and `.agents/slop/` is permitted to name port strays while
forbidden to delete them (`AGENTS.md`: do not touch `tinybendygrad/`).
