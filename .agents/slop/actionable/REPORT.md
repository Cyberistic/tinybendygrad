# ACTIONABLE triage — `checks/repro-paths.py`'s 45 dangling paths

**PROVENANCE.** `.venv/bin/python checks/repro-paths.py`, read-only, **no `--mark`**.
HEAD `7a826eb70a4599392e229b750782a5e9d76a2f24` (`7a826eb7`), run `2026-10-17T00:16:05Z`,
re-verified `2026-10-17T00:19:42Z` with identical counts. Every `git` call prefixed
`env -u GIT_INDEX_FILE`; the default index is chronically stale and was never read.

**THE TREE MOVED UNDER ME, TWICE, AND IT CHANGES THE ANSWER.** The task brief says 46 ACTIONABLE;
this run says **45**. `git rev-parse HEAD` read `9122a0d2` at `00:15:20Z` and `7a826eb7` at
`00:16:05Z` — another session committed between two commands of my own. **I CANNOT ACCOUNT FOR THE
46TH ROW.** It is either one row that resolved or one that appeared between the brief's run and
mine. **A count of 46 with no row named is not reproducible from this artifact, and I decline to
reconstruct it.** Everything below is 45 of 45 at the HEAD named above. Re-run before citing.

## THE SPLIT, WITH ITS DENOMINATOR

| verdict | n | of |
|---|---|---|
| **REAL** | **2** | 45 |
| **DECLARED_ABSENT** | **7** | 45 |
| **FALSE_POSITIVE** | **36** | 45 |

45 = 2 + 7 + 36. Every member is named in `rows.rows`, one row per path, 5 TAB-separated fields,
verified 1:1 against the run with no missing and no extra row.

Context, from the same run: 562 committed reports at HEAD name 3,586 distinct paths
(+2 written as patterns); 3,026 of 3,586 resolve; 560 dangle, of which 45 are ACTIONABLE and 515
historical. **So 2 of 560 dangling paths (0.36%) are REAL, and 2 of 45 ACTIONABLE (4.4%) are REAL.**
A count without these denominators is not a result.

## THE THREE I WAS TOLD ABOUT — CONFIRMED, AND TWO OF THEM ARE NOT "REAL"

All three are in `checks/rn-gate.py`, and all three are **DECLARED_ABSENT, not REAL**: each is a
genuine declared input that the gate *tests for* and then **REFUSES (exit 3)** rather than running
or reporting a verdict.

- `.agents/slop/xd1/render-gate-oracle.py` — `rn-gate.py:74` argv literal, **guarded at
  `:467-468`** (`if not (REPO/ORACLE[0]).is_file(): refuse(...)`), exec at `:475` is downstream.
- `checks/rn-orc.txt` — **guarded at `:400-402`** in a loop over `("rn-port.txt","rn-orc.txt")`,
  `read_text()` at `:406` is downstream.
- `checks/rn-port.txt` — same guard; `read_text()` at `:405` is downstream.

**The brief's own framing is the first finding.** These three are the *only* three whose citation
the tool found in **code** (`:74`) rather than prose — and for two of them the citation the tool
printed is a **comment** (`:393`), while the real use sits four lines below it as a bare
basename in a tuple. The brief expected REAL-and-fixed-to-refuse; the honest verdict is that they
were already counted, and the category that fits them is DECLARED_ABSENT. Reporting them as REAL
would overstate the finding by 3.

## THE TWO THAT ARE REAL

1. **`.agents/slop/cstyle-live/run-all.log`** ← `checks/run-f64.sh:104`. `grep -m1` reads it inside
   a `say`. No guard: the nearest `exit` is `mkdir -p` at `:83`, and the substrate `WARM` test is at
   `:107` — **after** the read. `grep -n 'set -e' checks/run-f64.sh` returns nothing, so the missing
   file degrades to an **empty sha printed as if it were a measurement**, not to a refusal.
2. **`.agents/slop/ops_bend-milestone-expected.txt`** — **REAL, and the tool attributed it to the
   wrong instrument.** The only thing `checks/e2e.sh` does with it is mention it in comments
   (`:147`, `:168`). The reader is `.agents/slop/opsbend_milestone_gate.py:27`
   (`EXPECTED = pathlib.Path(__file__).parent / "ops_bend-milestone-expected.txt"`) and `:36`
   (`_RAW = EXPECTED.read_text()`) — **unguarded, at import**. `checks/e2e.sh:161` reaches it via
   `.agents/slop/opsbend-milestone.sh:93`. `.agents/slop/` is **not** in the tool's `LIVE_HOMES`, so
   the instrument that actually reads it cannot be a citer. This is the one row where the tool's
   citation is a false positive *and* the row is REAL, and a name-only triage would have filed it
   under FALSE_POSITIVE and lost it.

## THE FALSE-POSITIVE CLASS THE BRIEF ASKED ME TO LOOK FOR — IT IS LARGER THAN EXPECTED

**Nine rows are an instrument citing its own history or its own old home**, which is precisely the
class the brief warned about, and it is **9 of 45 = 20%** of the ACTIONABLE population:

- **`checks/repro-paths.py` citing itself, 4 rows**: `blob-intern-gate.sh` (`:12`), `li/li-control.sh`
  (`:14`), `ops-gate.sh` (`:13`), `mathlib/const_probe.bend` (`:16`), plus `guardfix/probe-c.bend`
  (`:16`) and `tn_graph_census-gate.py.bak` (`:56`) — all six are the **docstring that justifies the
  tool itself**. The tool's own `live_citers()` docstring at `:111-113` admits "a name match, so
  prose counts too", and then `classify()` at `:123` promotes prose to ACTIONABLE anyway.
- **A gate naming where it used to live, 3 rows**: `checks/marker-audit.py:4` names
  `.agents/slop/marker-audit.py`; `checks/nl-gate-noguard.py:4` names
  `.agents/slop/eq/nl-gate-noguard.py`; `checks/gate.py:75-77` names `.agents/slop/jsfp8/drive.mjs`
  inside its own refusal **message**.
- **A docstring that is simply WRONG about where its input lives**, 2 rows:
  `checks/repair-dupes.py` says the good rows are at `gates/artifacts/cstyle-live/port.txt` (`:33`,
  `:40`) while its code reads `gates/cstyle-live.rows` (`:48`, which **exists**, 46291 B); and
  `checks/vz_gate.py:5` says the oracle is `.agents/slop/vz/viz_oracle.py` while `:60` runs
  `checks/viz_oracle.py`.
- **Synthetic plants and needle tables**, 6 rows: all five `gates/gates-pop.py` rows
  (`checks/bad.py`, `checks/good.py`, `checks/driver.py`, `checks/first.py`,
  `checks/abi_gate.py.fixed`) are written into `tempfile.TemporaryDirectory()`s and read back out of
  them — they are never repo files. `checks/gate.out` is `checks/gate_norm.py`'s **own output**
  (`:271` `write_text`).

## METHOD, AND TWO BUGS IN MY OWN FIRST PASS

`rows.rows` is not a reading, it is a verdict, so I built two read-only scanners over the citing
instruments and parsed source text with `ast`/`tokenize` (nothing imported, nothing executed):
`scan.py` → `mentions.rows` labels every mention DOCSTRING / COMMENT / STRING_LITERAL / DICT_KEY;
`shadow.py` → `shadow.rows` looks for **variable-derived** uses the literal match cannot see.
**Two defects in my own instruments, both caught by disagreeing with the source, both recorded here
because each one inverted a verdict:**

1. `shadow.py` retired **every string literal** as prose. That filed `checks/nl-port-post.txt` as
   FALSE_POSITIVE on the strength of a comment at `nl-gate.py:420` — while `_live = HERE /
   "nl-port-post.txt"` at `:416` is the line that makes it a real input. **A gate writes its inputs
   as string literals; that is what an argv and a `Path()` are made of.** Retiring strings retires
   the uses.
2. `shadow.py` ran the Python `tokenize` over `.sh`, which raises, and my fallback marked **every
   line** of `checks/gate.sh` and `checks/sb-gate.sh` prose — about to hide the two real `$SL` and
   `$D` variable uses. Caught because the tool's own citation evidence for both rows was a comment.

**THE STRUCTURAL POINT, AND IT IS THE SAME DEFECT ONE LEVEL DOWN.** For **7 of the 45 rows the
citation the tool printed is a comment or a docstring while the real use is elsewhere in the same
file** — `nl-port-post.txt`, `rn-port.txt`, `rn-orc.txt`, `checks/isolate.py`, `checks/drive.mjs`,
`shlscope/gen.py`, `sb-oracle.py`. The path is reached by **basename** (`HERE / "isolate.py"`) or by
**a variable holding its directory** (`SL=.agents/slop/shlscope; $SL/gen.py`). `live_citers()` does
a **substring test for the full relative path**, so it finds the prose and misses the use. **A
literal match finds the mention; only reading the code finds the dependency.**

## BYSTANDERS FOUND WHILE READING — REAL, AND **OUTSIDE** THE 45

Both are unguarded missing inputs that **no committed report names**, so they cannot appear in this
population. They are the reason a "45 rows, 2 REAL" headline is a floor and not the whole.

1. **`checks/viz_oracle.py` does not exist and `checks/vz_gate.py:60` runs it.** `lanes()` calls
   `run([sys.executable, os.path.join(HERE, "viz_oracle.py")])` with **no guard anywhere above
   `:60`** (verified line by line). The row the tool *did* report, `.agents/slop/vz/viz_oracle.py`,
   is the stale docstring name for this same input.
2. **`checks/drive.mjs` does not exist** and is the live JS driver of `checks/gate.py:202`. It IS in
   the 45 (as `checks/drive.mjs`) but only because a *different* gate's docstring names it.

## WHAT I COULD NOT DETERMINE

- **The 46th row.** Not reproducible from this artifact. See the drift note. REFUSED, not guessed.
- **Whether the guards actually fire.** I read the code; I did **not run `checks/rn-gate.py`,
  `checks/gate.sh`, `checks/sb-gate.sh` or `checks/run-f64.sh`** — the brief forbids it and the
  machine is critical. Every "REFUSES" above is a **code reading**, cited to a line, not an
  observed exit status. The two REAL rows are equally read-not-run.
- **`checks/gates-pop.py`'s 5 plants and `checks/hermetic-census.py`'s fallback are claims about a
  temp tree that only a run can confirm.** The *citations* are unambiguous; the *runtime behaviour*
  is not mine to assert.
- **Whether the 515 historical rows are all legitimately historical.** Out of scope, unexamined. A
  count of 515 with no denominator is not a result either.
- **`.agents/slop/opsbend_milestone_gate.py`'s absence guard** — there is none before `:36`, so the
  e2e chain's milestone stage raises `FileNotFoundError` at import rather than refusing. Whether any
  caller catches that, I did not trace past `:93` of `opsbend-milestone.sh`.

**NOTHING WAS FIXED.** No commit, no `--mark`, no edit to any file outside
`.agents/slop/actionable/`.