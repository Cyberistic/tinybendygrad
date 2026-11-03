# serve_frame.bend -- the live renderer fed by a length-prefixed frame on the pipe.
# Shipped protocol: file + 1-byte signal. Measured difference: 0.96 ms of a 5.88 ms turn (§79.2).
# The language shapes are forced; each refusal is recorded in PARITY §83.
import Base
import ./../../../tinybendygrad/renderer/live.bend as L
import ./../../../tinybendygrad/renderer/cstyle.bend as C

type St is Data:
  SRead{mode: Nat, acc: String, need: Nat, chunks: List<&2, String>}
  SEmit{chunks: List<&2, String>}
  SBad{}

# **DECODED ONE CHUNK AT A TIME, BECAUSE ONE `String.split` OVER 28 KB OVERFLOWS THIS RUNTIME'S STACK.**
# MEASURED (`PARITY.md` §84.3): a 1,215-uop kernel killed the daemon and the caller fell back for the rest
# of the session. `L.kus` is the renderer's own decode, so the daemon now splits exactly what the one-shot
# path splits, and the frame says where the chunks end with a ZERO-LENGTH chunk.
def decode.go(+cs: List<&2, String>, +acc: List<&2, C.KU>) -> List<&2, C.KU>:
  match cs:
    case Nil{}: acc
    case h <> t: decode.go(t, List.append(&2, C.KU, acc, L.kus(h)))

def decode(+cs: List<&2, String>) -> List<&2, C.KU>: decode.go(cs, Nil{})

def begun() -> String: "@@BEGIN"
def ended() -> String: "@@END"

def is_nl(text: String) -> Bool: String.eq(text, "\n")

def parse_len(+s: String) -> Nat: U32.to_nat(Maybe.default(&2, U32, U32.read(s), 0))

def read_pay(need: Nat, +acc: String) -> U32:
  U32.from_nat(Nat.max(1n, Nat.sub(need, String.length(acc))))

def st_len.x(+acc: String, +text: String, +chunks: List<&2, String>) -> St:
  Bool.pick(St, is_nl(text),
    Bool.pick(St, Nat.is_eq(parse_len(acc), 0n), SEmit{chunks}, SRead{1n, "", parse_len(acc), chunks}),
    SRead{0n, String.concat([acc, text]), 0n, chunks})

def st_len(r: Result<&1, &1, U32 & String, String>, +acc: String, +chunks: List<&2, String>) -> St:
  match r:
    case Fail{error}: SBad{}
    case Done{text}: st_len.x(acc, text, chunks)

def st_pay.x(+acc: String, +text: String, +need: Nat, +chunks: List<&2, String>) -> St:
  +both = String.concat([acc, text])
  Bool.pick(St, Nat.is_le(need, String.length(both)), SRead{0n, "", 0n, List.append(&2, String, chunks, [both])},
    SRead{1n, both, need, chunks})

def st_pay(r: Result<&1, &1, U32 & String, String>, +acc: String, +need: Nat, +chunks: List<&2, String>) -> St:
  match r:
    case Fail{error}: SBad{}
    case Done{text}: st_pay.x(acc, text, need, chunks)

def st_of(mode: Nat, r: Result<&1, &1, U32 & String, String>, +acc: String, +need: Nat, +chunks: List<&2, String>) -> St:
  match mode:
    case 0n: st_len(r, acc, chunks)
    case _: st_pay(r, acc, need, chunks)

def sz_of(s: St) -> U32:
  match s:
    case SRead{mode, acc, need, chunks}: Bool.pick(U32, Nat.is_eq(mode, 0n), 1, read_pay(need, acc))
# THE EMIT STATE ASKS FOR NOTHING. MEASURED: a read of 0 bytes returns immediately, and a read of 1
# byte here BLOCKS on the next frame -- which is exactly why the first version printed nothing.
    case SEmit{acc}: 0
    case SBad{}: 1

# the number the length digits parsed to, for the first frame only (scratch diagnostic)
def len_dbg(acc: String) -> Nat: parse_len(acc)

def serve(fuel: Nat, m: (File & Result<&1, &1, U32 & String, String>), s: St) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+k:
      (f, r) = m
      match s:
        case SBad{}: IO.die(Unit, 1, "serve: the fifo could not be read")
        case SRead{mode, acc, need, chunks}:
          +a = acc
          +n = need
          +cs = chunks
          +st2 = st_of(mode, r, a, n, cs)
          IO.bind((File & Result<&1, &1, U32 & String, String>), Unit, File.read(f, sz_of(st2)),
            m2 => serve(k, m2, st2))
        case SEmit{chunks}:
          +cs = chunks
          IO.bind(Unit, Unit, IO.print(begun()), _ =>
            IO.bind(Unit, Unit, IO.print(C.render(C.dev_clang(), True{}, decode(cs))), _ =>
              IO.bind(Unit, Unit, IO.print(ended()), _ =>
                IO.bind((File & Result<&1, &1, U32 & String, String>), Unit, File.read(f, 1),
                  io => serve(k, io, SRead{0n, "", 0n, Nil{}})))))

def pick(n: Nat, +xs: List<&2, String>) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, n), "")

def serve_after(r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Done{f}:
      do IO<Unit>:
        io : (File & Result<&1, &1, U32 & String, String>) <- File.read(f, 1)
        serve(1000000n, io, SRead{0n, "", 0n, Nil{}})
    case Fail{error}: IO.die(Unit, 1, "serve: fifo could not be opened")

def go(+fifo: String) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(fifo, "r"), r => serve_after(r))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    pair : String <- IO.pure(String, Maybe.default(&1, String, List.get(&1, String, as, 1n), "|"))
    go(pick(0n, String.split(pair, '|')))
