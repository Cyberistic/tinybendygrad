# EMPTY EVIDENCE — a 0-byte capture records nothing, and most of them are duplicates of a token recorded elsewhere

**Discovery pinned at `46cfa894a`** (2026-10-06). HEAD moved to `794dc3dbf` while this was being
written: **4854 → 4909 tree paths, 273 → 274 empty.** The +1 is another ADDED empty capture
(`.agents/slop/substrate2/names-only.err`), not a truncation — the same growth the prior
`emptyblob` audit measured (**246 → 273 inside one session**). **Re-run this; do not quote it.**

**Answer, in one line.** Of the **201** empty captures the prior audit called SENTINEL/UNKNOWN,
**168 are REDUNDANT** — the producer's exit code or verdict token is recorded in a named sibling
ledger, so the empty file is duplication. **2 are HOLE** — the producer is named, nothing records
its token, so the empty file is a gate that cannot be re-read. **31 are UNCLASSIFIED** — no
producer and no token. **No capture among the 201 is the `.rows` kind, because there are zero
empty `.rows` in the whole tree** — row dumps are never empty, which is exactly why they are
the right shape for expected values.

---

## 1. Population — declared by discovery, not by a list

| source | command | tracked paths | at empty blob |
|---|---|---|---|
| HEAD tree, pinned `46cfa894a` | `git ls-tree -r 46cfa894a` | **4854** | **273** |
| HEAD, live `794dc3dbf` | `git ls-tree -r HEAD` | **4909** | **274** |

The walk is `.agents/slop/emptyevid/discover.py`: `git ls-tree -r <rev>` → field **2 = SHA**
(the output is `MODE TYPE SHA\tPATH`; an earlier revision of this instrument read field 1 and
counted **0**, which is doctrine 1 reproduced inside the census *of* doctrine 1). `git ls-files -s`
is deliberately **not** used: it answers the empty blob for `git add -N` placeholders and once
inflated this population to **1252**.

**The 201 is the prior audit's SENTINEL/UNKNOWN class, and discovery reproduces it exactly.**
Taking every empty file whose extension is a capture extension (`.err .out .stdout .stderr .said
.log`) gives **227**; removing the 26 that the prior audit classed INTENTIONAL (21 planted
fixtures), TRUNCATED (3) or UNCLASSIFIED (4 `.said` + `langs/out/clang.log`) leaves **201
exactly**. So the subset is not carried over — it falls out of two independent walks.

---

## 2. Split of the 201 by extension and by producer

By extension:

| ext | count | note |
|---|---:|---|
| `.err` | **129** | empty stderr |
| `.out` | **67** | empty stdout |
| `.stderr` | **3** | `skipexit/{BEFORE,AFTER,AFTER2}.stderr` |
| `.stdout` | **2** | `abi4check/now-{py3,venv}.stdout` |
| **`.rows`** | **0** | **no row dump is empty — see §0** |
| other | **0** | |

By what WROTE them (`.agents/slop/emptyevid/findproducers.py`, `git grep -F` for the full path
and the basename, census artifacts excluded):

* **69 of 201** have a producer *derivable from the name* — the census/batch dirs encode the
  command (`checks_al-verdict.py.err` means `checks/al-verdict.py`). These are the `gatesrun/`
  (27) and `canrun/census/` (42) families.
* **4 of 201** have an in-tree **write site** — a committed script whose text contains the path
  *and* a redirection/`write_text` on that line:

  | capture | writer | line |
  |---|---|---|
  | `.agents/slop/canrun/gate.out` | `checks/gate_norm.py` | `:261` `(HERE / "gate.out").write_text(text)` |
  | `checks/check.out` | `.agents/slop/one.sh` | `:47` `./bin/bend "$f" --check-only >"$d/check.out" 2>"$d/check.err"` |
  | `oracles/sb-oracle.err` | `checks/sb-gate.sh` | `:153` `... python $ORACLE > $D/sb-oracle.txt 2> $D/sb-oracle.err \|\| {` |
  | `.agents/slop/substrate/artifacts/pop/oracle.err` | `checks/sb-gate.sh` | `:153` |

* **132 of 201** have **no script reference at all**. They were produced by ad-hoc shell
  invocations — the command and its exit status were never committed. That is the root of the
  whole problem: the producer is not in the tree, so only a *token written next to the capture*
  could ever have made it re-readable.

---

## 3. IS A 0-BYTE CAPTURE EVIDENCE OF ANYTHING? **No — never by itself.**

An empty `.err`/`.out` cannot distinguish *"exited 0 and wrote nothing"* from *"was killed before
it wrote anything."* `AGENTS.md` already records the failure verbatim: a unit whose *"first RSS
pass sent stdout to `/dev/null` and `bend` answered `out=0B peak-RSS=32 MB` four times running.
THAT IS A DEAD LANE, NOT A CHEAP BUILD."* So the empty file must be paired with the producer's
rc/token *somewhere else*; only then is dropping or ignoring it free.

**The good news, measured: the good units already do this.** Where a unit ran a batch, it wrote a
structured ledger beside the captures:

| family | token ledger | what it records |
|---|---|---|
| `.agents/slop/gatesrun/` (27 caps) | `gatesrun/CLASSES.tsv` | `path · class · rc · token · cause · answer` — **27/27 covered** |
| `.agents/slop/canrun/census/` (42 caps) | `canrun/census/rc.tsv` + `rc-venv.tsv` | `producer<TAB>rc` — **41/42**; the 42nd (`test_rewrite_bottom_up_gate`) is `rc=0 PASS` in `gatesrun/CLASSES.tsv:67` and `canrun/canfail.tsv:67` |
| `.agents/slop/rerun/D-before/` (47 caps) | `D-before/D0-run-summary.txt` + `D1-verdicts.txt` | aggregate verdict tokens + per-graph `VERDICT=` |
| `.agents/slop/spine/` (19 caps) | `spine/SPINE.md` | `BEFORE rc=1` / `AFTER rc=0`, `[bounded] WITHIN-LIMITS`, the 16 diff verdicts |
| `.agents/slop/censroot/` (4 caps) | `censroot/statuses.tsv` | `before_rc` / `after_rc` / `before_verdict` / `after_verdict` |

**So the empty capture is almost always REDUNDANT: the token is the evidence, and it lives in
a `.tsv`/`.rows`/`.md` that a reader can actually read.**

---

## 4. Three classes, with denominators

`.agents/slop/emptyevid/classify.py` → `.agents/slop/emptyevid/CAPTURES.tsv` (201 rows:
`path · ext · producer_name · token_recorded_elsewhere · class`).

| class | count | meaning |
|---|---:|---|
| **REDUNDANT** | **168** | the producer's rc/verdict token is recorded in a named committed file (column 4 names it) |
| **HOLE** | **2** | the producer is named, **nothing else records its token** — the empty file is the only record and it records nothing |
| **UNCLASSIFIED** | **31** | no producer established **and** no token — the run's command and status are not in the tree |

**`168 + 2 + 31 = 201`.** `UNCLASSIFIED` is **not** `REDUNDANT`: a capture whose producer was an
ad-hoc shell that wrote no token is a gap in the evidence ledger, not a duplicate of one.

### HOLE — 2
```
.agents/slop/canrun/gate.out   writer checks/gate_norm.py:261   no token file anywhere
checks/check.out               writer .agents/slop/one.sh:47   no token file anywhere
```
`gate_norm.py:261` writes the file but never records the gate's rc beside it. `one.sh:47`
redirects `bend --check-only`, then uses `[ -s check.err ] || [ -s check.out ]` to call the
attempt *void* — an in-memory decision that is never written down. **A 0-byte `check.out` after a
`check-only` that exited 0 and a `check.out` after a `bend` that died before printing are the same
file.** That is the task's target exactly.

### UNCLASSIFIED — 31
Whole families, by what is missing:

* **`.agents/slop/loopfix/` (13)** — `b-fold-{new,old,probe,v2}.out`, `b-gcmp-{final,new,old,v2}.out`,
  `b-insprobe{,-old,-v2}.out`, `build-base.out`, `fbuild-base.out`. `loopfix/FINDINGS.md` and
  `rss-ledger.rows` record build tokens for *attempts* (`attempt1 KILLED-ON-MEMORY rc=-9 …`) but
  **name none of these files**, so the mapping cannot be established from the tree. (The two
  loopfix `.err` that *do* have `.rows` siblings — `loop-before`, `oracle-rng` — are REDUNDANT.)
* **`.agents/slop/skipexit/artifacts/` (6)** — `{FAIL,GREEN,SKIP}.{pre,post}-fix.err`; the dir has
  **zero non-capture siblings**. The parent `skipexit/FINDINGS.md` documents whole-run rcs
  (`BEFORE.rc=0`, `AFTER.rc=1`, `AFTER2.rc=4`) but not these six.
* **`.agents/slop/rerun/` (6)** — `probe-{flip,lin,loop}.err` and `probe-loop-{METAL,NULL}.err`,
  `retention-after.err`: probe captures whose producer is not in the tree.
* **`oracles/baseline-probe.err` (1)** and **`oracles/nested/baseline-probe.err` (1)** — no
  producer, no token.
* **`.agents/slop/censroot/` (2)** — `full-corpus.err`, `repro.err`; `statuses.tsv` covers the
  census/hermetic pair, not these.
* **`.agents/slop/canrun/` (2)** — `beltA.out`, `beltB.out`; `canrun/REPORT.md` names the gate
  table but not the belt captures.
* **`.agents/slop/arghalf/arity.out` (1)**, **`.agents/slop/bitcastrow/fold-base.err` (1)** — the
  units' `FINDINGS.md`/`README.md` discuss the underlying measurement but do not name the capture.

---

## 5. The rule that stops the growth

**Proposed rule.** *A capture file is written only when its stream is non-empty; and the
producer's exit token is written to a sibling `.tsv` row (`name<TAB>rc<TAB>token`) regardless of
emptiness.*

Measured against the producers found:

* **All 201 empty captures never get written** (they are 0 bytes). The 168 REDUNDANT lose nothing —
  their token is already in the ledger named in `CAPTURES.tsv` column 4.
* The **2 HOLE** and **31 UNCLASSIFIED** gain the one thing they lack: a token row. `check.out` and
  `gate.out` become re-readable; the 31 ad-hoc runs stop being invisible.
* **Net: 201 empty files prevented, 33 evidence gaps closed, 0 tokens lost.**

A weaker rule — *"write a capture only if non-empty"*, with no token clause — would still prevent
all 201 empty files, but it would leave the 2 HOLE and 31 UNCLASSIFIED with **no record at all**;
those runs would remain un-re-readable, only now without even a 0-byte marker. **The token clause
is not optional for the 33.**

**Not implemented.** The producers are dozens of units' files, and this brief is read-only.

---

## 6. What I did NOT do

* Did not delete, truncate or restore a single file. `git status` untouched.
* Did not run `bend`.
* Did not settle the two HOLEs' producers' actual exit status — that requires re-running the
  producers, which other units own.

## Artifacts (`READ-ONLY` elsewhere)
* `.agents/slop/emptyevid/CAPTURES.tsv` — 201 rows: `path · ext · producer_name · token_recorded_elsewhere · class`.
* `discover.py` (population by `git ls-tree -r <rev>`), `extsplit.py` (ext histogram),
  `findproducers.py` (`git grep` write sites), `resolve.py` (script-vs-census split),
  `siblings.py` (per-dir token candidates), `classify.py` (the three classes above).
* `population.json`, `producers.json`, `script_refs.json`, `siblings.json`, `classified.json`.
