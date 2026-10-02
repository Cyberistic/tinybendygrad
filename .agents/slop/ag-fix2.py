p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
a = s.index("def te_hit(")
b = s.index("def br_pat(")
new = '''# `Some` has ONE field, so a `Some{kind, cty}` pattern is refused; the Bool
# comes out of the `te_cty` string instead. That is FAITHFUL for `typehint`,
# because Python's guard is `if v:` on a `str | None`, and `None` and `""` are
# both falsy there -- the two spellings agree on every kind libclang has.
def te_hit(k: U32, xs: List<&2, TE>) -> Bool:
  Bool.not(String.eq(te_cty(te_at(k, xs)), ""))

def th_hint(m: Maybe<&2, TH>) -> String:
  match m:
    case Some{hint}: hint
    case None{}: ""

def th_hit(k: U32, xs: List<&2, TH>) -> Bool:
  Bool.not(String.eq(th_hint(th_at(k, xs)), ""))

'''
s = s[:a] + new + s[b:]
open(p, "w").write(s)
print("ok")
