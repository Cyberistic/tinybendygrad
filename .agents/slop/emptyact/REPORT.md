# emptyact — close the 33, not the 201

**HEAD `c7e8a530b`.** Read `.agents/slop/emptyevid/REPORT.md` (the census) and its
`CAPTURES.tsv` (201 rows). This unit acts on the **2 HOLE + 31 UNCLASSIFIED** it left open.
Nothing deleted, truncated or restored; no file outside `.agents/slop/emptyact/` written.

## 1. The denominator — reproduced, but the two witnesses name different 31

`.agents/slop/emptyact/derive.py` re-reads `CAPTURES.tsv` and counts:

```
REDUNDANT=168  HOLE=2  UNCLASSIFIED=31  total=201  targets=33
```

**The count reproduces: 2 + 31 = 33.** The **membership does not.** The census's own two
witnesses disagree by exactly a swap of two:

| witness | its 31 UNCLASSIFIED |
|---|---|
| `CAPTURES.tsv` class column | 13 loopfix · 6 skipexit · 6 rerun · 2 oracles · 2 censroot · **1 arghalf · 1 bitcastrow** |
| `emptyevid/REPORT.md` §4 (and the brief) | 13 loopfix · 6 skipexit · 6 rerun · 2 oracles · 2 censroot · **2 canrun/belt{A,B}** |

`beltA.out`/`beltB.out` are classed **REDUNDANT** in `CAPTURES.tsv` (rows 11-12) while the
prose that enumerates the 31 counts them UNCLASSIFIED; `arghalf/arity.out` and
`bitcastrow/fold-base.err` are UNCLASSIFIED in the TSV and absent from the prose. Intersection
**29**, union **35** (33 + the 2 belt). I acted on the **union**; `TOKENS.tsv` has 35 rows.

## 2. HOLE — 2/2 closed, and one of the two attributions was a basename error

The census attributed `canrun/gate.out` to `checks/gate_norm.py:261`. That line writes
**`checks/gate.out`** (`HERE / "gate.out"`, `HERE` = `checks/`), a different path that does not
exist. The match was a **basename** `git grep gate.out` — doctrine 1 reproduced inside the census
of doctrine 1. The real producer is named by the non-empty sibling `canrun/gate.err`:

| hole | real producer | act | rc | token |
|---|---|---|---|---|
| `.agents/slop/canrun/gate.out` | `checks/gate.py` (its `drive.mjs` refusal) | **re-ran, no `bend`** | **3** | `REFUSED` |
| `checks/check.out` | `.agents/slop/one.sh:47` (`./bin/bend … --check-only`) | **not re-run — needs `bend`** | `-` | `SOME PROOFS FAIL` |

* `canrun/gate.out`: `.venv/bin/python checks/gate.py` → `rc=3`, stdout empty, stderr **byte-equal
  to the committed `canrun/gate.err`** (`== REFUSED, NOT A VERDICT: input absent: … checks/drive.mjs`).
  A REFUSED needs no `bend`. Closed.
* `checks/check.out`: `one.sh` needs `bend`, which this unit must not run, **but the token is already
  in its non-empty sibling `checks/check.err`** (`SOME PROOFS FAIL`, with the failing law). `one.sh`
  never reads `bend`'s rc by design, so rc is `-`; the verdict token is recovered. Closed.

**Both "holes" were mis-classified: the token lives in the sibling capture, which the census only
looked for in *named ledgers*, not in the other stream.** The rule is right; the census under-counted
the evidence.

## 3. UNCLASSIFIED — producers recovered

Of the 31: **producer recovered 22 · producer unknown 9.** Recovery all came from the
**non-empty sibling capture**, which the census did not read:

| family | n | producer, from the sibling | token |
|---|---:|---|---|
| `loopfix/b-*.out`, `*-base.out` | 13 | `./bin/bend … -o`, named verbatim in `b-*.err` | **rc=0 `WITHIN-LIMITS`** |
| `arghalf/arity.out` | 1 | `./bin/bend .agents/slop/arghalf/arity.bend --check-only` in `arity.err` | **rc=1 `SOME PROOFS FAIL`** |
| `censroot/repro.err` | 1 | `.agents/slop/censroot/repro.py` (write site `repro.py`, commit `457b81619`) | `PASS` |
| `censroot/full-corpus.err` | 1 | `checks/census.py` full corpus (recoverable from `full-corpus.out` content) | not recorded |
| `skipexit/artifacts/*.err` | 6 | `.agents/slop/skipexit/repro.py` (write site `:102`) | not recorded |
| `canrun/belt{A,B}.out` | 2 | `checks/norm_check.py` belt directions 1/2 (named in `beltA/B.err`, REPORT §7) | **rc=3 `REFUSED`** |
| `rerun/probe-*.err`, `retention-after.err` | 6 | **unknown** — ad-hoc `graphcmp.py`/`retention-check.py`; no committed producer | — |
| `oracles/baseline-probe.err` | 1 | **unknown** — `.rows` sibling is the only witness | — |
| `oracles/nested/baseline-probe.err` | 1 | **unknown** — a `jj` rename artefact of empty `helpers.bend` (`W64-MILE.md:300-308`) | — |
| `bitcastrow/fold-base.err` | 1 | **unknown** — added with `fold-base.txt` in `22580ecca`; no producer committed | — |

**Producers I own, named per file (the brief's own test):**
`.agents/slop/skipexit/repro.py` **owned** · `.agents/slop/censroot/repro.py` **owned** ·
`.agents/slop/one.sh` **owned** (but its capture is `checks/check.out`, outside my lane).
`checks/gate.py` and `checks/gate_norm.py` are **not** mine. The loopfix/arghalf producers are
`bend` invocations with no committed script — **not owned, do not exist as files.**

## 4. The token clause, applied

`TOKENS.tsv` (header `name<TAB>rc<TAB>token`, 35 rows):

* **19 rows carry a recovered `rc` + verdict token** → 19 runs re-readable (loopfix 13, arghalf 1,
  `gate.out` 1, belt 2, `check.err`→`check.out` 1, `repro.err` 1).
* **7 rows `not-recorded`** — producer found, but it is not re-runnable here (`skipexit` 6 need
  `bend`/`node`/`cc`; `full-corpus` 1) and the producer never persisted its rc. No token invented.
* **9 rows `producer-unknown`** — no producer in tree or history; a token would be a guess.

**Of the 33 the census defines: 17 closed · 16 open with a reason.** (7 `not-recorded`, 9
`producer-unknown`.) By the brief's prose enumeration the recovered count is 18 (belt swap). The
weakness the census named is confirmed and larger than 33: **the sibling capture is where the token
already was, and reading both streams closes 17 of 33 without re-running anything.**

## 5. What I did NOT do
Did not delete/truncate/restore any file. Did not run `bend`. Did not touch `checks/`, `gates/`,
`AGENTS.md`, `runs/`, `tinybendygrad/`. Did not commit.
