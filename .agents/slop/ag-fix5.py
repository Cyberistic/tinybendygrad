import re
p = "tinybendygrad/runtime/support/autogen.bend"
s = open(p).read()
# A binder read twice needs `+`. Four walkers use their row binder twice.
for T, f in (("TE", "kind"), ("TH", "kind")):
    s = s.replace(f"case {T}{{{f}, ", f"case {T}{{+{f}, ")
s = s.replace("case BR{pat, rep} <> rest:\n      List.find.put", "case BR{+pat, +rep} <> rest:\n      List.find.put")
s = s.replace("case BR{+pat, +rep} <> rest:\n      List.append", "case BR{+pat, +rep} <> rest:\n      List.append")
# the row-printing walks read every field exactly once, so `+` is not needed
# there -- but rows_br reads pat and rep twice.
open(p, "w").write(s)
print("ok")
