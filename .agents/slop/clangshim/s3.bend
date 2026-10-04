# STAGE 3 -- the falsifiable row. One law per control; nothing compares to a
# constant. See s3.c for why each row exists and what a disarmed lane looks like.
import Base

# clang_createIndex(excludeDeclarationsFromPCH:int, displayDiagnostics:int)
law same:
  U32 -> U32 -> IO(Nat)

def same(a, b):
  import "./s3.c"

# two live indices in ONE process; returns 1 when their addresses differ
law two_live:
  IO(Nat)

def two_live():
  import "./s3.c"

# setGlobalOptions(ix, v) then getGlobalOptions(ix), inside one foreign call
law trip:
  Nat -> IO(Nat)

def trip(v):
  import "./s3.c"

# clang_getClangVersion() -> const char* : the one marshalling path the census
# could not fold into a word
law cver:
  IO(String)

def cver():
  import "./s3.c"

def main() -> IO(Unit):
  do IO<Unit>:
    h : Nat <- same(0, 0)
    IO.print("BEND_HANDLE " ++ Nat.show(h))
    d : Nat <- two_live()
    IO.print("TWO_LIVE_DIFFER " ++ Nat.show(d))
    t0 : Nat <- trip(0n)
    IO.print("PLANT_0 " ++ Nat.show(t0))
    t5 : Nat <- trip(5n)
    IO.print("PLANT_5 " ++ Nat.show(t5))
    t5b : Nat <- trip(5n)
    IO.print("DISARM_5_AGAIN " ++ Nat.show(t5b))
    t7 : Nat <- trip(7n)
    IO.print("PLANT_7 " ++ Nat.show(t7))
    s : String <- cver()
    IO.print("BEND_CVER " ++ s)