# THREE `needs=` THAT NEVER FIRE: TWO ARE DUPLICATES (DELETED), ONE IS A SHADOWED TRIPWIRE (KEPT)

A census (`.agents/slop/needsaudit/REPORT.md`) put **11 `needs=`/`UNKNOWN:` clause instances** on the
real tree and found **8 fire, 3 never do**. All three dead ones are in `checks/residue.py`;
`checks/sweep.py`'s four all fire. This report decides each dead one, proves the decision, and plants it.

| clause (label × producer) | planted | live (reading A) | outcome | one-line reason |
|---|---:|---:|---|---|
| `residue.py` `commit-or-drop` | 1 → 0 | **0** | **DELETE** | duplicate of `sweep.py`'s, live 114 (99 in reading B) |
| `residue.py` `commit-the-report-that-explains-it` | 1 → 0 | **0** | **DELETE** | duplicate of `sweep.py`'s, live 110 (105 in reading B) |
| `residue.py` `unstage-self` | 0 → 0 | **0** | **MEASURED REFUSAL** | shadowed tripwire; deleting it loses the only witness |

**A count of firing clauses is not a coverage statement unless you say out of how many.** By clause
instance (label × producer), the denominator is **11 before → 9 after** — two instances deleted. The two
deleted ones were among the three non-firing, so **8 of 11 fire → 8 of 9 fire** (reading A). The fraction
rises from 73% to 89%.

**THE NUMBER MOVES, SO IT CARRIES ITS READING.** Seven units were writing the tree while this ran; the
citation-belts count is the volatile part. Reading B below reads `residue-internal-citer` at 0 rather
than 317 because the belts disagreed on 633 rows during that scan — same instrument, different minute.
**7 of 11 → 7 of 9** in reading B. What does *not* move — and what the deletion rests on — is measured
in reading B directly: **residue's output is identical before and after, and the two deleted labels are
0 in both.**

---

## 1. WHY THE TWO ARE DUPLICATES — one question, two authorities, and the second copy is empty

`checks/residue.py`'s contract is *"a SECOND OPINION on `sweep.py`'s DELETE bucket"* (header, line 2).
`residue.main` honours it literally (line 515):

```python
rows = [(rel, sz, first(rel, named)) for rel, sz in files]   # first = sweep.verdict_for
residue_rows = [r for r in rows if r[2] == "DELETE"]          # ONLY the rows sweep already acted on
```

`sweep.verdict_for` (`checks/sweep.py:658`) reaches its last three statements in this order:

```python
if rel not in f.tracked:                       # -> "UNKNOWN:commit-or-drop"
if ...TOOL... and not witness_committed(...):  # -> "UNKNOWN:commit-the-report-that-explains-it..."
return "DELETE"
```

So a row `rel not in tracked`, and a TOOL row with no committed report, are **never `DELETE`** and never
enter `residue.classify`. `residue.py`'s own copies of those tests — the `untracked` and `witness`
branches — were a **second authority over a question `sweep.py` had already decided**, three ways
literally the same code:

- `residue.git_tracked` (`residue.py:161`) and `sweep.tracked_files` (`sweep.py:365`) are the same
  `git ls-files -z` filtered by `os.path.lexists` — same `tracked` set.
- `TOOL_EXT` was byte-identical in both files.
- `witness_committed` was the same test in both files (sweep took `root` as a parameter).

**Two copies of one clause, one live at 114 and one at 0, because the second's input is the first's
output filtered to empty.** Deleting the second is a gain: the `UNKNOWN:` verdict it would have produced
is still produced, per row, by `sweep.py`'s original — 99/105 in reading B, 114/110 in reading A.

## 2. THE TWO PLANTS — each FAILS on the pre-change file

Instrument: `.agents/slop/deadclause/deadclause.py` (default mode). It builds a one-row git tree,
classifies it with the **pre-change module** (`git show HEAD:checks/residue.py`, `HERE` repointed to
`checks/`) and the **post-change module** (the working file), and asserts the post module falls through
to `UNNAMED` while `sweep.verdict_for` still returns the same `UNKNOWN:` tag.

```
# plant commit-or-drop
#   post  -> UNNAMED  needs=commit-or-drop present: no PASS
#   pre   -> UNKNOWN  (FAILS the post assertion, as required)
#   sweep -> UNKNOWN:commit-or-drop (verdict survives the delete)
# plant commit-the-report-that-explains-it
#   post  -> UNNAMED  needs=commit-the-report-that-explains-it present: no PASS
#   pre   -> UNKNOWN  (FAILS the post assertion, as required)
#   sweep -> UNKNOWN:commit-the-report-that-explains-it (verdict survives the delete)
# PLANTS PASS -- each fails on the pre-change file
```

Both plants run against the untouched file and **fail** there — "post-column is `UNNAMED`" is false on
the pre-change file, which still returns `UNKNOWN` with the deleted `needs=`. After the delete they pass.
`checks/residue.py --plant` (the fixture plant) is also green: `# plant: armed; PASS`.

## 3. `unstage-self` IS A MEASURED REFUSAL, NOT A DELETE — the clause item 3 protects

`unstage-self` fires 0 and cannot be planted, but it is **not a duplicate**: `sweep.py` has no such
clause. It is **shadowed**, and shadowing is about *reachability*, not about *worth*:

- `belt_self_cited` (`residue.py:202`) is consulted only after `belt_a ^ belt_b` declines — only when the
  two citation belts **agree**.
- Belt A is `git grep … -- :(exclude).agents/slop/residue/**` (`residue.py:185`), so belt A can never
  contain a `.agents/slop/residue/` path, and `EXCLUDED_DIRS` keeps belt B's index from containing one
  either.
- So whenever a SELF path is in belt B but not belt A, the belts **disagree** and `belts-disagree`
  answers first; when they agree, neither holds a SELF path and `belt_self_cited` is empty.

**The condition belt C exists to catch is the one the fix makes impossible — until the fix is undone.**
If *only belt A's pathspec* is removed, the staged report makes the belts disagree and `belts-disagree`
still catches the self-citation. If **both halves** of the fix are removed (`:(exclude)` **and** the
`"residue"` entry in `EXCLUDED_DIRS`), the belts agree on the SELF path and **only `unstage-self`
fires** — it is the last and only witness for that regression. Deleting it would delete the only
authority over the question, which is exactly the loss item 3 warns against. The 0 is the honest answer
under the current tree: **MEASURED REFUSAL.**

`FIX` is unavailable without reintroducing the bug: no reordering makes belt C reachable while the
exclusion holds, because the exclusion strips the SELF path from **both** belts.

## 4. HASHES AND LIVE COUNTS

`sha256` before → after (before = working copy = `HEAD`, `5f6c7362`):

| file | before | after | touched? |
|---|---|---|---|
| `checks/residue.py` | `70c335f2958cc2dbcc5c10c23f1f0ec33558f49f4b1094026be8bea7690e6feb` | `d54ffdd26f0fcb2bccb7fcfbdf7675cc24e3a207baf1dff68bb0fd3b2eb87c9f` | **yes** |
| `checks/sweep.py` | `983be5dc0d9db1e46ccf7d05819274e05ebb95b76bf997621b32c4919c865386` | `983be5dc0d9db1e46ccf7d05819274e05ebb95b76bf997621b32c4919c865386` | no |
| `checks/residue-plant.tsv` | `18ba8db80bc206afd02671ad0f580cc94ffcb3ce2f847128f180ad7ab85174d1` | `f34fdd0133cb1072d83808c9f8b1a51450c04b5d6a5c32c8d2caa975e6aeb5f8` | yes (its clauses' fixture) |

**Reading A** — the census the task quotes (`.agents/slop/needsaudit/REPORT.md`; 3959 walked rows, 1161
classified): **8 of 11 instances fire.** residue: `owner-decision` 62, `readlink-target` 185,
`belts-disagree` 66, `residue-internal-citer` 317; `commit-or-drop` 0, `commit-the-report…` 0,
`unstage-self` 0. sweep: `belts-disagree` 84, `residue-internal-citer` 265, `commit-or-drop` 114,
`commit-the-report…` 110.

**Reading B** — this work's frozen single-scan diff (`.agents/slop/deadclause/diff.out`; PRE and POST
modules over the SAME population and the SAME belts, 4626 walked rows, 1149 classified):

```
#   residue needs= PRE : belts-disagree=633 commit-or-drop=0 commit-the-report-that-explains-it=0 owner-decision=62 readlink-target=185 residue-internal-citer=0 unstage-self=0
#   residue needs= POST: belts-disagree=633 commit-or-drop=0 commit-the-report-that-explains-it=0 owner-decision=62 readlink-target=185 residue-internal-citer=0 unstage-self=0
#   residue OUTPUT IDENTICAL: True
#   deleted from pre: ['commit-or-drop', 'commit-the-report-that-explains-it']
#   sweep UNKNOWN: belts-disagree=78 commit-or-drop=99 commit-the-report-that-explains-it=105 residue-internal-citer=251
```

Reading B's `residue-internal-citer` read 0 (not 317) because 633 rows' belts disagreed during that
scan — the reason its instance count is 7 of 11, and the reason every count here carries its reading.
**`OUTPUT IDENTICAL: True` is the safety proof: deleting the two branches changed no residue verdict on
the live tree, and `sweep.py` still emits both tags.**

## 5. WHAT CHANGED, AND HOW TO REPRODUCE

- `checks/residue.py` (−23 lines net): the `untracked` and `witness` branches of `classify` are gone,
  with `witness_committed`, `TOOL_EXT`, the now-unused `tracked` keyword, and the `"untracked"`/
  `"witness"` entries in `RESOLVERS`/`CONDITIONS`. `unstage-self` is untouched.
- `checks/residue-plant.tsv`: the rows that asserted the two deleted clauses now assert the fall-through
  (`UNNAMED`), which is the correct residue verdict once the duplicates are gone.
- `checks/sweep.py`: untouched (its originals are the surviving witnesses).

```
.venv/bin/python .agents/slop/deadclause/deadclause.py         # both plants (fail on HEAD, pass now)
.venv/bin/python .agents/slop/deadclause/deadclause.py --diff  # reads the live counts above; ~3 min
.venv/bin/python checks/residue.py --plant                     # the fixture plant, green
```
