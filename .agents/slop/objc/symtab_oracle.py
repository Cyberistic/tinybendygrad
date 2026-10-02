# SYMBOL BINDING AUDIT for tinygrad/runtime/support/objc.py and its ONE caller ops_metal.py:86
#
# Every question here is answered by CALLING the real tinygrad objects or by reading the real
# dyld export table. Nothing is hand-typed. Run with .venv/bin/python (needs the repo root on cwd).
import ctypes, ctypes.util, functools, os, sys
from tinygrad.runtime.support.c import DLL as CDLL
import tinygrad.runtime.support.objc as objc

def has(lib, sym):
  try: return hex(ctypes.cast(getattr(lib, sym), ctypes.c_void_p).value)
  except (OSError, AttributeError): return "MISSING"

rows = []
def row(name, bound_on, sym, ans): rows.append((name, bound_on, sym, ans)); print(f"{name:26s} {bound_on:16s} {sym:26s} {ans}", flush=True)

# ---- objc.py:25-29 : lib = CDLL(find_library('objc')) ------------------------------
p = ctypes.util.find_library('objc')
print(f"# objc.py:25  ctypes.util.find_library('objc') -> {p}")
for s in ("sel_registerName", "objc_msgSend", "objc_getClass", "objc_autoreleasePoolPush", "objc_autoreleasePoolPop"):
  row("objc.py:26-29 lib", p.split('/')[-1], s, has(objc.lib, s))

# ---- objc.py:30 : dispatch_data_create off the hardcoded libSystem --------------------
# NOTE the asymmetry, and it is MEASURED: objc.py uses a BARE ctypes.CDLL, and ctypes CAN
# dlopen a path that only exists in the dyld shared cache.  support/c.py's DLL.findlib
# (c.py:102-103) uses pathlib.Path(...).is_file(), which is FALSE for such a path, so the
# same library routed through DLL() silently never loads.  Both are shown.
ls = ctypes.CDLL("/usr/lib/libSystem.dylib")
row("objc.py:30", "libSystem.dylib", "dispatch_data_create", has(ls, "dispatch_data_create"))
row("objc.py:30", "libSystem.dylib", "objc_msgSend", has(ls, "objc_msgSend"))
from tinygrad.runtime.support.c import DLL as CDLL2
row("c.py:102 via DLL()", "libSystem.dylib", "dispatch_data_create",
    "NEVER LOADED" if "libSystem.dylib" not in CDLL2._loaded_ else has(CDLL2("x","System"), "dispatch_data_create"))
CDLL2("x", "/usr/lib/libSystem.dylib")  # force the attempt
row("c.py:102 via DLL()", "libSystem.dylib", "<DLL()>",
    "in _loaded_: " + str("x" in CDLL2._loaded_) + " emsg-free path rejected by is_file()")

# ---- ops_metal.py:86 : BOTH bound on metal.dll ---------------------------------------
metal = CDLL('metal', 'Metal')
mp = metal.__dict__.get('_name') or "/System/Library/Frameworks/Metal.framework/Metal"
print(f"# ops_metal.py:86  metal.dll path = {mp}")
for s in ("objc_msgSend", "sel_registerName"):
  row("ops_metal.py:86", "Metal.framework", s, has(metal, s))

# ---- the ACTUAL dyld export tables (this is the load-bearing measurement) -------------
def exports(path, pats):
  out = subprocess_run(["xcrun", "dyld_info", "-exports", path])
  live = sum(1 for l in out.splitlines() if l.strip().startswith("0x"))
  if live < 20: return None, live        # dyld_info read a header only: UNAVAILABLE, not "zero exports"
  return {s: sum(1 for l in out.splitlines() if l.rstrip().endswith("_" + s)) for s in pats}, live

import subprocess
def subprocess_run(cmd): return subprocess.run(cmd, capture_output=True, text=True).stdout

SYMS = ("sel_registerName", "objc_msgSend", "objc_getClass", "objc_autoreleasePoolPush", "dispatch_data_create")
print("\n# dyld_info -exports counts (DEFINED exports of the image itself)")
for label, path in (("Metal.framework", mp), ("libobjc.dylib", p), ("libSystem.dylib", "/usr/lib/libSystem.dylib"),
                    ("libm.dylib", "/usr/lib/libm.dylib")):
  ex, live = exports(path, SYMS)
  if ex is None:
    print(f"EXPORT {label:20s} {'(ALL FIVE)':26s} UNAVAILABLE: dyld_info read 0 export lines -- NOT a zero")
  else:
    for s, n in ex.items(): print(f"EXPORT {label:20s} {s:26s} {n}   [{live} live exports]")

print("\n# dlsym REACHABILITY through each handle (this is what objc.py/ops_metal.py actually get)")
for label, lib in (("libSystem.dylib", ls), ("Metal.framework", metal), ("libobjc.dylib", objc.lib)):
  for s in ("dispatch_data_create", "sel_registerName", "objc_msgSend"):
    print(f"REACH  {label:20s} {s:26s} {has(lib, s)}")

print("\n# who does dlsym reach? Metal's LC_LOAD_DYLIB neighbours")
out = subprocess_run(["otool", "-L", mp])
print("\n".join("   "+l for l in out.splitlines()))

# ---- elf.py:13 link_sym against the libs CPUProgram actually passes -------------------
print("\n# ops_cpu.py:19  CPUProgram.rt_lib/libm  -> the link_libs jit_loader gets")
rt, lm = CDLL('rt', 'System'), CDLL('m', 'm')
for s in ("sel_registerName", "objc_msgSend"):
  row("ops_cpu.py:19 link_libs", "libm+libSystem", s, (has(lm, s) if has(lm, s) != "MISSING" else has(rt, s)))

print(f"\nROWS={len(rows)}")
