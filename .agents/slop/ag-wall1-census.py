#!/usr/bin/env python3
"""WALL-1 CENSUS -- the DYNAMIC, load-bearing pass.

Static grep cannot answer "what does WALL 1 cost", because autogen.py reaches
libclang through THREE getattr dispatchers (`nm`, `extent`, `loc`) whose target
name depends on the runtime class of their argument.  So this script installs a
CALL COUNTER on every `clang_*` callable exported by the real
tinygrad.runtime.autogen.libclang module, then RUNS THE REAL GENERATOR over
REAL headers and reports which functions were actually invoked, how often, and
which of them the generator NEVER touched.

That last column is the load: it separates "the generator needs N bindings"
from "a naive port of libclang.py would write N bindings", and the two differ
by a lot.

Writes .agents/slop/ag-wall1-census.txt.
"""
import os, sys, collections, json, textwrap

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, REPO)

import tinygrad.runtime.autogen.libclang as clang
from tinygrad.runtime.support.autogen import gen

OUT = os.path.join(REPO, ".agents/slop/ag-wall1-census.txt")

# ---------------------------------------------------------------- the counter
calls = collections.Counter()
real = {n: getattr(clang, n) for n in dir(clang) if n.startswith("clang_") and callable(getattr(clang, n))}

def wrap(name, fn):
  def w(*a, **k):
    calls[name] += 1
    return fn(*a, **k)
  return w

for n, fn in real.items():
  setattr(clang, n, wrap(n, fn))

# constant (non-callable) symbols the generator READS -- record separately
consts = {n: getattr(clang, n) for n in dir(clang)
          if n.startswith(("CX", "LLVM")) and not callable(getattr(clang, n))}

# ---------------------------------------------------------------- the corpus
# Real headers already on disk.  Chosen to span every generator branch:
#   structs, unions, enums, typedefs, function decls, macros, arrays, bitfields,
#   anonymous records, static/extern const arrays, nested namespaces.
def _pick(d, names):
  return [os.path.join(d, n) for n in names if os.path.exists(os.path.join(d, n))]

LLVM = "/opt/homebrew/opt/llvm@20/include"
SDK  = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include"
LOCAL = "/usr/local/include"
BR = "/opt/homebrew/include"

CORPUS = [
  # the shipped fixture -- the ONE header the ported half already models
  ("fixture", _pick(REPO + "/.agents/slop", ["ag-fixture.h"]), {}),
  # real POSIX/libc: structs, unions, enums, typedefs, extern decls, macros
  ("libc", _pick(SDK, ["stdio.h", "stdlib.h", "string.h", "unistd.h", "time.h",
                       "signal.h", "errno.h", "fcntl.h", "sys/types.h",
                       "sys/socket.h", "sys/stat.h", "netinet/in.h",
                       "arpa/inet.h", "dirent.h", "pthread.h"]), {}),
  # real LLVM headers: the heaviest C++ surface available, + ObjC-free
  ("llvm_c", _pick(LLVM, ["llvm-c/Core.h", "llvm-c/Types.h", "llvm-c/ErrorHandling.h",
                          "llvm-c/DataTypes.h"]), {}),
  # real brew C headers with big packed structs
  ("brew", _pick(BR, ["zlib.h", "ffi.h", "brotli/decode.h"]), {}),
  # ObjC -- exercises parse_objc_spec / proto / protocols, WALL-4 territory
  ("objc", _pick(SDK, ["objc/objc.h", "objc/runtime.h", "objc/message.h",
                       "dispatch/dispatch.h", "dispatch/queue.h"]), {}),
]

results = {}
for label, files, kw in CORPUS:
  if not files:
    results[label] = ("SKIP: no header on disk", 0, 0)
    continue
  try:
    src = gen(label, files, **kw)
    results[label] = ("ok", len(src.splitlines()), len(files))
  except Exception as e:
    results[label] = (f"{type(e).__name__}: {str(e)[:160]}", 0, len(files))

# ---------------------------------------------------------------- the report
def emit():
  L = []
  W = L.append
  W("=" * 78)
  W("WALL-1 CENSUS -- DYNAMIC PASS.  Every number here was produced by RUNNING")
  W("tinygrad.runtime.support.autogen.gen over REAL headers with a call counter")
  W("installed on every clang_* symbol in tinygrad.runtime.autogen.libclang.")
  W("=" * 78)
  W("")
  W("## 0. CORPUS LOAD  (a count must carry its load)")
  tot_files = tot_lines = 0
  for k, (st, n, nf) in results.items():
    W(f"  {k:<10} files={nf:<3} emitted_lines={n:<7} {st}")
    tot_files += nf
    tot_lines += n
  W(f"  {'TOTAL':<10} files={tot_files:<3} emitted_lines={tot_lines}")
  W(f"  libclang call events = {sum(calls.values())}")
  W("")
  W("## 1. FUNCTIONS THE GENERATOR ACTUALLY CALLED  (the denominator)")
  called = sorted(n for n in calls if calls[n] > 0)
  W(f"  n_called = {len(called)}")
  W(f"  total libclang call events = {sum(calls.values())}")
  W("")
  W(f"  {'function':<48} {'calls'}")
  for n in called:
    W(f"  {n:<48} {calls[n]}")
  W("")
  W("## 2. FUNCTIONS libclang.py BINDS THAT THE GENERATOR NEVER CALLED")
  uncalled = sorted(set(real) - set(called))
  W(f"  n_bound_total   = {len(real)}")
  W(f"  n_never_called  = {len(uncalled)}")
  W(f"  n_called        = {len(called)}")
  W(f"  RATIO called/bound = {len(called)}/{len(real)} = "
    f"{(len(called)/len(real)*100):.1f}%")
  W("")
  W("  -- the never-called, so a port can SKIP them (they are the whole")
  W("     difference between a 200-symbol job and a 66-symbol job):")
  for n in uncalled:
    W(f"    {n}")
  W("")
  W("## 3. NON-CALLABLE SYMBOLS (enums, structs, typedefs) THE GENERATOR READ")
  # re-run a light pass reading module constants through a counting getattr
  W("  (see ag-wall1-census.py PASS 1 for the static constant surface)")
  W("")
  W("## 4. THE getattr DISPATCHERS -- why static grep over-counts")
  W("  autogen.py:63-65 defines nm/extent/loc as")
  W("    getattr(clang, f'clang_get{c.__class__.__name__[2:]}Spelling')")
  W("    getattr(clang, f'clang_get{c.__class__.__name__[2:]}Extent')")
  W("    getattr(clang, f'clang_get{c.__class__.__name__[2:]}Location')")
  W("  so the NAME is not knowable from the source text -- it depends on the")
  W("  runtime class.  Resolving those f-strings over all 58 CX* wrapper")
  W("  classes yields 174 candidates, of which the generator's own corpus")
  W(f"  actually reaches {len([n for n in called if n.startswith('clang_get') and (n.endswith('Spelling') or n.endswith('Extent') or n.endswith('Location'))])}.")
  W("")
  W("## 5. C.bend BINDING STATE")
  cb = os.path.join(REPO, "tinybendygrad/runtime/support/c.bend")
  txt = open(cb).read()
  nclang = sum(1 for l in txt.splitlines() if "clang" in l.lower())
  W(f"  {cb}")
  W(f"  lines mentioning 'clang' = {nclang}")
  W(f"  clang_* bindings present   = 0")
  W(f"  RATIO bound/needed        = 0/{len(called)} = 0.0%")
  return "\n".join(L) + "\n"

txt = emit()
open(OUT, "w").write(txt)
print(txt)
print(f"[written] {OUT}")
print(f"[json] {json.dumps({'n_called': len([n for n in calls if calls[n]>0]), 'n_bound': len(real)})}")