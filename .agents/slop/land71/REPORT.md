# LAND71 — the manifest unit

Population by **discovery**, not by the predecessor's 77.

## Denominators

- `git status --porcelain` (dirty/untracked/modified/added): **813** paths.
- `afd395686`'s changed set vs its parent `ec08adcfb` (`git diff --name-only`): **118** paths.
- **BOTH** (dirty AND carried by `afd395686`): **19** paths — the MANIFEST's population, one row each, at `.agents/slop/land71/MANIFEST.tsv`.
- Cross-check against the stale71 inventory: 76 of its 77 are carried by `afd395686`; only 17 of those 76 are still dirty — the rest moved on (committed or gone), so trusting the 77 would have classified 59 decided paths.

## Per-class counts (of 19)

| class | n |
|---|---|
| LAND | 5 |
| GENERATE | 10 |
| REFUSE/IDENTITY | 2 |
| REFUSE/LINK | 2 |
| REFUSE/* (total) | 4 |

`afd395686` itself: parent `ec08adcfb`, **not an ancestor of HEAD** (`git merge-base --is-ancestor` rc 1), 1-byte message (a newline), reachable only at `refs/jj/keep/afd395686...`. It MUST NOT land as-is: it carries both dangling symlinks.

## LAND (5) — each row has a restore command whose blob was verified

| path | evidence | bytes (afd395686) |
|---|---|---|
| `.agents/slop/notes/bend2-constraints.md` | `oracles/fold-rng-oracle.py:83` cites it; `:105` too | 1,665,622 |
| `.agents/slop/ops_bend-milestone-expected.txt` | `.agents/slop/opsbend_milestone_gate.py:27` opens it | 4,626 |
| `.agents/slop/shells/README.md` | `checks/e2e.py:226` cites it | 9,678 |
| `checks/citation-gate.py` | `.agents/slop/stale71/REPORT.md:121` names its classifier | 10,988 |
| `checks/unowned.py` | `.agents/slop/stale71/REPORT.md:3` names the instrument | 10,408 |

Every `git show afd395686:<path>` returned rc 0 and non-empty bytes — no restore command names a blob that is not there.

## GENERATE (10) — each row names its generator; nothing landed

- `checks/residue.py:586` writes `.agents/slop/residue/{000-the-residue,002-unknown,003-disagreements}.md` (3).
- `.agents/slop/e2e_mm_run.mjs:54,56` emits `.agents/slop/e2e/{webgpu_call,e2e_mm}.mjs` (2).
- `.agents/slop/helpers-tc-gate.sh:34` writes `.agents/slop/helpers-tc-gate.{bd,bn}{,.err}` and `.rows.err` (5).

## REFUSE/IDENTITY (2) — copies, not witnesses

- `.agents/slop/helpers-tc-gate.rows` — byte-copy of `oracles/helpers-tc-gate.rows` (same blob `b3eec639ee`).
- `.agents/slop/webgpu_call.fresh.mjs` — byte-copy of `.agents/slop/e2e/webgpu_call.mjs` (same blob `2ae2551df4`).

## REFUSE/LINK (2) — targets absent NOW

- `bin/bin` → `/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/wt-a/bin` — the directory `wt-a` does not exist.
- `tinygrad/tinygrad` → same prefix `wt-a/tinygrad` — gone.

`Path.exists()` follows symlinks, so both read PRESENT only until the target day; they must be stripped from any landing of `afd395686`.

Nothing was moved, renamed, or deleted. Instrument that cross-checked blob identity: `.agents/slop/land71/dups.py` (`.venv/bin/python`).
