# serve_routerdrv.bend -- GENERATED differential driver for tinybendygrad/llm/serve.bend.
#
# Replays fixed piece sequences through `Router.route` and prints every delta in order, then the final
# (mode, buf). THE INPUTS CONTAIN NO NEWLINES, so a line-based diff is a byte comparison of the deltas.
#
# The port is PURE, so the driver owns the threading: `Acc` carries the `Router` and the deltas, and every
# computed pair is consumed by a def whose PARAMETER is the pair -- the idiom this tree uses everywhere,
# because `match` cannot scrutinize a computed value.
import Base
import ../../../tinybendygrad/llm/serve.bend as C

type Acc is Data:
  Acc{r: C.Router, ds: List<&2, C.Delta>}

def into2(av: C.Router & List<&2, C.Delta>, +ds: List<&2, C.Delta>) -> Acc:
  match av:
    case (r, d2): Acc{r, List.concat(&2, C.Delta, [ds, d2])}

def into(+piece: String, +final: Bool, a: Acc) -> Acc:
  match a:
    case Acc{r, ds}: into2(C.Router.route(r, piece, final), ds)

#: `final` is True only for the LAST piece, so the flag is decided from the tail here rather than in a
#: second def -- `run` and `run.last` would call each other, and Bend refuses mutual recursion.
def into.at(+h: String, +t: List<&2, String>, acc: Acc) -> Acc:
  match t:
    case Nil{}: into(h, True{}, acc)
    case _: into(h, False{}, acc)

def run(+pieces: List<&2, String>, acc: Acc) -> Acc:
  match pieces:
    case Nil{}: acc
    case h <> t: run(t, into.at(h, t, acc))

def field_name(+f: U32) -> String:
  Bool.pick(String, U32.is_eq(f, C.Delta.reasoning()), "R", "C")

def mode_name(+m: U32) -> String:
  Bool.pick(String, U32.is_eq(m, C.Router.undecided()), "undecided",
    Bool.pick(String, U32.is_eq(m, C.Router.reasoning()), "reasoning",
      Bool.pick(String, U32.is_eq(m, C.Router.content()), "content", "tool")))

#: one recursion prints the deltas and then the `/final` row, so the empty case still has an effect --
#: `IO.pure` is not a no-op here (MEASURED: it wants a continuation, "expected : ... -> IO.OP<R>").
def print_ds(+name: String, +ds: List<&2, C.Delta>, +r: C.Router) -> IO(Unit):
  match ds:
    case Nil{}:
      IO.print(String.concat([name, "/final\t", mode_name(C.Router.mode(r)), "\t", C.Router.buf(r)]))
    case h <> t:
      match h:
        case C.Delta{f, text}:
          IO.bind(Unit, Unit, IO.print(String.concat([name, "/", field_name(f), "\t", text])),
            x => print_ds(name, t, r))

def print_ds.at(a: Acc, +name: String) -> IO(Unit):
  match a:
    case Acc{+r, ds}: print_ds(name, ds, r)

def go(+name: String, +r: C.Router, +pieces: List<&2, String>) -> IO(Unit):
  print_ds.at(run(pieces, Acc{r, Nil{}}), name)

def main() -> IO(Unit):
  do IO<Unit>:
    go("reason", C.Router.of(True{}), ["<thin", "k>rea", "soning</thi", "nk>hel", "lo"])
    go("plain", C.Router.of(False{}), ["he", "llo"])
    go("tool", C.Router.of(False{}), ["hi<tool_call>{\"a\":1}"])
    go("nothnk", C.Router.of(True{}), ["no think here"])
    go("hold", C.Router.of(False{}), ["x<tool_c"])
    go("empty", C.Router.of(True{}), ["", ""])
