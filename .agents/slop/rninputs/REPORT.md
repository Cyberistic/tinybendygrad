# `checks/rn-gate.py` — are its three missing inputs recoverable from git?

**Report only. Nothing fixed, nothing restored.** One read-only pass; no gate was run.

- **Timestamp (start):** `2026-10-17T00:15:21Z`
- **Timestamp (verdict written):** `2026-10-17T00:17:18Z`
- **HEAD at start:** `9122a0d28` (`9122a0d28c60055d45c07566715823af2f208680`)
- **HEAD at verdict:** `7a826eb70` — **THE TREE MOVED UNDER ME.** `git rev-list --all --count` went
  23611 → 23612 between the two readings. Every answer below was re-measured at `7a826eb70`.

**Denominators (all at `7a826eb70`):** 6381 refs · 23612 reachable commits · 194299 objects in
`git rev-list --all --objects` · **18057 distinct path names** in history · 0 unreachable commits.

---

## 1. What I searched, and why each instrument can see its population

| # | instrument | what it can and cannot see |
|---|---|---|
| 1 | `env -u GIT_INDEX_FILE git log --all --oneline -- <path>` | every commit reachable from **any of the 6381 refs**, rename detection on by default (`3f0e70ff1` shows as `D checks/render-gate-oracle.py`, so deletes are seen) |
| 2 | `env -u GIT_INDEX_FILE git cat-file -e HEAD:<path>` | the committed tree at one named commit |
| 3 | `env -u GIT_INDEX_FILE git rev-list --all --objects \| awk 'NF==2{print $2}' \| sort -u` | **every path name that has ever existed in any tree of any ref** — the path census. 18057 rows. This is a *name* census over the whole object graph, not a hand list and not a basename regex. |
| 4 | `env -u GIT_INDEX_FILE git log --all --follow --name-status -- checks/render-gate-oracle.py` | the rename chain of the surviving oracle — decides whether the missing xd1 path is a *rename of it* or a separate disk-only copy |
| 5 | `env -u GIT_INDEX_FILE git fsck --unreachable --no-progress --connectivity-only` | whether `--all` misses commits no ref points at. **0 unreachable commits**, so `--all` is a complete denominator over the commit graph |
| 6 | `env -u GIT_INDEX_FILE git cat-file --batch-all-objects --batch-check` | metadata for all 200k objects, so a same-size blob can be found even if no tree names it |
| 7 | `grep` of the tree + `find . -name 'rn-port*' -o -name 'rn-orc*'` | present-day disk, to separate "was never built" from "was built and lost" |
| — | **positive control** | `checks/render-gate-oracle.py` = **1** hit under instrument 3. The census can see a thing. Its 0s are 0s, not blindness. |

---

## 2. The three answers

### 2.1 `.agents/slop/xd1/render-gate-oracle.py` — **NOT RECOVERABLE. Never committed.**

Measured, all zero:
- `git log --all --oneline -- .agents/slop/xd1/render-gate-oracle.py` → **0 commits of 23612.**
- `git cat-file -e HEAD:<path>` → **absent.** (and absent at `9122a0d28` too)
- Of the **18057** distinct path names in history, **0** are `xd1/render-gate-oracle*`.
- `git fsck --unreachable --connectivity-only` → **0 unreachable commits**, so this is not an
  unreached-ref problem.
- `git cat-file --batch-all-objects` for a same-size blob: only two blobs of 13073 B exist,
  `b45c0975…` (the `checks/` oracle) and `076fecbf…` = `test/test_multitensor.py`, an unrelated
  upstream file that merely happens to be the same size. **No orphan copy.**

**Two facts that change the shape of this answer, and neither was in the brief:**

**(a) `.agents/slop/xd1/` WAS committed — 211 distinct paths, including 155 under `xd1/head/`
(`tinygrad/uop/ops.py`, `tinygrad/uop/render.py`'s neighbours, etc.). `git ls-tree -r HEAD --
.agents/slop/xd1` returns **0** paths.** So the directory, the upstream `head/` seam the oracle
imports, and everything around it were tracked and are gone. The one file the gate names was
never among them. "The whole directory is gone" is true of HEAD and false of history.

**(b) THE FILE EXISTED ON DISK — here is the receipt.** Blob `894a2a30…`, recoverable at
`.agents/slop/gatecensus/runs/.agents%slop%xd1%render-gate-oracle.py.json`:

```json
{"rel": ".agents/slop/xd1/render-gate-oracle.py", "how": "venv-py", "leash_s": 25, "mb": 1024,
 "wall_s": 0.31, "bounded_exit": 2, "bound": "WITHIN-LIMITS", "child_rc": 2, "peak_mb": 2,
 "verdict": "", "status": "FAIL", "why": "child rc=2 within both bounds"}
```

A tree-walking census ran that exact relative path and got a child process out of it. It was a
real, runnable, 13 kB-scale instrument. It was on disk and **not in git**. Same class as the
`xd1/mutate.py` instance already recorded in `AGENTS.md`: an instrument that ran, was never
committed, and was swept.

**Is the SUBJECT recoverable at a different path? YES, and it matters:**
`checks/render-gate-oracle.py`, blob **`b45c0975b68cf0242fbe8c6e270a8a50b483cd46`**, **in HEAD**,
13073 B, 288 lines, md5 `b6e2dd42b1de822ea554fd4d3d9b2b4f` identical on disk and in HEAD.
Exact command: **`git show HEAD:checks/render-gate-oracle.py`**.

But `git log --all --follow --name-status -- checks/render-gate-oracle.py` — 41 commits, every
single entry `A` or `D` **at `checks/`**, one `D` at `3f0e70ff1` and re-`A`s afterwards. **There
is no rename into `.agents/slop/xd1/`.** So the xd1 path was a **disk-only copy** of the oracle,
and no blob in any commit was ever *at* that path.

### 2.2 `checks/rn-port.txt` — **NOT RECOVERABLE. Never committed. No substitute exists.**

- `git log --all --oneline -- checks/rn-port.txt` → **0 of 23612.**
- `git cat-file -e HEAD:<path>` → **absent.**
- 0 of 18057 history paths.
- `find . -name 'rn-port*'` → **0 hits on disk.**
- Searched history for *any* port-lane capture of `render.bend` at any path: the only
  `oracles/` entry is the **oracle** side, `oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows`.
  **There is no port-side capture in this repository, in git or on disk.**

**The pair was not hypothetical — it ran and passed.** Blob `ee4924de…` at
`.agents/slop/eq/rn-selftest.txt`, held by commit
**`1bb5facad0cc27f3331e3edfa40fb150ee2bbd67`**; exact read:
**`git show 1bb5facad0cc27f3331e3edfa40fb150ee2bbd67:.agents/slop/eq/rn-selftest.txt`**.
Its `[selftest base]` line reads:

> `the REAL captured pair: 80 gated rows, 75 agree, 5 disagree ['arg_repr AKern', 'arg_repr AParam1', …]`

and its last line reads `SELFTEST OK -- a planted VALUE raises 'disagree' by one; a planted NAME
leaves 'disagree' at the base count and moves the name sets, so the two are distinguishable`.
Its sibling `808b0333…` at `.agents/slop/eq/rn-live.txt` (same commit) is the live-lane
transcript: `live port rc=0 md5=302944bb   live oracle rc=0 md5=642f9770`, port 140 physical /
91 logical, oracle 124 physical / 80 logical.

Those are the gate's **own stdout**, not the capture. They are a *verifiable record of what the
missing pair measured* — they are not the pair, and restoring them would give `selftest()` a
report to read instead of rows to judge.

### 2.3 `checks/rn-orc.txt` — **NOT RECOVERABLE. Never committed. A committed stand-in exists.**

- `git log --all --oneline -- checks/rn-orc.txt` → **0 of 23612.**
- `git cat-file -e HEAD:<path>` → **absent.**
- 0 of 18057 history paths. `find . -name 'rn-orc*'` → **0 hits.**

**But the oracle lane's bytes ARE in git, at another path, and they match the recorded run.**
`oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows`, **in HEAD**, 7683 B, blob
`08e8755b0cc3b9f644718279393569798027cfcc`, exact read
**`git show HEAD:oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows`**.
Measured with `.agents/slop/rninputs/foldrows.py`: **124 physical lines, 80 logical rows** —
an exact match to the oracle lane recorded in `rn-live.txt` ("oracle 124 phys lines … 80 logical
rows"), and its spelling is the glued `name=[…]` form that `rn-gate.py:171-176` documents as the
oracle's own.

**I am not certifying it as a drop-in.** Two measured reasons: only **22 of its 80 rows** carry
`rn-gate.py`'s exact three-space `SEP = "]   py=["` (the rest use 1 or 5 spaces of padding), so
`split_py` at `rn-gate.py:212` would return `None` for most rows and the `STALE-LITERAL` count
would read as 0 without anything being compared. And I was told not to run the gate, so I cannot
certify the substitution by running it.

---

## 3. Is restoring safe? — NO for the live lane, even though the file is findable.

`checks/render-gate-oracle.py:14-16`:

```python
if "--gate" in sys.argv:
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "head"))
```

The oracle resolves its upstream `tinygrad` **relative to its own location**, and the gate invokes
it as `[sys.executable] + ORACLE`, i.e. `ORACLE[0]` is both the path it checks and the path it runs.

- Restored at `checks/render-gate-oracle.py` → it would look for **`checks/head/`**, which exists
  neither on disk (`ls: checks/head: No such file or directory`) nor in HEAD
  (`git ls-tree HEAD checks/head/` → empty). It would fall through to the vendored `tinygrad/`,
  which is exactly the hybrid the file's own docstring refuses: *"The rebase gate's row parser
  … disagrees with every bracketed port row even when the answer is the same."*
- Restored at `.agents/slop/xd1/render-gate-oracle.py` → it would look for
  **`.agents/slop/xd1/head/`**, which **is in history** (155 paths) and **is not in HEAD**
  (`git ls-tree -r HEAD -- .agents/slop/xd1` → 0). So it is restorable *in principle*, but only by
  also restoring 155 upstream files, and only to a path that never existed in git.

**Either way the live lane stays refused.** Restoring the script does not buy a lane; it buys a
*third* way for the gate to fail with `ImportError` instead of exiting 3. **A refusal is the better
outcome**: `exit 3` is a declared verdict, an import traceback is a `DEAD` lane wearing a `FAIL`'s
clothes. **Do not restore.**

---

## 4. Is the refusal prose accurate? — **NO for the live lane. YES for the selftest lane.**

### 4.1 `rn-gate.py:468-471` — the LIVE lane. **The clause is misleading.**

> `` oracle absent: … the live lane would run a script that is not there
> (`.agents/slop/xd1/` is gone; **recoverable from git if it was ever committed**). ``

The hedge *"if it was ever committed"* is logically true and **operationally useless, because the
answer is that it was never committed** — 0 of 23612 commits, 0 of 18057 history paths, with a
positive control proving the instrument sees a sibling. A reader who takes the clause at face value
will spend the next hour in `git log --all --diff-filter=D` looking for something that is not
there, and the failure mode is a *silent* one: the gate keeps exiting 3, the prose keeps implying
a recovery exists, and nobody ever establishes that it does not.

Worse, the clause is misleading in a way that hides a real fact: **the oracle's subject IS in git,
at `checks/render-gate-oracle.py`, tracked, 13073 B, 41 commits** — and it was **never renamed**
to the path the gate names. So "recoverable from git" is *true about the subject* and *false about
the path*, and the prose asserts them as one thing.

The accurate clause is one sentence:

> the oracle is **never committed** at this path (0 of 23612 commits, 0 of 18057 history paths); a
> copy of it is tracked at `checks/render-gate-oracle.py`, but its `head/` seam is in neither HEAD
> nor the working copy, so **this lane is PERMANENTLY REFUSED**. `--oracle-stdout` against a fresh
> capture is the only route.

### 4.2 `rn-gate.py:400-404` — the `--selftest` lane. **ACCURATE, and it is the model.**

> `` selftest input absent: … the captured pair this lane judges was never committed (0 commits
> touch it), so there is no denominator to judge. Capture it with `--port-stdout` /
> `--oracle-stdout` on a live lane, or restore it. ``

This names the measured fact, not a possibility, and it does **not** offer a recovery that does not
exist. Two caveats, neither an inaccuracy:

- **"or restore it" is dead.** Neither file was ever committed, so there is nothing to restore. It
  is a *weaker* version of the same defect as 4.1 — same shape, no false promise attached.
- `--oracle-stdout` has **something** to point at
  (`oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows`, 124 physical / 80 logical rows,
  matching the recorded oracle lane exactly) and `--port-stdout` has **nothing**. So half the
  suggested remedy works and half does not, and the prose does not say which is which.

---

## 5. Verdict

1. **`.agents/slop/xd1/render-gate-oracle.py` — PERMANENTLY REFUSED.** It ran (blob `894a2a30…` is
   the receipt) and was never committed (0 / 23612 / 18057). The lane needs a fresh live capture,
   which needs `bend`, which is outside this session's budget. **Not re-derivable, and re-deriving
   it would be fabrication** — the subject at `checks/` is a real oracle but with no `head/` seam.
2. **`checks/rn-port.txt` — PERMANENTLY REFUSED**, and with no substitute anywhere in the
   repository. The pair demonstrably existed (`1bb5facad…:.agents/slop/eq/rn-selftest.txt` ends
   `SELFTEST OK`) and is unrecoverable.
3. **`checks/rn-orc.txt` — PERMANENTLY REFUSED as a file.** A committed oracle-lane capture exists
   at a different path and matches on 124 physical / 80 logical rows, uncertified as a drop-in.

**Both lanes are permanently refused, and that is the correct verdict, not a bug to be patched
around.** The guards are working: they converted two `FAIL`/`exit 1` readings that would have been
read as a red port into two declared `exit 3` refusals. What is left is one sentence of prose.

---

## Boundary of this search — stated, not hidden

- `--all` covers **0 unreachable commits** (`fsck --connectivity-only`), so the commit-graph
  denominator is complete.
- `fsck --connectivity-only` does **not** walk blob reachability. 6951 objects are loose.
  **An unreferenced loose blob carrying the xd1 oracle's bytes cannot be ruled out by path**, but
  instrument 6 bounds it: the only blobs of the oracle's size (13073 B) are `b45c0975…` and an
  unrelated upstream test, and identical content would be the *same* sha, which already exists at
  `checks/`. So **there is no orphan content to recover**, only an unknown number of nameless
  blobs that by construction belong to no path.
- For `rn-port.txt` / `rn-orc.txt` there is **no** content-addressed search available: with no blob
  and no path, nothing to hash against. Their absence is established by path census and disk
  search only.
- **`git ls-files` was never used** — the default index is chronically stale. `git ls-tree`,
  `git cat-file`, `git log --all` and `git rev-list --all` were, all under `env -u GIT_INDEX_FILE`.
- HEAD moved mid-session (`9122a0d28` → `7a826eb70`, 23611 → 23612 commits). All three answers were
  **re-measured at `7a826eb70`**; instruments 1–7 were each run once, at that HEAD.