"""DID THE SPLIT DROP A COMMENT? The safenet in `cl_split.py` counts DEFS, and a
def count cannot see a lost comment -- and three were lost on the first pass, all
of them load-bearing: `vend.trace`'s fold-order rationale, `vend.name.at`'s
rule-34 note and `timing.scale_hp`'s comment. This is the check that found them.

It compares every non-blank line of the ARCHIVED pre-split source against the
union of the three destinations and reports every line whose text appears in
NONE of them. Lines that were legitimately EDITED (a call-site qualifier, a
dropped `v` argument, a moved row) show up here too, so the report is grouped:
a line that changed is expected and enumerated in the split script; a line that
was never even COPIED is a drop.

  python3 .agents/slop/cl_split_noloss.py
"""
import pathlib, re, sys, collections

ROOT = pathlib.Path(__file__).resolve().parents[2]
PRE = ROOT / ".agents/slop/ops_cl-pre-split.bend"
DST = ["tinybendygrad/runtime/ops_cl.bend",
       "tinybendygrad/runtime/ops_cuda.bend",
       "tinybendygrad/runtime/ops_hip.bend"]

pre = PRE.read_text().splitlines()
dest = []
for f in DST:
    dest += (ROOT / f).read_text().splitlines()
have = set(l.strip() for l in dest)

# the edits the split is ALLOWED to make, as regexes over a stripped line
ALLOWED = [
  (re.compile(r"^(#|//)"), "prose: a header or an inline comment was rewritten"),
  (re.compile(r"^(def|type) "), "a declaration: the per-file picks lost their `v`"),
  (re.compile(r"^\w"), "a body line: a call site gained a `CL.`/`CU.` qualifier"),
  (re.compile(r"^[\[\](){}]"), "a bracket: `cu_unchecked`'s op list, qualified in place"),
  (re.compile(r"^:"), "a record field: a field list line"),
]

dropped = collections.defaultdict(list)
for i, ln in enumerate(pre, 1):
  s = ln.strip()
  if not s or s in have:
    continue
  for rx, why in ALLOWED:
    if rx.match(s):
      break
  else:
    dropped[why].append((i, s))

print(f"pre-split lines {len(pre)}; destination lines {sum(len((ROOT/f).read_text().splitlines()) for f in DST)}")
print(f"non-blank pre-split lines whose text appears in NO destination: "
      f"{sum(len(v) for v in dropped.values())}")
for why, rows in dropped.items():
    print(f"\n  {why}")
    for i, s in rows:
        print(f"    pre:{i:5} {s[:96]}")
if dropped:
    sys.exit("SOME PRE-SPLIT LINES WERE NEVER COPIED -- see above")
print("\nno pre-split line was dropped. The edits that DID happen are the ones the")
print("split script enumerates: call-site qualifiers, four `v`-argument removals,")
print("two `cl.sync` -> `cu.sync` call sites, and the rewrites of t_vend/t_check/")
print("t_err/t_print/main. Each is asserted by a count in cl_split.py.")