# jjhazard — what the `visualjj` process does to the git index

Measured 2026-10-06 14:16–14:25 in `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`
(jj-colocated git repo, `.jj` + `.git` in one tree). Every number below was produced by a
named instrument; the artifacts are in this directory.

## Verdicts (five-verdict lexicon)

| question | verdict | evidence |
|---|---|---|
| who/what the process is | **PASS** | `pgrep`/`ps`/`lsof` + extension manifest |
| does it write `.git/index` | **PASS (conditional)** | deterministic repro below |
| reproduce by *waiting 60 s* | **REFUSED / negative** | no jj op in an 8-min window |
| reproduce by *causal sequence* | **PASS** | `repro-mechanism.out` |
| safe staging primitive | **PASS** | `primitive-tests.out` |
| detection guard + plant | **PASS** | two states, `INDEX-OK` / `INDEX-DRIFT` |

**The session's attribution was incomplete.** `visualjj` is a *carrier*, not the sole author:
units run `jj commit` on the same shared index (op-log args: `jj commit -m …` ×17, `jj diff` ×20).
Both the extension's server and a unit's `jj` command reset the index by the **same** path — the
one below — and the trigger that arms it is a **unit's own `git commit`**.

## 1. The process, measured

```
pid 2368  ppid 1520  etime 01-03:44:51  (still running)
/Users/cyberistic/.vscode/extensions/visualjj.visualjj-0.35.4-darwin-arm64/dist/bin/jj branching server
```

- It is the extension's **bundled** `jj 0.45.1+visualjj-…` (a fork), not the system `jj 0.42.0`.
- `jj branching server` = *"Run a JSON-RPC server for IDE integration"*; the fork adds
  `jj branching snapshot` (*"Trigger a working copy snapshot…"*) and a documented **snapshot loop**
  (`docs/watcher.md`, referenced in the binary's own help).
- Activation is `onStartupFinished` (extension `package.json`); the process predates this session.
- Repo config that makes it dangerous: `snapshot.auto-track = "all()"`,
  `visualjj.snapshot-workspaces = true`, `fsmonitor.watchman.register-snapshot-trigger = false`.
- **It spawns no subprocesses.** `ps` sampled every 10 s for 120 s: zero children; `lsof -p 2368`
  shows only its own binary and the VS Code unix sockets on fds 0/1/2/5. The snapshot runs in-process.
- Changelog 0.35.4: *"Skip snapshotting when no files changed (macOS)"*, 0.35.2: *"Adapt snapshotting
  frequency to working copy size"*, older: default every 1 s → 10 s. This is why its rate is gated.

## 2. What it does to the index — the mechanism

In a colocated repo the git index and jj's working copy are two views of one tree. `git add` writes
`.git/index`; a `jj` operation that creates or imports commits then **re-imports git HEAD and rewrites
`.git/index` relative to it**, discarding the staged set. Deterministic, isolated, one scenario per
fresh repo (`repro_mechanism.py` → `repro-mechanism.out`, bundled jj):

```
git add; jj commit                     staged 1->0  HEAD 1d637e3e->283ff7c5  RESET   reflog: export from jj
git add; jj branching snapshot         staged 1->1  HEAD (unchanged)        no-op
git add; jj status                     staged 1->1  HEAD (unchanged)        no-op
unit git commit; git add; jj snapshot  staged 1->0  HEAD (unchanged)        RESET   reflog: commit: unit git commit
unit git commit; git add; jj commit    staged 1->0  HEAD ec0a9ec8->2d817a68  RESET   reflog: export from jj
```

The last two rows are the session, reproduced: a unit's `git commit` moves HEAD to a git-only commit;
the **next** `jj` operation — including the extension server's own `branching snapshot`, which is a
no-op in a quiet repo — imports that commit and rewrites `.git/index`, and **`git diff --cached`
goes to 0**. `jj commit` additionally repoints HEAD (detached, reflog `export from jj`), which is the
"HEAD moved to a commit I did not make" symptom. The real repo is in exactly that state: `.git/HEAD`
is a raw sha (detached), and `.git/logs/HEAD` holds ten `export from jj` entries (739–803).

## 3. The 60-second wait — it does **not** reproduce by idling

- **Passive watch** (`watch_index.py` → `passive-watch.tsv`, 115 s, no `jj`/`git` invoked by me):
  index inode/size changed twice and HEAD moved `c0d2689e7 → b3a4c476b18a`.
- **Attribution** (`watch_correlate.py` → `correlate.tsv`, 300 s, heartbeat file rewritten every 20 s):
  jj's **op-store mtime never advanced from `1791285353509060632` (= 14:15:53)** for the entire
  window — the snapshot loop wrote **zero** operations. Meanwhile the index was rewritten ~10 times
  and HEAD moved 4 times (`b3a4c476b18a`→`956de35262a2`→`1e9507f92fdd`→`800161b016f6`→`bcd715b5df28`),
  each a unit commit. Most writes sampled with a live `git`/`jj` process (`git_procs=1`);
  the few that read `0` occurred *between* a unit's stage and its commit (the process came and went
  inside one 5 s interval) — and the constant op-store mtime rules jj out for all of them.
- **Staged-file test** (`repro_index_reset.py` → `repro.out`, 120 s): staged count stayed `1` the whole
  window; `NO CHANGE within window`.

So the hazard is **not** periodic: it is gated on (a) a preceding `git commit` that diverges HEAD, and
(b) the snapshot loop actually firing. A nondeterministic hazard, rate ≈ once per git/jj interleave.

## 4. The safe staging primitive

Measured (`primitive_tests.py` → `primitive-tests.out`):

```
[untracked pathspec commit] rc=1  error: pathspec 'u.rows' did not match any file(s) known to git
[shared index  vs resetter] staged ['s.rows'] -> []        WIPED (hazard confirmed)
[private index vs resetter] staged ['s.rows'] -> ['s.rows'] SURVIVES
```

**The one safe command form:**

```
GIT_INDEX_FILE=.git/agent-index git add -- <paths> \
  && GIT_INDEX_FILE=.git/agent-index git commit -m "MSG" -- <paths>
```

Why it is safe: the resetter owns `.git/index`; it does not know or touch `.git/agent-index`, so
staging into the private index is atomic against it, and `-- <paths>` scopes the commit to exactly
your paths so a concurrent unit's broad `git add -A` cannot leak in. It also sidesteps the measured
fact that `git commit -- <untracked>` fails outright (rc=1 above). If HEAD may also move, pin the
parent with a compare-and-swap: `… git commit-tree <tree> -p <captured-head>` then
`git update-ref HEAD <new> <captured-head>` (refuses if HEAD moved).

Direct evidence of why this matters: a concurrent unit's broad add **committed my `probe.rows`
into HEAD** during this session; it is now tracked by git and `git add` on it is a no-op.

## 5. Detection guard

`checks/git-index-guard.py` (`.venv/bin/python`, no deps, `git --no-optional-locks` so it never
writes the index). It fingerprints the two things a reset moves — the staged set **and** HEAD —
because a reset makes the staged set empty *relative to the new HEAD*, and staged-empty→staged-empty
alone reads as agreement.

```
git-index-guard.py snap                    -> INDEX-BASELINE <tok> HEAD <sha> STAGED <n>
git-index-guard.py check --expect <tok>    -> INDEX-OK      exit 0
                                              INDEX-DRIFT   exit 1
                                              INDEX-REFUSED exit 3   (no --expect)
                                              INDEX-DEAD    exit 5   (no repo/HEAD)
```

**Plant, two states:**

```
STATE A (nothing staged):          INDEX-BASELINE …  STAGED 0   then  INDEX-OK    rc=0
STATE B (staged, then reset):      INDEX-BASELINE …  STAGED 1   then  INDEX-DRIFT rc=1
```

Orchestrator use: run `snap` immediately after staging, `check --expect <tok>` immediately before
committing; a non-zero exit means the index moved under you — abort and re-stage into a private index.

## 6. Artifacts

- `watch_index.py`, `passive-watch.tsv` — passive index/HEAD sampler
- `watch_correlate.py`, `correlate.tsv` — index vs jj-op-store vs git-process correlation
- `repro_index_reset.py`, `repro.out` — the literal 120 s staged-file test (negative)
- `repro_mechanism.py`, `repro-mechanism.out` — the deterministic causal reproduction (positive)
- `primitive_tests.py`, `primitive-tests.out` — the safe primitive, measured
- `mechanism_demo.py`, `mechanism-demo.out` — first isolated attempt (showed colocated `jj` alone
  does not export; the trigger is a git-only commit)
- `checks/git-index-guard.py` — the guard

## 7. Corrections to the session's record

- Commit `9e700e003` ("visualjj … is what has been resetting the index all session, not the units")
  is itself an **unsourced attribution**. Measured today: the extension wrote zero ops in 8 minutes,
  and every observed index write was a unit's git/jj command. The mechanism is real and the
  extension can drive it — but so can any unit's `jj commit`, and the arming event is a unit's
  `git commit`.
- `.git/index` currently holds **0** null-OID entries (parsed from `index-snapshot.bin`, 6478 entries,
  all `H`), so the "537 intent-to-add ghosts" symptom is **transient**, not a standing index state.
- The prior attribution was the doctrine-1 failure one level up: a conclusion with a named culprit
  and no instrument. The instrument is now `checks/git-index-guard.py`.
