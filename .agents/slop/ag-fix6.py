p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
reps = [
 ("def te_at(k: U32, xs: List<&2, TE>)", "def te_at(+k: U32, xs: List<&2, TE>)"),
 ("def th_at(k: U32, xs: List<&2, TH>)", "def th_at(+k: U32, xs: List<&2, TH>)"),
 ("def str_in(k: String, xs: List<&2, String>)", "def str_in(+k: String, xs: List<&2, String>)"),
 ("    case s <> rest: List.find.put(String, True{}, str_in(k, rest), String.eq(s, k))",
  "    case +s <> rest: List.find.put(String, True{}, str_in(k, rest), String.eq(s, k))"),
 ("def u32_in(k: U32, xs: List<&2, U32>)", "def u32_in(+k: U32, xs: List<&2, U32>)"),
 ("def attrs_mem(k: U32, xs: List<&2, U32>)", "def attrs_mem(+k: U32, xs: List<&2, U32>)"),
 ("def gtn_find(n: String, xs: List<&2, Gt>)", "def gtn_find(+n: String, xs: List<&2, Gt>)"),
 ("def gtn_del(n: String, xs: List<&2, Gt>)", "def gtn_del(+n: String, xs: List<&2, Gt>)"),
 ("def rows_br(i: Nat, xs: List<&2, BR>)", "def rows_br(+i: Nat, xs: List<&2, BR>)"),
 ("def gtn_set(n: String, tnm: String, defd: Bool, ln: Nat, xs: List<&2, Gt>)",
  "def gtn_set(n: String, tnm: String, defd: Bool, ln: Nat, xs: List<&2, Gt>)"),
 ("def gtn_is_reserved(n: String) -> Bool", "def gtn_is_reserved(n: String) -> Bool"),
]
for a, b in reps:
    assert a in s, a[:60]
    s = s.replace(a, b)
open(p, "w").write(s)
print("ok")
