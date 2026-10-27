# DEVLANE REPORT — GIVING THE PORT's OWN `Device` LANE A SCHEDULER

Started 2026-10-27T13:38:55Z. Owner: subagent `devlane`.
NOT committing. `env -u GIT_INDEX_FILE` for every git read.

## Machine constraint (given, not mine)
Every locally-built binary is killed by this machine's kernel (AMFI launch-constraint
violation; `DevToolsSecurity -status` reports developer mode disabled). Until the user
runs `sudo DevToolsSecurity -enable`, measurement runs in the **JS lane**
(`bend -o out.js` + `bun`) and the one stage that is not the port's source (the ~30
lines that mmap and call) is spelled in Python exactly as upstream spells it.

## Rules I am holding
- ONE bend process at a time. Never background. Never a sweep. No `--jobs`, no
  `xargs -P`, no `&`. No corpus run. No gate sweep.
- Every command's wall-clock cost is reported.
- Every count names its denominator.
- `.rows` / `.out` / `.err` / `.md` / `.json` — never `.txt`.

---

## 1. THE GAP, IN ONE PARAGRAPH, WITH `file:line` ON BOTH SIDES

**THE PORT's `Device` LANE HAS EVERY STAGE AND NO DRIVER, AND THE ONE STAGE THAT IS
CALLED "THE SCHEDULER" IS NOT THE MISSING PIECE — THE MISSING PIECE IS THE *ENGINE*
THAT RUNS THE SCHEDULER'S STAGES, PLUS THE LINK FROM THE PORT's ARENA TO THE PORT's
RENDERER.**

**THE SCHEDULER IS PORTED.** `tinybendygrad/schedule/__init__.bend:1139`
`def schedule(+ar: O.Arena, +sink: U32) -> Lin` IS upstream's `create_schedule`
(`tinygrad/schedule/__init__.py:32-80`), and `schedule/__init__.bend:1135`
`def linear(+x: Lin) -> O.Found` IS upstream's `return UOp(Ops.LINEAR,
src=tuple(linearized))` (`tinygrad/schedule/__init__.py:80`). The port's
`schedule/` DIRECTORY HOLDS THE WHOLE CHAIN: `rangeify.bend` (`get_kernel_graph`),
`prepare.bend` (`prepare_rangeify`), `memory.bend` (`memory_plan_rewrite`),
`multi.bend`, and `__init__.bend` (`create_schedule`). **⇒ AND IT IS ALREADY
MEASURED AGAINST CPython**: `.agents/slop/schedport/` holds 109 rows and
`oracles/schedule-bodies/BEFORE-rows.rows` (81 rows) with
`checks/sb-gate.sh` as the gate, on five fixtures.

**⇒ AND THE CHAIN'S OWN HEADER SAYS WHY IT IS NOT A LANE.**
`tinybendygrad/schedule/rangeify.bend:2669`:
`# WALL(p3) rangeify.py:351  get_kernel_graph      the order is here, the engine is
not -- BLOCKED: NOT A GAP: the ORDER is here; the ENGINE that would consume it is
not, so this is a downstream unit.` **⇒ THAT IS THE GAP, IN THE TREE'S OWN WORDS.**
Upstream's `get_kernel_graph` (`tinygrad/schedule/rangeify.py:341-376`) is SEVEN
`graph_rewrite` CALLS; the port has all seven TABLES (`rangeify.bend:2577-2600`,
`rf_stage_count() -> 9` at `:2586`, `rf_stages()` at `:2592`) and NOT the engine that
applies them to an arena.

**⇒ AND THE SECOND LINK IS MISSING TOO, AND IT IS THE RENDERER'S.**
`tinybendygrad/renderer/cstyle.bend:2297`
`def render(+dev: U32, cpu: Bool, +kus: List<&2, KU>) -> String` — the port's
`ClangRenderer` — **TAKES A `List<KU>`, AND NO DEF IN THE PORT PRODUCES ONE FROM THE
PORT's ARENA.** `KU` (`cstyle.bend:126-129`) is
`{op, dtype, addr, numel, shape, arg, srcs}`, i.e. a FLATTENED uop list whose `srcs`
are POSITIONS IN THAT LIST. Upstream's renderer takes `list[UOp]`
(`tinygrad/renderer/cstyle.py:456`, `ctx.render(list(lin.src))` in
`tinygrad/codegen/__init__.py:456`), i.e. the port's `List<U32>` — arena indices —
which the port's `codegen/late/linearizer.bend:836 linearize(+ar, +lst, vms, +sink)
-> List<&2, U32>` DOES produce. **⇒ SO THE MISSING LINK IS EXACTLY
`List<&2, U32> -> List<&2, KU>`, AND IT IS ONE DEF.**

**⇒ AND THE THIRD LINK IS THE DEVICE'S, AND IT EXISTS.**
`tinybendygrad/runtime/ops_cpu.bend:1578` `def Cpu.compile(src: String, argv: String)
-> IO(Result<&1, &1, U32 & String, String>)` and `:1582` `def Cpu.exec(img: String,
bufs: String, sizes: String) -> IO(...)` are upstream's `CPUProgram.__init__` +
`__call__` (`tinygrad/runtime/ops_cpu.py:23-62`) in upstream's own order
(`ops_cpu.py:23-46`: `cc` → `jit_loader` → `mmap` → `pthread_jit_write_protect_np` →
`__clear_cache` → `CFUNCTYPE` → call). **⇒ AND NOTHING IN THE PORT CALLS THEM**:
`grep -rn "Cpu.compile\|Cpu.exec" tinybendygrad/` answers ONLY the two definitions.

**⇒ AND THE DRIVER THAT WOULD TIE THEM TOGETHER EXISTS — IN A SCRATCH DIRECTORY, NOT
IN THE PORT.** `.agents/slop/cpuseam/launch.bend:113-131` IS the seven-step driver
(render → argv → `cc` → `jit_loader` → `mmap`+call → read the oracle's buffers →
print), and `.agents/slop/cpuseam/REPORT.md:692-697` states the gap as
*"THE PORT's `Device` LANE HAS NO SCHEDULER, SO THE WHOLE MNIST FORWARD PASS THROUGH
THE PORT's OWN LANE IS NOT MEASURED."* **⇒ THAT CLAIM IS **NEARLY** RIGHT AND ITS
CAUSE IS WRONG: the port's `Device` lane has no DRIVER, and the SCHEDULER's engine is
missing, and the ARENA→RENDERER link is missing. The scheduler ITSELF (`schedule()`)
is ported and measured.**

**⇒ AND THE PRIOR ART'S `KU` LIST IS A TRANSCRIPTION OF UPSTREAM's TEXTUAL ROWS, NOT
THE PORT's ARENA.** `.agents/slop/cpuseam/gen_kus.py:104-150` READS
`.agents/slop/cpuseam/uops/<name>.rows` (written by `dump_kernel.py:41-77` from
upstream's LIVE uop objects) and EMITS `C.KU{...}` LITERALS. **⇒ SO THE PORT's ARENA,
THE PORT's `schedule()`, AND THE PORT's RENDERER HAVE NEVER MET.**

## 2. WHAT I OWN AND WHAT I WILL LAND

`tinybendygrad/runtime/device.bend` (NEW — the prompt named
`tinybendygrad/runtime/device.bend`; the tree's registry file is
`tinybendygrad/device.bend` at the TOP level, so the runtime path is free):
the port's `Device` lane's `Program`, its SCHEDULER HOOK, its COMPILE/EXEC ENTRIES,
and — if it measures — the ARENA→`KU` CONVERSION.

---

## 3. COMMAND COST LEDGER (every command, with its wall cost)

| # | command | cost | notes |
|---|---|---|---|
| 1 | `mkdir -p .agents/slop/devlane` | <0.1 s | |
| 2 | `ls tinybendygrad/runtime/ tinybendygrad/schedule/` | <0.1 s | |
| 3 | `find tinybendygrad -name 'device*'` | <0.1 s | |
| 4 | `wc -l` over the tree's `.bend` files | <0.1 s | |
| 5 | `grep -n "^def " tinybendygrad/tensor.bend` etc. (many) | ~0.1 s each | no compiler |
| 6 | `sed -n` reads of `tinygrad/device.py`, `tinygrad/runtime/ops_cpu.py`, `tinygrad/codegen/__init__.py`, `tinygrad/schedule/rangeify.py`, `tinygrad/schedule/__init__.py` | <0.1 s each | no compiler |
| 7 | **`./bin/bend tinybendygrad/schedule/__init__.bend --check-only`** | **0.82 s** (real 0.82, user 1.92) | ONE bend process, the SCHEDULER's file compiles GREEN (`ALL PROOFS CHECK`) |
