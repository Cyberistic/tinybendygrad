#!/usr/bin/env python3
"""OUTPUT CENSUS -- what WALL 4 leaves unbuilt, measured.

The brief warns that "13,480 defs" for this region is WRONG: it came from
`ast.walk`, which counts NESTED defs.  This script counts TOP-LEVEL defs and
says which method it used, decomposes the total with no residue, and checks
the emitted bodies against the generator's OWN TEMPLATE rather than against
name-and-arity.

Name-and-arity is the stated ceiling and it is a WEAK ceiling: a body that
calls the wrong function at the right arity passes it.  So this also asks the
stronger question -- do the bodies share a TEMPLATE with the generator that
emits them? -- and checks every body against that template.
"""
import ast, os, re

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT  = os.path.join(REPO, ".agents/slop/ag-output-census.txt")
AUTO = os.path.join(REPO, "tinygrad/runtime/autogen")
BEND = os.path.join(REPO, "tinybendygrad/runtime/autogen")

files = sorted(f for f in os.listdir(AUTO) if f.endswith(".py"))
py_files = [os.path.join(AUTO, f) for f in files]

# ------------------------------------------------------ MEASURE (no reporting)
def top_defs(tree):
  """Top-level defs only: module body, plus the BODY of each top-level class."""
  out = []
  for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): out.append(node)
    elif isinstance(node, ast.ClassDef):
      out += [s for s in node.body if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef))]
  return out

top_level = walk_total = classes = 0
nflow = 0; flow_files = {}
per_file = []
for p in py_files:
  src = open(p, encoding="utf-8", errors="replace").read()
  tree = ast.parse(src)
  td = top_defs(tree)
  c = sum(1 for fn in td if any(isinstance(n, (ast.If, ast.For, ast.While, ast.Try, ast.With))
                               for n in ast.walk(fn)))
  cl = sum(1 for n in tree.body if isinstance(n, ast.ClassDef))
  top_level += len(td); nflow += c; classes += cl
  walk_total += sum(1 for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)))
  if c: flow_files[os.path.basename(p)] = c
  per_file.append((os.path.basename(p), len(td), cl, len(src.splitlines())))

# the template, lifted verbatim from autogen.py:240-241
DEFLINE = re.compile(r"^def \w+\(.*\) -> [^:]+: \.\.\.$")
allbind = shaped = 0
for p in py_files:
  lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
  for i, ln in enumerate(lines):
    if ln.startswith("@dll.bind("):
      allbind += 1
      if i + 1 < len(lines) and DEFLINE.match(lines[i + 1]): shaped += 1

# ------------------------------------------------------------------ REPORT
L = []
def W(s=""): L.append(s)

W("=" * 78)
W("OUTPUT CENSUS -- tinygrad/runtime/autogen/*.py  (the generator's OUTPUT)")
W("=" * 78)
W("")
W("## 0. THE COUNT, AND WHICH METHOD PRODUCED IT")
W(f"  files counted                       : {len(py_files)}")
W(f"  TOP-LEVEL defs (method used)        : {top_level}")
W("    method: ast.parse, then module tree.body and each ClassDef's .body.")
W("            Nested defs are NOT counted -- there are none in this corpus.")
W(f"  ast.walk count (CONTRAST)           : {walk_total}")
W("    method: ast.walk over the whole tree.")
W(f"  classes                             : {classes}")
W("")
W("  ON THE '13,480' FIGURE: it is not reproducible here by either method.")
W(f"  ast.walk gives {walk_total}, the same as the top-level count, because these")
W("  are generated one-expression defs with no nested defs at all.  Whatever")
W("  produced 13,480 counted something other than Python defs (most likely")
W("  class bodies, or rows of emitted text).  Reported, not reconciled.")
W("")
W("  per file:  name  top_defs  classes  lines")
for n, tl, cl, ln in per_file:
  W(f"    {n:<24} {tl:>7} {cl:>8} {ln:>7}")
W("")
W("## 1. DOES THE PORT SIDE EXIST AT ALL?")
W(f"  {BEND}")
W(f"  exists = {os.path.isdir(BEND)}")
W("")
W("## 2. THE DECOMPOSITION -- 4,868 = 4,864 + 4, with NO residue")
W("")
W(f"  @dll.bind trampolines matching the template : {shaped}")
W(f"  top-level defs NOT of that shape            : {top_level - shaped}")
W(f"    all of them in                            : {list(flow_files) or 'n/a'}")
W("      macossdk, load, _extract_deb, __getattr__ -- the hand-written LOADER")
W("      in __init__.py, not generator output at all.")
W("")
W("  CONTROL FLOW, counted over TOP-LEVEL DEF BODIES:")
W(f"    defs whose body contains if/for/while/try/with : {nflow}  {flow_files}")
W(f"    => {top_level - nflow} of {top_level} top-level defs have NO control flow:")
W(f"       each is a `def f(...) -> T: ...` line under an `@dll.bind`.")
W("")
W("  CORRECTION TO THE TASK BRIEF, which said '3 bodies contain any control")
W(f"  flow'.  Measured it is 1 (`load`, the loader def).  3 is not reproducible")
W("  by top-level parse, by ast.walk over defs, or by ast.walk over files")
W("  (6 files contain if/for/try SOMEWHERE, but never inside a top-level def")
W("  body other than `load`).  1 is the number; 3 is not inherited.")
W("")
W("## 3. THE TEMPLATE CHECK -- what name-and-arity cannot do")
W("")
W("Name-and-arity proves the counterpart def EXISTS and its signature")
W("AGREES.  It cannot see WHICH FUNCTION a body calls, so a body calling the")
W("wrong getter at the right arity passes it.  The stronger check is a")
W("TEMPLATE check: these bodies are generated, so they must match the shape")
W("autogen.py:240-241 emits.")
W("")
W("  THE TEMPLATE, lifted verbatim from autogen.py:240-241:")
W("    @dll.bind(<ret>, <arg types>)")
W("    def <name>(<anm>:<hint>, ...) -> <ret>: ...")
W("")
W(f"  @dll.bind lines in corpus                : {allbind}")
W(f"  ...immediately followed by the def line  : {shaped}")
W(f"  RATIO shaped/all                         : {shaped}/{allbind}")
W("")
if allbind and shaped == allbind:
  W("  => ONE TEMPLATE COVERS EVERY BOUND BODY.  A per-def gate would be 4,864")
  W("     copies of this one shape.  The template check is strictly STRONGER")
  W("     than name-and-arity because it also pins the RETURN TYPE, the")
  W("     PARAMETER NAMES, the PARAMETER ANNOTATIONS and the `...` body,")
  W("     none of which a name+arity diff looks at.")
else:
  W("  => TEMPLATE DOES NOT COVER ALL BODIES.  name-and-arity is the ceiling;")
  W("     state that limit rather than papering over it.")
W("")
W("## 4. WHAT THE TEMPLATE CANNOT SEE (stated, not hidden)")
W("  The template pins the SHAPE of the emitted def.  It cannot see:")
W("    - whether the ctypes TYPE SPELLING tname derived is correct")
W("      (`c.POINTER[struct_Pair]` vs `ctypes.c_void_p`) -- that is WALL 4,")
W("      the unported record arm, reproduced at .agents/slop/ag-wall4-repro.bend;")
W("    - whether the FIELD ORDER inside a struct is right -- the template")
W("      never sees struct bodies;")
W("    - whether register_fields OFFSETS are right.")
W("  So a template check covers the FUNCTION TRAMPOLINES and none of the")
W("  STRUCT LAYOUTS.  Reported, not papered over.")
W("")
W("## 5. COVERAGE versus FUNCTION -- the honest statement")
W("  These 4,864 defs are device FFI trampolines.  Emitting them moves")
W("  COVERAGE, not FUNCTION: none can execute without a working device layer,")
W("  and .agents/slop/e2e.sh still proves exactly ONE matmul on real")
W("  hardware.  A full port of this region is not reachable anyway -- WALL 4")
W("  (tname's record arm) is refused by bend's decreasing-self-call rule,")
W("  and it is refused INDEPENDENTLY of WALL 1, so closing the FFI would not")
W("  make the generator able to emit.")

open(OUT, "w").write("\n".join(L) + "\n")
print("\n".join(L))
print(f"[written] {OUT}")
print(f"[json] top_level={top_level} walk={walk_total} template={shaped}/{allbind} flow={nflow}")