# serve.bend -- THE LIVE RENDERER AS A LONG-LIVED PROCESS, fed one kernel per signal.
#
# WHY. `renderer/live.bend` removed the per-kernel TYPECHECK but not the per-kernel PROCESS: every kernel
# still starts `bun`, which MEASURES at ~26.5 ms of start-up plus module load for a 349 KB artifact. That
# fixed cost is the largest single term per kernel (`PARITY.md` §28.4), and it is the one thing a batch
# cannot remove, because a real program asks for one kernel at a time.
#
# THE PROTOCOL, AND WHY IT IS TWO CHANNELS RATHER THAN ONE PIPE. `File.read` on a pipe returns WHATEVER IS
# AVAILABLE, so a 13 KB wire can arrive in pieces and a single read would render a truncated kernel. So the
# request travels through a REGULAR FILE (written to a temporary name and RENAMED, hence complete) and the
# PIPE CARRIES ONLY A ONE-BYTE SIGNAL -- a short read of one byte is still a whole request.
#
#   caller                            worker
#   ------                            ------
#   write req (atomic rename)
#   open fifo, write 1 byte, close    -> open fifo (blocks until a writer), read, close
#                                     read req whole
#                                     print "@@BEGIN" / <the C> / "@@END"
#   read until "@@END"                 (loop)
#
# THE LOOP IS ONE DECREASING SELF-CALL AND HAS NO SHUTDOWN ARM, for a measured reason: Bend refuses two
# defs that call each other ("expected : a filled definition"), so a `serve -> read -> branch -> serve`
# chain does not compile, and a self-call carrying a COMPUTED fuel is refused too ("expected : a decreasing
# self-call"). So the fuel is structural, and the process ends when its parent kills it -- which is what a
# caller that goes away wants anyway.
#
# **THE PIPE IS OPENED ONCE AND READ FOREVER, AND THAT IS A MEASURED FIX.** The first version opened the
# fifo, read one byte, closed it, and opened it again -- MEASURED: the FIRST request answered in 90.7 ms and
# the SECOND never did, with the worker alive and silent. The race is the close: a writer that opens while
# the previous reader is still closing PAIRS WITH THE STALE READER, so its byte goes into a pipe nobody will
# read again, and the worker's next open blocks forever waiting for a writer that has already gone. One
# persistent reader has no such window.
import Base
import ./../../../tinybendygrad/renderer/live.bend as L
import ./../../../tinybendygrad/renderer/cstyle.bend as C

def begun() -> String: "@@BEGIN"

def ended() -> String: "@@END"

# ---- reading a REGULAR file whole. ONE `File.read`, the same shape `runtime/ops_bend.bend:2055` uses for
# its packets; the channel that can arrive in pieces is the PIPE, and the pipe carries one byte.
def read_done(f: File, r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{text}: IO.bind(Unit, String, File.close(f), _ => IO.pure(String, text))
    case Fail{error}:
      IO.bind(Unit, String, File.close(f), _ => IO.die(String, 1, "serve: request could not be read"))

def read_take(m: (File & Result<&1, &1, U32 & String, String>)) -> IO(String):
  (f, r) = m
  read_done(f, r)

def read_after(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, String, File.read(f, 1073741824),
        m => read_take(m))
    case Fail{error}: IO.die(String, 1, "serve: request file could not be opened")

def read_whole(path: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, "r"),
    r => read_after(r))

# ---- the one-byte signal
def signal_done(f: File, r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{text}: IO.bind(Unit, String, File.close(f), _ => IO.pure(String, text))
    case Fail{error}: IO.die(String, 1, "serve: fifo could not be read")

def signal_take(m: (File & Result<&1, &1, U32 & String, String>)) -> IO(String):
  (f, r) = m
  signal_done(f, r)

def signal_after(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, String, File.read(f, 1),
        m => signal_take(m))
    case Fail{error}: IO.die(String, 1, "serve: fifo could not be opened")

def signal(fifo: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(fifo, "r"),
    r => signal_after(r))

# THE DECODE IS THE RENDERER'S OWN: `nlch` and `ku_all` are `live.bend`'s, so the daemon and the one-shot
# path cannot disagree about what a wire means.
def kus(+text: String) -> List<&2, C.KU>:
  List.reverse(&2, C.KU, L.ku_all(String.split(text, L.nlch()), Nil{}))

# A READ THAT RETURNS NOTHING IS NOT A REQUEST: once every writer has closed, POSIX answers EOF until a new
# writer arrives, so an empty read costs one turn of fuel and the next read blocks. The fuel is structural
# and huge, so a handful of those is nothing.
# THE PAIR COMES BACK FROM `File.read` AND ITS `File` HALF MUST SURVIVE THE TURN. A destructuring bind is a
# DEF body in this language, not a do-block statement ("expected : a pattern"), so the accessor is here and
# the recursion stays a direct self-call -- any helper that called `serve` would make the cycle mutual, which
# Bend refuses ("expected : a filled definition") -- MEASURED on this file's first three shapes.
def fst_of(m: (File & Result<&1, &1, U32 & String, String>)) -> File:
  (f, _) = m
  f

def serve(fuel: Nat, f: File, +req: String) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+g:
      do IO<Unit>:
        m : (File & Result<&1, &1, U32 & String, String>) <- File.read(f, 1)
        text : String <- read_whole(req)
        IO.print(begun())
        IO.print(C.render(C.dev_clang(), True{}, kus(text)))
        IO.print(ended())
        serve(g, fst_of(m), req)

# ONE ARGUMENT, "fifo|req", because `IO.args()` is LINEAR and a list read twice is refused.
def pick(n: Nat, +xs: List<&2, String>) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, n), "")

def serve_after(r: Result<&1, &1, U32 & String, File>, +req: String) -> IO(Unit):
  match r:
    case Done{f}: serve(1000000n, f, req)
    case Fail{error}: IO.die(Unit, 1, "serve: fifo could not be opened")

def serve_open(+fifo: String, +req: String) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(fifo, "r"),
    r => serve_after(r, req))

# `+pair` LETS ONE STRING BE SPLIT TWICE. A `List` split once and read twice is refused ("consumed more
# than once") even when the callee takes it `+`, because the CALLER would be consuming the same variable
# twice; the string is the thing that may be used many times, so the split happens per use.
def go(+pair: String) -> IO(Unit):
  serve_open(pick(0n, String.split(pair, '|')), pick(1n, String.split(pair, '|')))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    pair : String <- IO.pure(String, Maybe.default(&1, String, List.get(&1, String, as, 1n), "|"))
    go(pair)
