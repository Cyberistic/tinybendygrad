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
- [x] **0.3 There was no phantom index (corrected).** My first reading called `git status`'s
      23,476 lines "modified tracked files". They were **untracked**: `git status | cut -c1-2`
      counted 23,446 `??` and 0 modifications. No `--refresh` was needed; the claim was wrong,
      and it is recorded here rather than quietly dropped.
- [x] **0.4 Stop scratch polluting `git status`.** 32,877 untracked, non-ignored files, all
      `.agents/slop/` scratch. Excluded locally via `.git/info/exclude`.
      *Pass:* `git ls-files --others --exclude-standard | wc -l` ≈ 0.
- [x] **0.5 Compact `.agents/TODO.md`.** 30,951 lines → a board. Archive the original
      verbatim at `.agents/slop/todo-archive-20261125.md`.
      *Pass:* every one of the 160 categories is present; 52 open ones keep their detail.

## Phase 1 — wire the truth (30 min, cheapest win in the tree)

- [x] **1.1 Track a pre-commit hook.** `gates/hooks/pre-commit` runs the 2.2 s witness gate
      when a staged line carries the certificate's vocabulary (`graphs-agree=`,
      `byte-identical=`, `claim=ESTABLISHED`, …). It gates the **claim**, not the file — a
      checkbox edit passes, a figure does not.
      *Pass:* verified both ways 2026-11-25 — board commit rc=0, recorded figure rc=1 with the
      four red readings printed. *Why selective:* you may move the tree, you may not claim a
      green tree.
- [x] **1.2 `git config core.hooksPath gates/hooks`.** Record it in `.agents/TOOLS.md`.
      *Pass:* `git config --get core.hooksPath` answers.
- [x] **1.3 Strip every run verdict from `AGENTS.md`.** Replace each quoted run with the
      command and the token it must print.
      *Pass:* `grep -c 'graphs-agree' AGENTS.md` → `0`. Done 2026-11-25: 987 → 374 lines, all
      40 rules kept, original verbatim at `.agents/slop/agend/AGENTS-20261125-987line.md`.

## Phase 2 — the one red row

- [x] **2.1 Re-run the corpus.** 38/38 agree, 0 disagree, 0 refused, byte-identical 38,
      plants 8/8, conflations 4/4, controls 5/5, stability 5/5, both selfchecks OK. The run is
      **self-consistent** (`substrate-start == substrate-end`) and records
      `substrate-head=2cb2437c2`.
      **Still not a certificate**: `uop/fold.bend` and `schedule/rangify.bend` were dirty
      (another unit) while it ran, so the digest describes a working tree rather than that
      commit. A `repro` on a quiet tree is what turns this into one.
- [x] **2.2 Fix `grad`.** Root cause was not the walk: `gmul_bc` passed
      `gs_solid(gbcast(...))` to `gmul` as an operand, and `gs_solid` is the **count of
      non-holes**, not a node. On this fixture the count is `1`, which is arena node 1 — the
      `STACK` a `BUFFER` keeps its shape in — so the port built `MUL(STACK, ctx)` where
      CPython builds `MUL(BUFFER, ctx)`, and both directions interned onto one node.
      Same lines also dropped the arena `gbcast` grew. Fixed in `99efae865`.
      *Pass:* `--graph grad` → 9 rows, 9 shared cores, 0 field mismatches, 7/7 ops, `AGREE`;
      `gates/gr_graph_census-gate.py` → 32 rows, no divergences.
      *Blast radius:* `gmul_bc` is reached only by the autodiff rules, exercised only by the
      `grad` and `gral` graphs — both verified.

## Phase 3 — retire gates that cannot go red (2 days)

- [ ] **3.1 Plant each gate.** 586 files, 210,209 lines, median 211. Apply `differ.py`'s own
      method: mutate the input, require the verdict token to move.
      *Pass:* a `LIVE` / `LABEL` row exists for all 423 `.py` gates.
- [ ] **3.2 Delete the labels.** Not archive — an archived gate gets cited.
      *Estimate:* ~30 survivors.

## Phase 4 — generate the tables (1 week, ~14k lines)

- [x] **4.1 `uop/symbolic.bend` — the table is now a projection, not a transcription.**
      `gates/symbolic-table-gate.py` derives `(ops, rej)` per row from `sym.patterns` and
      compares. It found **three rows whose `rej` was wrong**, and the bodies are what proved
      it: `tag 2` demanded `CONST` while `sym_84.pat` reads a WHERE at src 0, so the rule could
      never fire; `tag 12/13` demanded `CONST` while upstream tests `INDEX.or_casted()`, which
      a disjunction cannot put in `early_reject`. Fixed in `bd4be1206`.
      *Pass:* gate reports `sym_table 131/131 · rm_table 2/2 · valid_table 2/2`, 0 hazards,
      1 documented 6-row permutation, and 77 rows that drop a fast path (counted, not failed —
      `rej` is a filter, so narrower costs time and not an answer).
      *Still to do:* `uop/fold.bend` — it has no `PMEntry` at all, so its table has a different
      shape and the same treatment is a separate job.

      **4.1b `codegen/decomp/dtype.bend` — a different answer, and the difference is the finding.**
      Its rule table is **not** projectable: `l2i_pair` (`dtype.py:89`) wraps a rule as
      `BITCAST(STACK(x))`, so 4 of `pm_long_decomp`'s 10 patterns *claim* `BITCAST` while the
      port's rows claim the inner op, and the float rows are reordered with one merged
      catch-all. A projection would report six rules as missing that are merely shaped
      differently. What *is* directly comparable is the **op groups**, and two were wrong:
      `dd_ops.all()` was 75 of `GroupOp.All`'s 76 (no `REFPARAM`), and the `GroupOp.Defines`
      row spelled 3 of 5 (no `BINARY`, no `REFPARAM`). Fixed in `089670d84`.
      *Pass:* `gates/dtype-table-gate.py` — `all 76/76 · Comparison 3/3 · Defines 5/5`, and it
      prints the rule table as `NOT-PROJECTABLE` with the wrapper count, rather than deciding
      something it cannot see.
      *Shared:* `gates/pmtable.py` holds the parser and both pairing modes; `symbolic-table-gate.py`
      was re-derived on top of it with unchanged output.

      **The behaviour is validated, and this is what validated it:** the three rows went from
      dead/filtered to live in `bd4be1206`, and the full corpus run after it is green — 38/38
      agree, byte-identical 38, plants 8/8 — so making them fire rewrote nothing CPython does
      not also rewrite. That is the difference between "the gate says the table matches" and
      "the rules do what the table claims".

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
