# execgate.bend -- THE PORT's OWN KERNEL, COMPILED AND RUN, WITH NO CPython IN THE LOOP.
#
#   ./bin/bend .agents/slop/execgap/execgate.bend
#   .venv/bin/python .agents/slop/execgap/execgate-gate.py          # the gate, which decides
#
# WHAT RUNS, AND IN WHOSE CODE. The chain below is the port's from the pre-scheduled arena
# onward; the two ends are named because the gap is at the ends and not in the middle:
#
#   the arena       `.agents/slop/graphcmp.bend`'s `g_lin()` -- a HAND-BUILT fixture that
#                   matches upstream's scheduled `(4,3)@(3,5)` matmul. **NOT THE PORT's
#                   SCHEDULER.** The port has no working scheduler for a real graph: its
#                   engine's stage 1 (`run_rangeify`) is not driven, so `schedule()` answers
#                   ZERO kernels (`.agents/slop/chain/GAP.md`, measured). THIS LANE DOES NOT
#                   SCHEDULE ANYTHING, AND SAYING SO IS PART OF THE CLAIM.
#   the fold        `tinybendygrad/uop/fold.bend`          -- the port's
#   the toposort    `tinybendygrad/uop/ops.bend`           -- the port's (`toposort_nocalls`)
#   the linearizer  `tinybendygrad/codegen/late/linearizer.bend` -- the port's
#   the converter   `tinybendygrad/renderer/kuconv.bend`   -- the port's
#   the renderer    `tinybendygrad/renderer/cstyle.bend`   -- the port's, and it emits the
#                   WHOLE kernel: the typedef, the signature, the two loop heads, the three
#                   tap names, the index arithmetic, the store and the braces.
#   the driver      THIS FILE. `main()`, the buffers and their data. It is the harness, in
#                   exactly the way `emit-mm.bend`'s body was, and it is named here so that
#                   nobody has to guess which half of the C is whose.
#
# AND THE EXECUTION IS IN BEND TOO: `Base` has `File.open`/`File.write` and `Process.run`, so
# this ONE `bin/bend` invocation writes the `.c`, runs `cc`, runs the binary, and prints the
# binary's own stdout. NO PYTHON PROCESS IS INVOLVED IN PRODUCING A NUMBER.
#
# THE PLANTED LANES ARE SEPARATE DEFS AND THE MEASURED ONE IS NEVER PLANTED: `main` reads an
# optional argv tag and `plant_of` maps it to a tag; tag 0 is `drv_real`, and 1..3 are only
# reachable by asking for them by name.
import Base
import ./../linrender/linrender.bend as LR
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/uop/ops.bend as O

# THE DEVICE AND THE SHAPES. `dev_clang` is upstream's own `ClangRenderer`; the three sizes are
# the FIXTURE's element counts (4x5 out, 4x3 left, 3x5 right) and they are pinned twice over:
# the port's own buffer NAMES carry them (`data0_20`), so the `sig` row below moves if they
# ever disagree.
def N0() -> U32: 20
def N1() -> U32: 12
def N2() -> U32: 15

# THE INPUTS. TWO MATRICES WITH NO STRUCTURE TO HIDE BEHIND: they are not rank-1, they are not
# symmetric, and the right one is not its own transpose, so a kernel that swapped the two
# operands, or indexed one of them the wrong way round, produces DIFFERENT NUMBERS. The values
# are small integers, so the product is exact in binary32 and no tolerance is needed anywhere.
#
#   A (4x3, `data1_12`)      B (3x5, `data2_15`)
#   1 2 3                    1 0 2 0 1
#   0 1 2                    0 1 0 2 0
#   3 1 0                    2 0 1 0 2
#   2 0 1
#
# THE EXPECTED OUTPUT IS HAND-DERIVED IN `expected.rows` AND THE DERIVATION IS IN THE REPORT.
# IT IS NOT COMPUTED BY ANY PROGRAM ON THIS PATH.
def A_VALS() -> List<&2, U32>: [1, 2, 3, 0, 1, 2, 3, 1, 0, 2, 0, 1]
def B_VALS() -> List<&2, U32>: [1, 0, 2, 0, 1, 0, 1, 0, 2, 0, 2, 0, 1, 0, 2]

# THE SENTINEL IS -99 BECAUSE THE ANSWER CONTAINS ZEROS: a buffer that was never written and a
# buffer of the right shape full of zeroes must not look alike, and `changed` counts the cells
# that moved off the sentinel.
def SENT() -> U32: 99

type Kern is Data:
  Kern{name: String, bufs: List<&2, String>, c: String}

# A LOCALLY-DECLARED `Data` RECORD HAS NO PROJECTION SYNTAX (`cstyle.bend:116-118` says the same
# thing about `BArg`): the readers are written by hand or `Kern.name(k)` is "a defined name".
def Kern.name(x: Kern) -> String:
  match x:
    case Kern{name, bufs, c}: name

def Kern.bufs(x: Kern) -> List<&2, String>:
  match x:
    case Kern{name, bufs, c}: bufs

def Kern.c(x: Kern) -> String:
  match x:
    case Kern{name, bufs, c}: c

def names.go(+bs: List<&2, C.BArg>, +acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case b <> t: names.go(t, List.append(&2, String, acc, [C.BArg.name(b)]))

# ONE `_render` WALK, THEN `render`'s OWN BODY (`cstyle.bend`'s `render`,
# `render_kernel_body` + `render_kernel`), because the harness needs the NAME and the BUFFER
# NAMES the walk produced -- and `render` folds all three into one string.
def kern_at(+s: C.St, +ks: List<&2, C.KU>) -> Kern:
  Kern{C.St.name(s), names.go(C.St.bufs(s), Nil{}),
    C.render_kernel(C.dev_clang(), True{}, C.St.name(s),
      List.reverse(&2, String, C.St.kernel(s)), C.St.bufs(s), ks, 1)}

def kern() -> Kern:
  +ks = LR.lin_build()
  kern_at(C._render(C.dev_clang(), ks), ks)

# THE SIGNATURE, SPELLED FROM THE PORT's OWN RECORDS AND NOT PARSED OUT OF THE TEXT.
def sig_of(+k: Kern) -> String:
  String.concat([Kern.name(k), "(", String.join(Kern.bufs(k), ","), ")"])

def buf_at(+ns: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ns, i), "<missing>")

# A C initialiser from a `List<U32>`, so the numbers in the driver and the numbers printed as
# the `in` rows are THE SAME LIST and cannot disagree.
def init_go(+xs: List<&2, U32>, +neg: Bool, first: Bool, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t:
      init_go(t, neg, False{}, String.concat([acc, Bool.pick(String, first, "", ", "),
        Bool.pick(String, neg, "-", ""), U32.show(h)]))

def init(+xs: List<&2, U32>) -> String: init_go(xs, False{}, True{}, "")

# THE SIGN IS NOT COSMETIC. `SENT()` IS 99 AND THE DRIVER COMPARES AGAINST `-99.0f`, SO AN
# INITIALISER THAT WROTE `+99` WOULD COUNT EVERY CELL AS WRITTEN AND THE `changed` CONTROL WOULD
# READ 20 FOR A KERNEL THAT DID NOTHING. MEASURED -- this is what the first version did, and
# `plant=nocall` is what found it (the report's §4.2).
def init_neg(+xs: List<&2, U32>) -> String: init_go(xs, True{}, True{}, "")

# NO RECURSION FOR THE SENTINELS: `List.replicate` says it once, and a match arm may not call
# the def it is in, so the twenty-element initialiser is built rather than counted down.
def out_init(n: U32) -> String: init_neg(List.replicate(U32, U32.to_nat(n), SENT()))

# THE DRIVER. `kern` is spliced in whole, so the call below names the port's function and the
# port's buffers; `call` is the ONE line a plant is allowed to move.
def drv(+k: Kern, call: String) -> String:
  String.concat([
    "#include <stdio.h>\n", Kern.c(k), "\n",
    "int main(void) {\n",
    "  float ", buf_at(Kern.bufs(k), 0n), "[", U32.show(N0()), "] = {", out_init(N0()), "};\n",
    "  float ", buf_at(Kern.bufs(k), 1n), "[", U32.show(N1()), "] = {", init(A_VALS()), "};\n",
    "  float ", buf_at(Kern.bufs(k), 2n), "[", U32.show(N2()), "] = {", init(B_VALS()), "};\n",
    call, "\n",
    "  int changed = 0;\n",
    "  for (int i = 0; i < ", U32.show(N0()), "; i++) if (", buf_at(Kern.bufs(k), 0n), "[i] != -",
    U32.show(SENT()), ".0f) changed++;\n",
    "  printf(\"changed=%d\\n\", changed);\n",
    "  printf(\"out=\");\n",
    "  for (int i = 0; i < ", U32.show(N0()), "; i++) printf(\"%s%.0f\", i ? \" \" : \"\", ",
    buf_at(Kern.bufs(k), 0n), "[i]);\n",
    "  printf(\"\\n\");\n",
    "  return 0;\n}\n"])

def call_real(+k: Kern) -> String:
  String.concat(["  ", Kern.name(k), "(", buf_at(Kern.bufs(k), 0n), ", ",
    buf_at(Kern.bufs(k), 1n), ", ", buf_at(Kern.bufs(k), 2n), ");"])

# ---- THE PLANTS. Each is its own def and none of them is reachable without naming it.
# `data` moves ONE input cell (B's first 1 becomes a 2): the answer must move, so a comparison
# that did not look at the numbers would stay green.
# `swap` calls the kernel with the two operands the wrong way round: the shape is legal (3x5 is
# not 4x3 -- so this one would also overflow a naive driver) and the VALUES must move.
# `nocall` never calls the kernel: `changed=0` is the control that a seam which did nothing
# cannot pass.
def B_VALS_PLANT() -> List<&2, U32>: [2, 0, 2, 0, 1, 0, 1, 0, 2, 0, 2, 0, 1, 0, 2]

def drv_data(+k: Kern) -> String:
  String.concat([
    "#include <stdio.h>\n", Kern.c(k), "\n",
    "int main(void) {\n",
    "  float ", buf_at(Kern.bufs(k), 0n), "[", U32.show(N0()), "] = {", out_init(N0()), "};\n",
    "  float ", buf_at(Kern.bufs(k), 1n), "[", U32.show(N1()), "] = {", init(A_VALS()), "};\n",
    "  float ", buf_at(Kern.bufs(k), 2n), "[", U32.show(N2()), "] = {", init(B_VALS_PLANT()), "};\n",
    call_real(k), "\n",
    "  int changed = 0;\n",
    "  for (int i = 0; i < ", U32.show(N0()), "; i++) if (", buf_at(Kern.bufs(k), 0n), "[i] != -",
    U32.show(SENT()), ".0f) changed++;\n",
    "  printf(\"changed=%d\\n\", changed);\n",
    "  printf(\"out=\");\n",
    "  for (int i = 0; i < ", U32.show(N0()), "; i++) printf(\"%s%.0f\", i ? \" \" : \"\", ",
    buf_at(Kern.bufs(k), 0n), "[i]);\n",
    "  printf(\"\\n\");\n",
    "  return 0;\n}\n"])

def drv_swap(+k: Kern) -> String:
  drv(k, String.concat(["  ", Kern.name(k), "(", buf_at(Kern.bufs(k), 0n), ", ",
    buf_at(Kern.bufs(k), 2n), ", ", buf_at(Kern.bufs(k), 1n), ");"]))

def drv_nocall(+k: Kern) -> String: drv(k, "  /* the kernel is deliberately not called */")

# ---- THE IO. Write the `.c`, run `cc`, run the binary, print what the BINARY said.
def row(+nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def wrote(m: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  (f, r) = m
  do IO<File>:
    u : Unit <- IO.pass(Unit, r)
    IO.pure(File, f)

def rows_of(+nm: String, code: U32, out: String, err: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- row(String.concat([nm, "_status"]), U32.show(code))
    Unit <- IO.print(String.concat([nm, "_err<", String.trim(err), ">"]))
    IO.print(String.trim(out))
def on_done(+nm: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Unit):
  match r:
    case Done{value}:
      (code, (out, err)) = value
      rows_of(nm, code, out, err)
    case Fail{(code, msg)}:
      row(String.concat([nm, "_fail"]), String.concat([U32.show(code), " ", msg]))


def run(+nm: String, prog: String, args: List<String>) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Unit,
    Process.run(prog, args, "", 1000000, 120000), on_done(nm))

# THE PATH. It is under the state directory, so the `.c` and the binary are visible to a reader
# after the run and `rm -rf` on this one directory removes them; a `/tmp` path would hide both.
def C_PATH() -> String: ".agents/slop/execgap/out/k.c"
def BIN_PATH() -> String: ".agents/slop/execgap/out/k.bin"

def plant_of(+s: String) -> U32:
  match s:
    case "plant=data": 1
    case "plant=swap": 2
    case "plant=nocall": 3
    case _: 0

def mode_of(t: U32) -> String:
  match t:
    case 1: "plant=data"
    case 2: "plant=swap"
    case 3: "plant=nocall"
    case _: "real"

def src_of(t: U32, +k: Kern) -> String:
  match t:
    case 1: drv_data(k)
    case 2: drv_swap(k)
    case 3: drv_nocall(k)
    case _: drv(k, call_real(k))

def arg1(as: List<&1, String>) -> String:
  Maybe.default(&1, String, List.get(&1, String, as, 1n), "")

def go(+p : String, +k: Kern) -> IO(Unit):
  do IO<Unit>:
    +t : U32 = plant_of(p)
    +src : String = src_of(t, k)
    Unit <- row("mode", mode_of(t))
    Unit <- row("sig", sig_of(k))
    Unit <- row("c_len", U32.show(U32.from_nat(String.length(Kern.c(k)))))
    Unit <- row("in12", init(A_VALS()))
    Unit <- row("in15", init(Bool.pick(List<&2, U32>, U32.is_eq(t, 1), B_VALS_PLANT(), B_VALS())))
    f : File <- IO.try(File, File.open(C_PATH(), "w"))
    f2 : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File, File.write(f, src), wrote)
    Unit <- File.close(f2)
    Unit <- run("cc", "cc", ["-O1", "-o", BIN_PATH(), C_PATH()])
    Unit <- run("run", BIN_PATH(), [])
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<&1, String> <- IO.args()
    p : String <- IO.pure(String, arg1(as))
    go(p, kern())

# THE TODOs, AS COMMENTS BECAUSE rg IS HOW THEY GET FOUND. Each one is a measured wall and not
# a wish; the report's §6 has the evidence for each.
#
# TODO(p3) schedule/rangeify.bend:2810 -- STAGE 1 `run_rangeify`'s APPLY HALF is not driven, so
#   the port's own `schedule()` answers ZERO kernels for a real graph (`.agents/slop/chain/GAP.md`)
#   and THIS LANE SCHEDULES NOTHING: its arena is `graphcmp.bend`'s hand-built `g_lin`. THE
#   MISSING LINK IS ONE STAGE, AND IT IS THE LINK BETWEEN "a Tensor" AND THIS FILE.
#
# TODO(p3) runtime/ops_cpu.bend -- the LAUNCH is `cc` + `exec` here, and the port's OWN device
#   lane is not on the path: `Cpu.compile` builds a FREESTANDING object (`-nostdlib`,
#   `-ffreestanding`, `-o -`) and `Cpu.exec` mmaps and calls it in-process, which is a different
#   shape from a hosted `main` that prints through libc. Routing this lane through those two
#   effects would make the launch the port's too; `.agents/slop/cpuseam/launch.bend` is the
#   worked example and its own report names the one stage it could not run on the machine it had.
#
# TODO(p3) the DRIVER IS THE HARNESS'S. `main`, the three buffer arrays and the printf are this
#   file's; the port emits the KERNEL. Upstream draws the same line -- its launcher is
#   `CPUProgram.__call__`, not the renderer -- so this is a boundary and not a gap, but it means
#   "the port ran a program" is not yet a sentence this tree can say.
#
# TODO(p3) ONE KERNEL, ONE DTYPE, ONE ADDRSPACE. The kernel is f32, GLOBAL, two RANGEs, LOAD/STORE
#   and MUL/ADD (+ one `int` index ALU). `SPECIAL`, `BARRIER`, `CALL`, `CUSTOM_FUNCTION`, the
#   vectorised `float4` path and every non-f32 dtype are UNREACHED BY THIS LANE and are gated
#   elsewhere (`gates/cstyle_render_census-gate.py` renders them as TEXT; nothing executes them).
#
# TODO(p3) NO PLANT AT THE PORT's OWN SOURCE LEVEL. The three plants move the harness's inputs and
#   the call site; none of them edits a shipped `.bend` file, because editing a path another unit
#   is compiling is the hazard `AGENTS.md` records (`checks/bendlock.sh`, mid-run). The
#   port-level plant that is cheap and real -- feed `LT.linearize` a `Nil{}` vms table, the
#   defect `.agents/slop/linrender/REPORT.md` §2 found -- is NOT RUN, and it is the next thing to
#   measure, because THIS kernel's three products are summed left to right in both orders, so the
#   tap ORDER alone may be semantically inert here and the plant may need a different kernel.

