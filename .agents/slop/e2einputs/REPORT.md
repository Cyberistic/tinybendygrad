# Two claims in `AGENTS.md:145-152`, measured — one CONFIRMED, one REFUTED, one CONFIRMED-BY-A-NEARER-AUDIT

Read-only census. **No gate was executed** (`checks/e2e.py`, `checks/e2e.sh`, `checks/differ.py`,
`gates/*`, `run-port-mm.sh`, `run-f64.sh` all untouched, per instruction). Every number below is
`stat`/`git`/`grep` output.

* **HEAD** `0273fe4286e2446c28865eaa155ec09e3052a41f` (read at `16:24:48Z` and re-read at `16:27:35Z`
  — **unchanged**).
* **Run window** `2026-10-19T16:24:48Z` → `16:27:35Z` UTC. Machine `vm.loadavg` **5.41** at start.
* **Timezone trap, recorded because it bit this report first:** the host is `Asia/Kuwait` (**UTC+3**,
  `/etc/localtime` symlink). BSD `stat -f %Sm` formats in **local** time, so my first read printed
  `2026-10-07T23:25:58Z` for an instant that is really **`2026-10-07T20:25:58Z`** — a 3-hour error
  manufactured by a `Z` suffix typed into a format string. All rows in `findings.rows` use
  `TZ=UTC stat` and `date -u -r <epoch>`.

## VERDICT TABLE

| # | `AGENTS.md` claim | Verdict |
|---|---|---|
| 1 | transcript exists, mtime `Oct 7 23:25`, **11.7 days** old, **TRACKED not gitignored** | **CONFIRMED** (mtime string is local time; age now **11.83 d**) |
| 2 | `ops_bend-milestone-expected.txt` does not exist; renamed to `.md`; loader resolves **by stem**, no `.txt`-then-`.md` fallback | **CONFIRMED** |
| 3 | `runtime/dtype.js` **IS ABSENT ENTIRELY**; `cdp.mjs`'s counterpart **ALSO ABSENT** | **REFUTED — `runtime/dtype.js` IS PRESENT** |

---

## 1. The transcript — CONFIRMED, and it is worse than "stale"

`.agents/slop/e2epy/artifacts/live.port.out`

```
disk      PRESENT, 13306 bytes
mtime     2026-10-07T20:25:58Z   (epoch 1791404758, stable across both readings)
in HEAD   YES, blob f7363cfc591bc5fc68932d45a41723bd07b36da7
worktree  git hash-object == f7363cfc... == the HEAD blob, byte for byte
ignored   NO.  git check-ignore -v <path> -> rc=1; no .gitignore rule names e2epy
tracked   347 paths under .agents/slop/e2epy/ are in `git ls-files`
age       284.03 h = 11.8345 d  (reading #2)
```

**It is TRACKED — say it plainly.** `gates/`-adjacent `.gitignore` audit confirms AGENTS.md's own
pointer: `.gitignore:262` is exactly `/runs/`, and the only `.agents/slop/*` rules are 30ish
*specific subdirectories* (`opstree/`, `xd1/`, `elf/`, `probe/`, …). `.agents/slop/e2epy/` is not
among them, so every `live.*` and `plant-*` transcript is **committed**.

**Why that is the sharp point, precisely:** the working tree hashes to the HEAD blob exactly. So
`git status` reports it **clean**, `git diff` reports **nothing**, and the file is as committed now as
it was when it was written. A tracked, unmodified, 11.8-day-old transcript is **invisible to every
tool that asks git** — which is why the mtime, and only the mtime, is the evidence.

**Correction to the quoted string.** AGENTS.md (via `.agents/slop/e2ereport/REPORT.md:157`) gives
the mtime as `2026-10-07T23:25:58Z`. That is the **local** rendering, wearing a `Z`. The epoch is
unambiguous and the UTC instant is `20:25:58Z`. The **duration** is unaffected (11.83 d either way);
the **timestamp string** is 3 h wrong. Same trap `gates/gapcensus.py:479-482` documents for itself
("`cI` CARRIES AN OFFSET and `fromtimestamp` is NAIVE").

## 2. `ops_bend-milestone-expected` — CONFIRMED on all three sub-claims

* **The `.txt` does not exist** — on disk (`find` for the name, any directory, returns nothing) **and
  in HEAD** (`git cat-file -e` → rc≠0).
* **The real file is `.agents/slop/ops_bend-milestone-expected.md`**, 4626 bytes, **PRESENT on disk
  and in HEAD**. Exactly **one** file beside the gate carries that stem.
* **The loader resolves BY STEM.** `.agents/slop/opsbend_milestone_gate.py:46-52`:

```python
here = pathlib.Path(__file__).resolve().parent
hits = sorted(p.name for p in here.iterdir()
              if p.is_file() and p.stem == _EXPECTED_STEM)
if len(hits) != 1:
    raise SystemExit(f"{_EXPECTED_STEM}: expected exactly one file beside this gate, "
                     f"found {hits}")
```

  `_EXPECTED_STEM = "ops_bend-milestone-expected"` (`:36`). Resolution is `iterdir()` + `p.stem ==`,
  and **0 or 2 hits is a hard `SystemExit`, not a choice**. That is a *resolver*, not a fallback.
* **No `.txt`-then-`.md` fallback exists** — and the file says so itself at `:28-29`:
  *"**NOT BY EXTENSION, AND NOT BY A `.txt`-THEN-`.md` FALLBACK: TWO LITERALS IS A HAND LIST, WHICH
  IS NOT A POPULATION**"*. AGENTS.md is citing a real line in the tree, and the line is honest.

**Residual, named:** `checks/e2e.sh:147` and `:168` still cite the dead
`ops_bend-milestone-expected.txt` **in prose comments**. The *loader* is by stem (correct); these two
*citations* still name the old path. A reader grepping `e2e.sh` finds a `.txt` that cannot exist.

## 3. `runtime/dtype.js` — **REFUTED**

AGENTS.md:149, sourced verbatim from `.agents/slop/e2ereport/REPORT.md:154` ("| `runtime/dtype.js`
is **ABSENT entirely** | **DELETE** the file-name clause"), says the file is gone. It is not gone.

```
tinybendygrad/runtime/dtype.js   PRESENT  8884 B  mtime 2026-10-05T17:59:52Z (334.46 h old)
                                HEAD_YES, tracked, stage-0 index entry, blob 233a053a...
tinybendygrad/runtime/dtype.c    PRESENT 14348 B  mtime 2026-10-05T16:05:27Z (336.37 h old)
                                HEAD_YES, tracked
```

**Ruled out as a jj artifact:** the armed-index failure mode named in `AGENTS.md` leaves the empty
blob `e69de29b`. This file hashes to `233a053a308b769e5273c256969468a0698975f7` and opens with real
prose (*"// dtype.js -- the interpreted-lane half of the runtime/dtype.c seam."*). It is content.

**What actually happened — the confusion is worth naming.** `checks/e2e.py:67-80` retires **stage 8**
(`RETIRED, AND NOT RE-POINTED: ITS DENOMINATOR IS 0`) because `dtype.bend` declares 0 `IO(` laws, so
*zero rows reach* the JS lane. **The STAGE was retired. The FILE was not deleted.** "`dtype.js` is not
one byte of the emitted bundle" is a statement about the *bundle*, and the prior audit promoted it to
"the file is ABSENT entirely". The correct reading is the opposite of the one AGENTS.md now prints:
**the file is still sitting there, waiting to be re-pointed** — which is what `checks/e2e.py:77-78`
says in so many words (*"Re-point it only if a `Dt.*` law becomes a seam again"*).

Note also that only `tinybendygrad/runtime/dtype.js` exists; the **repo-root-relative**
`runtime/dtype.js` named in `checks/e2e.py:68` does not. That may be the sliver of truth the prior
audit half-saw.

### `cdp.mjs`'s counterpart — the "both absent" half is **REFUTED too**

Every fixture of that set is present, on disk and in HEAD:

```
.agents/slop/xd2/cdp.mjs          6150 B  HEAD_YES
.agents/slop/xd2/serve.mjs        2185 B  HEAD_YES
.agents/slop/xd2/sh.mjs           1054 B  HEAD_YES
.agents/slop/fixures/xd2/cdp.mjs  6150 B  HEAD_YES
```

`e2ereport/REPORT.md:156` ruled "`cdp.mjs` PRESENT, the other **ABSENT**". If "the other" is
`serve.mjs` (the pairing `.agents/TOOLS.md:726` states: *"Imports the port's own `xd2/cdp.mjs` and
`xd2/serve.mjs`"*) then that is **REFUTED**: `serve.mjs` is present and tracked. `.agents/TODO.md:13941`
independently records all four (`cdp.mjs`, `serve.mjs`, `sh.mjs`, `ops_bend-milestone-expected.txt`)
returning to disk. **Only the `.txt`→`.md` rename is real.**

**Net:** the "BOTH EXIST" correction was worth making, but its current replacement over-corrects in
one place (dtype.js) and under-corrects in another (cdp.mjs's neighbours).

---

## 4. THE GENERAL FORM — **PARTIALLY REFUTED, and the true part is sharper**

AGENTS.md:153 asserts: *"**NO INSTRUMENT IN THE TREE NOTICES THAT A COMPARISON ARTIFACT IS OLDER THAN
THE CODE IT COMPARES.**"* Measured, that is **false as stated**. Two instruments exist, and neither
covers the transcript.

### 4a. The relative check EXISTS — `gates/gapcensus.py:469-495`

```python
d = ROOT / "runs" / "graphcmp" / "D"
newest = max((p.stat().st_mtime for p in d.rglob("*") if p.is_file()), default=0)
when   = datetime.fromisoformat(rev.split()[1]).astimezone()   # last commit touching `tinygrad`
gap    = (when - datetime.fromtimestamp(newest)) if when and newest else None
rows = { ..., "corpus.artefacts_OLDER_by": str(gap), "corpus.artefacts_NEWER_than_the_revendor": len(freshers) }
```

This computes **precisely** "how much older the artifacts are than the code", and `:474-478` records
having already been burned by it (*"a corpus that is 5h24m STALE read as FRESH. A date is not a
timestamp"*). **But it REPORTS a row; it does not REFUSE.** No `sys.exit`/non-zero path is wired to
`artefacts_OLDER_by`, and it is scoped to `runs/graphcmp/D` alone.

### 4b. The absolute check EXISTS and DOES refuse — `checks/runs-artifacts.py:550-566`

```python
newest = max(os.path.getmtime(f) for f in files); age = now - newest
if max_age_s is not None and age > max_age_s:
    return REFUSED, "ARTIFACTS-STALE", ...
```

`MAX_AGE_S = 24*3600` (`:91`), `GRAPH_D = "runs/graphcmp/D"` (`:81`). It is **wired**:
`gates/retention-check.py:669` calls `ra.require(prefix, ...)` *before any work*, and its comment at
`:655-660` records the lesson (*"A GUARD PLACED AFTER THE WORK IT GUARDS IS A COMMENT"*). But it
compares the artifact to **the clock**, never to **the code**.

### 4c. The census — gates that read an artifact/transcript, each NAMED

| instrument | artifact read | vs the clock | vs its source code | verdict |
|---|---|---|---|---|
| `gates/retention-check.py:669` → `runs-artifacts.py` | `runs/graphcmp/D` | **REFUSES at 24 h** | no | age-gated |
| `gates/gapcensus.py:485` | `runs/graphcmp/D` | no | **computes + reports** | reports only |
| `gates/corpuswitness-gate.py:148-158` | run vs repro summaries | `st_mtime_ns`, `>=` | no — **artifact vs artifact** | ordering only |
| **`gates/e2estage8-stage-legacy.py:29`** | **`.agents/slop/e2epy/artifacts/live.port.out`** | **NONE** | **NONE** | **unguarded** |
| **`.agents/slop/e2estage8/verdicts.py:62`** | **the same transcript** | **NONE** | **NONE** | **unguarded** |

**The two unguarded readers are the finding.** `gates/e2estage8-stage-legacy.py:29` is literally:

```python
DEFAULT = ROOT / ".agents/slop/e2epy/artifacts/live.port.out"
```

and `main()` at `:129` does `src = Path(args[0]) if args else DEFAULT` — so **running it with no
arguments reads the stale transcript**, and its `grep -c 'st_mtime\|getmtime'` is **0**.

This is the sharpest possible instance of the defect, because **this gate's entire purpose is the
cross-check AGENTS.md wants** — its docstring names *"THE THREE READERS OF A STAGE LIST"* (`:32-35`):
PROSE vs CODE vs TRANSCRIPT *"must agree"*, and it fails when *"the gate and its own artifact
disagree"* (`:119-121`). It cross-checks a gate's **docstring** against the gate's **code** against a
**run's transcript**, and it never asks whether that transcript is current. A week of edits to
`checks/e2e.py` is invisible to it.

**Bonus defect, measured:** those two readers are **not the same file**. `.agents/slop/e2estage8/verdicts.py`
hashes `fcb8f70a20afe07b4f3771a6e77f2681c8bca0c0`; `gates/e2estage8-stage-legacy.py` hashes
`eb67bf0554facd1f30c2390d24e127304d0943c2`. Two divergent instruments, both defaulting to the same
stale transcript, both with no age check.

### 4d. The gap, measured live, during this run

```
checks/e2e.py     mtime 2026-10-19T16:27:12Z   age 0.01 h   (modified 23 s before the sweep)
checks/e2e.sh     mtime 2026-10-19T16:27:17Z   age 0.01 h
live.port.out     mtime 2026-10-07T20:25:58Z   age 284.03 h
                                        gap ≈ 284 h ≈ 11.8 days
```

`checks/e2e.py` was being edited **by another unit while this census ran** — the moving-target warning
is live, not rhetorical. The transcript cannot describe that code. The instrument that would notice is
`e2estage8-stage-legacy.py`, which has no age check.

## 5. CONTROL — PASSED

Two independent readings, separated by wall clock, of the same quantities:

| | reading #1 | reading #2 |
|---|---|---|
| `date -u` | `16:25:00Z` | `16:27:35Z` |
| epoch now | 1792427100 | 1792427255 |
| artifact epoch | **1791404758** | **1791404758** |
| age seconds | 1022342 | 1022497 |
| age hours | 283.984 | 284.027 |
| age days | 11.8326 | 11.8345 |
| HEAD | `0273fe42…` | `0273fe42…` |
| artifact hash | `f7363cfc…` | `f7363cfc…` |

The artifact mtime is **invariant**; the only moving term is `now`, and age grew **155 s**, exactly the
155 s between the two readings. HEAD and the blob are byte-stable. The arithmetic is a fixed point, not
a one-shot.

## 6. WHAT I DID NOT MEASURE (REFUSED, not guessed)

* I did **not** execute any gate, so I report **no runtime verdicts** — every claim above is about
  files, not behaviour.
* I did **not** determine which file `.agents/slop/e2ereport/REPORT.md:156` meant by "the other".
  I report `serve.mjs`/`sh.mjs` as present and leave the referent unresolved.
* `checks/e2e.py` moved under me mid-run (0.01 h old). My line citations into it (`:67-80`, `:28-29`
  of the milestone gate) are valid as of `0273fe42` and may have shifted by the time this is read.
* `.agents/TODO.md` cites `gates/` as "56 `.py`"; `ls gates/*.py | wc -l` reads **239** today. Not
  my subject, recorded because it means every "56 of them" denominator in the ledger is stale.

## FILES

* `.agents/slop/e2einputs/findings.rows` — TAB: `item, exists_disk, exists_HEAD, mtime_utc, age_hours, gitignored`
* `.agents/slop/e2einputs/REPORT.md` — this file

No `.txt` was written. No existing file was modified. No git-mutating command was run.
