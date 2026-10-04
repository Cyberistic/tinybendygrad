import Base

def slurp(path: String) -> IO(String):
  do IO<String>:
    f <- File.open(path, "r")
    IO.bind(Result<&1, &1, U32 & String, File>, String, f, IO.pass(String, _ => {
      r <- File.read(File.unwrap(f), 4096)
      IO.bind(File & Result<&1, &1, U32 & String, String>, String, r, IO.pass(String, IO.drop))
    }))
