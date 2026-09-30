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

| what | where | why |
| --- | --- | --- |
| `tinygrad/` | this repo, tracked, **read-only** | the thing being ported, and the oracle. Never edited by a port agent. |
| `spec/tinyspec.tex` | this repo, tracked | the specification. `bendgrad/LAWS.bend` is its machine-checked form. |
| `references/bend` | gitignored | the language itself: `guide/GUIDE.md`, `guide/EFFECTS.md`, `guide/SHADERS.md`, `bend2/base.bend` (the prelude), `bend2/effs/*.c` (the effect ABI), `tests/` (the test convention). |

The distilled, hard-won facts about all of the above — the affinity rules, the
binder-order rule, the `Maybe`-destructuring rule, what Bend's `F32` actually
does — live in `.agents/slop/notes/bend2-constraints.md`, which is what agents
are told to read first. Re-derive it there rather than in a comment.

## No dependencies

The shipped Bend code depends on nothing outside `Base` and the C standard
library that clang links by default. No package manager, no vendored library, no
codegen dependency. `tools/` holds scripts we wrote.