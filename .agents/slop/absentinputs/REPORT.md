# The absent-input class, SIZED

**`READ ONLY — REPORT ONLY. NOTHING WAS FIXED. NO COMMIT WAS MADE.`**

| | |
|---|---|
| **HEAD** | `96f1611c8ea229f2e712b0697325af8b3795de91` (7433 tracked paths) |
| **timestamp** | `2026-10-17T00:51:57Z` |
| **HEAD at census start** | `444890672d9baebb6309952495f480623f481fc5` — **the tree moved under the census** and every number below was RE-TAKEN at the HEAD named in this table |
| **population source** | `env -u GIT_INDEX_FILE git ls-tree -r HEAD --name-only` (the default index is chronically stale and lies) |
| **artifacts** | `sites.rows` (166→**162** adjudicated sites), `sites.raw.out` (mechanical, every candidate), `discover.py`, `rows.py`, `plantcheck.py` |
| **what I ran** | `ast.parse` on source text, one `.venv/bin/python` at a time, plus read-only `git ls-tree`/`cat-file -e`/`diff`. **No `bend`, no `gates/*.py`, no `checks/differ.py`, no e2e/sweep/bounded, no pytest/mypy/ruff.** `gates/*.py` were READ AND PARSED, never run. |

---

## 1. THE CLASS

An instrument declares an external input (a script, an oracle, a captured fixture) and reads or
executes it **with no existence guard**, so when the file is gone the instrument reports a LANE
FAILURE instead of an ABSENT SUBJECT. The repo's own vocabulary is PASS 0 / FAIL 1 / REFUSED 3 /
SKIP 4 / DEAD 5. **Absent is not a pass, and an absent subject is REFUSED (3).**

## 2. THE SPLIT, WITH DENOMINATORS

| # | population | count | denominator |
|---|---|---|---|
| D0 | instruments in scope (`.py` + `.sh` under `checks/` and `gates/`, from HEAD) | **279** | 260 `.py` + 19 `.sh` |
| **N** | **instruments naming an EXTERNAL input** (≥1 path literal outside their own directory, present or absent) | **89** | of 279 |
| — | candidate path literals extracted | 910 | 317 external / 593 own-dir |
| — | present, disk AND HEAD | 444 | |
| — | present on disk, **not in HEAD** | **41** | a DIFFERENT state; counted separately, not as absent |
| — | present in HEAD, not on disk | **0** | |
| — | present as a DIRECTORY, not a file (a scan root) | 63 | not an input |
| — | `PRESENT_SUFFIX_ONLY` — matches a tracked path by suffix, literal written against a base computed at runtime (`uop/ops.bend` under `tinybendygrad/`) | 200 | **weak present; disclosed** |
| **n1** | **target ABSENT (disk AND HEAD, no directory, no suffix match)** | **162** — 7 external, 155 own-dir | of 910 literals |
| n1′ | instruments with ≥1 absent target | **49** | of 89 (of 279) |
| n1″ | instruments with ≥1 absent **external** target | **5** | of 89 |
| **n2** | **ABSENT and UNGUARDED — THE DEFECT COUNT** | **2** | of 162 absent sites |
| n2′ | instruments carrying a defect | **2** | of 89 |

**A count without a denominator is not a result**, so: **2 defects in 162 absent sites, in 49 of
the 89 instruments that name an external input, in a scope of 279 instruments.**

### Verdict distribution over the 162 absent sites

| verdict | sites | reading |
|---|---|---|
| **`DEFECT-ABSENT-UNGUARDED`** | **2** | absent, no guard, absence reads as **FAIL** (one) or as **silent GREEN-and-wrong** (one) |
| `GUARDED-REFUSED` | **8** | absent and correctly REFUSED — the fixed pattern, incl. all 3 previously-known instances |
| `PLANT-*` (self-written, fixture, negative-control, scratch, emitted, state-fixture, orphan) | 133 | the instrument CREATES the file; its absence is the intended state |
| `NOT-AN-INPUT-*` (row-value, emitted, name-set, label, scratch) | 15 | path-SHAPED but never opened |
| `SELF-WRITTEN` / `DELETION-BY-DESIGN` | 6 | a probe it plants and removes; an `rm -f` by design |
| `UNADJUDICATED` | **0** | every site carries a verdict |

## 3. THE TWO DEFECTS, NAMED

### 3.1 `checks/gen_gate.py` → `checks/hdr.bend` — the purest instance of the class

- `gen_gate.py:138` — `HEADER = open(os.path.join(HERE, "hdr.bend")).read()` **at column 0**.
  `HERE = os.path.dirname(os.path.abspath(__file__))` (`:22`), so the target is `checks/hdr.bend`.
- **It is module level.** `def main()` is at `:170`. The read happens at **import**, before any
  lane can run.
- **Absent from disk AND HEAD, and 0 commits ever touched it**
  (`git log --all -- checks/hdr.bend` → empty).
- **No guard of any kind exists in the file.** `grep -n 'is_file|exists|refuse|exit(3)|SystemExit|FileNotFound|except'`
  over all 221 lines returns **nothing**. There is not even a `try`.
- **The absence reads as FAIL.** `FileNotFoundError` out of `open()` → CPython prints a traceback
  and exits **1**. The repo's own doctrine is explicit that exit 1 is "a stage ran and got the
  wrong answer" — but no stage ran. Nothing here can even reach the `DEAD` (5) vocabulary.
- **It is live and depended upon.** `.agents/slop/i64div/gate.sh:15` runs
  `python3 gen_gate.py || { echo "GENERATOR FAILED"; cat gen.out; exit 1; }` — so the absent
  input becomes an explicit `exit 1` failure verdict. `.agents/slop/i64mul/census.py:18,87`
  `subprocess.run`s it for the i64mul census (`.agents/slop/I64MUL.md:11` claims 442/442 rows from it).
- **Corroboration that this is not new information:** `.agents/slop/gatesrun/REPORT.md:22`
  already lists `checks/gen_gate.py` among *"libraries (no guard)"*. The class was identified
  once and not repaired. I am re-reporting it because the brief asks for the size, not because
  it was undiscovered.
- **The other four paths `gen_gate.py` names are OUTPUTS it writes** (`:211,217,218,219`), so
  `hdr.bend` is the only input it depends on, and the only unguarded one.

### 3.2 `checks/classify.sh` → `.agents/slop/mutledger/BLOBHIST.tsv` — worse than FAIL: green and wrong

- `classify.sh:20` — `H=.agents/slop/mutledger/BLOBHIST.tsv`. The **only** use is `:26`
  `grep -q "^$live	$b\$" "$H"`.
- Absent from disk AND HEAD — but **RECOVERABLE**: it is in 5 commits (`5444ea42e` and four
  siblings), so this is a restore, not a permanent refusal.
- **Unguarded.** The only `[ -f` in the file is `:18`, for `pyproject.toml`. There is no test of
  `$H` and no exit-3 arm for it.
- **The absence does not read as FAIL. It reads as a confident WRONG VERDICT.**
  `grep` on a missing file exits 2, so the `else` at `:27` fires and **every** differing file is
  reported **`PLANT`** instead of `STALE`. The script's exit status is the last `printf`, i.e. **0**.
- This directly contradicts the file's own header (`:9-10`): *"A PLANT is a deliberately-mutated
  copy still sitting in the tree. That is the thing that must not be reachable by accident."*
  With the ledger gone, **every stale copy is now reported as a plant, and the report is green.**
  Per this repo's doctrine, *a gate that exits 0 having measured nothing is worse than no gate,
  because it is trusted* — and here it exits 0 having measured something false.

## 4. THE CONTROL — it PASSED, on both halves

Required before reporting any split. Both halves run, both recorded.

**Control A — the test must FIND the three known-fixed instances. It does, all four literals:**

| instrument | literal | disk | HEAD | class |
|---|---|---|---|---|
| `checks/rn-gate.py:74` | `.agents/slop/xd1/render-gate-oracle.py` | no | no | external |
| `checks/rn-gate.py:400` | `rn-port.txt` | no | no | own_dir |
| `checks/rn-gate.py:400` | `rn-orc.txt` | no | no | own_dir |
| `checks/vz_gate.py:59` | `viz_oracle.py` | no | no | own_dir |

**All three are now guarded, confirmed by reading:**

1. `rn-gate.py:468-470` — `if not a.oracle_stdout and not (REPO / ORACLE[0]).is_file(): refuse(...)`
   → exit 3 (`:77-84`), sitting **before** the subprocess at `:477`.
2. `rn-gate.py:400-405` — loops `("rn-port.txt","rn-orc.txt")`, `if not (HERE / _cap).is_file(): refuse(...)`
   → exit 3, **before** the reads at `:406-407`.
3. `vz_gate.py:74-77` — `if not os.path.isfile(ORACLE): refuse(...)` → exit 3 (`:61-71`),
   **before** the subprocess at `:78`.

**Control B — the test must NOT fire on a same-directory code reference. It does not:**
**236** literals land `own_dir` + present on disk and in HEAD (`checks/coindep.py` from
`checks/abi4_gate.py`, `checks/abi.json`, `checks/nvrows-deadrow-gate.py` from `checks/census.py`, …).
Every one of those is sibling **code**, and none is reported as a finding.

**I also ran the control against my own instrument four times and it failed four times.** Each
failure is recorded below, because the fixes are the reason the final numbers are defensible:

| # | defect in MY instrument | measured symptom | fix |
|---|---|---|---|
| 1 | docstrings and prose harvested as paths | 47,183 candidates, **0 present** — a census of my own regex | path charset `^[A-Za-z0-9_./@+-]+$` + explicit docstring exclusion |
| 2 | HEAD existence desynced | `present_disk_and_head = 0`, including `render.bend` which exists — newline-bearing targets corrupted `cat-file --batch-check` stdin | set-intersect `git ls-tree` output instead of batching stdin |
| 3 | a slashed path resolved against the wrong base | `tinybendygrad/uop/tinybendygrad/uop/render.bend`, `checks/.agents/slop/xd1/…` — 100% phantom absences | try repo-root **and** instrument-dir anchors; exist if **any** resolves |
| 4 | `../` and `./` prefixes | `../checks/gatesweep.py` reported absent while **both** `checks/gatesweep.py` and `checks/index-arm-gate.py` exist on disk and in HEAD | same two-anchor rule |
| 5 | extension matched inside a word | `Nat.show` read as `Nat.sh`; `s.count` read as `s.c` | `(?![A-Za-z0-9])` word boundary + reject a token preceded by `(` |
| 6 | template suffixes | `name.endswith("-gate.py")` and `f"D6-{g}-ordered.txt"` counted as paths | reject a basename starting with `-` |
| 7 | shell scratch-dir variables | `RUN/e2e-mm-gate.out`, `GT/`, `W/`, `OUT/`, `SL/` — 116 phantoms from 10 files | reject an ALL-CAPS first segment; reject `$1/…` positionals |
| 8 | `isfile` on a DIRECTORY | `runs/graphcmp/D`, `.agents/slop`, `tinybendygrad` counted absent | separate `dir` signal |
| 9 | **my own typo** | I hand-verified `.agents/slop/ops_bend-milestone.sh` as absent — I had typed `ops_bend`; the real name is `opsbend` and it EXISTS. The instrument was right and I was wrong | recorded, because it is the reason I trust the instrument over my spot-checks |

**Defects 4 and 5 are the ones that matter for the count**: each was silently *inventing* absent
targets, i.e. inflating the very number I was asked to size. Defect 9 is the inverse — a manual
check inventing an absence that was not there.

## 5. WHAT IS *NOT* A FINDING, and why it matters to the count

Absence alone is not the defect. **133 of the 162 absent sites are plants** — files the instrument
creates in order to see that it notices. Counting them would have inflated the class by 66× and
the class would have been worthless. The discrimination was made mechanically, not by taste:

- **`self_written()`** (`rows.py`): ±400 chars around any mention of the basename, searched for a
  create/remove verb. **84 rows** resolve this way — the fixture vocabularies of
  `gate-surface.py` (`planted.py`, `unplanted.py`, `vacuous.py`, `nogreen.py`, `home-witness.py`),
  `gates-pop.py` (`good.py`, `bad.py`, `wrong-shallow.py`, `undeclared.py`, `keeper.py`),
  `msgdiff-gate.py` (`keep.py`, `victim.py`, `more.py`, `cnt.py`, `ported.py`), `gendirs.py`,
  `runner.py`, `git-massdelete-gate.py`, `index-arm-gate.py`, `bounded.py`. **This check can only
  turn a row INTO a plant; it can never manufacture an external finding, because every row it
  touches is own-directory absent.** 87 of 89 candidates resolved; the 2 that did not were the
  `js-lane-census` control files, which are guarded (below).
- **`READ` (25 rows)**: I read the use site and its guard, and the evidence in `sites.rows` cites
  the line. Both defects and all 8 guarded rows are in this tier.
- **`CATEGORY` (53 rows)**: a family whose exemplar I read, with the exemplar's line cited.
  `decided_by` is a column in `sites.rows` **precisely so a count never mixes the three tiers
  silently** — the failure mode of the "487 mutations / 25 unclassified" number this repo already
  recorded once.

Two more shapes that look like inputs and are not:

- **path-SHAPED ROW VALUES** (5): `gates/datasets-oracle.py:27-28,38` — `CIFAR_TEST`,
  `train-images-idx3-ubyte.gz`, … are emitted as `srow("dst_cifar_test", CIFAR_TEST)` rows
  describing members of a downloaded tarball. Never joined to a path, never opened.
- **an EMITTED OUTPUT whose absence IS a verdict** (4): `checks/abi_gate.py:371-376` and
  `checks/gate_norm.py:119-123` — `abi_probe.js` / `gate_norm.js` are `bend -o` targets, and
  `if not out.exists()` is exactly the code that separates REFUSED from DEAD. Absence here is
  the instrument working.
- **a NAME SET, and the file says so**: `checks/slop-declare.py:96` —
  *"This is a name set, not a population"* — the instrument matching directory listings.

## 6. ADJACENT, NOT PART OF THE COUNT

- **`AGENTS.md` contains a false existence claim.** It asserts
  `.agents/slop/ops_bend-milestone-expected.txt` **EXISTS** ("BOTH EXIST"). MEASURED
  2026-10-17: **absent from disk AND HEAD.** The sibling claim in the same sentence
  (`.agents/slop/xd2/cdp.mjs`) **does** hold. This is the failure mode AGENTS.md itself documents
  — a path named in a ledger, not owned by it — and it is a *document* defect, not an instrument
  defect: the file is referenced only in **comments** (`checks/e2e.sh:147,168`,
  `checks/e2e.py:42`), never read, so no gate misbehaves.
- **`checks/gen_gate.py` is run from `.agents/slop/i64mul/` with `cwd=HERE`**
  (`census.py:18,87` expects `gen_gate.py` *there*). That is outside `checks/`/`gates/` and so
  outside this population; I did not test it.
- `.agents/slop/gatesrun/REPORT.md:22` already classifies `gen_gate.py` as "no guard". This audit
  re-derives it independently and agrees.

## 7. WHAT I COULD NOT DETERMINE

Stated rather than guessed, per the brief's preference for REFUSED over a guess:

1. **The 19 shell files are the weakest part of the census.** They were read as TEXT and matched
   by regex, never parsed, and `SHELL_REGEX_ONLY` is recorded for each in `discover.py`'s output.
   Six separate false-positive modes had to be closed (§4 rows 5, 7). Shell **occurrence-line
   attribution is unreliable**: for `checks/sb-gate.sh` the literal is found at **line 9, a
   comment**, while the real use is at `:153` via `$ORACLE` and the **guard** is at `:81`. I
   adjudicated `sb-gate.sh` correctly only by reading it. **Any shell-only finding would need
   re-reading by hand; I did not find one, and I do not claim the shell subset is clean.**
2. **Existence was decided on exact-anchor + suffix-match, never by running anything.** A path
   reached through a computed base, a glob, an env var, or a symlink target is not resolvable from
   source text. The **200 `PRESENT_SUFFIX_ONLY`** rows are disclosed as weak-presents and are
   **under-counted as findings** by construction: a literal whose real base is computed at
   runtime could be reported present when it is not. This biases the defect count **down**.
3. **Guards were adjudicated by reading, not by control-flow analysis.** "Guarded" means I saw an
   `is_file()`/`exists()`/`-f`/`-e` check or a `refuse()`/exit-3 **before** the use on the path I
   read. For a site whose use sits behind a conditional I did not trace, `GUARDED` means
   *unguarded on the paths I read*. The 53 `CATEGORY` rows lean on this hardest.
4. **The two defects were determined statically, by reading the code.** I did not run
   `gen_gate.py` or `classify.sh` to observe the traceback and the exit 1, and I could not
   measure `classify.sh`'s STALE→PLANT relabelling on real data. Both are read from the code
   path; the *absence* claims are `os.path.isfile` + `git cat-file -e`, which were measured.
5. **`PRESENT_SUFFIX_ONLY` and `disk-only-not-in-HEAD` (41 rows) are reported but not
   adjudicated.** Those 41 are files on disk that no commit owns — the shape that lets a gate's
   inputs vanish silently — and they are a separate census, not this one.
6. **`.agents/slop/` was deliberately excluded from the walk** (along with `references/`,
   `node_modules/`, `.git`) to bound memory on a tight machine, so the ~39k-file disk set is not
   the whole filesystem. Any target reached only through those trees is unresolved.

## 8. REPRODUCING THIS

```
env -u GIT_INDEX_FILE git ls-tree -r HEAD --name-only > .agents/slop/absentinputs/head-tree.out
grep -E '^(checks|gates)/.*\.(py|sh)$' .agents/slop/absentinputs/head-tree.out \
  > .agents/slop/absentinputs/pop-code.out
.venv/bin/python .agents/slop/absentinputs/discover.py   # -> sites.raw.out, the counts in §2
.venv/bin/python .agents/slop/absentinputs/rows.py       # -> sites.rows, the verdicts
.venv/bin/python .agents/slop/absentinputs/plantcheck.py # -> the 87/89 plant confirmation
```

**The tree is a moving target: HEAD advanced `44489067` → `96f1611c` during this census.** Four
sites changed state because another session materialised plant fixtures on disk. Every number in
§2 was re-taken at `96f1611c`; the two defects and all eight guarded rows are unchanged across
both HEADs.