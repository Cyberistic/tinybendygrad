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