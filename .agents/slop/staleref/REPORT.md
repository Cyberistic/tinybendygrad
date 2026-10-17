# STALE-CITATION CENSUS — REMOTE-TRACKING REFS READ AS IF THEY WERE THE REMOTE

**HEAD at census: `62032e2aa6e352dc03c065716749c6c8f663e6f4` (detached).**
**HEAD observed twice during the census: `c0795853ae9bc75b4442db43eb6cf035ddddf4a6`
(05:11:20Z), then `030a34fe19fddb9a1e166294460ef92836621ee2` (05:17Z).**
**Report written `2026-10-17T05:18Z`. Read-only: nothing outside `.agents/slop/staleref/` was
touched, and no git command that writes was run.** (One `git status --porcelain=v2` for
orientation; it can refresh the index's stat cache but changes no content, and it ran with
`GIT_INDEX_FILE` scrubbed.)

**HEAD MOVED TWICE DURING THIS CENSUS** (`c0795853` → `030a34fe` → `62032e2a`), which is the
hazard this report is about, happening to the census itself. The site set was re-derived and
**diffed at each move: IDENTICAL, 103 of 103, both times.** The denominator below is therefore a
property of the class, not of a lucky commit.

---

## 1. THE FINDING, IN ONE LINE

**Of 103 sites in the tracked tree that read a remote-tracking ref, exactly ONE obtains the
remote's state from git rather than from the ref cache — and it is a GitHub Action, not an
instrument. Zero of the tree's three executable ref-reading instruments fetch by default, and
`git ls-remote` appears in exactly one tracked file, in prose, explaining why the wrong command
is wrong.**

## 2. POPULATION AND DENOMINATORS

Discovered, not listed: `git grep` over the blobs of `git ls-tree -r HEAD` (**7,501 tracked
paths**). Two shapes are unioned, because either alone misses members (see §6).

| verdict | count | share | meaning |
|---|---|---|---|
| **SELF-REFRESHING** | **1** | **1.0%** | a fetch reaches the read, so the ref is fresh when used |
| **STALE-CITATION** | **35** | **34.0%** | names a remote ref, does not fetch, and puts that ref's value/count — or a cached-ref read labelled "upstream" — into a claim about the remote |
| SOUND | 29 | 28.2% | a local-only question, a monotone-safe claim, or the documented correction |
| MENTION | 38 | 36.9% | names a command or records a past event; asserts no live remote state |
| **TOTAL** | **103** | **100.0%** | |

The two columns `fetches_first` and `claims_remote_fact` in `sites.rows` are **mechanical**;
`verdict` is **semantic**, hand-assigned after reading all 103 lines and tabulated in
`staleref.py` so the judgement is reviewable. **They disagree on purpose, and the disagreement
is the interesting part**: `UPSTREAM-PIN.md:151`, `upstream-delta.py:48` and
`rebase-gate.py:577` carry `claims_remote_fact=no` because the *line* holds no value and no
copula — the claim lives in what the code *does*, not in what the line *says*.

`MENTION` exists so the headline number cannot be inflated. `.agents/slop/strays/origin/**` is
a **directory** named `origin`, and the tree's own cites census already rules those "a mention
is not a claim"; they are excluded, and so are `origin` the HTTP header
(`cdp.mjs:37`) and `original` the adjective (`plans/REPORT.md:17`).

## 3. WHICH INSTRUMENTS FETCH FIRST — the (a)/(b) split

| site | fetches first? | reports a REMOTE fact? | verdict |
|---|---|---|---|
| `.github/actions/process-replay/action.yml:15` | **YES** — `git fetch origin master && … checkout origin/master`, one `&&` chain | yes, and it is fresh | **SELF-REFRESHING** |
| `gates/git-massdelete-gate.py` `mode_push` | n/a — it never reads a ref at all | yes, and it is fresh | **SOUND** |
| `.agents/slop/upstream-delta.py:48,196,210` | **NO** — `--fetch` is opt-in, off by default | yes | **STALE-CITATION** |
| `.agents/slop/rebase-gate.py:577` (+ its probe copy) | **NO** — no fetch anywhere in the file | yes | **STALE-CITATION** |
| `.agents/slop/duptree/control.py:27,35,36` | **NO** | no — it asks "ancestor of *my last fetch*" | **SOUND** |

**`gates/git-massdelete-gate.py` `mode_push` is the template, and it gets there without
fetching.** It takes the remote sha from git's own **pre-push stdin**
(`<local_ref> <local_sha> <remote_ref> <remote_sha>`), which git fills from the remote's ref
advertisement during push negotiation. That is a live remote reading, structurally, with no
ref cache anywhere in it. The other three instruments could take the same route.

**`duptree/control.py` is SOUND only because of a fact it does not check.** It reads
`origin/master` with no fetch, and that is sound *because this tree REFUSES non-fast-forward
pushes* (`gates/git-massdelete-gate.py:160`) — so a cached remote-tracking ref's history is a
**prefix** of the real remote's, and "is `c` an ancestor of my last fetch?" implies "origin
accepted `c`". One un-refused force-push and the prefix property, and with it that control's
negative lane, stops holding.

## 4. THE STALE-CITATION MEMBERS (35), with what each claims

### Tier 1 — hard-codes a ref's VALUE or a COUNT. These decay invisibly.

| site | the claim |
|---|---|
| **`.agents/UPSTREAM-PIN.md:22`** | `| **UPSTREAM HEAD** | `91b8cb5fa6c0` | 2026-10-02 | 59 commits ahead |` |
| `.agents/slop/state-audit-report.md:308` | `UPSTREAM 91b8cb5fa6c0 2026-10-02 BEHIND 59 commits, 124 files, 51 under tinygrad/` |
| **`.agents/slop/duptree/REPORT.md:36`** | `| ON ORIGIN | **no** — git merge-base --is-ancestor 591f6b499 origin/master **rc=1**; origin/master is `52d77134b` |` |
| `.agents/UPSTREAM-PIN.md:447` | `equals upstream HEAD   189` |
| `.agents/slop/pin-tree-oracle-report.md:15` | `tinygrad/` vs `upstream/master` (`91b8cb5fa6c0`): **215 same, 14 differ** |
| `.agents/slop/pin-tree-oracle-report.md:14` | vendor `tinygrad/` equals **`origin/master`'s** `tinygrad/` **230/230, 0 differ** |
| `.agents/slop/pin-tree-oracle-report.md:93,272` | 27 oracles import "the working vendor, which is `origin/master`" |
| `.agents/TODO.md:4597` | the dtype answer at `upstream/master` **`91b8cb5fa6`** |
| `.agents/TODO.md:3844` | `uop/ops.py` **is at upstream HEAD** while `uop/render.py` is at the pin |
| `.agents/UPSTREAM-PIN.md:452,487,559,571,585,406` | negative/positive claims over the ref's contents and diffs |

### Tier 2 — executable: reads the cached ref and reports it as the remote's state

| site | the claim |
|---|---|
| **`.agents/slop/upstream-delta.py:48`** | `UPSTREAM = "upstream/master"` |
| `.agents/slop/upstream-delta.py:196` | emits a JSON field **literally named `upstream_head`** |
| `.agents/slop/upstream-delta.py:210` | prints `UPSTREAM {head} BEHIND {n} commits, {n} files` |
| `.agents/slop/rebase-gate.py:577` | `git diff --stat pin upstream/master`, and on empty output says **`(upstream has no diff for …)`** |
| `.agents/slop/denominator/probe/.agents/slop/rebase-gate.py:577` | a vendored copy of the same line |

### Tier 3 — recipes that build a tree from the cache while labelling it upstream

`.agents/UPSTREAM-PIN.md:151,313,321` · `.agents/slop/notes/bend2-constraints.md:8948,8958` ·
`tinybendygrad/uop/render.bend:178` · `.agents/slop/argowner/mine/render.bend:178` ·
`.agents/TOOLS.md:546` · `.agents/TODO.md:3848`

### Tier 4 — mislabelled local facts, the subtlest form

`.agents/TODO.md:4020` and `.agents/slop/notes/bend2-constraints.md:11737` both read:

> `upstream/master` (`git diff 6c3d401cf324 HEAD -- tinygrad/` is 20 files)

The command diffs **pin..HEAD**. It never touches `upstream/master`. The number is a perfectly
good **local** measurement of our own vendored tree; the label on it is a remote claim. A reader
re-deriving the citation would run the sentence and get a different question than the number
answers.

## 5. THE DECAY, MEASURED

**`UPSTREAM-PIN.md:22` is wrong by 212 commits and is wrong about a number the tree verifies
elsewhere.**

```
$ git rev-list --count 6c3d401cf324..91b8cb5fa6c0     # what :22 says is "59 commits ahead"
59
$ git rev-list --count 6c3d401cf260..upstream/master  # measured 2026-10-17T05:12Z
271
$ git rev-list --count 91b8cb5fa6c0..upstream/master # the drift since :22 was written
212
```

The `59` is **internally correct** — it really was 59 when taken. What rotted is the **label
`UPSTREAM HEAD`**. `91b8cb5fa6c0` is dated 2026-10-02; the cached `upstream/master` is
`002630241`, dated **2026-10-16**. So the document under-reports our distance from upstream by
**212 commits, a 4.6× understatement**, and it under-reports it while looking *current*.

**`duptree/REPORT.md:36` is self-refuting from inside the tree, with no network needed.**
`.agents/TODO.md:464` records, at `2026-10-17T03:54Z`:

> `git rev-parse origin/master` still said `52d77134b` while `git ls-remote` said `473d7ce98`

`duptree/REPORT.md:36` asserts **`origin/master` is `52d77134b`** — i.e. it publishes the
**cached** value under the remote's name. Measured now: `52d77134b` is a real ancestor of
`origin/master`, `473d7ce98` is the live value (`ls-remote origin master` =
`473d7ce988d0f0741e26bccf5e8c1495d864be4c`, 05:12:34Z), and **cache and remote currently
agree** — which is exactly why the defect is invisible today.

The **conclusion** at `:36` is nevertheless correct: `591f6b499` is still not an ancestor of
`origin/master` (rc=1, re-measured). A stale citation reached a true verdict.

## 6. WHAT IT WOULD TAKE TO MAKE THESE RE-DERIVABLE

The cheap, uniform fix is **to stop quoting the ref's value and quote a SHA instead** — which
this tree already does correctly in nine places (§7). A commit cannot move.

1. **Quote the SHA, not the ref's value.** `:22` becomes `upstream head at 2026-10-02 was
   91b8cb5fa6c0` — which is *true forever* — instead of `**UPSTREAM HEAD** | 91b8cb5fa6c0 |`.
   Same edit for `state-audit-report.md:308`, `pin-tree-oracle-report.md:14,15`,
   `TODO.md:4597`, `UPSTREAM-PIN.md:447`.
2. **Where a HEAD claim is the point, derive it.** `git ls-remote upstream master` is the
   question; `rev-parse upstream/master` is not. `:22`, `:447` and `upstream-delta.py:196,210`
   should take it from an `ls-remote`, or drop the word *HEAD* and name the sha they used.
3. **Make the fetch default, not a flag.** `upstream-delta.py` already has `--fetch`;
   `rebase-gate.py` has no fetch at all and its failure mode is a *false clean* ("upstream has
   no diff for X"). A fetch-before-read in `main()` is one line each.
4. **Fix the mislabelled local facts first — they are the cheapest and they are wrong twice.**
   `TODO.md:4020` and `bend2-constraints.md:11737`: either drop the words `upstream/master`, or
   change the command to `git diff <pin> upstream/master` so the number answers the label.
5. **Give recipes a fetch.** Every `git checkout upstream/master -- …` and
   `git archive upstream/master` recipe (`UPSTREAM-PIN.md:151,313,321`,
   `bend2-constraints.md:8958`) should read `git fetch upstream && …`, or state "as of the last
   fetch" so the reader can see the decay. Note `UPSTREAM-PIN.md:11` **already** documents the
   self-refreshing form (`upstream-delta.py --fetch`) and `:17` **already** warns the table
   "has been stale twice today" — the document knows; the table does not show it.
6. **Name the field for what it is.** `upstream-delta.py:196`'s `upstream_head` is a cache
   reading. `fetched_upstream_head` plus a `fetched_at` would make the two distinguishable in
   the row itself.

## 7. WHAT THE TREE ALREADY GETS RIGHT (the template, and the contrast)

**Eleven sites across nine files pin an immutable SHA and are therefore SOUND**, all verified
here (`git cat-file -t commit`, all ancestors of `upstream/master`, and `002630241` confirmed
equal to `ls-remote upstream master` at 05:12Z):

`gates/js-lane-census.py:90` · `gates/onnx_census-gate.py:78` ·
`gates/rand_census-gate.py:144` · `gates/state_census-gate.py:109` ·
`tinybendygrad/device.bend:56,1006` · `tinybendygrad/runtime/ops_metal.bend:2855` ·
`tinybendygrad/runtime/support/hcq2.bend:55,173` · `.agents/UPSTREAM-PIN.md:552` ·
`.agents/UPSTREAM.md:376`

Each says *"upstream `<sha>`"* or *"at UPSTREAM HEAD `<sha>`"* — the same words as the broken
sites, but attached to a **sha rather than a ref's value**, and dated. That is the whole
difference, and it is why four `gates/` members survive this census and `.agents/UPSTREAM-PIN.md:22`
does not.

Two more sites are the *antidote* and are SOUND for it:
`.agents/TODO.md:464-465` — the one place in the tree that pairs `rev-parse origin/master` with
`ls-remote` and concludes the former is not a remote measurement — and
`.agents/slop/prune4/REPORT.md:345`, which records having assumed `origin/master` when the
answer was HEAD's ancestry.

## 8. THE CONTROL — PASS (3 of 3), and the negative control is the one that matters

```
POSITIVE  .agents/UPSTREAM-PIN.md:22        -> STALE-CITATION   PASS
POSITIVE  .agents/slop/duptree/REPORT.md:36 -> STALE-CITATION   PASS
NEGATIVE  .github/.../process-replay/action.yml:15 -> SELF-REFRESHING  PASS
GAPS      0 unclassified
```

Both positives are **pointable and independently checkable**, which is the requirement:
`UPSTREAM-PIN.md:22` is falsified by a two-command measurement (§5), and `duptree/REPORT.md:36`
is falsified by `TODO.md:464` with no network at all.

The negative control is the one that earns the report. The classifier had every opportunity to
flag `.github/actions/process-replay/action.yml:15` — it contains the exact string
`origin/master`, and a naive "does it read a remote-tracking ref" test fires on it — and it did
not, because `git fetch origin master` is in the same `&&` chain. **A classifier that cannot
leave that site alone has not learned the distinction; it has only learned the string.**

**`GAPS 0`** is also a control: `classify()` emits `UNCLASSIFIED` for any discovered site not in
the three hand-assigned tables, and `main()` **exits non-zero if that number is not 0**. It
reached 18 mid-work and is 0 now.

## 9. THREE BLIND SPOTS THIS CENSUS MEASURED IN ITSELF

Reported because a census whose instrument is not itself audited is a list with extra steps.

1. **A remembered SHAPE hid the worst member.** The first pattern was anchored on
   `<remote>/<ref>`. It found **70** sites and could not see `.agents/UPSTREAM-PIN.md:22`,
   because that line says **`UPSTREAM HEAD`** under a **bare SHA** and contains the string
   `upstream/master` **nowhere**. The strongest member in the tree was invisible to a regex
   shaped like the thing it was looking for. A second, label-anchored shape was added; it
   contributed 33 of the 103. **The two shapes' denominators are 70 and 33 and the union's is
   103 — the union is not either one's.**
2. **`\b` does not exist in this git's `grep -E`.** Measured: `git grep -E '\bout\b'` returns
   **0** on a tree where `out` occurs. Every `\b` silently matched nothing, which cost the
   entire second shape until it was found. A shorthand that *quietly* returns empty is worse
   than one that errors.
3. **`origin` ⊂ `original`.** With a word boundary spelled as the bare word, the patterns matched
   `origin` inside `original` — **5 false positives**, two of them in **vendored
   `tinygrad/uop/ops.py`**, which is not our instrument and never was. The boundary is now
   `[^A-Za-z]`.

## 10. WHAT THIS CENSUS DOES **NOT** COVER — stated, not implied

- **Ahead/behind parsing: nothing to census.** `git status -sb` and `--short --branch`:
  **0 tracked files**. `@{u}` / `@{upstream}`: **0**. `git remote show` and
  `for-each-ref refs/remotes`: **0**. Those three of the brief's named vectors are **absent from
  this tree**, which is a result, not a gap.
- **`.txt` and row-dump surfaces are excluded**, not classified. A `.rows`/`.json` file
  capturing an instrument's output (e.g. `.agents/slop/agend/ruff.rows:8553`, which mirrors
  `upstream-delta.py:196`'s own `upstream_head`) is filed MENTION. There may be more such
  captures; I counted the ones the patterns reach and stopped.
- **`rebase-gate.py`'s output is read from its source, never run** (per the brief's
  read/parse-only rule), so the STALE verdict on `:577` rests on the code's text: no `fetch`, no
  `ls-remote`, both verified by `grep` over the whole file.
- **`git ls-remote` was run against both remotes**, read-only, and is the only network call
  made. Every other statement here is offline-reproducible.
- **The two remotes are not equally exposed.** Of the 35 STALE-CITATION members, **29 name
  `upstream` (tinygrad) and 6 name `origin`**. `origin` is this fork and moves rarely;
  `upstream/master` moves daily, and that is where the decay is measured.

## FILES

- `sites.rows` — 103 rows, TAB-separated: `site · fetches_first · claims_remote_fact ·
  verdict · evidence`
- `staleref.py` — the census. Discovery is `git grep` over `git ls-tree -r HEAD`; the semantic
  verdicts are three hand-assigned tables in the source, so each judgement is reviewable and
  editable. Re-run: `.venv/bin/python .agents/slop/staleref/staleref.py` (exit 0 only when the
  control passes **and** unclassified is 0).