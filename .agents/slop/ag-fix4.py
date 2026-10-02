p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
reps = [
 ("""def typehint_ints() -> List<&2, TH>:
  match ints():
    case Nil{}: Nil{}
    case k <> rest: List.append(&2, TH, [TH{k, "int"}], typehint_ints(rest))""",
  """def typehint_ints(xs: List<&2, U32>) -> List<&2, TH>:
  match xs:
    case Nil{}: Nil{}
    case k <> rest: List.append(&2, TH, [TH{k, "int"}], typehint_ints(rest))"""),
 ("""def typehint_table() -> List<&2, TH>:
  List.append(&2, TH, List.append(&2, TH, typehint_ints(), typehint_floats()), typehint_tail())""",
  """def typehint_table() -> List<&2, TH>:
  List.append(&2, TH, List.append(&2, TH, typehint_ints(ints()), typehint_floats()), typehint_tail())"""),
 ("""def ints_tail_of(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case x <> rest: List.append(&2, U32, [x], ints_tail_of(rest))

""", ""),
 ("""def gtn_names(xs: List<&2, Gt>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Gt{nm, tnm, defd, ln} <> rest: List.append(&2, String, [nm], gtn_names(rest))""",
  """def gtn_names(xs: List<&2, Gt>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Gt{nm, tnm, defd, ln} <> rest: List.append(&2, String, [nm], gtn_names(rest))

# the wall note's `types` lookups, kept as defs because the wall is about how
# they COMBINE, not about whether they are expressible."""),
]
for a, b in reps:
    assert a in s, a[:60]
    s = s.replace(a, b)
open(p, "w").write(s)
print("ok")
