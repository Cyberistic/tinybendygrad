# ARE THE RUN'S PINS STILL FRESH?

**HEAD `4b42c0ccf7e53bb140680a19bbcdaddad2f02bf4` · read at 2026-10-18T17:33:57Z · 156 declared members**

**NO. And the reason is not decay — it is a treadmill.** In the 12 minutes between my first reading
and this one, the substrate took **three distinct values**, `D0-run-summary.txt` was rewritten
**three times**, and every run that finished in that window recorded its own two rows **unequal**.
`differ.substrate_bad()` — the tree's own function, called in-process, not paraphrased — says of the
live artifact:

> `substrate-start=a842e8323cbe but substrate-end=7f84fd3da937 -- THE SUBSTRATE MOVED WHILE THE
> RUN WAS IN FLIGHT, so D/ holds a MIXTURE of two substrates and no artifact set here describes one thing`

Per `checks/differ.py:899-906`, that verdict means the artifact set in `D/` is **not a measurement of
one thing at all** — which is a stronger statement than "the pin is stale", and it is the tree's.

### Method, and what was deliberately not done

`checks/differ.py` was **loaded by path** (`importlib.util`, never executed): its module level is
constants (`ROOT` at :42 and the tables) and `main()` sits behind the guard at :1427, so loading it
runs no gate, no subprocess and no compile. `substrate_digest()`, `substrate_entries()`, `corpus()`
and `substrate_bad()` are **called**, never re-typed. No `bend`, no `graphcmp`, nothing under
`gates/`, no `e2e*`, no `sweep.py`, `bounded.py`, `differ.py` CLI, `pytest`, `mypy` or `ruff`. Git
was read only, always with `env -u GIT_INDEX_FILE`. One process at a time, nothing backgrounded.

**The brief's timestamp is off by its own timezone.** `D0-run-summary.txt` was written at
**2026-10-18T02:51:48Z**; `05:51:48` is the local (UTC+03:00) clock reading of the same instant.

---

## 1. WHAT THE DIGEST COVERS, FROM THE CODE

```python
SUBSTRATE_INPUTS = ("checks/differ.py", "checks/devpin.py", "bin/bend",
                    ".agents/slop/graphcmp.py", ".agents/slop/graphcmp.bend",
                    ".agents/slop/graphcmp-oracle.py", ".agents/slop/graphcmp-dbg-oracle.py",
                    ".agents/slop/graphcmp-p13-ops.py")

def substrate_entries() -> list[tuple[str, str]]:
    out = [(p.relative_to(ROOT).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest())
           for p in (ROOT / "tinybendygrad").rglob("*")
           if p.is_file() and "__pycache__" not in p.parts]
    for rel in SUBSTRATE_INPUTS:
        p = ROOT / rel
        out.append((rel, hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "ABSENT"))
    return out

def substrate_digest() -> str:
    h = hashlib.sha256()
    for rel, blob in sorted(substrate_entries()):
        h.update(rel.encode()); h.update(b"\0")
        h.update(blob.encode()); h.update(b"\0")
    return h.hexdigest()
```

**The population is exactly two things: one directory walk and one hand list.** Measured today:
**148 walked files under `tinybendygrad/` + 8 named files = 156 members**, 0 `ABSENT`. The walk is
by extension-agnostic `rglob("*")`, so it takes `runtime/sz.c`, `runtime/dtype.js` and even
`renderer/amd/dsl.bend.bak` — it is not a `.bend` census. Content is keyed, `mtime` is not, and an
absent declared path folds the token `ABSENT`, so a deletion moves the digest.

| a reader would think it covers | it does | denominator, measured |
|---|---|---|
| the port | **YES** | 148 of 148 files under `tinybendygrad/` |
| the corpus graphs | **YES** — `GRAPHS = {"matmul": g_matmul, …}` at `graphcmp.py:1667` puts the graph *bodies inside* a named input | 34 of 34 graphs, in `graphcmp.py`, which is member 4 of 8 |
| the `.py` drivers under `.agents/slop/` | **5 of them only** — `graphcmp.py`, `graphcmp-oracle.py`, `graphcmp-dbg-oracle.py`, `graphcmp-p13-ops.py` (+ `graphcmp.bend`) | 5 of **977** `.py` files under `.agents/slop/` (maxdepth 2) |
| the named oracle scripts | **PARTLY** — 3 oracle `.py` are named; the frozen shell bodies under `.agents/slop/diffpy/` are **not**, they are covered by a *different* pin, `ORACLE_PIN` at :62 | 3 of 5 oracle scripts named |
| **the `tinygrad` tree** | **NO — 0 of 213 `.py` files** | the CPython reference every graph is compared against |
| **the compiler `bin/bend` runs** | **NO** — the digest covers a 5-line shim; the shim `exec`s `../references/bend/bend2/main.ts`, and `references/` is gitignored | 25 `.ts` files sit behind the shim |
| `.venv/bin/python` and the editable `tinygrad` it imports | **NO** | `PY` at :44 |
| `declared()`'s oracle artifacts | **NO** | 0 of **176** |

Two of these are worth more than a line. **The digest does not cover `tinygrad/`** — so every
`graphs-agree` / `byte-identical` row is a claim about *the port against an upstream the pin does not
name*, and the upstream can move under a green pair. And **`bin/bend` is untracked at HEAD**
(`git ls-tree -r HEAD -- bin/bend` → 0 rows) while being a declared input: the digest covers a file
git cannot reproduce, which is also why my commit-reconstruction test in §3 had to be abandoned.

---

## 2. THE RE-TAKE: FOUR READINGS, THREE SUBSTRATES

`pins.rows` is the row-per-pin table. `timeline.rows` is every reading this unit took, with a
`provenance` column naming the tool that printed it.

| read at (UTC) | summary mtime | `substrate-start` | `substrate-end` | live digest | verdict |
|---|---|---|---|---|---|
| 17:22:22 | 02:51:48 | `9528bb5e` | `9528bb5e` | not read | one substrate |
| 17:28:36 | 17:26:49 | `9528bb5e` | `a842e832` | `a842e832` | **MIXTURE** |
| 17:32:00 | 17:32:00 | `a842e832` | `7f84fd3d` | `7f84fd3d` | **MIXTURE** |
| 17:33:57 | 17:32:00 | `a842e832` | `7f84fd3d` | `7f84fd3d` | **MIXTURE** |

The chain is legible: **each run's `substrate-start` is the previous run's `substrate-end`**, and each
run's two rows differ. The 02:51:48Z run *was* internally consistent — `start == end == 9528bb5e` —
and I verified that claim is not a mirage of a stale file: a third witness,
`.agents/slop/reproloop/summary1.txt` (mtime 17:26:49Z), holds a byte-copy of the summary of the run
that broke it. The pair was green at 17:22 and red by 17:28, and the question was never asked.

**All three values disagree with the tree as it is now.** Live is `7f84fd3d` (156 members), so it
matches the *current* `substrate-end` and not the `substrate-start` — the run was a mixture the whole
time, and its artifacts were written across the edit.

**The run is also red on its own terms, which freshness does not rescue.** `differ.PINS` (:248)
against the live summary: **10 of 17 agree, 7 miss** — `expect-moved` 3 vs 0, `graphs-agree` 31 vs 34,
`byte-identical` 20 vs 34, `census-rc` `rc=1` vs `rc=0`, `stable-pairs` 4 of 5, `stable-failed` 1 of 5,
`oracle-selfcheck` FAIL vs OK. So `RUN HEALTH` is red whether or not the tree has moved.

---

## 3. WHICH DECLARED INPUTS MOVED

**Determined, by replay, for the move off the run's `substrate-end`.** The mtime census over all 156
members names exactly **1 of 156** written after the run's summary write: `checks/differ.py` at
17:29:01Z (`mtime-census.rows`). The digest moved `a842e832` → `7f84fd3d` in the window that contains
that write. `replay.py` then closes the arithmetic: take the current member list, put
`checks/differ.py` back to the sha the 17:28:36Z reading recorded for it
(`8485eb209e1a…`), fold — and the result **is `a842e832…`**.

```
one-member replay, checks/differ.py@8485eb209e1a -> a842e8323cbebc391833efa9c76d15bb3822ec4355f6050fbaeb9f53a691df64
  == run's substrate-end          True   HIT
```

That is not an inference from a census; it is one member's bytes accounting for the whole digest
change. **The named input that moved is `checks/differ.py` — the gate itself, edited by another unit
while runs were in flight.**

**REFUSED: which inputs moved for the 02:51:48Z run's `9528bb5e`.** I cannot enumerate them, and I
will not guess:

- the run left a digest and **no member list**, so there is nothing to diff;
- the run records **no population size** — `9528bb5e` could have been a fold over 151 members or 156
  and the artifact cannot say. That gap is the exact defect `checks/substrate-manifest.py:146-152`
  names ("`members=` is what keeps a manifest from being MISDIAGNOSED"), and the summary has no such
  row. `pins.rows` carries this as the row `members | ABSENT-IN-SUMMARY`;
- the only per-member record on disk is `runs/graphcmp/MANIFEST.tsv` — **151 members, 2026-10-17T00:35:35Z,
  26 h before the run**, digest `454e8595…` which I re-folded and confirmed. Against it: 7 added,
  2 removed, 40 changed — **49 of 151**. That is the change over 26 hours, not over the run, so it is
  an upper bound on nothing in particular;
- commit reconstruction was tried and **fails for a nameable reason**: 3 commits (`4b42c0ccf`,
  `1af4ba921`, `3001661a7`) fold to `cd6294a5`, `7bef3f1f`, `2b723269`, none of them any recorded
  value — because `bin/bend` is **not in any of those trees**, so the fold must carry `ABSENT` for a
  member the disk has. A reconstruction that cannot represent the population cannot attribute it.

One further observation, offered because it cuts against my own method: the census also shows
`tinybendygrad/mixin/movement.bend` written at **02:52:13Z — 25 s after the 02:51:48Z run's summary**.
But the 17:2x run's `substrate-start` equals the 02:51 run's `substrate-end`, and equal digests mean
equal member lists, so that write did **not** change the file's bytes. **An mtime census over-reports,
and the digest pair is what caught it.** My own unit's replay in §3 is the same argument from the
other side, and it is why the replay rather than the census is the row I stand behind.

---

## 4. THE OTHER 24 ROWS: WHICH ARE FUNCTIONS OF THE TREE

All 24 rows of `D0-run-summary.txt`, classified by where the number comes from — read from the code,
not from the row names:

| class | rows | n | can it rot like a pin? |
|---|---|---|---|
| **read out of a tree file** | `graphs`, `graphs-answered`, `graphs-unset` (via `corpus()` → `graphcmp.py`, a named input) · `substrate-start`, `substrate-end` | **5 of 24** | **the substrate pair: already has.** Three values in 12 minutes. **The graphs triple: yes, and today it has not** — measured `len(corpus()) == 34` against the recorded `34`, at 17:33Z, off a `graphcmp.py` that *has* changed since 10-17. Measured, not assumed. |
| numerator read from a `D/` artifact, **denominator a literal in the code** | `stable-pairs`/`-failed`/`-differ` (`of 5`, `STAB` :241) · `plants-disagree` (`of 7`, `PLANTS` :230) · `controls` (`of 5`, :237) · `cross` (`of 1`) · `conflations` (`of 4`) | 7 of 24 | **yes, and silently.** The `of 5` is a claim about `STAB`'s length in the source. Add a stability pair and the denominator does not move, so `5 of 5` can become `5 of 6` and read as perfect. Same shape as the `59 → 1168` decay this audit was commissioned against: a number in a document. |
| read from the child `ENV` | `dev`, `lc_all`, `noopt`, `pythonhashseed` (`precondition_rows()` :824) | 4 of 24 | no — they are conditions, not claims, and `preconditions_bad()` compares them to the same table |
| measured from the artifacts the run wrote | `graphs-agree`, `graphs-disagree`, `byte-identical`, `not-comparable`, `expect-moved`, `selfcheck`, `oracle-selfcheck`, `census-rc` | 8 of 24 | they cannot rot, but they are **old** — they are facts about a mixture, and a reader comparing them to today's tree is comparing to `D/`, not to the tree |

So **5 of 24** rows are tree-derived, **7 of 24** carry a code-resident denominator, and **8 of 24**
are honest measurements of artifacts that no longer describe one substrate. `oracle-selfcheck` and
`census-rc` sit in the last bucket by mechanism and in the first by consequence: the census is
produced by `.agents/slop/graphcmp-*.py`, which are named inputs, so the *oracle* is tree-coupled
even though the row is read out of `D0-coverage-census.txt`.

---

## 5. VERDICT

**This run's evidence is not valid for the tree as it is now, and — by the tree's own reading — it
was never a valid measurement of one thing.**

1. `substrate-start ≠ substrate-end` in the live artifact (`a842e832` vs `7f84fd3d`), so `D/` is a
   **mixture of two substrates**. Measured by `differ.substrate_bad()` at 17:33:57Z. Every
   `graphs-agree`, `byte-identical` and `VERDICT:` row in `D/` was written across a change to
   `checks/differ.py` at 17:29:01Z.
2. Both recorded rows are already superseded. The substrate has taken **3 distinct values** and the
   summary has been rewritten **3 times** since 17:22Z; the tree is moving every few minutes, so
   "still fresh" is not a property this artifact can be said to have at any instant.
3. Independently: **10 of 17 pins agree**. The run is red whether the tree moved or not.

What would make it answerable rather than merely observable — none of it done here, all of it named:

- a `members=` row beside the pair, so a digest is never read without its population (the row
  `members | ABSENT-IN-SUMMARY` is the finding);
- the two-row bracket compared against **the tree at the moment of reading**, which is what
  `checks/substrate-current.py` exists for — note `checks/substrate-manifest.py`'s own finding, that a
  reader using a *different* population (151 vs 153 members, different sort key) answers `REFUSED` on a
  tree that has not moved a byte, so the reader must be `differ.substrate_digest()` itself;
- and the honest root cause, which is not a hashing defect: **a corpus run cannot be a one-substrate
  measurement while another unit edits `checks/differ.py`, which is itself a declared input.** The
  pair is doing its job — it is reporting `MIXTURE` — and the thing to fix is the concurrency, or the
  choice to put the gate's own source inside the set of bytes the gate certifies.

### Files, and how to re-take

| file | what it is |
|---|---|
| `retake.py` | writes `live-entries.rows` (one row per declared member) and prints the writer's digest + an independent replay of it |
| `measure.py` | parses the summary, calls `substrate_bad()`/`corpus()`, writes `pins.rows`, `timeline.rows` (appended), `moved.rows`, `mtime-census.rows` |
| `replay.py` | the one-member prediction in §3. It can print `MISS`, and a `MISS` is reported as a miss |
| `attrib.py` | the commit-reconstruction attempt that §3 records as failing, kept so the failure is not re-run blind |
| `pins.rows` · `timeline.rows` · `live-entries.rows` · `moved.rows` · `mtime-census.rows` | the measurements |

```
.venv/bin/python .agents/slop/pinfresh/retake.py && .venv/bin/python .agents/slop/pinfresh/measure.py
```

### One defect of this unit's own, disclosed

The first snapshot was written with a header line that had no trailing newline, so **the writer ate
its own first member row**, and re-taking the snapshot overwrote it. That is why §3 is a *narrow*
one-member replay and not a full 156-member reconstruction of the run's substrate. Found by the
replay failing (S1 folded to `0a4ec6a4…`, not the `a842e832…` the reading had reported), fixed in
`retake.py`, and the corruption is disclosed here rather than quietly replaced. The four timeline
rows above are the measurements that survived it.