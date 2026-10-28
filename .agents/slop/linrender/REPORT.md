# LINRENDER — THE PORT's OWN ARENA → THE PORT's OWN RENDERER, AGAINST UPSTREAM's OWN C

## THE MEASUREMENT

**THE PORT's OWN `lin` ARENA → THE PORT's OWN FOLD → THE PORT's OWN LINEARIZER → THE
PORT's OWN CONVERTER (`renderer/kuconv.bend`) → THE PORT's OWN RENDERER
(`renderer/cstyle.bend`'s `render`) → C, COMPARED WHOLE-FILE WITH UPSTREAM's OWN C.**

| | |
|---|---|
| **the port's arena** | `.agents/slop/graphcmp.bend`'s `g_lin()` — **THE PORT's OWN**, 51 arena nodes |
| **the oracle** | UPSTREAM's own file, written by CALLING CPython: `Tensor.empty(4,5).realize(); out.assign(Tensor.empty(4,3) @ Tensor.empty(3,5))` → `schedule_linear` → the kernel SINK → `full_rewrite_to_sink` → `linearize` → `Device['CPU'].renderer.render(list(lines))` |
| **the bytes** | **port 547, upstream 547** — the same length |
| **the verdict** | **THE SAME KERNEL, THE SAME THREE BUFFERS, THE SAME TWO LOOPS, THE SAME STORE — AND THE LOADS ARE NOW GROUPED BY BUFFER** |

**⇒ THE PORT's ARENA AND THE PORT's RENDERER HAVE MET ON A REAL SCHEDULED PROGRAM, AND
THE RESULT IS UPSTREAM's KERNEL.** **⇒ AND THE *ONLY* REMAINING DIFFERENCE IS THE ORDER
OF THREE SAME-BUFFER LOADS, AND ITS CAUSE IS MEASURED, NAMED, AND ALREADY DOCUMENTED BY
THE PORT's OWN `linearizer.bend` (SEE §3).**

## THE THREE THINGS THIS MEASUREMENT ESTABLISHED, IN ORDER

### 1. THE PORT's OWN TOPOSORT IS **EXACTLY** UPSTREAM's — MEASURED

The port's `ns_ops` (the op names of the port's own toposort) and upstream's toposort op
names are **the same 50-element sequence, in the same order**:

```
CONST,PARAM,CONST,CAST,RANGE,CONST,CAST,MUL,AFTER,RANGE,ADD,INDEX,CONST,PARAM,CONST,CAST,MUL,INDEX,LOAD,...
```

**⇒ ⇒ SO THE PORT's TOPOSORT IS NOT THE DEFECT.** **⇒ AND THIS WAS NOT OBVIOUS: THE
FIRST ATTEMPT USED `schedule/__init__.bend`'s `sc_topo_of`, WHICH ANSWERED **ZERO**
NODES, BECAUSE ITS `sc_gate` (`schedule/__init__.bend:511-517`) GATES THE KERNEL SINK
OUT — `sc_gate.of`'s `case O.OpsSINK{} a: Bool.not(sc_gate.ker(a))`. **⇒ UPSTREAM's
`linearize` USES **NO GATE** (`linearizer.py:10` IS `sink.toposort()`), AND THE PORT's
OWN `O.UOp.toposort_nocalls` (`ops.bend:3376`) IS EXACTLY THAT — NO GATE,
`enter_calls=False`.** **⇒ ⇒ SO THE FIX WAS TO USE THE PORT's OWN UNGATED TOPOSORT,
AND THE `sc_topo_of` PATH IS A GATED SCHEDULER WALK THAT DOES NOT ANSWER THIS
QUESTION.**

### 2. THE PORT's OWN `vms` TABLE HAD **ZERO** VMAX VALUES — AND THAT WAS A **REAL
   DEFECT IN THE PORT's FOLD**, NOT IN THE HARNESS

The `vms` TABLE IS WHAT `linearize` READS FOR EACH NODE's RUN COUNT
(`linearizer.bend:644`: `vms = [ n0, v0, ..., v_{n0-1}, n1, ... ]`, LENGTH-PREFIXED).
**⇒ THE PORT's TABLE HAD THE RIGHT *LENGTH* (97, EXACTLY UPSTREAM's) AND **ZERO** FOR
EVERY VMAX.**

```
port:     0,0,0,0,1,0,0,0,1,0,1,0,2,0,0,2,0,0,2,...
upstream: 0,0,0,0,1,3,0,0,1,3,1,3,2,4,3,2,3,4,2,3,4,...
```

**⇒ ⇒ AND THE CAUSE IS `F.rng_width` (`uop/fold.bend:1478`), WHICH READS A RANGE's
BOUND AND **REFUSES ANY BOUND THAT IS NOT A CONST**:

```bend
def rng_width.end(op: O.Op, +ar: O.Arena, e: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsCONST{}: const_i64(O.Arena.arg(ar, e))
    case _: None{}
```

**⇒ AND THE PORT's `g_lin` RANGE's BOUND IS AN **AFTER**, NOT A CONST**
(`graphcmp.bend:1127-1128`: `+af = O.UOp.new(..., O.OpsAFTER{}, [O.Found.i(c5i), O.Found.i(ra)], ...)`
and `+rb = O.UOp.new(..., O.OpsRANGE{}, [O.Found.i(af)], ...)`) — **BECAUSE
`pm_simplify_ranges` REWRITES A RANGE's BOUND INTO `AFTER(bound, prev_range)`.**

**⇒ ⇒ AND UPSTREAM READS THE VMAX THROUGH IT: A RANGE's `_min_max` IS
`(self.src[0]-1).vmax` (`ops.py:1147`), AN AFTER's IS ITS `src[0]`'s (`ops.py:457`), AND
A CAST PASSES ITS `src[0]` THROUGH (`ops.py:142`'s GROUP).** **⇒ SO THE CHAIN IS
`RANGE → AFTER → CAST → CONST`, AND THE HARNESS READS IT WITH AN EXPLICIT THREE-LEVEL
UNROLL (`lin_width_end`/`end2`/`end3`).**

**⇒ ⇒ AND THE UNROLL IS AN UNROLL BECAUSE OF BEND's OWN RULES, NOT BY CHOICE: A
`match` MAY NOT CALL THE DEF IT IS IN (THE ERROR IS *"an unfilled law: live code cannot
use it"*), AND A SELF-CALL's ARGUMENTS ARE READ LEFT TO RIGHT, EACH PASSED UNCHANGED
UNTIL ONE SHRINKS (SO A COMPUTED LIST IN FRONT OF A PASS-ONE ARGUMENT IS REFUSED).**

**⇒ ⇒ AND WITH THE VMAX READ CORRECTLY, **THE LOADS GROUPED BY BUFFER** — WHICH IS THE
VISIBLE CHANGE IN THE OUTPUT:**

```
before (vmax all zero):  val0=data1_12+alu0 ; val1=data2_15+Lidx2 ; val2=data1_12+(alu0+1) ; ...
after  (vmax correct):   val0=data1_12+alu0 ; val1=data1_12+(alu0+1) ; val2=data1_12+(alu0+2) ; ...
```

**⇒ THAT IS THE WHOLE DIFFERENCE BETWEEN "WRONG ORDER" AND "RIGHT ORDER" FOR THE
LOADS, AND IT WAS ONE MISSING CHAIN IN A FOLD READER.**

### 3. THE REMAINING DIFFERENCE IS **`TUPLE_ORDER`**, AND **THE PORT's OWN FILE ALREADY
   SAYS SO**

The three same-buffer loads are in a different order within their group, and the FMA's
terms are correspondingly permuted. **⇒ THE CAUSE IS UPSTREAM's `linearizer.py:36`:**

```python
nkey = {u:i for i,u in enumerate(sorted(lst, key=lambda x: priorities[x]+(x.tuplize if TUPLE_ORDER else ())))}
```

**⇒ UPSTREAM's `priorities[x]` IS A **FOUR**-TUPLE `(run_count, len(u.ranges), priority,
extra)` (`linearizer.py:33`), AND THE FINAL TIE-BREAK IS `x.tuplize`
(`ops.py:316-318`), WHICH IS `(self.op.value, repr(self.arg), self.dtype, *src.tuplize)`.**

**⇒ AND THE PORT's `lt_key` (`linearizer.bend:521`) IS **TWO** COMPONENTS:
`rc * 64 + po`.** **⇒ SO THE PORT OMITS `len(u.ranges)` AND `x.tuplize`.**

**⇒ ⇒ AND **THE PORT's OWN FILE NAMES THIS EXACTLY**, AT `linearizer.bend:115-125`:

> `W2 x.tuplize -- linearizer.py:36 ... TUPLE_ORDER is a real ContextVar
> (helpers.py:280, default 1) and setting it 0 makes the key the STABLE
> (run_count, priority) pair, which is exactly List.sort with <=, measured stable. So
> this file ports the TUPLE_ORDER=0 lane exactly and names the =1 lane W2.`

**⇒ ⇒ MEASURED, UPSTREAM's DEFAULT IS `1` (`tinygrad/helpers.py:282`:
`TUPLE_ORDER = ContextVar("TUPLE_ORDER", 1)`), SO **THE PORT IS ON THE `TUPLE_ORDER=0`
LANE WHILE UPSTREAM IS ON `=1`** — **⇒ AND THAT IS WHY THE ORACLE DISAGREES, AND IT IS
NOT A MYSTERY: IT IS A NAMED WALL IN THE PORT's OWN FILE.**

**⇒ ⇒ AND MEASURED, THE PORT's OWN `linearizer.bend:1215-1218` ALREADY QUANTIFIES IT:
`lin_ties=47` OF 171 PAIRS TIE ON `(run_count, priority)` — **⇒ 47 OF 171 PAIRS ARE
DECIDED BY `tuplize` ALONE ON THE PORT's OWN FIXTURE.****

**⇒ ⇒ AND THE MEASUREMENT CONFIRMS IT DIRECTLY: SORTING UPSTREAM's LIST WITH AND
WITHOUT THE `x.tuplize` TIE-BREAK **DIFFERS** (THE FIRST DIFFERENCE IS AT POSITION 4),
WHILE THE PORT's `TUPLE_ORDER=0` KEY IS WHAT IT USES.**

## WHAT IS **NOT** CLAIMED, SPECIFICALLY AND NAMED

1. **THE `lin` FIXTURE IS HAND-BUILT, NOT DRIVEN BY THE PORT's OWN SCHEDULER.**
   **⇒ THE REMAINING GAP IS "THE PORT's OWN SCHEDULER MUST PRODUCE THIS ARENA",** WHICH
   IS THE ENGINE's JOB (`schedule/rangeify.bend`'s `eng_*`, BUILT AND COMPILING BUT
   UNWIRED AND UNMEASURED).
2. **`TUPLE_ORDER=1` IS NOT PORTED.** **⇒ THE PORT IS ON `=0` AND UPSTREAM IS ON `=1`,
   AND **THE FIX IS TO PORT `x.tuplize`** — WHICH IS A **STRUCTURAL KEY** HOLDING A
   `repr` OF AN ARBITRARY ARG AND A DTYPE VALUE (`ops.py:316-318`), **⇒ SO IT IS NOT
   A `U32` AND THE PORT's SINGLE-`U32` KEY (`lt_key`) CANNOT HOLD IT AS IS.**
3. **`F.rng_width` STILL REFUSES AN AFTER-BOUND RANGE.** **⇒ THE HARNESS READS THE
   CHAIN ITSELF (`lin_width_end`) RATHER THAN FIXING THE FOLD, **⇒ SO THE FIX IN THE
   PORT IS `uop/fold.bend`'s `rng_width.end`, WHICH SHOULD DESCEND THE SAME CHAIN.**
4. **THE PORT's `len(u.ranges)` COMPONENT IS ALSO ABSENT FROM `lt_key`.**

## THE COST

**ONE `bend` PROCESS AT A TIME THROUGHOUT. THE WHOLE COMPARISON IS ~1.3 s OF `bend` TIME
AND 0.5 s OF CPython TIME.**
