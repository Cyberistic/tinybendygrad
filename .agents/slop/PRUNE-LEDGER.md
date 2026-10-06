## SLOP PRUNE LEDGER (2026-10-06T16:00Z, HEAD `4bb9afa1`)

`.agents/slop` went **133 MB -> 43 MB** this session. Every deletion below named a
**generator, a report, or a per-file reason**, per the rule that a prune which cannot say
what it spared is a prune nobody can audit.

| removed | bytes | authority |
|---|---|---|
| `substratepop/tree/` | 11 MB | **its own `REPORT.md:8` calls it "debris"**; a frozen copy of the port that already DIVERGES from the live tree (`renderer/tc_ptx.bend` differs) — neither a mirror nor re-derivable |
| `arghalf/`, `loopfix/`, `xd1/`, `dd-cone-wt/` frozen trees | 84 MB | `prune2` — superseded by a re-takeable measurement |
| 11 `__pycache__` dirs | 0.5 MB | already `.gitignore`d (`.gitignore:13`), 0 tracked |
| `jjhazard/index-snapshot.bin` | 732 KB | a raw `.git/index` DIRC dump, untracked, named by nothing |
| 11 `loopfix/*.bin` | 10.0 MB | `prune3` — each a `bend -o` build with a committed generator and a committed `.err` naming the command; outputs (`.rows`) committed |
| `run34/gcb-{head,now}.bend` | 108 KB | **my own scratch** — the byte-identity that proved `graphcmp.bend` unchanged is IN the commit message, not two copies of the file |
| `webgpu_call.fresh.mjs` | 1.0 MB | build product; `e2e_mm_run.mjs:48` documents the port's own is STALE and the runner regenerates it; byte-identical to tracked `e2e/webgpu_call.mjs` |

**SPARED, each with a measured reason (not a shrug):**
- `strays/` 3 MB — `prune3` re-audited all history: **0 of 24 KEEP blobs ever appeared at the live path**, so they are UNIQUE, not a mirror.
- `e2e/` 2 MB — **named by 25 committed readers**; deleting it breaks readers that are not tests.
- `loopfix/insprobe{,-v2,-old}.bin` 340 KB — the generator was **deleted and never committed**, so "no generator" is an **absence, not a proof of redundancy**.
- `spine/` (8 identical `.out`) and `rerun/` (7) — **the duplicates ARE the measurement**: `stable-pairs` exists because two runs must produce the same bytes.
- 1.96 MB of remaining redundant blobs — every group is either a fixture sandbox (37 groups, 0.09 MB, load-bearing) or **run evidence where a duplicate is the witness**.

**THE ONE I BROKE MYSELF:** my own `git add -A` committed 15 regenerated `.txt` fixtures
(`git ls-files '*.txt'` 2 -> 19). `git add -A` **cannot tell a violation from evidence** — it
adds everything the index lacks, which is exactly what `no-txt.py` refuses. Fixed in its own
commit so the check still means something. **Commit-by-explicit-path exists for this.**