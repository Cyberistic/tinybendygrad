# ENGINE — the scheduler's engine (port's `Device` lane drives its own stages)

**UNIT:** build the engine that applies the seven `graph_rewrite` tables of
`tinygrad/schedule/rangeify.py:341-376` (`get_kernel_graph`) to an arena.
**OWNED:** `.agents/slop/engine/`, `tinybendygrad/schedule/rangeify.bend`,
`tinybendygrad/runtime/device.bend` (only if the driver needs it).
**NEVER:** `tinygrad/`, `ops_bend.py`, `checks/`, `gates/`, `.agents/TODO.md`,
`.agents/TOOLS.md`, `AGENTS.md`, `.agents/slop/{seams,cpuseam,devlane,mnist}/`,
`tinybendygrad/renderer/cstyle.bend`, `tinybendygrad/runtime/ops_cpu.{bend,c,js}`,
`.agents/slop/graphcmp.{py,bend}`.
**NO COMMIT.** `env -u GIT_INDEX_FILE` for every git read. Never `git add -A`,
never `reset`, never `rebase`.
**MACHINE:** one `bend` process at a time. Never background. Never a sweep.
Never a corpus run. Never a parallel fixture loop. Report wall-clock of every command.

---

## STATUS LOG (append-only)

### 2026-10-27T14:00:25Z — unit start

- `git rev-parse --short HEAD` → `d340ed691` (0.1 s).
- `tinybendygrad/schedule/*.bend` line counts: `__init__ 2594`, `allreduce 773`,
  `indexing 1988`, `memory 1788`, `multi 3455`, `prepare 986`, `rangeify 2839`.
- Upstream: `tinygrad/schedule/rangeify.py` 367 lines,
  `tinygrad/schedule/__init__.py` 296 lines.

### 2026-10-27T14:12Z — THE BASELINE IS GREEN AND THE TOOLING IS FASTER THAN I EXPECTED

| command | wall-clock | result |
|---|---|---|
| `./bin/bend tinybendygrad/schedule/rangeify.bend --check-only` | **0.93 s** | `ALL PROOFS CHECK` |
| `./bin/bendygrad/schedule/rangeify.bend` | **0.98 s** | **126 lines** of `name=value` rows (125 rows + the `bend 2.0.39 is available` notice on stderr) |

`BEND_NO_TELEMETRY=1` is exported for every `bin/bend` call, so `~/.bend/check.json`
is not touched (the off-repo input `AGENTS.md` records).

**⇒ THE COMPILER IS CHEAP HERE (≈1 s for a 2 839-line file), so the machine
constraint is about CONCURRENCY, not about compile time. One `bend` at a time
costs ≈1 s each and that is affordable.**

### 2026-10-27T14:20Z — WHAT THE PORT ACTUALLY HAS, TABLE BY TABLE

`rf_stage_count() -> 9` at `rangeify.bend:2592` and `rf_stages()` at `:2596` are the
STAGE ORDER. The TABLES are eleven, and each is `table()` / `dispatch()` /
`try()` / `scan()`. **MEASURED by reading the file** (not by running it):

| port table | `file:line` | upstream table | `file:line` | entries | LIVE rules (body ported AND able to fire) |
|---|---|---|---|---|---|
| `ct_table` | `:1162` | `pm_const_buffer_folding` | `rangeify.py:110` | 9 | **`ct_6`** (`:979`, INDEX(const)→const), **`ct_8`** (`:1123`, deviceless-MSTACK unwrap) |
| `rb_table` | `:659` | `pm_remove_bufferize` | `rangeify.py:126` | 3 | **`rb_1`** (`:~610`, STORE→self ⇒ NOOP), **`rb_2`** (`:622`, END(NOOP)⇒NOOP) |
| `lb_table` | `:1463` | `pm_limit_bufs` | `rangeify.py:189` | 1 | none — `lb_0` (`:1440`) refuses to fire by construction |
| `ab_table` | `:1622` | `pm_add_buffers` | `rangeify.py:245` | 10 | **`ab_7`** (`:1512`, drop RESHAPEs on CALL), **`ab_8`** (`:1534`, invalid write ⇒ NOOP), **`ab_9`** (`:1588`, remove_noop_afters) |
| `aprt_table` | `:798` | `pm_add_param_range_tags` | `rangeify.py:321` | 1 | **`aprt_0`** (`:775`, `x.rtag(())`) |
| `nic_table` | `:696` | `pm_no_indexing_calls` | `rangeify.py:155` | 1 | **`nic_0`** (`:677`, `no_indexing_calls`) |
| `sk_table` | `:834` | `split_kernels` | `rangeify.py:337` | 1 | none — `sk_0` (`:811`) is the `graph_rewrite`-INSIDE-a-rule wall |
| `nv_table` | `:761` | `pm_no_views` | `rangeify.py:160` | 1 | **`nv_0`** (`:737`, `v ⇒ v.src[0]`) |
| `fb_table` | `:1242` | `pm_flatten_bufferize` | `rangeify.py:235` | 1 | none — the `apply_movement_op` wall |
| `dg_table` | `:1376` | `to_define_global` | `rangeify.py:302` | 7 | **`dg_3`** (`:1274`, ALU-PARAM ⇒ the scalar), **`dg_6`** (`:1282`, `renumber_range`, counter hard-wired to 0) |
| `gs_table` | `:874` | `pm_gate_substitute` | `rangeify.py:45` | 1 | none — it RAISES `BottomUpGate`, which is "no rewrite" |

**⇒ ELEVEN LIVE RULES OUT OF FORTY-ONE TABLE ENTRIES.** The other thirty are
walls, and the file names each one (`# WALL(p3) rangeify.py:NN …` at
`rangeify.bend:2654-2698`). **⇒ THE ENGINE'S JOB IS TO DRIVE THE ELEVEN, AND
THE MEASUREMENT MUST SHOW THE OTHER THIRTY AS NAMED DIVERGENCES, NOT HIDE
THEM.**

### 2026-10-27T14:30Z — UPSTREAM'S ENGINE, READ FROM THE SOURCE (not from memory)

`tinygrad/uop/ops.py:1814` `unified_rewrite` — the default path (`walk=False`).
`RewriteContext(pm if not bottom_up else None, pm if bottom_up else bpm, …)`
(`ops.py:1891`), so **`bottom_up=True` puts the matcher in `self.bpm`** and
`bottom_up=False` in `self.pm`. The three stages:

* **stage 0** — `self.bpm` is applied to the node **as it stands, before its
  children are visited**, in a fixed-point loop (`ops.py:1826-1832`).
* **stage 1** — the node is **REBUILT** with the children's rewritten srcs
  (`ops.py:1864`, `UOp(new_n.op, new_src, new_n.arg, new_n.tag)`); if the srcs
  did not change, `self.pm` (top-down only) is applied and the answer is final.
* **stage 2** — `self.replace[n] = self.replace[new_src_n]`, and the ANSWER is
  itself re-traversed (`ops.py:1866-1867`), so **the rule is a FIXED POINT**.

**⇒ THE ENGINE IS: children first (DFS), rebuild with the children's current
indices, apply the table until it stops firing.** `bottom_up` additionally
applies the table to the node BEFORE descending.

### 2026-10-27T14:35Z — TWO FACTS THAT MAKE THE ENGINE FIT THE PORT

1. **`Arena.nodes` IS TOPOLOGICALLY SORTED** — `ops.bend:2754`: *"`UOp.new` is
   only ever called with srcs already in the arena, so every node's src indices
   are all BELOW its own position"*. ⇒ a sweep in index order IS a sweep in an
   order every node's children precede it, which is the order the DFS produces.
2. **`+` MEANS "REBINDABLE", NOT "LINEAR"** — `.agents/slop/notes/bend2-constraints.md:8633`:
   *"A `+` PARAMETER MAY BE READ MANY TIMES; A PLAIN ONE MAY BE READ ONCE."*
   ⇒ the engine can thread an arena through a recursion without a linear-type
   fight.

**⇒ THE ORDER IS NOT OBSERVABLE IN THE PORT TODAY** (every live rule is
ctx-free), but it IS observable upstream (the `itertools.count` of
`pm_add_buffers` at `rangeify.py:357` and of `renumber_range` at `:318`), so
the engine records the order it used and the report says so.

(continues below)
