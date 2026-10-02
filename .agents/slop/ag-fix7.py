p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
reps = [
 ("""def te_cty(m: Maybe<&2, TE>) -> String:
  match m:
    case Some{cty}: cty
    case None{}: \"\"""",
  """def te_cty_of(t: TE) -> String:
  match t:
    case TE{kind, cty}: cty

def te_cty(m: Maybe<&2, TE>) -> String:
  match m:
    case Some{value}: te_cty_of(value)
    case None{}: \"\""""),
 ("""def th_hint(m: Maybe<&2, TH>) -> String:
  match m:
    case Some{hint}: hint
    case None{}: \"\"""",
  """def th_hint_of(t: TH) -> String:
  match t:
    case TH{kind, hint}: hint

def th_hint(m: Maybe<&2, TH>) -> String:
  match m:
    case Some{value}: th_hint_of(value)
    case None{}: \"\""""),
 ("""def gtn_tnm(m: Maybe<&2, Gt>) -> String:
  match m:
    case Some{tnm}: tnm
    case None{}: "?"

def gtn_defd(m: Maybe<&2, Gt>) -> Bool:
  match m:
    case Some{defd}: defd
    case None{}: False{}

def gtn_ln(m: Maybe<&2, Gt>) -> Nat:
  match m:
    case Some{ln}: ln
    case None{}: 0n""",
  """def gtn_tnm(m: Maybe<&2, Gt>) -> String:
  match m:
    case Some{value}: gtn_nm_tnm(value)
    case None{}: "?"

def gtn_nm_tnm(g: Gt) -> String:
  match g:
    case Gt{nm, tnm, defd, ln}: tnm

def gtn_defd(m: Maybe<&2, Gt>) -> Bool:
  match m:
    case Some{value}: gtn_g_defd(value)
    case None{}: False{}

def gtn_g_defd(g: Gt) -> Bool:
  match g:
    case Gt{nm, tnm, defd, ln}: defd

def gtn_ln(m: Maybe<&2, Gt>) -> Nat:
  match m:
    case Some{value}: gtn_g_ln(value)
    case None{}: 0n

def gtn_g_ln(g: Gt) -> Nat:
  match g:
    case Gt{nm, tnm, defd, ln}: ln"""),
 ("""def anon_name(g: G, tag: String) -> String:
  String.concat(["_anon", tag, Nat.show(g.anon)])""",
  """def anon_name(g: G, tag: String) -> String:
  String.concat(["_anon", tag, Nat.show(g_ctr(g))])

def g_ctr(g: G) -> Nat:
  match g:
    case G{lines, typs, anon, objc}: anon"""),
]
for a, b in reps:
    assert a in s, a[:70]
    s = s.replace(a, b)
open(p, "w").write(s)
print("ok")
