# THE PORT's `Device` LANE — THE COMPLETE MAP, MEASURED 2026-10-28

**⇒ THIS IS THE ANSWER TO "WHAT IS STILL MISSING", AND IT IS **MEASURED**, NOT A GUESS.**

## THE PIPELINE, END TO END, AND WHERE EACH STAGE STANDS

**UPSTREAM'S PIPELINE IS ONE LINE (`tinygrad/schedule/__init__.py:132`):**
```python
linear = create_schedule(get_kernel_graph(prepare_rangeify(function)))
```
**⇒ AND THEN (`tinygrad/codegen/__init__.py:427-458`):**
```python
lst = line_rewrite(linearize(sink), pm_linearize_cleanups+pm_alloc_to_buf)
src = ctx.render(list(lin.src))          # the C
lib = ctx.compiler.compile_cached(source.arg)   # the ELF
```

| # | STAGE | UPSTREAM | THE PORT | MEASURED |
|---|---|---|---|---|
| 1 | **the function's graph** | `Tensor`'s uop | `tinybendygrad/tensor.bend`'s `Tensor{ar, uop, ...}` | **THE PORT HAS AN EAGER GRAPH AND **NO REALIZE-TO-SINK** PATH** |
| 2 | **`prepare_rangeify`** | `prepare.py:271-284`, **FOUR** `graph_rewrite` CALLS | `schedule/prepare.bend`'s TABLES (`pr_mop_table()`, `pr_inl_table()`, `pr_dsk_table()`, `pr_ear_table()`, `pr_fma_table()`, `pr_mcl_table()`) | **THE TABLES ARE THERE AND **THE DRIVER IS NOT** — MEASURED: NO `prepare_rangeify` DEF IN `schedule/prepare.bend` |
| 3 | **`get_kernel_graph`** | `rangeify.py:341-376`, **SEVEN** `graph_rewrite` CALLS | `schedule/rangeify.bend`'s `eng_stages()` + `eng_run`/`eng_node`/`eng_sweep`/`eng_fix`/**472 LINES** | **BUILT AND COMPILING, **UNWIRED** (`grep -c 'eng_\|Eng\b' schedule/__init__.bend` ANSWERS **0**) AND **UNMEASURED** |
| 4 | **`create_schedule`** | `__init__.py:32-80` | `schedule/__init__.bend:1139` `schedule(+ar, +sink) -> Lin` | **MEASURED AGAINST CPython: `checks/sb-gate.sh` READS **81 of 81**** |
| 5 | **`linearize`** | `codegen/late/linearizer.py:8-51` | `codegen/late/linearizer.bend:836` `linearize(+ar, +lst, vms, +sink)` | **MEASURED (THE FILE'S OWN GATE ROWS)**** |
| 6 | **the `List<KU>`** | the renderer's `list[UOp]` | **`renderer/kuconv.bend` (430 LINES, LANDED 2026-10-28)** | **MEASURED: **5 OF 5 REAL MNIST CPU KERNELS BYTE-IDENTICAL** WITH UPSTREAM's `csrc/*.c`, IN BOTH LANES, PLANT RED 0 OF 5** |
| 7 | **`render`** | `renderer/cstyle.py:268-278` | `renderer/cstyle.bend:2297` `render(+dev, cpu, +kus)` | **MEASURED (5/5 IDENTICAL C)** |
| 8 | **`compile`** | `runtime/ops_cpu.py:23-46` (`cc` → ELF) | `runtime/ops_cpu.bend` `Cpu.compile` | **MEASURED NATIVELY: **5/5 IDENTICAL C, IDENTICAL RELOCATION**** |
| 9 | **`exec`** | `runtime/ops_cpu.py:23-62` (mmap → call) | `runtime/ops_cpu.bend` `Cpu.exec` | **MEASURED NATIVELY: **OUTPUT BYTES IDENTICAL TO CPython's OWN CPU DEVICE, `max_abs=0`**** |

**⇒ ⇒ STAGES **4–9 ARE MEASURED AND GREEN**. STAGE **3** IS BUILT BUT UNWIRED. STAGE **2**
HAS ITS TABLES BUT NO DRIVER. STAGE **1** IS THE PORT's EAGER GRAPH WITH NO REALIZE-TO-SINK
PATH.

## ⇒ ⇒ SO THE **DEVICE LANE'S** REMAINING WORK IS **STAGES 1–3**, AND **STAGE 3's
MEASUREMENT IS NOW POSSIBLE** (`.agents/slop/engine/eng-oracle.py`, LANDED 2026-10-28).

## WHY STAGE 1 IS NOT "ONE MORE DEF" — AND WHAT IT ACTUALLY IS

**⇒ THE PORT's `Tensor` CARRIES AN ARENA AND A UOP (`tensor.bend:200-205`
`Tensor{ar: O.Arena, uop: U32, is_param: Bool, grad: U32}`), AND ITS METHODS BUILD EAGER
GRAPHS (`tn_alu`, `tn_binop`, `tn_where`, `tn_assign_store`…).**

**⇒ AND UPSTREAM'S STAGE 1 IS NOT A "REALIZE" EITHER: IT IS `prepare_rangeify(function)`,
WHICH IS FOUR `graph_rewrite` CALLS OVER **THE FUNCTION'S SINK OF AFTERs** — AND THE SINK OF
AFTERs IS WHAT `create_schedule` CONSUMES (THE PORT's OWN `schedule(+ar, +sink)` TAKES A
`sink`!).**

**⇒ ⇒ ⇒ SO THE PORT's STAGE 1 AND STAGE 2 ARE **ONE** PIECE OF WORK: A DRIVER THAT TAKES
THE PORT's EAGER GRAPH AND PRODUCES **THE SINK OF AFTERs** THAT `schedule()` ALREADY
ACCEPTS — **AND `schedule()`'s SIGNATURE SAYS THE PORT WAS BUILT FOR EXACTLY THAT.**

**⇒ ⇒ AND THE PRIOR ART IS **THE PORT's OWN `schedule/__init__.bend`'s OWN FIXTURES** —
`fx1()`/`fx2()`/`fx3()` (`:1846`, `:1862`, `:1879`) ARE **SINKS OF AFTERs**, HAND-BUILT
TO MATCH CPython's, AND `checks/sb-gate.sh` MEASURES THE PORT's `schedule()` AGAINST
CPython's `create_schedule` ON THEM. **⇒ ⇒ SO THE PORT'S OWN SCHEDULER HAS **NEVER BEEN
DRIVEN** ON A GRAPH **THE PORT BUILT ITSELF** — EVERY SCHEDULER FIXTURE IS HAND-BUILT.**

## THE MEASUREMENT THE ENGINE NOW HAS, AND WHY IT MATTERS

**⇒ `.agents/slop/engine/eng-oracle.py` **SPIES ON UPSTREAM's OWN CALL** TO
`get_kernel_graph` ON A REAL PROGRAM (`(4,5) = (4,3) @ (3,5)`) AND PRINTS **THE EXACT
23-NODE GRAPH** CPython HANDS THE ENGINE, IN **THE PORT's OWN DUMP SPELLING**:
```
eng_py_in_nodes=23
eng_py_out_nodes=9
# the engine's input  census: AFTER CONST MUL PARAM PERMUTE REDUCE RESHAPE SINK STACK STORE
# the engine's output census: AFTER CALL CONST PARAM SINK
```
**⇒ ⇒ SO THE COMPARISON IS **NODE-FOR-NODE, WITH NO TRANSLATOR**, AND IT IS THE FIRST
TIME THE ENGINE HAS AN ORACLE — **⇒ BEFORE THIS, `grep -rln 'eng_a_s|eng_b_s|eng_fixture_rows'`
OVER THE WHOLE TREE ANSWERED **NOTHING**.**

**⇒ AND CPython **REFUSES** THE PORT's OWN TWO ENGINE FIXTURES**
(`RAISED:TypeError:'>=' not supported between instances of 'tuple' and 'int'` AND
`RAISED:RuntimeError:UOp verification failed at 1 on Ops.NOOP dtypes.void 0 [] ()`), **⇒ SO
THE FIXTURES ARE **SYNTHETIC** GRAPHS BUILT TO FIRE INDIVIDUAL RULES, AND THE COMPARISON
AGAINST UPSTREAM MUST USE **A REAL GRAPH**, WHICH IS WHAT THE ORACLE NOW SUPPLIES.**

## THE `TUPLE_ORDER` LANE — THE LAST BYTE-LEVEL DIFFERENCE, AND IT IS **NAMED**

**⇒ THE PORT's OWN `codegen/late/linearizer.bend:115-125` ALREADY NAMES IT:**
> `W2 x.tuplize -- linearizer.py:36 ... TUPLE_ORDER is a real ContextVar (helpers.py:280,
> default 1) and setting it 0 makes the key the STABLE (run_count, priority) pair ... So this
> file ports the TUPLE_ORDER=0 lane exactly and names the =1 lane W2.`

**⇒ MEASURED, UPSTREAM's DEFAULT IS `1` (`tinygrad/helpers.py:282`), AND THE PORT IS ON `=0`.
**⇒ AND THE PORT's OWN `linearizer.bend:1215-1218` QUANTIFIES IT: `lin_ties=47` OF 171 PAIRS
TIE ON `(run_count, priority)` — **⇒ 47 OF 171 PAIRS ARE DECIDED BY `x.tuplize` ALONE.****

**⇒ AND `x.tuplize` IS `(self.op.value, repr(self.arg), self.dtype, *src.tuplize)`
(`ops.py:316-318`) — **A STRUCTURAL KEY HOLDING A `repr` OF AN ARBITRARY ARG AND A DTYPE
VALUE**, **⇒ SO IT IS NOT A `U32` AND THE PORT's SINGLE-`U32` KEY (`lt_key`) CANNOT HOLD IT
AS IS.** **⇒ ⇒ SO PORTING IT IS A **KEY-TYPE** CHANGE, NOT A KEY-VALUE CHANGE.**

**⇒ AND THE PORT's KEY IS ALSO MISSING **`len(u.ranges)`**, WHICH IS UPSTREAM's **SECOND**
COMPONENT (`linearizer.py:33`'s `(run_count, len(u.ranges), priority, extra)`) — **⇒ SO THE
PORT's `lt_key` IS ORDER-ISOMORPHIC TO `(run_count, priority)`, WHICH IS **TWO** OF
UPSTREAM's **FOUR** COMPONENTS.**

## THE COST

**ONE BEND PROCESS AT A TIME THROUGHOUT. EVERY MEASUREMENT ABOVE IS ONE PROCESS AND ITS
WALL-CLOCK COST IS IN THE COMMIT MESSAGES.**
