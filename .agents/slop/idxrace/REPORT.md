# THE COMMIT RECIPE, MEASURED UNDER A RACE

MEASURED 2026-10-22, in this repo, at HEAD `a50ec806e`. The instrument is
`.agents/slop/idxrace/idxrace.py`; it is Python, it runs in a throwaway repo, and it needs no
`bend`, no corpus and no network.

## WHY THIS WAS MEASURED AT ALL: THE HAZARD FIRED ON THE ORCHESTRATOR

At 2026-10-22T04:2xZ the orchestrator's own commit `64169355a` carried **866 deletions across
5 paths** — including **`tinybendygrad/device.bend` (441 lines, a SUBSTRATE file)** and three
`.agents/slop/linkbuf/` tools (422 lines). The recipe was the documented one:

```
PARENT=$(git rev-parse HEAD)
git read-tree "$PARENT"     # the tree, CAPTURED
git add -- <path>
git commit                  # HEAD HAD MOVED in between
```

Another unit committed between the `rev-parse` and the `commit`. The commit's tree was the
OLD tree, so it **reverted 5 paths and deleted 4 of them** — the silent reversion
`AGENTS.md` names.

**`git show --stat` caught it**, which is why `AGENTS.md` mandates it, and the concurrent
session **re-landed it on top** (`4f189e21c`: *"RE-LAND of fa8d62f01 -- a concurrent commit
REVERTED IT, and the remedy is to re-land, never to reset"*) without being asked. The bytes on
disk were never touched (`git read-tree` without `-u` does not touch the working tree), so
nothing was lost.

## THE MEASUREMENT

Three recipes, 40 trials each, and **the race is injected in every trial**: another unit
commits between the seed and the commit, pathspec-scoped (`git add -- b.txt d.txt` +
`git commit -- b.txt d.txt`), never `git add -A`.

| recipe | what it does | swept |
|---|---|---|
| **A** | `read-tree "$PARENT"` where `$PARENT` was **captured earlier**, then add, then commit | **40 of 40** |
| **B** | re-`read-tree` the **current** HEAD immediately before add, and re-check HEAD did not move; re-seed and re-add if it did | **0 of 40** |
| **C** | **no seed at all**: `git commit --only -m msg -- <path>` | **0 of 40** |

A's example sweep: `DELETED d.txt; REVERTED b.txt ('b1\n' != 'b2\n')` — a **deletion and a
reversion**, which are the two shapes the real incident had.

**C on a NEW (untracked) file** — the case that matters, because agents create files:
**0 of 40**.

**SELFCHECK: OK — 0 refused commits**, so every "swept 0" above is a real pass: the commit
landed *and* carried nothing of the other unit's.

## TWO OF MY OWN INSTRUMENTS WERE VACUOUS WHILE I MEASURED THIS

Both are fixed in the script, and both are the session's recurring class:

1. **`git commit --only -- <path> -m msg` puts `-m` AFTER `--`,** so `-m` is parsed as a
   *pathspec* and **the commit never happens**. The other unit's commit was then HEAD, HEAD's
   tree looked perfect, and recipe C read as a **clean pass**. `-m` must come before `--`.
2. **A recipe measurement must assert that the commit it is measuring LANDED.** A commit that
   did not happen is not a pass — it is a **refusal**, and a refusal is a different class. The
   instrument now returns a refusal as a *failure*, so "swept 0" cannot hide one.

A third, in the experiment's setup: the "other unit" originally used `git add -A`, which
**swept my own file into its commit** and made my commit refuse with *"nothing to commit,
working tree clean"* — so the recipe under test was destroyed by the instrument. That is
`AGENTS.md`'s *"NEVER `git add -A`"* showing up as a measurement bug.

## THE PRESCRIPTION THIS MEASUREMENT SUPPORTS

1. **Never capture a parent and use it later.** The capture IS the defect; the `read-tree` is
   not. `git read-tree "$(git rev-parse HEAD)"` evaluated inline is *nearly* as unsafe as the
   captured form, because the race can land in the microseconds between the two calls — so
   prefer **C**, which has no seed to go stale.
2. **Prefer a pathspec'd commit**: `git commit --only -m "msg" -- <path>`. It is bounded by
   construction (the pathspec IS the boundary) and it needs no index seed. `AGENTS.md` already
   measured `--only` as bounded (`contam.py` 4 of 4) and race-free (`race.py` 36 concurrent
   one-path commits through ONE shared index swept 0; `route.py` 22 under a concurrent index
   writer swept 0). **This measurement is the third, independent confirmation, and the first
   that forces the race in EVERY trial.**
3. **If you must seed an index, re-seed and re-check** (recipe B) — and know that it can still
   refuse, which is safe but useless.
4. **Always `git show --stat` in the same command as the commit.** It is the instrument that
   caught this, and it is the only thing standing between a stale seed and a 866-line revert.
5. **Never `git add -A`.** It puts another unit's work inside your commit — measured here, and
   already measured in `AGENTS.md` as the arithmetic of the `591f6b499` outage.

## WHAT THIS DOES NOT CLAIM

- It does not claim recipe B is safe under a race that lands *between* its re-check and its
  commit; that window is smaller, not absent. **C is the recommendation because it has no
  window to lose.**
- It does not claim anything about `jj`'s index handling, which `AGENTS.md` measures
  separately.
- 40 trials per recipe is enough to separate 40 from 0; it is not a confidence interval.
