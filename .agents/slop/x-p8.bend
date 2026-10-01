import Base

type St is Data:
  Head{acc: List<&2, Char>}
  Keep{acc: List<&2, Char>}

def St.acc(s: St) -> List<&2, Char>:
  match s:
    case Head{acc}: acc
    case Keep{acc}: acc

def drop.head(c: Char, acc: List<&2, Char>) -> St:
  match c:
    case '.': Head{acc}
    case _: Keep{List.append(&2, Char, acc, [c])}

def drop.st(c: Char, s: St) -> St:
  match s:
    case Head{acc}: drop.head(c, acc)
    case Keep{acc}: Keep{List.append(&2, Char, acc, [c])}

def drop(cs: List<&2, Char>, s: St) -> List<&2, Char>:
  match cs:
    case Nil{}: St.acc(s)
    case c <> t: drop(t, drop.st(c, s))

def rev(cs: List<&2, Char>) -> List<&2, Char>:
  List.reverse(&2, Char, cs)

def ldrop(cs: List<&2, Char>) -> List<&2, Char>:
  drop(cs, Head{Nil{}})

def strip(s: String) -> String:
  String.from_list(rev(ldrop(rev(ldrop(String.to_list(s))))))

def show(nm: String, s: String) -> IO(Unit):
  IO.print(String.concat([nm, "=[", s, "]"]))

def main() -> IO(Unit):
  do IO<Unit>:
    show("empty", strip(""))
    show("dot", strip("."))
    show("twodot", strip(".."))
    show("adot", strip(".a."))
    show("inner", strip("a..b.."))
    show("a", strip("a"))
    show("wdot", strip("w."))
    show("nest", strip("layers.0.weight."))
    show("all", strip("..."))
    show("mid", strip("a.b."))
