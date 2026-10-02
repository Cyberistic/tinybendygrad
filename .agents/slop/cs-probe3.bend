import Base

def Fp.srow(nm: String, r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{(c, m)}: String.concat([nm, "_FAIL code=", U32.show(c)])
    case Done{v}: String.concat([nm, "=[", v, "]"])

def Fp.urow(nm: String, r: Result<&1, &1, U32 & String, Unit>) -> String:
  match r:
    case Fail{(c, m)}: String.concat([nm, "_FAIL code=", U32.show(c)])
    case Done{v}: String.concat([nm, "_OK"])

def Fp.write(path: String, data: String) -> IO(String):
  IO.bind(File & Result<&1, &1, U32 & String, Unit>, String, IO.bind(File, File & Result<&1, &1, U32 & String, Unit>, IO.try(File, File.open(path, "w")), f => File.write(f, data)), pr => IO.pure(String, Fp.urow("wr", Pair.snd(File, Result<&1, &1, U32 & String, Unit>, pr))))

def Fp.read(path: String) -> IO(String):
  IO.bind(File & Result<&1, &1, U32 & String, String>, String, IO.bind(File, File & Result<&1, &1, U32 & String, String>, IO.try(File, File.open(path, "r")), f => File.read(f, 4096)), pr => IO.pure(String, Fp.srow("rd", Pair.snd(File, Result<&1, &1, U32 & String, String>, pr))))

def main() -> IO(Unit):
  do IO<Unit>:
    w : String <- Fp.write(".agents/slop/probe-tmp.txt", "HELLO-WORLD")
    IO.print(w)
    r : String <- Fp.read(".agents/slop/probe-tmp.txt")
    IO.print(r)
    IO.print("probe3-done=1")
