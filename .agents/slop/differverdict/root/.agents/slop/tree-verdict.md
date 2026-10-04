# tree-verdict — a tree verdict bucketed by CAUSE

    python3 .agents/slop/tree-verdict.py -P 12          # every .bend under tinybendygrad + examples
    python3 .agents/slop/tree-verdict.py --only sz      # subset
    python3 .agents/slop/tree-verdict.py --json         # machine-readable

`tinybendygrad/**` and `tinygrad/**` are opened read-only. The only writes are to
`.agents/slop/tv-scratch/`. `--root DIR` points the whole tool at a **copy**, which is how the
negative control below is run without ever patching the live tree.

## The problem this exists to solve

`bend --check-only` has a two-word first line that covers four different worlds, and
`--check-only` **exits 1 even on a clean file**. A single RED bucket therefore says
"somebody go fix something" for a declared FFI seam, for a proof that is deliberately
unfinished, for a library with no `main`, and for a genuine compile error. Those four sent a
unit to fix things that were not broken, twice in one day.

## The decision rule, in order

The first line of bend's **diagnostics**, where `diagnostics = check.err + check.out`
(see rule 4 below for why both):

| first line | then | bucket |
|---|---|---|
| `ALL PROOFS CHECK` | rows > 0 | `green` |
| `ALL PROOFS CHECK` | rows == 0 and **no main anywhere in scope** | `no-main` — a library |
| `ALL PROOFS CHECK` | rows == 0 and a main **is** in scope | `no-rows` — a question, not a verdict |
| `SOME PROOFS FAIL` | `defs rely on unsafe or foreign code:` | `foreign-code-surface` |
| `SOME PROOFS FAIL` | `N TODOs found` / `not a valid proof yet` | `proof-in-progress` |
| `SOME PROOFS FAIL` | `expected`/`observed` + `Location:` | `broken-here` |
| `SOME PROOFS FAIL` | …and the offending line is NOT in this file | `broken-in-import` |
| neither | | `no-verdict` — bend died, exit 1 |

`broken-*` is the **residual**: every red matching a declared-failure message is named, and
one matching none is a real defect. That is why the rule reads from the error text and never
from a list of filenames — a hardcoded list would have gone stale the first time a unit's
scope moved, and would have labelled `PROOF.bend` "fine" because someone said so.

**The 0-row split walks the import graph, it does not grep the source.** `codegen/rewriter.bend`
declares no `def main` anywhere, yet a `main` **is** in scope — appending one fails with
`duplicate declaration: main`, because `LAWS/spec.bend`, `uop/ops.bend` and `uop/fold.bend` all
declare one and it imports all three. So it prints 0 rows with a main present, which is not the
same situation as `helpers.bend`, whose closure has no main at all. Calling both "no main, by
design" repeats the conflation this tool exists to stop, one level down.

Two more discriminators worth naming, because they look identical and mean opposite things:

- **`foreign-code-surface` vs a proof failure.** Both print `SOME PROOFS FAIL`. The first
  names the defs: `dtype.bend` *declares* 14 own (`Dt.bf16`, `Dt.fp16`, `Dt.fp8_from`,
  `Dt.i64_trunc`, `float_to_bf16`, …) and 8 files merely *import* them, which shows up as a
  `/` in the name (`../dtype.Dt.bf16`). `sz.bend` declares its own 7 and **one of them is
  `main`**, which is why `sz.bend` prints 0 rows. Not a defect; a declared seam.
- **`proof-in-progress` vs broken.** Decided by the message `not a valid proof yet`, never by
  the filename. The law/PROOF name is printed as corroboration so a reader can see it was not
  what entered the bucket.

## Measured, live tree, 137 files

    green                  109
    no-main                 15     libraries; the verdict is their first line, not a row count
    foreign-code-surface    10     9 propagate dtype's 14; sz.bend declares its own 7
    proof-in-progress        3     LAWS.bend 34 TODOs, PROOF.bend 18, PROOF2.bend 16
    broken-here              0
    broken-in-import         0

**Genuinely broken: 0.** Every red is a declared seam or an unfinished proof.

## The rules this tool had to learn by measurement

1. **Never gate on the exit status.** `--check-only` exits 1 on a clean file.
2. **A 0-row result is indistinguishable from "not started."** bend's machine stack overflows
   on ~1 run in 20 and prints nothing. `one.sh` retries, up to `ONE_ATTEMPTS` (6), before
   anything is classified. 0 rows is *not* itself a retry trigger — a library prints 0 rows
   forever — so the 0-row verdict is split afterwards by a **static** fact the run cannot
   supply: does the source declare `def main`?
3. **A compile error propagates, and `Location:` never names the file.** `PROOF.bend` reported
   an error at line 821 whose text is not `PROOF.bend`'s line 821 — the owner was
   `LAWS/spec.bend`, mid-edit by another unit, **which 76 files import**. The owner is
   therefore found by asking *which file in the tree holds that source text at that line*,
   with `observed : {LAWS/spec.d0 : …}` as an independent corroboration (the prefix names the
   defining module, and is absent exactly when the error is in the file itself).
4. **Which stream the verdict arrives on depends on the verdict.** Success prints to **stdout**,
   failure to **stderr**. Reading `check.err` alone reports every green file as
   `no-verdict`. This is also what makes the row count honest: the error block is on stderr, so
   stdout is rows apart from bend's own two success messages.

## Controls

**Negative control — the `broken` rule really fires, and attribution is exact.** One
unterminated `def planted_control_error(` appended to a **copy** of `LAWS/spec.bend`:

     1 broken-here          tinybendygrad/LAWS/spec.bend:773  def planted_control_error(
    86 broken-in-import     ...all attributed to that one owner
    rc=1

87 red files from one defect. That is why a red *count* is not a defect count.

**No-op control — the output is stable.** Run twice unchanged on the live tree and diffed;
see `tree-verdict-control.txt`.

This control found a real bug in my own attribution: the planted error marks a **blank** line
(a caret points past the `def`), an empty string matches every file with a blank line at that
number, and the first version named **seven false owners**. Fixed by walking back to the
nearest non-empty gutter line, and by reporting "owner NOT identifiable" instead of guessing
when there is none.

The control's *first* run also found something in bend, not in the tool: two sweeps 16 minutes
apart with nothing edited disagreed on **1 of 137** files — `runtime/support/elf.bend` at 353
rows vs 331. `stat` puts its mtime at 14:59:55, before both runs. **bend emitted a truncated
row set with no stderr, no overflow message and exit 0.** I then ran it **39 more times** (15
idle back-to-back, 24 under sweep load) and got **353 every time** — so I am reporting one
observation, not a rate, and could not make it happen on demand. A single run is therefore not
evidence for a row count, so `one.sh` now reports the **modal** count over repeated runs plus
how many **distinct** counts it saw, never lets 0 be the agreement, and records void
(overflowed) attempts separately so a partial total cannot win the mode.

## Two hazards worth flagging to the coordinator

- **Two units were given the same two filenames.** `one.sh` and `tree-verdict.py` were created
  at 14:39, deleted at 14:58, and `one.sh` was recreated at 14:59 by another unit **in a
  version lacking the `$BEND_ROOT` switch** the negative control needs. Nothing errored: it
  reported `ALL PROOFS CHECK` for a deliberately broken file, because it silently read the
  live tree instead of the copy. A benign fallback path, not a crash, is how a harness lies.
  The file on disk now also carries another unit's `proof_set_verdict` pass (it judges a
  `PROOF`/`LAWS` member by the SET verdict, found by structure — the file importing the most
  other bend files — rather than by a hardcoded name). **That branch is currently inert**:
  `_SET` is left as `[None, None, None]` and never populated, so today it changes no verdict.
- **The tree verdict is a moving target.** `LAWS/spec.bend` broke at 14:35 and was repaired by
  its owner within the session; `PROOF.bend` went 20 TODOs → a syntax error at :821 → 18 TODOs;
  and the file count moved 137 → 136 → 137 during the session. **Re-run the tool; do not
  remember its verdict.** At least 9 of the files are mutation scratch or probes that a naive
  `find` counts, which is the likeliest reason a brief says 128 where the tool says 137.
