"""TWO MEASUREMENTS THE SPLIT OWES THE OWNER.

1. NAME CORRESPONDENCE. The rule is "def names match upstream exactly". What that
   costs is a PER-FILE number, not a tree-wide one, and the two are very
   different: this file's port defs are not renamed ports at all, they are
   port-local record types and accessors with no upstream counterpart. This script
   counts both, per file, from the real `tinygrad/runtime/*.py` AST.

2. VERBATIM BODIES. Every def body must have MOVED unchanged. This script
   reverse-applies the split's call-site qualifiers to each destination and
   diffs the def against the pre-split source, so a hand-edit inside a moved
   body cannot hide.

  python3 .agents/slop/cl_split_names.py
"""
import ast, pathlib, re, subprocess, sys, collections

ROOT = pathlib.Path(__file__).resolve().parents[2]
PRE = ROOT / ".agents/slop/ops_cl-pre-split.bend"
PAIRS = [("cl", "tinygrad/runtime/ops_cl.py", "tinybendygrad/runtime/ops_cl.bend"),
         ("cu", "tinygrad/runtime/ops_cuda.py", "tinybendygrad/runtime/ops_cuda.bend"),
         ("hp", "tinygrad/runtime/ops_hip.py", "tinybendygrad/runtime/ops_hip.bend")]

UPSTREAM = {}
for tag, py, _ in PAIRS:
  tree = ast.parse((ROOT / py).read_text())
  names = set()
  for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
      names.add(node.name)
  UPSTREAM[tag] = names

print("== 1. NAME CORRESPONDENCE, per file, against the real .py AST ==")
print("`verbatim` = a port def whose name IS an upstream def name.")
print("`port-local` = a port def with NO upstream counterpart (a record type, an")
print("              accessor, a trace op). The naming rule does not apply to it:")
print("              there is nothing to match. This is the whole reason the")
print("              tree-wide '3% carry the upstream name' figure is misleading.")
print("`MISSED` = an upstream def with NO port def of that name: the actionable")
print("           number, and the one a rename pass would work from.")
print()
print(f"{'file':10} {'upstream':>9} {'port defs':>10} {'verbatim':>9} {'port-local':>11} "
      f"{'MISSED':>7}")
print("-" * 62)
tot = collections.Counter()
missed_all = []
for tag, py, bend in PAIRS:
  src = pathlib.Path(bend).read_text().splitlines()
  port = [m.group(1) for ln in src
          if (m := re.match(r"def ([A-Za-z_][\w.]*)\(", ln))]
  up = UPSTREAM[tag]
  verb = [n for n in port if n in up or n.split(".")[-1] in up]
  local = [n for n in port if n not in verb]
  # dunders are Python's own, not the port's to carry
  miss = sorted(n for n in up if n.startswith("__"))
  carry = up - set(miss)
  missed = sorted(n for n in carry if not any(n == p or p.split(".")[-1] == n for p in port))
  print(f"{'ops_' + tag:10} {len(carry):>9} {len(port):>10} {len(verb):>9} {len(local):>11} "
        f"{len(missed):>7}")
  tot["up"] += len(carry); tot["port"] += len(port); tot["verb"] += len(verb)
  missed_all += [(tag, n) for n in missed]
print("-" * 62)
print(f"{'TOTAL':10} {tot['up']:>9} {tot['port']:>10} {tot['verb']:>9}")
print(f"  {tot['verb']} of {tot['up']} upstream names are carried verbatim "
      f"({100*tot['verb']//tot['up']}%), and {tot['port'] - tot['verb']} of the")
print(f"  {tot['port']} port defs have NO upstream name at all.")
print()
print("  MISSED (an upstream def with no port def of that name):")
for tag, n in missed_all:
    print(f"    ops_{tag}.py  {n}")
print()

print()
print("== 2. VERBATIM BODIES: reverse the qualifiers and diff every def ==")
print("COMMENT lines are excluded: a block boundary legitimately re-attaches a")
print("trailing comment to the next def, and `cl_split_noloss.py` is the check")
print("that no comment was DROPPED. This check is about CODE.")
print()
# the edits the split is allowed to make, with the reason
ALLOW = {
  "chk_count.at": "the `v` argument: per file",
  "chk_count": "the `v` argument: per file",
  "vend.line": "the `v` argument: per file",
  "vend.trace.put": "the `v` argument: per file",
  "vend.trace.go": "the `v` argument: per file",
  "vend.trace": "the `v` argument: per file",
  "vend.name": "the `v` argument: per file",
  "vend.count": "the `v` argument: per file",
  "vend.checked": "the `v` argument: per file",
  "cu.free": "cu:80/82 synchronize is CUDA's own: `cu.sync`, not `cl.sync`",
  "cu.wait_signal": "cu:134-136 synchronize is CUDA's own: `cu.sync`, not `cl.sync`",
  "cu.sync": "NEW: cu:82's own `OP_FINISH` emitter",
  "t_vend": "REWRITTEN: the three-vendor columns went to their own files",
  "t_check": "REWRITTEN: the three-vendor columns went to their own files",
  "t_err": "REWRITTEN: the three-vendor columns went to their own files",
  "t_hptiming": "NEW: hp:57's row followed `timing.scale_hp` to this file",
  "main": "REWRITTEN: one `main` per file, and only ops_cl prints `cl-done=1`",
  "t_print": "one row moved out with `timing.scale_hp`",
  "V_CL": "the `vendor` field it feeds is read by nothing",
}

tags = {"cu": ["CL."], "hp": ["CL.", "CU."]}

# The split's ENUMERATED call-site edit, normalised rather than allow-listed, so
# this check keeps its teeth over everything else: `vend.trace(v, cs)` and
# `vend.name(v, op)` lost their vendor tag, because the vendor is now the MODULE.
DROP_TAG = re.compile(r"\b(vend\.trace|vend\.name|vend\.checked|vend\.count)"
                      r"\(V_(?:CL|CUDA|HIP)\(\), ")


def body(src, i):
    """a def's CODE lines, comments excluded, up to the next def/type/import."""
    out = [src[i]]
    j = i + 1
    while j < len(src) and not re.match(r"(def|type|import) ", src[j]) \
          and not src[j].startswith("# =="):
        if src[j].strip() and not src[j].lstrip().startswith("#"):
            out.append(src[j])
        j += 1
    return out


pre = PRE.read_text().splitlines()
pre_at = {}
for i, ln in enumerate(pre):
    m = re.match(r"def ([A-Za-z_][\w.]*)\(", ln)
    if m and m.group(1) not in pre_at:
        pre_at[m.group(1)] = i

bad, checked = [], 0
for tag, _py, bend in PAIRS:
    src = pathlib.Path(bend).read_text().splitlines()
    i = 0
    while i < len(src):
        m = re.match(r"def ([A-Za-z_][\w.]*)\(", src[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        got = body(src, i)
        j = i + len(got)
        if name in ALLOW:
            i = j
            continue
        if name not in pre_at:
            i = j
            continue
        # pre-split line 2443 had the NEXT section marker glued onto the def:
        # `def hp_offset_sum(...): U32.add(buf, offset)# =====`. The split drops the
        # marker because it opens `ops_cl.bend`\'s gate section, so strip it here.
        want = [re.sub(r"\s*# =+.*$", "", l) for l in body(pre, pre_at[name])]
        want = [DROP_TAG.sub(r"\1(", l) for l in want]
        for t in tags.get(tag, []):
            got = [l.replace(t, "") for l in got]
        if want != got:
            bad.append((tag, name, want, got))
        checked += 1
        i = j

print(f"  {checked} moved defs compared against the pre-split source, "
      f"{len(ALLOW)} allow-listed edits")
print(f"  defs whose CODE is not verbatim after un-qualifying: {len(bad)}")
for tag, name, want, got in bad:
    print(f"    ops_{tag}.bend {name}:")
    for a, b in zip(want, got):
        if a != b:
            print(f"      pre: {a.strip()}")
            print(f"      now: {b.strip()}")
    if len(want) != len(got):
        print(f"      line count {len(want)} -> {len(got)}")
sys.exit(1 if bad else 0)
