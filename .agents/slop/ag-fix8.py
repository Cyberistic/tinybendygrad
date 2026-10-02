p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
a = s.index("def anon_name(g: G, tag: String) -> String:")
b = s.index("# autogen.py:113 the suggested name")
s = s[:a] + '''def anon_name(g: G, tag: String) -> String:
  match g:
    case G{lines, typs, anon, objc}: String.concat(["_anon", tag, Nat.show(anon)])

''' + s[b:]
open(p, "w").write(s)
print("ok")
