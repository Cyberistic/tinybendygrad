# shaders/ — a fragment shader as a tensor program

**The claim: Shadertoy's expression vocabulary is expressible in this port's UOps without
extending the IR.** Not "a shader renders" — that is the runtime half and it is not here.

It is the smallest anti-aliased shape that uses the four things a Shadertoy author reaches
for and a tensor model does not have on the shelf:

| Shadertoy | here | why it is not free |
|---|---|---|
| `length(p)` | `sqrt(x*x + y*y)` | a tensor has no `vec2`, so `p` is **two buffers** |
| `fwidth(d)` | `pad` + `shrink` + `sub` + `abs` | screen-space derivatives are an *invocation-neighbourhood* notion and UOp has none |
| `smoothstep` | `clamp` composed from arithmetic | GLSL vocabulary, **absent from tinygrad**: `grep -c smoothstep tinygrad/` is 0 |
| `clamp(x,0,1)` | `max(x,0)` and `x - max(x-1,0)` | there is **no `Ops.MIN`**, upstream or here |

## Run it

```sh
.venv/bin/python shaders/shader-gate.py            # PASS / FAIL / DEAD / REFUSED
.venv/bin/python shaders/shader-gate.py --plant     # the gate must go RED
bin/bend shaders/shader-rows.bend                       # the port's graph, as rows
.venv/bin/python shaders/shader-oracle.py --values  # the formula, as numbers
```

`shader-gate.py` answers **two** questions and the exit status covers both:

* **graph parity** — 2 079 rows, the port's `bin/bend` against CPython's tinygrad, byte for
  byte after normalising one float spelling (the port prints the exact f32
  `9.999999747378752e-05`; CPython prints the shortest repr of the double `0.0001`).
* **is it a circle** — `centre=1.0000 corner=0.0000 partial=95`, then `VALUES OK`.
  `partial` is the count of pixels with an alpha strictly between 0 and 1: the
  anti-aliasing band. **It is the only number that sees `fwidth`**, because a shader that
  multiplies the derivative by zero still agrees with its own oracle. 95 of 256 at 16×16 is
  the *resolution*, not a defect: `fwidth = |dFdx| + |dFdy|` spans a band ≈ 4 px wide here
  and ≈ 1 px at 512².

`--plant` rewrites `SH_R()` in a **copy of `shader.bend`** so the *port's* graph moves, and
requires the diff to fire. Measured: `PLANT FIRED -- row 37`.

## Where the derivative comes from

A quad neighbour needs no new op:

```
right(d) = shrink(pad(d, +1 col), drop col 0)      # movement ops
dFdx(d)  = d - right(d)
fwidth   = abs(dFdx) + abs(dFdy)
```

**This is the result worth having.** In most systems autodiff is the hard half; here autodiff
is already done (32 rules, exercised by the corpus's `grad`/`gral` graphs) and the *screen-space*
derivative is the half that looks missing — and it is a movement op.

## The pipeline run: four links, and a measured negative

`shader-run.bend` takes the shader through the port's own compiler. **It runs and produces a
WRONG kernel** (`*(buf0+Lidx0) = 1`, one buffer instead of three), so it is a measured
negative and not a renderer. What it established on the way is worth more than the render:

| link | without it |
|---|---|
| `tn_assign_store` | a bare expression under a SINK schedules **nothing** — `kernels=0`, no error |
| `rr_kernel_graph` | `SCH.schedule` **is** `create_schedule`, which walks existing kernels and creates none |
| per-body `linearize` | it takes **one kernel**; given the `LINEAR` it renders `UNHANDLED(Ops.LINEAR)` |
| `vms` widths | `Nil{}` gives every node key 1, the sort collapses, and the body is **one op** |

**The kernel graph is right, and the loss is now pinned past it — measured, not inferred.**
`sched-probe.bend` (a probe, gitignored) walked the 2-D gate lane node by node:

* the **tensor** graph is healthy — `detT2` counts 4 `PAD` + 4 `SHRINK`, and the movement
  wrapper is clean (`pad4`: `sh_right` returns `Ops.SHRINK` with dims `1616`, the identity
  test answers `F`, so the shrink is kept; the double call in `mxw_pairs_node2` is wasted
  work, not a defect);
* rangify **consumes the `SHRINK`s** — `rr_mvx`'s arm puts `r+off` in the range table
  (`rangify.bend:680`, upstream `indexing.py:166`) and the node answers its src per Rule 5 —
  but **keeps the `PAD`s**: `rr_ap_wall_hit` (`rangify.bend:1474`) names pad a wall, so the
  node passes into the kernel graph unchanged. Upstream's kernel graph holds **no** movement
  ops (`get_kernel_graph`, `rangeify.py:341`: "convert movement ops to ranges");
* the surviving `PAD`'s 2-D marg meets the flattened kernel graph and **the fold refuses it**
  — the same refusal the standalone flat pad shows (`padflat=:GAP`) — so the `PAD` gets no
  fold row, the formula tail loses its rows, and the `END` has none;
* `F.fold.ended(END)` is `None` while the structural answer is 2 (`ended_direct=2`) — the
  structure is right, the fold route is broken. The END's own RANGE srcs are never popped,
  the 2 WEAK ranges read as open, `sk_open=False`, `split_store` refuses, no `CALL` is
  built, and the store's value is dropped: `*(buf0+Lidx0) = 1`.

**The cure is upstream's pad lane, and it is a milestone, not a patch.** `apply_movement_op`
(`indexing.py:169-173`) shifts and masks the ranges — `(r-off).valid(gate)`, which is
`gate.where(r-off, Invalid)` (`ops.py:636`) — and `convert_pad_to_where_to_keep_behavior_local`
(`indexing.py:98-103`) turns the pad into a value-level `WHERE(valid, indexed_value, 0)`.
The neighbour shift can only apply to a **buffered** read, and the port never realizes `dd`
(there is no store of it; the pad names the inline chain), so the fix is the other half of
W3 — `valid`/`Invalid` plus the realize-forcing of movement-op sources. A partial arm would
not do: the pad's zero-fill is load-bearing at the last column, so a wrong arm trades a loud
`= 1` for silently wrong border pixels.

`buf-schedules.bend` remains the control: the same chain over `a + b` on two `BUFFER`s
answers `kernels=1` **and renders the add**, so the scheduler is not broken — this graph's
pad is.

## The schedule now refuses instead of rendering a wrong kernel

Upstream's `create_schedule` **asserts** that an END's src0 is a CALL
(`schedule/__init__.py:46`) — the graph whose kernel graph was never split — and the port
had no such check: it unwrapped the END to its STORE, dropped the store's value, and
rendered `*(buf0+Lidx0) = 1`. The port now answers an **empty schedule** for that graph
(`sched_unbacked`), because a schedule missing a kernel is a schedule missing an output.
MEASURED, before and after, same tree: `kernels=1` + `*(buf0+Lidx0) = 1` → `kernels=0` +
`refused=END src[0] should be KERNEL, not Ops.STORE` -- upstream's own assertion
text (`schedule/__init__.py:46`) -- and no C is compiled at all.

**And the gate that should have caught it had two defects, one masking the other.** The
schedule gate's `bend=` field still pointed at the **library** after `d404c64d9` moved the
135 rows into the driver `gates/schedule-init-gate.bend` — so the port lane ran a file with
no `main` and read bend's proof check ("ALL PROOFS CHECK", 2 lines) instead of 135 rows.
The CPython lane **dies first** on master (`RuntimeError: cycle detected in assign graph`,
the re-vendor changed `create_schedule`), which is why the stale field went unnoticed. The
field is fixed (the driver emits 135 rows and compiles natively, rc=0); the oracle's
rebasing is a separate job, and the port change is **inert for every fixture** (no one of
the 135 rows moves) — which is also its gap: no fixture exercises it yet.

**And the runner's buffers were flat where upstream's are (16,16).** Upstream's
`Tensor.empty((16,16))` is `ALLOC(prod)` + `RESHAPE(shape)` and the formula is
two-dimensional, so a flat `(256,)` buffer is a graph upstream would never build — the
`PAD`'s marg has two pairs and a flat input has one dim, and the fold refuses that on the
length check (`len(ps) != len(self.marg)`, `ops.py:397-405`). MEASURED on the runner's
**own** tensor graph: the first `PAD` answers `18:GAP` with the flat buffers and `21:ok`
with the (16,16) ones. The runner reshapes all three buffers now (`shaders/` is not in
the substrate, so this does not stale the corpus). The kernel graph's PAD wall is a
separate matter — above.

## The realize the merge forgot, and what it exposes

Upstream's merge ends with `if len(_realize_axis): rctx.realize_map[x] = _realize_axis`
(`indexing.py:267`), and the port's `rr_merge` **minted the new RANGE and recorded
nothing** — so a node read at two different ranges (the shader's `dd`, read at `r` by the
formula and at `r+1` by the neighbour) was never realized, and a node that is never
realized has no buffer, so its second read has nothing to read from. Implemented in the
worktree, it produces upstream's shape — the kernel graph now carries
`STAGE:none:MAX,RANGE,RANGE` and `INDEX:none:STAGE,RANGE,RANGE` — **and it makes a cycle**:
the kernel graph's reachable set falls from 64 nodes to 39 (`topon=39`), the END falls
outside it, and the ranges change (`rngs=2` where the unrealized graph had 1). The 39 nodes
contain both `STAGE`s and **none** of the fw term's nodes (the MAX, the PADs and the RECIP
are absent), so the cycle runs through the realized value's own subtree. The port's
substitution is upstream-shaped (`rr_ap_stage_src` builds `STAGE(s, closed_ranges)` and
indexes it by the *consumer's* input ranges, `indexing.py:80-91`), so the failure is in the
**realize decision** or the **ranges it mints**: the kernel graph comes out carrying
**five `STAGE`s** (`STAGE:none:MAX`, `STAGE:none:ADD` ×3, and `INDEX:none:STAGE,INDEX,RANGE`
— an INDEX with three srcs) — and without the realize the graph carries **zero**
`STAGE`s — so the decision fires on five nodes where upstream would fire on one or two,
and each firing mints new ranges for every axis and stages the value: a nest of STAGEs, and
the fw term falls out of the graph. The comparison itself is **upstream-shaped**
(`IxRngs{inp, outp}` is the (input ranges, output ranges) pair — `indexing.bend:250-252` —
and upstream compares `range_map[c][0]`, the input ranges, `indexing.py:222`), so what is
missing is what upstream does with the *old* ranges: upstream **ends** the realized node's
old ranges (`ending_ranges[x] = []`, `indexing.py:226-228`) and keeps the consumers' ranges
where they agree, while the port's `rr_merge` mints a new range for *every* axis and ends
nothing. **That is the next thing to read** — the realize's *ending*, not its decision —
and the realize is not landed.

**And the pair underneath it.** Upstream's pair IS `(rngs, out_rngs)` (`indexing.py:307`) — so
the port's `(inp, outp)` (`indexing.bend:250-252`) is upstream's pair, and upstream's
`closed_ranges` (`indexing.py:82`) is the output ranges the port's `rr_ap_closed` reads; the
name is upstream's, the value is the same. *(An earlier revision of this file said the pair's
second element was not upstream's. It was wrong.)* The real gap is one line: upstream sets
`rngs = out_rngs` for **every** node (`indexing.py:283`) — a node's input ranges *are* its
output ranges — while the port's `inp` is `Nil{}` for every node, and `rr_one_rngs`, the
thing the realize decision compares, reads `IxRngs.inp`. **So the port's comparison is over
empty lists**, which is why the decision's granularity changed nothing when I measured it,
and why the five `STAGE`s are not the new rule firing: that rule needs a disagreement, and
with empty lists there is never one — they come from the port's *other* realize rules (the
WAR rule, `realize_store_after_src`), which the newly minted ranges perturb. The realize this
graph needs is upstream's **range-map-time** one (`indexing.py:267`) — a node read at two
different ranges — and the port cannot see that, because its per-node input ranges are
empty. **That is the next reading**, and it is a model change.

*(An earlier revision of this file called the port's gated toposort shallow — 7 of 138
nodes — and that was WRONG: it was the flat-(256,) graph. With the (16,16) buffers the same
traversal answers 64 — the whole reachable set — and the tensor graph's 56 of 56.)*

**And a genuinely missing port.** An `ALLOC` has no realize-time rebind: `UOp.new_buffer` is
`TODO(p3)` in `ops.bend`, and upstream's `linear_with_vars` swaps `ALLOC` → `BUFFER` there.
That is why the runner takes `mxw_buf` (BUFFERs) and why a graph built the `Tensor.empty`
way — which is what the graph gate correctly builds, because CPython builds it — cannot be
scheduled at all.

## What upstream's kernel looks like, and the PAD arm that answers it

Upstream's own pipeline answers what the port's kernel graph has to BECOME, and the
answer is a measurement, not an inference: `shaders/upstream-kernel-oracle.py` patches
`create_schedule` -- the one place upstream turns a graph into kernels
(`tinygrad/schedule/__init__.py:117`) -- realizes the shader's formula and dumps the
kernel sink it is handed.

    kg0_0_census=ADD=17 CMPLT=2 CONST=11 END=1 INDEX=7 MAX=4 MUL=15 PARAM=3 RANGE=2 RECIP=1 SINK=1 SQRT=3 STORE=1 WHERE=4
    kg0_0_end_srcs=STORE RANGE RANGE

**THREE FACTS, AND THE PORT HAS NONE OF THEM YET.** Upstream's SCHEDULED kernel carries
**no `PAD` and no `SHRINK`**: the `PAD` became a `WHERE` (upstream's
`convert_pad_to_where_to_keep_behavior_local`, `indexing.py:98-103` -- the value's own
zero fill, gated by the range's valid) and the `SHRINK` became an `INDEX` at a shifted
range. The distance field is **MATERIALIZED** (`STORE=1`): upstream realizes a node whose
consumers read it at different ranges (`indexing.py:267`), so the neighbour read is a
buffered read, not a register read. And the two `CMPLT`s and four `WHERE`s are the two
pads' gates -- one non-trivial axis each -- which is exactly what upstream's PAD arm
(`indexing.py:169-173`) mints.

**THE PAD ARM, LANDED.** Upstream's arm is

    rngs = tuple(r if (sz == sh and off == 0) else (r-off).valid(graph_rewrite((r >= off) & (r < (sh+off)),
      symbolic+pm_simplify_valid, name="pad")) for r,sh,(off,sz) in zip(rngs, in_shape, arg))

and every part of it is a trap:

* `sz` IS THE MARG's SECOND ELEMENT (`tinygrad/uop/ops.py:771`: `marg` IS
  `zip(src[1].as_shape, src[2].as_shape)`) and `sh` IS THE INPUT's DIM (`in_shape` IS
  `x.src[0].shape`), so the IDENTITY TEST IS `sz == sh and off == 0`;
* THE GATE's UPPER BOUND IS `sh+off` -- THE INPUT's EXTENT SHIFTED -- AND **NOT** `sz`,
  WHICH IS `sh+off+after` (`tinygrad/mixin/movement.py:188`: the marg's size is
  `s+x[0]+x[1]`). *(An earlier revision of this file said `sz` and `sh+off` were the same
  thing. They are not, and the difference is the whole gate.)*
* `r >= off` HAS NO `CMPGE` UPSTREAM EITHER, so it is `NOT (r < off)`
  (`tinygrad/mixin/elementwise.py:326`: `__ge__` IS `(self < x).logical_not()`);
* `.valid(gate)` IS `cond.where(self, self.const_like(Invalid))`
  (`tinygrad/uop/ops.py:664`), AND THE PORT HAS IT AS `UOp.valid_of`
  (`tinybendygrad/uop/ops.bend:1905`).

The port's arm (`rr_pad`, `tinybendygrad/schedule/rangify.bend`) mints `(r-off)` and
gates it with `(NOT (r < off)) AND (r < sh+off)`, and MEASURED on the shader's own graph
the range it mints is now CONSUMED: the probe's `det2` row reads
`#138:Ops.ADD[#135:Ops.RANGE:ok,#137:Ops.MUL:ok]` -- the `ADD` IS THE SHIFTED RANGE --
where before the arm the PAD's range was minted and never read.

**AND THE SHRINK ARM, WHICH WAS READING THE TABLE BY THE WRONG KEY.** Upstream's SHRINK
arm is `tuple(a if off == 0 else a+off for a,(off,_) in zip(rngs, arg))` -- `a` IS THE
RANGE NODE. In the port the range is a TABLE ENTRY (`IxRange{kind, idx, ext}`,
`indexing.bend:209`), and the arm read it by `ix_rg_n(pos)` -- a table POSITION read as
an ARENA INDEX. It reads `ix_tbl_at(tbl, pos)` now and materialises the range from it
(`ix_rg_node`), which is upstream's `a`. The `off == 0` case keeps the entry as it is:
MEASURED, minting a fresh entry moved the END and the index math onto different RANGE
nodes, so `_ranges` saw two open ranges and `split_store` refused.

**RULE 2, LANDED: THE `PAD` IS A `WHERE` NOW.** Upstream's rule 2
(`convert_pad_to_where_to_keep_behavior_local`, `indexing.py:98-103`) replaces the `PAD`
with `valid.where(source, 0)`, the valid being the AND of the input ranges' valids
(`ops.py:640`: a range's valid is the gate its `WHERE` carries) -- and the port has it
(`rr_ap_pad_where`). The `STACK` stays the only wall (rule 3 needs `_stack_select`).
MEASURED, the schedule builds a kernel where it built none (`kernels=1`), and the graph
is `SINK -> AFTER -> (INDEX, CALL)` with a `CALL` of three buffers -- upstream's shape
(`PARAM=3` in the oracle's census).

**AND THE RUNNER EMITS C FOR THE SHADER.** `create_schedule` hands back the kernel
BODIES as `CALL`s (`tinygrad/schedule/__init__.py:71`: `k.replace(src=(k.body,
*buf_uops))`), and the linearizer takes the BODY, and `toposort_nocalls` does not descend
into a `CALL` -- so a `CALL`'s walk was the `CALL` itself and the body was never
rendered: the C said `UNHANDLED(Ops.CALL)`. The runner unwraps it (`cus_body`) and the
kernel is now `circle(data0_256, data1_256, data2_256)`, 788 lines, with the distance
field's `__builtin_sqrtf` in it and the store `*(data0_256+((Lidx0+(16*Lidx1))%256))`.

**FOUR DEFECTS ARE LEFT IN THE C, AND EACH ONE IS NAMED.**

| what | why |
|---|---|
| `UNHANDLED(Ops.MAX)` | the port's `code_for_base` is upstream's 21-key dict (`cstyle.py:153-161`) and that dict has no `MAX` arm -- **and neither does upstream's** (`cstyle.py` has no `MAX` at all). A `MAX` reaches the C because the port does not run upstream's symbolic normalization, which is a recorded deviation (`rangify.bend`: "the symbolic normalization upstream runs after it is NOT applied"). The `MAX` has to be lowered before the C, not taught to the emitter. |
| `(&)?alu1:0.0f` | the `WHERE`'s CONDITION is missing: the gate is not riding on the range. MEASURED, the port's `AND` has two `CONST` operands where upstream's gate is a `CMPLT` -- so the valid is `True` and the zero-fill is unconditional. |
| `weakint Lidx0` | the strong dtype: upstream's `UOp.dtype` is a property that never returns `weakint` (`tinygrad/mixin/dtype.py:17`), and the port has neither it nor `commit_int`. |
| four nested range loops | the kernel's `END` closes FOUR ranges where upstream's closes TWO (`kg0_0_end_srcs=STORE RANGE RANGE`). |

**THE MEASUREMENT THAT EXPLAINS THE REST: THE RANGE MAP IS EMPTY.** The probe's row
`rmpad` (the range map's entry for the shader's `PAD`) reads

    rmpad=rm=False False in= out= tbl=1 rmn=0

`rmn=0` is the range map's SIZE and `tbl=1` is the RANGE TABLE's size -- **the range map
holds NOTHING and the table holds only the CONST 0**. So the port's whole range-map
stage is INERT for this graph: the PAD arm, the SHRINK arm, the zero-fill and the gate
never run, and the kernel graph's four ranges and its `WHERE` come from the ENGINE's own
stage (`eng_after_rangeify`), which is why the schedule builds a kernel but the gate does
not ride.

**WHY, AND IT IS UPSTREAM's LINE.** Upstream's propagation starts at the REALIZED node:
`if x in rctx.realize_map: out_rngs = tuple(rctx.new_range(s) for s in x.shape)`
(`indexing.py:222-225`) -- and everything else inherits its ranges from its consumers
(`indexing.py:233-235`). The port has that shape (`rr_p1.real` mints, `rr_p1.one`
inherits, `rr_p1.none` is upstream's `continue`), but `rr_p1.real` mints NOTHING, because
the shape it reads is the FOLD's shape and **the fold has no row for the node** -- the
same fold refusal this file already named ("the fold refuses its 2-D marg -> END has no
fold row"). An empty shape mints no ranges, the propagation has no seed, and the range
map stays empty.

**THE SEED, AND WHERE IT IS READ.** The seed is the REALIZED node, and the realized node
is the `STORE` (upstream's `pm_generate_realize_map` realizes every `STORE`:
`tinygrad/schedule/indexing.py:36-37`), and upstream's `STORE` shape IS ITS DST's shape
(this file said so before: "upstream reads `x.shape`, and for a STORE that IS
`src[0].shape`"). The port reads the same thing (`rr_p1.shape`: a `STORE` reads its
dst's dims). So the seed is the dst's DIMS -- and the dst in the kernel graph is a
`BUFFER`, and the probe's `gaps` row already says the `BUFFER` HAS a fold row
(`#54:Ops.BUFFER`) while the `END` and the `STORE` do not
(`#170:Ops.END:GAP,#169:Ops.STORE:GAP`).

**AND A DIVERGENCE THAT IS NOT THE BLOCKER BUT IS REAL:** upstream's `END` shape is the
RANGES IT CLOSES (`tinygrad/uop/ops.py:446`: `if self.op is Ops.END: return tuple(r for
r in self.src[1:] if r.op is Ops.RANGE)`) and the port's fold says `thru0` -- the first
src's shape (`tinybendygrad/uop/fold.bend:1756`). It is not the blocker (the `END` is
not the seed; the `STORE` is) but it is a divergence and it is on the list.

**AND THE SEED'S ABSENCE IS MEASURED TOO: THE REALIZE MAP IS EMPTY.** The port has the
instrument (`rr_rmap_row`: "which nodes the apply's realize map holds") and the probe
now runs it on the runner's own graph:

    rmap=

**NOTHING.** Upstream's realize map holds every `STORE` (`indexing.py:36-37`:
`realize(tr)` for `UPat(Ops.STORE)`), and the realized node is where upstream seeds the
propagation (`indexing.py:222-225`). The port's `rr_realize_one` has the same three
rules (a `STORE`, an `MSTACK`, a custom `CALL`) -- and it answers NOTHING for every
node, so `rr_p1.real` never fires, so no range is ever minted, so the propagation has no
seed, so the range map is empty (`rmn=0`), so the table never grows (`tbl=1`), so the
PAD arm, the SHRINK arm, the zero-fill and the gate are all inert.

The seed's dims, measured too, are not the problem either: the three `BUFFER`s of the
kernel graph have fold dims `256` (`seedbuf= 54=256 2=256 7=256`) -- FLAT, not `(16,16)`
-- so even a working realize map would mint ONE range of 256, and upstream's kernel has
TWO. The `STORE` itself has no fold dims at all (`seedstore= 204=`).

**AND A CONTRADICTION THE NEXT INSTRUMENT RAISED.** The probe now calls the def itself
on the runner's graph and censuses that graph's toposort:

    sreal=
    tcensus=Ops.NOOP

**THE REALIZE DEF ANSWERS NOTHING FOR EVERY `STORE`** (`sreal=` is empty ✓ -- the
`STORE`s are listed with the LENGTH of `rr_realize_one`'s answer ✓, and every one of
them is 0 ✓) **AND THE RUNNER's GRAPH's TOPOSORT READS AS A SINGLE `NOOP`** ✗ -- while
the KERNEL graph, built from that same sink, has 64 nodes and a `STORE` in it ✓ (the
`kg=` dump ✓). So the toposort the realize map is built from and the graph the kernel
comes from DISAGREE ✗✗ -- and one of the two readings is the probe's own ✗ (the
`tcensus` row is new ✗ and unverified ✗). Either way it is the toposort or the def, and
both are in `rr_realize`/`rr_realize_one` ✓.

**THE ROOT CAUSE, MEASURED IN THE ARENA.** The probe reads the arena itself -- every
node's op, by id, not by toposort -- and the toposort's size:

    tsz=1
    arops=Ops.NOOP,Ops.CONST,Ops.BUFFER,Ops.CONST,Ops.STACK,Ops.RESHAPE,Ops.MUL,Ops.BUFFER,
           Ops.RESHAPE,Ops.MUL,Ops.ADD,Ops.SQRT,...,Ops.PAD,...,Ops.SHRINK,...,Ops.PAD,...,Ops.SHRINK,...

**THE PORT's TOPOSORT OF THE RUNNER's SINK IS ONE NODE** (`tsz=1`) **AND THE WHOLE
FORMULA IS IN THE ARENA** (the census ✓ -- the `PAD`s, the `SHRINK`s, the `SQRT`, the
`MAX` ✓, all of it ✓).

**AND A CORRECTION TO THE WORDING, BECAUSE THE DISTINCTION IS THE FIX.** The formula IS
the sink's subtree: `sink_of()` returns the `AFTER` (`tn_assign_store` returns
`O.UOp.after`, `tensor.bend:1550-1552`), and the `AFTER`'s srcs are the dst and the
`STORE`, and the `STORE`'s srcs are the dst and the value -- the formula. So the graph
is fine. **WHAT IS NOT FINE IS THE PORT's TOPOSORT**: `O.UOp.toposort` is upstream's
UNGATED walk (`ops.py:280`, the default gate is "everything" ✓) and it answers ONE node
for a sink whose subtree is the whole graph ✗ -- so the port's toposort GATES the
`AFTER` ✗✗. Upstream's range map runs on `tsink.toposort(gate_kernel_sink)`
(`indexing.py:194`), whose gate is about KERNEL boundaries ✓ -- and the port's
`rr_range_map` calls the ungated `O.UOp.toposort` ✓ and gets the gated answer ✗.

**=> THE NEXT READING IS IN THE PORT's TOPOSORT, NOT IN THE RUNNER's GRAPH: WHAT GATES
THE `AFTER`?** (`O.UOp.toposort` -> `Topo.push` -> the worker.)

**=> THE PORT's RANGE-MAP STAGE AND THE ENGINE LOOK AT DIFFERENT GRAPHS.** The range-map
stage works on the sink's subtree (`rr_range_map` walks `rr_rev(topo)` -- one node ✗),
and the ENGINE works on the FOLD, which is arena-wide (`F.folded(ar)` -- 64 nodes ✓).
That is why the kernel graph has 64 nodes and a `STORE` ✓ while the range map is empty ✓,
the realize map is empty ✓ (no `STORE` in a one-node toposort ✗), the table never grows
✓, and the PAD arm, the SHRINK arm, the zero-fill and the gate are all inert ✓.

**=> AND UPSTREAM's `sink_of()`-SHAPED GRAPH HAS THE STORE, SO THE REALIZE MAP IS NOT
EMPTY THERE.** Upstream's realize map holds every `STORE` (`indexing.py:36-37`) and the
runner's graph here has **no `STORE` at all** (the census ✗) -- so the port's realize
map is empty for a reason upstream does not have.

**SO THE NEXT READING MOVES OUT OF THE RANGIFY AND INTO THE RUNNER's GRAPH: WHAT DOES
`sink_of()` RETURN, AND WHY IS THE FORMULA NOT UNDER IT?** The port's kernel graph has
always been the fold's arena-wide graph, so upstream's range-map stage has never run on
it.

**SO THE NEXT READING IS ONE LINE: WHY DOES `rr_realize_one` ANSWER NOTHING FOR A
`STORE`?** `rr_is_store` is `O.eq_op(O.Arena.op(ar, u), O.OpsSTORE{})` and
`rr_store_entries` is `rr_store_real` -- the same shape as upstream's rule. Either the
toposort the map is built from does not contain the `STORE`, or the map's entries are
dropped on the way into the context (`ix_ctx_realize`).

**SO THE ORDER OF THE REMAINING WORK IS REVERSED FROM WHAT THE PLAN SAID.** The gate
cannot ride before the fold gives the range map a seed: the fold's refusal is upstream of
the gate, the PAD arm and the zero-fill. The plan's `THE GATE DOES NOT RIDE` is a
symptom; the fold's missing row is the disease.

**AND THE GRAPH IS STILL ONE KERNEL WHERE UPSTREAM'S IS ONE KERNEL BUT NOT THE SAME
ONE.** The oracle's body has `INDEX=7 WHERE=4 CMPLT=2 SQRT=3`; the port's has
`INDEX=4 WHERE=1 AND=1 SQRT=1` -- the port's distance field is NOT materialized (upstream
realizes it, `indexing.py:267`), so the neighbour read is a register read, not a buffered
one.

## What this folder does not do

* **It does not execute.** The port builds and renders graphs; it makes no device call
  (`runtime/ops_cpu.bend`: "none of them is made"). Every number above is CPython's, except
  the row *structure*, which is the port's. Closing that is separate work.
* **It is not a rasterizer.** No geometry, no coverage, no perspective divide. A fragment
  shader's inputs are buffers, which is why the two coordinate grids are the inputs here.
* **`pad-arg-form.bend` is a measurement, not a gate.** It exists because this folder nearly
  wrote up a port defect that was its own bug: `mxw_pad` takes upstream's `(offset, END)`
  pairs, **not** after-amounts, so `[0,1]` gives a `?` dtype and `[16,17]` gives `f32`. Both
  readings are one line apart and the fold is right in both.

## Files

| file | what it is |
|---|---|
| `shader.bend` | the shader, built with the port's own Tensor API, printed as a preorder unfolding |
| `shader-oracle.py` | the same formula in CPython tinygrad — graph lane and value lane |
| `shader-gate.py` | the differ over both lanes, the five verdicts, and the plant |
| `pad-arg-form.bend` | the `pad` argument-form measurement quoted above |
| `upstream-kernel-oracle.py` | upstream's SCHEDULED kernel for this formula -- the census the port's kernel graph has to become |
