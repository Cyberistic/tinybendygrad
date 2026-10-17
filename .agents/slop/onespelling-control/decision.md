# IS THE CONTROL WRONG, OR THE INSTRUMENT? — `.agents/slop/onespelling/census.py` pos1

**MEASURED 2026-10-17T00:42Z–00:47Z at HEAD `444890672d9baebb6309952495f480623f481fc5`**, and
**re-confirmed at `3173198bd80e2c1ba28d635d7c0f8121fac31a37`** (HEAD moved under me at 00:47Z; `measure.py`
re-run there and **every number below is identical** — same 2-site population, same verdicts, same 764→3618,
same 3612/3618, same control outcomes).
Instruments: `measure.py` → `measure.rows` (this directory), `census-proposed.py` → `census-proposed.rows`
(a **copy** of the census carrying a one-line control change; its `--rows` points here, so
`.agents/slop/onespelling/findings.rows` was not overwritten and still reads 16:22 local, mtime unchanged).

**Nothing outside this directory was modified.** `shasum` of `.agents/slop/onespelling/census.py` and of
`checks/repro-paths.py` equals `git show HEAD:<path> | shasum` for both (`3e3481a02072`, `a0fc2cc800b8`).
One disclosure: importing `census.py` by path made Python write `.agents/slop/onespelling/__pycache__/`, which
I deleted at 00:47Z (the directory is gone; `census.py`, `findings.rows` and `REPORT.md` are as they were —
16:20/16:22 local).
No `bend`, no `checks/differ.py`, no `gates/` execution, no `checks/e2e*`, no `sweep.py`, `bounded.py`,
`repro-paths.py`, `pytest`, `mypy`, `ruff`; `gates/docnum-census.py` was read and parsed, never run.
Eleven process invocations, never two at a time: `measure.py` ten times (1.2 s, 65 MB peak each) and
`census-proposed.py` once (8.74 s, **342 MB peak** — the one place I went over the 120 MB guidance,
deliberately, once, for the exact post-fix denominators).

---

## 1. THE CAUSAL CHAIN, LINE BY LINE

The refusal is `census.py:481`'s message for `CONTROLS[0]`:

| line | text | what it does |
|---|---|---|
| `census.py:467` | `("pos1 anchored path regex", "regex-anchor-set", "POSITIVE", "checks/repro-paths.py"),` | the assertion that fails |
| `census.py:479-481` | `if not [r for r in rows if r["kind"] == kind and frag in r["site"] and r["verdict"] == verdict]:` → `bad.append(f"{label}: no {verdict} {kind} site matching {frag}")` | asks for a **POSITIVE row at that path** |
| `census.py:349` | `elif rx is not None and widened(rx) is not None:` → `entry["kind"] = "regex-anchor-set"` | the classifier; `widened()` (`:174-179`) only recognises a source opening `(?:^|…)` |
| `census.py:357` / `:368` | `group.append(entry)` … `found = [e for e in group if e["kind"]]` | the literal is still extracted and still counted in `stats["spellings"]`, but a `kind` of `None` never becomes a row |
| `census.py:525-529` | `if failures: print("SELFCHECK REFUSED -- nothing written", file=sys.stderr); return 3` | the run ends here, so `:535` never runs and **nothing is written** |

**Measured, not inferred.** The same file at the **parent of the fix** and at HEAD, through the census's own
`literal_sites()` + `probe_regex()` (`measure.py` §7, `measure.rows` lines `fix-commit`/`before-fix`/`after-fix`):

```
THE FIX COMMIT FOR checks/repro-paths.py : 08957587170ef6ea323c8131180e3bf68e45ddf1  (ancestor of HEAD: True)
   subject: repro-paths: widen the anchor AND split the rows, so the 46 actionable findings surface
   checks/repro-paths.py@3a195037176e  literals=4  sites=1  spellings={'re.compile': 2}
      regex-anchor-set   REF    POSITIVE yes   anchored 764, anchor dropped 3618, 2854 invisible (568 .md)
   checks/repro-paths.py@HEAD         literals=6  sites=0  spellings={'re.compile': 2, 'Tuple': 1}
   -> the fix alone moves the census by 1 site and 1 POSITIVE
```

So the chain is exactly as described: `REF` went from `(?:^|\s)(…)` to `(?<![\w/.])(…)`; `widened()` returns
**`None`** for the new source (measured); the kind never fires; `checks/repro-paths.py` now contributes
**0 rows** (`grep -c repro-paths census-proposed.rows` = **0**); the comprehension at `:480` is empty; rc 3.
Its other five controls are intact — with only `:467` changed, the census prints
`selfcheck : OK -- 6 controls, the FS_DELETES trap, and every literal spelling read` and exits 0.

**What pos1 is trying to prove.** That the `regex-anchor-set` *probe* still works: the extractor still
recognises a leading delimiter-class anchor, and `probe_regex` still separates "anchored names `old`" from
"anchor dropped names `new`" over real prose (`census.py:263-288`). The path was a **proxy** for that
capability, picked because that file was the class's known instance.

---

## 2. VERDICT: **THE CONTROL IS WRONG.** The instrument is right, and no instrument change can help.

Four independent reasons, each with its measurement or its line:

1. **A control that pins a defect cannot survive the defect's repair.** `census.py:23` defines the verdict:
   *"POSITIVE — a second spelling exists in this tree and this site cannot see it."* A repaired site stops
   being POSITIVE because there is no second spelling left to miss. The census going quiet on that file is the
   census **working**. `pos1` asserts a positive *finding*; that is asserting the tree stays broken.
2. **It pinned the class's only true instance, and the fix resolved it.** `.agents/slop/onespelling-precision/
   sample.rows:42-44` hand-labelled the whole `regex-anchor-set` population: `probe.py:26 OLD` **FALSE**
   ("a deliberately retained supersession fixture"), `probe.py:27 PERMISSIVE` **FALSE** ("byte-identical to the
   shipped fix … the census charges the proposed FIX for the defect it fixes"), `checks/repro-paths.py:64:REF`
   **TRUE**. pos1 pinned the single TRUE one. A control whose subject is the thing under test is the defect
   class `AGENTS.md` documents as `.agents/slop/toolsledger/extract.py` — one base resolving every token.
3. **The census already made this exact correction once, on a different control.** `REPORT.md:131-132`:
   *"**`no site was extracted from a frozenset(Set) literal`** — the control was asking about sites when the
   question is about extraction. Moved to the population census, where it is answerable."* pos1 is the same
   mistake in a different coat: it asks about **a site** when the question is about **the probe**.
4. **A path fragment in a control tuple is a hand list**, which is doctrine 1's forbidden shape: populations
   are discovered by walking or by the generator's own declaration, never written down.

**And the instrument behaved correctly at every step.** `widened()` returning `None` for a pattern with no
leading `(?:^|…)` is right, not a bug; if the classification were forced anyway, `probe_regex` (`:267-268`)
would answer `UNKNOWN, "?", "no leading (?:^|...) anchor; not a delimiter-set regex"` — a row that can never be
anything but a guess, i.e. **DEAD**. `AGENTS.md`'s doctrine 2: a gate that exits 0 having measured nothing is
worse than no gate. Refusing with rc 3 and writing nothing is the correct outcome of a control that caught a
real change. **Change the control, not the census.**

---

## 3. THE MINIMAL FIX — one token, and it is measured green

**The diff I ran** (`census-proposed.py` vs `HEAD:.agents/slop/onespelling/census.py`, `diff` shows one line):

```diff
--- HEAD:.agents/slop/onespelling/census.py
+++ .agents/slop/onespelling-control/census-proposed.py
@@ -467 +467 @@
-    ("pos1 anchored path regex", "regex-anchor-set", "POSITIVE", "checks/repro-paths.py"),
+    ("pos1 anchored path regex", "regex-anchor-set", "POSITIVE", ""),
```

`frag=""` satisfies `frag in r["site"]` for every site, so the tuple now asks the **population** question the
control was always for: *does this kind still produce this verdict anywhere in the tree?* The honest spelling
of the same semantics is `None` plus a two-line predicate, if `""` reads as a trick:

```python
    ("pos1 anchored path regex", "regex-anchor-set", "POSITIVE", None),
```
```python
        found = [r for r in rows if r["kind"] == kind and r["verdict"] == verdict
                 and (frag is None or frag in r["site"])]
        if not found:
            bad.append(f"{label}: no {verdict} {kind} site" + (f" matching {frag}" if frag else ""))
```

I ran the `""` form, not the `None` form; the predicate is identical, and I do not claim to have executed the
second.

**Measured result of the fix** (`census-proposed.rows`, one run, rc 0, `selfcheck : OK`):

```
population : 1889 committed .py, 568 committed .md, 7435 committed paths -- every one from `git ls-tree -r HEAD`
module-level literals examined : 101396  (from 1421 .py parsed; 468 dropped by the column-0 grammar gate)
CANDIDATE SITES : 316   extension-set=50  module-attr-table=3  prose-basename-citation=255  regex-anchor-set=2  single-base-resolver=6
bare basenames cited : 4379, ambiguous 255
VERDICTS : NEGATIVE=30  POSITIVE=260  UNKNOWN=26
```

**What power the fix keeps, stated as the failure it still catches:** if `widened()` breaks, if the
`regex-anchor-set` classification breaks, or if `probe_regex`'s `len(new) <= len(old)` comparison inverts,
this kind yields **zero** POSITIVE rows and the census REFUSES again — which is precisely the capability the
control was buying. **What it gives up:** sensitivity to the loss of *one* site. That loss is the census's
job to report, not the control's job to forbid.

**The strictly-smaller alternative, if a path pin is wanted** (measured `holds=True`, `measure.rows`
`control frag='.agents/slop/reprorefs/probe.py'`):

```python
    ("pos1 anchored path regex", "regex-anchor-set", "POSITIVE", ".agents/slop/reprorefs/probe.py"),
```

Same one token, same rows. **Its cost, and it is real:** it pins the two rows the precision report measured
**FALSE**, and `.agents/slop/` is the tree that has already lost 85+ committed paths to pruning (`AGENTS.md`
re-measurement 2026-10-07), so this variant is a control that rots the next time a finished unit's directory
is swept. The population form cannot rot that way. **Recommended: the population form.**

---

## 4. THE REPLACEMENT POSITIVE, MEASURED

The whole population for `regex-anchor-set` at HEAD is **2 sites**, because the kind requires a module-level
`re.compile` whose source opens `(?:^|…)` — a **necessary condition**, so `git grep -F '(?:^|' HEAD -- '*.py'`
(9 files) is a *superset* and the census's own `literal_sites()` over those 9 files is the exact population,
without `ast.parse` over 1 889 files. Both survivors are POSITIVE under the census's own `probe_regex` over
HEAD's 568 committed `.md` (`measure.rows`):

| site | verdict | evidence at 568 `.md` |
|---|---|---|
| `.agents/slop/reprorefs/probe.py:26:OLD` | **POSITIVE** | anchored **593**, anchor dropped **1412**, **819 invisible**; delimiters `` ` ``×5548, ` `×1518, `\n`×156, `/`×84, `"`×42 |
| `.agents/slop/reprorefs/probe.py:27:PERMISSIVE` | **POSITIVE** | anchored **764**, anchor dropped **3618**, **2854 invisible**; delimiters `` ` ``×9660, ` `×3217, `'`×721, `/`×668, `\n`×212 |

```
CONTROLS OF THIS KIND, AS `selfcheck()` ASKS THEM
   frag='checks/repro-paths.py'            holds=False      <-- today's refusal
   frag='.agents/slop/reprorefs/probe.py'  holds=True
   frag=''                                 holds=True
```

**And a bonus measurement that matters for the precision report:** the byte-identity it relied on is now gone.

```
probe.py:27 PERMISSIVE == the SHIPPED pattern BEFORE the fix ? True
probe.py:27 PERMISSIVE == the SHIPPED pattern AFTER  the fix ? False
```

So the fix has also made `probe.py:27` stop being a duplicate of the shipped gate — R4 in the precision
report ("A FIXTURE IS NOT AN INSTRUMENT", triggered by "byte-identical to another site in the tree") can no
longer fire on it by that rule; only the same-file-comment rule (`probe.py:23-25`) still catches it.

---

## 5. WHAT THE FIX COSTS — every number that goes stale

### `.agents/slop/onespelling/REPORT.md` (written at HEAD `037d5d536e`, 551 `.md`)

| claim in REPORT.md | stale because | post-fix value at `444890672` |
|---|---|---|
| header: `1835 .py, 551 .md, 7308 paths` | HEAD growth | **1889 / 568 / 7435** |
| `module-level literals examined : 100951 (1369 parsed; 466 dropped)` | growth | **101396 (1421; 468)** |
| `CANDIDATE SITES : 307` | growth **+3**, the fix **−1** | **316** |
| `extension-set=47 … prose-basename-citation=248 … regex-anchor-set=3` | growth, and the fix | **50 / 255 / 2** |
| `bare basenames cited : 4228, ambiguous 248` | growth | **4379 / 255** |
| `VERDICTS : NEGATIVE=27 POSITIVE=254 UNKNOWN=26` | growth, and the fix | **30 / 260 / 26** |
| **class table row 1** (`checks/repro-paths.py:64 REF` — "`^` or whitespace" vs backticks) and **§POSITIVE "`regex-anchor-set`, 3 sites, and this is known positive #1 … 2782 spellings invisible"** | **the instance was resolved by commit `0895758717`** — this is the fix, not growth | **2 sites**: `probe.py:26 OLD` 819 invisible, `probe.py:27 PERMISSIVE` 2854 invisible |
| §POSITIVE `prose-basename-citation, 248 of 4228 cited` | growth | **255 of 4379** |
| §NEGATIVE `extension-set, 24` at such a call | growth | **27** (of 50; the other 23 UNKNOWN) |
| §UNKNOWN "19 `extension-set`, literal sets … " | growth | **23** literal-set UNKNOWN |
| exit-code legend `0 written, 3 REFUSED, 1 error` | still true | unchanged |

**Also stale, and it is a file I was told not to edit:** `census.py`'s **own docstring**, line 5
(`a delimiter class in a regex  checks/repro-paths.py REF: (?:^|\s) cannot see a backticked path`) and line 20
(`if any of that fails it exits 3 having written nothing`). The census's self-description still advertises
instance #1 as live. Flagged, not touched.

### `.agents/slop/onespelling-precision/REPORT.md` (at HEAD `03500a2620`, 554 `.md`)

| claim | stale because |
|---|---|
| §0 table `regex-anchor-set │ POSITIVE n=3 │ sampled 3 (the whole population) │ TRUE 1 │ 0.333 │ [0.061, 0.792]` | n drops **3 → 2** and both survivors are the two rows it already labelled **FALSE**, so the kind now has **0 true findings in the tree**. The precision estimate is **withdrawn, not recomputed**: on 0 of 2 the same `intervals.py` formula gives Wilson **[0.000, 0.658]** (recomputed with its `wilson(t, k)`, which reproduces its published [0.061, 0.792] for 1/3 exactly). |
| "`251 of the 257 positives (97.7 %) are ONE kind`" | **255 of 260 = 98.1 %** |
| §5 "`69 + 1 + 2 = 72`" | the middle term is **0**: `69 + 0 + 2 = 71` |
| §3.2 "`TRUE — checks/repro-paths.py:64:REF` … This is the census at its best" and its quoted histogram `` ` ``×9078 | the row **no longer exists**; today's equivalent measurement is §4 above |
| §3.2 "`FALSE — probe.py:27 PERMISSIVE. Byte-identical to the shipped fix`" | **no longer byte-identical** to anything shipped (§4) |
| **R4** "`releases 2 rows today`", triggered by "byte-identical to another site in the tree" | would now release **0** by the byte rule; only the same-file-comment rule fires, so R4 needs the pattern of a *former* commit, i.e. `git log` archaeology |
| `census-run.rows` (311 rows) and `sample.rows:44` (`…repro-paths.py:64:REF TRUE`) | already stale by growth; now stale by the fix too — `sample.rows:44`'s subject is retired |
| §6 "`The census's own REPORT was 4 sites and 3 positives out of date`" | now **9 sites and 6 positives** (307→316, 254→260) |

---

## 6. PLAIN ANSWER TO THE LAST QUESTION

**No — the census should not be able to find `checks/repro-paths.py` as a POSITIVE again, and the finding was
correctly RESOLVED by commit `0895758717`.** Measured, in the shipped instrument's own terms, over the same
568 committed `.md`:

| pattern | names | a pattern with **no** leading-anchor clause names | invisible |
|---|---|---|---|
| shipped before the fix, `(?:^|\s)(…)` | 764 | 3618 | **2854** |
| shipped now, `(?<![\w/.])(…)` | **3612** | 3618 | **6** |

The one-spelling defect went from 2 854 invisible spellings to 6 over the same corpus, and the 6 that remain
are all `/`-prefixed fragments — named here with the spelling the report writes (`measure.rows` carries the
byte context for each):

```
.agents/slop/JSFP8.md                                  .agents/TODO.md, written ../../.agents/slop/JSFP8.md
.agents/slop/xd2/serve.mjs                             examples/webgpu/mnist/README.md, written ./.agents/slop/xd2/serve.mjs
.agents/slop/twopass/corpus/matmul.txt                 .agents/slop/residue/000-the-residue.md, written .../twopass/corpus/matmul.txt
.agents/slop/proof-close/MUTANT/tinybendygrad/uop/ops.bend   .agents/slop/shadowtrees/REPORT.md, before='/'
checks/deeper/e2e.sh                                   .agents/slop/e2esh/FINDINGS.md, before='/'
checks/differ_wantdummy.py                             .agents/slop/remembered103/REPORT.md, written corpuswire/tree/checks/differ_wantdummy.py
```

So: **move the control, and record the resolution.** Two `MARKED-RESOLVED` lines under the control, or one
sentence in the census's REPORT, is what keeps the next reader from re-deriving this 20-minute question.

---

## 7. WHAT I COULD NOT DETERMINE, AND WHAT IS UNKNOWN

- **UNKNOWN — whether those 6 residual spellings are a defect of the shipped `REF`.** Three are relative
  spellings of a tracked path (`../../…`, `./…`, `corpuswire/tree/…`) and three are `/`-joined tails of a longer
  token (one of them the absolute `/2026-09-30-tinybendygrad/checks/deeper/e2e.sh`). Whether reading them is
  wrong depends on the subject — can the reader resolve `../../` from where they stand? — which the tree does
  not state, the same reason `census.py:251` gives ("The second spelling EXISTS; whether reading it is wrong
  depends on the subject, which the tree does not state"). Not charged, not cleared.
- **A REAL GAP, reported not fixed: the census is now structurally blind to this file.** `widened()`
  recognises only `(?:^|…)`, so a lookbehind-anchored regex is never a `regex-anchor-set` candidate and no
  future one-spelling defect in `checks/repro-paths.py:64` can ever be found by this instrument. Measured:
  `widened('(?<![\w/.])(…)') is None`, and the file yields 0 rows. Widening `widened()` to also recognise a
  leading `(?<!…)` is a **change to the instrument's kind definition**, not a control fix, and it needs its own
  brief.
- **The census has no vocabulary for "resolved".** It cannot distinguish "fixed" from "never looked at", and a
  site that stops being POSITIVE simply vanishes. That is the defect that produced this refusal; the minimal
  fix does not address it, and a retraction ledger would.
- **Not re-measured: the two controls that need the full AST walk** (`neg live table has companion` on
  `checks/sweep.py`, and the four `ast-spelling` population assertions). They pass in the post-fix run
  (`selfcheck : OK -- 6 controls`), so nothing is outstanding — but the *reason* they cannot have been moved by
  this fix is a reading, not a measurement: `literal_sites()` appends every module-level literal to `group`
  (`:357`) and `spellings` is updated from `group` (`:372`), so a lost `kind` cannot move `re.compile=386`.
- **The tree moved under me twice** while measuring: `.md` 551 → 568 across the two reports, and HEAD
  `444890672` → `3173198bd` at 00:47Z. Every number above carries `444890672` for the census run and was
  re-verified at `3173198bd` unchanged.

## 8. COST AND COMPLIANCE

`measure.py` 10 × (1.2 s / 65 MB peak), `census-proposed.py` 1 × (8.74 s / **342 MB peak**), writing only
into this directory. One process at a time, nothing backgrounded. No `.txt` created. No commit, no `jj`,
no `git add`; every git read was `ls-tree`/`cat-file`/`grep`/`show`/`log` with `env -u GIT_INDEX_FILE`.
Files written: `decision.md`, `measure.py`, `measure.rows`, `census-proposed.py`, `census-proposed.rows` —
all under `.agents/slop/onespelling-control/`.