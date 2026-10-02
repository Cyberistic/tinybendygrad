p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
a = s.index("# autogen.py:117 `nm(t) in types and")
b = s.index("# ===========================================================================\n# SECTION 15 --")
new = '''# autogen.py:117 `nm(t) in types and types[nm(t)][1]`, :135 the same for a
# Record after `re.sub("^const ", "")`, and :211 the same for an ObjC protocol.
# All three are the same three questions about the same dict, so they are three
# readers over one `Data`.
def gtn_tnm_of(g: Gt) -> String:
  match g:
    case Gt{nm, tnm, defd, ln}: tnm

def gtn_defd_of(g: Gt) -> Bool:
  match g:
    case Gt{nm, tnm, defd, ln}: defd

def gtn_ln_of(g: Gt) -> Nat:
  match g:
    case Gt{nm, tnm, defd, ln}: ln

def gtn_tnm(m: Maybe<&2, Gt>) -> String:
  match m:
    case Some{value}: gtn_tnm_of(value)
    case None{}: "?"

def gtn_defd(m: Maybe<&2, Gt>) -> Bool:
  match m:
    case Some{value}: gtn_defd_of(value)
    case None{}: False{}

def gtn_ln(m: Maybe<&2, Gt>) -> Nat:
  match m:
    case Some{value}: gtn_ln_of(value)
    case None{}: 0n

def gtn_find(+n: String, xs: List<&2, Gt>) -> Maybe<&2, Gt>:
  match xs:
    case Nil{}: None{}
    case Gt{+nm, tnm, defd, ln} <> rest: List.find.put(Gt, Gt{nm, tnm, defd, ln}, gtn_find(n, rest), String.eq(nm, n))

def gtn_names(xs: List<&2, Gt>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Gt{nm, tnm, defd, ln} <> rest: List.append(&2, String, [nm], gtn_names(rest))

def gtn_del(+n: String, xs: List<&2, Gt>) -> List<&2, Gt>:
  match xs:
    case Nil{}: Nil{}
    case Gt{+nm, tnm, defd, ln} <> rest: List.filter.put(Gt, Gt{nm, tnm, defd, ln}, gtn_del(n, rest), Bool.not(String.eq(nm, n)))

def gtn_put(e: Gt, xs: List<&2, Gt>) -> List<&2, Gt>: List.append(&2, Gt, xs, [e])

def gtn_set(n: String, tnm: String, defd: Bool, ln: Nat, xs: List<&2, Gt>) -> List<&2, Gt>:
  gtn_put(Gt{n, tnm, defd, ln}, gtn_del(n, xs))

# autogen.py:128 `types[nm(t)] = cnm if nm(t).startswith("__") else
# nm(t).replace('::', '_')` -- an implementation-reserved name KEEPS the
# canonical spelling, and `String.starts_with` is the whole of that test.
def gtn_is_reserved(n: String) -> Bool: String.starts_with(n, "__")

'''
s = s[:a] + new + s[b:]
open(p, "w").write(s)
print("ok")
