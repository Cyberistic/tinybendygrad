# execfull.bend -- THE PORT's OWN `rz_built` FIXTURE -> THE PORT's OWN RANGIFY -> THE
# PORT's OWN `schedule()` -> `compile_sink` -> C -> `cc` -> RUN -> NUMBERS.
#
# WHAT THIS IS THAT `.agents/slop/execgap/` IS NOT. `execgate.bend` starts from
# `.agents/slop/graphcmp.bend`'s HAND-BUILT `lin` arena -- a PRE-SCHEDULED kernel -- because
# when it was written the port's `schedule()` answered ZERO kernels for a real graph. This
# lane starts one link earlier: `schedule/realize.bend`'s own 23-node sink -> `rangify.bend`'s
# `rr_kernel_graph` -> `runtime/device.bend`'s `compile_sink` (`schedule()` -> `body_low` ->
# `linearize` -> `kuconv` -> `render`). So the kernel below is not a fixture's kernel; it is
# the kernel THE PORT's OWN SCHEDULER CHOSE.
#
# THE DRIVER IS STILL THE HARNESS's (`main`, the three arrays, the `printf`) -- the same
# boundary `execgate.bend` names: upstream draws it at `CPUProgram.__call__`, not at the
# renderer. THE THREE BUFFER NAMES ARE SPELLED HERE, so a rename in the port is a COMPILE
# ERROR in this lane rather than a silently different call.
#
# THE EXPECTED OUTPUT IS `execgap/expected.rows`' (4x3)@(3x5) MATMUL, hand-derived there:
#   7 2 5 4 7 | 4 1 2 2 4 | 3 1 6 2 3 | 4 0 5 0 4
import Base
import ./../../../tinybendygrad/runtime/device.bend as D
import ./../../../tinybendygrad/schedule/rangify.bend as P
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/uop/ops.bend as O

def N0() -> U32: 20
def N1() -> U32: 12
def N2() -> U32: 15
def SENT() -> U32: 99

def A_VALS() -> List<&2, U32>: [1, 2, 3, 0, 1, 2, 3, 1, 0, 2, 0, 1]
def B_VALS() -> List<&2, U32>: [1, 0, 2, 0, 1, 0, 1, 0, 2, 0, 2, 0, 1, 0, 2]

# THE KERNEL, from the port's own chain. `compile_sink` is the lane's entry: no caller exists
# for it in the tree, so THIS FILE is its only caller.
def kernel_c() -> String:
  +q = RZ.rz_built()
  +k = P.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  D.Prog.src(D.compile_sink(O.Found.ar(k), O.Found.i(k)))

def init_go(+xs: List<&2, U32>, +neg: Bool, first: Bool, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t:
      init_go(t, neg, False{}, String.concat([acc, Bool.pick(String, first, "", ", "),
        Bool.pick(String, neg, "-", ""), U32.show(h)]))

def init(+xs: List<&2, U32>) -> String: init_go(xs, False{}, True{}, "")

def init_neg(+xs: List<&2, U32>) -> String: init_go(xs, True{}, True{}, "")

def out_init(n: U32) -> String: init_neg(List.replicate(U32, U32.to_nat(n), SENT()))

def drv(+k: String) -> String:
  String.concat([
    "#include <stdio.h>\n", k, "\n",
    "int main(void) {\n",
    "  float data0_20[", U32.show(N0()), "] = {", out_init(N0()), "};\n",
    "  float data1_12[", U32.show(N1()), "] = {", init(A_VALS()), "};\n",
    "  float data2_15[", U32.show(N2()), "] = {", init(B_VALS()), "};\n",
    "  test(data0_20, data1_12, data2_15);\n",
    "  int changed = 0;\n",
    "  for (int i = 0; i < ", U32.show(N0()), "; i++) if (data0_20[i] != -",
    U32.show(SENT()), ".0f) changed++;\n",
    "  printf(\"changed=%d\\n\", changed);\n",
    "  printf(\"out=\");\n",
    "  for (int i = 0; i < ", U32.show(N0()), "; i++) printf(\"%s%.0f\", i ? \" \" : \"\",",
    " data0_20[i]);\n",
    "  printf(\"\\n\");\n",
    "  return 0;\n}\n"])

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

def C_PATH() -> String: ".agents/slop/pipelinecensus/out/full.c"
def BIN_PATH() -> String: ".agents/slop/pipelinecensus/out/full.bin"

def main() -> IO(Unit):
  do IO<Unit>:
    +c : String = kernel_c()
    +src : String = drv(c)
    Unit <- row("c_len", U32.show(U32.from_nat(String.length(c))))
    Unit <- row("in12", init(A_VALS()))
    Unit <- row("in15", init(B_VALS()))
    f : File <- IO.try(File, File.open(C_PATH(), "w"))
    f2 : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File, File.write(f, src), wrote)
    Unit <- File.close(f2)
    Unit <- run("cc", "cc", ["-O1", "-o", BIN_PATH(), C_PATH()])
    Unit <- run("run", BIN_PATH(), [])
    return Unit{}
