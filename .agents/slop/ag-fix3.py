p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()

# 1. tmap_rev must take the list as a PARAMETER: a match cannot scrutinise a call.
a = s.index("# the reverse direction, kind-for-value.")
b = s.index("# ===========================================================================\n# SECTION 4 --")
s = s[:a] + '''# the reverse direction, kind-for-value. It walks the list Python's tmap was
# built from rather than re-deriving it, so a wrong constant shows up as the
# wrong kind -- which is the whole reason for keeping both directions.
def tmap_rev(xs: List<&2, TE>) -> List<&2, TE>:
  match xs:
    case Nil{}: Nil{}
    case TE{kind, cty} <> rest: List.append(&2, TE, [TE{kind, cty}], tmap_rev(rest))

''' + s[b:]
s = s.replace("tmap_rev_tl(rest)", "tmap_rev(rest)")

# 2. drop the mutually-recursive tname skeleton: WALL 4 replaces it.
a = s.index("def tname(t: Ty, g: G) -> R:")
b = s.index("# ===========================================================================\n# SECTION 14 --")
s = s[:a] + s[b:]

# 3. `G` is used by `anon_name` in the gate, so the type must precede it; and
#    the `R`/`Gt` types are only needed by the wall note, which is prose.
s = s.replace('''# the answer of one `tname`: the name, and the state it left behind.
type R is Data: R{name: String, g: G}

''', '')
open(p, "w").write(s)
print("ok")
