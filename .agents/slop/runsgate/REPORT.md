# runsgate — a gate's REQUIRED INPUT under a `.gitignore` rule

*Subagent report, 2026-10-06. Read-only on `gates/` and `AGENTS.md`; no `git add`,
no commit, no `bend`. Every number below carries the command that produced it.*

---

## 1. The instance, verified three ways

**NAMED?** YES.
`checks/run-port-mm.sh:50` (was):

```
ORACLE="$ROOT/runs/e2e/e2e-mm-oracle.json"
```

and it is `READ` at three sites in that file — the step-0 guard (`:67`), the
64/64 `diff` (`:133` reads `$ORACLE`), and the C3 plant source (`cp "$ORACLE"`).

**PRESENT?** YES. `runs/e2e/e2e-mm-oracle.json`, 19,253 B,
`sha256 39686a96002df4c4be4b3cea095ede839063614a6ecd32c73f7b1baca39cec00`.

**TRACKED?** NO. `git ls-files runs/e2e/` = **0**; `git check-ignore -v` →
`.gitignore:172:runs/`. The file is **present + ignored + untracked**: a gate
that passes here and has no input in a clone.

**BYTE-IDENTICAL IN HISTORY.** It was tracked until `cf2d14fa4` (the clause-III
"219 tracked generated files → 0" commit) deleted it with 168 `runs/` siblings.
`git cat-file blob cf2d14fa4^:runs/e2e/e2e-mm-oracle.json` = 19,253 B, and the
recovered blob is byte-identical to the on-disk file (same sha256, `diff` empty).
**So `runs/e2e/e2e-mm-oracle.json` is a RECORDED RUN, exactly the shape
`gates/cstyle-live.rows` was** — and the same answer applies: recover it to a
**tracked path beside the gate**.

---

## 2. The population — DISCOVERED, not listed

Instrument: `.agents/slop/runsgate/pop.py`. It walks `checks/*.sh`, `checks/*.py`,
`gates/*.py` (102 files), pulls every string literal (`.py` via AST) and every
`/`-bearing shell token (`.sh`), resolves each to a repo-relative path under
`runs/`, `gates/artifacts/`, `checks/gen/`, `checks/rows-*` or `checks/check.out`,
and asks `present`/`ignored`/`tracked` of each with `git`.

```
$ .venv/bin/python .agents/slop/runsgate/pop.py
POPULATION  20 distinct paths named across 102 files (17 sh + 85 py)
  paths with a READ site        : 8/20
  ignored by a rule             : 18/20
  tracked in the index          : 0/20
  READ + PRESENT + IGNORED + UNTRACKED (the defect): 8
```

The denominator, with the read sites that make each a **required input**:

| path | read at | present/ignored/tracked | decision |
|---|---|---|---|
| `runs/e2e/e2e-mm-oracle.json` | `checks/run-port-mm.sh:50`, `portexec/oracle.py:140`, `e2e_mm_gate.py:44`, `e2e_port/run-port-mm.sh:42` (all repointed) | P/I/U | **MOVE INTO GIT** → `checks/e2e-mm-oracle.json` (**landed**) |
| `runs/graphcmp/D` | `devpin.py:44`, `differ.py:42`, `disagree-gate.py:11` | P/I/U | **REGENERATE / REFUSAL** (generator `checks/differ.py run`) |
| `runs/graphcmp/D/D0-run-summary.txt` | `corpus-figure.py:182`, `env-precond.py:64` | P/I/U | REGENERATE (corpus-figure already REFUSES loudly; env-precond does not) |
| `runs/graphcmp/D/D0-coverage-census.txt` | `env-precond.py:134,151` | P/I/U | REGENERATE (env-precond has no absence guard) |
| `runs/graphcmp/D/D2-canon-py-late.txt` | `env-precond.py:135,149` | P/I/U | REGENERATE (env-precond has no absence guard) |
| `checks/gen/probe.js`, `checks/gen/probe.gen.c` | `checks/abi_gate.py:508-516,574` | P/I/U | **REFUSAL**: `abi_gate.py:605-611` CREATES them via `bend` before reading |

The other named paths (`runs`, `runs/e2e`, `runs/graphcmp`, `gates/artifacts`,
`gates/artifacts/*`, `<gate>`, `beautiful-mnist-gate`, `mixin-op-gate`,
`i64-shr/<lane>`, `cstyle-live/port.txt`) are **write targets or cites**, not reads
— `runs/e2e` is stage 3/6's output dir (`e2e.sh:45 RUN="$ROOT/runs/e2e"`), and
`gates/artifacts/*` is a generated directory.

**DENOMINATOR, one line:** of 20 paths named in `checks/*.sh`, `checks/*.py`,
`gates/*.py`, **8 have a read site; 18/20 are ignored; 0/20 are tracked; 6
required inputs resolve to an ignored, untracked path** — the oracle, the
`runs/graphcmp/D` family and its three named files, and `checks/gen/probe.*`.
(The 8th pop.py row is `runs/e2e` + `gates/artifacts`, write targets the
assignment heuristic misread — the instrument's false positives, named.)

**THE INSTRUMENT'S OWN BLIND SPOT, STATED:** `abi_gate.py` reaches `checks/gen/`
through `gendir / "probe.js"` (a computed join), so a literal scan misses it; it is
in the table above by hand, and the instrument is a **lower bound**.

---

## 3. Decisions

- **`runs/e2e/e2e-mm-oracle.json` → MOVE INTO GIT.** It is a pinned CPython
  RECORD (`e2e_mm.py`'s own trace), not per-run output. Tracking a *record* is
  right; the `cf2d14fa4` rule ("a tracked artifact is regenerable, and tracking it
  makes the next run show a diff that is not a change") is a rule about **output**,
  and this is an **input**. `gates/cstyle-live.rows` is the precedent.
- **`runs/graphcmp/D*` → REGENERATE (name the generator: `checks/differ.py run`),
  or REFUSAL.** These are the graphcmp run's own outputs; `retention-check` clause
  I/III/IV deliberately registers the directory as generated. Moving 150+ rows into
  git would overturn a *measured* decision, and a tracked row dump is "the same
  failure one level down". `corpus-figure.py` already refuses loudly with no run
  summary; **`env-precond.py` does not — it `read_text()`s the three files
  unconditionally and would raise `FileNotFoundError`.** That gap is the finding.
- **`checks/gen/probe.*` → REFUSAL (it is output the gate makes).** `abi_gate.py`
  runs `bend -o` into `checks/gen/` before reading it back, so a checkout is not a
  clone-blocker; but nine `checks/abi.json` citations are line-number pointers into
  a **regenerated** file, which is the real fragility.
- **`gates/artifacts/` → REFUSAL by design.** Its readers are the gate runners
  themselves; it is `.gitignore`d output, and `cstyle-live.rows` already moved the
  one *fixture* out to a tracked path.

---

## 4. The fix landed (smallest, complete)

A `.gitignore` negation inside `runs/` was **measured and REJECTED**: it would
leave the directory `runs/e2e/` ignored, so a committed oracle would make
`retention-check` clause V's **IGNORED-BUT-INDEXED** rule fire a *new* red
(`gendirs.ignored()` asks `git check-ignore --no-index -- runs/e2e/`). So the input
moves **out** of the ignored tree, beside the gate, and every reader moves with it.

| file | change |
|---|---|
| `checks/e2e-mm-oracle.json` | **NEW**, recovered byte-identical from `cf2d14fa4^` (`sha256 39686a96…`) |
| `checks/run-port-mm.sh` | `ORACLE=` now `checks/e2e-mm-oracle.json`; `mkcopy`/C3 plant paths → `$NC/checks/…` |
| `.agents/slop/e2e_port/run-port-mm.sh` | the **executed** copy (`e2e.sh:209`, `e2e.py:452`) — same three paths |
| `.agents/slop/portexec/oracle.py` | `e2e = ROOT / "checks/e2e-mm-oracle.json"` (the lane's real read) |
| `.agents/slop/e2e_mm_gate.py` | `ORACLE` → `checks/…` (stage 4 gate's real read) |
| `.agents/slop/e2e_mm.py` | `OUT = ROOT / "checks"` so the **writer** lands where the readers read (no drift) |
| `checks/e2e.py`, `.gitignore` | prose: the path moved; the old clause-V citation corrected |

`checks/e2e.sh` is **NOT** touched: it is pinned by `BODY_SHA` in `checks/e2e.py`,
and `e2e.oracle_drift()` returns `[]` (verified) with it unchanged. Its `:13`
comment is now **stale** and can only move in a `refreeze` — reported, not edited.

**TWO AUTHORITIES REMAIN** (this is a finding, not a fix):
- `checks/run-port-mm.sh` (relocated, asserts ROOT) and
  `.agents/slop/e2e_port/run-port-mm.sh` (the original) are **duplicates**, and
  `e2e.sh:209` / `e2e.py:452` still run the **`.agents/slop`** one, not the
  `checks/` one. Two copies of the same gate read the same oracle; both are now
  repointed, but they can drift. Wiring the callers at `checks/` is left to an
  owner.
- `checks/e2e.sh:13`, the frozen `.agents/slop/e2epy/oracle-e2e.sh:13`, and
  snapshots under `.agents/slop/skipexit/prefix/` still **cite** the old path.

---

## 5. The plant — REFUSED is not FAILED

`.agents/slop/runsgate/plant.py` copies the real `checks/run-port-mm.sh` to a
scratch ROOT (it asserts `pyproject.toml` + `tinybendygrad/`), runs it twice, and
never invokes `bend` (portexec is absent, and step 0 precedes any lane):

```
$ .venv/bin/python .agents/slop/runsgate/plant.py
  ABSENT   exit=3 refused=True  first= 'REFUSED, NOT A VERDICT: …'
  PRESENT  exit=1 refused=False first= '-----------------------…'
PLANT PASS -- ABSENT refused with 3 and PRESENT did not
```

- **ABSENT → `REFUSED, NOT A VERDICT`, exit 3.** Step 0 sets a **distinct** exit
  and token, so a missing record never reads as the port being broken.
- **PRESENT → exit 1, no `REFUSED`.** It gets *past* step 0 and fails later on the
  absent scratch machinery — a **FAIL**, not a refusal. The two states are
  distinguishable in the token and the exit code, which is the whole claim.

Scratch-path caveat, admitted: the PRESENT run does not complete the real lane
(that needs `bend`). The state under test — the step-0 precondition — is fully
executed, and it is the *input* state this unit owns.

---

## 6. `retention-check.py` clause V — ONE authority, and it does not see this

The two prior flags and `.gitignore:137-139` all say *"`gates/retention-check.py`
clause V records that conflict"* (`.agents/slop/gitignore/REPORT.md:227` cites
`:479-494, :550-553`). **It does not.** Clause V's rule is:

```python
# gates/retention-check.py:485
contradiction = [r for r in rows if r["n_tracked"] and r["ignored"]]
# :492
print(f"V  IGNORED-BUT-INDEXED: {len(contradiction)}/{len(rows)} dirs -- …")
```

That rule fires on a directory that is **indexed AND ignored**. `runs/e2e/` has
`n_tracked = 0` (measured: `git ls-files runs/e2e/` = 0), so it is **neither**, and:

```
$ .venv/bin/python gates/retention-check.py | grep IGNORED-BUT-INDEXED
V  IGNORED-BUT-INDEXED: 0/258 dirs -- none
```

`retention-check.py` never mentions `e2e-mm-oracle` (`grep` = 0 hits). **This is a
THIRD witness to a rule that does not implement it** — the exact failure
doctrine 1 names. The instrument sees *indexed∧ignored*; this defect is
*ignored∧REQUIRED*, a different hole it was never built for.

**My fix does NOT change clause V, and cannot:** that file is under `gates/`, which
this unit must not touch. It changes nothing in that output because the fix moves
the input *out* of the population clause V measures.

---

## 7. Artifacts

- `.agents/slop/runsgate/pop.py` — the DISCOVERED population (items 1–2).
- `.agents/slop/runsgate/plant.py` — the two-state refusal plant (item 5).
- `checks/e2e-mm-oracle.json` — the recovered, tracked-candidate record.

**Not done, and named:** no `git add`/commit (owner's call); `checks/e2e.sh`'s
stale comment (pinned by `BODY_SHA`); the two-copy gate (`checks/` vs
`.agents/slop/e2e_port/`) and the wiring of `e2e.sh:209` / `e2e.py:452`; the
`env-precond.py` absence guard; doc/ledger citations under `.agents/`.
