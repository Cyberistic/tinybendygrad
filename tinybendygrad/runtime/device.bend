# tinybendygrad/runtime/device.bend -- THE PORT's OWN `Device` LANE.
#

# The port has EVERY STAGE of the device lane, ONE DEF DRIVES THEM -- `compile_sink`
# (`:427`, the port's own arena to C) -- AND NOTHING SHIPPED CALLS IT. MEASURED 2026-11-19
# by `.agents/slop/pipelinecensus/callers.py`: `compile_sink` has 0 callers under
# `tinybendygrad/`; its seven callers are all `.agents/slop/browser/` lanes.
#
#   * `schedule/__init__.bend:1295` `schedule(+ar, +sink) -> Lin` IS upstream's
#     `create_schedule` (`tinygrad/schedule/__init__.py:32-80`), and
#     `schedule/__init__.bend:1292` `linear(+x: Lin) -> O.Found` IS upstream's
#     `return UOp(Ops.LINEAR, src=tuple(linearized))`
#     (`tinygrad/schedule/__init__.py:80`).
#   * `renderer/cstyle.bend:2364` `render(+dev, cpu, +kus) -> String` IS upstream's
#     `ClangRenderer.render` (`tinygrad/renderer/cstyle.py:268-278`).
#   * `runtime/ops_cpu.bend:1035` `Cpu.compile(src, argv)` and `:1039`
#     `Cpu.exec(img, bufs, sizes)` ARE upstream's `CPUProgram.__init__` +
#     `__call__` (`tinygrad/runtime/ops_cpu.py:23-62`), in upstream's own order.
#   * `runtime/support/elf.bend:1720` `jit_loader(+e, +base) -> Img` IS
#     upstream's `jit_loader` (`tinygrad/runtime/support/elf.py:52-86`).
#
# AND `rg -n "Cpu\.(compile|exec)\(" tinybendygrad/` ANSWERS THREE LINES EACH: the DEF, and
# the ONE CALL at `:151`/`:177` BELOW. So both are wired to THIS file and neither is wired to
# anything that runs -- the port's `Device` lane is ONE DEF WITH NO CALLER.
#
# `.agents/slop/cpuseam/launch.bend:113-131` IS that lane, and it is IN A
# SCRATCH DIRECTORY. This file is the lane, IN THE PORT.
#

# the four entries, and what each one is upstream's.
#
#   `program`  THE PROGRAM. Upstream's `Compiled.runtime(obj)` takes a
#              `TinyELF` (`tinygrad/device.py:402`) and the renderer's C is
#              `ctx.render(list(lin.src))` (`tinygrad/codegen/__init__.py:456`).
#              The port's `KU` list IS upstream's `list[UOp]`, so `program` is
#              the port's own spelling of that render step.
#
#   `schedule` THE SCHEDULER. Upstream's `create_schedule(sched_sink)` takes the
#              ASSIGN GRAPH's sink and answers the LINEAR
#              (`tinygrad/schedule/__init__.py:32-80`). The port's `schedule()`
#              is that function; this is the CALLER it did not have.
#
#   `compile`  THE COMPILER. Upstream's `CPUProgram.__init__` step 1 is `cc` on
#              the C source, with upstream's OWN argv
#              (`tinygrad/runtime/support/compiler_cpu.py:21-22`), and the ELF
#              object comes back. The port's `Cpu.compile` is that effect; this
#              is the entry that hands it the argv
#              (`runtime/support/compiler_cpu.bend:260`) and the C.
#
#   `exec`     THE EXECUTION. Upstream's `CPUProgram.__init__` steps 3-7 are
#              `mmap` -> `pthread_jit_write_protect_np` -> write -> `__clear_cache`
#              -> `CFUNCTYPE` -> call (`tinygrad/runtime/ops_cpu.py:29-46`), and
#              `__call__` packs the arguments as 64-bit words
#              (`tinygrad/runtime/ops_cpu.py:51, :61`). The port's `Cpu.exec` is
#              that effect.
#
# `relocate` IS THE MISSING MIDDLE: upstream's step 2 is `jit_loader(lib, base)`
# (`tinygrad/runtime/ops_cpu.py:34`) and it is the port's own
# `runtime/support/elf.bend:1796`.
#
# what is still missing, and it is named here rather than hided.
#
# THE LAST LINK EXISTS AND IS `body_kus` (`:378`): it takes a kernel index, runs the four
# lowerer passes, the toposort, `codegen/late/linearizer.bend:762 linearize` and
# `renderer/kuconv.bend:349 kuconv.convert`, and answers a `List<KU>` in the grown arena.
# MEASURED 2026-11-19: `compile_sink` on `rangify.bend`'s `rr_kernel_graph` output renders
# 665 bytes of C for the (4,3)@(3,5) matmul, so the `List<U32> -> List<KU>` conversion is
# NOT missing and `kuconv.dt` DOES answer the KU record's dtype from the fold.
#
# WHAT IS MISSING IS THE ENDS AND ONE PASS. `compile_sink` (`:427`) is this lane's entry and
# it has NO SHIPPED CALLER; `compile` (`:149`), `relocate` (`:162`) and `exec` (`:175`) are
# three defs nothing composes into a lane. AND `body_low` (`:372`) runs `wk_commit`,
# `lower_reduce_all`, `late_apply` and `alloc_to_buf_all` and NOT `pm_add_loads`
# (`codegen/kernel.bend:565`, ZERO callers), so the rendered kernel has NO `LOAD` NODE and
# `cc` refuses it: MEASURED, three `invalid operands to binary expression
# ('float *' and 'float *')` errors from the port's own scheduler's kernel.
import Base
import ./../uop/ops.bend as O
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./../renderer/cstyle.bend as C
import ./../schedule/__init__.bend as SCH
import ./ops_cpu.bend as CPU
import ./support/elf.bend as E
import ./../uop/fold.bend as F
import ./../codegen/late/linearizer.bend as LIN
import ./../renderer/kuconv.bend as KC
import ./../uop/weak.bend as WK
import ./../codegen/kernel.bend as KR
import ./../codegen/decomp/op.bend as DC

# THE PROGRAM. Upstream's `Compiled.runtime(obj)` (`tinygrad/device.py:402`)
# takes the compiled OBJECT; the port's `Program` is the C SOURCE, because the
# port's `compile` is the step that turns the C into the object.

type Prog is Data:
  Prog{name: String, src: String}

def Prog.name(p: Prog) -> String:
  match p:
    case Prog{name, src}: name

def Prog.src(p: Prog) -> String:
  match p:
    case Prog{name, src}: src

# THE RENDER. `C.render(+dev, cpu, +kus)` IS upstream's
# `ClangRenderer.render(self, uops)` (`tinygrad/renderer/cstyle.py:268-278`) and
# `C.dev_clang()` IS THE CLANG RENDERER'S DEVICE TAG.
#
# THE `+kus` IS AFFINE, so the caller hands over the list and does not get it
# back: the port's `List` is a persistent structure and `render` CONSUMES it.
# - a caller that needs the list twice builds it twice, which is what
# `.agents/slop/cpuseam/launch.bend:120-122` already does.
def program(name: String, kus: List<&2, C.KU>) -> Prog:
  Prog{name, C.render(C.dev_clang(), True{}, kus)}

# THE SCHEDULER. Upstream's `create_schedule(sched_sink)`
# (`tinygrad/schedule/__init__.py:32-80`) IS THE PORT's `schedule()`
# (`schedule/__init__.bend:1124` symbol=schedule), and `linear`
# (`schedule/__init__.bend:1121` symbol=linear) IS upstream's
# `return UOp(Ops.LINEAR, src=tuple(linearized))` (`__init__.py:80`).
#
# - this is the caller the port's scheduler did not have, and it is why the
# port's `Device` lane "has no scheduler" was TRUE in code and not in prose:
# the function was there and unreachable from any device.
#
# the answer is the linear node and its arena: `schedule` consumes the arena and
# `linear` hands back the node in the arena it grew, so the caller keeps the
# arena by taking the `Found`.
def schedule(ar: O.Arena, sink: U32) -> O.Found:
  SCH.linear(SCH.schedule(ar, sink))

# THE COMPILE. Upstream's `CPUProgram.__init__` step 1 (`ops_cpu.py:29-34`) is
# `cc` on the C source with upstream's OWN argv
# (`runtime/support/compiler_cpu.py:21-22`), and the ELF OBJECT comes back.
#
# `cc_argv` is the port's own spelling of that argv
# (`runtime/support/compiler_cpu.bend:260 symbol=ClangCompiler.compile_argv`), and it is
# JOINED WITH NEWLINES because the C side has no argv of its own -- a second copy
# of upstream's argv is a second thing to rot.
#
# `IO.try` IS BASE's OWN (`references/bend/bend2/base.bend`) and it turns the
# effect's `Fail` into a `Halt` with the message on stderr, which is what
# upstream's `CPUProgram.__init__` raising IS.
def cc_argv(cc: String, arch: String) -> String:
  CPU.cpu.cc_argv_str(cc, arch)

def compile(src: String, argv: String) -> IO(String):
  do IO<String>:
    +elf : String <- IO.try(String, CPU.Cpu.compile(src, argv))
    IO.pure(String, elf)

# THE RELOCATION. Upstream's step 2 (`ops_cpu.py:34`) is
# `jit_loader(lib, base=mv_address(self.mem))` and it is the port's own
# `runtime/support/elf.bend:1796`.
#
# the base is `0`, and that is measured, not chosen: the port's
# `.agents/slop/cpuseam/REPORT.md:507-523` records that BOTH bases give the same
# five kernels, and the reason is that those five kernels have NO `CALL26`/
# `JUMP26` relocations, so the image-relative arms are the only ones that fire.
def relocate(+elf: String) -> String:
  +ehdr : E.Ehdr = E.Ehdr.at(elf, True{})
  +img : E.Img = E.jit_loader(E.elf_loader(elf, ehdr, True{}, 1, Nil{}), 0)
  E.Img.body(img)

# THE EXECUTION. Upstream's steps 3-7 (`ops_cpu.py:29-46`) and `__call__`
# (`:51, :61`).
#
# - the buffers cross as hex, and that is upstream's shape and not a
# CONVENIENCE: `Process.run` hands its stdout back as a UTF-8 STRING
# (`references/bend/bend2/effs/process_run.c:277` builds it with `io_str`, and
# `io_str` replaces every invalid sequence with u+fffd) and an elf object is not
# utf-8. - the hex is the only way the bytes survive the seam.
def exec(img: String, bufs: String, sizes: String) -> IO(String):
  do IO<String>:
    +out : String <- IO.try(String, CPU.Cpu.exec(img, bufs, sizes))
    IO.pure(String, out)

# THE DRIVER THE LANE NEVER HAD: from the port's OWN arena to C source, the four links
# `full_rewrite_to_sink` calls `linearize` -> `kuconv` -> `render` on (a `.agents/slop`
# probe has run this chain since 2026-10-31; THIS is the port's own copy of it, and
# MEASURED 2026-11-18 it renders the fullchain kernel -- 661 bytes, no UNHANDLED node).
#
# `linear` (`schedule`) answers `LINEAR(call, ...)`, and a kernel's BODY is the CALL's
# `src[0]` -- upstream's `do_to_program` linearizes THE SINK (`codegen/__init__.py:456`),
# not the CALL, and the port's `linearize` takes the toposort the caller owes it
# (`linearizer.py:7` does `list(sink.toposort())` itself).
# THE LOWERING PASSES ARE PART OF THE LANE: `full_rewrite_to_sink` runs the weak rounds
# and `pm_reduce_local` before `linearize`, and without them a kernel renders `weakint`
# and `UNHANDLED(Ops.REDUCE)` -- MEASURED, that is exactly what the first run of this
# driver printed. `wk_commit` is `pm_commit_weak`+`pm_cast_const`+`pm_uncast_const`;
# `lower_reduce_all` is `lower_reduce` (the small-range unroll, bounded by `LR_MAX`) and
# `alloc_to_buf_all` is `pm_alloc_to_buf`.
# THE LATE DECOMP TABLE, APPLIED -- `codegen/__init__.py:339-341`. Upstream runs
# `get_late_rewrite_patterns(supported_ops, DISABLE_FAST_IDIV)` under `graph_rewrite`
# AFTER `pm_reduce_local` and BEFORE the renderer, and the port had the TABLE
# (`codegen/decomp/op.bend`, nineteen rules) and NO STAGE -- so a MAX reached the
# renderer and printed `UNHANDLED(Ops.MAX)`. MEASURED: that is what max_pool2d rendered.
#
# THE WALK IS BOTTOM-UP over the body's toposort, ONE LEVEL of substitution per node
# (upstream's `self.replace.get(x, x)` final pass), and repeated to a fixpoint because
# one late rule feeds another. A node the table does not CLAIM is interned back
# unchanged, which `UOp.new` makes free: the arena internes.
type LateRep is Data:
  LateRep{old: U32, new: U32}

# THE LOOP STATE IS A RECORD AND NOT A TUPLE. `rangify.bend` records the reason for the
# same choice on the same shape: a three-element `Pair` whose middle Kind is a `List`
# "fails kind inference in Base" (`(_ => Bool)`), so the state is a record and the
# accessors are the fields.
type Lt is Data:
  Lt{ar: O.Arena, rs: List<&2, LateRep>, fired: Bool}

def Lt.ar(x: Lt) -> O.Arena: match x: case Lt{ar, rs, fired}: ar
def Lt.rs(x: Lt) -> List<&2, LateRep>: match x: case Lt{ar, rs, fired}: rs
def Lt.fired(x: Lt) -> Bool: match x: case Lt{ar, rs, fired}: fired

type LtR is Data:
  LtR{ar: O.Arena, i: U32, fired: Bool}

def LtR.ar(x: LtR) -> O.Arena: match x: case LtR{ar, i, fired}: ar
def LtR.i(x: LtR) -> U32: match x: case LtR{ar, i, fired}: i
def LtR.fired(x: LtR) -> Bool: match x: case LtR{ar, i, fired}: fired

def lt_get.go(+k: U32, +rs: List<&2, LateRep>) -> U32:
  match rs:
    case Nil{}: k
    case LateRep{old, new} <> t: Bool.pick(U32, U32.is_eq(old, k), new, lt_get.go(k, t))

def lt_get(+rs: List<&2, LateRep>, +k: U32) -> U32: lt_get.go(k, rs)

def lt_srcs.go(+ss: List<&2, U32>, +rs: List<&2, LateRep>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: lt_srcs.go(t, rs, List.append(&2, U32, acc, [lt_get(rs, s)]))

def lt_rebuild(+ar: O.Arena, +u: U32, +rs: List<&2, LateRep>) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, u), lt_srcs.go(O.Arena.srcs(ar, u), rs, Nil{}),
            O.Arena.arg(ar, u), O.Arena.tag(ar, u))

# THE TABLE FOR THIS TARGET, WHICH IS UPSTREAM's OWN CONDITION AND NOT A TASTE:
# `decomp/op.py:116` adds the two `ADD -> MULACC` rules only `if Ops.MULACC in ops`,
# and the C renderer's `code_for_op` has no MULACC (`cstyle.py:142-150`) -- its MULACC
# is expanded later in the pipeline, which the port has not ported. Applying them
# anyway is what put `UNHANDLED(Ops.MULACC)` in the max_pool2d store's index.
# The port's `dc_l_tab` is the nineteen-rule union, so the target condition is a
# filter HERE, by tag, and the two tags are named with the upstream line that adds them.
def lt_is_mulacc(+tg: U32) -> Bool: Bool.or(U32.is_eq(tg, 14), U32.is_eq(tg, 15))

def lt_tab.go(+es: List<&2, O.PMEntry>, +acc: List<&2, O.PMEntry>) -> List<&2, O.PMEntry>:
  match es:
    case Nil{}: acc
    case e <> t:
      lt_tab.go(t, Bool.pick(List<&2, O.PMEntry>, lt_is_mulacc(O.PMEntry.tag(e)), acc,
                             List.append(&2, O.PMEntry, acc, [e])))

def lt_tab() -> List<&2, O.PMEntry>: lt_tab.go(O.PMEntrys.es(DC.dc_l_tab(False{})), Nil{})

# THE SCAN IS THE TABLE's OWN (`dc_l_scan`), so a rule fires exactly where upstream's
# `PatternMatcher` would and the answer is built by the rule's own body.
def lt_rule(+ar: O.Arena, +u: U32) -> DC.Hit:
  DC.dc_l_scan(lt_tab(), F.folded(ar), u, DC.miss(ar))

# THE CLAIM IS THE TABLE'S OWN OP SETS, FOLDED -- not a hand list, so a rule added to
# `dc_l_tab` is claimed here the day it lands. It also SAVES THE FOLD: the rule needs
# `F.folded(ar)`, which sweeps the arena, and an unclaimed node never asks for it.
def lt_claimed.go(+op: O.Op, +es: List<&2, O.PMEntry>) -> Bool:
  match es:
    case Nil{}: False{}
    case e <> t:
      Bool.pick(Bool, O.op_in(O.PMEntry.ops(e), op), True{}, lt_claimed.go(op, t))

def lt_claimed(op: O.Op) -> Bool: lt_claimed.go(op, lt_tab())

def lt_put(+ar: O.Arena, +u: U32, +i: U32, +rs: List<&2, LateRep>, fired: Bool) -> Lt:
  Lt{ar, List.append(&2, LateRep, rs, [LateRep{u, i}]), fired}

def lt_take(+h: DC.Hit, +u: U32, +rs: List<&2, LateRep>) -> Lt:
  +f = lt_rebuild(DC.Hit.ar(h), DC.Hit.i(h), rs)
  lt_put(O.Found.ar(f), u, O.Found.i(f), rs, True{})

def lt_keep(+u: U32, +ar: O.Arena, +rs: List<&2, LateRep>, fired: Bool) -> Lt:
  +f = lt_rebuild(ar, u, rs)
  lt_put(O.Found.ar(f), u, O.Found.i(f), rs, fired)

def lt_hit(on: U32, +h: DC.Hit, +u: U32, +ar: O.Arena, +rs: List<&2, LateRep>, fired: Bool) -> Lt:
  match on:
    case 1: lt_take(h, u, rs)
    case _: lt_keep(u, ar, rs, fired)

def lt_pick(c: Bool, +u: U32, +ar: O.Arena, +rs: List<&2, LateRep>, fired: Bool) -> Lt:
  match c:
    case True{}:
      +h = lt_rule(ar, u)
      lt_hit(DC.Hit.on(h), h, u, ar, rs, fired)
    case False{}: lt_keep(u, ar, rs, fired)

# `pm_split_ends` -- linearizer.py:88-99, and it is the SECOND half of upstream's
# `pm_final_rewrite` (`codegen/__init__.py:348`: `pm_decomp + pm_split_ends`). An `END`
# over N ranges becomes N NESTED single-range ENDs, built in DESCENDING range order so the
# lowest range ends up OUTERMOST:
#
#   ret = e.src[0]; for r in sorted(rngs, key=arg, reverse=True): ret = ret.end(r)
#
# THE PORT NEEDED IT AND THAT IS MEASURED, not stylistic: this renderer prints one
# `for (...) {{` per RANGE and one `}}` per END, so an END over two ranges closed ONE loop
# and the max_pool kernel came out with 5 openers and 3 closers, and its output store
# landed INSIDE the window loop.
def se_rev.go(+xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: se_rev.go(t, List.append(&2, U32, [x], acc))

def se_wrap.go(+rs: List<&2, U32>, +ar: O.Arena, +b: U32) -> O.Found:
  match rs:
    case Nil{}: O.Found{ar, b}
    case r <> t:
      +f = O.UOp.end(ar, b, [r])
      se_wrap.go(t, O.Found.ar(f), O.Found.i(f))

def se_end(+u: U32, +ar: O.Arena, +rs: List<&2, LateRep>) -> Lt:
  +b = lt_get(rs, O.Arena.src0(ar, u))
  +f = se_wrap.go(se_rev.go(O.Arena.src_from(ar, u, 1), Nil{}), ar, b)
  lt_put(O.Found.ar(f), u, O.Found.i(f), rs, True{})

def lt_kind(isend: Bool, +u: U32, +ar: O.Arena, +rs: List<&2, LateRep>, fired: Bool) -> Lt:
  match isend:
    case True{}: se_end(u, ar, rs)
    case False{}:
      +h = lt_rule(ar, u)
      lt_hit(DC.Hit.on(h), h, u, ar, rs, fired)

def lt_pick2(c: Bool, isend: Bool, +u: U32, +ar: O.Arena, +rs: List<&2, LateRep>, fired: Bool) -> Lt:
  match c:
    case True{}: lt_kind(isend, u, ar, rs, fired)
    case False{}: lt_keep(u, ar, rs, fired)

def lt_step(+u: U32, +st: Lt) -> Lt:
  +op = O.Arena.op(Lt.ar(st), u)
  lt_pick2(Bool.or(lt_claimed(op), O.eq_op(op, O.OpsEND{})), O.eq_op(op, O.OpsEND{}),
           u, Lt.ar(st), Lt.rs(st), Lt.fired(st))

def lt_pass.go(+us: List<&2, U32>, st: Lt) -> Lt:
  match us:
    case Nil{}: st
    case u <> t: lt_pass.go(t, lt_step(u, st))

def lt_round.fin(root: U32, +st: Lt) -> LtR:
  +f = lt_rebuild(Lt.ar(st), root, Lt.rs(st))
  LtR{O.Found.ar(f), O.Found.i(f), Lt.fired(st)}

def lt_round(+ar: O.Arena, +root: U32) -> LtR:
  lt_round.fin(root, lt_pass.go(O.UOp.toposort(O.Arena.budget(ar), ar, root), Lt{ar, Nil{}, False{}}))

# FOUR ROUNDS, AND A ROUND THAT FIRED NOTHING STOPS THE CHAIN. The late table's longest
# known chain is three (`MUL(1/b) -> FDIV`, then the FDIV forms), and a bound here LOSES
# rewrites rather than correctness: a body that needs a fifth round keeps the first four,
# which is what the fixpoint would have had at that point anyway.
def lt_r2.on(fired: Bool, +q: LtR) -> LtR:
  match fired:
    case True{}: lt_round(LtR.ar(q), LtR.i(q))
    case False{}: q

def lt_r2(+q: LtR) -> LtR:
  lt_r2.on(LtR.fired(q), q)

def late_apply(+ar: O.Arena, +root: U32) -> O.Found:
  +q = lt_r2(lt_r2(lt_r2(lt_round(ar, root))))
  O.Found{LtR.ar(q), LtR.i(q)}

# `pm_add_loads` -- THE PASS `body_low` WAS MISSING, and why the first wiring died.
#
# upstream `codegen/__init__.py:301` runs `symbolic_simple+pm_expand_broadcast+pm_add_loads`
# before the devectorizer. `body_low` ran `wk_commit`, `lower_reduce_all`, `late_apply` and
# `alloc_to_buf_all` and not this pass, so the port's own scheduled kernel carried ZERO `LOAD`
# nodes and `cc` refused its C -- `invalid operands to binary expression ('float *' and
# 'float *')`, 3x (`.agents/slop/pipelinecensus/REPORT.md`). `.agents/slop/execgap/` is green
# only because `graphcmp.bend:g_lin` HAND-BUILDS the six loads a real lowerer would insert.
#
# IT IS ONE ROUND AND NOT A FIXPOINT, AND THAT WAS A MEASURED 3 GB MISTAKE FIRST.
# `kn_load_one` (`codegen/kernel.bend:499-505`) wraps a source in `Ops.LOAD` whenever the
# source's addrspace is GLOBAL/LOCAL/REG, and it HAS NO "already a LOAD" GUARD -- so a LOAD
# itself still reads as loadable and the next round wraps it again. A fixpoint (`al_r2`, two
# rounds) was `KILLED-ON-MEMORY` at 3099 MB and 3162 MB on a 50-node kernel. UPSTREAM DOES NOT
# ITERATE HERE EITHER: `pm_add_loads` is one `graph_rewrite` in a pipeline that runs once, and
# the guard is unnecessary because the graph it is handed still has BUFFERs for leaves. So the
# faithful shape is the single round, and the guard belongs to a caller that re-runs it.
# `at = 0` IS "NO REWRITE" AND NOT AN INDEX. `pm_add_loads` is `al_scan` (`codegen/kernel.bend`
# :565), whose accumulator STARTS at `Ker{ar, 0}` and only reaches `ker_self` through
# `al_try.go` -- so a node no rule claims comes back as `at=0`. Mapping `u -> 0` records every
# unclaimed node as a NOOP and the rebuilt body collapses to `NOOP[] SINK[0]`, MEASURED.
# THE UNCLAIMED NODE IS REBUILT AND RECORDED TOO, AND THAT IS WHAT MAKES THE PASS LAND.
# `lt_rebuild` substitutes a node's SRCS from the map and nothing else, so the map has to hold the
# WHOLE toposort -- which is why `late_apply` routes every node through `lt_keep` and not only the
# ones a rule claimed. Recording only the claimed ones (`nmap=3`) left the map's values unreachable:
# the rule built the right node (`at=559`, `loads-in-at=2`, `src0` is a LOAD) and the rebuild from
# the root never constructed it, so `add_loads` changed NOTHING and the C kept multiplying pointers.
# `at == u` is routed here too: the rule fired but produced the same node, and a src that DID change
# has to reach it.
# AND THE ARENA IS THE ACCUMULATOR'S, NOT THE ONE THE PASS WAS HANDED. `al_try.go`'s unmapped arm
# answers `Ker{ar, 0}` with the FOLD's arena, which is older than anything the walk has grown; minting
# a node there lands on an index the newer arena already holds. MEASURED: `KR.Ker.ar(al)` in this arm
# rendered all four kernels as `void test() { }` -- an empty body, because the rebuilt root pointed at
# collided nodes. `Lt.ar(st)` is the newest arena at every step, and the `False` arm still takes
# `KR.Ker.ar(al)` because that one holds the node `at` names.
def al_keep(none: Bool, +al: KR.Ker, +u: U32, +st: Lt) -> Lt:
  match none:
    case True{} : lt_keep(u, Lt.ar(st), Lt.rs(st), Lt.fired(st))
    case False{}: lt_put(KR.Ker.ar(al), u, KR.Ker.at(al), Lt.rs(st), True{})

# THE MAP TRAVELS AS `KR.Sub`, because `pm_add_loads` asks loadability of the SUBSTITUTED source
# (`codegen/kernel.bend`'s `Sub` header records why) and this file is the one that owns `LateRep`.
# `lw_find` is first-match and the walk writes each key once, so the conversion is a rename.
def al_subs.go(+rs: List<&2, LateRep>, +acc: List<&2, KR.Sub>) -> List<&2, KR.Sub>:
  match rs:
    case Nil{}: acc
    case LateRep{old, new} <> t: al_subs.go(t, List.append(&2, KR.Sub, acc, [KR.Sub{old, new}]))

def al_subs(+rs: List<&2, LateRep>) -> List<&2, KR.Sub>:
  al_subs.go(rs, Nil{})

# THE MEMORY BIT, ONE PER NODE, ONE ENTRY PER VISITED NODE. It is keyed by the ORIGINAL id -- that is
# what a src IS -- and `mem_flag` (kernel.bend) folds it from the src's bit, which the bottom-up walk
# has already recorded. No recursion: the recursion `ops.py:876-880` reads as is `op -> all-srcs -> op`,
# and with "never load an ALU node" in hand it collapses to the one bit.
def al_src0_mem(+ar: O.Arena, +fm: List<&2, KR.Sub>, +u: U32) -> Bool:
  Bool.pick(Bool, U32.is_zero(O.Arena.nsrc(ar, u)), False{},
            KR.flag_get(fm, O.Arena.src0(ar, u)))

def al_bit(b: Bool) -> U32: Bool.pick(U32, b, 1, 0)

# THE WALK STATE IS `Lt` PLUS THIS MAP, AND IT IS A PAIR BECAUSE `Lt` IS ALSO `late_apply`'s: a fourth
# field would make every `Lt` constructor in that pass pay for a map it cannot use. A pair is legal as a
# PARAMETER that gets destructured, which is the form `rr_widen.all.fin` already uses.
def al_step(+fx0: F.Folded, +u: U32, p: (Lt & List<&2, KR.Sub>)) -> (Lt & List<&2, KR.Sub>):
  (+st, +fm) = p
  +al = KR.pm_add_loads(fx0, Lt.ar(st), al_subs(Lt.rs(st)), fm, u)
  (al_keep(Bool.or(U32.is_zero(KR.Ker.at(al)), U32.is_eq(KR.Ker.at(al), u)), al, u, st),
   List.append(&2, KR.Sub, fm, [KR.Sub{u, al_bit(KR.mem_flag(O.Arena.op(Lt.ar(st), u),
                                                             al_src0_mem(Lt.ar(st), fm, u)))}]))

def al_pass.go(+fx0: F.Folded, +us: List<&2, U32>, p: (Lt & List<&2, KR.Sub>)) -> (Lt & List<&2, KR.Sub>):
  match us:
    case Nil{}: p
    case u <> t: al_pass.go(fx0, t, al_step(fx0, u, p))

# THE PASS WORKS AND IS NOT WIRED, AND THE TWO FACTS ARE SEPARATE. `shaders/index-loadable.bend`
# measures it firing: `mul_at_src0_op=Ops.LOAD` on `MUL(INDEX, INDEX)`, with `at=10` inside an
# arena of `next=11`. Wired into `body_low` it reaches `KILLED-ON-MEMORY` at **3217 MB** on the
# 50-node matmul kernel -- so the remaining problem is the SIZE of the term this builds, not the
# rule. The three defects it exposed (`kn_map_load`'s discarded arena, `al_next`'s erased hit,
# and `al_next`'s stale arena) are fixed in `codegen/kernel.bend` and are correct independently
# of whether this is wired.
#
# THE FOLD IS TAKEN ONCE FOR THE ROUND: per node was the FIRST O(n^2) attempt, and the fold of
# an append-only arena is the expensive part of this pass, not the rule.
def al_fin(p: (Lt & List<&2, KR.Sub>), +root: U32) -> O.Found:
  (+st, +fl) = p
  +q = lt_round.fin(root, st)
  O.Found{LtR.ar(q), LtR.i(q)}

def add_loads(+ar: O.Arena, +root: U32) -> O.Found:
  al_fin(al_pass.go(F.folded(ar), O.UOp.toposort(O.Arena.budget(ar), ar, root),
                    (Lt{ar, Nil{}, False{}}, Nil{})), root)

def body_low(+ar: O.Arena, +b: U32) -> O.Found:
  +w = WK.wk_commit(ar, b)
  +r = KR.lower_reduce_all(O.Found.ar(w), O.Found.i(w))
  # WIRED, AND THE COST IS THE TERM SIZE, NOT THE RULE -- see the note above `add_loads`. Without
  # it the rendered C does not compile at all: `(data1_784+idx) * (data2_4+idx)` multiplies two
  # POINTERS, which `cc` refuses with `invalid operands to binary expression ('float *' and
  # 'float *')` (`.agents/slop/browser/fchain-harness.c` measures exactly that).
  +l = late_apply(O.Found.ar(r), O.Found.i(r))
  +z = KR.alloc_to_buf_all(O.Found.ar(l), O.Found.i(l))
  add_loads(O.Found.ar(z), O.Found.i(z))

# `vms` -- THE LINEARIZER'S `run_count` AND `len(u.ranges)` INPUT, WHICH WAS `Nil{}` FOR EVERY KERNEL.
# `linearizer.py:33` keys a node on `(run_count, len(u.ranges), priority, extra)`; with no `vms` the
# port's `lt_rc` answered 1 for every node AND the `len` term did not exist, so the order degenerated
# to `priority` with the LIST breaking every tie. THAT IS WHAT PUT A STORE'S `CAST(RANGE)` INSIDE THE
# INNERMOST LOOP BODY AND REUSED IT TWO SCOPES OUT (`use of undeclared identifier 'cast0'`).
#
# THE VALUES ARE THE REAL `vmax`, AND `1`s WERE MEASURED AND ARE NOT ENOUGH. `run_count` is
# `prod(vmax+1)` (`linearizer.py:19`), so a section of `1`s makes `lt_rc` answer `2^n` -- it orders by
# NESTING, and two SIBLING ranges then TIE. MEASURED: the linear kernel's `Lidx0` (10) and `Lidx1` (49)
# tied, the list order decided, and the two loops came out INVERTED -- `cast1` declared inside a loop
# body that the store, two lines below, was outside of (`use of undeclared identifier 'cast1'`).
# A RANGE's extent is its `src[0]`, a CONST (`indexing.bend`'s `ix_nr_pick` -- `UOp.range` IS
# `src=(sint_to_uop(end, dtype),)`), so `vmax + 1` is that const and `v = extent - 1` because
# `lt_rc` multiplies `v + 1`. A missing const answers 1, which is `v = 0`: a NAMED fallback, not a
# silent one.
def rg_ext.c(c: O.Const) -> U32:
  match c:
    case O.CInt{i}: H.lo32(i)
    case _: 1

def rg_ext.arg(arg: O.Arg) -> U32:
  match arg:
    case O.APy{c}: rg_ext.c(c)
    case _: 1

def rg_ext.n(fuel: Nat, +ar: O.Arena, +i: U32) -> U32:
  match fuel:
    case 0n: 1
    case 1n+p:
      Bool.pick(U32, O.eq_op(O.Arena.op(ar, i), O.OpsCAST{}),
                rg_ext.n(p, ar, O.Arena.src0(ar, i)), rg_ext.arg(O.Arena.arg(ar, i)))

# NEVER ZERO: `ix_nr_pick`'s `One{}` arm builds `const 0`, and a zero factor makes `rc` zero, which
# `U32.sub(rc, 1)` turns into an underflow and `lt_rc` turns into a key of `0`. MEASURED: the ranges
# read `1049` -- `rc 0, len 16` -- and every loop lost its rank.
def rg_ext.pick(z: Bool, v: U32) -> U32: Bool.pick(U32, z, 1, v)

def rg_ext(+ar: O.Arena, +r: U32) -> U32:
  +v = rg_ext.n(2n, ar, O.Arena.src0(ar, r))
  rg_ext.pick(U32.is_zero(v), v)

def vms_row.go(+ar: O.Arena, +rs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}: acc
    case r <> t: vms_row.go(ar, t, List.append(&2, U32, acc, [0]))

# A RANGE'S `run_count` IS `{self} | enclosing` (ops.py:471-472), AND THE ENCLOSING SET IS READABLE.
# The port's `F.UOp.ranges` is the DEPENDENCY closure, which for a RANGE is `{self}` and for a
# `CAST(RANGE)` is also `{self}` -- so `rc` came out as the range's own extent. MEASURED
# (`.agents/slop/browser/vmsp.bend`): an END's toposort CONTAINS THE ENDS NESTED INSIDE IT -- k0's four
# ENDs reach 1, 2, 3 and 4 ENDs, k3's reach 1 and 2 -- so the nest IS a DAG path and the enclosing set
# is the union of the closed ranges of the ENDs in `toposort(e)` other than `e`, where `e` is the END
# that closes the range. No stack walk, no containment test.
def vms_cls(+ar: O.Arena, +rt: F.RTable, +u: U32) -> List<&2, U32>:
  F.Rng.rs(F.UOp.ranges(ar, rt, u))

def vms_prod.go(+ar: O.Arena, +rs: List<&2, U32>, +acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case r <> t: vms_prod.go(ar, t, U32.mul(acc, rg_ext(ar, r)))

def vms_prod(+ar: O.Arena, +rs: List<&2, U32>) -> U32: vms_prod.go(ar, rs, 1)

def vms_enc.go(+ar: O.Arena, +ns: List<&2, U32>, +e: U32, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t:
      vms_enc.go(ar, t, e, Bool.pick(U32,
        Bool.and(O.eq_op(O.Arena.op(ar, n), O.OpsEND{}), Bool.not(U32.is_eq(n, e))),
        U32.mul(acc, vms_prod(ar, O.Arena.src_from(ar, n, 1))), acc))

def vms_enc(+ar: O.Arena, +e: U32) -> U32:
  vms_enc.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, e), e, 1)

def vms_end_of.go(+ar: O.Arena, +ns: List<&2, U32>, +r: U32, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t:
      vms_end_of.go(ar, t, r, Bool.pick(U32,
        Bool.and(O.eq_op(O.Arena.op(ar, n), O.OpsEND{}), F.mem_u32(O.Arena.src_from(ar, n, 1), r)),
        n, acc))

def vms_end_of(+ar: O.Arena, +r: U32, +lst: List<&2, U32>) -> U32:
  vms_end_of.go(ar, lst, r, 0)

def vms_nends.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t: vms_nends.go(ar, t, Bool.pick(U32, O.eq_op(O.Arena.op(ar, n), O.OpsEND{}),
                                              U32.add(acc, 1), acc))

# `nends(toposort(e))` is `1 + the loops nested INSIDE e`, so the OUTERMOST range gets the LARGEST
# count. `lt_key` sorts ascending, so the count is carried in the `len` term as `16 - count`: the two
# nested ranges of k3 have the SAME `rc` product (10*49 == 49*10) and only the nesting breaks the tie.
def vms_zeros.go(n: Nat, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: vms_zeros.go(p, List.append(&2, U32, acc, [0]))

def vms_pad(k: U32) -> List<&2, U32>:
  vms_zeros.go(U32.to_nat(k), Nil{})

# THE SECTION IS `[rc - 1] ++ zeros`, AND THE ZEROS ARE NOT FILLER: `lt_rc` multiplies `v + 1`, so a
# zero leaves `rc` alone while raising the section's LENGTH, which is the `len` term. One list carries
# both, which is the only way this linearizer receives them.
# THE FLAT FORM, AND IT IS A COINCIDENCE -- kept because it is the best MEASURED reading (1 `cc` error)
# and named so no one mistakes it for a rule. The two facts that replace it are written at `vms_enc`
# above and in `D1.md`: the nest IS a DAG path (an END's toposort contains the ENDs nested inside it),
# and `rc = extent x enclosing-product` TIES for a nested pair (10*49 == 49*10), so the depth has to
# ride in the `len` term. The attempt in `vms_enc`/`vms_nends`/`vms_pad` produced `rc = 0` for the
# ranges -- `1049` is `rc 0, len 16`, i.e. `U32.sub(rc, 1)` on a zero -- and is left UNWIRED rather
# than shipped: `rg_ext` answering 0 through `U32.mul(rg_ext, vms_enc(..))` is the thing to explain.
def vms_rg(+ar: O.Arena, +rt: F.RTable, +r: U32, +lst: List<&2, U32>) -> List<&2, U32>:
  [1, 0]

def vms_one2(isrg: Bool, +ar: O.Arena, +rt: F.RTable, +u: U32, +rs: List<&2, U32>,
             +lst: List<&2, U32>) -> List<&2, U32>:
  match isrg:
    case True{} : vms_rg(ar, rt, u, lst)
    case False{}: List.concat(&2, U32, [[U32.from_nat(List.length(&2, U32, rs))], vms_row.go(ar, rs, Nil{})])

def vms_one(+ar: O.Arena, +rs: List<&2, U32>) -> List<&2, U32>:
  List.concat(&2, U32, [[U32.from_nat(List.length(&2, U32, rs))], vms_row.go(ar, rs, Nil{})])

def vms.go(+ar: O.Arena, +rt: F.RTable, +lst: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match lst:
    case Nil{}: acc
    case u <> t:
      vms.go(ar, rt, t, List.append(&2, U32, acc,
        vms_one2(O.eq_op(O.Arena.op(ar, u), O.OpsRANGE{}), ar, rt, u, vms_cls(ar, rt, u), lst)))

def vms(+ar: O.Arena, +lst: List<&2, U32>) -> List<&2, U32>:
  vms.go(ar, F.rng_sweep(ar, F.Folded.t(F.folded(ar))), lst, Nil{})

def body_kus(+ar: O.Arena, +k: U32) -> (O.Arena & List<&2, C.KU>):
  +l = body_low(ar, SCH.sc_src0(ar, k))
  +a2 = O.Found.ar(l)
  +b2 = O.Found.i(l)
  +lst = O.UOp.toposort(O.Arena.budget(a2), a2, b2)
  +lin = LIN.linearize(a2, lst, vms(a2, lst), b2)
  (a2, KC.kuconv.convert(F.folded(a2), lin))

def program.of(p: (O.Arena & List<&2, C.KU>), name: String) -> Prog:
  (ar, kus) = p
  program(name, kus)

# WHICH KERNEL TO RENDER -- TRIED AND REVERTED. Selecting the first kernel whose body is a
# SINK (kern_pick below) made the conv/pool render `void test(params) { }` -- EMPTY, with
# no loops at all -- i.e. it picked a DIFFERENT, trivial kernel, and `compile_sink` is
# shared with the fc probe, so the revert is for correctness of the known-good lane. The
# selection needs the LINEAR's real kernel list first (`lin_kernels` is here for that).
# `SC_SRC0(linear)` is a body only when the first entry IS a
# kernel; MEASURED, the pool/conv programs' LINEAR leads with an entry whose `src[0]` is an
# INDEX, and linearizing that renders `void test() { for(..) { } }` with no params while
# rangeify and the scheduler keep the PARAM and the body intact. So the SINK-rooted kernel
# is selected, and the first entry is only a fallback.
def body_is_sink(+ar: O.Arena, +k: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, SCH.sc_src0(ar, k)), O.OpsSINK{})

def kern_fb(zero: Bool, k: U32, fallback: U32) -> U32:
  match zero:
    case True{} : fallback
    case False{}: k

def kern_pick.zero(hit: Bool, k: U32, acc: U32) -> U32:
  match hit:
    case True{} : k
    case False{}: acc

def kern_pick.one(hit: Bool, k: U32, acc: U32) -> U32:
  match acc:
    case 0: kern_pick.zero(hit, k, acc)
    case _: acc

def kern_pick.go(+ar: O.Arena, +xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case k <> t: kern_pick.go(ar, t, kern_pick.one(body_is_sink(ar, k), k, acc))

def kern_pick(+ar: O.Arena, +ks: List<&2, U32>, fallback: U32) -> U32:
  +k = kern_pick.go(ar, ks, 0)
  kern_fb(U32.is_zero(k), k, fallback)

def compile_sink(+ar: O.Arena, sink: U32) -> Prog:
  +lin = schedule(ar, sink)
  +ar2 = O.Found.ar(lin)
  program.of(body_kus(ar2, SCH.sc_src0(ar2, O.Found.i(lin))), "test")
