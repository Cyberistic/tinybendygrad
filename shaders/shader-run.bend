# shaders/shader-run.bend -- THE SHADER THROUGH THE PORT'S OWN COMPILER, END TO END.
#
# VERDICT: **THE CHAIN RUNS AND THE SCHEDULE REFUSES.** `kernels=0` and
# `refused=unbacked-end`: the kernel graph was never SPLIT (the `PAD` the neighbour reads
# need is not lowered, so upstream's `create_schedule` would ASSERT -- `schedule/__init__.py:46`
# -- where the port answers an empty schedule). BEFORE THAT, the port built a kernel whose
# value was dropped, and the body was `*(buf0+Lidx0) = 1` for one buffer instead of the
# 256-cell circle over three. **THIS FILE IS A MEASURED REFUSAL AND NOT A RENDERER**, and it
# is kept because the four links below each answered ZERO (or `UNHANDLED`) rather than an
# error, and the next agent should start from the last measurement rather than from the
# beginning. THE ROOT CAUSE IS IN `README.md`: the rangify apply keeps `PAD` as a wall.
#
# THE CHAIN, and what each link cost:
#
#   shader.bend          the graph, over GIVEN inputs (`sh_graph_on`) so the gate can keep
#                        `Tensor.empty`'s ALLOC and the runner can use `mxw_buf`'s BUFFER
#   tn_assign_store      upstream's `out.assign(compute)`. WITHOUT IT: a bare expression
#                        under a SINK schedules NOTHING and `schedule` answers `kernels=0`
#                        rather than an error.
#   rr_kernel_graph      `SCH.schedule` IS `create_schedule`: `pass1`/`sa` WALK existing
#                        `Ops.AFTER` nodes and CREATE none, so the kernel graph must exist
#                        FIRST. `schedule/rangeify.bend:2570` still calls that stage
#                        "NOT PORTED" while `schedule/rangify.bend` has the driver.
#   per-body linearize   `LT.linearize` takes ONE kernel (`linrender`'s `g_lin` is a single
#                        sink); handing it the `LINEAR` renders `UNHANDLED(Ops.LINEAR)`.
#   vms                  `[count, width..]` per node, and `Nil{}` is NOT a default: every
#                        node then gets key 1, the priority sort collapses, and the body
#                        comes out with ONE op. Widths come from `F.UOp.vmax` (the port's
#                        own reader) and NOT from `linrender`'s hand-rolled chain walk.
#
# THE UNRESOLVED DEFECT, NOW PINNED. The kernel graph ITSELF carries the formula -- `eng_dump`
# shows `SINK(AFTER(INDEX, END(STORE, RANGE x4)))` and the `SQRT`, `RECIP`, `MAX` and the two
# `PAD`s -- and the loss is the `PAD`: the rangify apply CONSUMES the `SHRINK` but keeps the
# `PAD` as a wall (`rr_ap_wall_hit`, `schedule/rangify.bend:1474`), so the `PAD` reaches the
# kernel graph with a 2-D marg over a flattened graph, the fold refuses it, the `END` loses
# its fold row, and the schedule has no kernel to build. `README.md` has the chain and
# upstream's cure. `buf-schedules.bend` is the control: the same chain over `a + b` on two
# BUFFERs answers `kernels=1` AND renders the add, so the scheduler is not simply broken;
# this graph's `PAD` is.
#
# AND THE FOURTH LINK, WHICH IS A MISSING PORT AND NOT A WIRING GAP: an ALLOC has no
# realize-time rebind. `UOp.new_buffer` is `TODO(p3)` in `ops.bend`, and upstream's
# `linear_with_vars` (`tensor.py:184`) swaps ALLOC for BUFFER there. `schedule/realize.bend`'s
# own point 2 records that the port's Tensor path dodges it by building BUFFERs directly --
# which is why this runner takes `mxw_buf` and why a graph built the `Tensor.empty` way cannot
# be scheduled at all.
#
# TODO(p3) THE DRIVER IS THE HARNESS'S. `Cpu.compile`/`Cpu.exec` is the port's own device lane;
# this spawns hosted `cc` and execs the binary, exactly as `.agents/slop/execgap/` does.

import Base
import ../tinybendygrad/uop/ops.bend as O
import ../tinybendygrad/uop/fold.bend as F
import ../tinybendygrad/LAWS/spec.bend as S
import ../tinybendygrad/helpers.bend as H
import ../tinybendygrad/tensor.bend as T
import ../tinybendygrad/mixin/creation.bend as CR
import ../tinybendygrad/mixin/movement.bend as MX
import ../tinybendygrad/schedule/rangify.bend as RNG
import ../tinybendygrad/schedule/rangeify.bend as RG
import ../tinybendygrad/schedule/__init__.bend as SCH
import ../tinybendygrad/codegen/late/linearizer.bend as LT
import ../tinybendygrad/renderer/kuconv.bend as KUC
import ../tinybendygrad/renderer/cstyle.bend as C
import ./shader.bend as SH

def N() -> U32: 16
def NCELLS() -> U32: 256

type Kern is Data:
  Kern{name: String, bufs: List<&2, String>, c: String, refused: String}

def Kern.name(x: Kern) -> String:
  match x:
    case Kern{name, bufs, c, refused}: name

def Kern.bufs(x: Kern) -> List<&2, String>:
  match x:
    case Kern{name, bufs, c, refused}: bufs

def Kern.c(x: Kern) -> String:
  match x:
    case Kern{name, bufs, c, refused}: c

# THE REFUSAL, WHEN THERE IS ONE. Upstream's `create_schedule` ASSERTS that an END's src0
# is a CALL (`schedule/__init__.py:46`) -- the graph whose kernel graph was never SPLIT --
# and the port answers an EMPTY schedule for it (`sched_unbacked`), because a schedule
# missing a kernel is a schedule missing an output. The runner NAMES the refusal instead of
# rendering a kernel whose value was dropped.
def Kern.refused(x: Kern) -> String:
  match x:
    case Kern{name, bufs, c, refused}: refused

def names.go(+bs: List<&2, C.BArg>, +acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case b <> t: names.go(t, List.append(&2, String, acc, [C.BArg.name(b)]))

# ONE KERNEL BODY -> ITS CU LIST. `LT.linearize` takes a SINGLE kernel (`linrender`'s
# `g_lin` is one sink with a `KernelInfo`), and `create_schedule` hands back the kernel
# BODIES, so the loop belongs here and not in the linearizer.
# THE KERNEL, NAMED HERE AND NOT BY THE GRAPH. A kernel's name lives in its `KernelInfo`
# upstream and the port's kernel graph carries NONE (its `END` prints `:none:`), so
# `C.St.name` answers `test`. `render_kernel` takes the name as an argument, so the harness
# supplies it and no `KernelInfo` has to be invented.
def kern_at(+s: C.St, +ks: List<&2, C.KU>, +nm: String, +refused: String) -> Kern:
  Kern{nm, names.go(C.St.bufs(s), Nil{}),
    C.render_kernel(C.dev_clang(), True{}, nm,
      List.reverse(&2, String, C.St.kernel(s)), C.St.bufs(s), ks, 1), refused}

# `List.concat` IS `concat(n, T, List<List<T>>)` -- it flattens a LIST OF LISTS and cannot
# append one flat list to another (MEASURED: the four-argument form expects `List<List<KU>>`
# where `kuconv.convert` answers a flat `List<KU>`). So two flat lists are joined by handing
# it the pair.
# THE VARIABLE WIDTHS (`vms`), AND `Nil{}` IS NOT A DEFAULT FOR IT. `lt_vm.go` reads the list
# as `[count, width..]` PER NODE IN `lst` ORDER and `lt_rc` multiplies `(width+1)`, so an empty
# list gives every node the same key, the priority sort collapses, and the linearizer emits a
# body with one op in it -- MEASURED: `*(buf0+Lidx0) = 1`.
#
# THE WIDTH IS THE RANGE's `vmax`, WHICH UPSTREAM READS AS `(src[0]-1).vmax`, so the port's own
# `F.UOp.vmax` already answers it and NO subtraction belongs here. `linrender` walks
# RANGE->AFTER->CAST->CONST by hand because it predates the bound table; `F.mm.sweep` is that
# table and this uses it instead of copying the walk.
def bnd_u32(b: F.Bnd) -> U32:
  match b:
    case F.BndInt{neg, mag}: H.lo32(mag)
    case F.Bnd{inf}: 0
    case F.BndFlt{v}: 0

def w_of(+ar: O.Arena, +bt: F.BTable, +r: U32) -> U32:
  bnd_u32(Maybe.default(&2, F.Bnd, F.UOp.vmax(ar, bt, r), F.bnd_pinf()))

def widths_go(+ar: O.Arena, +bt: F.BTable, rs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}: acc
    case +r <> t: widths_go(ar, bt, t, List.append(&2, U32, acc, [w_of(ar, bt, r)]))

def vms_go(+ar: O.Arena, +bt: F.BTable, +rt: F.RTable, ns: List<&2, U32>,
           +acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case +n <> t:
      +w = widths_go(ar, bt, F.Rng.rs(F.UOp.ranges(ar, rt, n)), Nil{})
      vms_go(ar, bt, rt, t,
        List.concat(&2, U32, [acc, [U32.from_nat(List.length(&2, U32, w))], w]))

# THE SCHEDULER HANDS BACK CALLs (`create_schedule`: `k.replace(src=(k.body, *buf_uops))`,
# `tinygrad/schedule/__init__.py:71`) AND THE LINEARIZER TAKES THE BODY, AND
# `toposort_nocalls` DOES NOT DESCEND INTO A CALL -- so A CALL's WALK IS THE CALL ITSELF
# AND THE BODY IS NEVER RENDERED. THE BODY IS THE CALL's FIRST SRC (`k.body`) ✓.
def cus_body.pick(+ar: O.Arena, +k: U32, iscall: Bool) -> U32:
  match iscall:
    case True{}: O.Arena.src0(ar, k)
    case False{}: k

def cus_body(+ar: O.Arena, +k: U32) -> U32:
  cus_body.pick(ar, k, O.eq_op(O.Arena.op(ar, k), O.OpsCALL{}))


def cus_go(+ar: O.Arena, +fx: F.Folded, +bt: F.BTable, +rt: F.RTable, ks: List<&2, U32>,
           +acc: List<&2, C.KU>) -> List<&2, C.KU>:
  match ks:
    case Nil{}: acc
    case +k <> t:
      +body = cus_body(ar, k)
      +ns = O.UOp.toposort_nocalls(O.Arena.budget(ar), ar, body)
      +ix = LT.linearize(ar, ns, vms_go(ar, bt, rt, ns, Nil{}), body)
      cus_go(ar, fx, bt, rt, t, List.concat(&2, C.KU, [acc, KUC.kuconv.convert(fx, ix)]))

# THE WHOLE PORT-SIDE CHAIN, AS ONE PURE DEF.
#
# THREE LINKS WERE MISSING AND EACH ONE ANSWERS ZERO RATHER THAN AN ERROR:
#   1. the ASSIGN -- a bare expression under a SINK schedules nothing;
#   2. `rr_kernel_graph` -- `SCH.schedule` IS `create_schedule`, which WALKS existing
#      kernels and creates none, so a graph with no kernels answers `kernels=0`;
#   3. the PER-BODY linearize -- `linearize` takes ONE kernel, and the scheduler returns
#      the bodies, so handing it the `LINEAR` renders `UNHANDLED(Ops.LINEAR)`.
# THE SINK, SPLIT OUT BECAUSE ONE DEF LARGE ENOUGH TO HOLD THE WHOLE CHAIN DOES NOT COMPILE
# (MEASURED: bend answers "a def whose body is implemented before the def is used" naming a
# generated binder, with the shader's 55-node formula and the buffer construction in one term).
def sink_of() -> O.Found:
  # `UOp.new_buffer` AND NOT `mxw_buf`: the general def is the port's `new_buffer`
  # (`ops.bend`, `ops.py:809`), which was a `TODO(p3)` until it was written. Using it here is
  # what proves it builds the node `mxw_buf` builds -- `mxw_buf` is the f32/GLOBAL shortcut
  # over exactly this call.
  #
  # THE BUFFERS ARE (16,16) AND NOT (256,). Upstream's `Tensor.empty((16,16))` is
  # `ALLOC(prod)` + `RESHAPE(shape)` (`tensor.py`), and the formula is TWO-DIMENSIONAL, so a
  # flat buffer is a graph upstream would never build: the `PAD`'s marg has TWO pairs and a
  # flat input has ONE dim, and the fold refuses that on the length check (upstream's
  # `len(ps) != len(self.marg)`, `ops.py:397-405`). MEASURED, THE RUNNER'S OWN TENSOR GRAPH:
  # the first `PAD` answers `18:GAP` with the flat buffers and `21:ok` with the (16,16) ones.
  +x0 = O.UOp.new_buffer(O.Arena.empty(), S.D1{0}, 256, S.single(), Some{1})
  +xvw = T.tn_wrap_uop(O.Found.ar(x0), O.Found.i(x0))
  +xv = MX.mxw_reshape.go(xvw, [16, 16])
  +y0 = O.UOp.new_buffer(T.Tensor.ar(xv), S.D1{0}, 256, S.single(), Some{2})
  +yvw = T.tn_wrap_uop(O.Found.ar(y0), O.Found.i(y0))
  +yv = MX.mxw_reshape.go(yvw, [16, 16])
  +t = SH.sh_graph_on(xv, yv)
  +o0 = O.UOp.new_buffer(O.Found.ar(t), S.D1{0}, 256, S.single(), Some{0})
  +ow = T.tn_wrap_uop(O.Found.ar(o0), O.Found.i(o0))
  +o = MX.mxw_reshape.go(ow, [16, 16])
  T.tn_assign_store(T.Tensor.ar(o), T.Tensor.u(o), O.Found.i(t))

# THE WHOLE PORT-SIDE CHAIN.
#
# THREE LINKS WERE MISSING AND EACH ONE ANSWERS ZERO RATHER THAN AN ERROR:
#   1. the ASSIGN -- a bare expression under a SINK schedules nothing;
#   2. `rr_kernel_graph` -- `SCH.schedule` IS `create_schedule`, which WALKS existing
#      kernels and creates none, so a graph with no kernels answers `kernels=0`;
#   3. the PER-BODY linearize -- `linearize` takes ONE kernel, and the scheduler returns
#      the bodies, so handing it the `LINEAR` renders `UNHANDLED(Ops.LINEAR)`.
# THE REFUSAL, WITH UPSTREAM'S OWN WORDS. Upstream's `create_schedule` says
# `assert k.src[0].op is Ops.CALL, f"END src[0] should be KERNEL, not {k.src[0].op}"`
# (`schedule/__init__.py:46`). THE PORT CANNOT ASSERT, SO IT ANSWERS AN EMPTY SCHEDULE
# (`sched_unbacked`) -- AND THE RUNNER, WHICH OWNS NO SCHEDULE OF ITS OWN, NAMES WHAT
# UPSTREAM WOULD HAVE ASSERTED: the END's src0 and its op.
def refused_of(+kg: O.Found) -> String:
  +ar = O.Found.ar(kg)
  +end = O.Arena.src(ar, O.Arena.src0(ar, O.Found.i(kg)), 1)
  String.concat(["END src[0] should be KERNEL, not ", O.Ops.name(O.Arena.op(ar, O.Arena.src0(ar, end)))])

def build() -> Kern:
  +st = sink_of()
  +sk = O.UOp.sink(O.Found.ar(st), [O.Found.i(st)])
  +kg = RNG.rr_kernel_graph(O.Found.ar(sk), O.Found.i(sk))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ar = SCH.lin_ar(lin)
  +fx = F.folded(ar)
  +bt = F.mm.sweep(ar, F.Folded.t(fx))
  +rt = F.rng_sweep(ar, F.Folded.t(fx))
  +kus = cus_go(ar, fx, bt, rt, SCH.lin_kernels(lin), Nil{})
  +ref = Bool.pick(String, SCH.sched_unbacked(O.Found.ar(kg), O.Found.i(kg)), refused_of(kg), "")
  kern_at(C._render(C.dev_clang(), kus), kus, "circle", ref)

def buf_at(+ns: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ns, i), "<missing>")

def sig(+k: Kern) -> String:
  String.concat([Kern.name(k), "(", String.join(Kern.bufs(k), ","), ")"])

# THE GRID IS COMPUTED IN C AND NOT PASTED, so the values the kernel reads are the same
# formula the Python side's `--values` lane uses: `((i + 0.5) / N) * 2 - 1` per axis.
def grid(buf: String) -> String:
  String.concat(["  for (int a = 0; a < ", U32.show(N()), "; a++) for (int b = 0; b < ",
    U32.show(N()), "; b++) ", buf, "[a*", U32.show(N()), "+b] = (((float)(a + 0.5)) / ",
    U32.show(N()), ".0f) * 2.0f - 1.0f;\n"])

# `%.6f` AND NOT `%g`: the comparison is against a float32 the other lane also prints to six
# places, and `%g` would drop a `-0.000000` that `%f` keeps -- a difference in the printing
# and not in the number.
def drv(+k: Kern) -> String:
  String.concat([
    "#include <stdio.h>\n", Kern.c(k), "\nint main(void) {\n",
    "  float ", buf_at(Kern.bufs(k), 0n), "[", U32.show(NCELLS()), "];\n",
    grid(buf_at(Kern.bufs(k), 0n)),
    "  float ", buf_at(Kern.bufs(k), 1n), "[", U32.show(NCELLS()), "];\n",
    grid(buf_at(Kern.bufs(k), 1n)),
    "  float ", buf_at(Kern.bufs(k), 2n), "[", U32.show(NCELLS()), "];\n",
    "  for (int i = 0; i < ", U32.show(NCELLS()), "; i++) ", buf_at(Kern.bufs(k), 2n),
    "[i] = -99.0f;\n",
    "  ", Kern.name(k), "(", buf_at(Kern.bufs(k), 0n), ", ", buf_at(Kern.bufs(k), 1n), ", ",
    buf_at(Kern.bufs(k), 2n), ");\n",
    "  printf(\"sig=%s\\n\", \"", sig(k), "\");\n",
    "  printf(\"out=\");\n",
    "  for (int i = 0; i < ", U32.show(NCELLS()), "; i++) printf(\"%s%.6f\", i ? \" \" : \"\", ",
    buf_at(Kern.bufs(k), 2n), "[i]);\n",
    "  printf(\"\\n\");\n  return 0;\n}\n"])

def C_PATH() -> String: "shaders/out/circle.c"
def BIN_PATH() -> String: "shaders/out/circle.bin"

def wrote(m: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  (f, r) = m
  do IO<File>:
    u : Unit <- IO.pass(Unit, r)
    IO.pure(File, f)

def on_done(+nm: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Unit):
  match r:
    case Done{value}:
      (code, (out, err)) = value
      do IO<Unit>:
        Unit <- IO.print(String.concat(["# ", nm, "_status=", U32.show(code)]))
        Unit <- IO.print(String.concat(["# ", nm, "_err<", String.trim(err), ">"]))
        IO.print(String.trim(out))
    case Fail{(code, msg)}:
      IO.print(String.concat(["# ", nm, "_fail=", U32.show(code), " ", msg]))

def run(+nm: String, prog: String, args: List<String>) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Unit,
    Process.run(prog, args, "", 1000000, 120000), on_done(nm))

def diag() -> List<&2, String>:
  +t = SH.sh_graph()
  +sk = O.UOp.sink(O.Found.ar(t), [O.Found.i(t)])
  +o = CR.cr_empty(O.Found.ar(t), Some{S.single()}, [16, 16], S.D1{0})
  +st = T.tn_assign_store(T.Tensor.ar(o), T.Tensor.u(o), O.Found.i(t))
  +sk2 = O.UOp.sink(O.Found.ar(st), [O.Found.i(st)])
  +kg = RNG.rr_kernel_graph(O.Found.ar(sk2), O.Found.i(sk2))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ks = SCH.lin_kernels(lin)
  +k0 = Maybe.default(&2, U32, List.get(&2, U32, ks, 0n), 0)
  +lf = SCH.linear(lin)
  +ns = O.UOp.toposort_nocalls(O.Arena.budget(O.Found.ar(lf)), O.Found.ar(lf), O.Found.i(lf))
  [String.concat(["graph_nodes=", U32.show(O.Arena.next(O.Found.ar(t)))]),
   String.concat(["sink_op=", O.Ops.name(O.Arena.op(O.Found.ar(sk), O.Found.i(sk)))]),
   String.concat(["kernels=", U32.show(U32.from_nat(List.length(&2, U32, ks)))]),
   String.concat(["lin_nodes=", U32.show(O.Arena.next(O.Found.ar(lf)))]),
   String.concat(["topo=", U32.show(U32.from_nat(List.length(&2, U32, ns)))]),
   String.concat(["kout0=", O.Ops.name(O.Arena.op(SCH.lin_ar(lin), k0))]),
   String.concat(["kout0_src0=", O.Ops.name(O.Arena.op(SCH.lin_ar(lin), O.Arena.src(SCH.lin_ar(lin), k0, 0)))]),
   String.concat(["body_nodes=", U32.show(U32.from_nat(List.length(&2, U32, O.UOp.toposort_nocalls(O.Arena.budget(SCH.lin_ar(lin)), SCH.lin_ar(lin), k0))))]),
   String.concat(["body_value_nodes=", U32.show(U32.from_nat(List.length(&2, U32, O.UOp.toposort_nocalls(O.Arena.budget(SCH.lin_ar(lin)), SCH.lin_ar(lin), O.Arena.src(SCH.lin_ar(lin), k0, 1)))))]) ,
   String.concat(["kout0_dump=", RG.eng_dump(SCH.lin_ar(lin), k0)]),
   String.concat(["kout0_nsrc=", U32.show(U32.from_nat(List.length(&2, U32, O.Arena.srcs(SCH.lin_ar(lin), k0))))]),
   String.concat(["kg=", RG.eng_dump(O.Found.ar(kg), O.Found.i(kg))])]

def put(rs: List<&2, String>) -> IO(Unit):
  match rs:
    case Nil{}: IO.pure(Unit, Unit{})
    case +r <> rest:
      do IO<Unit>:
        a : Unit <- IO.print(String.concat(["# ", r]))
        b : Unit <- put(rest)
        IO.pure(Unit, b)

# THE RENDER, AND THE REFUSAL, AS TWO DEFS AND A MATCH. THE REFUSAL IS A MATCH ON A
# PARAMETER -- THE PORT'S SPELLING FOR A VALUE-DEPENDENT BRANCH (a match may not scrutinize
# a computed value) -- AND THE TWO EFFECTS LIVE IN DEFS OF THEIR OWN, SO THE TAKEN ONE IS
# THE ONLY ONE THAT RUNS. MEASURED: on a refused run `shaders/out/` stays EMPTY, and the
# row `refused=unbacked-end` is the last thing printed.
def go_render(+k: Kern, c_only: Bool) -> IO(Unit):
  Bool.pick(IO(Unit), c_only,
    IO.print(Kern.c(k)),
    do IO<Unit>:
      f : File <- IO.try(File, File.open(C_PATH(), "w"))
      f2 : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File,
        File.write(f, drv(k)), wrote)
      Unit <- File.close(f2)
      Unit <- run("cc", "cc", ["-O1", "-o", BIN_PATH(), C_PATH()])
      run("run", BIN_PATH(), []))

def go_refused(+k: Kern) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print(String.concat(["# refused=", Kern.refused(k)]))
    IO.pure(Unit, Unit{})

def go_pick(empty: Bool, +k: Kern, c_only: Bool) -> IO(Unit):
  match empty:
    case True{}: go_render(k, c_only)
    case _: go_refused(k)

def go(+k: Kern, c_only: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- put(diag())
    Unit <- IO.print(String.concat(["# sig=", sig(k)]))
    Unit <- IO.print(String.concat(["# c_len=", U32.show(U32.from_nat(String.length(Kern.c(k))))]))
    go_pick(String.eq(Kern.refused(k), ""), k, c_only)

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    +n : String = Maybe.default(&1, String, List.get(&1, String, as, 1n), "")
    go(build(), String.eq(n, "c"))
