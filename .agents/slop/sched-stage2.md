# STAGE 2 -- one real spec end to end, and then six

`create_schedule` was already in the port (Stage 3's `create_schedule` row), so
Stage 2 is not "does it exist" but **"does it agree with CPython on a graph
CPython itself built."**

## THE BRIDGE, AND WHY IT IS A GENERATOR AND NOT A FIXTURE

`sched-emit.py` turns CPython's own sched_sink object graph into a Bend arena
builder. Nothing is transcribed: it walks `sink.toposort(None)`, and every
`+nK = O.UOp.new(...)` it writes comes from a real `UOp`'s op, srcs and arg.

Two details are load-bearing and both were measured, not designed:

- **TWO LISTS, not one.** `create_schedule`'s walk is
  `sched_sink.toposort(gate_kernel_sink)` (`__init__.py:39`) and `toposort`
  enters CALL bodies by default (`ops.py:297`) -- but `gate_kernel_sink` REJECTS a
  SINK carrying a `KernelInfo` (`ops.py:1911`), and the kernel body is exactly
  such a SINK. So the gated walk is 6 nodes while the graph is 29. The emitter
  writes the full graph (the Kahn loop needs `k.src[0]`, the body) and the port
  separately computes the gated count, which is the `_gated` row.
- **THE ARENA IS THE EMITTED INDICES.** Node N is built from node N-1's arena,
  so the emitted indices are the oracle's `tree[i]` indices and a disagreement is
  locatable.

## THE RESULT: 6 specs, 10 fields each, 60/60 AGREE, 0 DISAGREE

`sched-cmp.py` recomputes CPython's side by CALLING `create_schedule` a second
time -- not by reading `sched-oracle.txt` -- and diffs whole `name=value` lines.

```
# specs_attempted=6 specs_scheduled=6 fields_compared=60
# fields_agree=60 fields_disagree=0 port_only=0
# denominator: 60 fields = 6 specs x 10 fields
```

Determinism: two consecutive `./bin/bend .agents/slop/sched-fixture.bend` runs
produce byte-identical output,
`sha256 207ee494251e3dcde90ef2b03e5709899ff39604885b7bedad06b3beadd34817`.

## matmul, FIELD BY FIELD

`matmul` is `(4,3)@(3,5)` into a realized `Tensor.empty(4,5)` -- the spec
`graphcmp.bend:859 g_lin` was hand-written from.

| field | CPython | port | agrees |
|---|---|---|---|
| `_gated` (`sink_n`) | 6 | 6 | yes |
| `_root_op` (`sink_op`) | SINK | SINK | yes |
| `_lin_n` (`lin_nsrc`) | 1 | 1 | yes |
| `_lin_op` (`lin_op`) | LINEAR | LINEAR | yes |
| `_ksrc` (`lin_ksrc`) | `['SINK','PARAM','PARAM','PARAM']` | 241278 | yes |
| `_ksrc_n` | 4 | 4 | yes |
| `_knsrc` (`lin_knsrc`) | `[4]` | 4 | yes |
| `_ktop` (`lin_ktop`) | `['SINK']` | 5 | yes |
| `_kmark` (`lin_kmark`) | `<REDUCE>` | 15 | yes |
| `_cyc` | no raise | 0 | yes |

241278 is base36 `5666` = `[SINK, PARAM, PARAM, PARAM]`; 15 is `REDUCE`. Both
decoded by `sched-cmp.py`, which re-derives them from CPython's own lists.

**The fields I did NOT match: none -- for `matmul`, and for all six specs.** The
three rows that did NOT match on the first run, and what each was, is the honest
part of this stage:

| row | first value | cause |
|---|---|---|
| `*_ksrc` | 287933 (= base36 `6665`) | **my** reader, not the port. `List.append(x, A, xs, ys)` is `xs ++ ys`, so `List.append(&2,U32, srcs.of(ar,rest), [d])` PREPENDS. `['PARAM','PARAM','PARAM','SINK']` instead of `['SINK','PARAM',…]`. The head/tail swap from agent-core, reached again; only a SEQUENCE row catches it. |
| `*_kmark` | 0 on all six | **my** reader again. It walked `sc_srcs(ar, k)` -- the kernel's direct srcs -- so it never reached the STORE, which is under `k.src[0]`. Fixed by `O.UOp.toposort`, which enters calls (ops.bend:2839). |
| `*_ksrc` on `multi` | wraps | not a bug: base36 in a U32 wraps past 7 ops. `multi` has exactly 7, and `_ksrc_n` prints the untruncated count so the bound is never silent. CPython's 11 257 073 070 mod 2^32 = 2 667 138 478 = the port's value. |

## THE SIX SPECS, ALL 60 FIELDS

`matmul` 1 kernel, `matmul_sym` 1 kernel with a bound Variable, `conv` 1 kernel,
`elementwise` 1 kernel, `multi` **2** kernels, `chain` 1 kernel. `multi` is the
only one that exercises the ordering: `multi_ktop=185` = base36 `55` =
`[SINK, SINK]` and `multi_knsrc=67` = base16 `[4, 3]`, so both kernels and their
arities come out in LINEAR order.

## WHAT THIS DOES NOT ESTABLISH, WITH THE WALL

- **Everything upstream of `create_schedule` is still `__init__.py:82-301` and is
  still deferred.** This stage feeds the port's `create_schedule` a sched_sink
  that CPython built. It does not show that the port can BUILD one.
- **Kernel ORDER is exercised by 1 spec of 6.** `matmul`, `matmul_sym`, `conv`,
  `elementwise` and `chain` all schedule exactly ONE kernel, so the Kahn loop's
  queue order, the WAR pass at `:59-65`, and the zero-degree seed order at `:68`
  are all decided on a one-element queue. The port's hand-built `fx1`/`fx2`/`fx5`
  fixtures (2 and 3 kernels) are the only thing covering them, and `fx2` is the
  row that proves the linearization is not the toposort order.
- **No MSELECT, no MSTACK, no BUFFER, no ALLOC in any of the six.** See
  sched-stage1.md's census: every real sched_sink here is PARAMs and a CALL.
- **`_cyc = 0` on all six, so the CYCLE PATH IS UNTESTED BY REAL SPECS.** CPython
  raises on none of them, so 0 is the right answer and it is also the answer for
  "never asked". The port's `fx2`/`fx5` (which DO have cycles) are the only
  coverage, and there CPython raises while the port reports a count -- see below.

## THE THREE VERDICTS, AND WHAT THE PORT ANSWERS FOR EACH

The brief is explicit that a fuel bound, a cycle and a raise are three different
answers, so here is each one and the observable chosen:

| outcome | CPython | the port | the observable |
|---|---|---|---|
| **raise, `_states` (`:22`)** | `AssertionError` | cannot raise | **none chosen.** `_states` answers `[s]` for ANY op (schedule/__init__.bend:376). A non-state input is silently treated as a state. Reported as a gap, not papered over with a `()`. |
| **raise, `_split_after` (`:29`)** | `AssertionError` | cannot raise | **the DROP.** `Split` carries Python's two fields and Python's `remaining` is discarded, so a bad source is silently dropped. The gate pins the drop at `split_bad_ks`. |
| **raise, cycle (`:79`)** | `RuntimeError` | cannot raise | **`cycles(Ctx)` -- the count of kernels whose `in_degree` never reached zero** (`:1067`). It is 1 for `fx2`/`fx5` and 0 for `fx1`, so a cycle IS visible -- but as a number beside the schedule, not as a refusal. |
| **fuel bound (`:66-80`)** | none: CPython's `while queue` always terminates or raises | the loop is a fuel fold | **NOT SEPARATELY OBSERVABLE TODAY.** This is the honest wall of this stage: the Kahn loop is `ln_go(fuel, q, l)` and there is no row saying whether `fuel` was exhausted. A fuel-bound stop and a cycle both present as "fewer kernels than CPython" and only `cycles` distinguishes them -- and `cycles` is 0 for a fuel-bound stop, because the degrees it reads are whatever the fold left. **So `cycles == 0` currently does NOT certify a complete linearization.** |

The last row of that table is the wall worth carrying forward, and it is exactly
the failure mode the brief names: "a bound hit reported as a schedule is the
same class of bug as the `False` flag that meant two opposite things." The port's
`_cyc` row is a real improvement over a silent `()` and it is still not enough.

## WHAT IT TOOK TO BUILD, HONESTLY

Eleven Bend rules were learned by hitting them, all now written into
`sched-fixture.bend`'s header: a Bool LITERAL is a PATTERN (`False{}` compiles in
`case` and is refused in a term position -- so `ParamArg.volatile` needs
`btrue()`/`bfalse()`); a parameter may be consumed ONCE unless it is `+`
(`mk.of(+ar, +u, …)`, and `wt_go`'s arrangement at `schedule/__init__.bend:865`);
mutual recursion needs a forward reference and the compiler REFUSES it ("expected
: a filled definition"), so each fold is one self-recursive def building a list
plus an arena-free pack; there is no `pow`; there is no `let` and `do IO<Unit>:`
binds only IO actions; `Arena.node` is total so a stale index reads back as NOOP;
`O.AAlu{}` is spelled `Aalu`; Bend has no negative integer literal;
`UOp.range_end`'s CPython arg is `(AxisType, int)` but the port takes a list.

## THE OPS FINDING: `DIV` IS NOT PORTED

The first `dig` list included `O.OpsDIV{}` and the fixture FAILED TO COMPILE:
"a declared constructor (unknown: OpsDIV)". `ops.bend` has no DIV variant at all.
`conv` needs it and works around it by never emitting one. That is a real gap in
`ops.bend` and it is a single-line fix for whoever owns that file -- which is
**not** this unit (`uop/ops.bend` is single-ownership and DO NOT TOUCH).
## THE MUTATIONS, AND TWO BLIND SPOTS THAT ARE THE STAGE'S MOST USEFUL OUTPUT

Nine mutations, all measured, in two sets. The harness files are
`.agents/slop/sched-mut.py` (six, against the fixture's own readers) and
`.agents/slop/sched-portmut.py` (three, against `schedule/__init__.bend` itself).
Both verify three things before printing a number: the pattern was PRESENT, it is
ABSENT afterwards, and the mutant produced the same number of parseable rows.
`sched-portmut.py` also asserts the schedule file's sha256 is byte-identical after
the run.

### Set 1 -- the fixture's readers. 6 mutations, all move 6 rows, no blind spots.

| id | what it breaks | rows moved |
|---|---|---|
| M1 | every `_ksrc` digit shifted by 1 | 6 |
| M2 | `_ktop` reads the kernel op instead of the BODY op | 6 |
| M3 | `_kmark` answers 0 unconditionally | 6 |
| M4 | the gated toposort is replaced by the ungated one | 6 |
| M5 | `_lin_n` answers 0 | 6 |
| M6 | `dig(OpsLINEAR)` is 8 instead of 9 | 6 |

Six each is the right answer: a per-spec field broken for all six specs.

### Set 2 -- `create_schedule` ITSELF. 1 of 3 moves; 2 ARE BLIND SPOTS.

| id | what it breaks | rows moved |
|---|---|---|
| P1 | the gate stops rejecting the kernel SINK -- upstream's own **M8** | **6** |
| P2 | the Kahn queue never re-pushes -- upstream's own **M3** | **0, BLIND** |
| P3 | an END-wrapped kernel is not unwrapped (`k = rk.src[0] if END`) | **0, BLIND** |

P1 moving 6 rows is the load-bearing positive result: **the 60-row real-spec gate
can see a real `create_schedule` bug**, and `matmul_gated` goes 6 -> 26 with the
gate removed. That is the gate's whole purpose.

**P2 is blind because no spec has a RAW or WAR edge between two kernels.** Only
`multi` schedules two kernels (`lin_n=2`, `knsrc=[4,3]`), and they write disjoint
buffers, so both are zero-degree SEEDS and the re-push at `__init__.py:77-78`
never fires. Measured, not assumed: the mutant's 60 rows are byte-identical to the
baseline's. The port's own `fx2`/`fx5` fixtures DO have RAW edges -- its own table
records M3 moving `fx1_marks`/`fx2_marks` -- so this is a gap in the REAL-SPEC lane
specifically, and the two lanes are complementary rather than redundant.

**P3 is blind because `get_kernel_graph` puts the END INSIDE the body.** `lin_ktop`
is SINK for all six specs, so no linearized kernel is END-wrapped and
`kernel.of`'s `OpsEND` arm is unreachable from a real sched_sink. `_split_after`'s
END partition arm is likewise never taken by these six. Both arms need a fixture
with an END in the kernels-list position, which no spec at these sizes produces.

### THE HARNESS COMMITTED THE FALSE ZERO, AND IT IS WORTH RECORDING

The FIRST version of set 2 reported **0 rows moved for all three mutations, and
all three were false.** The shell wrapper passed `"$1"` -- the mutation's LABEL --
where the Python side expected the PATTERN, so `assert "P1" in source` ran, `"P1"`
does occur in the file, and `replace` then edited an unrelated line. The
comparator dutifully reported 60/60 on an unmutated fixture. Caught by running one
mutation by hand and seeing `matmul_gated=26`.

Two independent false zeros in one session, from two different harness bugs, is the
measurement that matters here: **a mutation number is only evidence if the
harness has been shown to fail once.** `sched-mut.py` and `sched-portmut.py` now
refuse to print a number unless the mutant ran, and they print the sha256 they
restored to.

## THE 60 ROWS ARE NOT IN `schedule/__init__.bend`, AND WHY

Bend has no `include`, and `sched-fixture.bend` already
`import`s `schedule/__init__.bend`, so importing the fixture the other way would be
a cycle. And the 60 rows are a FUNCTION of CPython's output, so the file holding
them must be regenerable -- which is the whole point of `sched-fixture.py`.
Copying them into the schedule file would make them typed expectations, which is
the failure mode agent-core's table is built on.

The schedule file's own 71 rows are untouched and still green, and the file is
byte-identical to how this session found it:
`sha256 652986d27842d09b63e5579f47b1f135e4747141f2dff2c75102fa115e818edf`.
