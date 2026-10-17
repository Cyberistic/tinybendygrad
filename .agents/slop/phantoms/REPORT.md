# PHANTOM-DELETION STRAGGLERS: is the class bigger than 3?

**VERDICT: NO. THE CLASS IS EXACTLY 3, AND `02329daf`'s RECORD IS NOT AN UNDERCOUNT -- IT NAMED
ALL THREE, AS DELIBERATE WITHHOLDINGS. THE BRIEF'S PREMISE IS INVERTED.**

- Measured: `2026-10-17T05:25:28Z` (head of run); all git reads under `env -u GIT_INDEX_FILE`.
- `HEAD` = `2473958642727eeb0e5ed0b86dbe8eadb0a823d5` — `REINDEX: a unit swept 7,533 files by
  obeying AGENTS.md AS WRITTEN, and upstream REIMPLEMENTED GROUP/FLIP`
- `origin/master` = `473d7ce988d0f0741e26bccf5e8c1495d864be4c` — `Update README.md`
- `merge-base(origin/master, HEAD)` = `52d77134b90312eb001ab3362477dc5db9ebac5e`. **THE TWO HAVE
  DIVERGED**; `HEAD` is *not* an ancestor of `origin/master`. Read the denominators below with that
  in mind: the 104-path skew between the trees is normal two-sided development, not damage.
- Nothing was changed. Read-only throughout. Scratch evidence: `_origin.rows`, `_head.rows`,
  `_head_oid.rows`, `_head_sorted.rows`, `_only_origin.rows`, `_empty_index.rows`,
  `_empty_sorted.rows`, `_landmine.rows`, `_catA..D.rows`, `_repair_msg.rows`, all in this directory.

## 1. POPULATION AND DENOMINATORS

| population | count |
|---|---|
| paths in `origin/master`'s tree (`git ls-tree -r`) | **7 433** (6 903 blob/100644, 325 blob/100755, 205 blob/120000 symlink -- all blobs, no submodules) |
| paths in `HEAD`'s tree (`git ls-tree -r`) | **7 533** |
| paths in `origin/master` but not `HEAD` | **4** |
| paths in `origin/master`, not `HEAD`, **but present on disk** -- *the straggler population* | **3** |
| paths in `origin/master`, not `HEAD`, **and not on disk** | **1** (`tinygrad/runtime/ops_bend.py`, the control -- see §5) |

Denominator for the empty-blob question (§6): **1 256** paths carry the empty blob
`e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` in the default index; of those, **704** are absent from
`HEAD`'s tree.

Disk check uses `os.path.lexists`, not `os.path.exists`: the trees hold 205 symlinks, and
`exists()` follows them and would silently drop a broken-but-present link.

### EVERY MEMBER, NAMED

1. `gates/assertlit.rows` -- index `e69de29b`, `1 .A N...`, 5 646 B on disk
2. `gates/falseclaim.rows` -- index `e69de29b`, `1 .A N...`, 17 457 B on disk
3. `gates/oracleblind.rows` -- index `e69de29b`, `1 .A N...`, 35 858 B on disk

**No fourth member exists.** Category B of the matrix -- in `origin/master`, absent from `HEAD`,
empty blob in the index, **and not on disk** (i.e. content genuinely destroyed) -- is **0**.

## 2. CLASSIFICATION: EMPTY BLOB OR REAL BLOB?

**All three carry the empty blob `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` in the current index**
-- the exact phantom-deletion fingerprint, corroborated by `git status --porcelain=v2` reading
`1 .A N... 000000 000000 100644 0000...` for each: stage 0 with a null oid, i.e. an
intent-to-add placeholder. `git ls-files -v` reads `H` for all three.

`git rev-parse HEAD:<path>` fails for all three with `exists on disk, but not in 'HEAD'`, which is
git's own independent statement of the same fact.

**The content is NOT lost, and restoring from `origin/master` would be a REGRESSION.** Disk hashes
differ from the `origin/master` blobs for all three -- the on-disk copies are *newer* than
`origin/master`:

| path | disk blob | `origin/master` blob |
|---|---|---|
| `gates/assertlit.rows` | `aa51d802b4f0e832` | `2a1e8d6198776652` |
| `gates/falseclaim.rows` | `5f673f31d15d4db9` | `cd1d641d677bc8bc` |
| `gates/oracleblind.rows` | `f642af029dc3fba7` | `e606d484fc560b25` |

So the withheld content is live work that survived only on disk. That is the whole reason
`02329daf` declined to commit it, and it is why the correct repair is `git add <path>` on a private
index, never a checkout from `origin/master`.

## 3. IS `02329daf`'s RECORD ACCURATE? -- YES, AND THE BRIEF IS INVERTED

The brief states the message "names the files it deliberately withheld" and that "we have since
found THREE stragglers **it missed**". **These are the same three.** The message names them as
*deliberately withheld*, not as oversights. Verbatim, `02329daf` lines 9-11:

> OF THE 182: **178 ARE BYTE-IDENTICAL TO `HEAD~1`** AND ARE RESTORED HERE VERBATIM. **THE **4** THAT
> DIFFER ARE LIVE WORK AND ARE **NOT** IN THIS COMMIT**: `gates/assertlit.rows`, `gates/falseclaim.rows`,
> `gates/gates-pop.py`, `gates/oracleblind.rows` -- `gates-pop.py` BEING EDITED **AT THE MOMENT** OF
> THE MEASUREMENT.

Its own scope arithmetic is 178 restored + **4** withheld = 182, and that sum closes.

| withheld by `02329daf` | named? | state at `24739586` |
|---|---|---|
| `gates/assertlit.rows` | **yes** | still a straggler (empty blob, on disk) |
| `gates/falseclaim.rows` | **yes** | still a straggler (empty blob, on disk) |
| `gates/oracleblind.rows` | **yes** | still a straggler (empty blob, on disk) |
| `gates/gates-pop.py` | **yes** | **landed** -- re-added by `b37c73190` |

- **UNDERCOUNT: NONE.** 3 named and withheld, 3 found independently. The two sets are identical.
- **OVER-WITHHOLDING: NONE.** The 4th, `gates-pop.py`, is in `HEAD` today, so nothing it declined
  turned out to be fine.

**The residual of its withheld list is exactly my independently-derived straggler set.** `02329daf`
was an *accurate* record that was simply never completed -- its withholding was correct at the time
(it would have destroyed live work), and the gap is that nobody ever came back and committed the
three survivors.

## 4. DANGEROUS SUBSET (LIVE CONSUMER BY PATH): **EMPTY**

I expected this to be the headline. **It is not.** Every one of the three is a **write** target of
its own census gate, not a required input:

| path | only code-level binding | kind |
|---|---|---|
| `gates/assertlit.rows` | `gates/assertlit-census.py:85` `REPORT = HERE / "assertlit.rows"` -> `:1286` `REPORT.write_text(...)` | **WRITES** |
| `gates/falseclaim.rows` | `gates/falseclaim-census-gate.py:100` `ROWS = HERE / "falseclaim.rows"` -> `:635` `Path(a.rows).write_text(render(rows))` | **WRITES** |
| `gates/oracleblind.rows` | `gates/oracleblind-census.py:118` `REPORT = HERE / "oracleblind.rows"` -> `:1321` `REPORT.write_text(text)` | **WRITES** |

No gate *reads* any of the three. A repo-wide search for runtime reads (`read_text`, `open(`,
`exists(`, `read_bytes`) of these paths returns nothing: the only three code sites naming them are
the three declarations above, all of which feed `write_text`.

**So none of the three is a silently-vanished gate input.** Each is regenerable by re-running its
own census. Severity is "uncommitted work at risk from an `rm`", not "a gate is now measuring
nothing".

### A FALSE POSITIVE I CORRECTED

A naive grep makes `gates/tnvalue-census.py` look like a live consumer. Its **docstring line 52**
says: *"verdict is read from `gates/oracleblind.rows`, ALSO LOADED BY PATH."* **The code does not do
that.** AST inspection of the file shows every string literal mentioning `oracleblind.rows` lies
inside the **module docstring** (one constant spanning from line 2, hence hits reported at 2 and
251), and the file's **only `.rows` string literal of any kind is `tnvalue.rows`**. What it actually
loads is the census *module*: `gates/tnvalue-census.py:258` and `:711` do
`_load(HERE / (BLIND_STEM + ".py"))` with `BLIND_STEM = "oracleblind-census"`. So `:52` is a prose
claim contradicted by its own file's literals -- worth fixing, but it is not a live dependency and
it does not enlarge the class.

`gates/pins-shape-gate.py:324,330` and `gates/tnvalue-census.py:8` also cite the file in prose only.

## 5. CONTROL -- **PASS**, WITH THE FALSE-POSITIVE RATE MEASURED

Requirement: find all three known stragglers, and **not** fire on a deliberately-deleted path.

- **POSITIVE: 3 of 3** known stragglers found. (Also reached by a second, independent route --
  index-empty-blob ∩ ¬HEAD ∩ origin ∩ disk -- which returns the same 3.)
- **NEGATIVE:** the single origin-only path that is *not* on disk is
  `tinygrad/runtime/ops_bend.py`, removed by `a1a7d370a`: *"PURGE: tinygrad/ held EXACTLY ONE file
  of ours. It is now at the repo root."* **Claim verified independently:** `ops_bend.py` does exist at
  the repo root in `HEAD`. A move, not a loss. My test did **not** report it. **0 false positives.**
- **The disk predicate is load-bearing, and here is the number:** dropping it (testing
  origin−HEAD alone) yields **4** candidates, of which **1 (25%) is a false positive**. With it,
  3 true / 0 false. The predicate is not decoration.

Control verdict: **PASS**. No `REFUSED`.

## 6. IS THE CLASS BIGGER THAN 3? -- NOT AS A STRAGGLER CLASS. TWO NEIGHBOURING POPULATIONS, ONE OF THEM A REAL LANDMINE

The question was phrased against the defined population, and on that population the answer is **3**,
twice-derived, with 0 false positives. But the same index fingerprint is far larger elsewhere, and
suppressing that would be the dishonest answer:

**Matrix of the 704 index-empty-blob paths absent from `HEAD`:**

| class | count | meaning |
|---|---|---|
| A: in `origin`, on disk | **3** | the straggler class (§1) |
| B: in `origin`, not on disk | **0** | content genuinely destroyed -- **none** |
| C: not in `origin`, on disk | 700 | new WIP never committed -- not phantoms |
| D: not in `origin`, not on disk | 1 | stale intent-to-add |

Category C is normal work-in-progress and is not phantom deletion.

**The mirror-image hazard, which is a different and sharper failure: 552 of the 1 256 empty-index
entries ARE in `HEAD`.** Of those, 543 have an empty blob in `HEAD` too (harmless), but **9 have REAL
content in `HEAD` while the index says empty.** For all 9, disk == HEAD right now, so the work is
intact *only on disk*; a commit naming any of them replaces real content with an empty blob:

```
.agents/slop/dictkeyed/dictdrop.py      HEAD=657d52c6  4 117 B
.agents/slop/dictkeyed/discover.py      HEAD=fd3be9d1  4 080 B
.agents/slop/dictkeyed/discover.rows    HEAD=c2ed4f23  3 128 B
.agents/slop/dictkeyed/p42.rows         HEAD=bcd4d24b  1 048 B
.agents/slop/staleref/HEAD-tracked-paths.rows  HEAD=8c5e71e9  306 693 B
.agents/slop/unpushed/audit.py          HEAD=30d95229  7 591 B
.agents/slop/unpushed/findings.rows     HEAD=fb8eb398  3 981 B
.agents/slop/unpushed/range.rows        HEAD=766950c1  3 213 B
.agents/slop/unpushed/range.sha.rows    HEAD=33b399ab  2 009 B
```

All 9 are under `.agents/slop/` -- **zero** are gate inputs, so none is a "gate silently measuring
nothing". They are documentation and instrument files. This is a real but *lower-severity* sibling
of the straggler class, and it is invisible to the origin−HEAD test by construction (it is defined
on paths present in both trees).

## 7. WHAT FOLLOWS (report only -- I changed nothing)

1. The three survivors are **uncommitted**, and their disk content is *ahead of* `origin/master`.
   The fix is `git add` on a **private** index (`GIT_INDEX_FILE` set in the same command, same
   byte-identical value every time), followed by `git show --stat` **in that same command** reading
   `3 files changed` -- never a bare commit, never `git add -A`, and never a checkout from
   `origin/master`, which would silently revert live work to older blobs.
2. `02329daf` needs no correction. It is a truthful record; the finding is that it was left
   **incomplete**, not that it misdescribed itself.
3. `gates/tnvalue-census.py:52`'s docstring should be corrected: it claims a load-by-path of
   `gates/oracleblind.rows` that the file's own literals contradict.