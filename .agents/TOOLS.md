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
| `.agents/slop/tx-arena.py` | the ORACLE for `codegen/transcendental.bend`: walks the tinygrad UOp graph every expansion builds and prints one STRING row per node — `a_<tag>=<slot>,<OP>,<arg or dtype>,<src slots>` — plus a `n_<tag>` COUNT row per expansion. Redirect to `.agents/slop/tx-arena.txt`; that file is the diff target and is checked in so the gate does not need Python to run. **It erases three things the real tinygrad does not**: promotion CASTs, `UOp.const`'s own fold, and the fact that a CONST's key is its VALUE and not `repr(arg)` (so `UOp.const(x)` and `UOp.const(x, float32)` are two Python nodes and one Bend node). Every erasure is a decision, so each one is a comment in the file. |
| `.agents/slop/tools/tx-mut.py` | 13 mutations of `codegen/transcendental.bend`, one hand edit at a time, each re-checked and each row-set diffed against `.agents/slop/tx-arena.txt`. `--one <name>` runs one. Two details worth keeping: it keys rows on `<tag>#<slot>`, because a positional diff reports every row after an insertion as moved (noise) while a `<tag>`-only key collapses all 205 `a_xsin` rows into one; and it records the moved rows even when the mutated file FAILS to run, as `<gate did not run>`, so a compile-time catch is never silently dropped. The file is asserted to contain each `old` exactly once — a stale edit target is an error, not a no-op. |
| `.agents/slop/mixin-op-gate.py` | the ORACLE for `mixin/op.bend`: prints one `name=<count> OP/<nsrc> ...` row per claim, in the same ORDER and the same format the `.bend` `main` prints, from a live `tinygrad`'s own `t.uop.toposort()`. **Nothing is executed** — every row is the SIGNATURE of the lazy graph, so no device is needed. Every fixture is DERIVED from CPython rather than restated from the port, which is the only reason the comparison means anything. The four BEND-ONLY rows (`rop_gap`, `exp_cast`, `commit_weak`, `bin_promote`) name a refusal or a defect rather than a graph Python can be asked for, so the script prints none of them and the runner filters them BY NAME, never by position. |
| `.agents/slop/mixin-op-gate.sh` | runs all THREE lanes — CPython, `./bin/bend` interpreted, and `./bin/bend -o` native — and diffs them byte for byte. Exits non-zero on any divergence. The native lane is what catches a `law` that is unfilled in the interpreter and live in the compiled binary, which is a real failure mode here (`F32.mul(1.0e30, 1.0e30)` printed `inf` in both, while `tensor.bend`'s header claimed otherwise). |
| `.agents/slop/mixin-op-mutate.py` | 17 one-token mutations of `mixin/op.bend`. Each is applied, **BOTH Bend lanes are run and required to agree**, the rows are diffed against the unmutated output, and the edit is reverted. Restores from a **byte snapshot** on every exit path including SIGINT/SIGTERM, and exits 1 if the file is left dirty — the earlier hand-run version left a DETACH mutation applied to the source and the stale result was nearly recorded as a measurement. Asserts each search string occurs exactly once, so a stale edit target is an error rather than a silent no-op. **A mutation that moves nothing is a row the gate cannot see, and it is printed rather than dropped**: 4 of 17 are zero, three with a reason (two negatives for a float32 fixture, one that is unfalsifiable by ANY graph oracle because `m - ss.log()` and `e - ss.log()` are graph-isomorphic) and one whitespace CONTROL. One of the 13 that DID move was zero until the row meant to test it turned out not to run — so the table changed a gate row, which is the whole reason to keep one. |
| `.agents/slop/state-gate.py` | the ORACLE for `nn/state.bend`: prints one row per claim, from a live tinygrad's own `get_state_dict` / `get_parameters` / `safe_dtypes` / `TensorIO.seek`. **Nothing is executed on a device** — a `state_dict` key is a function of the object SHAPE alone, so the whole oracle is `str.strip`, `str(i)` and dict insertion order. Its printers match the port's exactly (a trailing `","` join, `hi:lo` for a negative), so a diff is a diff of values and not of formatting — and that mattered: two wrong versions of the `i64` helper, each caught by the diff and each recorded in the script. |
| `.agents/slop/nn-init-gate.py` | the ORACLE for `nn/__init__.bend`: one row per claim from a live tinygrad's own `.shape`, `.padding`, `.axis`, `get_state_dict(...).keys()` and `.is_param`. Every row is a GRAPH FACT in tinygrad and a plain Python value here, so the comparison needs no GPU. The three float rows print the **f32 image of the Python double** (`struct.unpack('f', struct.pack('f', x))`), because the port's answer is an `F32` and comparing an f32 against a double is red for a rounding reason rather than a formula reason. |
| `.agents/slop/state-mutate.py` and `.agents/slop/nn-init-mutate.py` | one-token mutations of the two `nn/` files; each is applied, the rows are diffed against the unmutated output, and the file is RESTORED from a byte snapshot. **The mutated copy must live in `tinybendygrad/nn/` beside the original** — the imports are relative, so a copy in `/tmp` cannot resolve them and every mutation reports "did not compile" for a reason that has nothing to do with the mutation (measured; it cost one full pass). Asserts each search string occurs exactly once, so a stale edit target is an error rather than a silent no-op. **A mutation that moves nothing is printed, never dropped**: `state-mutate`'s M12 and `nn-init-mutate`'s M14 are whitespace CONTROLS, and one `nn-init` mutation is recorded as a *semantically identical* edit that moved nothing for a reason that had nothing to do with the gate — which looks identical to a real negative in a table and is not the same thing. |
| `.agents/slop/tcptx-oracle.py` | the ORACLE for `renderer/tc_ptx.bend`: `rows` prints all 620 string-diff rows, `stage1` (286) and `stage2` (334) print the halves for a localised diff. **The `py=` half of every row is a LITERAL in the `.bend` and a live tinygrad value here, which is the only reason the diff is a diff** — `String.concat` drops a literal silently, so a row that said "the asm is right" would survive a missing `;`. Three normalisations, each a decision and each recorded in the file: `frag_coords` is gated on a **FNV-1a digest plus length** and not on the 22 647-character string (hard-coding the eight shapes would put ~180 KB of literals in a file, past bend's measured 28 988-byte per-file cliff; the digest catches every dropped literal a sample would miss, and both sides implement FNV independently); `supported_dtypes` is **sorted**, because ptx.py:230 returns a `set` and a set has no order to compare; and the two control-character constants (`barrier`'s TAB, `fmt`'s TABS) are escaped, so a dropped tab is a shorter line rather than an invisible one. The `render_wmma` and `render_kernel` fixtures are **transcriptions of ptx.py's own text driven by a stand-in ctx**, and every name they print is a register name and every dtype a real `DType`. `PTXRenderer.__init__` needs the CUDA compiler, so `supported_dtypes` is bound to a `Shell` that supplies `target` and nothing else. Wired into `rebase-gate.py` as `stage2` (228 shared names). The six disagreements were stale `py=` literals (`half`/`float`) against live `DType.name` (`f16`/`f32`, dtype.py:134 and :136); the computed half already matched. |
| `.agents/slop/tcptx-mutate.py` | 51 one-edit mutations of `renderer/tc_ptx.bend`, each applied to a scratch copy **in the same directory** (the imports are relative, so a copy in `/tmp` cannot resolve them) and each row-set diffed against the unmutated 620. Prints the first line of a compile refusal, because *why* a mutation will not compile is the measurement: a refused edit says the type system pinned something the text does not. **Four are whitespace CONTROLS and four move nothing for a real reason**, and the two are kept distinguishable — the controls say "an edit that changes nothing must move nothing", the other two are provable blind spots (`Tc.threads` reads a lane count that `__post_init__` ASSERTS is the same for all three fragments, and `supported_dtypes`' order is a `set`'s). One mutation in the table — a `py=` half holding a real TAB where CPython's `repr()` holds a backslash and a `t` — is the only one a human reading both lanes side by side would call green, and it is the reason this gate is a byte diff. |
| `struct.pack('<f', x)` | the cross-check for every float CONST in a port: one Python line that answers "is this literal the bit pattern I think it is". Found the `F32.to_u32` trap (a truncation in the native lane, unfolded in the interpreter) and confirmed `match f: case F32{data}: U32{data}` is right for `0.3183098861837907`, `2.0**24`, `-0.5` and the rest. |

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
## The device-registry oracle (2026-10-02, `device.bend`)

`device.py`'s decisions are gated against **upstream's own Python**, with no
hardware: `Device['PYTHON']` for the Buffer arithmetic, and a **stub on
`Device.get_class`** for the two rows that need a device to "fail to open". The
stub is the whole trick and it is three lines:

```python
class Fake:
  def __init__(self, ix): self.device, self.ix = ix, ix
TD.Device.get_class = lambda ix: (lambda i: Fake(i)) if ix.split(':')[0] in avail \
                                      else (_ for _ in ()).throw(RuntimeError('no'))
```

`get_available_devices` is `with contextlib.suppress(Exception)` around exactly
that call, so a stub which raises IS the "device does not open" case, and
`avail` is the set of names that open.

**TWO TRAPS, both cost a wrong diff and neither is a port bug.**

1. `__get_canonicalized_item` is `functools.cache`d. Clearing
   `Device._opened_devices` is NOT enough: a cached device is returned without
   re-running the body, so the `add` never happens and an opened-set count comes
   out one short. You must also
   `TD.Device._Device__get_canonicalized_item.cache_clear()`.
2. Patch `get_class` LAST, or restore it. `get_class` is itself cached, and every
   `Device[...]` after the patch returns the `Fake`. Reading `rtalloc_size` or
   `device_id` after installing the stub raises `AttributeError` on `Fake`, which
   reads like a broken port and is not.

The rule: **the oracle does the same amount of work the Bend rows do, or the diff
is a harness artifact.** `bend2-constraints.md` has three separate entries about
a comparison being a harness bug (`sz` line counts, the 32 KiB cliff, the
`List.append` reversal), and this is the fourth.

## The four-lane export matrix (`langs/`, 2026-10-02)

| tool | version | pin | why |
| --- | --- | --- | --- |
| zig | 0.15.2 | system | bundles clang + LLVM + wasi-libc, so `zig cc --target=wasm32-wasi-musl` is a wasi-sdk equivalent with no separate download. The **only** wasm toolchain on this machine, and it still cannot host Bend -- see `langs/wasm/WALL.md`. |
| node | 26.8.1 | system | runs the JS lane, the `.mjs` pure-def lane, the SDK and the bench. `--experimental-strip-types` runs the `.ts` sources with no build step; note it does **not** erase constructor parameter properties or rewrite import specifiers, so those are written out. |
| typescript | 5.2.2 | global npm, unused | installed, but `langs/` adds no build step on purpose: node's own type stripping runs the SDK, so a `tsc` would be a second source of truth. |

Two things `langs/` established that the rest of the project should not
rediscover:

- **`bend <file> -o <out>` emits C SOURCE, JS, `.mjs` and BendTT by extension.**
  It was checked before anything was designed, because lane 1's whole shape
  depends on it; `bend2/main.ts:363` is the three lines that do it.
- **There are no per-def symbols in the emitted C.** Every def compiles to a
  segment of a flat state machine, so a C lane has to drive the program's own
  `main` (which bend's emitted C owns) rather than `dlsym` a named function.

`langs/NOTES.md` records the eleven Bend 2.0.34 behaviours that `langs/` had to
work around, each with a reproducer. Four of them are checker defects that will
bite anyone writing loops, and one — **a `case 1n+pn:` arm cannot hold a call** —
contradicts the fuel pattern this project recorded as its loop answer in
`bend2-constraints.md`. That entry needs revisiting by whoever owns it.

## The METAL unit's oracle and harness (2026-10-02)

Four scripts, all in `.agents/slop/`, all for `tinybendygrad/runtime/ops_metal.bend`.
The shape generalises to any backend port whose gate has to be checked against
real hardware, and the reason there are FOUR rather than one is that each answers
a different question.

| script | what it answers | how |
| --- | --- | --- |
| `mt_oracle.py` | what does the SOURCE say, structurally? | `ast`-walks `ops_metal.py`: the 18 `HANDLES + SELECTORS` with `(HANDLES+SELECTORS).index(name)` called, `run`'s thirteen statements with their four conditional arms tagged, `MetalDevice.__init__`'s twelve statements, `submit`'s three `run(h, first, count, last)` calls. `--nol` for the offline rows. |
| `mt_oracle.py` (live half) | what does THE MACHINE say? | opens a real `MetalDevice()`: `check_family("Apple")`, `check_family("Mac")` through `sysdevice.supportsFamily`, `.arch`, `residency.value is not None`, `d.sels.size`, `d.sels.nbytes`, `MTLResourceStorageModeShared`, `platform.mac_ver()`. |
| `mt_rows.py` | which gate ROWS can CPython answer, and do they agree? | 167 `name=value` rows, each a CALL: `helpers.round_up`, `hcq2.layout_args`, `hcq2`'s `prod`, tinygrad's own `BufferSpec`, ops_metal.py's own f-strings, and `MetalDevice()` for the arch. |
| `mt_diff.py` | do the THREE lanes agree? | runs `bin/bend`, `bin/bend -o` and `mt_rows.py`, diffs row names per lane, prints `THREE LANES AGREE`, exits non-zero otherwise. **The scratch binary must be written NEXT TO THE .bend file** — `bin/bend` resolves relative imports from the source's directory, so a `/tmp` copy fails with `no such file: /tmp/helpers.bend`. |
| `mt_mutate.py` | what does this gate NOT see? | 48 mutations, one text edit each, applied to a scratch copy **also beside the .bend file**, then the INTERPRETED lane, then a diff of row NAMES. It REFUSES a mutation whose `old` text does not match exactly once and prints `PATTERN MATCHES Nx -- NOT RUN`, because a table entry whose target line was hand-edited would otherwise read as "0 rows moved" and that is exactly the reading a blind spot must not be confused with. |

Two things worth knowing before writing the next one:

- **The mutation harness wants the scratch copy in the source's own directory.**
  `bin/bend` resolves `import ../helpers.bend as H` relative to the file, so a
  copy anywhere else cannot even be checked. This cost a run.
- **Generate the expectation by CALLING the helper, never by transcribing it.**
  Seven real bugs were found this way and the two that mattered most
  (`csrc_pad` dropping a subtraction, and the ICB header rows hardcoding the
  first command's `off` instead of `zero`) are invisible to a boolean row and
  invisible to a hand-written number.

## ops_dsp — the oracle/checker/mutate trio (2026-10-02)

| script | what it answers | how |
| --- | --- | --- |
| `dsp_oracle.py` | what does CPython say? | calls `rpc_sc`, `rpc_prep_args`, `_render_entry`, `_render_defines`, `supported_dtypes`, `DSPCompiler` and `mockdsp_boilerplate` for the tables; then **fakes the ioctl/os layer and drives the REAL `DSPDevice.init_dsp`, `open_lib`, `close_lib`, `exec_lib`, `DSPAllocator._alloc/_free/_offset`**, which is the only way to measure the seven-call init ORDER and the eleven-call retry without a DSP. |
| `dsp_gate_check.py` | do the `py=` comments still match the lane? | regexes every `# py=` row out of the .bend, parses the lane's `name=value` output, prints MATCHED / MISMATCHED / NEVER PRINTED. **First run: 420 matching, 35 mismatched, six of them real port bugs.** Four lines of regex; run it on every edit. |
| `dsp_mutate.py` | what does this gate NOT see? | 68 one-edit mutations (67 + a comment-only control), each applied to a scratch copy **beside the .bend file**, then the INTERPRETED lane, then a diff of the **whole `name=value` line**. Refuses an edit whose `old` text does not apply and prints `-- EDIT DID NOT APPLY --`, distinct from `-- DID NOT COMPILE / RUN --`. |

Two things worth knowing before writing the next one:

- **Diff `name=value`, not the row NAME.** A name-only diff reads **all 68
  mutations as "0 rows moved"**, because a mutation almost always changes a value
  and never a name. The control is the only honest zero.
- **The scratch copy must sit in the source's own directory.** `bin/bend` resolves
  `import ../helpers.bend as H` relative to the file; a `tempfile.mkdtemp()` scratch
  dir makes every mutation report `-- DID NOT COMPILE / RUN --`, which reads like a
  broken table and is a broken harness.

## late — the oracle/gate/mutate set (2026-10-02, regalloc)

| script | what it answers | how |
| --- | --- | --- |
| `late-oracle.py` | what does CPython say about the LOWERER? | drives `tinygrad/codegen/late/{linearizer,regalloc,gater}.py` over FIXED fixtures and prints all 128 rows. Its regalloc half supplies the four hooks tinygrad's own base class leaves `NotImplementedError` (`assign_spill_slot`, `fill`, `spill`, `is_two_address`) and builds two hand-made uop lists: `ra_fixture` twice with `is_two_address` False and True, and `ra2_fixture`, which is the only one with a RANGE and an END. No GPU, no driver, no codegen cache. |
| `oracles/late-oracle.txt` | what did it say, checked in? | the oracle's 128 rows. The acceptance test is `diff oracles/late-oracle.txt <(./bin/bend tinybendygrad/codegen/late.bend)`, and the native lane must print the same bytes. |
| `ra-mutate.py` | what does the regalloc gate NOT see? | 38 one-edit mutations of the ported pass, each applied to `late.bend` in place, run, and RESTORED in a `finally`. Reports the rows that move by NAME (`ra0_a7`), or `NOTHING (blind spot)`. |
| `ra-mutate2.py` | the same, for the rest | 14 more, and the one that catches an ORDER-ONLY mutation. |
| `fixplus.py` | bend says "consumed more than once" | reads the compiler's Location + Context, adds the `+` to the named parameter in the named def, repeats. **It edits in place and is only as safe as its `def` lookup** — it once blanked five continuation lines of an unrelated def because it matched the wrong header. Check `def`/`type` counts after every run. |

Three things worth knowing before writing the next one:

- **When another agent is mid-edit in a file you import, `--check-only` fails on a
  location that is not in your file.** `uop/fold.bend` carried a mutual recursion for an
  hour and every cold compile of `late.bend` reported it while the WARM cache kept
  printing 83 correct rows. Iterate on a probe that imports only what the unit needs
  (`Base`, `helpers.bend`, `ops.bend`), and treat a failure whose Location is outside
  the file as somebody else's edit. This is RA-8 in `bend2-constraints.md`.
- **Mutate in place and restore, not into a scratch copy.** A scratch `.bend` beside
  the original is one more file to delete and one more way to leave a broken unit behind;
  `try/finally` around `run()` makes the restore unconditional. A scratch copy in
  *another directory* is worse than useless — the relative imports stop resolving and
  every mutation reports a compile error.
- **Compare the row SEQUENCE as well as the set.** "Every row is present and correct but
  in the wrong order" is a real mutation the port survived (`ra_lines` putting the
  per-uop rows first), and a set-comparison harness reports it as `NOTHING`.

## am/ip — the oracle, the three lanes, and TWO mutation harnesses (2026-10-02)

`tinybendygrad/runtime/support/am/ip.bend` is a port of `tinygrad/runtime/support/am/ip.py`
(755 lines). It keeps to the `ops_webgpu.bend` **trace lane** — `Tr`/`Call`/`Row` records,
`Tr.emit` as the only seam — so it is `ALL PROOFS CHECK` with no foreign effect, and it
needs no device to run. `ip.py` itself imports with no card present, which is what makes
the oracle possible.

| script | what it answers | how |
| --- | --- | --- |
| `ip_oracle.py` | what does CPython say? | imports `tinygrad/runtime/support/am/ip.py` for real, walks the `am` autogen enums, imports the four `smu_<maj>_<min>_<pat>` modules for the per-arch table, PROBES each `SOC15_*_FROM_IH_ENTRY` one bit at a time to recover its mask and shift, reads `register_fields` out of `autogen/am/am.py`, and evaluates the PM4 packet literal against the real `pm4_soc15` module. 447 rows. |
| `ip_check.sh` | do the three lanes agree? | `bend --check-only`, the INTERPRETED lane, the NATIVE lane, and the oracle diff **keyed on row name**. Row-name keying matters: three row names would otherwise collide silently. |
| `ip_mutate.sh` | what does the LOGIC gate not see? | 45 hand-written mutations, one per rule. Scratch copy **beside** the original at the same depth (the relative import is three levels up), removed by an `EXIT` trap. |
| `ip_sweep.py` | what does the gate not see among the LEAVES? | 369 **exhaustive** perturbations: every numeric constant by +1, and every generated register row twice — once on the line number, once on the field name. No hand-picking, so "over every rule" is a measurement. |
| `ip_prune.py` | which constants are not a port at all? | deletes numeric constants with **zero call sites**, refusing anything it cannot prove unread. It found and removed 46; all three lanes re-verified byte-identical afterwards. |

Four things worth knowing before writing the next one:

- **The scratch must live in the tree.** `import ../../../helpers.bend` is relative, so a
  copy under `$TMPDIR` cannot resolve it and every mutation reports a compile failure.
  Same as the note in the `late` section above.
- **A mutation that never applied reports `0`, and `0` is also a finding.** The runner
  splits its edit on `|||`; one row shipped a single `|`, the split raised, the scratch
  stayed pristine, and the pristine-vs-pristine diff printed `0` next to 42 real
  measurements. The runner now asserts `len(parts) == 2` and prints `HARNESS-FAIL`.
- **An oracle row that re-transcribes a Python expression agrees with a port that
  misread it.** `lo, _ = data64_le(x)` stood in for `*data64_le(x)`, so the port's
  dropped high word and the oracle's dropped high word cancelled and all 447 rows were
  green on a **sixteen-word PM4 packet that `ip.py:108-110` builds as seventeen**. Asking
  CPython for `len(pkt(...))` is what found it. An expectation has to CALL the thing.
- **Two Python lines may share an f-string register name.** Sixteen of the 115 names are
  f-strings (`regCP_{cntl_reg}_CNTL`, `{reg_pref}_64`, …) and nine appear twice, so a
  field-name swap is a genuine equivalence for those rows while a line-number swap moves
  all 115. That is why `Row` is keyed on `(ln, reg)` and not on the name.

## The `nv/ip.py` toolchain — `tinybendygrad/runtime/support/nv/ip.bend`

| tool | question | what it does |
| --- | --- | --- |
| `nv_ip_gen.py` | what are the LAYOUTS and the TABLES? | reads `ctypes` `_real_fields_`, module constants and `rpc_fns`/`rpc_events` out of `autogen/nv.py` and emits `nv_ip_tables.bend` (54 structs, 413 fields, 64 constants, 260 dispatch rows) **and** the Stage B rows. Run first; everything else reads what it writes. |
| `nv_ip_oracle.py` | what does CPython say about the ARITHMETIC? | asserts its own `round_up`/`round_down`/`ceildiv` against `tinygrad.helpers` at five probes **before** using them, then evaluates queue sizing, radix3, the WPR-meta ladder on both branches, libos regions, registry offsets, `bdf_as_int` and the PMA shifts. 401 rows. |
| `nv_ip_oracle3.py` | what does CPython say about the TRACE? | lifts `_checksum` and `_send_rpc_record` out of `NVRpcQueue` **verbatim** and runs them over the real `nv.GSP_MSG_QUEUE_ELEMENT` / `nv.rpc_message_header_v`, then reads the twenty U32 words off `bytes(phdr) + msg`. Also builds `build()`/`record()`/`record_words()` so the checksum, the record and the word image are ONE transcription. 394 rows. |
| `nv_ip_oracle4.py` | what does CPython say about a REFUSAL? | **executes** `_send_rpc_record` with the fault raised at call ordinal N, against a real `nv.msgqTxHeader`, and reads `tx.writePtr` and `seq` back off the machine. 62 rows. |
| `nv_ip_diff.py` | do BOTH lanes agree with the oracle? | three comparisons, all byte-exact: interp vs compiled, and each vs the four row files. Reports VALUE / MISSING / EXTRA separately and flags an oracle **self-conflict** (one key, two values) rather than letting one silently win. |
| `nv_ip_build.py` | is the FILE reproducible? | assembles `ip.bend` from ten parts, runs the reorder, runs `--check-only`. Forty hand patches had corrupted the file before this existed. |
| `nv_ip_order.py` | what order do the defs go in? | stable topological sort. Three bugs it had — stalled after one pass, rebuilt one-line defs wrongly, swallowed the preamble and deleted `import Base` and the GENERATED markers — are fixed and documented in its own comments. |
| `nv_ip_mutate.py` | what does the LOGIC gate not see? | one textual edit per rule, applied to the file **at its real path**, interpreted lane re-run, whole `name=value` lines diffed. 37 mutations, each with an exact-match assertion so a mutation that silently matched nothing cannot report a fake `0`. Classifies a `0` as **MOVED** / **EQUIVALENT** (with the identity that makes it so) / **BLIND**. |
| `dead-defs2.py` | which defs does NOTHING read? | full **dotted** name, comments and strings stripped, `main` whitelisted. Supersedes `dead-defs.py`, which matched the base name and scored `def rp.pair.hi` alive on the hundreds of `rp.` uses. 4 dead reported vs 30 found. |

Five things worth knowing before writing the next one:

- **A hand-tabulated oracle reproduces the port's mistake.** The Stage E truncations were
  a hand-written `ENTRIES` table plus a rule saying the write pointer moves "if `fail_at`
  < 3". The rule was backwards (the store at :51 IS the third call), the port's guard was
  inverted to match, and all five rows were green over the bug. `nv_ip_oracle4.py` now
  raises the fault and reads the struct, so the two cannot be wrong the same way twice.
  This is the fifth unit bitten by a typed expectation and by far the worst, because it
  produced **corroboration of a bug** rather than a mismatch.
- **A dead def keeps itself out of the dead-def audit.** `type Wv`, `rp.acc`,
  `rp.pair.hi`, `rp.pair.lo` were an abandoned fold that could never have worked
  (`Bool.pick` drops its untaken arm, so a `{h, l}` record cannot be threaded out of a
  recursion). They survived 1174 green rows because a dead def cannot fail. Match the FULL
  dotted name and strip comments before believing any reachability number.
- **A comment is not a row.** The word layout said `elemCount` was at [11]; it is at
  [10], and `ip_rp_0_w10` is what proved it. The other direction also holds: a rule that
  claims a row must have one, or the claim is the same kind of fiction.
- **A mutation may need to span sites, because Bend has no forward references.** A rule
  whose threads run through two defs cannot be cut at one of them; the harness takes a
  LIST of `(old, new)` pairs for exactly that, and the helper has to land in the right
  SLOT or the file will not build (`an unfilled law is a dead claim`).
- **A `0` needs a reason.** Four of the 37 mutations move nothing because the mutant is
  the same function — `x - x%m == (x/m)*m`, `cdiv(0,m) == 0`, XOR commutativity across two
  accumulators, and two zero slots that both answer `0`. Those are theorems, not gaps, and
  the harness prints the identity so a reader does not have to rediscover which of the two
  it is.

## 2026-10-02 — `schedule/rangeify.bend` (the `ct` table's op sets)

- **`.agents/slop/rf-ct-oracle.py` → `oracles/rf-ct-oracle.txt`.** The ONLY way
  this unit's central question was answerable: `for tag, (p, _f) in
  enumerate(pm.patterns)` prints `p.op` and `p.early_reject` for all nine rules, and
  `p.match(u, {})` + `pm.rewrite(u)` prints the bindings and the answer. It is ~200
  lines and it replaced every hand-transcription. `run` with `.venv/bin/python` from the
  repo root; `sys.path.insert(0, '.')` or the import fails.
- **`UOp` does not type-check `arg` against `op`.** That is the measurement that makes
  the outer-vs-inner fixture constructible at all, and it is also why an INDEX may carry
  `(axis_id, AxisType)` — `prepare.py:70` passes `arg=idx.arg` in real code.
- **`.agents/slop/rf2-mutate.py` → `.agents/slop/rf2-mutations.txt`.** The mutation
  harness, rewritten to diff WHOLE `name=value` lines and to require
  `ALL PROOFS CHECK` before running (a COMPILE-FAIL is reported, never counted as a
  zero). It writes a raw TSV, which is the thing to read when a summary lies.
- **A scratch `.bend` outside the tree cannot resolve `./../uop/ops.bend`.** The
  symlink farm `.agents/slop/rf2root/` holds `helpers.bend`, `LAWS`, `uop`, `runtime`,
  `codegen`, `mixin`, `device.bend` as symlinks into `tinybendygrad/`, with a real
  `schedule/rf2_work.bend` inside it; `.agents/slop/rf2_work.bend` is a symlink to that,
  so the brief's path and the runnable path are ONE file.
- **A harness that restores the baseline at the end will silently revert edits made
  while it runs.** It happened twice here: `rf2-mutate.py` writes `WORK` from a
  `.orig` snapshot taken on its FIRST run, so any edit made after that first run is
  destroyed by the next run. Delete the snapshot before every run.
- **`F.folded(O.Found.ar(<node>))` is a SNAPSHOT.** A node interned after it is in
  `G.ix` but not in the fold's table, so every property of it reads as the arena's
  bottom (`mp_op` answers `OpsNOOP`, value 4). Symptom: `lay` rises, the new rows read
  0, and `ren_axis_in_dev` disagrees with the node's own constructor.

## `runtime/support/memory.py` — the oracle/differ/mutator trio (2026-10-02)

| tool | what it is |
|---|---|
| `.agents/slop/memory_oracle.py` | **Every** `py=` row is produced by CALLING CPython: `MMIOInterface(...)`, `BumpAllocator(...).alloc(...)`, `TLSFAllocator(...).lv1/lv2`, `struct.calcsize`, `dataclasses.fields`, `inspect.signature`, `inspect.getsource`, `MemoryManager.__new__(...)._frag_size(...)`, and the two page-table assert loops run as Python against a recorder. Nothing typed. |
| `oracles/memory_oracle.txt` | the snapshot, 889 rows. Regenerate, never edit. |
| `.agents/slop/memory-diff.py` | the gate. Diffs **whole `name=value` lines** and reports rows only in one side **in BOTH directions**. Prints `rows: bend=889 oracle=889 compared=889 disagreements=0` and exits 0. |
| `.agents/slop/memory-mutate.py` | 70 mutations (M01–M70), rewrites a `.mut` copy, reports rows moved **by name**, and prints its own blind-spot list. Currently **6 moved nothing**. |
| `.agents/slop/memory-report.md` | the report: citing-file audit, stage table, gate table traced to CPython calls, mutation table with reasons, the FFI seam split by Python line. |

No new dependency. The only tool is `bin/bend` plus CPython 3 via `.venv/bin/python`.

**THE THREE THINGS THIS TRIO TAUGHT, all now in `bend2-constraints.md`:**

1. **The ONLY-IN check in both directions is the whole gate.** Reconciling this unit started at
   570 compared / **0 value disagreements** / **547 rows on one side only** — the lanes agreed
   perfectly about the rows they shared and the file had drifted off the oracle entirely. A
   differ that skips the unmatched rows reports `disagreements=0` and measures nothing.
2. **A mutation harness must diff whole lines, not row names**, and must print its own blind
   list. Both directions of that have now bitten: comparing names reports 0 for every mutation,
   and a harness that only prints what moved cannot tell a closed mutation from an unfalsifiable
   one.
3. **A row that cannot be computed in the lane must be DELETED from both sides, not kept as a
   literal.** `va_alloc_off_*` was a literal on the Bend side because the TLSF free-list walk is
   not ported; a literal that agrees is a change-detector.

## `runtime/support/usb.py` — the assembler + the eight checks (2026-10-02)

| tool | what it is |
|---|---|
| `.agents/slop/usb-gen.py` | writes `oracles/usb-arith-rows.bend.txt`: 17 flat row sections, 357 rows. A row that is a `#` comment is emitted verbatim, which is how the two "do not re-spell this row name" notes survive regeneration. |
| `.agents/slop/usb-gen-strings.py` | patches `t_strings` in `.agents/slop/usb-sblock.bend.txt`. Idempotent, and the cut starts at the banner and not at the `def` — see the rule in `bend2-constraints.md`. |
| `.agents/slop/usb-gen-tables.py` | prints the 21 `enum_libusb_*` tables, both folds, the 22 field lists and the 22 `ctypes.sizeof`s, read out of the LIVE `tinygrad.runtime.autogen.libusb`. |
| `.agents/slop/usb-build.py` | the assembler. Reads the pieces in DEPENDENCY order and writes `tinybendygrad/runtime/support/usb.bend`, 2596 lines. The mutation table and the seam list are read back from their generators, so both are MEASURED rather than transcribed. |
| `.agents/slop/usb-diff.py` | the gate. Diffs **whole `name=value` lines** against four CPython oracles and reports one-sided rows **in both directions**. `rows bend=939 oracle=939 disagree=0 oracle_only=0 bend_only=0`. |
| `.agents/slop/usb-oracle{,-arith,-trace,-strings,-run}.py` | every `py=` expectation is produced by CALLING CPython: the live `autogen.libusb`, `struct.calcsize`, `struct.pack`, and `usb.py`'s own AST (arguments-first, `n.func` visited last). |
| `.agents/slop/usb-handmap.py` | 74 port constant -> `(line, col)` in `usb.py`, so a wrong value is not expressible and a wrong POSITION is loud. `--list` prints every evaluable node on a line. |
| `.agents/slop/usb-constsweep.py` | evaluates every `def NAME() -> U32` against the hand map, `ctypes.sizeof`, `struct.calcsize` or the port's own derivation. `swept 124: 123 CONFIRMED, 0 WRONG, 1 unverified` (the PORT-INTERNAL `NOT_FOUND`). |
| `.agents/slop/usb-symmap.py` | the `K_*` -> `SYMS()` bijection and that every symbol is a real libusb export. `kinds=24 syms=24 injective=True all_symbols_real=True`. |
| `.agents/slop/usb-dead.py` | a def nothing calls is invisible to every other check. `339 defs, 0 dead`. |
| `.agents/slop/usb-mutate.py --md` | 45 mutations, one edit each, whole-line diff, and it WRITES the table the port quotes. `44 move rows, 1 theorem`. |
| `.agents/slop/usb-seam.py` | the 111 unported lines of `usb.py` with a reason each, printing the source text out of `usb.py` so the list cannot drift. |

No new dependency: `bin/bend` plus CPython 3. The three generators exist because the
port is GENERATED — in-place edits destroyed the file twice, and the last stretch of
this unit went into making the pipeline reproducible rather than into the file.

**REPRODUCIBLE END TO END** (run the pipeline twice and diff — that check is what
caught the non-idempotent patcher):

    python3 .agents/slop/usb-gen.py && python3 .agents/slop/usb-gen-strings.py && \
    python3 .agents/slop/usb-build.py && ./bin/bend tinybendygrad/runtime/support/usb.bend && \
    python3 .agents/slop/usb-diff.py && python3 .agents/slop/usb-constsweep.py && \
    python3 .agents/slop/usb-symmap.py && python3 .agents/slop/usb-dead.py && \
    python3 .agents/slop/usb-mutate.py --md .agents/slop/usb-mutations.md

`--check-only` exits 1 even when it is fine. **Read the FIRST LINE**: `ALL PROOFS CHECK`.

---

## The autogen const audit (2026-10-03, ops_webgpu.bend + ops_cl.bend)

The lesson from `ops_nv`'s 33/219 wrong constants in a file with 590 green rows:
a green gate tests GRAPHS, the constants answer to a C header nobody read, and the
fix is a hand-built name map. The smoke-test script `.agents/slop/const-audit.py`
is documented to be one and reaches only 0-18 of 222 `ops_nv` consts because the
port invents names; what shipped was a 219-entry hand map. The two device files
audited in this round use the same recipe.

| tool | why |
| --- | --- |
| `.agents/slop/const-audit.py` | the SMOKE TEST. Name-matches the port to the autogen, exact and by a small prefix list (`CLASS_`, `CUDA_`, `CL_`, `HIP_`); refuses to call a name WRONG when the two sides are plainly different concepts. Its **coverage** number is the finding: 0-18/222 on `ops_nv` meant the port invents names and a real audit needs a hand map. |
| `.agents/slop/ops_webgpu_constmap.py` | the 65-entry hand map for `ops_webgpu.bend` -> `tinygrad/runtime/autogen/webgpu.py`. The 14 header-mapped names (`BIND_*`, `FILTER_*`, `MAP_*`, `FEATURE_*`, `USAGE_*`, `STATUS_SUCCESS`) match byte-for-byte; the 51 PORT_ONLY are `OBJ_*` (13), `CALL_*` (23), `SYNC_*` (11), and four sentinels (`BIND_GROUP_INDEX`, `UNIFORM_SIZE`, `QUERY_COUNT`, `QUERY_BUF_SIZE`). |
| `.agents/slop/ops_webgpu-const-audit.txt` | the 65-row report. |
| `.agents/slop/ops_cl_constmap.py` | the 66-entry hand map for `ops_cl.bend` -> `tinygrad/runtime/autogen/opencl.py`. 14 `CL_*` exact, plus `cl_err_n` = 63 and `cl_err_names_n` = 74 verified against the live autogen (74 error names -> 63 unique codes). The 50 PORT_ONLY are the 41 `OP_*` trace tags, `V_CL`, three fold bodies, and seven sentinels/sizes. |
| `.agents/slop/ops_cl-const-audit.txt` | the 66-row report. |

The third vendor spelling (CUDA, HIP) lives in `ops_cuda.bend` / `ops_hip.bend`
after the 1:1 file split. They remain queued under the same recipe. **0 source
edits in this round** because both ports' header-mapped values are correct.

---

## Env-flag measurement (2026-10-02, owner: the env-flag audit unit)

No new dependency: `bin/bend` plus CPython 3 via `uv run`. The point of these four
is that a flag bug is INVISIBLE to a default-environment gate, so the oracles have
to *set the environment* and the differ has to read CPython's answer rather than
mine. `.agents/slop/env-flag-divergence.md` is the findings.

| tool | what it is |
|---|---|
| `.agents/slop/env-coercion-table.py` | the `getenv` coercion table, MEASURED. PART 1 replaces `os.getenv` with a spy before importing `tinygrad.helpers`, so the 64 (key, default, type) triples are the interpreter's own. PART 2 calls `H.getenv` once per (default type, probe). PART 3 re-imports in a fresh process per probe so PART 2 is not an artefact. PART 6 is the three `bool`-default flags. PART 7 walks `NO_COLOR` end to end through `helpers.colored`. Writes `env-coercion-table.txt`. |
| `.agents/slop/nocolor-oracle.py` | the `py=` half of the `NO_COLOR` gate. **One fresh process per probe**, because `getenv` is `@functools.cache`'d and one process is one reading. A line that says `REFUSED` is `int()` raising, i.e. tinygrad refusing to import. |
| `.agents/slop/nocolor-probe.bend` | the Bend half: `no_color_of` over the same 31 probes in the same order, one answer per line. `ALL PROOFS CHECK`. |
| `.agents/slop/nocolor-diff.py` | diffs WHOLE LINES. `REFUSED` requires `False` (rule X: a refusal is not a value, so the port takes the default reading); one line is an allowlisted NAMED BOUNDARY with its reason. `exact 18  refusal-answered-False 13  named-boundary 1  DISAGREE 0  of 32`. |
| `.agents/slop/flag-def-scan.py` | every `def <FLAG>() -> U32: <default>` in the tree, i.e. the mechanical signature of a substituted flag. 4 hits, 2 real. |
| `.agents/slop/flag-consume.py` | every Python READ of each flag, with the Bend lines that name it. This is how a wall note is told from a silent absence. |
| `.agents/slop/flag-literal-scan.py` | every literal equal to a distinctive (non-0, non-1) flag default inside the Bend port of each consuming file. **396 candidates, 3 real** — it can only nominate; see the false-positive list in the findings. |

**`--check-only` exits 1 even when the file is fine. Read the FIRST LINE.** The three
`SOME PROOFS FAIL` files that are NOT mine: `dtype.bend` (14 unfilled laws),
`sz.bend` (7 foreign defs), `test/dtype_oracle.bend` (imports `dtype.bend`).

---

## Ungated-drift closure, `render.bend` + `rewriter.bend` (2026-10-03)

No new dependency: `bin/bend` + CPython 3. Everything lives in `.agents/slop/xd1/`.
**Nothing is committed.**

| tool | what it is |
|---|---|
| `.agents/slop/xd1/wt-sync.sh` | **A COMPILER WORKAROUND, not a design.** A live agent is mid-edit on `tinybendygrad/helpers.bend` and it does not compile (eight `nc_*` defs read an un-`+`-pinned binder twice), which fails EVERY file in the tree with the same error. This mirrors `tinybendygrad/` into `.agents/slop/xd1/wt/` and restores `helpers.bend` from HEAD — the substrate the baseline was measured against. The mirror is a whole tree, not one file: relative imports resolve inside it, and a single-file scratch copy produced 22 phantom blind spots in an earlier unit. **Delete this script and `wt/` the moment that agent lands.** |
| `.agents/slop/xd1/verify.py` | the check `agent-core.md` asks for and that NOTHING in this repo had: a port and its own embedded `py=` oracle can AGREE AND BOTH BE WRONG (`nv_query_litter` was wrong in the port AND in the oracle, and the differ reported zero). This reads the lane, extracts each row's answer and its embedded `py=`, reads the SAME fixture out of a CPython oracle in a SEPARATE PROCESS against a SEPARATE TREE, and reports where they differ. Three shapes had to be got right, each after a failure recorded in the notes: (1) **the lane's row NAMES are the oracle's vocabulary** — a rendered pyrender tree puts `c1 = UOp.range(...)` on UNINDENTED lines inside a value, and any "does this line start a row" heuristic that did not know the names clobbers the real value; (2) **the `py=` regexes use SEPARATE capture groups and consume nothing** — cutting at the marker ate the value's closing `]` and reported 41 of 78 rows disagreeing by one character; (3) **the oracle dying is NOT a pass** — it raises, because `0 rows` is the broken shape. |
| `.agents/slop/xd1/rowdiff.py` | whole-`name=value`-LINE diff between a clean lane and a mutated one, rows reported BY NAME. **Needs bracket-depth tracking**: a rendered pyrender value contains `[...]` on continuation lines, so counting lines starting a record mis-splits it. |
| `.agents/slop/xd1/render-gate-oracle.py` / `rw-gate-oracle.py` | the CPython halves, run against `.agents/slop/xd1/head` (`git archive upstream/master`) because the working `tinygrad/` is a measured broken hybrid (`ops.py` at HEAD, `render.py` at the pin) whose `pyrender` answers NEITHER end. Every `py=` is a CALL into CPython, never a transcribed string — and no row's expected value was ever edited to make a change pass. Where the two ends read differently, the oracle builds the node the port's reading NAMES (e.g. `ARng` builds `UOp.range(4, 0, GLOBAL)`, not `UOp.range(4, (0,), GLOBAL)` — two nodes, one ucache key). |
| `.agents/slop/xd1/mkrows.py` | turns a CPython run into gate rows. **Escapes quotes before newlines, never backslashes** — a backslash escape corrupts the value it is meant to carry. |
| `.agents/slop/xd1/mutate.py` / `rw-mutate.py` | the mutation tables: 13 and 10 one-edit reverts of this unit's own fixes, each compiled, run, and diffed against the clean lane by whole lines. **Every mutation is a revert of one of the fixes, so the set a mutation moves IS the set that fix was load-bearing for.** A `0` is printed as a REQUEST for a fixture or a theorem, never as a coverage claim, and the two sorts are kept distinguishable from a whitespace control. |
| `.agents/slop/xd1/stem-bug.py` | the proof for the `rebase-plan.py` fix: old map **34 ported / 15 NONE**, new map **38 ported / 11 NONE, 0 lost**. 4 files the planner had never seen, 3 whose status changed. |
| `.agents/slop/xd1/rewrite-main.py` | moves a ported rule's block without touching its neighbours, used when a new rule has to land above `main()` because it is not entry-order-linear. |

Current state: `render.bend` **66 -> 80 rows** (14 added, 4 re-measured, 0 removed),
**77 agree / 3 disagree / 0 no-oracle-row of 80** — the 3 are `ops.bend` substrate
(`CustomFunction` added, `CallInfo.dtype` dropped). `rewriter.bend` **32 -> 54 rows**
(22 added, 0 re-measured), **54 agree / 0 disagree / 0 no-oracle-row of 54**.

Counting rows through `verify.py`'s parser rather than `grep -c`: a rendered pyrender
value puts `c2 = UOp.range(...)` and `ast = UOp(Ops.BUFFER, ...)` on UNINDENTED lines
INSIDE a value, so a line-count over-reports by 5 and a name-split over-reports by
more. `reassemble`'s bracket-depth tracking plus the name-vocabulary filter is the
only count that matches what a reader sees.

**`--check-only` exits 1 even when the file is fine. Read the FIRST LINE.**

---

## The rebase-gate wiring unit (2026-10-03) — instruments, no new dependency

Everything below is `bin/bend` + CPython. **Nothing is committed.**

| tool | what it is |
|---|---|
| `.agents/slop/rebase-survey.py` | **WIRE AN ORACLE BY ITS OUTPUT, NEVER BY ITS FILENAME.** Runs every candidate under `.agents/slop/`, `xd1/`, `notes/`, `oracle/` and `oracles/`, and reports the row-NAME intersection with each port: `WIRED` / `NO-SHARED` / `DEAD-LANE` / `DISAGREES`. `hcq2-oracle.py` looks like it belongs to `hcq2.bend` and it does; `qc_oracle.py` runs, exits 0, emits 364 rows and shares **zero** names with `ops_qcom.bend`'s 750. Each candidate runs ONCE (an oracle's row names do not depend on the port it is passed) and the measurement is a set intersection; running 104 oracles per port is a 50-minute job that had not finished when it was abandoned. |
| `.agents/slop/rebase-oracle-spec.py` | NEW oracle for `uop/spec.bend`, 11 of 21 rows, **RED on 2**: `te_len` 56 vs 55 and `fu_len` 71 vs 70, which is the "TWENTY-THIRD TENSOR RULE" the port's own header calls WRONG. `PatternMatcher` has no `len()` and every CPython spec table is a `PatternMatcher([...]) + spec_shared` CONCATENATION — `spec_full` names `spec_shared` three times, so `len(spec_full.patterns)` (136) cannot be the row a linear `full_table()` (70) answers. `own(pm, base) = len(pm) - len(base)` is the subtraction that survives it. The 10 rows it does NOT cover are 24-node fixture-arena verdicts, and re-typing the PORT's fixture into Python is the move that produced `nv/ip`'s hand-TABULATED oracle agreeing with a swapped `Bool.pick` on all five rows. |
| `.agents/slop/rebase-oracle-ops.py` | `ops-oracle.py` plus the filter `ops-gate.sh` already applies, with the bend-only prefix list **DERIVED from the oracle's own `#bend_only_` lines**. Handing `ops-oracle.py` to the gate raw gives 5 `rngarg_*` disagreements — the `ARange` FIELD ORDER, which eleven committed files read positionally — and typing the filter list here would make the two filters drift. Reports three states itself: dead lane, empty output, agreement. |
| `.agents/slop/rebase-oracle-search.py` | NEW oracle for `codegen/opt/search.bend`, 12 of 18 rows, **RED on 5**, and it exists because `tinygrad/codegen/opt/search.py` **in the vendored tree does not import**: line 15 reads `AxisType.UNROLL`, which upstream deleted. Measured against `.agents/slop/opstree`: `actions` is 209 where the port counts 269 and has 18 amt-0 entries where the port counts 28. `TG_TREE` picks the tree exactly as `ops-gate.sh` does, and the vendored tree's import failure is printed as the ROW `#repro_vendored_import` — because a fact that can only be read in a comment survives exactly as long as the comment. `acts_n_padto` is the length of `actions` imported **with `BEAM_PADTO=1`**, because the PADTO group is added by a module-scope `if getenv(...)` and is not in this process's list. |
| `.agents/slop/rebase-break.py` | PROVE AN ORACLE IS CAPABLE OF BEING RED, by perturbing the PORT and reverting it. The revert is **asserted, not intended**: SHA-256 before, SHA-256 after, and a non-zero exit with the backup left in place if they differ. Fails when the perturbation string is not unique (it must occur exactly once or the proof is about nothing) and when it moves no row. |
| `.agents/slop/rebase-shadow.py` | The same proof for an oracle whose INPUT IS THE TREE. `copytree(symlinks=True)` — 289 links, no bytes, two seconds — then one link is replaced by a real perturbed copy, so nothing upstream can be reached and `codegen/opt/*` (a live agent's file) is never touched. Asks the right question: not "did it go red" but **"did the row that moved belong to the thing the oracle claims to read"**. |
| `.agents/slop/rows-blast.py` | **THE BLAST RADIUS OF `rows()`, MEASURED OVER EVERY WIRED LANE.** Runs all pairs LIVE, keeps the RAW stdout, and applies the shipped parser and any candidate to the same bytes; per lane it reports old/new row counts, keys gained, keys dropped and values changed, and per PAIR the shared and disagreeing counts under each. Nothing is read from a cache, because a cached row DICT cannot answer the only question here -- what did the text say. 38 pairs in ~470 s at 5 workers. It is how the `]   py=[` fold was shown to move 0 keys and 0 verdicts on 32 of the pairs while it changed 1 504 values on `renderer/amd/generate.bend` alone, and how `cstyle.bend` was shown to go 222 shared / 222 disagree -> 222 / 0. |
| `.agents/slop/rebase-gate-selftest.py` | The six-state TEMPLATE every oracle must pass: dead lane, empty output, no shared row name, a shared name that differs, agreement, malformed baseline — each driven through the same `gate_port()` main() calls, with each wired oracle's OWN row names as the fixture. Synthetic names would pass a broken oracle and fail a working one. |

Three bugs found in the instruments themselves this session, all recorded at the
end of `.agents/slop/notes/bend2-constraints.md` as `AQ1`-`AQ7`: an unkeyed cache in
`rebase-survey.py` that replayed a FAILED run for twenty minutes (the exact
hazard the gate's GUARD 3 exists to prevent, reproduced in the tool that documents
it); `ports_of()` raising `TypeError: cannot use 'list' as a dict key` once
`rebase-plan.py` started mapping one upstream file to a LIST of ports; and
`run_port()` running oracles under `sys.executable`, so an oracle that imports
fine under `.venv`'s 3.12 can be reported dead under `python3`'s 3.14.

**`--check-only` exits 1 even on a clean file. Read the FIRST LINE.** And a `.bend`
that does not compile prints `SOME PROOFS FAIL` and **exits 0**, so a zero-row lane
looks exactly like an oracle that emitted nothing — which is what GUARD 2 is for.
| `.agents/slop/ga-oracle.py` -> `oracles/ga-oracle.txt` | the ORACLE for `renderer/amd/generate.bend`: **892 rows, every one produced by CALLING CPython**, and the file is checked in so the gate does not need Python to run. It imports `tinygrad/renderer/amd/generate.py` and calls `_strip_enc`/`_norm_field`/`_map_flat`/`parse_xml`/`extract_pcode` and the five emitters, whose emitted FILES are read back and emitted one row per LINE; `fetch` is satisfied from tinygrad's download cache so no network is used, and the 34 `parse_xml` rows are over the REAL pinned `amdgpu_isa_rdna3_5.xml`. **The per-LINE rows are joined per module by `ga_gate.py` into eight whole-file gate rows**, because a count row is identical for a dropped class, a dropped enum member, a swapped `default=NULL` and a reordered field. Two harness bugs here were real bugs elsewhere: `tag_join` re-reads the oracle FILE rather than a name-keyed dict, because blank lines in an emitted file share one row name (`common | `) and three separators were lost, producing a WRONG expectation that disagreed with the correct port. |
| `.agents/slop/ga_fix.py`, `ga_splice.py`, `ga_topo.py`, `ga_dedup.py`, `ga_plus.py` | the fixture/gate GENERATOR and the three repair passes. `ga_splice.py` removes the ten generated defs (`g`, `gl`, `main`, six `fx_*`) WHEREVER they are and appends them at the end -- they are **NOT contiguous**, because `ga_topo.py` hoists the callees above `main`, so "cut from `def g` to end of file" once deleted 618 lines of port. `ga_topo.py` is a callee-first reorder that also hoists every `type`/`import` block (without which the file keeps whichever types happened to sit above the first def and silently loses the other fourteen). `ga_plus.py` drives `bend --check-only` and adds the `+` for the ONE error class this file keeps hitting (`x (consumed more than once)`), stopping loudly on anything else so a real type error is never papered over. |
| `.agents/slop/ga_gate.py` | diffs a `bend` run against the oracle by diffing whole `name=[value]` ROWS, never row NAMES -- a name-comparing harness reported 0 moved rows for all 30 mutations of the autogen unit and all 68 of the ops_rdma one. The regex is DOTALL and lazy because six rows carry a whole generated Python file in one value. It also **refuses to score a row whose name is not an oracle row name**, so a hand-added row cannot pass unnoticed. |
| `.agents/slop/ga_mutate.py` -> `ga-mutate.txt` | 41 one-token mutations of `renderer/amd/generate.bend`: **40 move gate rows**, and the one that does not is a documented deliberate no-op (`NULL` is in BOTH `_ALL_DSL` and `_DSL_REGS` upstream, so the union cannot see either copy dropped). `--one M9` runs a subset. **It retries `the machine stack overflowed` eight times**, because the PRISTINE gate-green file died with it on 2 of 12 back-to-back runs under load and on 0 of 8 when idle; a single-shot harness reports a spurious failure about one run in six. The mutant runs IN THE ORIGINAL'S DIRECTORY (a `$TMPDIR` copy cannot resolve `import Base`), and each anchor is asserted to occur exactly once so a stale edit target is an error rather than a silent no-op. |
| `.agents/slop/ga_probe.sh` | runs ONE gate row with every other removed, which is the only way to bisect a fold: `do IO<Unit>:` evaluates its whole body, so a hang or an overflow anywhere hides behind any earlier row. |

## WebGPU call layer (`runtime/webgpu_call.*`)

- `bend FILE -o FILE.mjs` — the ES-module emitter. Every NON-IO def, all on
  `default` under its own name (`M["Cs.order"]`, never `M.Cs.order`); `do IO<>`
  blocks are dropped, which is what lets a pure Bend file drive JS.
- `bend FILE -o FILE.js` — the whole program plus the IO event loop; run with
  `bun FILE.js`. Used for the `ops_webgpu.bend` second lane.
- `bend guide effects` — the custom-effect protocol. Read before writing one; the
  JS side is FD-shaped and there is no promise arm.
- Headless Chrome + CDP, for a real `navigator.gpu`:
  `--headless=new --enable-unsafe-webgpu --use-angle=metal --no-sandbox
  --remote-debugging-port=9222`, driven by `.agents/slop/probe/cdp.mjs` via
  `.agents/slop/probe/real.sh`. Chrome does NOT survive the shell that launched it
  here, so `real.sh` starts and kills it in one invocation.
- `.agents/slop/probe/serve.py` — a static server on :8731, because `file://`
  blocks a module importing a relative `.mjs`.
- The WebGPU IDL mixes string enums and numeric bitmasks; WC4 in
  `.agents/slop/notes/bend2-constraints.md` has the measured table.

## Tree verdict (bucketed by cause, not pass/fail)

- `.agents/slop/tree-verdict.py -P 12` — sweeps every `.bend` under `tinybendygrad` +
  `examples` and reports `green` / `no-main` / `no-rows` / `foreign-code-surface` /
  `proof-in-progress` / `broken-here` / `broken-in-import` / `no-verdict`. Exit 1 on a real
  defect or a dead substrate. `--json`, `--only SUBSTR`, `--root DIR` (point it at a COPY for
  a negative control). Read `.agents/slop/tree-verdict.md`.
- `.agents/slop/one.sh <file> <outdir>` — the per-file primitive: check-only + run, first
  diagnostic line as the verdict, modal row count over repeated runs. It NEVER reads bend's
  exit status, and it is the only place the retry rule lives.
- `--check-only` exits 1 on a clean file, and WHICH STREAM the verdict arrives on depends on
  the verdict: success prints to stdout, failure to stderr. A harness reading `check.err`
  alone calls every green file dead.
- A compile error propagates and bend's `Location:` block NEVER NAMES THE FILE, so a red
  count is not a defect count — one planted `def` in `LAWS/spec.bend` reds 87 files. Attribute
  by the offending source text, walking back past a blank marked line.
- **`tinybendygrad/runtime/support/elf.bend`'s ROW COUNT IS NOT A CONSTANT — and the failure
  modes are THREE, not one.** 2026-10-04, full artifact
  `.agents/slop/runs/elf-run-353rows-2026-10-04.txt`:
  - **353** proof rows on a complete run (stdout lines carrying `=`, less bend's own
    `bend 2.0.35 is available...` line) — **which REPRODUCES the 353 already recorded here.**
  - **331** on another run with no edit between. Unreproduced, still unexplained, and still a
    reason not to quote a single run.
  - **246 — RETRACTED, and it was MY error, not the file's.** I read the row count off a
    background `bend` job that was **still writing**: four reads of one file gave 239, 246, 354
    and 355 lines. **246 was a partial read of an in-flight run.** Reported here because the
    retraction is the useful part.
  - **Rule-dependence is real but smaller than it first looked:** counting `=`-bearing lines
    reads 354, because my own `done rc=0` shell echo carries an `=` and is not a proof row.
    **Exclude the harness's own output or you will count your marker as evidence.**
  - `--check-only` prints `ALL PROOFS CHECK` and **no row count at all** — only `bend <file>`'s
    stdout carries one (`.agents/slop/runs/elf-checkonly-2026-10-04.txt`).

  **Three rules, and the third is the one that bit me: (1) never quote a row count without the
  RULE that produced it; (2) never quote one from a job that may still be running — wait for the
  file's own completion marker (`elf-done=1`) or for the process to exit; (3) a count that grows
  while you watch it is not an unstable measurement, it is an UNFINISHED one.**
- **THE NAMING GATE'S `VERBATIM` COUNT IS NOT A CONSTANT EITHER — 283 vs 278.** Six runs 14 s
  apart were byte-identical md5 at **283**; a window at 19:34-19:36 read **278**, bracketed by
  283, with files mid-write. **283 is a SETTLED-SUBSTRATE reading and 278 is a
  SUBSTRATE-IN-FLUX reading; neither is a property of the port.** Any ledger sentence of the form
  "N VERBATIM of M" must name the two values and the substrate state, or it is a stale count
  presented as fact. `naming-gate.py` reports `VERBATIM … 283 17.9%` on stdout, and a parser
  that reads only the leading integer drops the `QUALIFIED` column silently.

## Pin vs xd1/head (2026-10-03)

- `.agents/slop/pin-tree-oracle.py` — which tree each wired oracle imports, and the
  GUARD 3/2/4 verdict under the pin (`xd1/pin` = `6c3d401cf324`) and under `xd1/head`.
  Forces a tree with a `meta_path[0]` finder so a child cannot keep its own insert.
  Never patches a live tree. Report: `.agents/slop/pin-tree-oracle-report.md`.
  Snapshots: `runs/pin-tree-oracle/`.

- `.agents/slop/arange-ucache/` — the ARange ucache collision. Probes
  `probe-fields-3.bend` / `probe-variant-3.bend` show a third field and a new
  variant are both non-local. `baseline.txt` / `after.txt` / `reverted.txt` /
  `comment.txt` are the before, after, comparison-reverted, and comment-only
  lanes. `importers-all.txt` is the 63-importer row count.

- `.agents/slop/oracle_py.py` — WHICH PYTHON RUNS THE CPYTHON ORACLES, pinned in one place.
  `rebase-gate.py` used to spawn its lanes with `sys.executable` and fetch its plan with a
  hardcoded `sh("python3", ...)`, so the gate's verdict was a function of the LAUNCHER:
  `.venv/bin/python tensor-gate.py` printed 30 rows and `python3 tensor-gate.py` printed 0
  with `ModuleNotFoundError`, because the editable tinygrad install exists only in `.venv`
  (3.12) and PATH's python3 (3.14) has no `.pth`. Three contradictory published claims came
  out of that in one day. Now the lanes, the plan fetch and the verifier all launch under
  `.venv/bin/python`, and `rebase-gate.py --json` carries `oracle_py` / `tinygrad` / `python`
  so a published number is traceable to the interpreter that produced it. `probe()` runs the
  import under `-I` with `cwd=.agents/slop`, because `python3 -c "import tinygrad"` from the
  repo root SUCCEEDS spuriously — `sys.path[0]` is `''` and a `tinygrad/` sits in the cwd, so
  the only honest check is one the cwd cannot answer. An unresolvable interpreter **refuses
  with exit 2** rather than reporting zero rows; `ORACLE_PY=` overrides the pin and is probed
  the same way. Control: `python3` and `.venv/bin/python` on the same port now produce
  byte-identical verdicts.

## The E2E lane (`.agents/slop/e2e*`) — the port COMPUTES

`runs/e2e/README.md` is the writeup. Ledger only:

- **`.agents/slop/e2e.sh`** — THE ONE COMMAND. oracle -> pure bend -> GPU -> gate.
  Prints `PASS`/`FAIL`, exit 0/1. Retries the bend run up to 8 times and checks the
  ROW COUNT (bend stack-overflows ~1 run in 20 and prints nothing, and a 0-row result
  is indistinguishable from "not started"). Reads the first diagnostic line, never the
  exit status.
- **`.agents/slop/e2e_mm.py`** — the ORACLE and the fixture GENERATOR. Traces a real
  `(A @ B) @ C` out of tinygrad on `DEV=CPU`, takes tinygrad's **own WGSL** for each of
  the two launches, PARSES the bindings out of the shader, and writes both
  `runs/e2e/e2e-mm-oracle.json` and `.agents/slop/e2e_mm.bend`. **Every literal in the
  `.bend` came from a call here.** Two renderer shims, both quoted from
  `xd2/trace_forward.py`: the float4 STACK (`wgsl.py`'s `supports_float4` is read in one
  place and a STACK still reaches `string_rewrite` with `float4 = None`). The FDIV shim
  is deliberately NOT applied — a matmul chain has no division, and shimming it would
  widen the fixture past the program under test. `.venv/bin/python` only.
- **`.agents/slop/e2e_mm_run.mjs`** — the GPU lane. Emits `bend -o` for both the program
  and a **fresh** `webgpu_call.mjs` into `.agents/slop/e2e/`, serves it, drives headless
  Chrome-stable over CDP. Imports the port's own `xd2/cdp.mjs` and `xd2/serve.mjs`;
  `xd2/sh.mjs` is new and is three lines.
- **`.agents/slop/e2e/index.html`** — the page. Three imports and one `walk`. Its one
  addition is the constructor-tag normalisation (rules C1/C6), guarded by injectivity
  and by a check against the driver's own source text.
- **`.agents/slop/e2e_mm_gate.py`** — 40 rows, diffed by whole `name=value` line. No
  typed constants: every row is an identity between two measured counts or between the
  port and `e2e-mm-oracle.json`. Six `mm_power_*` rows prove the equality can fail.
- **`.agents/slop/e2e_negctl.sh`** — the negative control. `$TMPDIR` copy with the
  relative layout intact (`tinybendygrad/` copied = 11 MB; `bin/` and the 227 MB
  `references/` SYMLINKED). Three breaks, all caught.
- **`.agents/slop/e2e_gpu_probe.mjs`** -> `e2e-gpu-probe.txt` — is there a device that
  **computes** here? Dispatches a kernel and reads it back, because
  `requestAdapter()` resolving is a name. **This file's first expectation was wrong**
  (`?? 0` for the wrap instead of the shader's wrap-to-0) and disagreed with a correct
  GPU on 7 of 8 — which is the rule about transcribing an expectation, caught by the
  device. chrome-stable works headless and headed; **chrome-for-testing reports
  `"gpu": false` for every flag set tried**, including `--enable-unsafe-webgpu`.
- **`.agents/slop/e2e/cc-no-fma.sh`** — a `CC` wrapper adding `-ffp-contract=off`, so
  the CPU's contraction is a MEASUREMENT rather than an assumption. The flag must come
  FIRST: `compiler_cpu.py`'s argv ends in `- -o -`, and a flag appended after the stdin
  marker does not reach clang's option parser.

## The `uop/fold.bend` oracle and mutation harnesses (2026-10-04)

Four scripts, all `.venv/bin/python`, all in `.agents/slop/`. **The fold has no oracle of
its own until this session — it is the only file in the port whose 300 rows were pinned by
hand-written expectations.** Two lanes are the contract everywhere: `./bin/bend <file>` and
`<oracle>.py > py.txt`, then `diff` of the row names.

- **`oracles/fold-rng-oracle.py`** — the CPython oracle for the RANGES fold
  (`UOp._ranges` ops.py:483, `UOp.ranges` ops.py:497). 12 rows, one per fixture, spelled
  `rg_<tag> ranges=[R(0),R(1)]`. A range is labelled by the ints of its innermost
  `axis_id` and NEVER by an index: CPython's interning order is not the arena's, so a
  number neither lane means the same thing by, and the NESTING (`arg[1:]` makes CPython's
  `axis_id` `((0,),)` where the arena's `ARange{ids}` is `[0]`) is ops.bend's recorded wall
  and is read one way on each side. `ABSENT` is where the two lanes DISAGREE by design: a
  DEFERRED op has no `ended` list (the fold's `Derived` field), and CPython answers.
  Prints its own DIVERGES block, as `fold-mvt-oracle.py` does.
- **`.agents/slop/fold-rng-mutate.py`** — 19 mutations of the ranges fold and of
  `is_image_shape`, 15 of which move rows. **IT RUNS IN A SCRATCH TREE with `ops.bend`
  PINNED AT `master`**, and that is not a style choice: `uop/ops.bend` and
  `uop/symbolic.bend` are owned by two other agents and went transiently uncompilable three
  times while this table was measured, so a harness editing the working tree in place is a
  race with two writers, and a baseline captured from a different state makes every row look
  as if it moved. **Its row parser is `re.match(r'^([^ =]+)[ =](.*)$')` rather than the
  sibling's `if ' ' in line`**, because this file prints BOTH `name=value` and
  `name value=...` and the sibling's test cannot see `img_shape=True` at all. Reported
  there, not fixed: that file is not this unit's.
- **`.agents/slop/fold-lift-mutate.py`** — the `_min_max` op table's 35-entry table. The
  control whose lesson this unit's harness copies: four "neutral" mutations there were NOT
  no-ops and took 276 rows with them, and they were REMOVED rather than counted, because a
  "moved every row" line in a mutation table is a harness bug wearing a result's clothes.
- **`oracles/fold-mut.py`** — the movement arms' 14 mutations, both lanes.

### `sh .agents/slop/ops-501-gate.sh` -- the ops.py:501-1928 unit's three-lane gate

The CPython lane is `.agents/slop/ops-501-oracle.py` and the mutation table is
`.agents/slop/ops-501-mutate.py`. It is a SEPARATE gate from `ops-gate.sh` rather
than more rows in that one, for one reason: `ops-gate.sh` diffs a byte stream whose
row ORDER is the contract, and this unit's 82 rows are a different unit with a
different fixture arena. `ops-oracle.py` carries a `#bend_only_s5=` entry so
`ops-gate.sh` filters them, with the reason written down -- filtered, not un-gated.

TWO THINGS IN IT THAT ARE WORTH THE REUSE.

1. **THE ROW-NAMES DIFF IS SEPARATE FROM THE VALUES DIFF.** A row that exists on
   one side only is a different failure from a row whose value differs, and a
   value-only diff hides the first inside the second. The gate diffs the sorted
   `name=` prefixes first, then the values. It is three extra lines and it is what
   turns "75 rows" into "the same 75 rows".

2. **`ops-gate.sh`'s `sed` for the filter was `[a-zA-Z_]*` and a family name with a
   DIGIT in it was silently DROPPED** -- so the filter missed its rows and the gate
   failed on rows that were supposed to be filtered, with an error that pointed at
   the rows and not at the filter. Widened to `[a-zA-Z0-9_]*`; a no-op for every
   name already there, none of which has a digit. If a new `#bend_only_<name>` ever
   fails to filter, LOOK AT THE CHARACTER CLASS before looking at the rows.

### `.agents/slop/afloat-patch.py` -- reconstructing an edit into a file another unit overwrote

A concurrent unit wrote a divergent 7230-line `ops.bend` over the shared working copy,
taking both this unit's four `afloat_*` rows and the earlier `ABlob` false-intern fix
with it. This script rebuilds the lost side from a **HASH-ASSERTED** base
(`ops-blob-fixed.pristine.bend`, md5 `d5c1174e...`), re-applies three anchors, and emits
`afloat-ops-bend.bend` + `afloat-ops-bend.patch`.

It **REFUSES** rather than emitting a wrong patch in three cases: the base md5 is not the
one this unit started from (somebody refreshed the snapshot), an anchor matches zero or
more than once, or **the base still compares a blob by LENGTH** -- because then the patch
would apply on top of the false-intern fix rather than after it. A snapshot somebody else
can refresh is not a base; a snapshot with an asserted digest is.

The reconstruction was **proven, not assumed**: in a mirrored subtree it is
`ALL PROOFS CHECK` and its row output is byte-identical to the `blobrows/af-after`
snapshot taken from the file that had been green. See `## A-4` in
`notes/bend2-constraints.md`.

### `.agents/slop/afloat-probe.py` -- what CPython's ucache does with a BARE float arg

Read-only, one file, no gate. It exists because `ops.py:201`'s key holds the element
and **each element carries its own `__eq__`**, so "is this the right comparison" is
unanswerable without asking CPython which Python class is in the key. `TG_TREE`
selects the tree and the answers are IDENTICAL on the vendored pin and on
`.agents/slop/opstree`, which is itself part of the finding.

The measured answer is that the two float classes are opposite rules:
`dtype.py:8-23`'s `ConstFloat` overrides `__eq__` and `__hash__` ("distinguishes
-0.0 from 0.0 and where nan == nan"), so a CONST's arg compares BITWISE and
`eq_const.CFloat` is right; a bare `float` overrides nothing, so `hash(-0.0) ==
hash(0.0)` and CPython **interns `0.0` with `-0.0` (1 node)** and keeps two DISTINCT
same-payload NaNs apart (2 nodes), which is IEEE and makes `eq_arg.AFloat`'s
`F32.is_eq` right. Changing it to `F32.bits` inverts both cells -- it is a double
regression wearing the costume of a fix.

**ONE CELL IS DELIBERATELY UNGATED.** The same NaN *object* twice interns in CPython
(1 node, `lookdict` short-circuits on pointer identity) and `F32.is_eq(nan, nan)` is
False. That is a fact about Python object IDENTITY and not about the float, so a row
for it would have to lie about the comparator or about CPython. It is measured here
and printed nowhere else.

### `sh .agents/slop/ops-gate.sh` -- the two red-at-rest lanes it stopped hiding

`ops-gate.sh` is the three-lane gate for `uop/ops.bend` and it was **RED ON THE
PRISTINE TREE**: its CPython lane had none of the five `cfun_*` rows the Bend prints,
so the byte diff reported `0a1,5` on every run and `TODO.md:600` recorded it as
pre-existing. Those five rows are **gateable, not bend-only** -- `CustomFunction` is a
frozen dataclass at `ops.py:1395` and `UOp.custom_function` at `ops.py:1259`, both
present on BOTH selectable trees, answering `True/True/True/sel_registerName|u64/
sel_registerName|void` identically on each. They are now a shared `# 0bis0` block at
the HEAD of `ops-oracle.py`, in the Bend's print order, with no `#bend_only_` reason:
**denominator 94 -> 103 shared rows, three lanes byte-identical, exit 0, on both
trees.**

The general lesson, and it is the one in the notes: **a lane must never be wired
having been seen go red**, because a gate that is red at rest trains its reader to
read red as normal. `sh .agents/slop/ops-501-gate.sh` is red for the same reason and
is still red -- 101 `s5_*` rows in `ops-501-oracle.py` against 82 in the Bend, 19
families (`s5_copy_*`, `s5_devrange_*`, `s5_ga_*`) that only the oracle has. That
oracle is at its committed state, so it is red AT REST and it is another unit's file.

## Unobservable-row census (2026-10-03/04)

Five tools, all read-only against the ports; the only file one of them *writes*
is a frozen copy it owns, md5-asserted against the live tree first.

| tool | what it is | what it found |
|---|---|---|
| `.agents/slop/unobservable-census.py` | static blind-transposition census over every committed oracle; `--handtyped`; `--countgate` | 17684 rows / 10 ORDER-DEAD / 10374 order-weak / 14136 blind transpositions / 111 sibling-blind; 290 hand-typed rows; 1 count-only gate |
| `.agents/slop/commute-detect.py` | frozen-copy harness; swaps commutative srcs and same-shape `List.append` args; hit rate over APPLIED patches only | population 2 comm + 2 append sites over 7 ports; `late/linearizer` 0/69 moved |
| `.agents/slop/unobservable-gr-oracle.py` | answers `u` vs `rebuilt` by CALLING tinygrad (10-fixture sweep + pattern introspection) | 10/10 identical => THEOREM closed upstream; the SINK-identity defect |
| `.agents/slop/unobservable-gr-probe.bend` | THE FIXTURE. `gr.sink_srcs` = the op+slot sequence the engine RETURNS | 3 distinct answers over 3 behaviours => the row MOVES |
| `.agents/slop/unobservable-gr-move.py` | runs the probe under 3 port behaviours on an md5-asserted frozen copy | proof of movement; prints `PATCH DID NOT APPLY`, never a count |

Harness rules learned here and worth keeping:

* a patch that does not apply is **not a zero** — `applied` is its own column and
  a port with zero applied sites reports **NO MEASUREMENT**, not 0%;
* every run needs a **pre-flight** (each port prints rows from the frozen copy
  before any mutation) and a **port-scoped end-of-run md5 re-check**, because
  two agents were mid-edit in `uop/ops.bend` and `uop/fold.bend` for 15 minutes
  of the first run;
* the freeze asserts md5 per file BEFORE mutating, never after.

## 2026-10-04 — the two-oracle investigation for `codegen/decomp/dtype.bend`

| file | what it does | the number it establishes |
|---|---|---|
| `.agents/slop/dd-truth.py` | ONE run of port + `dd-oracle.py` + `dtype-oracle.py`, all parsed with **`rebase-gate.py`'s own `rows()`**; asserts the filter identity; decomposes the disagreements; `--control` runs the mutant | port 174 / dd 416 / dtype 351; **19 vs 1**; 18 not gated; 242 oracle rows unemitted |
| `.agents/slop/dtype-oracle-MUTANT.py` | `dtype-oracle.py` with `SKIP = set()`, one `diff` block, nothing else | **1 → 19.** Proves the count is a function of SKIP |
| `.agents/slop/dd-audit.py` | wraps every entry point of `tinygrad.codegen.decomp.dtype` in a counting proxy and RUNS both oracles | `l2i` 1341 / `f2f` 18 / `f2f_clamp` 26 calls; **0** hand-derived arithmetic. Neither oracle re-implements |
| `.agents/slop/dd-probe.py` | measures decision 1's projection, and re-runs `lg5`'s cone with it OFF | **281** promotion CASTS deleted; `lg5k` is NOT an artifact |
| `.agents/slop/dd-coverage.py` | the coverage question with NO bend lane, so it survives a cold substrate | **57** of 65 SKIP names are creation-order, **8 are bare answers** |
| `.agents/slop/dtype-oracle-truth.md` | the argument, with per-family mechanism and CPython line citations | the recommendation to the gate's owner |

Harness rules learned here:

* **a lane must print its own denominator as rows** — `dtype-oracle.py` emits five
  `dtype_oracle_*` rows named so they can never collide with a port row, and therefore can
  never be compared or silenced;
* **count a filter's gap from the STREAM, never from `len(SKIP)`** — a stale SKIP entry
  silently inflates it, which is the 82-stale-`{}`-cache failure in another costume;
* **empty the filter to test the filter** — the cheapest possible control for any
  filter-shaped oracle;
* **load the gate's parser, do not write one** — a second parser is a second opinion
  nobody checked;
* **assert a filter's identity as `FILTERED == PRODUCED - SKIP`**, because the near-miss
  `(A & B) - C` is vacuous and printed a confident "NOT a pure filter" on a pure filter;
* **a 0-row port lane is a cold substrate until proven otherwise** — `ops.bend` was written
  14 s before a run and broke the typecheck, and every count-only harness read that as
  "not started". `dd-truth.py` refuses to report a verdict on 0 port rows.

## The mutation-table harness (`codegen/decomp/dtype.bend`, 2026-10-04)

| tool | what it is |
|---|---|
| `.agents/slop/dd-mutate.py` | the harness. Builds a MIRROR (`git archive <PINNED REV> tinybendygrad` + the FROZEN `dtype.bend`), asserts the mirror reproduces the snapshot's digest, runs 3 controls + 36 mutations in parallel over per-worker tree copies, and diffs WHOLE `name=value` lines. **Writes the live tree never.** `probe_substrate()` exits unless the unmutated mirror reproduces the baseline's exact shape, and ANY control that is not `SAME` aborts with no table written. Pins: `FROZEN_SHA1` and `TREE_REV` at the top of the file. `DD_WORKERS` (default 6). |
| `.agents/slop/dd-mutations.frozen.bend` | the pinned snapshot, `73b0e1e7…`. **The live file is a concurrent unit's** and moved under the run. |
| `.agents/slop/dd-gate-base-172.txt` | the 172-row baseline the table is diffed against. |
| `.agents/slop/dd-mutations-report.md` | the classified table: 28 MOVED, 5 THEOREM with a proof each, 1 REQUEST with the fixture named, 2 DID-NOT-COMPILE. |
| **`.agents/slop/zero-classify.py`** | **A ZERO CLASSIFIES ITSELF: five verdicts and no sixth** — `UNREACHABLE+proof` / `PORT-DEFECT` / `PATCH-NOT-APPLY` / `INVISIBLE-to-reader` / `NO-MUTATION-WRITTEN`. `MOVED` and `DID-NOT-COMPILE` are counted separately (they are not zeros), and **RULE C controls are excluded from the tally** (their `0 rows` is the required outcome). Two string questions decide a zero: **Q1 WRONG+JOINED** — does a DISAGREEING row carry CPython's answer *at this site*? **Q2 VISIBLE** — does CPython's answer at the site appear in *any* row? **WRONG before VISIBLE.** **Q1 MUST BE A PER-SITE JOIN, NOT A FAMILY VOTE**: a coarse family lets every disagreeing row in it act as an alibi for every site under it. Driven by three declarations — `--aim` (id→def), `--family` (row regex→family), `--site-answer` (site→CPython's measured answer) — so it never guesses, and a site with no answer is refused as UNDECLARED rather than guessed at. **`inside()` tests the UNDERSCORE, not the dot**: Bend namespaces sub-defs as `l2i_shl.hi`, and a `startswith(fam + ".")` test classifies every `l2i_*` site as belonging to no family. **REFUSES an unrecognised MEASURED verdict** so "unrecognised" cannot become a sixth bucket that reads like a pass. `--verdicts` prints the five. |
| `.agents/slop/zero-selftest.py` | proves the PORT-DEFECT / INVISIBLE-to-reader discrimination **on the real snapshots**: `l2i_shl.hi` against the defective `73b0e1e7` reads `PORT-DEFECT` (`lg9p` says `BITCAST(WHERE)` where CPython has `BITCAST(OR)`), an answer in no row reads `INVISIBLE-to-reader`. Same site, same rows, different snapshot, different verdict. Exits 1 on any failure; every input is a file this project produced by running something. |
| `.agents/slop/zero-audit.py` | audits **every** mutation table in `.agents/slop` and prints **THE DENOMINATOR** — mutations recorded vs zeros, controls excluded — because "unmoved" conflates *no mutation was written* with *written and it did not move*. Measured: 487 mutations / 15 tables / 30 zeros, of which **25 are unclassified**. A table whose pattern matches nothing is printed **UNPARSED, not skipped silently**. Also **greps RULE D at the branch that PRODUCES the number** — a report file cannot say which branch produced its own figure — and found a live violation: `ops-python-mutate.py` prints `\| {mid} \| (pattern not found) \| 0 \|` and the committed record carries it. |
| `.agents/slop/dd-zero-{aim,family,site-answer}.tsv` | the three declarations `zero-classify.py` is driven by for `codegen/decomp/dtype.bend`: which site each of the 41 mutations is aimed at, which family produces each baseline row, and **CPython's measured answer at each site** (the join key). |
| `.agents/slop/dd-mut-proof.py` | proves a THEOREM by **renaming the enclosing def**: a rename cannot change semantics or break a type, so a rename that compiles proves nothing resolved the old name. Reports `REACHABLE-WAS` (bend refused, so a caller exists) or `THEOREM` (compiled, output byte-identical). Reads **stderr** to tell a refusal from bend's stack overflow, because both print nothing on stdout. |
| `.agents/slop/dd-mut-tether.py` | proves a THEOREM by **deleting the arm**: compiles and byte-identical ⇒ the arm was dead. The complement — deleting the *interceptor* and seeing the rows CHANGE — is what attributes the death to the interception rather than to unreachability (M06). |
| `.agents/slop/dd-mut-reach.py` | the call graph from `main` to every def. **Evidence, not proof** (a regex over source can miss an indirect use), but it names the 81 defs no fixture reaches. |
| `.agents/slop/dd-mut-deepen.py` | builds a 3-deep `dd_tree` printer (changes 28 baseline rows) and re-measures a mutation against it, to separate "the code does not run" from "the row does not print it". Bend has no mutual recursion, so depth is unrolled into `d1 → d2 → d3` in dependency order. |
| `.agents/slop/dd-mut-classify.py` | turns the measured `.tsv` into MOVED / THEOREM / REQUEST. It **refuses to emit a verdict with no proof kind behind it**, and a zero with no proof is a REQUEST by construction — there is no fourth bucket. |

Why the bake lives in the mirror and not the live tree: a bake catches a run killed mid-write, so
it is only meaningful for the tree that run writes. `git archive` carries only tracked files, so a
mirror can never inherit one — a bake in the live tree guards nothing and blocks every run that
mirrors it. `stray_bakes()` reports rather than deletes (another unit's mirror may be mid-run).

## The `.bend` CENSUS (2026-10-04) — one number, four definitions, and none of them is "the" count

Measured in the working copy during 2026-10-04. **The tree was being written throughout**, which
is itself the headline: four reads of one command gave 196,610 -> 196,743 -> 196,724 -> 196,821
lines before settling (then byte-identical, md5 `640487f2…` on the settled corpus), and the
`find` file count went **137 -> 138** when another unit landed a `.bend` mid-session, with four
files mid-edit by live agents. **A census taken while agents are writing is a sample.**

Read the PORT row as a **bracket**, not a point — the file count was rock-stable at 128 across
every reading while the line count moved, so the count of files is the trustworthy half:

| definition | `tinybendygrad` + `examples` | `tinybendygrad` alone |
|---|---|---|
| A. `find … -name '*.bend'` — **the published method** | **137-138 files / ~197.9k lines** | 136-137 / ~196.8k |
| B. A, git-tracked only (what a clone reproduces) | 133 / ~196.3k | 132 / ~195.2k |
| C. B minus scratch (`tree-verdict.py`'s `SCRATCH_RE`) | **128 files / 195,016-195,188 lines** | **127 / ~193.9k** |
| D. A minus B: untracked, gitignored scratch | 4 / 1,598 | 4 / 1,598 |

**State the SET and the RULE, then the number. "137 `.bend` files" without either is
unreproducible.** The published 137 was *not* wrong — it is `tinybendygrad` + `examples`, which is
what `bend2-constraints.md` §6 means by it.

**Do not discover `.bend` files with `glob('*.bend')`.** Python's `glob` will not let `*` consume a
leading dot, so root-level `glob.glob('*.bend')` returns `[]` while `.bend` sits on disk — and it
did, tracked, 1,890 lines, invisible to `find tinybendygrad`. `os.walk` + `endswith` (what
`tree-verdict.py` actually does, positions 86-93) sees everything. `find -name` also sees
everything. **A dot-named port file is the one thing that can hide from a glob.**

## Repo hygiene (2026-10-04)

| tool | what it is |
|---|---|
| `.agents/slop/stale-snapshot-detect.py` | finds `.bend` files that are a stale PREFIX of a sibling in the same directory — the shape an in-place mutation harness leaves behind. Prints the shared-prefix length, the ratio, and the tail divergence, because "most of the shorter file matches" is a judgement the reader makes. `--min-ratio` (default 0.70; `csprobe`/`cstyle` is 0.76). Run over `tinybendygrad` + `examples` it finds exactly one pair, so it is a cheap regression check on the tree. |
| `.agents/slop/hygiene-2026-10-04.md` | this pass's report: the root `.bend` duplicate, the glob proof, the corrected census, per-file scratch verdicts, and every stale number marked unstable. |

**The scratch that is in the tree, and the one that must stay.** 8 files match
`tree-verdict.py`'s `SCRATCH_RE`; 4 are untracked and already ignored. Of the 4 tracked:
`renderer/csprobe.bend` (774) is a stale snapshot of `cstyle.bend` and wants `rm`; `runtime/_p6.bend`
(4) and `uop/probe-bl.bend` (36) / `probe-f32.bend` (10) want `rm`; and **`uop/probe-mmcore.bend`
(471) MUST STAY**, because `.agents/slop/mm-mutate.py:17` names it `SRC` and `mm-gate.py:12` runs
it. **`.gitignore`'s "a broken probe in the source tree is a trap, not a fixture" is too broad as
written — the repo's own "DELIBERATELY NOT IGNORED" doctrine (*a cache-shaped path is not the
test; "a report cites it" is*) has to be applied first.** A `probe-` prefix is a shape; a citation
is evidence.

## Order-blind gates (2026-10-04)

Seven tools, all in `.agents/slop/`, all rerunnable, none of which needs the live
tree patched.

| tool | what it is |
|---|---|
| `order-lin-probe.py` | CPython-side src-swap probe. Rebuilds `late-oracle.py`'s `lin_fixture` with one src list permuted and prints the SAME 128 rows, so a diff measures the swap and not a second transcription. `--swap=add\|add2\|end\|range\|sink0\|sinkend\|sinkrev`, driven by `ORDER_LIN_SWAP=`. |
| `order-lin-sweep.sh` | the sweep. Asserts the probe's unswapped rows equal the committed `oracles/late-oracle.txt` FIRST (a probe that does not reproduce is a failure, not a run), then prints which rows moved per swap. Established that CPython moves 2/0/20/6/9/3/10 rows where the port moved 0. |
| `order-lin-cand.py` | scores CANDIDATE rows by how many swaps they can see, so the fix is chosen on measured movement. `DEGK` (out_degree key order) sees 4 of 7; `EDG` (the edge list) sees 7 of 7. **This is how `lin_edg` was chosen instead of argued for.** |
| `order-late-move.py` | THE PROOF. Nine mutations over `codegen/late/linearizer.bend` (seven src-swaps + two controls) and two over `regalloc.bend`. Imports `commute-detect.Frozen` rather than copying it, because a `$TMPDIR` scratch file cannot resolve `import ./../../uop/ops.bend`. Pre-flight prints rows from the frozen copy before any mutation; end-of-run prints `SUBSTRATE STABLE` or `SUBSTRATE MOVED`. |
| `order-late-gate.sh` | `late-gate.sh` with a substrate stamp on BOTH ends over eight `.bend` files, retrying through the ~1-in-20 stack overflow and through a concurrent agent. Prints `SUBSTRATE MOVED -- THESE NUMBERS ARE ABOUT A TREE THAT NO LONGER EXISTS`. **Fired once here and forced a re-run**, so it earns its 20 lines. |
| `order-gate-probe.py` | D5. Reads the six `pm_move_gates_from_index` pattern OBJECTS and renders a structural fingerprint (`UPat.src` is a tuple OF GROUPS, a group is a tuple of UPats or a bare name string, `None` is `allow_any_len`). Answers: root op 3 of 6 distinct, depth-4 shape **6 of 6 distinct**. |
| `order-verdicts.py` | the two verdicts. (1) resolves every `ops_bend` sibling-blind family's oracle VALUE ARGUMENT and classifies it CALL vs LITERAL, following one assignment including tuple unpacking and `for` targets: **98 of 98 CALL-derived, so INHERENT**. (2) the hand-typed-row sample: per-oracle counts and a `BELIEF?`/`CONTRAST` split, **224 not 290**, with the 66-row gap attributed to f-string row NAMES being invisible to `unobservable-census.hand_typed`. |

`order-lin-cand.py` is the one to copy first for any future "which row could see
this" question: it turns an argument about what a row *should* detect into a
table of what it *does*.

## MUTATION-ZERO VERBOSITY — the four tools that make a dead patch unable to read as a zero

| tool | what it is, and the one thing about it worth copying |
|---|---|
| `patch_not_apply.py` | **THE SHARED REPORTER**, and the only place the marker is spelled. `not_applied(note="")` for a count or verdict cell, `pipe(cells, width)` for a `\|` row, `fail(note="")` to ABORT. `pipe()` raises on a width mismatch, so cell-count parity is structural rather than a promise; `fail()` is an explicit `raise`, not `assert`, because `python -O` strips `assert` and a stale anchor is exactly what must not be optimisable away. `MARKER` is `zero-classify.py`'s `V_PATCH`, **queried** through that file's `--verdicts` flag and checked at import, so the two cannot drift without one of them failing loudly. |
| `not-applied-audit.py` | RULE D over harness SOURCES, never over reports, because a report cannot say which branch produced its own figure. Four assertions: **A1** the branch body must CALL the reporter (so an inlined literal is a failure, not a style nit), **A2** no emitted cell whose FIRST TOKEN parses as an integer, **A3** a `\|` row's width equals the enclosing scope's own rows with the branch EXCLUDED, **A4** the marker is in the queried vocabulary. `--dir D` audits another directory. **Use `--dir` against reconstructed pre-fix sources before trusting a green run** — an auditor that has only seen correct code has not been tested. |
| `false-zero-sweep.py` | The same question asked of the COMMITTED TABLES instead of the sources, and the answer comes from the producer's branch body. A row is `MEASURED?` (the producer can only write a count there), `UNMARKED`/`NO-GUARD` (the record cannot say which branch produced its own figure), or `ANCHOR-GONE` (the anchor is absent from the file the harness names TODAY, so the figure cannot be re-derived — a REPRODUCIBILITY finding, **not** a claim the number was wrong). Imports its predicates from `not-applied-audit.py` rather than re-implementing them; two copies of "what is a stale-anchor branch" is two answers. |
| `revision-ledger.py` | Which revision each committed table is valid for. Records **two** digests per table — the file it patches AND the baseline ROW SET — because a digest protects the MUTANT, not the REFERENCE: the `hi42` order swap (the exact M09 defect) leaves `shape()`'s three fields unchanged. Over 22 tables: 2 name a revision, 20 name none, 9 have a file digest, 5 have a row-set digest. |

The generalisable lesson, and it cost this pass two wrong rounds of its own: **discovery
keyed on the SHAPE of the `if` line misses every author who phrased it differently, and a
whitelist of variable names is a fixture list that is stale the moment someone calls a
variable `green`.** Broad discovery plus a real scope filter — the COMPARISON identifies the
guard, and a separate predicate asks whether that scope publishes a count anywhere — beats
narrow discovery plus a hopeful list. Both rounds are recorded as `## Z-3` in
`bend2-constraints.md` (position 18919).

### `ops501-*` — diagnosing a red-at-rest gate on a file another unit is editing

| tool | what it is for |
|---|---|
| `ops501-atrest.sh [REV]` | The `s5_` rows of a REVISION of `uop/ops.bend`, default `@-`. **The at-rest state is `@-`, not `@`** — in Jujutsu `@` IS the working-copy commit, so `jj file show -r @ f` and `cat f` are the same bytes. Asking `@` here reported GREEN 6/6 while `@-` reported 82 rows against the oracle's 101. Stages beside the real file (never `$TMPDIR`: `ops.bend:168` imports `./../helpers.bend`), asserts the digest, deletes in a trap. |
| `ops501-ctl.sh [REV] [TG_TREE]` | The three-lane comparison against a revision, printing **denominators and one-sided name sets**. `101 vs 82` is not a coverage statement; `101 | 82 | 82 shared | 19 oracle-only | 0 port-only | 0 disagreements on shared` is, and it eliminates the "different row names" hypothesis instead of assuming it away. |
| `ops501-names.py PY PORT` | The same three numbers, from two lane files. Calls `rebase-gate.py`'s `rows()` — do not write a second reader. |
| `ops501-agree.py PY BD BN` | AGREE / DISAGREE over whole `name=value` lines, **naming every disagreeing row** and every row present on one side only. |
| `ops501-plant.sh [REV]` | **The control a missing-row failure cannot supply.** Plants one op out of `UOp.getaddr.op`'s nine-op ladder in a staged copy; requires clean rc=0 AND planted rc=1, and asserts the live file's digest is unchanged. Measured: `ROW DISAGREE s5_ga_param: cpython=Ops.GETADDR/Ops.PARAM bd=Ops.PARAM`. |
| `ops-501-mutate.py` | 23 mutations, all moving the rows they name. **Stages `jj file show -r @` and never writes `ops.bend`** — the previous version did, and its `finally` restore would have permanently destroyed a concurrent unit's edit. Its anchors carry the `def` header: `case OpsPARAM{}: True{}` alone occurs 4 times in `ops.bend` and a 3-line window 6–62 times, so an unanchored replace edits a different ladder. |

### `graphcmp-*` — comparing GRAPHS (not printers) between the port and CPython

| tool | what it is for |
|---|---|
| `graphcmp.py` | The differ. `diff --graph NAME` is **the artifact**: one command, one argument, one `# VERDICT:` line, and a `# DENOMINATOR:` line above it. Nine graphs (63 nodes/side, 13 of 77 ops). Also `control` (each side against itself), `cross` (one graph against another, BOTH sides), `conf` (the three conflations), `dbg --levels` (across DEBUG on a fixed graph), `selfcheck`, `emit`. Compares on an 8-field normal form with `repr` **excluded from the equality decision**, plus `--equiv` for commutative-canonical agreement. `runs/graphcmp/D/README-D.txt` is the index; `.agents/slop/graphcmp-LIMITS.md` is the honest limits. |
| `graphcmp.bend` | The port side of the same wire format. **Imports nothing it could copy**: `graphcmp-dbg.bend` reaches `matmul_of`, `row`, `rows.of`, `chunk`, `i`, `us` through it rather than re-implementing the graph builder or the wire grammar. |
| `graphcmp-dbg.bend` | The DEBUG-level probe. Builds ONE graph and varies only `H.debug()`, reaching all seven gated sites through the port's own `*_dbg*` defs (`memory.py:59`, `allreduce.py:16`, `state.py:260`, `amdev.py:185/225/251/254`). Emits each site as ONE named row in the graph wire format so the trace diff is a first-class diff rather than an eyeball comparison. |
| `graphcmp-oracle.py` | The coverage denominator, tabulated: per graph the node count on BOTH sides, distinct ops, distinct arg atom letters, distinct shapes, distinct depths, and which ledger markers are LIVE. Emits both sides so a port-only op shows up as a per-side difference instead of being absorbed into an AGREE. |
| `graphcmp-dbg-oracle.py` | Whether CPython's own `DEBUG >= 1` site (`memory.py:59-60`) can be reached on this host. Measured **0 of 8 real graphs**, which is why `dbg` is a port-vs-port comparison and says so in its own output. |
| `graphcmp-run.sh` | Every artifact, one command. Stamps `rc=` into each output and compares the py and bend canonical files with `cmp`. |

Three findings from it generalise past this repo, and all three are in
`bend2-constraints.md` as `GC-1`…`GC-9` (positions ~19325–19445):

- **A field that reads equal because BOTH sides are wrong is worse than a field that is not
  compared.** `cdepth` was off by one against the port's `Arena.depth` on all four fixtures,
  and NO graph emitted before that day contained a RANGE — so both sides returned 0 and the
  field agreed. Only a graph that reaches the field finds that.
- **A length-counted wire reader that DROPS rows reports a smaller COUNT, which looks like a
  finding.** `unchunks` required a space between chunks; every graph field was a space-free
  atom so nothing caught it until a DEBUG line with spaces in it made the reader refuse the
  line and the lane print "0 trace rows".
- **A flag that reaches nothing is a comment with a command-line syntax.** This file had
  three: `--graph` (defaulted to the default), `--plant-side` (never read), `--bend-probe`
  (not reaching `emit`, the one command whose job it describes).

---

## FORM-BLINDNESS — the four instruments (2026-10-04)

The class every one of this round's six findings belongs to: **a tool that matches a
FORM cannot see the instance that lacks it.** The checkable form is
**spelling-invariance** — two texts that mean the same thing, written differently; a
reader that disagrees is matching a form. Rules `FB-1`…`FB-7` appended at the END of
`.agents/slop/notes/bend2-constraints.md` (positions ~19941–20057).

| tool | what it is |
|---|---|
| `.agents/slop/rowform.py` | The FORM-COMPLETE row reader (`any_row`, `blind_reason`) and the meaning-equal spelling battery every other tool is measured against. `--selftest` exits 1 on the four variants `rebase-gate.py:rows()` cannot see. |
| `.agents/slop/formblind-census.py` | Every selection predicate under `.agents/slop/`, extracted from the tool's own AST and RUN against the battery. `--denoms` (the denominators), `--detail TOOL` (every selector and the inference that put it in this subject language), `--floor` (how many real lane lines the shared reader cannot read). Output kept in `FORM-BLIND-TABLE.txt` / `FORM-BLIND-FLOOR.txt`. |
| `.agents/slop/formblind-audit.py` | 17 constructed variants. Each asserts the reader must produce the FORM-COMPLETE answer, and each carries a CONTROL reader that must NOT. `--corpus` repeats them against the real tree, twice, and compares. |
| `.agents/slop/substrate-audit.py` | The OTHER root cause: 4 instruments that are right about a form and wrong about the substrate. A census that reads FORMS cannot see these, so its FORM-COMPLETE verdict on one is silence, not clearance. |
| `.agents/slop/FORM-BLIND-SPOTS.md` | The ledger. Per-tool classification, the denominators, the measured floor, and what is still wrong and why it was not fixed. |

> **SNAPSHOT, AND THE UNIVERSE IS LIVE.** Other agents are adding tools while this runs:
> the census read **851 → 841 → 846** tools over one session and the lane count
> **771 → 834 → 835**. Every count below was read TWICE and the two reads compared, but a
> number that grows while you watch it is an **unfinished** one, not an unstable one. **Run
> `formblind-census.py --denoms` and `--floor`; do not quote these blocks from memory.**

MEASURED, this tree: **67 FORM-BLIND / 284 FORM-COMPLETE-ON-BATTERY / 490 NOT-A-SELECTOR
(unaudited, not cleared) / 166 delegating a reader, of 841 tools.** 9 tools call
`rebase-gate.py:rows()` and 156 fork a reader; that shared reader cannot read
**3,298 lines** inside the **835** `.txt` lanes it does read.

FOUND AND FIXED: `unobservable-census.py --handtyped` (**209 → 556** on a fixed file set,
329 rows it could not see, and 1 it reported that does not exist — it now delegates to
`handtyped-audit.py` rather than carrying a second reader) and `dd-band-census.py` §C (now
walks arguments over a stated callee set and prints its own denominator).

FOUND AND REPORTED, NOT FIXED: `rebase-gate.py:rows()` A1–A4 (another unit's file);
`wire_parse.read_fresh_cache` returning `({}, 'fresh')` for a crashed lane (three
consumers, two not mine); `cstyle-gate.py:rows_shipped`, whose docstring claim of being
`rebase-gate.py:rows()` "verbatim" measured false on four of six shapes.

---

## `uop/validate.bend` unit — the z3 out-of-bounds checker. Appended 2026-10-04.

**`z3-solver` 4.16.0.0 IS ALREADY INSTALLED** at `/opt/homebrew/lib/python3.14/site-packages/z3`
(homebrew python 3.14.6; `python3 -m pip show z3-solver` says "not found" and is WRONG — the dist
is not registered under that name, so **`pip show` is not a reachability test, `import z3` is**).
`tinygrad.uop.validate` imports cleanly and its own version gate at `validate.py:8` passes, so
`uops_to_z3` is callable. This retracted a recorded OPEN QUESTION whose stated cause was "z3 is
not installed". **No dependency was added; the constraint held.**

Three new instruments, all in `.agents/slop/`, all reading `rebase-gate.py`'s `rows()` by path
(a copy would be a second reader, and `agent-core.md` records a name-comparing harness reporting 0
for all 68 mutations in one unit):

| file | what it is | how to run |
| --- | --- | --- |
| `validate-oracle.py` | the CPython lane; calls `uops_to_z3` + `solver.add(z3_mask)` on validate.py:92-95 verbatim, plus `validate.py:16`'s width expression, `range_str`, `z3_alu` and a 120-pair comparison-printer table | `DEV=NULL python3 .agents/slop/validate-oracle.py` |
| `validate-gate.py` | both lanes over the shared row names; prints the DENOMINATOR | `DEV=NULL python3 .agents/slop/validate-gate.py` |
| `validate-mutate.py` | 11 mutants run through BOTH lanes, so a row that moved TOWARD CPython is distinguishable from one that moved away; restores from memory and asserts the md5 | `DEV=NULL python3 .agents/slop/validate-mutate.py [--only M1,M2]` |
| `mask-probe.bend` | the `Arena.at`-based probe that located the stale-arena defect (VZ-3/VZ-4) | `./bin/bend .agents/slop/mask-probe.bend` |

Current measurement: **port 155 rows, oracle 364, shared 138, agree 123, disagree 15 (89.1%).** Of
the 11 mutants, 10 move rows AWAY from CPython and 1 (M10, `range_str`'s axis-id separator) moves
nothing — a declared blind spot, because every fixture has a single axis id and no multi-axis row
exists. Bend 2.0.34 via `bin/bend` (a 2.0.35 update is offered; not taken mid-session).

z3's own artefacts, all measured and all of them the reason two rows stay red: the pretty-printer
wraps long terms at a position **of its own choosing** (so a whitespace normalisation cannot be
undone), and `z3.FreshInt` appends a **per-`z3.Context`** counter -- `invalid_shift!0` -- which
resets because `validate_index_with_z3` builds a fresh `Context` per call.

`.agents/slop/notes/bend2-constraints.md` section `VZ-*` (appended at the END, continuing from
`FF-*`): VZ-1 a row shape nobody reads is not a row; VZ-2 z3 has no printer reorientation, the AST
does, and Python's reflected operators put it there; VZ-3 `Arena.at` is the only interning test;
VZ-4 a fixture that mints its own gate must build the sink in the arena AFTER the gate; VZ-5 a
`Bool` head-flag drops the first list element (found three times); VZ-6 a constructor-matching def
is the most expensive kind of no coverage; VZ-7 `m>0 and m&(m-1)==0` ≡ `m!=0 and m&(m-1)==0`;
VZ-8 `String.concat` consumes each name and `+` does not raise the read count; VZ-9 `+` silences
"consumed more than once" without guaranteeing the value; VZ-10 a "cannot be adjudicated" claim is
a claim about the ENVIRONMENT and it expires; VZ-11 a new oracle must pin the inputs the port
transcribes by hand; VZ-12 a row NAME must not contain `=` (30 of this oracle's own rows collapsed
onto 10 names before the fix).

**THE GENERAL LESSON, and it is the one worth keeping: `agent-core.md` warns that an instrument
can return something other than its subject. Twice, this oracle did.** Once through a row name
containing `=` (VZ-12) and once through `norm()` inventing a space inside z3's line wrap, which
made the PORT look wrong when it was right. Both were caught by printing the RAW value as its own
row -- `#raw_and21`, `#raw_cmod4`, `#wrap_cmod4` -- and by noticing that a printed-row count
exceeded a parsed-row count. Neither would have been caught by an assertion of the form "the oracle
emits rows".

## `graphcmp` — a CANONICAL GRAPH NORMAL FORM both sides emit, and a differ over it

The one instrument in this repo that compares **graphs** rather than rows, and the one whose
limits file is the deliverable. Not a library: seven files, two commands — one to regenerate
all of it, one to measure whether the regeneration is reproducible.

| file | what it is | how to run |
| --- | --- | --- |
| `.agents/slop/graphcmp.py` | the differ. Emits a NORMAL FORM both sides produce — eight fields per node, `id op dtype shape depth tag arg src`, `id` reporting-only because the two arenas number differently — pairs by a structural `core`, and falls back to a dtype-erased `loose` key and then to full node dumps, so a difference is NAMED (`MISMATCH RESHAPE py#8 vs bend#8 shape py=(U,l0:4) bend=?`) rather than counted. `--equiv` is the commutative-canonical mode. `conf` runs the four conflations. | `env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py diff --graph NAME` |
| `.agents/slop/graphcmp.bend` | the port side. READS `uop/ops.bend` and `uop/fold.bend` and PRINTS; it edits neither and adds nothing to either. Each graph is built node for node into its own `O.Arena.empty()`. **Every bend-side graph in the corpus is hand-built, including the three program graphs** — `schedule/__init__.bend` DEFERRs `__init__.py:82-301`, so the port cannot build a schedule. | `./bin/bend .agents/slop/graphcmp.bend NAME` |
| `.agents/slop/graphcmp-p13-ops.py` | the raw CPython probe, and the answer to every coverage claim: does `Ops.GROUP` carry a `params` list (no), which Tensor op emits which NODE op, can two different symbolic dims be separated and by which field, what is a variable PARAM's slot, and the corpus-wide op/node/symbolic-dim/fan-in tally. **Everything is a CALL, never a transcription.** | `env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/graphcmp-p13-ops.py` |
| `.agents/slop/graphcmp-p14{,-b,-c,-d,-e}.py` | the round-three probes: **what a real SCHEDULED program actually contains**. Q: does `schedule_linear` + `full_rewrite_to_sink` reach LOAD/STORE (yes, 46 nodes); does `hcq_fence` reach BACKEDGE (yes, 25 nodes); **does the scheduler ever mint a GATED STORE, which is the only input to the tree's one `Ops.ENDIF` rule (0 in 9 programs)**; and does the real `pm_linearize_cleanups` turn one into IF/ENDIF (yes, 14 nodes). | `env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-p14d.py` |
| `.agents/slop/graphcmp-oracle.py` | the coverage census, per graph and corpus-wide, with the PER-OP NODE COUNTS that are the denominator for every op claim. Carries **three assertions of its own** (`# ORACLE SELFCHECK:`), which is where defect 21 is kept from coming back. | `env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-oracle.py` |
| `.agents/slop/graphcmp-run.sh` | every artefact, one command. 16 graphs, five controls, cross, seven plants, the ordered/equiv split, the conflations, the DEBUG sweep, five stability pairs classified into **three** outcomes (identical / differ / **one side is a 0-row failure**), the fired 0-row guard, and a byte-identity step that **counts bytes on both sides before comparing**. Every output is written to a dot-named temp and `mv`d into place, so a run killed mid-write cannot leave a truncated file. Its summary counts every step — **a step that fails silently is not a step whose failure a gate can see**. | `sh .agents/slop/graphcmp-run.sh` |
| `.agents/slop/graphcmp-repro.sh` | **the reproducibility check, as a script rather than as a comment.** Waits for the substrate (`--check-only`'s FIRST LINE), accepts a run only if its own summary reads 16 graphs / 14 AGREE / byte-identical 14 / not-comparable 0 / selfcheck OK / census-rc 0 / **stable 5-0-0** / plants 7 / cross 1 / controls 5 / conflations 4 / oracle OK — the **negative** counts included, because a positive count alone cannot tell "it worked" from "it failed the same way twice" — then compares sha256 over non-blank lines. MEASURED **154 of 154 files identical**. It exists because the previous claim was backed by `find \| md5 -q`, which on macOS takes ONE file — and the corrected check found a real nondeterminism on its first run. | `sh .agents/slop/graphcmp-repro.sh` |

`E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py`

Current measurement: **16 graphs, 189 nodes per side, 1134 field-records, 34 of 77 ops, 7 of
the 8 commutative ops, 2 symbolic-dim nodes of 189 on BOTH sides, 14 of 16 `AGREE`
(`lin`/`loop` DISAGREE, each with a named measured port gap), 14 of 16 byte-identical, 5 of
5 stability pairs identical with 0 differing and 0 failed, 7 of 7 plants, 5 of 5 controls,
4 of 4 conflations, `cross` 1 of 1, both selfchecks OK.** `graphcmp-repro.sh` measures
**154 of 154 files byte-identical across two clean runs**. **A limit closed mid-round:** the
`ssimplify` wall that made `sym` DISAGREE was closed by the `fold` unit
(`fold.bend:1296`), which moved three pinned numbers in this harness at once — including a
health gate that then refused to measure a correct run, which is why the gate now reads
negative counts (`stable-failed=`, `stable-differ=`) rather than only positive ones.

**`.agents/slop/graphcmp-LIMITS.md` is the point of the whole thing** — sixteen defects this
instrument found in its OWN normal form by widening its corpus, and every limit it does not
close, each with the denominator that produced it. The two that generalise past this unit: **a
field that reads equal because both sides are wrong is worse than a field that is not
compared** (`cdepth` was off by one against `Arena.depth` on all four fixtures and nobody
could see it, because no graph emitted a RANGE so both sides read 0), and **a check that
reports `PASS` over an empty comparison looks exactly like a check that passes** (the
byte-identity step had been running `emit py` where `--side` is a flag, so both files were 0
bytes and `cmp -s` on two empty files succeeded, and four graphs read `BYTE-IDENTICAL`).

`.agents/slop/notes/bend2-constraints.md` section `GC-*` (appended at the END, continuing from
`FF-*`/`VZ-*`): GC-1 a 0-row side is a FAILURE on the harness side too, not only the port side;
GC-2 `rng` was the only I64 formatter that forgot the `l`, and it was invisible because
`ParamArg`'s fourth field had never been emitted in its `Some` case — the cost was a four-node
cascade with the cause in none of them; GC-3 fan-in needs TWO counts (in-edges and distinct
parents) because a node naming the same child twice inflates the first; GC-4 a prose claim
written to justify a fixture is a claim with no denominator, and this repo's three such
sentences about shared nodes were FALSE; GC-5 `COMM` holds bare names and `Ops.ADD in COMM` is
`False`; GC-6 a string literal split across lines inside an f-string is a `SyntaxError`; GC-7 a
killed run leaves PASS-shaped files; GC-8 numbering positions.

## MUTATION-TABLE ANCHORS AND PINS — the mutation-records unit (2026-10-04)

Four tools. The unit's subject is not a port; it is **the records that claim things about
ports**, so every tool here reads a harness with `ast` and never imports one.

| tool | what it is | the trap it closes |
|---|---|---|
| `.agents/slop/mutanchor.py` | THE shared static reader: `targets()` (which files a harness patches), `anchors()` (which literal each mutation looks for), `writes()` (and in which ZONE it writes), `zone()` (`IN-PLAY` / `SCRATCH` / `ELSEWHERE`). Resolves `os.path.join` chains, `Path(...)`, `dirname(dirname(__file__))`, and `__file__` itself. | `BEND` names the **compiler** in most of these harnesses, so a reader that takes it as the substrate makes all 44 of `ag-mutate.py`'s anchors read STALE when every one is present. `bin/bend` has no extension, and that is the discriminator. |
| `.agents/slop/anchor-audit.py` | Which anchors are stale, and which harnesses may be run at all. 49 harnesses, all `patch_not_apply` consumers. | **The anchor cell index is a property of the HARNESS, not a constant** — 1 in `wgsl-mutate.py`, 2 in `rf-arg-mutate.py`. `anchor_column` VOTES over the rows on the two-sided signal *in the file AND successor not in file*, because presence alone ties the ID column against the anchor column in 8 of 13 harnesses, and absence alone scores zero for every column once a table's anchors have all moved. `--only-stale` |
| `.agents/slop/table-pin.py` | rev + **FILE** digest + **ROWS** digest per table, 24 tables. `ROWS` is the row SET (names AND values, sorted) taken from the harness's own baseline file. | A digest protects the MUTANT, not the REFERENCE. Swapping `hi42`'s operands leaves `shape()`'s three fields identical, and RULE C caught that twice in one day. |
| `.agents/slop/pin-tables.py` | WRITES the pin into each table — or writes `PIN NOT WRITTEN -- UNSTATED. <reason>`. | **A pin is a claim about a run, so it may only be written for a run that happened.** Measurements are ARGUMENTS; there is no code path in the file that can decide a table reproduces, and an unstated reason is an error rather than a default. |

```sh
python3 .agents/slop/anchor-audit.py [--only-stale]     # stale anchors + runnable zone
python3 .agents/slop/table-pin.py                       # what each table describes
```

`patch_not_apply.py` gained **`not_a_program()`** (RULE B): the `DID-NOT-COMPILE` cell value,
spelled EXACTLY because `zero-classify.py` compares the whole cell and `sys.exit`s on
anything unrecognised, and taking no note argument so the suffix cannot be added by accident.
It is a different claim from `PATCH-NOT-APPLY` — the edit landed, the result is not a program
— and `ops-python-mutate.py`'s M17/M22 had been reporting the second as the first while
printing **170 moved rows that do not exist**.

**RECONSTRUCTED RECORDS:** `memory-mutations.txt` (70 mutations; the harness had exited 2 on
every run for a week because it treated `bend`'s upgrade notice on stderr as a failure) and
`wgsl-mutations.txt` (36; its table was a stale comment block inside `renderer/wgsl.bend`,
which is a `.bend` file this unit does not own, so the record lives out here).

## Lane provenance — which revision a lane compiled (2026-10-04)

| tool | what it is | why it is here |
| --- | --- | --- |
| `.agents/slop/phantom-run.py` | Reproduces the four-lane death end to end, and measures the blast radius per error class. `--event` / `--event-order` / default matrix. Fixture in `phantom-repro/`, shapes **copied** from `uop/ops.bend:807/1045/2442`. | **`bend` checks an IMPORTED module, so a lane's verdict is a statement about its whole import CLOSURE, and `bend`'s error names a def and a source line with NO FILE in it.** Four lanes died with an identical error naming a def in no file on the tree; this reproduces it and shows propagation is **eager** (20 lanes, 4 of 4 cells) — so the small blast radius is the **sequential sweep's window**, not reachability. |
| `.agents/slop/lanedeath-provenance.py` | 7-cell control for the provenance reporting. Plants into `phantom-repro/planted/`, **never** into `tinybendygrad/`. | A lane-death must name the FILE and the REVISION. **C7 neuters `error_site()` and requires C2 to FAIL** — the three controls found disarmed here (`cmp -s` on two empty files, a digest guard whose `grep` matched nothing, a plant in the `py=` column while `row()` compares `left`, six lanes green while disarmed) were all checks with no state in which they could fail. Found three defects in the change before it was green, including the gate's own wrong lift order. |
| `.agents/slop/lanedeath-census.py` | Classifies every BROKEN entry in every stored gate artefact: is the def the error names in the PORT, in an IMPORTED file, or in no file at all? | Reuses `rebase-gate.error_site`, so the census cannot disagree with the gate it counts. **Every line prints `n of N`**: 3 artefacts / 150 verdicts / 18 BROKEN → 5 SUBSTRATE, 4 UNRESOLVED, 1 PORT, 8 NO-DEF. Found the second phantom (`UOp.const_factor.seed`) with no prose at all. |
| `rebase-gate.py`: `import_closure` / `substrate_manifest` / `drift` / `error_site` | Four readers. `run_port()` brackets the lanes with **two** manifests; every non-zero exit prints the closure, its digests, the `jj` id, and the resolved `(def, file, line)`. | **A digest says what the bytes are, never when they were read.** `BAND-19`'s mtime manifest answers "did the tree change"; the question the four victims asked is "was the tree the same tree". Two content digests with the lane between them. |

Report: `.agents/slop/lanedeath-census.md`. Rules: `notes/bend2-constraints.md` **BAND-20** and
**BAND-21**, cited by position (~20810 and ~20890).
| `.agents/slop/cstyle-reader-parity.py` | Answers "does the green survive the correct reader?" three ways: **(1)** each reader's name set, value-by-value agreement, and the symmetric difference over both lanes; **(2)** a **READER ABLATION** — it pulls the file's own PRE-FIX reader out of `jj file show -r @-` with `ast`, binds it back, and diffs the WHOLE printed output; **(3)** both denominators. Also diffs a saved pre-fix run against the post-fix run. | Result on this tree: `[2a] IDENTICAL: not one printed line differs` — `rows_shipped` reached one print and never `judge()`, so the stale reader was **not** load-bearing. The pre-fix→post-fix verdict flip is attributable to the **stderr** hole (`ORACLE-REFUSALS 0 → 13`), not the reader, and the harness separates the two rather than crediting whichever ran first. The fork is `ast`-extracted from the committed blob **because re-typing it would make a third reader** — the exact failure this file measures. |
| `.agents/slop/cstyle-shapes-selftest.py` | One control per row shape — F1 `name=value`, F2 `name = [v]   py=[w]`, F3 `name␣␣value` — each run **ARMED and RED**, each run TWICE, plus a DISARM lane (F2 only) and a real row through `cstyle-gate.py`'s own `judge()`. | F2's DISARM lane is the control that was paid for once: the plant sits in the **non-compared** `py=` column and must come back AGREE. Two name-spaces, because `rows()`'s F3 arm refuses a multi-token name — the spacey `ctl OPENCL sz1 k0` read F3 as **zero shared rows and reported AGREE**, so every case now requires `shared != 0` as well as the expected colour. Also prints reader reach: `cstyle rows_strict` cannot read F1 or F3 at all, which is why the parity reader is a print and not a substitution. |

## The load census and the baseline ledger (2026-10-04) — 0 of 234 recorded counts carry a load

| tool | what it is | why it is here |
| --- | --- | --- |
| `.agents/slop/load-census.py` | **One scanner, three questions.** `--ledger` every recorded baseline with its revision, row count, load-or-`UNKNOWN` and verdict; `--guard` the mechanical test; `--starvation` the retrospective over stored `BROKEN` verdicts; `--vocab` prints the scanner's own vocabulary so a reader can disagree with an entry rather than the concept. | **THE INVARIANT, made mechanical: *a count measured under unknown load is not a count*.** A "count claim" is defined by regex (`SENSITIVE_NOUNS` / `ROWCOUNT_KEYS`) and is LOAD-QUALIFIED only if a load token appears on its line or inside an 8-line blank-line-delimited window — the window exists because NV7's record puts "load average 6-7" on the line *after* the "108 rows" it qualifies. **234 recorded baseline counts in 13 files: 0 carry a load, 0 an elapsed time, 0 a revision. Across the whole record layer 92 of 1,816 sensitive counts are qualified (5.1%).** `--guard` exits 1 **by design and forever**: a guard that passed on this corpus would itself be the defect. |
| `.agents/slop/load-census.py::captures` / `verdict` | The ledger's row builder. Identifies a `*baseline*.txt` dump against `baseline.json` by **ROW-NAME-SET EQUALITY**, never by a typed port name. | A ledger that transcribed port identities would be able to launder a port's identity. Three verdicts: `OK` (a load is recorded), `RE-MEASURED-ALONGSIDE` (a second run in the same session reproduced the count), `SUSPECT`. The middle one is deliberately **not** a shade of `OK`: `stability-2026-10-03.json` ran 38 ports twice and **110 of 110** counts matched, which is evidence of REPRODUCIBILITY and **zero** evidence of load — two runs on one machine of unknown loading agree just as happily when both are starved. |
| `.agents/slop/load-census.py::starvation_retrospective` | Of the **18** `BROKEN` verdicts stored in `_coord-sweep.json`, `dev-wholetree-2.json` and `rebase/postrecord-2026-10-03.json` (**14** distinct ports), how many can be reclassified as starvation rather than a port defect. | **0 of 18, and 0 is the finding.** `rebase-gate.py` carries `CAUSE_STARVED` / `row_load1` / `row_secs`; every stored sweep predates that instrumentation, so **0** carry a load and **0** an elapsed time. Shapes: `dead-lane` 13, `disagree` 4, `no-shared-name` 1 — and **3 of the 18 are `dtype.bend`**, whose 14 permanently-red laws are a documented Bend limitation, so the unclassified count is **15 of 18**, not 18. Cross-checked against `lanedeath-census.py`, which independently reports the same 18. |
| `.agents/slop/loadwatch.py` | The load beside the count: `snapshot()`, `stamp()`, `counts_stamp()`, and the pair **`starved_at(x)` / `unknown(x)`**. | ⚠ `THRESHOLD = 4.0` is **derived from an observation class with zero members**: it is defined as "the largest load at which a full 787-row count was actually observed", and **0 of 18** row-emitting reps in `lane-load-measurements.tsv` reached 787 (max **79**), with `_OBSERVED["max_load_with_full_count"] = None`. It may be reasonable; nothing in the corpus establishes it. ⚠ Also, the anchor has **three values and no unit**: `787` (prose, from NV7) / **780** (rows emitted by `oracles/boot42_baseline_port.txt`) / **768** (distinct names — six names are emitted 3× each). The baseline layer counts distinct names; the starvation slope's axis is a line count. |
| `.agents/slop/lane-load-measurements.tsv` / `lane-load-sweep.sh` | The only place starvation is **DEMONSTRATED** rather than guessed: 5 cells × 3 reps on `nvdev.bend` md5 `2019c2c6…`, varying lane and filler `nice` and recording `load1_start`, `n_bends`, `lines`, `rows`, `secs`, `rc`, `timed_out`. | **18 of 18 row-emitting reps are provably starved** (75–79 rows against a declared 787, all `timed_out=1`, at load1 6.43–88.87). The **3 reps of cell `G_checkonly_f16` are EXCLUDED and NAMED**, not counted: that cell is the `--check-only` **control**, which prints no rows *by design* (NV7: 0.37 s under 19 concurrent compilers), and a deliberate zero read as a starved lane is the "never report an unexplained zero as a result" defect wearing a load number. The TSV has **no invocation column**, so the only available discriminator is the observable. |

**FOUR DEFECTS THE CENSUS FOUND IN ITSELF, all fixed, all recorded because they are the shapes it
exists to catch:** its header claimed `rebase-gate-selftest.py` carried a `load_guard()` calling
`census()` — **it does not, and never did** (that file imports nothing from the module); the same
header's "108 occurrences of the substring `load`" was stale at **176**; `load_guard()` v1 printed
*"215 of 234 carry a load"* because it computed `total − SUSPECT`, so every `RE-MEASURED-ALONGSIDE`
row silently counted as **qualified** and the headline contradicted its own detail table three lines
below; and the ledger's `*baseline*.txt` glob matched `oracles/baseline-ledger.txt`, so **the ledger counted
its own output** — denominator 234, then 235 seconds later, no edit in between.

Ledger: `.agents/slop/baseline-ledger.{md,txt,json}`. Rules: `notes/bend2-constraints.md` **L1**
at position ~20968.

---

## The row-NAME census (`name-census.py`) — why it needs a SECOND reader to say anything

`.agents/slop/name-census.py` asks whether a row name is **reader-dependent**, and that
question cannot be answered with one reader. It imports `rebase-gate.py`'s own `row`/`rows`
(read-only; that file is live and owned elsewhere) and cuts a second name at `" = "`, then
compares the two name sets. Lane roster is `rebase-gate.py`'s own `BASE_ORACLES` — **39 wired
ports, 78 lane texts**, so the census cannot drift from what the gate actually drives.

Three commands, and the middle one exists because of the fourth entry below:

```
--fetch        run every lane once, 8 at a time, cache the text under name-census-lanes/
--refetch-zero re-run, SERIALLY and ALONE, every PORT lane the parallel fetch left empty
--names        print every colliding key and every offending name
```

**The tool that found the defect is the tool that had it.** Three self-measurements, all
recorded in the file and in `name-census.md`:

- Counting `=` in `rows()`'s keys is a **tautological zero** — `row()` cuts at the first `=`,
  so a key can never contain one. It printed `0` over all 78 lane texts *including the eight
  rows the unit was sent to fix*.
- The reshape/duplicate split counted **keys** where the quantity is **rows behind one key**,
  and reported `0` on a lane with 148 unaddressable rows.
- The split's residual went **82 -> 146 -> 349** while `lost` itself was right throughout. It
  now prints `residual 0` and states the three earlier values, because an unexplained number
  in a coverage census is worse than a wrong one.

**The lane shape decides the denominator, and getting it wrong understates the defect by an
order of magnitude.** 79.6% of the tree's read rows are F1 (`name=value`), where the writer
*cannot* express a `=` in a name. The population at risk is the 20.4% that print `NAME = [v]`,
and **7.62% of those carry one** -- versus 1.59% of all names. `renderer/llvmir.bend` holds
157 of its 471 rows in that class, 48 on a single key; cstyle held 8 of 227.

**A starved lane is your harness until proven otherwise.** The 8-way parallel fetch printed 0
rows for 25 of 39 ports; `./bin/bend tinybendygrad/renderer/cstyle.bend` alone prints 227.
`--refetch-zero` re-runs each empty lane alone with `rebase-gate.py`'s own
`BEND_ROW_TRIES`/`BEND_ROW_BACKOFF` and records `row_tries`/`row_secs`. Rules:
`notes/bend2-constraints.md` **GC-7 .. GC-12** at the END of the file (position ~21284).

---

## `nv` register tables — the order-inside-a-pair census

- **`.agents/slop/nv_order_census.py`** — the per-site order-sensitivity census for every
  `Fld.of` in `tinybendygrad/runtime/support/nv/nvdev.bend` and for all 119 `NVReg` tables
  reachable from `nvdev.py`'s own `include()` calls (383 fields). **Its arithmetic is
  asserted against the port's own published `nv_mask_*` / `nv_fldmax_*` / `nv_fld_*` rows
  BEFORE it is used, and the control caught a real error of mine** — `nv.mask` is an
  OR-fold (`nvdev.py:28` is `functools.reduce(int.__or__, ...)`) and I first wrote it as a
  sum. A census whose arithmetic disagrees with the port measures nothing.
  Writes `nv_order_census.json`.
- **`.agents/slop/nv_mmustrans.py`** — transposes ONE field in each of the six `MMU_VER`
  structs and reports the rows that moved, plus two controls (BOOT_42, which has a
  `_ranges` row, and an `s == e` site widened to `(8,9)`, which is a width edit rather than
  a swap). Each transposition costs ~21 min: see NV-1 in the notes.
- **`.agents/slop/nv_one_mutation.py`** — one `nv_mutate.py` entry, full row list with
  before/after values. `nv_mutate.py` prints only the first three moved rows, and a mutation
  that moves 22 and reports 3 is a table nobody can read.
- **`.agents/slop/boot42_inversion.md`** — the before/after of the `minor_extended_revision`
  transposition, by whole `name=value` line, with both row-set digests.

**A `String` in Bend 2 is consumed by its one use**, so a gate row that must build its own
name from a value cannot also use that value as a lookup key. Row names in the new per-field
group are literals on both sides. See NV-2 in the notes.

## The libclang shim unit — `.agents/slop/clangshim/`

- **`clangshim-gen.py`** — the generator. Reads `.agents/slop/ag-libclang.tramp`
  (324 rows of ctypes spellings) plus `tinygrad/runtime/autogen/libclang.py` for
  the TypeAlias graph and struct `SIZE`s, and emits **ONE `shim.c` + ONE
  `shim.bend`** covering 308 of the 324. The ctypes resolver is **imported** from
  `ffi-port-cost.py`, never re-implemented. `--probe` adds the 305-fork CALL
  census; `--exclude` drops a binding the LINKER named. `--list` prints the
  blocked table.
- **`clang-cost.py`** — splits the GENERATED files into "shared, written once"
  and "marginal, one per binding", so the per-function cost is measured rather
  than estimated. `ffi-port-cost.py`'s `LAW_LINES_PER_FN = 3` is 2.1× low.
- **`clang-analyze.py`** — the type/arity census over all 324, and the
  name/arity cross-check against the committed `libclang.bend`
  (**324 defs, 0 missing, 0 arity disagreements** — that is what licenses the
  generation).
- **`leaf.c`** — the census failures' leaf cause, called with **no bend runtime
  in the process** (`rc=139`, SIGSEGV, on a zeroed struct). The census's own
  `FAILED-child-nonzero-exit` says `exit 1`, which on its own does not say *why*.
- **`s1.sh` / `s2.sh` / `s3.sh`** — the three stages, four named steps each, run
  from `$TMPDIR`. `s2.sh`'s link step is a **loop**: it greps the undefined
  symbols out of the linker's own output and regenerates without exactly those,
  printing each exclusion.
- **`libclang` facts re-measured here, on bend 2.0.35** — every `Nat` is LINEAR;
  `bend -o` emits no `CID_*` for a law `main` never calls; `an arity over 247` is
  a limit on live binders; a nullary `Data` is a singleton and cannot carry a
  handle; a bare integer literal is `U32` not `Nat`. Rules `S-1`..`S-14` at the
  END of `.agents/slop/notes/bend2-constraints.md`, cited by NAME because `F-`
  numbers have collided three times.

## Backward walk (2026-10-04) — `mixin/gradient.bend`, step 1 of 3

- **`.venv/bin/python .agents/slop/backward/oracle-cg.py`** — the CPython side of
  `compute_gradient`'s walk. **TWENTY reachable rows per run, and `main()` DIES at line
  116**, so `oracle_pmul`, `oracle_pmul0/1`, `oracle_seed` and the three
  `oracle_fwdwalk*` lines are NEVER EMITTED. Its second fixture drives CPython's own
  `compute_gradient` into `RuntimeError: cannot broadcast ... into ()` at
  `tinygrad/mixin/gradient.py:133` — **a place CPython itself raises**, which is why the
  shaped-edge reduce has no oracle at all. Run it with the repo's `.venv`, never
  `python3` (agent-core position 1733).
- **`sh .agents/slop/backward/run-oracle.sh`** — refuses, strictly, if the `.venv` still
  points at an original tree by absolute path. Prints only `RESOLVED=<tinygrad.__file__>`;
  **the expectation is in the `.txt`, not on stdout.**
- **`sh .agents/slop/backward/walk-mutate.sh <arm>`** — the plant/disarm harness. Arms
  `base plant_reverse plant_noguard disarm_comment disarm_name`. Every arm runs in
  `$TMPDIR` over a **real `cp -R`** (a symlink mirror breaks hub detection and then
  refuses an ordinary `import`), compiles a **control** first, and prints
  `INCONCLUSIVE (T-1)` with stderr on a substrate failure rather than a verdict. Its
  `apply` asserts **the bytes on disk differ** and contain the new text — because
  `s.count(old)` without `s.replace` is a vacuous plant that reports "1 occurrence
  replaced" and "0 rows moved", which this harness did once.
- **`.agents/slop/backward/walk-row.txt` / `walk-plant.md`** — the row table and the
  transcript, both generated from the runs rather than transcribed. Summary:
  `.agents/slop/BACKWARD-WALK.md`. Rules `G-1`..`G-8` at the END of
  `.agents/slop/notes/bend2-constraints.md` (24665+).

## The 93 one-space rows (2026-10-04) — `uop/fold.bend`'s `mm_*` / `bl_*` families

- **`.venv/bin/python .agents/slop/mmfold/mmfold-lane.py`** — the driver
  `LANE-LIVENESS.md:281` said did not exist. Runs `bin/bend tinybendygrad/uop/fold.bend` and
  both oracles, unions `rebase-gate.py`'s `rows()` with the one-space reader below, and asserts
  the two key sets are **disjoint**. `--port OTHER.bend` points it at a substitute port.
  **110 rows compared, 0 disagreements.** A child that fails prints `DIED` and exits **2** —
  never a zero, never a green verdict over nothing.
- **`.agents/slop/mmfold/mmfold-rows.py::rows_f3one`** — the ONE-SPACE F3 reader, registered in
  `reader-contracts.tsv` (signature `7c471b64d6f5`, computed by the census). Reads
  `ctl single half` → 1 row; refuses F1, F2, F3-two-space, F4 and F6-TAB → 0 rows each. Reads
  **0** of `oracle/dtype_tables.py`'s 14,766 TSV lines, which is why `rebase-gate.py:412`'s
  `GAP = "  "` did not and must not change.
- **`.venv/bin/python .agents/slop/mmfold/mmfold-plant.py`** — the plant and the disarm, over
  `copytree`s in `$TMPDIR`; the live tree is read and never written. Plant drops
  `mm.u64.add`'s carry (moves `mm_add_2p31`, `mm_add_carryhi`, `mm_add_carrylo`); disarm swaps
  two `bl_row` lines and must move nothing. Three preconditions: the anchor occurs once, the
  mutant compiles, and the port's stdout **sha256 moved**.
- **`.venv/bin/python .agents/slop/mm-lift-gate.py --selfcheck`** — drives **both** of
  `oracle_py.resolve()`'s refusals in a `$TMPDIR` tree and requires `DIED` on STDOUT with rc 2.
  Plain `--selfcheck` is not enough: the gate also prints **132** rows (127 `lf_` + 4 `satcp_`
  + 1 `DUPLICATE`) and answers **identically** under `python3` and `.venv/bin/python`.
- Report: **`.agents/slop/MMFOLD.md`**. Rules `M-1`..`M-5` at the END of
  `.agents/slop/notes/bend2-constraints.md` (24794+).

## `CSH` (2026-10-04/05) — `cshape`'s `except` arm, the 4 blocked ops

- **`.venv/bin/python .agents/slop/cshape/cs-arms.py`** — every py-side node of the 25
  corpus graphs PLUS the pattern IR (316 nodes): what `.shape` raises and the EXACT
  `tinygrad/.../ops.py:LINE` that raised it, then for each candidate widening the nodes
  rendered, the ops bought, and **every distinct (type, site, message) the arm admits**.
  Needs `env -u PYTHONPATH LC_ALL=C DEV=CPU`; imports the LIVE `graphcmp.py`, never a copy.
  → `arms-run0.txt`.
- **`.venv/bin/python .agents/slop/cshape/cs-opshape.py`** — the same census over all
  **77 ops at two arities**, which is where a widening's COST lives: `except
  AssertionError` admits 4 raising sites and only 1 is about shapes. Also checks the
  `ops.py:331-338` no-shape list against what ops.py:455 actually answers (10 transcribed,
  **13 measured**). → `opshape-run0.txt`.
- **`.venv/bin/python .agents/slop/cshape/cs-androot.py`** — calls upstream's `_get_clause`
  for **18 `UPat` shapes, one per clause branch**, and counts roots. `UPat.__init__` takes
  `dtype=`/`tag=`/`allow_any_len=`/`src=[...]`, NOT `match_dtype=`/`match_tag=`/
  `strict_length=`. → `androot-run0.txt`.
- **`./bin/bend .agents/slop/cshape/cs-patir.bend`** and **`cs-plantir.bend`** — the PORT
  side, built with `O.UOp.new` and the port's own `Arg` constructors, rendered by
  **`import ./../graphcmp.bend as GC`** so the rows are the differ's own. Relative depth is
  `../../../tinybendygrad`. `cs-plantir.bend`'s four SEPARATE graphs (Q1 `AND` over shaped
  consts / Q2 `CUSTOMI` no srcs / Q3 `CUSTOM` no srcs / Q4 `PYLITERAL` no srcs) are what
  separate "the port has no rule" from "the port refuses the same assert" — one graph cannot,
  because one unsettled node looks like both.
- **`.venv/bin/python .agents/slop/cshape/cs-plant.py`** — DISARM FIRST (census twice with a
  byte comparison + the live md5 pinned), then the blast radius of each arm on all 312 rows
  (diffed by whole `name=value` LINE), then PLANT-A (ops.py:438, the attribution between
  the unscoped and the ops.py:444-scoped arm — ONE predicate apart), PLANT-B (ops.py:444),
  PLANT-C (the pattern IR both sides, field-by-field, with `?=0/3` and a VERDICT), the
  per-row ledger by the differ's own `G.LEDGER` + `G.at_value`, and the corpus
  before/after against 77 with the split. Reads the bend transcript from
  `patir-bend.txt` and MUST skip the `bend 2.0.35 is available` line. → `plant-run0.txt`.
- Report: **`.agents/slop/CSHAPE.md`**. Rules `CSH-1..9` at the END of
  `.agents/slop/notes/bend2-constraints.md`. **Nothing committed; nothing outside
  `.agents/slop/cshape/` edited — `cshape` lives in `graphcmp.py`, which is another unit's,
  so every widening is a monkeypatch in this unit's own process.**

## `e2e-js-lane` — the JS dtype lane as `e2e.sh` stage 8

- **`.venv/bin/python .agents/slop/jstage/jsstage.py`** — the only instrument in this unit.
  `--tree DIR` measures `DIR/tinybendygrad` instead of the repo's (a READER of the
  substrate, not a way to plant one; it exists because `dtype.bend` was mid-edit). Emits
  ONE `.bend` with `bend -o` and runs it with **node** — `bend -o` emits JS, it does not
  build it; the C lane's build is `cc`. Exit **0** pass, **1** fail, **3** refuse.
- **Node is the runner, `node` v26.8.1.** `runtime/dtype.js` is a real lane: its text is
  embedded verbatim in the emitted JS (`comp.ts:3385` `effect_srcs(fl, ".js", …)`), so
  `grep -c asIntN seam.js` = 1 is how you confirm the lane's code is in the binary.
- **`.venv/bin/python`, never `python3`** — the editable tinygrad install exists only in
  `.venv` (3.12). PATH's `python3` has no `.pth` and would import a different tree.
- **`python3` for the shell-level probing only.** Two traps this unit hit: **zsh does not
  word-split an unquoted `$var`**, so `"$PY" gate.py $FLAGS` passed `--tree /path` as one
  argument and argparse answered `rc 2`; and **`$(basename …)` inside `echo … rc=$?` resets
  `$?`**, so a verification loop over five substrates printed `rc=0` for all of them.
- **`IO.pure(TYPE, value)`** — the first argument is the VALUE type, not a morphism
  (`IO.pure(Unit, e)` answers `expected : Unit, observed : F32`).
- **A `do IO<Unit>` block binds an `IO` value with `<-` and will NOT bind a pure one**;
  a pure `Dt.*` must be lifted. `dtype.bend` moved `Dt.bf16`/`Dt.fp16`/`Dt.fp8_to`
  between those two shapes mid-session, so the emitter READS the declaration
  (`SEAM_DECL`) instead of assuming one.
- **`BigInt.asIntN(64, x)` leaves a 32-bit `x` alone** — the sign lives in the HIGH word,
  so `i64_of_hi_lo(0, 4294967288)` is `+4294967288`, not `-8`.
- **`F32.show` prints SEVEN significant digits** (`1.0996094` where CPython prints
  `1.099609375`); normalise through an f32 round-trip before counting, or the count
  absorbs format noise.
- Report: **`.agents/slop/JSTAGE.md`**. Rules `JS8-1..7`. **Nothing committed; no `.bend`,
  no `runtime/*.c`, no `runtime/dtype.js` edited; every mutation on a `$TMPDIR` copy.**
- **Canonical float spelling: `.agents/slop/norm/canon.py`** --
  `canon(value, width)` for a value or a decimal spelling, `canon_bits(pattern,
  width)` for an IEEE-754 pattern.  The WIDTH IS AN ARGUMENT, so a gate cannot
  compare at the wrong width by accident, and `canon` REFUSES a NaN spelling
  (`f32:?nan`) rather than packing it as a payload it never carried.  Enforced by
  `.agents/slop/norm/lint_norm.py` (exit 1 on a NEW non-round-tripping normaliser;
  the known ones are a keyed baseline with a reason each).  Reproduce:
  `python3 .agents/slop/norm/canon.selftest.py`,
  `python3 .agents/slop/norm/gate_norm.py`, `zsh .agents/slop/norm/lint_demo.sh`.
  Report: **`.agents/slop/NORM.md`**.  Rules `NORM-1..7`.  **Nothing committed; no
  `.bend`, no `runtime/**`, no `tinybendygrad/**` edited.**

### Coldness

| tool | why |
| --- | --- |
| `zsh .agents/slop/coldness/sweep.sh` | **SUPERSEDED FOR VERDICTS BY `checks/substrate.py`, WHICH IS NOW MEMORY-BOUND.** This sweep exists because `substrate-check.sh:200` ran bend under `perl -e 'alarm 300; exec @ARGV'` — a time bound and **no memory bound** — which is the idiom that crashed this machine twice on 2026-10-05. **That gap is CLOSED: the port bounds all four instrument invocations, including the two `cc` calls the shell left entirely unbounded.** It still runs 3 `.bend` files CONCURRENTLY, so `-P 3` + `sz.bend` at 1.4 GB is the risk the port does not carry — **the port runs ONE at a time.** |
| **`checks/substrate.py`** | **THE SUBSTRATE GATE, NOW PYTHON.** HALF 1 judges each file by its OWN instrument (`.bend` → `bend --check-only`; `.c` → `cc -fsyntax-only` + bend's generated C context; `.js`/`.mjs` → `node --check`; anything else → `NO INSTRUMENT`, counted apart, never `COLD`) with an EMPTY/MISSING pre-gate, because `--check-only` answers `ALL PROOFS CHECK` for a 0-byte file. HALF 2 resolves every `<Mod>.<name>` against the modules that file imports, and prints its own `unseen=` blind spot. **Refuses zero arguments with exit 3**, because `SUBSTRATE CLEAN: 0 file(s)` is the same verdict as a green run over a population. **Every invocation under `checks/bounded.py`; `--mb` defaults to 2048, ABOVE the measured maximum, because a ceiling below the population's own maximum is a ceiling that CHANGES VERDICTS** (`sz.bend` 1,468 MB, `renderer/nir.bend` 1,435 MB, both killed at 1 GB). **`stdout` is byte-identical to the frozen shell oracle on all 6 input sets including the whole 344-line tree**, the `.sh` files remain as `exec` shims, and the shell body is frozen runnable at `.agents/slop/substrate/oracle-check.sh` under a sha256 `ORACLE_PIN` **checked in code on every run**. `--causes` additionally groups the COLD files by cause, off by default because it changes the stream. Report: **`.agents/slop/substrate/SUBSTRATE.md`**. | `.venv/bin/python checks/substrate.py --help` |
| `.venv/bin/python .agents/slop/coldness/coldness.py [DANGLING 2026-10-05: this path DOES NOT EXIST. It was pruned, or moved, or never committed -- do not assume which. `checks/repro-paths.py` lists all of them.]` | joins the compiler verdicts onto the import graph and prints `TABLE.tsv`: per file, imports / importers / reaches_live / imports_nothing / reached_by_nothing / defs / laws / driven / verdict / shape / symbol / cause_owner, then the cause collapse. **The number to quote is in `COLDNESS.md` §0 and it is 0 cold files**: nothing imports a file it cannot also run, and the 9 that satisfy both are the empty `__init__.bend` markers. Report: **`.agents/slop/coldness/COLDNESS.md`**. Rules `CLD-1..3`. |

### `bitcastrow` (2026-10-05) — the `bitcast_dims` range fix and its rows

| tool | why |
| --- | --- |
| `gates/bc-u32-gate.py` | **39 rows, 3 lanes, against the real tinygrad BITCAST arm.** Built BEFORE the fix and measured against the unfixed tree, because a row written after the code it approves cannot tell a fix from a description of the bug. **20 disagree before, 2 after**, and the 2 are PINNED divergences at `dim*inp == 2**63` — `i64_mul` wraps mod 2**64 and `i64_divmod` reads bit 63 as a sign, so the fix MOVED THE WINDOW. Refuses a lane that is all-refusals or all-shapes, which a `0 DIFFER` check would pass happily. |
| `.agents/slop/bitcastrow/table.py` | **The ONE fixture list**, from which both lanes are generated. Also carries the port's semantics as CODE rather than prose: `lo32`, `U32.mul`, and `sint_of`'s sign extension, and the model predicted the fixed port on all 39 rows. **A census whose port model is a Python int cannot see a truncation that lives in `i64_of_i32`** — that is how `.agents/slop/trigger/bc-oracle.py` reported 80 of a larger set. |
| `.agents/slop/bitcastrow/bc-gen.py` | Emits `bc-rows.bend` AND `bc-oracle.py` from `table.py`, and asserts the driver's row count against the table in the same breath. Every dim goes in as an `(hi, lo)` word pair through `i64_of_hi_lo`: `i64_of_i32` sign-extends, so it cannot express `dim = 2**60` — the defect under test is also the fixture-encoding limit. |
| `.agents/slop/bitcastrow/bc-diff.py` | Compares whole `name=value` lines, as a **multiset**. `fold.bend` emits `lf_sub_int32_-3_4` TWICE and a dict collapsed the pair — the lane then counted 333 for 334 rows and `--rows 334` failed for a reason unrelated to the change. **Asserts non-emptiness BEFORE comparing**, which is the `""` vs `""` failure `gates/README.md` records for the retired shell form. |
| `.venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- ./bin/bend F` | Every `bend` invocation. **2048, NOT 1024**: `sz.bend` peaks at 1,468 MB, so a ceiling below the population's own maximum is a ceiling that CHANGES VERDICTS. Parse the VERDICT TOKEN, not the exit code. |
