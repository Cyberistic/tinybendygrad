p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
old_start = s.index("def te_some(")
marker = "def str_in(k: String, xs: List<&2, String>) -> Bool: str_at2(k, xs, 4096n)"
old_end = s.index(marker) + len(marker)
new = '''# ===========================================================================
# SECTION 2 -- list plumbing.
#
# MEASURED, bend 2.0.34, and it shapes every walk below: an `if` scrutinee and
# a `match` scrutinee must both be a NAME -- a parameter or a pattern binder.
# `if U32.is_eq(kind, k):` is a PARSE error ("expected '=' observed ':'"), and
# `match at(k, xs):` is a TYPE error ("a match cannot scrutinize a computed
# value: give it its own def"). So a computed Bool reaches a branch through
# `List.find.put`, which takes the Bool as an ARGUMENT -- and that is what it
# is for. Reads out of a `Maybe` get their own def for the same reason.
#
# The walks recurse STRUCTURALLY on the list tail and need no Nat fuel: the
# list is the descending argument and it shrinks.
# ===========================================================================

# `List.find.put(h, r, hit)` -- the language's own answer to "a computed Bool
# guard". It returns `h` when `hit`, else `r`, and it is not a closure, so the
# recursion argument is written out where a `Bool.pick` would have hidden it.
def te_at(k: U32, xs: List<&2, TE>) -> Maybe<&2, TE>:
  match xs:
    case Nil{}: None{}
    case TE{kind, cty} <> rest: List.find.put(TE, TE{kind, cty}, te_at(k, rest), U32.is_eq(kind, k))

def th_at(k: U32, xs: List<&2, TH>) -> Maybe<&2, TH>:
  match xs:
    case Nil{}: None{}
    case TH{kind, hint} <> rest: List.find.put(TH, TH{kind, hint}, th_at(k, rest), U32.is_eq(kind, k))

def br_at(i: Nat, xs: List<&2, BR>) -> Maybe<&2, BR>:
  match xs:
    case Nil{}: None{}
    case BR{pat, rep} <> rest:
      List.find.put(BR, BR{pat, rep}, br_at(Nat.sub(i, 1n), rest), Nat.is_eq(i, 0n))

def str_in(k: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case s <> rest: List.find.put(String, True{}, str_in(k, rest), String.eq(s, k))

# reads out of a Maybe, each in its own def because the scrutinee must be a
# name. `""` is the miss marker and no table cell is the empty string.
def te_cty(m: Maybe<&2, TE>) -> String:
  match m:
    case Some{cty}: cty
    case None{}: ""

def te_hit(m: Maybe<&2, TE>) -> Bool:
  match m:
    case Some{kind, cty}: Bool.and(Bool.not(String.eq(cty, "")), U32.is_ne(kind, 0))
    case None{}: False{}

def th_hint(m: Maybe<&2, TH>) -> String:
  match m:
    case Some{hint}: hint
    case None{}: ""

def th_hit(m: Maybe<&2, TH>) -> Bool:
  match m:
    case Some{kind, hint}: Bool.and(Bool.not(String.eq(hint, "")), U32.is_ne(kind, 0))
    case None{}: False{}

def br_pat(m: Maybe<&2, BR>) -> String:
  match m:
    case Some{pat}: pat
    case None{}: ""'''
s = s[:old_start] + new + s[old_end:]
open(p, "w").write(s)
print("ok")
