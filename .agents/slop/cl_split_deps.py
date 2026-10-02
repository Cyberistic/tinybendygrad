"""WHICH DEF DOES EACH SECTION NEED? The split's whole risk is a call site.

Reads `runtime/ops_cl.bend`, buckets every `def` by the section it sits in, then
reports which bucket each bucket NAMES. The output is the call-site list the split
has to qualify, measured rather than guessed.

Usage: python3 .agents/slop/cl_split_deps.py
"""
import re, sys, pathlib, collections

ROOT = pathlib.Path(__file__).resolve().parents[2]
BENCH = ROOT / "tinybendygrad/runtime/ops_cl.bend"

# section boundaries are (first line, last line) inclusive, 1-indexed, measured
# from the PART markers: PART 0 substrate, PART 1 OpenCL, PART 2 CUDA, PART 3 HIP,
# THE GATE.
BUCKETS = [
  ("substrate", 261, 1012),
  ("cl",       1014, 1776),
  ("cu",       1777, 2152),
  ("hp",       2153, 2443),
  ("gate",     2444, 99999),
]
TESTS = {
  "t_vend": 2485, "t_check": 2522, "t_err": 2543, "t_print": 2576,
  "t_clinit": 2623, "t_climg": 2667, "t_clprog": 2730, "t_clcall": 2762,
  "t_clalloc": 2799, "t_refuse": 2832, "t_cuinit": 2880, "t_cuqueue": 2920,
  "t_cualloc": 2962, "t_hpinit": 3008, "t_hpargs": 3038, "t_cross": 3074,
}

lines = BENCH.read_text().splitlines()


def bucket_of(lineno: int) -> str:
  for name, lo, hi in BUCKETS:
    if lo <= lineno <= hi:
      return name
  return "header"


defs = collections.OrderedDict()   # name -> lineno
for i, ln in enumerate(lines, 1):
  m = re.match(r"def ([A-Za-z_][\w.]*)\(", ln)
  if m and m.group(1) not in defs:
    defs[m.group(1)] = i

# a body is every line of its def up to the next `def`/`type`/section marker
bounds = sorted(defs.values())
owner = {n: bucket_of(l) for n, l in defs.items()}

# which test function is a given line inside
def test_of(lineno: int) -> str:
  best = None
  for name, start in TESTS.items():
    if start <= lineno and (best is None or start > TESTS[best]):
      best = name
  return best or "gate-main"


refs = collections.defaultdict(set)          # (srcbucket, srctest) -> set(names)
for i, ln in enumerate(lines, 1):
  b = bucket_of(i)
  if b == "header":
    continue
  t = test_of(i) if b == "gate" else b
  # strip comments and string literals so a symbol inside a comment is not a call
  code = ln.split("#")[0]
  code = re.sub(r'"[^"]*"', '""', code)
  for name in defs:
    if re.search(r"(?<![\w.])" + re.escape(name) + r"(?![\w])", code):
      refs[(b, t)].add(name)

print("== every def, by bucket ==")
for name, lo in defs.items():
  print(f"  {owner[name]:9} {lo:5} {name}")
print()
print("== cross-bucket references (bucket -> set of buckets it needs) ==")
for (src, _), names in sorted(refs.items()):
  need = collections.Counter(owner[n] for n in names if owner[n] != src)
  if need:
    print(f"  {src:9} needs {dict(need)}")
print()
print("== per TEST: which buckets' defs does it name ==")
for (b, t), names in sorted(refs.items(), key=lambda kv: (TESTS.get(kv[0][1], 0), kv[0][0])):
  if b != "gate":
    continue
  need = collections.Counter(owner[n] for n in names)
  print(f"  {t:11} {dict(need)}")
print()
print("== the ACTUAL call sites that must be qualified, by target bucket ==")
for (src, _), names in sorted(refs.items()):
  for tgt in ("cu", "hp", "substrate"):
    hits = sorted(n for n in names if owner[n] == tgt)
    if hits and src not in ("header",):
      print(f"  {src:9} -> {tgt:9} ({len(hits)}): {', '.join(hits)}")