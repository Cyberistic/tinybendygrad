# tools/ — the tool ledger

Every tool, library and reference checkout this project uses, what it is
pinned to, and why it is here. Nothing in this list is a dependency of the
shipped code; the port has none.

## Compiler

| tool | version | pin | why |
| --- | --- | --- | --- |
| [Bend 2](https://github.com/HigherOrderCO/Bend) | 2.0.34 | `references/bend`, commit `0187512` | the language this project is written in. Fetched by `tools/get-bend.sh`; gitignored, because it is a toolchain, not part of the port. |
| `bin/bend` | — | this repo | two-line shim: `bun references/bend/bend2/main.ts "$@"`. |
| clang | 21 (Apple) | system | Bend compiles to C and calls `clang -std=c11 -O3 -lpthread -lm`. Also what the ported CPU device shells out to, the way `tinygrad` does. Needs clang 14+; 19+ for `!` GPU calls. |
| bun | 1.3.13 | system | runs the Bend compiler, which is TypeScript. Also executes the `-o out.js` lane. |

## Testing

| tool | why |
| --- | --- |
| `./bin/bend FILE` | **the only test mechanism for the Bend code.** A test is a `.bend` file whose trailing `#|` lines are the output its run must print — Bend's own convention, used by `vendor/bend/tests/`. No separate framework. |
| `./bin/bend PROOF.bend` | the laws gate: prints `ALL PROOFS CHECK` or `SOME PROOFS FAIL`. |
| `./bin/bend FILE -o OUT && ./OUT` | the native lane. The interpreted lane is for laws and small programs; anything with real work is compiled. |
| pytest + xdist | **the oracle, not our test suite.** The Python `tinygrad/` tree and its tests are untouched and run unchanged against the Bend build. `python -m pytest test/null/test_dtype.py -x -q -n12`. |
| uv, ty | Python package management and type checking, per the Python rules. The Bend port itself has no Python dependencies. |
| `.venv/bin/python sz.py` | the **differential** for `tinybendygrad/sz.bend`. It needs `tabulate`, which is why the venv exists (see *No dependencies*); the system `python3` has no `tabulate` and cannot run it. |
| `.agents/slop/notes/sz-lexer-proto.py` | a Python model of `sz.bend`'s lexer, `bend_stats(bytes) -> (tokens, lines)`, so one file's counts can be compared with CPython `tokenize` in a loop. The four lexer bugs in `spec/sz.md` were each found here, not by reading the Bend. |
| `.agents/slop/notes/sz-mktrees.py` | builds the two trees the diff-mode differential walks: the edge cases `sz.py` has to survive, then a second that changes, adds and deletes files. |
| `.agents/slop/dm-oracle.py` | the ORACLE for `uop/divandmod.bend`: prints Python's own `div_and_mod_symbolic.rewrite` answer for every fixture, structurally and as a number, with the promotion CASTs erased so it diffs against the Bend rows. Run with `PYTHONPATH=.`. Without it the Bend rows are a restatement of the Bend. |
| `.agents/slop/tools/mutate-dm.py` | applies one edit to `uop/divandmod.bend`, runs the interpreted lane, diffs the rows against `/tmp/dm-base.txt` and RESTORES the file. Prints one line per mutation with the rows that moved. Written because a hand-run mutation table is a guess. **Restores before `continue`, or a mutation that fails to compile leaves the file broken** (it did, once). |
| `.agents/slop/tools/mv.py` | moves one `def`'s whole block to just above another `def` by NAME. `hoist.py` stops on a 3-arg `match` and on locals named `s0`/`s1`, and it does not move a `.put`-style helper into a chain that already sits in the right order; this does, and it is idempotent. |
| `.agents/slop/notes/sz-snips.py` `+` `sz-snips.txt` | 28 f-string and string snippets, each diffed one file against `sz.py`. The nesting-in-a-format-spec corner is here. |
| `.agents/slop/tools/mutate-sz.py` | one edit at a time to `tinybendygrad/sz.bend`, compiled from a scratch copy (**it never edits the source**, so there is nothing to restore), run on four fixtures, and compared with both the unmutated binary and `sz.py`. It answers the question the `sz.py` differential cannot: does *any* output move? A `same` cell is a row the gate cannot see, which is the useful half. The `order` fixture is 15 files ALL TIED at 3 lines and 3.0 tokens/line, so the stable sort on `-lines` prints `os.walk`'s order verbatim and any permutation of it is visible. `--quick` runs one mutation. |

## Reference material

Fetched checkouts live under `references/`, which is gitignored. Neither is a
dependency — the port has none. Both are read-only to every agent; if one appears
to need changing, that is a finding to report, not an edit to make.

> `AGENTS.md` says to link `references/` in the README. Do not. The README is off
> limits. This table is the ledger instead.

| what | where | why |
| --- | --- | --- |
| `tinygrad/` | this repo, tracked, **read-only** | the thing being ported, and the oracle. Never edited by a port agent. |
| `spec/tinyspec.tex` | this repo, tracked | the specification. `tinybendygrad/LAWS.bend` is its machine-checked form. |
| `references/bend` | gitignored, [HigherOrderCO/Bend](https://github.com/HigherOrderCO/Bend) @ `v2.0.34` | the language itself: `guide/GUIDE.md`, `guide/EFFECTS.md`, `guide/SHADERS.md`, `bend2/base.bend` (the prelude), `bend2/effs/*.c` (the effect ABI), `tests/` (the test convention). Fetched by `tools/get-bend.sh`. |
| `references/tinyquery` | gitignored, [Cyberistic/tinyquery](https://github.com/Cyberistic/tinyquery) | Cyberistic's tinygrad-in-Odin. Not a dependency — a second opinion on the same port, so we can see the decisions a different language forced. Its `sz.odin` is the same line-counting tool we are porting to Bend; `slop/notes/sz-odin-precedent.md` records where it diverges from `sz.py` and which divergences we are deliberately not copying. |

The distilled, hard-won facts about all of the above — the affinity rules, the
binder-order rule, the `Maybe`-destructuring rule, the forbidden list-tail descent,
what Bend's `F32` actually does — live in
`.agents/slop/notes/bend2-constraints.md`, which is what agents are told to read
first. Re-derive it there rather than in a comment.

## No dependencies

The shipped Bend code depends on nothing outside `Base` and the C standard
library that clang links by default. No package manager, no vendored library, no
codegen dependency. `tools/` holds scripts we wrote.

**`uv.lock` IS KEPT, and that is not a contradiction.** Decided 2026-09-30. The
constraint binds what the Bend port SHIPS, and the port ships nothing: every
import in `tinybendygrad/` is either `Base` or another `.bend` file in this repo,
which is checkable in one grep and is the thing to keep checking.

`uv.lock` is not part of the port. It is what lets the ORACLE run -- and the
oracle is the whole acceptance mechanism for this project, because a Bend file
that merely compiles proves nothing. `sz.py`, upstream's own line counter, imports
`tabulate`; with no lockfile the differential test that `sz.bend` has to pass
cannot be run at all, which is how it was found. An acceptance test you cannot
execute is not an acceptance test.

So the rule as it now stands, and the reason to word it this way: **nothing is
added to the Bend port, and `uv.lock` exists to run upstream's Python, not to
build ours.** If a future agent finds themselves adding a Python import to
anything under `tinybendygrad/`, that is the violation -- not the lockfile.