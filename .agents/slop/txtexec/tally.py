import os
from collections import Counter
c = Counter()
resid = []
for dp, _, fns in os.walk("oracles"):
    for f in fns:
        ext = os.path.splitext(f)[1]
        c[ext] += 1
        if ext == ".txt":
            resid.append(os.path.join(dp, f))
print("ext tally under oracles/ after rename:")
for e, n in sorted(c.items()):
    print(f"  {e or '(none)':10s} {n}")
print("total files:", sum(c.values()))
print("residual .txt:", resid)
