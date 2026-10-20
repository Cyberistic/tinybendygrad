# THE `--selftest` LANE'S CAPTURED PAIR — RESOLVED

**HEAD at writing: `9574a3e2aa2508e400dc9931d01399ee9ba30226`** (`git rev-parse HEAD`,
2026-10-20T20:52Z). **HEAD MOVED DURING THIS INVESTIGATION**: the first reading, at
`2026-10-20T20:41:53Z`, was `d9dcd0fe2ffb6559beb13e67f083021fa0a6748c`. Every fact below was
re-verified at the second HEAD.

**Timestamp of the measurements: 2026-10-20T20:41Z – 2026-10-20T20:53Z.**
**Load average at the start: `{ 4.40 6.68 6.31 }` (under the 12 threshold).**

**VERDICT: (a) — THE PAIR IS NOT LOST. BOTH CAPTURES ARE IN THE TREE, TRACKED, AND
BYTE-VERIFIED AGAINST THE md5s `checks/rn-gate.py` ITSELF RECORDS. The gate's OWN `selftest()`
returns 0 over them. The lane is not PERMANENTLY REFUSED; it is REFUSED for a reason that is
FIXABLE, and the fix is not a one-line path change to the candidate — it is two new files plus a
rename of the gate's two input names (because `.txt` is illegal in this tree).**

THE PRIOR UNIT'S DECLINE WAS CORRECT ON THE EVIDENCE IT HAD AND WRONG ON THE CONCLUSION: it
measured "22 of 80 rows carry the exact three-space SEP" and read that as a mismatch. The 22 is
real, and it means something else entirely (§2).

---

## 1. THE REQUIREMENTS, IN ONE PLACE

Full detail, with the gate quoted, is in `requirements.md` beside this file. The short form:

- `checks/rn-gate.py:400-407` reads **two raw-text files, at fixed names**:
  `checks/rn-port.txt` (the PORT lane) and `checks/rn-orc.txt` (the ORACLE lane).
  **Neither exists: absent from disk, absent from HEAD, 0 commits in the whole history touch
  either.**
- The reader (`logical_rows` `:128-153`, `row_strict` `:156-197`) folds a capture into LOGICAL
  rows by bracket depth, then cuts each row at a depth-0 `=` whose remainder opens a bracket:
  `ROW_OPEN = " = ["` (the port's spaced spelling) first, then `"=["` (the oracle's glued
  spelling). **Exactly one candidate → a row; more → REFUSED; none → REFUSED.**
- `SEP = "]   py=["` (`:98`) is the gate's fast path for splitting a row's value from its `py=`
  column. **IT IS NOT A REQUIREMENT**: when it is absent the reader falls back to the whole text
  and still finds the boundary.
- The selftest's four lanes (`:417-424`) demand, of the PORT capture, two rows by name:
  **`pyrender const`** and **`pyrender cast`**, each spelled `name` + SPACES + `=`
  (`plant_shape`'s regex is `^` + re.escape(old) + `" +(?==)"`, `:307`). They demand, of the
  ORACLE capture, that it **share the port's row NAMES** — the `value` plant only moves
  `disagree` if `pyrender const` is on BOTH sides.

## 2. THE CANDIDATE — DOES IT SATISFY THE REQUIREMENTS? **YES.** AND THE 22 IS EXPLAINED

`oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows`:

- **md5 `642f9770c558df0f1be03a8f67ac997e`** — **exactly** the oracle stdout md5
  `checks/rn-gate.py:45` records. 124 physical lines. 80 logical rows. **0 refusals** from the
  gate's own `rows_strict`. 85 distinct keys of `rows()`, 124 lines `row()` accepts, 39 rows no
  name can address, 44 continuation lines — **all equal to `.agents/slop/eq/REPORT.md:27`.**

**THE 22, AND THE OTHER 58. THE 22 IS THE COUNT OF SEP-BEARING ROWS THAT ARE SINGLE-PHYSICAL-LINE.
THE 58 IS NOT A COUNT OF MALFORMED ROWS.**

| the oracle's 80 rows | n | what the `py=` column looks like | who spells it |
|---|---|---|---|
| `pyrender *` / `pyr_*` | **37** | `]   py=[` — the gate's exact three-space SEP | `emit_gate`, `_PY_ROW` class |
| &nbsp;&nbsp;of those, SINGLE physical line | **22** | the SEP is the row's only line | — |
| &nbsp;&nbsp;of those, MULTI physical line | **15** | the SEP is on the row's **FIRST** physical line; the VALUE continues below it | — |
| default | 32 | `]   py=` — three spaces, BARE | `emit_gate`, the `else` branch |
| `_IO1` (3 `sint_show`) | 3 | `] py=` — **one** space | `emit_gate` |
| `_IO5` (3 `f32_repr`) | 3 | `]     py=` — **five** spaces | `emit_gate` |
| `_SPLIT` (5 `arg_repr`) | 5 | **NO `py=` COLUMN AT ALL** | `emit_gate` |

22 + 15 + 32 + 3 + 3 + 5 = **80**. So the prior unit's "22 of 80" is the SEP-bearing rows whose
SEP is on the row's only physical line; the other 15 SEP-bearing rows put it on the row's FIRST
line, because a `pyrender` answer legitimately contains newlines (`render.bend:2048-2049`).

**AND THE 43 ROWS WITH NO SEP ARE NOT A DEFECT AND NOT A DIFFERENT ARTIFACT — THEY ARE THE
ORACLE'S OWN PRINTER SPELLING `py=` FOUR OTHER WAYS, BY NAME CLASS.** `checks/render-gate-oracle.py:251-281`:

```
251: _PY_ROW = ("pyrender ", "pyr_")
252: _IO1 = {"sint_show 2**31-1", "sint_show -3", "sint_show -2**31"}
253: _IO5 = {"f32_repr 3.0", "f32_repr 1e30", "f32_repr 0.1"}
254: _SPLIT = {"arg_repr AKern", "arg_repr AProgr", "arg_repr AParam1", "arg_repr AParam2", "arg_repr AParam3"}
...
278:     elif name.startswith(_PY_ROW):
279:         print(f"{name}=[{ans}]   py=[{ans}]")
280:     else:
281:         print(f"{name}=[{ans}]   py={ans}")
```

**THE DECISIVE MEASUREMENT: the gate's reader reads ALL 80 ROWS OF THE CANDIDATE WITH 0 REFUSALS.**
The SEP is a fast path, not a contract. The candidate is the oracle capture the gate was written
against, and it satisfies the requirements in full.

## 3. THE PORT SIDE — THERE WAS A CANDIDATE, AND IT IS NOT NAMED LIKE ONE

**THE PORT CAPTURE IS `.agents/slop/flipthird/base-render.err`, LINES 22..161.** (Tracked; added in
`91645e23d`, 2026-10-07.)

That file is a **concatenation**: 21 lines of bend's `pu_*` uop dump, then the 140 stdout row
lines, then the watchdog's own verdict line and bend's "update available" notice. The 140 row
lines are the capture.

| quantity | the slice | the gate's own record |
|---|---|---|
| md5 | `302944bb48a32379f3a13d857893ec69` | port stdout md5 `302944bb48a32379` (`rn-gate.py:44`) — **first 16 hex chars, exact** |
| physical lines | **140** | "140 lines against 124" (`rn-gate.py:45`) |
| distinct keys of `rows()` | **97** | 97 (`eq/REPORT.md:26`) |
| lines `row()` accepts | **140** | 140 (`eq/REPORT.md:26`) |
| rows no name can address | **43** | 43 (`eq/REPORT.md:26`) |
| continuation lines | **49** | 49 (`eq/REPORT.md` §1) |
| names containing `=` | 0 | 0 (`eq/REPORT.md:26`) |
| refusals from the gate's reader | **0** | — |

**`.agents/slop/flipthird/e2-base-tinybendygrad_uop_render.err` lines 22..161 IS A BYTE-IDENTICAL
SECOND COPY** (diff empty; same md5) — the same run, captured by the e2 harness.

**THE WHOLE `.err` FILE DOES NOT WORK** (measured: 2 names, 8 refusals, 0 gated rows). The slice
is the capture.

**THE PAIR, over the gate's own `judge()`:**

```
gated=80   agree=75   disagree=5
disagree: arg_repr AKern, arg_repr AParam1, arg_repr AParam2, arg_repr AParam3, arg_repr AProgr
stray (oracle-only): 0
ghost  (port-only) : the 11 rnd_* names
```

The 5 disagreements are **exactly** the five the gate's docstring names — "this lane's real pair
already disagrees on 5 rows (the hand-written `py=` wraps)" (`rn-gate.py:375-377`) — because the
port puts the `py=` column on its own line for those five and the oracle's `_SPLIT` class does
not print one. The 11 ghosts are **exactly** the 11 the docstring names — "The port has 11 rows
the oracle does not answer -- all `rnd_*`" (`rn-gate.py:47`).

**THE GATE'S OWN `selftest()`, RUN VERBATIM** (imported by path, with the gate's own `HERE` moved
to this directory so it reads the two captures from here — no lane re-implemented):

```
[selftest base] the REAL captured pair: 80 gated rows, 75 agree, 5 disagree
                 ['arg_repr AKern', 'arg_repr AParam1', 'arg_repr AParam2', 'arg_repr AParam3', 'arg_repr AProgr']
  base     BROKEN  cont=49 eq=0 unaddressable=43 disagree=5   ok
  value    BROKEN  cont=49 eq=0 unaddressable=43 disagree=6   ok
  shape    BROKEN  cont=49 eq=1 unaddressable=43 disagree=0   ok
  collide  BROKEN  cont=49 eq=0 unaddressable=44 disagree=0   ok
SELFTEST OK -- a planted VALUE raises `disagree` by one; a planted NAME leaves `disagree` at the
base count and moves the name sets, so the two are distinguishable
selftest() returned 0   (PASS)
```

**THE LANE'S SELFTEST PASSES OVER THIS PAIR. THE REFUSAL IS ABOUT A MISSING FILENAME, NOT A MISSING
CAPTURE.**

**OTHER CANDIDATES, AND WHY EACH FAILS** (full table in `candidates.rows`):
- `checks/rn-port.txt` / `checks/rn-orc.txt` — absent from disk, absent from HEAD, 0 commits touch
  either. **THE NAMES DO NOT EXIST. THE CONTENTS DO.**
- `.agents/slop/gatesrun/checks_render-gate-oracle.py.out` — the oracle's RAW (non-`--gate`)
  output, 102 lines of `name=answer` with no brackets and 0 SEPs. **A DIFFERENT ARTIFACT**, not a
  formatting variant: the reader would cut at the `=` inside the value.
- `oracles/baseline.json`, lane `tinybendygrad/uop/render.bend` → `cpython:render-gate-oracle` —
  the SAME oracle capture already read by the shipped reader, as an 85-entry JSON dict. The derived
  form; corroboration, and a fallback source, but not a text capture.
- `oracles/ops-rnd-gate-oracle.rows` — 12 lines, the `rnd_*` answers for a DIFFERENT gate.
- `runs/graphcmp/D/` (310 files) — **searched by content (`pyrender const`, `pyrender buffer`) and
  by name: 0 matches.** The corpus carries no render-lane capture.
- `.agents/slop/` at large — searched for `pyrender const` and for a padded port boundary
  ` = [`; the only captures that answer are the two flipthird `.err` files.

## 4. CAN THE PAIR BE RE-TAKEN? **NO. AND IT MUST NOT BE.**

**THE ORACLE SIDE CANNOT BE RE-TAKEN AT ALL — MEASURED, IT CRASHES.** `checks/render-gate-oracle.py`
IS COMMITTED (at `checks/render-gate-oracle.py`, since `3f0e70ff1`, 2026-10-04) — so the gate's
`ORACLE` constant (`:74`, `.agents/slop/xd1/render-gate-oracle.py`) names a path **0 commits ever
touched**, and the live lane's refusal is a **STALE PATH, not a missing artifact**. Fixing the
path does not make the lane work:

```
$ .venv/bin/python checks/render-gate-oracle.py --gate
ImportError: cannot import name 'pyrender' from 'tinygrad.uop.render'
  (…/tinygrad/uop/render.py)
```

**TWO INDEPENDENT REASONS, BOTH MEASURED:**
1. The `--gate` path puts `checks/head/` on `sys.path` to import upstream HEAD instead of the
   vendored hybrid (`checks/render-gate-oracle.py:15-16`). **`checks/head/` is ABSENT and is NOT
   TRACKED IN HEAD** (`git ls-tree -r HEAD -- checks/head/` = 0 entries), so it is not
   recoverable. Without it the script imports the vendored `tinygrad/`.
2. The vendored `tinygrad/` was **RE-VENDORED** at `86c4f1343` (2026-10-17, "RE-VENDOR tinygrad/ to
   upstream 002630241"), and upstream's `tinygrad/uop/render.py` no longer exports `pyrender`
   (it has `pretty_print` / `render_uir`). The script's own header says the vendored tree
   "disagrees with HEAD on 18 rows the port gets right" — but today it does not even import.

**THE PORT SIDE COULD BE RE-TAKEN, BUT NOT CHEAPLY, AND NOT INTO A COHERENT PAIR.**
`./bin/bend tinybendygrad/uop/render.bend`. Its own cost, from the capture that took it: the
watchdog line inside `base-render.err:162` records
`[bounded] WITHIN-LIMITS  rc=0  peak-RSS=702 MB (ceiling 2048)  2s`. And
`.agents/slop/peakrss/census.rows` records **`204 MB, rc=1`** for that file. **Both are over the
200 MB budget this unit was given**, and the census's `rc=1` says the run FAILED there. On top of
that, the pair would stop being a pair: the oracle side cannot be re-taken at all, so a fresh port
capture would be compared against a frozen oracle capture, and the gate's own docstring warns the
substrate is not still (`rn-gate.py:49-55`: `uop/ops.bend` and `uop/fold.bend` are in this port's
5-file import closure and belong to other live units; a zero on this lane is "a REQUEST FOR A
RETRY through `.agents/slop/eq/lane.py`, never a result").

**SO: RESTORE, DO NOT RE-TAKE.** Both halves of the pair are already in the tree, tracked, and
byte-verified. A re-take would produce a DIFFERENT pair and would destroy the one thing that makes
this lane worth having: it is the ONLY instrument in the tree that compares the render lane's
VALUES rather than its shape.

## 5. WHAT RESTORING THE LANE REQUIRES (NOT DONE HERE — this unit may only write under
##    `.agents/slop/rnpair/`, and the tree is a moving target)

1. **TWO NEW TRACKED FILES under `checks/`, renamed OFF `.txt`** — because `checks/no-txt.py`
   reports every `.txt` the project owns and **its five carve-outs do not include these names**
   (`checks/differ.py`, `.agents/slop/figure2/plant.py`, `.agents/slop/txtexec/rename.py`,
   `.agents/slop/skipexit/repro.py`, `checks/dup-census.py`'s cache). Committing them as
   `rn-port.txt` / `rn-orc.txt` turns `no-txt.py` red. The content is the byte content measured
   in §2 and §3.
2. **A RENAME OF THE GATE'S TWO DECLARED INPUT NAMES** in `checks/rn-gate.py` — `:400` (the
   `for _cap in` tuple), `:406-407` (the two `read_text()` calls) and the refusal message at
   `:402-405`. **The refusal message is also factually wrong** and should be corrected in the same
   commit: "the captured pair this lane judges was never committed … there is nothing to restore"
   is false about the CAPTURES. It is true about the two FILE NAMES.
3. **NOTHING ELSE.** The readers, the four plants and the `want` table are unchanged; the pair was
   measured against the gate's own code, and the gate's own `selftest()` returns 0 over it.
4. **SEPARATELY, FOR THE LIVE LANE** (`:468-473`): `ORACLE` at `:74` should name
   `checks/render-gate-oracle.py`. That fixes the REFERENCE and the refusal's claim that the
   script was "NEVER COMMITTED" — it was committed, at a different path, since 2026-10-04. **But
   the script then crashes** (§4), so the live lane's honest state is: the artifact is present, the
   path is stale, and the artifact itself is broken by the re-vendor. **Do not report "the live
   lane can be re-enabled with a one-line path change" — it cannot, and the measurement above is
   what says so.**

## 6. WHAT I DID NOT DETERMINE, AND WHAT WOULD SETTLE IT

- **NOT DETERMINED: whether a FRESH port capture, taken today, would still pair with the
  committed oracle capture.** Settling it needs `./bin/bend tinybendygrad/uop/render.bend` on the
  current tree — a 702 MB-peak run (or a 204 MB `rc=1` one) — and a comparison of the two row
  sets. It would PROVE the pair is still coherent against a moving substrate. It would NOT make
  the lane work, because the oracle side cannot be re-taken at all.
- **NOT DETERMINED: whether the five `arg_repr` disagreements are still the same five** against a
  current port capture. Same measurement, same cost.
- **NOT ATTEMPTED: writing `checks/rn-port.txt` / `checks/rn-orc.txt` or editing
  `checks/rn-gate.py`.** This unit may only write under `.agents/slop/rnpair/`, and the tree is
  under concurrent edit by other units (HEAD moved once during this investigation).
- **NOT RUN (per the brief):** `checks/differ.py`, anything under `gates/`, `checks/e2e*`,
  `checks/sweep.py`, `checks/bounded.py`, corpus-wide runs, pytest/mypy/ruff. The one gate I
  executed was `checks/rn-gate.py` — imported by path, with `HERE` redirected, and its
  `selftest()` run over the pair. No file outside `.agents/slop/rnpair/` was written; no git
  command was mutating; nothing was committed.

## 7. THE INSTRUMENTS, AND WHAT EACH ONE IS

| file | what it is |
|---|---|
| `requirements.md` | the two captures' exact requirements, quoted from `checks/rn-gate.py` |
| `candidates.rows` | TAB: path, origin, tracked, satisfies, why — 12 candidates |
| `measure.py` | the first sweep: the candidate vs the flipthird file, whole and sliced, and the 43/37 split |
| `measure2.py` | **the decisive one**: the pair, the md5s, the gate's own `judge()`, and **the gate's own `selftest()` VERBATIM** with `HERE` moved to this directory |
| `measure3.py` | the 22-vs-37 decomposition, the shipped reader's key counts (97 / 85), and the `oracles/baseline.json` lane |

Run them with `.venv/bin/python .agents/slop/rnpair/measure2.py` from the repo root.
