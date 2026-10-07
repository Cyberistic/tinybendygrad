# `citeresolve` — the prose-citation population, resolved, with its moment

Unit `citeresolve`, 2026-10-07. **STATIC-ONLY: `bend` was NOT run.** Python only,
`.venv/bin/python`, no `.txt`, no commit, no `git add`, no `@`.
**Moment: `git rev-parse HEAD` = `e62eaf1e81d5814dc18499b5ff95f96482fd2a4b`.** The
four surfaces are read AS COMMITTED (`git show <HEAD>:<p>`), so the population is a
snapshot; the *targets* are the working tree, which other units held open all session
— `HEAD` moved `949cea833` → `2b4cc9e4` → `e62eaf1e` across three runs, and the live
`runs/`, `checks/substrate.py`, `TOOLS.md` numbers moved again under me (recorded below,
each with the reading that produced it).

Instrument: `.agents/slop/citeresolve/scan.py` (population + resolution),
`hist.py` (16,688 historical paths), `classify.py` (kinds), `counts.py` (the stale-count
re-derivation), `anchors.py` (cites2's 16 re-measured).

## 0. THE DELIVERABLE — the count nobody had written down

A claim is `<path>:<spec>` where `<spec>` is `N`, `N-M`, or a comma list, carried by a
backtick path ending in a known tree extension. Population by DISCOVERY: every file
`git ls-files` returns for `AGENTS.md`, `.agents/TOOLS.md`, `.agents/TODO.md`,
`.agents/slop/*/REPORT.md`.

| surface | claims | RESOLVE | OUT-OF-RANGE | GONE-FILE |
|---|---:|---:|---:|---:|
| `AGENTS.md` | 22 | **22** | 0 | 0 |
| `.agents/TOOLS.md` | 42 | 38 | 3 | 1 |
| `.agents/TODO.md` | 877 | 762 | 51 | 64 |
| `.agents/slop/*/REPORT.md` (116 tracked files) | 1 507 | 1 461 | 32 | 14 |
| **TOTAL** | **2 448** | **2 283** | **86** | **79** |

**2 283 resolve; 165 do not** (86 OUT-OF-RANGE + 79 GONE-FILE). Of the 2 283,
**352 resolve only WEAKLY** — the basename is shared and the cite carries no directory
path (`dtype.py` has the same basename in `tinygrad/`, `mixin/` and `codegen/decomp/`;
a bare basename is **not a population**, Doctrine 1 at the level of a filename).
1 931 resolve to a unique file.

**`OUT-OF-RANGE` and `GONE-FILE` are the only two states a bare number can be in that
FAIL.** A number inside the file can only be stale, never wrong (cites2 §5). So the
mechanical floor is **165 / 2 448 = 6.7 % non-resolving**, and that is a *floor*, not
the defect rate: 770 more resolve in-range with their subject found elsewhere in the
file (DRIFT *candidates*), and 349 resolve in-range with no subject token found at all.

## 1. The four claims I relayed — resolved against the tree

| relayed claim | verdict | evidence |
|---|---|---|
| `base.bend:70` holds an `Array` | **OUT-OF-RANGE (a/c)** | `tinybendygrad/base.bend` is **56 lines**; `:70-72` is past EOF. `.agents/slop/bendperf/REPORT.md:102`. `Array` is Bend's builtin. |
| `ops.bend:7837` → `:7844` (`+7`) | **NARRATIVE, and the `+7` is invented** | `tinybendygrad/uop/ops.bend` is 8 818 lines; `def vd_text` is at **8 416**, not 7 844. `git log --all -S vd_dbg` over `ops.bend` = 0. The cite is a record of what the port's own failure NAMED. `.agents/slop/awmma/REPORT.md:99`. |
| `.agents/slop/oracles259/plants.py` was deleted | **FALSE, CONFIRMED** | `git ls-files` lists it; it is on disk (9 989 B) and present in `git show HEAD:`. `00b101574`'s message *says* prefixtxt "Deleted the superseded oracles259/plants.py" but `git show --stat 00b101574` is **4 files**, none of them it. |
| `00b101574` landed five units' reports | **FALSE, CONFIRMED** | `git show --stat 00b101574` = `censusred/run.err`, `censusred/run.out`, `gates/tn_sin_log2_exp2_rsqrt.bend`, `tinybendygrad/tensor.bend` — **no report, no `graphcmp.bend`.** |

All four were prose claims whose measuring party was the relayer, not the tree. The
machinery existed (`chkcites`/`cites2` had already measured three of them) and nobody
ran it against the *briefs*. That is §6.

## 2. The failures by KIND

Positive confirmations are conservative; the `*CAND` rows are the line-level needle
heuristic and are **candidates, not proofs** (`AT-LINE` is the only positive check).

| kind | confirmed | candidate | definition / evidence |
|---|---:|---:|---|
| **(a) DRIFT** | **22** | 1 159 | subject present in target but not at the cited line (`OUT-OF-RANGE`+token elsewhere = 22; `RESOLVES` with subject elsewhere/absent = 770 + 349 + 40) |
| **(b) DEAD SUBJECT** | **73** | — | `GONE-FILE` whose basename IS in the 16 688 historical paths (`renderer_oracle.py`, `ops-501-oracle.py`, `rebase-oracle-ops.py`, `decomp.bend`, …) — it existed and is gone |
| **(c) NEVER EXISTED** | **6** | — | `GONE-FILE`, basename in **no** commit: `jstage.py:308`, `p13-ops.py:168/79,106/66,51` (the real name is `graphcmp-p13-ops.py`), `debug-gate-out.0.py:73` ×2 |
| **(d) STALE COUNT** | **see §4** | — | a number that duplicates a generator's output; not a `<path>:<N>` claim |
| **(e) NARRATIVE** | **35** | — | a cue in the SOURCE line (`used to`, `historical`, `no longer`, `(was `, `pre-deletion`, `at the parent`, …) — **must NOT be renumbered**; `nl-gate.py:39,40,477` and `run-port-mm.sh:87` are the canonical four |

`(e)` is not a defect. `cites2` already found 4; this pass finds **35 by cue**, of which
the cstyle-deletion cites, the `ops.bend:7837/7874` pair, and the `helpers.bend:2551`
past-edit are the load-bearing ones.

`(b)` and `(c)` are **reported, not touched**: a dead subject's claim is deleted with its
reason recorded where it was (cites2 landed exactly that shape for the four `cstyle`
cites), and an invented cite is deleted as invented.

## 3. Fixes — (a) DRIFT only, and why almost none are safe

**One landed, line-count-neutral, in `.agents/TOOLS.md:12-13`** (mine): the live ledger's
own population reading was stale `160 present / 173 absent / 96 under slop` →
**`164 present / 169 absent / 85 under slop`**, re-derived by `counts.py` at HEAD
`e62eaf1e`. The date moved `2026-10-06` → `2026-10-07`. **Net lines changed: 0**, so no
downstream `TOOLS.md:<N>` cite shifted.

**Why no DRIFT *renumbering* landed anywhere else.** Every non-resolving cite in my owned
surfaces falls into one of four shapes, and NONE is a safe number edit:

* `TOOLS.md:747` `ops.py:501-1928` — a **unit label** ("the `ops.py:501-1928` unit's
  three-lane gate"), not a pointer. `ops.py` is 1 920 lines now; renumbering the label
  renames a unit.
* `TOOLS.md:1468` `substrate-check.sh:200` — a **narrative** ("this sweep exists because
  `substrate-check.sh:200` ran bend under `perl -e …`"); the file is a **46-line shim**
  now, and the sentence records a past property.
* `TOOLS.md:951` `.agents/slop/mm-mutate.py:17` — a **dead subject** (the file is
  deleted); the claim ("line 471 must stay") is what matters.
* `AGENTS.md:22` `TOOLS.md:51-52` and `AGENTS.md:145` `TOOLS.md:645` — **DRIFT, but
  `AGENTS.md` is out of my write scope.** The "off limits / ledger instead" sentence is
  at `TOOLS.md:65-66`; `xd1/pin` is at `TOOLS.md:651`. Reported for the `AGENTS.md` owner.

**A DRIFT fix is itself a drift source.** My first attempt to append the re-derived
`TOOLS.md` reading inserted 6 lines before line 51 and moved *two* `AGENTS.md` cites by
`+6` — the fix manufactured the defect it was fixing. It was reverted; the landed edit is
line-count-neutral. This is the cost of a positional citation, measured twice in one pass.

## 4. STALE COUNTS — THE PRIORITY. Every one, with its re-derivation

`AGENTS.md` says a literal count that duplicates a generator's output rots. Here is the
rot, re-derived at HEAD `e62eaf1e` by `.agents/slop/citeresolve/counts.py`:

| claim | stated | **current** | ONE-LINE COMMAND |
|---|---|---:|---|
| `no-txt.py` HARD | `550` (`AGENTS.md:39`) | **0** | `.venv/bin/python checks/no-txt.py` (rc=0, `CLEAN`) |
| `no-txt.py` EXCUSED | `139` (`AGENTS.md:39`) | **179** | `.venv/bin/python checks/no-txt.py` |
| `len(differ.declared())` | `139` (`AGENTS.md:98,100`) | **175** | `.venv/bin/python -c "import importlib.util as u;s=u.spec_from_file_location('d','checks/differ.py');m=u.module_from_spec(s);s.loader.exec_module(m);print(len(m.declared()))"` |
| `TOOLS.md` present | `153` (`AGENTS.md:140`) / `160` (`TOOLS.md:12`) | **164** | `.venv/bin/python .agents/slop/citeresolve/counts.py` |
| `TOOLS.md` gone | `180` / `173` | **169** | same |
| gone under `.agents/slop/` | `96` | **85** | same |
| gone instruments | `16` kind / `14` content (`AGENTS.md:178`) | **6** | same |
| `gates/*.py` | `21` (`AGENTS.md:131`) | **54** | `ls gates/*.py \| wc -l` |
| `checks/substrate.py` lines | `766`/`841` (`AGENTS.md:129`) | **936** | `wc -l checks/substrate.py` |
| `*-mutate.py` survivors | `9 + 7` (`AGENTS.md:33`) | **14** | `find .agents/slop -name '*-mutate.py' \| wc -l` |
| peakrss census denominator | `138` (`AGENTS.md:71`; `census.rows` header) | **134** | `find tinybendygrad -name '*.bend' \| wc -l` |
| `D0` `oracle-selfcheck` | `OK` (`AGENTS.md:104`) | **OK now — FAIL 30 min ago** | `grep oracle-selfcheck= runs/graphcmp/D/D0-run-summary.txt` |
| `REPORT.md` count | (unstated) | **116 tracked / 120 on disk** | `git ls-files '.agents/slop/*/REPORT.md' \| wc -l` |

**Two that are NOT stale** and are worth naming because the brief's own audit said they
moved: **`134` `.bend` is still 134** (`AGENTS.md`'s appended reading holds), and
**`333` TOOLS.md paths is still 333**. `checks/*.sh` = 17 and `checks/substrate-check.sh`
= 46 lines also still hold.

**THE `41%` IS NOT IN THE TREE.** Confirmed independently: no owned surface carries it
(`citetruth` found the same). The volume ratio `40.2%`/`39.4%` lives only in
`.agents/slop/portpop/REPORT.md` and `.agents/slop/portzz/REPORT.md`.

**THE ONE THAT BITES HARDEST: `D0-run-summary.txt` is a LIVE artifact.** It read
`oracle-selfcheck=# ORACLE SELFCHECK: FAIL` at 05:33 and `OK` at 05:37 on the same
command, because another unit re-ran `differ.py`. `AGENTS.md:104` asserts `OK` *as a
fact about the tree*. **A claim about a generated file must carry the file's mtime, not
just the claim's date** — otherwise it is a claim about whatever the last runner wrote.

`SPEC=1 70/70` and `SPEC=2 26/77` (`AGENTS.md` flag table) **were not re-derived** —
they need `bend`, which this session may not run. They stay as their 25/34-graph readings.

## 5. `(b)`, `(c)`, `(e)` reported; the 16 cites2 left alone

`cites2` left **16 distinct live anchors** alone and was right to. This pass closes them
by re-measurement — `anchors.py`, at HEAD `e62eaf1e`:

**15 of 16 are IMMUNE** (the anchor occurs on exactly ONE line, so the number is
redundant and can be dropped): `def Dt.i64_trunc`@1064, `ATuple{ys: List<&2, U32>}`@1208,
`def UOp.mselect`@4586, `#   dtype: DType = dtypes.void`@1060, `0x7FC00000`@42,
`String.concat([nm, " = ["`@125, `import Base` (`nv/ip.bend`)@371, `import Base`
(`LAWS/spec.bend`)@48, `def emit(xs: List<&2, String>)`@1770, `def py_row(`@2020,
`def rnd_row(`@2558, `def pu_line(`@2752, `` `Ops.SHRINK` HAS NO DTYPE ``@49, `def ew_add`@542,
`bend2-constraints.md`@32.

**1 of 16 is NEEDS-NUMBER**: `getenv_int("DEBUG", 0)` now occurs **twice** in
`helpers.bend` (306 a comment, 308 the code) — the number, or a longer anchor, must stay.
This is the 1 of cites2's 5 that survived; the other 4 were the `render.bend` five-wraps
range, already collapsed to five anchors.

**A defect one level up, found here:** two of cites2's *paste-ready* anchors could not
match their own file **as pasted** — `'String.concat([nm, " = ["]'` carries an extra `"]`
(the file has `" = ["` then `,`), and `` Ops.SHRINK.*HAS NO DTYPE `` was written as a
REGEX in a code block consumed as a literal. **An anchor that cannot match is a citation
whose measuring party was again the author.** Both were corrected to match before the 16
were re-measured.

## 6. THE COUNT THAT MATTERS MOST: how many claims were never checked

**2 448 claims; 671 carry a subject token confirmed AT the cited line. 1 777 were never
positively checked** — 2 448 − 671. In the four governing surfaces that is the *entire
history of this project's prose*: `AGENTS.md`'s 22, `TOOLS.md`'s 42, `TODO.md`'s 877, and
**essentially every `REPORT.md` written tonight** (1 507 claims across 116 files). They
were resolved mechanically for the first time *by this pass*. The briefs that relayed the
four false claims (§1) did so because **no instrument bounded the prose to the tree**;
each relayer checked by reading, and the reading was the error.

### One instrument, tree-wide

**`checks/disagree-gate.py`'s `(path, must_contain, why)` shape should become the house
form for every citation a document owns.**

* **What it buys.** `lane_citations` reads the cited line and `must_contain` requires the
  needle AND no identifier char after it. A moved line **FAILS LOUDLY** instead of
  pointing at the wrong thing. `cites2` measured **22 of 31** surviving cites IMMUNE
  under it; this pass re-measures **15 of 16 anchors** still IMMUNE a day later. The
  number becomes redundant exactly when the anchor is unique — and when it is not,
  the instrument says so.
* **The cost, stated plainly.** An anchor is a *second* claim, and it rots too: of the
  16, one anchor now repeats (`helpers.bend`), and two of cites2's pasted anchors never
  matched. So the shape is not free — **the anchor must be verified unique at author
  time and re-verified when the file moves**, and where it repeats the number must stay.
  The honest form is `(path, must_contain, N?)` with `N` optional.
* **Minimum viable landing.** A single `checks/cites.py` that (1) discovers every
  `<path>:<N>` in the four surfaces with the regex in `scan.py` (already written),
  (2) resolves it by the tree walk here, and (3) for each row with an anchor, asserts the
  anchor at the line. Exit `REFUSED` (3) when no anchor is parseable, `SKIP` (4) when the
  target is live, `FAIL` (1) on a moved anchor, `DEAD` (5) on a gone file — **the five
  verdicts `gates/gatekit.py:59` already spells.** The population is a generator's own
  declaration (`git ls-files` of the four surfaces), never a hand list.

The four false claims of §1 are all of the form *a number carried in prose with no rule
attached*. The `(path, must_contain)` shape is the rule. It should be the house form; the
price is that the anchor is checked too.

## 7. Artifacts (all under `.agents/slop/citeresolve/`)

* `scan.py` / `scan.tsv` — the discovery walk and the 2 448-row reading.
* `hist.py` / `hist.tsv` — 16 688 historical paths (the `(b)`/`(c)` discriminator).
* `classify.py` / `classified.tsv` — the kind assignment.
* `counts.py` / `counts.rows` — every literal count, its rule, its value.
* `anchors.py` / `anchors.tsv` — cites2's 16 anchors re-measured (15 IMMUNE, 1 NEEDS).
* `counts.err`, `classify.err`, `anchors.err` — the count lines with their HEAD.
