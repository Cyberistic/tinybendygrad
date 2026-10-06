# Restore the WIRING, not the instruments — and re-run what that revives

2026-10-06. Bytes were never the question; **"it runs and its subject resolves" is.** This
unit restored the DEPENDENCIES the 13 instruments died for, then re-ran the 5 BROKEN and the
3 ORPHANED. `bend` is held by another unit, so a bend-compiling mutator is measured by IMPORT
RESOLUTION + ANCHOR RESOLUTION and is **never executed** (doctrine 2: a SKIP is not a PASS).

**The systemic cause is confirmed and it is the wiring, not the instruments.** All 7 deleted
dependencies were removed by `371cc64c9` (the sweep), the same commit that took the files that
load them. Restoring them is what moved the classes.

---

## 0. The count, first

| measure | n / 13 |
|---|---|
| **restored** (bytes on disk, `git cat-file blob` non-empty) | **13 / 13** (+ **7 / 7** dependencies) |
| **running** (reaches a verdict; **0 die on the restored wiring**) | **13 / 13** |
| **executed green in this session** | 2 (`substrate-audit.py` rc=0; `e2e_gpu_probe.mjs` rc=0, prior unit) |
| **subject resolves** | **10 full + 1 partial** (tcptx 37/51) + 2 no (cstyle real lanes, pin-tables) |
| **LIVE now** | **2 / 13** (`e2e_gpu_probe.mjs`, `substrate-audit.py`; was 1) |

Full class census after repair, 13 = 2 + 8 + 2 + 1:

| class | n | instruments |
|---|---|---|
| **LIVE** | **2** | `e2e_gpu_probe.mjs`, `substrate-audit.py` |
| **READ-ONLY/UNSETTLED** (loads, needs `bend`, subject resolves) | **8** | `fold-rng-mutate.py`, `mixin-op-mutate.py`, `tcptx-mutate.py`, `tools/mutate-sz.py`, `ga_mutate.py`, `nn-init-mutate.py`, `state-mutate.py`, `rf2-mutate.py` |
| **ORPHANED** (loads; claim/subject gone) | **2** | `cstyle-shapes-selftest.py`, `pin-tables.py` |
| **BROKEN** (exists, does not run) | **1** | `tools/mutate-dm.py` (its OWN defect now, not the wiring) |

**+1 LIVE** (`substrate-audit.py`) and **+4 moved out of BROKEN** at import. The four that were
BROKEN *only* at `import patch_not_apply` are now READ-ONLY; `rf2-mutate.py`'s subject came back
with its file.

---

## 1. What was restored — `.agents/slop/instrepair/RESTORED.tsv`

7 dependencies + 13 instruments = 20 files. Each row carries path, blob, bytes, restoring
commit, sha256; every `git cat-file blob` answered **non-empty** (no `REFUSED`).

| dependency | bytes | blob | why |
|---|---|---|---|
| `.agents/slop/loadwatch.py` | 8982 | `01ca49164076` | `rebase-gate.py:164` → every instrument that loads it |
| `.agents/slop/oracle_py.py` | 5551 | `c91a2326e9a9` | `rebase-gate.py:165` |
| `.agents/slop/patch_not_apply.py` | 7626 | `0f8347842281` | the 4 `ga/nn-init/state/rf2` mutators |
| `.agents/slop/revision-ledger.py` | 8225 | `bb0f5d92d02d` | `substrate-audit.py` S1 |
| `.agents/slop/wire_parse.py` | 3119 | `47b4953ce972` | `substrate-audit.py` S2 |
| `.agents/slop/rebase-scan-oracles.py` | 11882 | `cdc60d5ed9e0` | `substrate-audit.py` S2 |
| `.agents/slop/rf2root/schedule/rf2_work.bend` | 193061 | `52fa11a55c80` | `rf2-mutate.py`'s subject |

Verification beyond the census: `import loadwatch`, `import oracle_py` and a full
`exec_module` of `rebase-gate.py` all succeed now — so `rebase-gate.py`, dead at import since
the sweep, is itself alive again.

### The `rf2_work.bend` subject, corrected

`newest_blob` first used `git log --all` and selected blob `089c10aacf44` from a **sibling
`portexec` branch** (`5444ea42eae3`, 14:21) — and that copy was a **WIP mutant**: M1's subject
was already inverted, so 41/42 anchors resolved and M1 counted 0. Restored instead from **this
history** (`git log` without `--all`, blob `52fa11a55c80`, commit `d897f17d3d8f`, the sweep's
parent line): **42/42 anchors resolve once, 0 zero.** A subject chosen by `--all` is a subject
chosen by branch order; only the instruments' own history is the reference.

**On the brief's item 3 ("do not restore `rf2-mutate.py`'s subject if it is gone"): it was not
gone.** `inst13` measured 0/42 because no file was on disk, not because no blob existed. The
blob exists and resolves 42/42, so it was restored under item 1 and the 0/42 is now closed.

---

## 2. The 8 re-run — `.agents/slop/instrepair/RECLASS.tsv`

| instrument | was | now | runs | measurement |
|---|---|---|---|---|
| `substrate-audit.py` | ORPHANED | **LIVE** | rc=0 | **4/4** assertions hold (was 1/4) |
| `rf2-mutate.py` | ORPHANED | READ-ONLY | loads | subject `52fa11a55c80`; **42/42** anchors (was 0/42) |
| `cstyle-shapes-selftest.py` | BROKEN | ORPHANED | rc=1 | wiring fixed; now dies on the **deleted real lanes** |
| `ga_mutate.py` | BROKEN | READ-ONLY | loads | `patch_not_apply` restored; **41/41** anchors |
| `nn-init-mutate.py` | BROKEN | READ-ONLY | loads | **15/15** anchors |
| `state-mutate.py` | BROKEN | READ-ONLY | loads | **12/12** anchors |
| `tools/mutate-dm.py` | BROKEN | **BROKEN** | rc=1 | wiring fixed; **own defect** below |
| `pin-tables.py` | ORPHANED | ORPHANED | rc=1 | its ~30 named tables still gone |

- `cstyle-shapes-selftest.py`'s rc=1 now comes from
  `blobrows/CURRENT/tinybendygrad__renderer__cstyle.bend.txt` and `cstyle-parity/oracle.txt`
  (its REAL-LANE subjects), not from `loadwatch`. Its synthetic controls pass. Those two lane
  files are SUBJECTS, have history, and were not in the enumerated restore set.
- `tools/mutate-dm.py` no longer dies on the wiring: it dies on
  `NameError: name 'importlib' is not defined` at `:24` — `importlib` is used at `:24-26` and
  **never imported**. That is an instrument defect, independent of the restored dependencies.
  The one-line fix (`import importlib`) is nameable but out of scope: this unit restores bytes,
  it does not author code into the restored instruments.

---

## 3. The one nameable repair — `tcptx-mutate.py` — `.agents/slop/instrepair/TCPTX-REPOINT.tsv`

`inst13` measured 37/51 anchors; **14 dead**. Measured now against both halves: **11 of the 14
re-point to `tinybendygrad/renderer/tc.bend`; 3 do NOT** — the brief's "14 because the tc.py
half split" is true for 11 and wrong for 3, which are dead because the SUBJECT TEXT evolved in
place.

**Re-point to `tinybendygrad/renderer/tc.bend` (11):**

| M-id | tc.bend:line | M-id | tc.bend:line |
|---|---|---|---|
| M1 | `:124` | M6 | `:409` |
| M2 | `:122` | M7 | `:515` |
| M3 | `:302` | M8 | `:554` |
| M4 | `:333` | M9 | `:455` |
| M4b | `:333` | M10 | `:97` |
| M5 | `:411` | | |

Each anchor occurs **exactly once** in `tc.bend` and **zero** times in `tc_ptx.bend`.

**Not a re-point — re-quote in place (3), all still in `tc_ptx.bend`, text changed:**

- **M14** `tc_ptx.bend:603` — `Tc` became namespace-qualified: anchor must read
  `def dsh_half.go(+ts: List<&2, T.Tc>, +acc: List<&2, T.Tc>) -> List<&2, T.Tc>:` with body
  `List.append(&2, T.Tc, ...)`.
- **M18** `tc_ptx.bend:597` — `def dsh_half.keep(+t: T.Tc) -> Bool: Bool.or(O.eq_dt(T.Tc.di(t), S.half()), O.eq_dt(T.Tc.di(t), S.single()))`.
- **M48** `tc_ptx.bend:621` — the dtype-name string was rewritten to
  `bool,f16,f32,f64,i16,i32,i64,i8,u16,u32,u64,u8` and the three `r_sd(75/53/80, …)` calls are
  now on ONE line, so the anchor's multi-line context no longer matches.

**Harness shape, not just anchors:** `tc_ptx.bend` now does `import ./tc.bend as T` (line 30).
37 anchors still live in `tc_ptx.bend`; 11 moved to `tc.bend`. So the repair is a **per-mutation
target file**, not "change `REL`" — changing the one `REL` would orphan the other 37. Not
applied here (needs a `bend`-holding unit to confirm the moved-row set).

---

## 4. Left alone, deliberately

- **`xd1/mutate.py` — NOT revived.** `lostinst` proved it is in no history path; guessing its
  bytes is exactly what this tree forbids.
- **`pin-tables.py`'s ~30 mutation tables** — still gone; only `bend_mutations.md` present. A
  pinner for absent tables is a claim about nothing.
- **`tools/mutate-dm.py`'s `importlib` NameError** — see §2; not authored here.

## 5. Side effect, stated

Restoring 20 files into `.agents/slop/` changes any census that counts that tree. The bytes are
new to disk; the instruments' own ledgers (`.agents/TOOLS.md`, `.agents/TODO.md`) were **not**
edited — `AGENTS.md`'s "14 INSTRUMENTS" clause can now read **2 LIVE / 8 READ-ONLY / 2 ORPHANED
/ 1 BROKEN out of 13** when a unit owns that edit.

## Reproduce

```
.venv/bin/python .agents/slop/instrepair/restore.py   # 7 deps + 13 instruments -> RESTORED.tsv
.venv/bin/python .agents/slop/instrepair/rerun.py     # imports + anchors; runs the 4 non-bend
.venv/bin/python .agents/slop/instrepair/repoint.py   # tcptx 14 -> TCPTX-REPOINT.tsv
.venv/bin/python .agents/slop/instrepair/reclass.py   # RECLASS.tsv
```

Artifacts: `RESTORED.tsv` · `RECLASS.tsv` · `TCPTX-REPOINT.tsv` · `rerun.json` · `run/*.out|.err`.
