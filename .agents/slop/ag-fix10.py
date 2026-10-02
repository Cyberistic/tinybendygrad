p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
a = s.index("# autogen.py:113 the suggested name")
b = s.index("# ===========================================================================\n# SECTION 13 --")
new = '''# autogen.py:113 the suggested name for an ELABORATED type, and :128/:142 the
# `::`-to-`_` and space-to-`_` rewrites that make a C++ name a Python
# identifier. BOTH are `str.replace`, and `String.replace` DOES NOT EXIST in
# bend 2.0.34 -- there is no such def in `references/bend/bend2/base.bend` and
# no intrinsic backs it. That is WALL 2's second mouth.
#
# A general substring replace wants "either consume 1 or consume len(pattern)",
# i.e. TWO recursive calls in one arm, and bend refuses that (measured: the
# second is rejected with "a decreasing self-call"). A left-to-right greedy
# replace is therefore written as a fixed stride with a PENDING state in the
# accumulator: one char in, zero or one out, one recursive call. The
# accumulator is a `Data` so it can carry the flag and the output together, and
# it goes SECOND because bend's descent rule wants the shrinking argument
# first.
def colon() -> Char: ':'

type RS is Data: RS{pend: Bool, cs: List<&2, Char>}

# the four cases of "a colon arrived while a colon was pending"
def rep_emit2(pend: Bool, c1: Char) -> List<&2, Char>:
  Bool.pick(List<&2, Char>, Char.is_eq(c1, colon()),
    Bool.pick(List<&2, Char>, pend, ["_"], Nil{}),
    Bool.pick(List<&2, Char>, pend, [colon(), c1], [c1]))

def rep_pend2(pend: Bool, c1: Char) -> Bool:
  Bool.pick(Bool, Char.is_eq(c1, colon()), Bool.not(pend), False{})

def rep_step2(c1: Char, acc: RS) -> RS:
  match acc:
    case RS{pend, cs}: RS{rep_pend2(pend, c1), List.append(&2, Char, cs, rep_emit2(pend, c1))}

# a lone trailing ':' SURVIVES, because Python's replace only fires on a pair
def rep_flush2(acc: RS) -> List<&2, Char>:
  match acc:
    case RS{pend, cs}: Bool.pick(List<&2, Char>, pend, List.append(&2, Char, cs, [colon()]), cs)

def rep_go2(cs: List<&2, Char>, acc: RS) -> List<&2, Char>:
  match cs:
    case Nil{}: List.reverse(rep_flush2(acc))
    case c1 <> rest: rep_go2(rest, rep_step2(c1, acc))

# the one-character form needs no pending state: a fixed stride of one
def rep_emit1(c1: Char) -> List<&2, Char>:
  Bool.pick(List<&2, Char>, Char.is_eq(c1, space()), ["_"], [c1])

def rep_go1(cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: List.reverse(acc)
    case c1 <> rest: rep_go1(rest, List.append(&2, Char, acc, rep_emit1(c1)))

def space() -> Char: ' '

def colons_to_underscores(n: String) -> String:
  String.from_list(rep_go2(String.to_list(n), RS{False{}, Nil{}}))

def spaces_to_underscores(n: String) -> String:
  String.from_list(rep_go1(String.to_list(n), Nil{}))

# autogen.py:142 `real_nm.replace(' ', '_').replace('::', '_')` -- the SPACE
# rewrite runs FIRST and the `::` rewrite second. On `a::b` the order is
# invisible; on a name with both it is not, so this is `rep_go1` then `rep_go2`
# and not the other way round.
def record_nm(n: String) -> String: colons_to_underscores(spaces_to_underscores(n))

'''
s = s[:a] + new + s[b:]
open(p, "w").write(s)
print("ok")
