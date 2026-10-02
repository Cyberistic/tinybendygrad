import Base

def main() -> IO(Unit):
  do IO<Unit>:
    f : File <- File.open(".agents/slop/probe-tmp.txt", "w")
    u : Unit <- File.write(f, "HELLO-WORLD")
    g : Unit <- File.close(f)
    h : File <- File.open(".agents/slop/probe-tmp.txt", "r")
    s : String <- File.read(h, 64)
    n : Nat <- File.size(h)
    k : Unit <- File.close(h)
    IO.print(String.concat(["p6_file=[", s, "] size=", Nat.show(n)]))
    IO.print("probe2-done=1")
