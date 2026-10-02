# PROBE: does bend 2.0.34 reach an external process?  MEASURED, not read.
import Base

def Pr.row(nm: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Fail{(c, m)}: String.concat([nm, "_FAIL code=", U32.show(c), " msg_empty=", U32.show(Bool.to_u32(String.is_empty(m)))])
    case Done{(code, (out, err))}: String.concat([nm, "_DONE code=", U32.show(code), " out=[", out, "] err=[", err, "]"])

def main() -> IO(Unit):
  do IO<Unit>:
    r1 : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/echo", ["hello", "world"], "", 65536, 5000)
    r2 : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh", ["-c", "cat"], "PIPED", 65536, 5000)
    r3 : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/nonexistent-tool-xyz", [], "", 65536, 5000)
    r4 : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh", ["-c", "exit 3"], "", 65536, 5000)
    r5 : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("true", [], "", 65536, 5000)
    r6 : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh", ["-c", "printf out; printf err >&2"], "", 65536, 5000)
    r7 : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh", ["-c", "exit 42"], "", 65536, 5000)
    r8 : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/cat", ["-"], "", 65536, 5000)
    IO.print(Pr.row("p1_echo", r1))
    IO.print(Pr.row("p2_stdin", r2))
    IO.print(Pr.row("p3_missing", r3))
    IO.print(Pr.row("p4_exit3", r4))
    IO.print(Pr.row("p5_pathlookup", r5))
    IO.print(Pr.row("p6_split", r6))
    IO.print(Pr.row("p7_exit42", r7))
    IO.print(Pr.row("p8_empty_input", r8))
    a : List<&1, String> <- IO.args()
    IO.print(String.concat(["p9_nargs=", Nat.show(List.length(&1, String, a))]))
    IO.print("probe-done=1")