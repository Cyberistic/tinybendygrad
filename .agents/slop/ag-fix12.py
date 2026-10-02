p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
old = '''def rows_br(+i: Nat, xs: List<&2, BR>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case BR{+pat, +rep} <> rest:
      List.append(&2, String, ["rule " ++ Nat.show(i) ++ " : " ++ pat ++ " => " ++ rep], rows_br((i.pred + 1n : Nat), rest))'''
new = '''# The rule INDEX counts UP while the list counts DOWN, and bend's descent rule
# wants each argument passed UNCHANGED until one shrinks -- so an up-counter
# threaded as a parameter is refused. The counter therefore rides in the
# accumulator, which is the shape `rep_go2` already uses for the same reason.
type BI is Data: BI{i: Nat, rows: List<&2, String>}

def br_row(i: Nat, pat: String, rep: String) -> String:
  String.concat(["rule ", Nat.show(i), " : ", pat, " => ", rep])

def bi_rows(acc: BI) -> List<&2, String>:
  match acc:
    case BI{+i, rows}: rows

def bi_step(pat: String, rep: String, acc: BI) -> BI:
  match acc:
    case BI{+i, +rows}: BI{i.pred + 1n, List.append(&2, String, rows, [br_row(i, pat, rep)])}

def rows_br_go(xs: List<&2, BR>, acc: BI) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, bi_rows(acc))
    case BR{+pat, +rep} <> rest: rows_br_go(rest, bi_step(pat, rep, acc))

def rows_br(xs: List<&2, BR>) -> List<&2, String>: rows_br_go(xs, BI{0n, Nil{}})'''
assert old in s
s = s.replace(old, new)
s = s.replace('rows_br(0n, base_rules())', 'rows_br(base_rules())')
open(p, "w").write(s)
print("ok")
