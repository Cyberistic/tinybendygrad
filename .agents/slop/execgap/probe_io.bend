# probe_io.bend -- WHAT THE HARNESS NEEDS FROM `Base`, MEASURED BEFORE IT IS RELIED ON.
#
# The execution lane needs FOUR things from outside the port: write a `.c`, run `cc`, run the
# binary, read the binary's stdout. `Base`'s own guide names `File.open/write/close` and
# `Process.run`, so this probe MEASURES them instead of assuming them: a lane that cannot
# spawn a process has to say so, and a lane that CAN has to prove it before its rows count.
#
#   ./bin/bend .agents/slop/execgap/probe_io.bend
#
# THE FOUR SPELLINGS THAT COST THIS PROBE A BUILD EACH, AND ALL FOUR ARE `Base`'s OWN CONTRACT:
#   * `File.open` answers a `Result`, so it is unwrapped with `IO.try`;
#   * every effect on a HANDLE hands the handle BACK beside its result (`File.write` answers
#     `IO(File & Result<..,Unit>)`), so its continuation destructures the pair;
#   * a do block's `=` bind takes a TYPE and cannot destructure, so the pair is destructured
#     in a DEF (`(f, r) = m`) -- the spelling `sz.bend` and `symrules-driver.bend` use; and
#   * `Process.run`'s `Done` payload is `U32 & (String & String)` (status, stdout, stderr) and
#     there is no `Done` TYPE to name, so the continuation matches the `Result` -- the shape
#     `gates/ops_bend-gate.bend:423` already uses.
import Base

def row(+nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def wrote(m: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  (f, r) = m
  do IO<File>:
    u : Unit <- IO.pass(Unit, r)
    IO.pure(File, f)

def done_rows(+nm: String, code: U32, out: String, err: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- row(String.concat([nm, "_status"]), U32.show(code))
    Unit <- IO.print(String.concat([nm, "_out<", String.trim(out), ">"]))
    IO.print(String.concat([nm, "_err<", String.trim(err), ">"]))

def on_done(+nm: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Unit):
  match r:
    case Done{value}:
      (code, (out, err)) = value
      done_rows(nm, code, out, err)
    case Fail{(code, msg)}:
      row(String.concat([nm, "_fail"]), String.concat([U32.show(code), " ", msg]))

def run(+nm: String, prog: String, args: List<String>) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Unit,
    Process.run(prog, args, "", 1000000, 60000), on_done(nm))

def main() -> IO(Unit):
  do IO<Unit>:
    +p : String = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/execgap-probe"
    f : File <- IO.try(File, File.open(String.concat([p, ".c"]), "w"))
    f2 : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File,
      File.write(f, "#include <stdio.h>\nint main(){printf(\"%d\\n\", 6*7);return 0;}\n"), wrote)
    Unit <- File.close(f2)
    row("write", "ok")
    Unit <- run("cc", "cc", ["-O1", String.concat([p, ".c"]), "-o", String.concat([p, ".bin"])])
    Unit <- run("run", String.concat([p, ".bin"]), [])
    return Unit{}
