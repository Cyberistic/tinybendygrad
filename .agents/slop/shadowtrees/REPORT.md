# Shadow trees under `.agents/slop` — classification, and a deletion ORDER

**DELETE NOTHING. NOTHING DELETED. NOTHING COMMITTED.**
No `bend` process was invoked. No build. No `cp -R` of a source tree.

## 0. THE HEADLINE, AND IT IS NOT THE ONE I WAS BRIEFED

The brief's largest items (`xd1/{work,cur,head,pin}/tinygrad`, `opstree/tinygrad`) are **already
gone** — deleted by a concurrent unit while I measured. `xd1/head` is now 876 KB, `xd1/pin` 740 KB,
`xd1/work` 64 KB, `xd1/cur` 64 KB, `opstree/tinygrad` 2 KB. What survives of `xd1` is the
`*-head.txt` / `*-pin.txt` / `call-*.txt` evidence at its top level, which is not inside a tree.

The largest item now is one the brief does not mention at all:

**`.agents/slop/differverdict/root/` is a 231 MB full copy of the REPO ROOT, and it contains a
150 MB nested copy of `.agents/slop` — which itself contains a nested copy of every shadow tree.**

`.agents/slop/differverdict/mkroot.sh [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git]` line 18 is `git archive HEAD | tar -x -C "$DST"`, and
`.agents/slop` is **tracked**. So `mkroot.sh` archived the slop tree, and the slop tree inside it
re-archived the slop tree inside it. That is where 150 MB of the 231 MB went.

It is **LIVE** (239 files touched inside 90 min; dir mtime 14:05) and belongs to a unit that is
still working in `differverdict/`. Not a candidate today. It is, however, the answer to "biggest
cleanup win", and it is one command away from being recreated.

## 1. WHAT CHANGED UNDER ME WHILE I MEASURED — read this before using any number below

`dd-cone-wt` and `proof-close` were **deleted and restored** inside my measurement window
(dir mtime `14:29:05`). At one sample `dd-cone-wt` read 44,816 bytes and
`dd-cone-wt/ctl-comment/codegen/decomp/dtype.bend` did not exist; twenty minutes later the same
path hashes `8fb3132f50ac` again and the tree reads 45,093,800. The restore was **faithful**
(byte totals and per-file md5s match my earlier readings exactly).

Two consequences, both of which the existing tooling already handles and which is why it handles them:

- **The byte totals in this report are a snapshot, not a fact.** The per-file md5s are facts;
  I recorded them at the paths so you can re-derive rather than trust.
- **`prune.py`'s live-window re-verification at delete time is not optional here.** It is the
  only thing standing between a manifest and a half-written tree.

## 2. CORRECTIONS TO THE BRIEF, EACH WITH ITS MEASUREMENT

**(a) `work` and `cur` are NOT byte-identical. "34 MB of exact duplication" is false.**

```
xd1/work/tinygrad  17,495,184 B  213 files  MANIFEST bee6f28d0c7cce0e6ef6b646843b4d03
xd1/cur/tinygrad   17,494,953 B  213 files  MANIFEST ea2983bc029bb5dc22d1c70776636818
```
Same file count, 231 bytes apart. They differ in **exactly one file**:
`uop/render.py` (10,808 B in `work` vs 10,577 B in `cur`) — and 231 is exactly that delta.
So the duplication is **16.67 MB, not 34 MB**, and `cur`'s `uop/render.py` is a distinct state.
*Both trees are now deleted; the distinction is recorded because it changes the rule, not the outcome.*

This is the exact failure the classifier's own docstring warns about: "both 17 MB, both 213
files" compressed into "byte-identical". Same size and same count are not a hash.

**(b) `125,668 bytes` is `helpers.bend`'s size, not all three files'.** Measured:

| file | bytes | `ALL PROOFS CHECK` in source |
|---|---|---|
| `tinybendygrad/helpers.bend` | **125,668** | 0 |
| `tinybendygrad/uop/ops.bend` | 287,092 | 0 |
| `tinybendygrad/device.bend` | 78,597 | 0 |

`ALL PROOFS CHECK` is bend's **stdout**, not source text, so it cannot be confirmed by reading a
file, and I did not run bend. The brief's three-file claim is not supportable as written.

**(c) `tree-before/` and `debug-control-work/` — the two the brief called untested — are
untested by nothing else. Both measure ZERO committed citations** (§3). They were also nearly
the same tree: 142 of 144 files identical, differing in `runtime/support/autogen.bend` and
`runtime/support/rdma/bnxtdev.bend.sweep`.

## 3. CITATIONS — whole path token, never basename

`citations.py` reads all **252 committed `.md`** (4.7 M chars) via `git show HEAD:`, and counts
only `tree-prefix + "/"`. The two weaker tests are computed alongside purely to be disbelieved.

| tree | TOKEN | SUBSTR | top-level basenames seen in reports |
|---|---|---|---|
| `xd1/{work,cur,head,pin}` | **0** | 0–2 | 5 (prose) |
| `tree-before` | **0** | 0 | 0 |
| `debug-control-work` | **0** | 0 | 0 |
| `opstree` | 2 | 7 | 0 |
| `render-wt` | 1 | 1 | 0 |
| `ddcheck` | 2 | 3 | 0 |
| `dd-cone-wt` | 1 | 1 | 1 |
| `xd1/wt` | 3 | 7 | 0 |
| `ind` | 3 | 3 | 10 |
| `strays` | 4 | 4 | 0 |
| `proof-close` | 6 | 6 | 8 |

The BASENAMES column is the trap the docstring records, reproduced: `opstree` has 2 token
citations and 0 basename hits; `ind` has 3 and **10**. Over 30× on one tree.

**Zero committed reports cite a path inside `xd1/{work,cur,head,pin}`, `tree-before`, or
`debug-control-work`.** The brief's measurement of `xd1` reproduces exactly.

Every token citation that exists is one of two kinds, and they point opposite ways:
- **A DUPLICATION CENSUS.** `dup/stage3-multiset.md:31` cites `render-wt`, `xd1/wt`,
  `proof-close/mut{1,2}`, `dd-cone-wt/{…}`, `ddcheck/tree` as places one gate row appears —
  i.e. as evidence they *are* duplicates. That is not a reason to keep them.
- **A HAZARD NOTE that requires the copy to exist.** `notes/bend2-constraints.md:9215` — *"`opstree/tinygrad/` is a verbatim copy of upstream, taken by another [unit]"*; `:11527` — *"is a full copy, so an unfiltered `rglob('render.py')` [double-counts]"*. Deleting it silently un-does a warning a reader depends on. Same file `:13088` for `ddcheck/tree/runtime/webgpu_call.bend`.

## 4. `wt-sync.sh` — WHAT IT WAITED FOR, AND IT LANDED

The script's whole mechanism is one line: `git show HEAD:tinybendygrad/helpers.bend > wt/…/helpers.bend`.
Its premise was an **uncommitted, uncompilable** `helpers.bend`. That premise is **false now**,
and I did not need bend to show it:

```
live tinybendygrad/helpers.bend   77deddb66cbd9b6eedaf379331f7db85  125,668 B
git show HEAD:.../helpers.bend    77deddb66cbd9b6eedaf379331f7db85  125,668 B   <-- IDENTICAL
wt/tinybendygrad/helpers.bend     30454c85b5f95fc2f94611e130d25299   67,404 B   <-- the spent snapshot
```

Working tree **is** `HEAD`. So the script would install the file that is already there: a no-op.
And the fix is visibly in the source — all eight `nc_*` defs are now `+`-pinned
(`nc_sign(+s: String)` :88, `nc_digits(+s: String)` :96, `nc_ok(+n: Nc)` :108, `nc_step(…, +h: Char)` :118,
`nc_walk(cs: …, +n: Nc)` :126), and the file explains itself at :247 —
*"`nc_sign` uses on its own `+s`. Without it, reading `t` twice is refused with"*.

`helpers.frozen.bend` is `30454c85…` — **the same md5 as the stale `wt/` copy.** Both are the same
spent pre-fix snapshot of `helpers.bend`, kept twice.

`.agents/TODO.md:3311` already records the debt (*"and `.agents/slop/xd1/wt/` the moment that
agent lands. **Not done by me**"*). `.agents/TOOLS.md:437` documents the script as a tool and
**will need a line removed** if the script goes.

**Verdict: spent by its own terms. `wt-sync.sh`, `xd1/wt/`, and `helpers.frozen.bend` are all one
expired workaround.** But `wt/` is 11,204 bytes now and `xd1/{work,cur,head,pin}` are already gone,
so this is bookkeeping, not bytes.

## 5. BYTE-IDENTICAL DUPLICATES — PROVEN BY HASH, NOT BY EYE

Three pairs, `treehash.py` MANIFEST over sorted `(md5, relpath)`, equal MANIFEST = same paths
and same bytes:

```
IDENTICAL 3a3a6f42bbac470f9f4e501e1fe1719e  45,093,800 B  576 files
   .agents/slop/dd-cone-wt
   .agents/slop/differverdict/root/.agents/slop/dd-cone-wt
IDENTICAL 611d8321c3e2835cc8fb3a410b1ce625  22,376,262 B  287 files
   .agents/slop/proof-close
   .agents/slop/differverdict/root/.agents/slop/proof-close
IDENTICAL 782e01df0197870220d6bf88019da76b  10,976,217 B  138 files
   .agents/slop/render-wt
   .agents/slop/differverdict/root/.agents/slop/render-wt
```

Same CONTENT hash too, so it is not a path-level coincidence. **78.4 MB of exact duplication,
all of it inside `differverdict/root`, and all of it disappearing the moment that one directory
does.**

**No two `tinybendygrad` shadows are byte-identical to each other or to the real tree.** All ten
tested have a distinct MANIFEST — every one has been edited since it was copied, which is exactly
why "delete the copy, keep the diff" is the wrong instinct here.

## 6. PER TREE — the three answers, separately

`SAME` = byte-identical to the real `tinybendygrad/`. `DIFF` = same path, different bytes.

| tree | bytes | SAME | DIFF | EXTRA | MISS | recreatable by | cited | only copy? |
|---|---|---|---|---|---|---|---|---|
| `differverdict/root` | 242.5 M | — | — | — | — | `sh .agents/slop/differverdict/mkroot.sh [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git]` | 0 | **LIVE — do not touch** |
| `dd-cone-wt/*` (4) | 45.1 M | 5.45 M | 4.41 M ea | 0.56 M | 17 | `cp -R tinybendygrad` + 2 file edits | 1 (census) | **yes — 4 distinct `dtype.bend` states** |
| `proof-close/MUTANT` | 11.3 M | 6.76 M | 3.78 M | 0.08 M | 12 | `cp -R` + mutation harness | 6 | **yes — mutation states** |
| `proof-close/MUTANT2` | 11.0 M | 5.01 M | 4.77 M | 0.56 M | 18 | `cp -R` + mutation harness | 6 | **yes — mutation states** |
| `render-wt` | 11.0 M | 5.13 M | 4.61 M | 0.49 M | 19 | `cp -R` | 1 (census) | **yes — `uop/fold2_work.bend` etc** |
| `deadreg/w/tree` | 14.1 M | — | — | — | — | unknown | 0 | **UNEXAMINED — appeared during my run** |
| `tree-before` | 11.6 M→? | 7.84 M | 3.21 M | 0 | 9 | `cp -R` | **0** | partly |
| `debug-control-work` | 11.6 M | 7.84 M | 3.21 M | 0 | 9 | `cp -R` | **0** | partly |
| `strays/working` | 2.39 M | — | **21 of 21** | 0 | 0 | n/a | 4 | **NEVER DELETE (§8)** |
| `strays/origin` | 2.25 M | — | **21 of 21** | 0 | 0 | from `origin` | 4 | **NEVER DELETE (§8)** |
| `ddcheck/tree` | 10.5 M | 4.50 M | 4.98 M | 0.57 M | 28 | `cp -R` | 2 | **recovery source (§7)** |

MISS > 0 everywhere means every one of these is a **dated photograph**, not a mirror. That is
the strongest single argument that the `SAME` rows carry no information.

## 7. WHAT IS SOMEBODY'S ONLY COPY — NAMED

**(a) `dd-cone-wt`: four variants differing in exactly two files.** `schedule/memory.bend` is
identical in `revert-add`/`revert-both`/`revert-push` (`4dc5314c`) and differs only in
`ctl-comment` (`364050b5`). `codegen/decomp/dtype.bend` is **four distinct states**:

```
ctl-comment  8fb3132f  110,562 B      revert-both  3794b7cc  110,429 B
revert-add   c5d9fe6a  110,429 B      revert-push  fdc9093a  110,518 B
```

Each is the only copy of its state. **The experiment is the difference, and deleting any three
of the four destroys three arms of it.**

**(b) `ddcheck/tree` was a RECOVERY SOURCE — and the recovery landed.** `mirror.sh:35-41`:
*"The copies in `ddcheck/tree/` are what I RECOVERED `webgpu_call.bend` from after a scripted
def-reordering pass truncated it to 11 lines."* Verified:

```
tinybendygrad/runtime/webgpu_call.bend              e9e6f376  68,368 B
ddcheck/tree/runtime/webgpu_call.bend               e9e6f376  68,368 B   <-- identical
git show HEAD:tinybendygrad/runtime/webgpu_call.bend e9e6f376            <-- committed
```

**So `ddcheck/tree` holds no only copy of `webgpu_call.bend`.** It is now safe in principle —
but it still holds 57 other DIFF files that nothing has vouched for.

**(c) `strays/working` vs `strays/origin` differ in ALL 21 files.** `origin` is not a copy of
`working`; it is the *other side* of a green→cold regression. Brief confirmed. See §8.

**(d) 1,351 files whose ONLY copy in the entire repo is inside `differverdict/root` — 43.2 MB,
including 243 `.bend` mutation artifacts (10.73 MB).** Measured by a single-pass repo-wide md5
index (`onlycopies.py`, skips `references/` and `.venv`). The biggest `.bend` ones:

```
d6610683 400,159  …/differverdict/root/.agents/slop/proof-close/MUTANT/tinybendygrad/uop/ops.bend
55b0406b 376,986  …/proof-close/MUTANT/tinybendygrad/uop/fold.bend
5025b0c1 211,306  …/proof-close/MUTANT2/tinybendygrad/uop/ops.bend
4700ab74 207,818  …/render-wt/tinybendygrad/uop/ops.bend
2a2634c6 166,023  …/proof-close/MUTANT/tinybendygrad/uop/render.bend
1c2f590d 164,738  …/proof-close/MUTANT/tinybendygrad/renderer/cstyle.bend
```

**This is the one thing I would not let happen by accident.** `mkroot.sh` line 13 is
`rm -rf "$DST"`. Running it once — for any reason, by anyone — destroys 43 MB that exists
nowhere else, including the MUTANT and render-wt mutation records whose outer copies are *already
deleted*. These 243 `.bend` files are, right now, the **last** copy.

The full list is written to `RESCUE-UNIQUE-ONLY-IN-differverdict-root.txt` (1,351 lines, with
md5s) — **outside** `differverdict/`, so it survives the `rm -rf` it describes.

**(e) IN THE PORT TREE, NOT MINE, REPORTED ONLY.** `.agents/TODO.md`/AGENTS.md forbid me from
`tinybendygrad/`. Nine leftover mutation-staging files are in the port:

```
tinybendygrad/uop/ops.staged-blob-{64022,66397,97648,36145}      287,092 / 286,321 / 287,092 / 286,404
tinybendygrad/runtime/support/memory.staged-mem-{68409,98861,40079}   153,558 ×3
tinybendygrad/runtime/support/elf.bend.mut                        257,721
tinybendygrad/runtime/support/rdma/bnxtdev.bend.sweep             143,273
```

They are `memory-mutate.py`'s staged mirrors — its docstring says they must be deleted after the
run, so these are crash leftovers. **`git show HEAD:` returns `d41d8cd9…` (md5 of the empty
string) for five of them: they are committed EMPTY and their working-tree content is
uncommitted.** So `classify.py` would call them JUNK-TEMP — but `classify.py` only walks
`SLOP` and `RUNS`, never `tinybendygrad/`, so no prune run can reach them. They are inert to
the cleanup and nobody has looked at them.

Duplication inside that set, so it is not nine mysteries: `ops.staged-blob-64022` and `-97648`
are both `d5c1174e` = **exactly the live `uop/ops.bend`** (574 KB of nothing);
`memory.staged-mem-98861` and `-40079` are both `a960d600`, which occurs **29×** repo-wide;
`elf.bend.mut` is `1a37024e` = **exactly the live `elf.bend`**. Three more are near-certainly
unique, and I did not chase them because they are not mine.

## 8. THE PRUNER'S REAL HAZARD, WHICH IS NOT A TREE

`strays/artifacts` is inside the tree the brief says nobody deletes from. `classify.py` puts
**5 files there in `JUNK-TEMP`** (`TEMP_RE` matches `\.staged-mem-|\.staged-blob-|\.mut$`):

```
ops.staged-blob-24323      287,092 B  d5c1174e  = live uop/ops.bend      -> duplicate, safe
memory.staged-mem-33281    153,558 B  e029842b  UNIQUE
memory.staged-mem-33929    153,558 B  2fd636fd  UNIQUE
memory.staged-mem-44257    153,558 B  5422e8d2  UNIQUE
```

**Three files, 460 KB, each the only copy of its state, sitting in the never-delete tree, already
classified as deletable junk.** `JUNK-TEMP` is 26 files repo-wide and appears **not** to be among
the classes the last prune acted on (`.pyc`, `.err`/`.out`, zero-byte, `.bak`/`.orig` were). So
this is a loaded gun, not a fired one.

**Whatever runs next should not run `JUNK-TEMP`.** It needs a path exclusion for
`.agents/slop/strays/` first, or the three `memory.staged-mem-*` files move out of `strays/`.

## 9. BYTES RECLAIMABLE

| what | bytes | % of slop (443 M) | recreatable | risk |
|---|---|---|---|---|
| `differverdict/root` (incl. 150 M nested slop) | 242.5 M | **54.7%** | `sh mkroot.sh` | **LIVE unit — not today** |
| `dd-cone-wt/*` | 45.1 M | 10.2% | `cp -R` + 2 edits | 4 unique arms |
| `deadreg/w/tree` | 14.1 M | 3.2% | **unknown** | **unexamined** |
| `proof-close/MUTANT{,2}` | 22.3 M | 5.0% | `cp -R` + mutations | unique states |
| `render-wt` | 11.0 M | 2.5% | `cp -R` | unique files |
| `tree-before` + `debug-control-work` | 23.2 M | 5.2% | `cp -R` | 2 files each unique |
| `ddcheck/tree` | 10.5 M | 2.4% | `cp -R` | 57 DIFF unvouched |
| `strays/{working,origin}` | 4.6 M | 1.0% | no | **NEVER** |
| **`xd1` tinygrad trees** | **~100 M** | — | `cp -R tinygrad` | **ALREADY DELETED** |
| **total already reclaimed by the other unit** | **~355 M** | | | |

**~116 MB is reclaimable from trees that are cold, uncited, and `cp -R`-recreatable — and ~355 MB
was just reclaimed by someone else.** The single largest remaining item is the one directory
nobody may touch yet because a unit is live inside it.

## 10. DELETION ORDER — safest first, each step independently checkable

Every step is a class or a path, never a file list. Re-run `classify.py` before each step;
`prune.py` re-verifies live window + citations + allow-list at delete time, which §1 shows is
load-bearing.

**Step 0 — before anything: preserve the 243 unique `.bend` files in `differverdict/root`.**
The list already exists at `shadowtrees/RESCUE-UNIQUE-ONLY-IN-differverdict-root.txt`.
*Check:* `while read _ _ p; do [ -f "$p" ]; done` over it returns 243.
*Do this first.* It is the only step that prevents unrecoverable loss.

**Step 1 — disarm `JUNK-TEMP` (§8).** Add `.agents/slop/strays/` to `prune.py`'s exclusion, or
move the 3 unique `memory.staged-mem-*` out of it. *Check:* classify `strays/` and confirm 0
`JUNK-TEMP`. **Do not run `JUNK-TEMP` before this.**

**Step 2 — `xd1/wt` + `wt-sync.sh` + `helpers.frozen.bend` (§4).** Cold, spent by its own comment,
and provably a no-op: live `helpers.bend` **is** `HEAD`'s. *Check:* the three md5s in §4 match.
*Then* remove the `wt-sync.sh` line from `.agents/TOOLS.md:437` and tick `.agents/TODO.md:3311`.
Bytes: ~0. **This is the cheapest deletion in the tree and the only one whose premise I verified
end-to-end.**

**Step 3 — `tree-before` + `debug-control-work`.** Both 0 token citations, both cold (0 files in
90 min), both `cp -R`-recreatable. 142 of 144 files identical between them. *Check:* re-run
`citations.py`; both must read 0. **Before deleting, decide the fate of the 2 files unique to each
(`autogen.bend`, `bnxtdev.bend.sweep` ×3 distinct hashes — port/tree-before/debug-control-work
are three DIFFERENT sweeps).** Bytes: 23.2 M.

**Step 4 — `xd1/{work,cur,head,pin}` and `opstree/tinygrad`.** *Already done by another unit.*
Keep `xd1/*-head.txt`, `*-pin.txt`, `call-*.txt` — evidence, not tree. **When `opstree` goes,
delete the two `bend2-constraints.md` lines that warn about it (9215, 11527), or the warning
becomes a lie.**

**Step 5 — `ddcheck/tree`.** Recovery source whose recovery **landed and is committed** (§7b) —
verified, not assumed. Still 57 unvouched DIFF files. *Check:* `git show
HEAD:tinybendygrad/runtime/webgpu_call.bend | md5 -q` = `e9e6f376…`. Bytes: 10.5 M.

**Step 6 — `deadreg/w/tree` (14.1 M). NOT EXAMINED.** It appeared during my run and I did not
classify it. Do not delete it on my say-so. Classify it first.

**Step 7 — `render-wt`, `proof-close/MUTANT{,2}`, `dd-cone-wt/*`.** **STOP.** These hold the
1,351 unique-only files' outer kin — real mutation evidence. Deleting them is defensible *only*
after Step 0 has captured the diffs. If the diffs are wanted, extract them as
`diff -u tinybendygrad/<f> <tree>/<f>` into `shadowtrees/diffs/` first — **the evidence is the
DIFF, not the copy**, and that is the one instruction from the brief I fully endorse.
Bytes: 78.4 M.

**Step 8 — `differverdict/root` (242.5 M). LAST, and only after its unit is finished.**
`rm -rf` inside `mkroot.sh` is what makes 43 MB unrecoverable. Until Step 0 is done, **anyone
running `mkroot.sh` destroys the last copy of 243 `.bend` files.** Add an `AGENTS.md` line:
*"never re-run `mkroot.sh` without re-reading `shadowtrees/RESCUE-…txt`."*

## 11. WHAT I DID NOT DO

No deletion. No commit. No `bend`, no build, no `cp -R` of a source tree. No file written inside
`tinybendygrad/`. Nothing in `runtime/**`, `uop/**`, `renderer/**`, `codegen/**`, `helpers.bend`,
`substrate-check.sh`, `graphcmp*`, `reader-*`, `e2e*`, `checks/**`. I read
`gatecensus/`, `coldness/`, `differverdict/`, `dd-cone-wt/` and `proof-close/` but wrote nothing
in them.

## 12. TOOLS ADDED (all in `shadowtrees/`, all read-only)

| file | what it decides |
|---|---|
| `treehash.py` | MANIFEST / CONTENT / BYBASENAME identity — §5 |
| `deltree.py` | SAME / DIFF / EXTRA / MISSING vs a reference — §6 |
| `citations.py` | TOKEN vs SUBSTR vs BASENAME citations — §3 |
| `onlycopies.py` | one-pass repo-wide "occurs exactly once" index — §7d |
| `MANIFEST-shadow.tsv` | `classify.py --live-minutes 90`, 22,553 files |
| `ONLY-COPIES.txt` | 4,945 unique-only blobs, 305.5 MB |
| `RESCUE-UNIQUE-ONLY-IN-differverdict-root.txt` | **the 1,351 at-risk files** — §10 step 0 |

`MANIFEST-shadow.tsv` verdict totals: `SCRATCH?` 19,467 files / 574.9 M · `JUNK-CAPTURE` 913 /
4.6 M · `RUN-ARTIFACT` 772 / 24.2 M · `JUNK-ZERO` 667 · `JUNK-BYTECODE` 326 / 11.5 M ·
`LIVE` 320 / 14.0 M · `KEEP-ENTRY-DIR` 58 / 2.9 M · `JUNK-TEMP` 26 / 4.9 M.

The 11.5 MB of `JUNK-BYTECODE` is 326 `.pyc` files, most inside shadow trees (`opstree` 54,
`xd1` 186). Deleting a `.pyc` cannot lose a source file, so **that class is safe to run before
anything else in this report** — it is the only free win available today.

*(The slop total moved 398 → 660 → 300 → 443 MB across this session. §1.)*