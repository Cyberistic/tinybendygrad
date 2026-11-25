# checklist

The recovery plan. Ordered by leverage per hour. **Every row carries the command that
re-measures it** — this file holds no verdicts, because a verdict here is a bet the tree
has not moved.

Baseline measured 2026-11-25 (re-run the commands to move it):

| reading | value | command |
|---|---|---|
| in-scope upstream Python | 27,261 lines | `git ls-tree -r HEAD --name-only tinygrad` |
| port | 173,028 lines, 199 files | `find tinybendygrad -name '*.bend'` |
| verification | 262,591 lines in `gates/ checks/ oracles/` | same walk |
| corpus graphs | 38 | `head -1 runs/graphcmp/D/D0-run-summary.txt` |
| corpus verdict | 37 agree, 1 disagree (`grad`) | `cat runs/graphcmp/D/D1-verdicts.txt` |
| certificate | `claim=NOT-ESTABLISHED` | `.venv/bin/python gates/corpuswitness-gate.py` |
| reachable gates | 20 of 321, all off one workflow | `gates/reachability-gate.py` |

---

## Phase 0 — the tree must be certifiable

- [x] **0.1 Quarantine the substrate draft.** `tinybendygrad/uop/ops.bend.new` (567 KB,
      Nov 11) was an untracked draft inside the walk, so it moved the substrate digest.
      Moved to `.agents/slop/quarantine/`, not deleted.
- [x] **0.2 Commit the 33 real content changes.** Two path-scoped commits (substrate+shaders+
      checks, then `.agents/`). `git commit --only -m … -- <paths>`.
- [x] **0.3 Clear the phantom "23,476 modified".** `git diff --name-only | wc -l` is the
      truth; `git status` was stat-only noise. `git update-index --refresh`.
- [x] **0.4 Stop scratch polluting `git status`.** 32,877 untracked, non-ignored files, all
      `.agents/slop/` scratch. Excluded locally via `.git/info/exclude`.
      *Pass:* `git ls-files --others --exclude-standard | wc -l` ≈ 0.
- [x] **0.5 Compact `.agents/TODO.md`.** 30,951 lines → a board. Archive the original
      verbatim at `.agents/slop/todo-archive-20261125.md`.
      *Pass:* every one of the 160 categories is present; 52 open ones keep their detail.

## Phase 1 — wire the truth (30 min, cheapest win in the tree)

- [ ] **1.1 Track a pre-commit hook.** `gates/hooks/pre-commit` runs the 2.2 s witness gate
      and refuses **only** commits touching a file that carries a verdict (`AGENTS.md`,
      `.agents/TODO.md`, `README.md`) when `claim=NOT-ESTABLISHED`. Code commits pass.
      *Pass:* a `AGENTS.md` commit while stale exits non-zero and prints the four red rows.
      *Why selective:* you may move the tree, you may not claim a green tree.
- [ ] **1.2 `git config core.hooksPath gates/hooks`.** Record it in `.agents/TOOLS.md`.
      *Pass:* `git config --get core.hooksPath` answers.
- [ ] **1.3 Strip every run verdict from `AGENTS.md`.** Replace each quoted run with the
      command and the token it must print.
      *Pass:* `grep -c 'graphs-agree' AGENTS.md` → `0`.

## Phase 2 — the one red row

- [ ] **2.1 Re-run the corpus.** `checks/differ.py run` (~271 s). The recorded run predates
      two `mixin/gradient.bend` commits (03:10, 04:09 +0300 today).
- [ ] **2.2 Fix or revert `grad`.** Measured delta: py 9 rows / bend 6; `BUFFER 2/0`,
      `MUL 2/1`; the surviving `MUL` is `dtype=void` where CPython has `f32`. The port's
      backward of a scalar product builds one `MUL` where CPython builds two.
      *Pass:* `D1-verdicts.txt` empty, `expect-moved=0`.

## Phase 3 — retire gates that cannot go red (2 days)

- [ ] **3.1 Plant each gate.** 586 files, 210,209 lines, median 211. Apply `differ.py`'s own
      method: mutate the input, require the verdict token to move.
      *Pass:* a `LIVE` / `LABEL` row exists for all 423 `.py` gates.
- [ ] **3.2 Delete the labels.** Not archive — an archived gate gets cited.
      *Estimate:* ~30 survivors.

## Phase 4 — generate the tables (1 week, ~14k lines)

- [ ] **4.1** `uop/symbolic.bend` 6,129 · `uop/fold.bend` 4,790 ·
      `codegen/decomp/dtype.bend` 2,934 are rule tables. Emit them from upstream's own
      pattern lists, the way `gates/ptx_render_census-gen.py` emits its driver.
      *Why:* removes the class `gral` found — a hand-copied rule with one swapped operand,
      invisible to node counts.

## Phase 5 — make upstream's tests the population (2 weeks)

- [ ] **5.1** 376 test files will never become 38 hand-built graphs by hand. Take the pure-UOp
      subset of `test/`, run it against the Bend build, compare semantically.
      *This is doctrine 1 applied to tests: a generated population, not a curated one.*

## Phase 6 — attack the loop (1 week)

- [ ] **6.1 Typecheck cache.** 2.6 s per file, no cache, 21k-line closure; `sz.bend` will not
      compile under 2 GB. `bin/bend` shims onto `references/bend/bend2/main.ts`, which this
      repo owns. Cache the typed closure by content hash.

---

## Do not

- Re-vendor upstream again (`ad117c928` cost a day, and the plan it came from has no script left).
- Add a census gate.
- Write a report about a report.
- Trust `git status` as a source of truth on this clone.
- `git add -A`, `git add <dir>`, amend, or rebase.
