# 259 `oracles/**/*.txt`: population, the pin, and what a rename costs

**Verdict, up front: the coupling the brief assumes does not exist.** `ORACLE_PIN` does **not**
read the 259 `oracles/*.txt` by name, by glob, or by anything. It is a sha256 over two *shell
bodies* (`.agents/slop/diffpy/oracle-run.sh`, `.agents/slop/diffpy/oracle-repro.sh`), and those
bodies read `runs/graphcmp/D/*.txt` — a **disjoint** population. So renaming any of the 259
cannot move the pin, and the "never edit an oracle and its pin in one commit" rule does not apply
to this population at all. Evidence below; every number is measured.

## 1. Population, by discovery (the denominator)

`os.walk(oracles/) + endswith(".txt")` — a directory walk, not the inherited 259 and not a hand
list. Instrument: `.agents/slop/txt259/discover.py` (`.venv/bin/python`, output in `census.out`).

| measure | value |
|---|---|
| `.txt` files under `oracles/` | **259** |
| tracked in git (`git ls-files`) | **259** (0 untracked) |
| non-`.txt` files under `oracles/` | 99 |

The inherited 259 is **confirmed by re-count**, not trusted. 259 is also what
`checks/oracle-txt-census.py` reports via `rglob("*.txt")` and what `checks/no-txt.py`'s walk
finds — three independent walks, one answer.

### Reach (who names them) — token-resolved, not a basename join
Instrument: `checks/oracle-txt-census.py` (loaded by path), which resolves `.txt` tokens through
variable bindings and compares the reader's path **by bytes**.

| reach | count | meaning |
|---|---|---|
| `LIVE` | **4** | a tracked script opens a path holding **these bytes** |
| `SHADOW` | 0 | a reader opens a *different* file with this basename |
| `STALE` | **30** | a tracked script opens a path that is **ABSENT**; this file is the basename it named — a gate input that moved |
| `NOTHING` | **225** | no tracked `.sh`/`.py` names it |

4 + 0 + 30 + 225 = 259. The inherited "30 named only by gone paths / 225 named by nothing" is
reproduced exactly.

**The 4 LIVE rows are not gate reads.** They are `.agents/slop/oracles259/ordering.py` (a scratch
tool belonging to the *classification unit*, inside the swept `.agents/slop/` tree) reading
`oracles/schedule-bodies/BEFORE-rows.txt` and `oracles/schedule-bodies/sb-oracle.txt` — two
duplicate copies that happen to hold the same bytes as the top-level `oracles/BEFORE-rows.txt` and
`oracles/sb-oracle.txt`. No production gate opens any `oracles/*.txt` at a present path.

### Committed `checks/` readers (the load-bearing ones)
Broad grep (`readers_for` in `discover.py`) finds `checks/` naming these basenames:

- `checks/sb-gate.sh` — `:42, :51` (`$D/BEFORE-rows.txt`, `$D=oracles/schedule-bodies/…`),
  `:114–:151` (`$D/rows-bd.txt`, `$D/sb-oracle.txt`). Its own header says it gates **nothing** and
  `exit 3`s: `sb-oracle.py`, `sb-diff.py` and `BEFORE-rows.txt` are absent from
  `.agents/slop/schedule-bodies/`. The `oracles/` copy is the surviving duplicate.
- `checks/lintable-gate.sh:177–179` — `$GT-oracle.txt` where `GT=.agents/slop/lintable` → **absent**.
- `checks/sweep.py:279, :735` — **comments** mentioning `blob-bn.txt`, not reads (false positive).

Caveat, stated so the number is not overread: a basename grep is a **superset**. `oracles/oracle.txt`
matches the substring inside `$GT-oracle.txt`; the census's token resolution is the authority on
liveness. The grep is used only to enumerate `file:line`, never to decide LIVE/STALE.

## 2. What the pin actually reads, and by what name

`checks/differ.py:61` `ORACLE_PIN` (a dict; `:58` is a comment) holds two entries:

```
"diffpy/oracle-run.sh":   "94e7108d428bae3fb211db5cce000819b63e2bfbfd51dad4c512e42626d15905"
"diffpy/oracle-repro.sh": "a5d23505b3e93816370e67df130993e812abd2db7e5c6919d6e98d51af92d2ea"
```

`check_oracle()` hashes `.agents/slop/diffpy/*.sh` and compares. **Run today: INTACT.** The pin is
over **the shell bodies by path**, covering **zero `.txt` files**.

What those bodies name (measured by `grep -n '\.txt'`):

| site | names | kind |
|---|---|---|
| `.agents/slop/diffpy/oracle-repro.sh:61` | `runs/graphcmp/D/D0-run-summary.txt` | **BY NAME** |
| `.agents/slop/diffpy/oracle-repro.sh:105` | `runs/graphcmp/D/*.txt` (via `find … -name '*.txt'`) | **BY GLOB** |
| `.agents/slop/diffpy/oracle-repro.sh:114` | `runs/graphcmp/D/{D1-graph,D3-control,D5-plant,D6,D9-stability}-*.txt` | **BY GLOB** |
| `.agents/slop/diffpy/oracle-run.sh` | writes all 139, reads twelve by name | **write + BY NAME** |
| `checks/differ.py:244–265` `declared()` | `{D0-*, D1-graph-*, D2-canon-*, …}.txt` | the generator's own declaration |
| `checks/corpus-figure.py:170` | `runs/graphcmp/D/D0-run-summary.txt` | **BY NAME** |

> The brief cites `oracles/oracle-repro.sh:61` and `checks/corpus-figure.py:137`. Neither is the
> read: there is **no** `oracles/oracle-repro.sh` (the file is `.agents/slop/diffpy/oracle-repro.sh`),
> and `corpus-figure.py:137` is `gc.load_tinygrad()`, part of a module loader; the actual read is
> **`:170`**. The brief also calls `:72` the non-read — that is correct: `:72` is
> `module_from_spec`.

**Decisive measurements:**

```
grep -n 'oracles/'  .agents/slop/diffpy/oracle-run.sh \
                    .agents/slop/diffpy/oracle-repro.sh \
                    checks/differ.py          ->  rc=1  (ZERO hits)
[n for n in differ.declared() if (oracles/n).exists()]  ->  []        (declared()==139, all runs/graphcmp/D)
[oracles/*.txt matching ^D[0-9]]                        ->  []        (no name collision)
```

**`declared()` = 139, and every one lives under `runs/graphcmp/D/`. The 259 live under `oracles/`.
The two sets are disjoint.** `checks/no-txt.py`'s carve-out (`graphcmp_artifacts()`) is built as
`runs/graphcmp/D/<name>`, so it can never excuse an `oracles/` file. The 553 HARD count includes
**all 259**.

## 3. What a rename costs, and the commit split

For the 259: **nothing in the pin, and one commit suffices.**

- Renaming `oracles/<x>.txt` → `.rows` does not alter a byte of either shell body, so `ORACLE_PIN`
  keeps both values **unchanged**. There is no pin to move and no second commit to make. The
  forbidden "rename + pin in one commit" is not a choice here because there is no pin move.
- The only real cost is the reader sites: **4 LIVE** and **30 STALE** basenames. The LIVE reader is
  `.agents/slop/oracles259/ordering.py` (scratch, under the swept tree) plus the duplicate copies
  `oracles/schedule-bodies/{BEFORE-rows,sb-oracle}.txt`. Renaming must either repoint those or leave
  the two duplicate copies in place. `checks/sb-gate.sh` names `.agents/slop/schedule-bodies/…`
  (already absent, already `exit 3`), so it is unaffected by renaming `oracles/`.
- **`UNCLASSIFIED` (and `empty`) must not be renamed to `.rows`** — see §5.

**If the intent was the `runs/graphcmp/D` population (the 139 excused), that is a different
problem and the two-commit rule bites there:** those names are read BY NAME at `oracle-repro.sh:61`
and BY GLOB at `:105/:114`, and `differ.declared()` + `no-txt.py` are built from them. Renaming an
artifact requires editing the shell bodies, which changes their bytes, which moves `ORACLE_PIN`.
Split across two commits, commit 1 leaves `check_oracle()` RED (pin names old bytes) — a retired
pin for one commit. In one commit, oracle and pin move together — exactly the forbidden form. The
only honest options are (a) **do not rename those artifacts**, or (b) re-base the pin in one
witnessed commit and record that the pin moved. **Neither is required for the 259.**

**PLAN.tsv** (`.agents/slop/txt259/PLAN.tsv`) carries one row per file: `path`, `cls`, `probe`,
`reach`, `readers` (`file:line`), `pin_covers` (`none` for all 259), `new_path`, and the exact
`restore` command. No rename is performed.

## 4. Restore verification (real, against git)

`git cat-file blob HEAD:<path>` is the restore. Verified two ways, nothing under `oracles/` written.

- **Sample of 10** (`.agents/slop/txt259/verify_restore.py`, output `restore-check.out`): one
  guaranteed per disposition plus a spread. **10/10 resolve to a non-empty blob from HEAD matching
  the manifest digest.**
- **All 259** (`.agents/slop/txt259/restore_all.py`, output `restore-all.out`):
  - blob **resolves from HEAD: 259/259**
  - **HEAD == worktree: 259/259** (every restore is identity)
  - **manifest sha256 column WRONG: 18/259**
  - 258 hold non-empty bytes; 1 (`oracles/rows-bd.txt`) is genuinely **0 bytes**.

The 18 "failures" re-derive the inherited "restore proven for 241 of 259" — **but the cause is the
manifest's digest column, not the restore command.** The command is correct for all 259; the
manifest handed 18 rows *another row's* digest (`blob-bn.txt`←`blob-py.txt`,
`cstyle-capture-oracle.txt`←`…renderer_oracle.txt`, `rows-matmul-py.txt`←its own duplicated hash…),
the exact failure `manifest.py`'s docstring predicted. **A restore is proven by bytes; the manifest's
own hash is not evidence of itself.**

## 5. Classes, with counts

Primary classifier: `checks/oracle-txt-census.py`'s three-mechanism `shape()` (a hand-written
`key=value` predicate, a nearest-neighbour fit against the 35 blessed `.rows`, and a
structure-before-mime language test) — **imported by path, never copied**. Second opinion:
`independent_class()` in `discover.py` (tab / markdown-heading / sentence-density), which shares no
threshold with the census and exists to catch the ambiguity `UNCLASSIFIED` is for.

| class | count | target ext |
|---|---|---|
| row dump | **240** | `.rows` |
| crash dump / captured stderr | **7** | `.err` |
| source in `.txt` | **3** | `.bend`/`.py` |
| **flagged: census says rows, content probe disagrees** | **9** | see below |

The 9 flags are **not** silently promoted to row dump:

| file | probe | file bytes/lines |
|---|---|---|
| `oracles/rows-bd.txt` | **empty** | **0 bytes** — UNCLASSIFIED, must not become `.rows` |
| `oracles/naming-gate-baseline.txt` | **tsv** | 684 lines, 669 tab-separated → `.tsv` |
| `oracles/main_rows.txt` | **tsv** | 227 lines, all tab-separated → `.tsv` |
| `oracles/wip/main_rows.txt` | **tsv** | 227 lines, all tab-separated → `.tsv` (duplicate of the above) |
| `oracles/baseline.txt`, `oracles/arglit/baseline.txt` | md | 28 prose lines w/ `#` headings |
| `oracles/cshape/rows-run0.txt`, `oracles/rows-run0.txt` | md | 27 prose lines w/ `#` headings |
| `oracles/rf-arg-oracle.txt` | md | 15 lines, 11 `key=value` rows (probe false positive — it IS a row dump) |

No `prose` group exists in the census output; the md-shaped files above are the only prose
candidates it produced, and the census's own comment records that `#` headings were deliberately
excluded from the source test (a heading is weak evidence of a language). The 3 `tsv` files and the
empty file are genuine misclassifications to review — **`UNCLASSIFIED` is not row dump.**

## Reproduction

```
.venv/bin/python .agents/slop/txt259/discover.py        # population, PLAN.tsv, census.out
.venv/bin/python .agents/slop/txt259/verify_restore.py  # 10-row sample
.venv/bin/python .agents/slop/txt259/restore_all.py     # all 259
.venv/bin/python checks/oracle-txt-census.py            # reach + shape, independent instrument
```

Artifacts: `PLAN.tsv`, `census.out`, `restore-check.out`, `restore-all.out`. Nothing renamed,
nothing deleted, nothing committed.
