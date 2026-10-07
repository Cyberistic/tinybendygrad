# jjreset — the mass-delete guard for a `jj`-colocated git repo

Measured 2026-10-07 05:32–05:40 in `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`.
Every claim below carries its instrument; the artifacts are in this directory.

## Verdicts (five-verdict lexicon, `gates/gatekit.py:60`)

| question | verdict | evidence |
|---|---|---|
| is there a `jj` repo HERE | **PASS — yes** | `.jj/{repo,working_copy}` present; `tools.jj.workspace_root` answers |
| is `visualjj` / pid 2368 alive | **FAIL — pid 2368 is DEAD** | `ps -p 2368` empty; a `jj branching server` runs at **pid 30543** |
| did the reset mechanism reproduce | **PASS (causal) / negative (passive)** | jjhazard's `repro-mechanism.out` vs `passive-watch.tsv`; not re-run |
| does the guard catch the catastrophe | **PASS** | `churn.rows`, `verdicts.rows` |
| guard plant, two states | **PASS** | `plant.out` / `plant.err`, rc 0; 6000-file state `REFUSED, NOT A VERDICT` rc 3 |

## 1. What the `jj` server actually IS here

A colocated jj repo **does exist** — `.jj/repo` and `.jj/working_copy` are on disk and
`tools.jj.workspace_root` returns this tree. So `AGENTS.md`'s mechanism names a hazard that is
**present**, not imagined.

But the record's two named details are stale:

- **`pid 2368` is dead.** `ps -p 2368` is empty. The `jj branching server` from
  `visualjj.visualjj-0.35.4-darwin-arm64` is alive at **pid 30543** (ppid 30017). A pid in a
  governing document is a citation with a shelf life; the *class* — `jj branching server` — is
  what survives.
- **The dangerous config is per-REPO, not repo-local, and two of its quoted keys do not exist.**
  jj stores per-repo overrides under `~/.config/jj/repos/<config-id>/config.toml`, and this repo's
  config-id is `1013720a994d3c872163` (`.jj/repo/config-id`). That file holds
  `[snapshot] auto-update-stale = true` and `[visualjj] snapshot-workspaces = true` — the second is
  the key that lets the extension snapshot the workspace, and it **is present**. The
  `snapshot.auto-track = "all()"` and `fsmonitor.watchman.register-snapshot-trigger = false` keys
  jjhazard quoted are **in no config file I can find**: not the user config
  (`~/.config/jj/config.toml`, 9 lines, no snapshot block), not the per-repo config, not the
  extension's `package.json`. `grep -rIl 'auto-track' ~/.config/jj` is empty.

Standing conditions (`.agents/slop/jjreset/jj-facts.rows`): `.git/HEAD` is a raw sha (detached),
`.git/logs/HEAD` holds **650** `export from jj` entries, and `.jj/repo/op_heads/heads` was written
at mtime `1791340465` (05:34:25) — the op store **is advancing**, so jj operations are live now.

## 2. The reset — I agree with jjhazard, and did not re-run the negative

`.agents/slop/jjhazard/REPORT.md` already measured both halves, and my reading agrees:

- **60 s passive: NEGATIVE.** `repro_index_reset.py` → `repro.out`: staged count stayed `1` for the
  window, `NO CHANGE within window`; `watch_correlate.py` → `correlate.tsv`: jj's op-store mtime
  never advanced across 300 s, so the snapshot loop wrote **zero** ops while the index moved ~10
  times — every write a unit's `git`/`jj` command.
- **Causal: POSITIVE.** `repro_mechanism.py` → `repro-mechanism.out`: `a unit git commit; git add;
  jj snapshot` takes staged `1 → 0` — a reset — reproducing the session.

The honest verdict the tree already has is **the mechanism is intermittent and gated, not
periodic**: it fires on (a) a preceding `git commit` that diverges HEAD, and (b) the next `jj`
operation firing. Re-running a negative test would add nothing, so I did not. My only addition is
the standing-condition reading above — detached HEAD, 650 `export from jj` entries — which is the
state jjhazard describes.

## 3. The guard, and the threshold taken from the data

`.agents/slop/jjreset/git-massdelete-gate.py` — Python, no deps, `git --no-optional-locks` so it
never writes the index it guards. Verdicts are `gatekit`'s: `PASS,FAIL,REFUSED,SKIP,DEAD = 0,1,3,4,5`.

The threshold is **measured, not guessed.** `churn.py` walks the last **120** commits of this tree
(`churn.rows`):

```
normal (120 commits)   max deleted files =  185   (15a485f0a)
                       max deleted lines = 237256  (a808071e8, a deliberate scratch-tree removal)
catastrophe            6167 deleted files / 1947172 deleted lines   (61be7ea90)
```

`REFUSE_FILES = 500` (2.7× the worst normal churn) and `REFUSE_LINES = 900000` (3.8× the worst
normal churn) separate the envelope from the catastrophe with headroom on both sides. The axis
that does the work is **deleted FILES**: 185 → 6167 is a clean 33× gap.

It is **REFUSED, not FAIL**, because the gate does not know the deletion is wrong — it knows the
*precondition* (an explanation for this much loss) is absent. Supply one with
`MASS_DELETE_ACK="<reason>"` (or `--ack`) and it PASSes, having recorded the reason.

Read-only readings on the real tree (`verdicts.rows`):

```
61be7ea90  6167 files  1947172 lines  REFUSED, NOT A VERDICT  rc=3   <- the catastrophe
813bbec3e     0 files        0 lines  PASS  rc=0                   <- the recovery
a808071e8   146 files   237256 lines  PASS  rc=0                   <- the largest LEGIT delete
baa109329    15 files      115 lines  PASS  rc=0                   <- the git-add-A .txt sweep
9d44f2c63     0 files        1 lines  PASS  rc=0
949cea833     1 files       50 lines  PASS  rc=0                   <- HEAD
staged             -            -     PASS  rc=0
```

**The one command that would have caught the catastrophe in one second is `git show --stat
<commit>` before pushing**, and `61be7ea90`'s own stat reads `6168 files changed, 1 insertion(+),
1947172 deletions(-)`. This gate is that look, mechanised.

## 4. Plant — two states, token AND exit code, in a SCRATCH repo

`git-massdelete-gate.py --plant` builds its own repo in a `TemporaryDirectory` (never this one):

```
PASS: HEAD deletes 1 files / 1 lines -- inside the envelope                      rc=0
REFUSED, NOT A VERDICT: HEAD deletes 6000 files / 6000 lines -- envelope: ...     rc=3
  D f0.bend ; D f1.rows ; ... (40 named, then "... and 5960 more")
PASS: HEAD deletes 6000 files / 6000 lines -- inside the envelope (ack: ...)      rc=0
--plant: all states OK
```

Four states, all asserted: a 1-file delete **PASSes**; a 6000-file delete **REFUSES, NOT A
VERDICT** at exit **3**, naming paths; the same catastrophe **PASSes with `--ack`**; and the
pre-push half PASSes a fast-forward and REFUSES a non-fast-forward. `run.py` re-runs it and
asserts the tokens (`plant.out`, `plant.err`).

## 5. What ELSE needs the guard — and yes, it can be a pre-push hook

`git push --dry-run` after a commit is the other half: a commit is local and cheap to undo, but a
push publishes. **Yes, the guard can be a pre-push hook, and force-push being forbidden does not
disable it — it makes the hook stricter.** Git hands a pre-push hook the refspec
`<local_ref> <local_sha> <remote_ref> <remote_sha>` on stdin; the guard walks
`git rev-list <local> --not <remote>` and checks each new commit. Because this tree forbids
rewriting pushed history, the hook should ALSO refuse a non-fast-forward (`git merge-base
--is-ancestor <remote_sha> <local_sha>` failing) — which is the `REFUSED` a force push deserves,
and is exercised in the plant.

Two homes, one guard (`wire.py`; **not installed**):

- `.git/hooks/pre-commit` → `... staged` — checks the index against HEAD. **Earliest** stop.
- `.git/hooks/pre-push` → `... push "$@"` — checks each pushed commit and the fast-forward.

**Wiring is deliberately left to the report.** `.git/hooks/` is shared, untracked and per-clone,
so installing a hook changes behaviour for every concurrent unit; `wire.py` prints a dry-run plan
(both hooks are currently **absent**) and writes them only with `--install`. The tracked gate file
lives here because I may not touch `gates/`; promoting it to `gates/git-massdelete-gate.py` (or
wiring the hook) is a one-line move for whoever owns that decision.

## 6. The residual — what a diff-checking guard CANNOT see

**It cannot see a wrong COMMIT MESSAGE, and three of tonight's four bad claims were messages, not
diffs:**

- `00b101574` "landed five units" over **4** files — the file COUNT is in the message, not the diff.
- `oracles259` "deleted" over a **live** file — the message contradicts a diff that was innocent.
- `41%` — a figure that lived **in the orchestrator's prompt and nowhere in the tree**.
- (`ad117c928`'s attribution, the fourth, was also a message.)

A diff-checking guard would have caught **none** of the first three: it reads the change, and the
change was fine. What *would* have caught them is a **message-vs-diff gate** — parse the numbers
and paths the message asserts (file counts, `deleted`, percentages, `path:line`) and resolve each
against `git show --stat` and the tree — which is exactly `checks/citetruth`/`chktcites`'s shape
applied to commit messages. **That guard does not exist yet, and this one cannot stand in for it.**

The other residual: this guard sees **deletions only**. A mass *addition* (a `git add -A` sweep of
6000 files) is invisible here; `no-txt.py` catches one narrow class of that, nothing catches the
rest. And it is a per-commit count — a **sequence** of 499-file deletes across many commits passes,
which is doctrine-1's shape: the population is one commit, not the push.

## 7. Artifacts

- `churn.py`, `churn.rows` — the measured deletion envelope (120 commits); **the threshold's source**
- `git-massdelete-gate.py` — the guard: `check <rev>` / `staged` / `push` / `--plant`
- `run.py`, `plant.out`, `plant.err`, `verdicts.rows` — the plant re-run and the real-tree readings
- `wire.py` — the pre-commit/pre-push wiring (dry-run by default; hooks are currently absent)
- `jj-facts.rows` — the standing conditions: detached HEAD, 650 `export from jj`, live op store
