# `substrate_digest()` — WHAT IT IS A FUNCTION OF

**VERDICT UP FRONT. CONFIRMED, and one half of the prior unit's stated MECHANISM is wrong.**
The digest is a function of **the working copy only** — measured in both directions: 0 of 3 commits
moved it, 2 of 2 observed moves happened at a fixed HEAD.
But `bin/bend` does **not** pull `references/bend/bend2/main.ts` into the digest: it is a regular
2097-byte `sh` shim (`exec bun "$_d/../references/bend/bend2/main.ts" "$@"`), `read_bytes()` follows
nothing, and **2,157 compiler files are outside the population entirely**. That is a bigger hole
than the clone divergence and it is the one the file's own comment at `differ.py:1230` rails against.

It is **not a bug against its own stated claim**: the docstring argues against an `st_mtime` key, and
that argument is sound and reproduced here. It IS a bug against the sentence a reader of
`D0-run-summary.txt` will draw from it, and `checks/substrate-current.py` — the file whose entire
purpose is to ask what those rows mean — already scopes its question to "the tree in front of me",
never to a commit.

MEASURED 2026-10-18T19:05:30Z–19:13:37Z · HEAD **cd0a0fe2** → **55c8bdb4** → **41a70210** →
**4ff41173** → **05e92674** (4 commits during the window; `git reflog HEAD`, index disarmed) ·
18 readings, 3 distinct digests. The tree was still moving when the last reading was taken, so
these counts are a floor; the two ratios this rests on were final by 19:08:40Z.

---

## 1. THE REPRODUCTION

`checks/differ.py` imported by path and its own function called in-process. No compile, no `bend`,
no corpus loop, no gate, no `differ.py` subcommand. `.venv/bin/python`.

| # | when (UTC) | digest (12) | population | HEAD |
|---|---|---|---|---|
| 1–7 | 19:05:30 → 19:08:16 | `291a162a8126` | 387 = 379 walk + 8 named | cd0a0fe2 ×3, 55c8bdb4 ×4 |
| 8 | 19:08:36 (+20 s) | `24645ea69ed7` | — | 55c8bdb4 |
| 9–18 | 19:08:40 → 19:13:37 | `b6d0bec6b52e` | 389 = 379 walk + 10 named | 55c8bdb4 ×7, 41a70210 ×2, 4ff41173 ×1, 05e92674 ×1 |

**Stable case: 7 of 7 readings byte-identical across 166 s**, spanning a HEAD move and two code
paths (`probe.py`'s direct call and `clone.py`'s recomputation from `differ.substrate_entries()`).
So the prior unit's "two digests ~70 s apart" is **not** non-determinism: nothing here is random,
not one byte of `sorted()` instability, no clock, no `PYTHONHASHSEED`. Same function, same
worktree, same answer, every time.

**Unstable case: 2 distinct digests from ONE HEAD, 20 s apart.** The two moves are named, and one of
them is the finding in miniature:

- **`291a162a` → `24645ea6` at 19:08:36.** Cause NAMED: `checks/differ.py` mtime **19:08:31Z**, and
  the edit grew `SUBSTRATE_INPUTS` from 8 to **10** members (`graphcmp-dbg.bend`,
  `graphcmp-empty.bend` — both files present since 2026-10-15/16, so they were not created, only
  *admitted*). The edit was **committed 33 s later**, at 19:09:04Z (`41a70210`, reflog). **The digest
  moved on a state that was never a commit.**
- **`24645ea6` → `b6d0bec6` between 19:08:36 and 19:08:40 — UNNAMED, and I will not guess.** A
  mtime census over the whole population for 19:08:35–19:08:42 finds **0** members written, which
  *refutes* an in-place edit; `snap-1.rows` (389 members, 19:08:44) == `snap-2.rows` (389 members,
  19:09:17), 0 moved. Add-then-delete of a transient file inside a walk is the only shape left
  standing, and nothing on disk now holds its name. **1 of the 2 observed moves is unexplained.**
  That limit
  is not mine alone: `checks/substrate-current.py`'s own header says a FAIL "says the tree moved and
  not WHICH file moved … the diagnosis is 1 bit and the population is N".

**The two directions, which is the whole characterisation:**

- **different HEAD → same digest:** rows 5→6, 10→11, 16→17, 17→18 — **0 of the 4 commits made in
  the window moved the digest**, and correctly so each time: `git diff --name-only` shows every one
  of them touched nothing in the population.
- **same HEAD → different digest:** rows 8→9, both at 55c8bdb4. **1 of the 1 fixed-HEAD interval
  observed (20 s) contains a move.**

Self-inflicted moves: **0 in 18.** This unit wrote only under `.agents/slop/digestwalk/`, which is in
neither `SUBSTRATE_WALKS` nor `SUBSTRATE_INPUTS`, so its own bytes cannot enter the hash. (Other
units' uncommitted work is visible in `checks/` — four `.tmp-*` scratch files at 19:11Z — but
`checks/` is in the population only through the single member `checks/differ.py`.)

## 2. CLONE DIVERGENCE — YES, AND HERE IS THE ARITHMETIC

`git ls-files references` = **0**, confirmed. But that is *not* the mechanism, for the reason in the
verdict. The mechanism is that the population is **not a subset of any commit**. At HEAD 41a70210:

| | count |
|---|---|
| worktree members | **389** |
| members present in the commit | **375** |
| **present in the worktree, absent from the commit** | **14** (13 in the walks + `bin/bend`) |
| present in the commit, absent from the worktree | **0** |
| in both, but **different bytes** (dirty) | **2** — `.agents/slop/graphcmp.py`, `.agents/slop/graphcmp.bend` |
| named inputs the commit does not have | **1 of 10** — `bin/bend` (`.gitignore:5:/bin/bend`) |

So a fresh clone of this commit hashes **366 walk + 9 named = 375** members against this tree's
**389**, with `bin/bend` contributing the token `ABSENT` instead of a sha256. **The digest differs
across clones of one commit, by construction, with no edit by anyone.** The `ABSENT` rule
(`differ.py:1243-1245`) is what keeps that divergence *attributable* rather than silent — a design
property worth keeping.

The 13 walk-only members are, exactly (`walk-untracked.rows`): seven `*-mut.bend`
(`codegen/decomp/dtype-mut.bend`, `codegen/decomp/op-mut.bend`, `codegen/late/.linearizer-mut.bend`,
`codegen/late/.regalloc-mut.bend`, `nn/optim-mut.bend`, `renderer/.wgsl-mut.bend`,
`renderer/cstyle-mut.bend`), `renderer/amd/dsl.bend.bak`, `runtime/_p6.bend`,
`runtime/PROBE-SELFDEMO.bend`, `test/_probe/v5.bend`, `uop/probe-mmcore.bend` — i.e. **other units'
scratch, inside the population, uncommitted.** That is also why I do not claim to have named the
UNNAMED move of §1: the transient shape that move admits has exactly this population to hide in.

`checks/substrate-id.py:54-55` claimed on 2026-10-08 that "137 of 137 `tinybendygrad/` blobs …
are in HEAD". Today it is **137 of 150**, and `bin/bend` has left with it. The sentence carries its
date; the shape is what matters — the member-set was clean then and is not now.

## 3. `references/`: THE COMPILER IS NOT IN THE POPULATION

`bin/bend` is **not a symlink** (`os.path.islink` → `False`; `realpath` → itself). It is a 2,097-byte
`#!/bin/sh` shim whose last line is `exec bun "$_d/../references/bend/bend2/main.ts" "$@"`. The
digest hashes those 2,097 bytes. `references/` is `.gitignore:2`, 0 tracked files, **2,157 on disk**,
and named by neither `SUBSTRATE_WALKS` nor `SUBSTRATE_INPUTS`. **The substrate digest covers the
program and the oracle and zero bytes of the compiler both sides run.** `differ.py:1230` calls the
analogue "a pin on the scale, not the subject", having just added `tinygrad/` for it.

## 4. THE CLAIM IT SUPPORTS, AND THE ONE IT DOES NOT

**Supports, as measured:** *within one working copy, spanning one run*, "the bytes this run read did
not change between its first emit and its summary." That is exactly what `substrate-start` /
`substrate-end` (`differ.py:1001` writes them; `:991` before another unit's 19:08:31 edit, which is
§1's finding happening to the citation) compare, and §1 shows the comparison fires correctly — it
caught an edit 33 s before that edit was a commit. It also supports, via `repro_bad()`
(`differ.py:1416`), "the artifacts in `D/` were produced by the bytes on this disk when you ask".

**Does not support:** anything about a commit, a branch, a clone, a push, or a review. Concretely it
does **not** support "these artifacts came from commit X" for any X, and it cannot: **14 of 389
members are in no commit at all, 2 more are dirty at any instant, and 2,157 compiler files are
invisible.** Two artifacts with the same digest can come from two different commits; one artifact's
digest matches no commit's content at all.

A live instance of the cost, read-only: `runs/graphcmp/D/D0-run-summary.txt` (mtime
**2026-10-18T19:06:26Z**, written by another unit's run) carries
`substrate-start = substrate-end = 291a162a…` — the digest of a worktree state that **no commit
described**: the edit behind it was committed at 19:09:04Z, **2 min 38 s after the summary that
claimed it**, and the state itself was displaced at 19:08:31Z. Both rows agree, so the run reads as
"one substrate", and the subject is a state that no commit ever named.

Second live instance, same directory: `D0-repro.txt` (mtime 2026-10-16T22:50:09Z) has **no
`repro-substrate` row at all**, so the cross-time staleness arm at `differ.py:1417-1421` would
report `repro-substrate ABSENT`. Not mine to fix; recorded because it is the arm that a commit-bound
digest would most improve.

## 5. MINIMAL CHANGE, AND THE TENSION THAT MAKES IT NOT MINIMAL

**The tension, stated first, because it decides the answer.** Move-detection and commit-identity are
*the same property* read two ways. What makes the digest able to answer "did the substrate move
DURING this run" is precisely that it reads the **live worktree**: an uncommitted edit and a
membership change both move it, and §1 caught both — a transient scratch file is the third shape and
I neither observed nor excluded it. Reading blobs from `git ls-tree HEAD` inverts every one of
those: a `HEAD`-read digest **cannot move** while a run is in flight, because nothing a run does
writes to HEAD. **Swapping the source to HEAD would delete the mid-run guard outright and report
`PASS` on precisely the mixture `differ.py:1150-1156` says it exists to catch.** Any proposal that
quietly does this is a regression dressed as a fix.

**Minimal change that keeps both — and it is ~6 lines, not a rewrite:**

1. `substrate_entries()` gains an optional `source` parameter, `"worktree"` (default, byte-identical
   today) or `"head"`. `"head"` builds the same `(relpath, sha256)` list from
   `git ls-tree -r HEAD` + one `git cat-file --batch` — the exact arithmetic already validated in
   `.agents/slop/digestwalk/clone.py`.
2. **Keep `substrate_rows` as two rows and add the commit identity as a THIRD row**, not as a
   replacement. `gates/corpusverdict-gate.py:149-171` reads `SUBSTRATE_ROWS` by name and
   `differ.py:990-996` records that this summary is parsed by four consumers, so a *replaced* value
   silently changes four readers' meaning while a *new* row costs one key and no parser.
3. `repro_bad()`'s staleness arm compares against the **HEAD** digest when the witness names one,
   keeping the worktree digest for the in-run pair. This is the arm that currently goes red on a
   legitimate hand-off between two clones — the concrete harm §2 measures.

**What it does to `ABSENT`, honestly:** under `"head"`, untracked-but-present members vanish from the
population instead of contributing a token. `differ.py:1207-1211` buys the `ABSENT` rule precisely so
"the population cannot silently shrink". A HEAD-read digest **reintroduces that exact defect at the
clone boundary**: 14 members would drop out with no row to say so. So `"head"` must carry the
**inventory**, not just the hash — the member count (and, if you want the diagnosis,
`substrate-current.py`'s own `residual()` already wants) the per-path rows. A digest whose clone
population silently shrinks is the failure `checks/substrate-id.py:579-583` already documents for the
empty-population case, where a `git archive HEAD` tree returned PASS over the sha256 of the empty
string.

**Cheapest thing that is worth doing even if nothing else is:** write `git rev-parse HEAD` **beside**
the two rows. It is one line, it is unambiguous, it is what a reader of `D0-run-summary.txt` actually
wants, and it changes no reader's meaning. The digest's own scope stays honest.

## 6. BUG, OR DOCUMENTED TRADE-OFF?

**Neither, exactly — and the difference is the finding.** The docstring, read in full at
`differ.py:1199-1212` (it was at `:1181` when I started; the file moved under me, which is §1's
finding happening to me):

> "Keyed on CONTENT and on the path RELATIVE TO `ROOT`. Never on `st_mtime`, never on the absolute
> path: a fresh clone of one tree writes every file at the moment it is cloned, so an mtime key is a
> fact about THIS TREE and two clones would disagree. MEASURED (`.agents/slop/substrateid/measure.py`
> …): rewriting every mtime of a second copy across a 4e12 ns spread left the digest byte-identical."

Read precisely, that argues **against an mtime key**. It does not claim two clones of one commit
agree, and it never mentions a commit. **Its stated claim is TRUE and I reproduced it** (7 identical
readings; and the principle is sound). The trade-off it silently accepts is real and now measured:
content-keying yields clone-identity only if the content is a function of the commit, and **14 of 389
members and the entire compiler are not**.

So: **not a bug against its own docstring. A defect against every unstated reading of it**, and the
file already knows it — `differ.py:1152-1153` says only that `start != end` means the run is "a
MIXTURE of two substrates", never "not this commit"; `checks/substrate-current.py` asks "IS
`runs/graphcmp/D/` STILL A MEASUREMENT OF **THIS TREE**?" and answers with a live
`substrate_digest()`. The scope is documented **at the readers, not at the digest.** And the readers
have a denominator: **4 read these two rows** (`checks/substrate-current.py`,
`checks/substrate-id.py`, `gates/corpusverdict-gate.py:149-171`, and `repro_bad()` inside
`differ.py`); **2 of the 4 name the worktree scope in prose, 0 of 4 name it in the row's own key** —
`substrate-start` and `substrate-end` say *when*, and nothing says *whose*.

The one thing I will call a **bug**, on the file's own authority and not mine: `substrate_digest()`
hashes `bin/bend` and 0 of the 2,157 files it execs, while `differ.py:1230` states that a digest
omitting the subject of the comparison is a pin on the scale. That sentence was written about
`tinygrad/`, and the same sentence applies here unfixed.

**REFUSED, not guessed:** the identity of the member that moved at 19:08:36–19:08:40. **1 of the 2
observed moves is unexplained**; the mtime census (0 members written in the window) and the two
identical snapshots bound the shape to add-then-delete, and I decline to name a file I cannot point
at.

---

## PROVENANCE

- **HEAD at close: `05e926744a38e368777824e61bd23e321075cf27`**; during the window
  `cd0a0fe2` → `55c8bdb4` → `41a70210` → `4ff41173` → `05e92674` (`git reflog HEAD` for the first
  four, `git rev-parse HEAD` for the last, read-only, `env -u GIT_INDEX_FILE`). **HEAD moved again
  within a minute of this line being written** (it was `29cf012b` at 19:14:22Z), so that hash is a
  *timestamped witness, not a current state* — re-derive it before citing it. Every digest here
  carries its own reading timestamp for the same reason.
- Window **2026-10-18T19:04:49Z → 19:13:37Z**. Digests unchanged from 19:08:40Z through 19:13:37Z
  across 10 readings and 2 further commits; the tree was quiescent for the final 4 min 53 s
  (snap-1 == snap-2).
- **Nothing compiled.** No `bend`, no `graphcmp*`, no `gates/`, no `checks/differ.py` subcommand, no
  `checks/e2e*`, `sweep.py`, `bounded.py`, `cites-census.py`, no pytest/mypy/ruff. No mutating git;
  no `git add`; `git ls-tree`/`cat-file`/`reflog`/`diff --name-only` only.
- Artifacts, all under `.agents/slop/digestwalk/`: `probe.py` (REPS × GAP calls + population
  census), `clone.py` (worktree vs commit vs one-edit counterfactual, one `cat-file --batch`),
  `headcmp.py` (per-file git blob-id census), `repro.rows` (**18 dated readings + 5 labelled
  comparison digests**), `clone.rows`/`clone2.rows`/`clone3.rows`, `headcmp.rows`, `drift.rows`,
  `drift2.rows`, `snap-1.rows`, `snap-2.rows` (per-path sha256 at 19:08:44Z and 19:09:17Z),
  `rcount.rows`, `walk-*.rows`. No `.txt` was written.
- Incidental citation drift, recorded not fixed, all three **re-derived today against the current
  `checks/differ.py`**: `checks/substrate-current.py:24` and `:56` cite `differ.py:718` for the write
  of the two rows — they are written at **`differ.py:1001`** (`:991` before the 19:08:31 edit, and
  this report's own §4 citation had to be corrected for the same reason); `:33` cites
  `differ.py:1043` for `unhealthy()` folding the two rows — it is **`differ.py:1367`** (`unhealthy()`
  is at `:1342`); `:15` cites `differ.py:905-911` for the per-file sha256 fold, which I did **not**
  re-derive and therefore quote nowhere. **A stale citation here moved a line number twice in one
  session, so any line number in this report is dated to the 19:08:31Z edit of `differ.py`.**