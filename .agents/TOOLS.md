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
| `.agents/slop/tcptx-oracle.py` | the ORACLE for `renderer/tc_ptx.bend`: `rows` prints all 620 string-diff rows, `stage1` (286) and `stage2` (334) print the halves for a localised diff. **The `py=` half of every row is a LITERAL in the `.bend` and a live tinygrad value here, which is the only reason the diff is a diff** — `String.concat` drops a literal silently, so a row that said "the asm is right" would survive a missing `;`. Three normalisations, each a decision and each recorded in the file: `frag_coords` is gated on a **FNV-1a digest plus length** and not on the 22 647-character string (hard-coding the eight shapes would put ~180 KB of literals in a file, past bend's measured 28 988-byte per-file cliff; the digest catches every dropped literal a sample would miss, and both sides implement FNV independently); `supported_dtypes` is **sorted**, because ptx.py:230 returns a `set` and a set has no order to compare; and the two control-character constants (`barrier`'s TAB, `fmt`'s TABS) are escaped, so a dropped tab is a shorter line rather than an invisible one. The `render_wmma` and `render_kernel` fixtures are **transcriptions of ptx.py's own text driven by a stand-in ctx**, and every name they print is a register name and every dtype a real `DType`. `PTXRenderer.__init__` needs the CUDA compiler, so `supported_dtypes` is bound to a `Shell` that supplies `target` and nothing else. |
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
| `late-oracle.txt` | what did it say, checked in? | the oracle's 128 rows. The acceptance test is `diff .agents/slop/late-oracle.txt <(./bin/bend tinybendygrad/codegen/late.bend)`, and the native lane must print the same bytes. |
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

- **`.agents/slop/rf-ct-oracle.py` → `.agents/slop/rf-ct-oracle.txt`.** The ONLY way
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
