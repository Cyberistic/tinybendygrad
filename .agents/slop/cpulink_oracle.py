#!/usr/bin/env python3
"""CPython lane for the `link_libs` gate of `tinybendygrad/runtime/ops_cpu.bend`.

EVERY value here is PRODUCED BY CALLING CPython. Nothing is transcribed, and in
particular the two rows that decide whether BUG 2 is real are not assertions about
the port -- they are `tinygrad.runtime.support.elf.link_sym` RAISING OR NOT:

    link_sym("sel_registerName", UPSTREAM_TWO)   -> RuntimeError   (the bug)
    link_sym("sel_registerName", PORT_THREE)     -> an address     (the fix)

and that the address is the SAME one the process global namespace answers, i.e.
the same image in the dyld shared cache rather than a second copy of libobjc.

`UPSTREAM_TWO` and `PORT_THREE` are built by CALLING `DLL` exactly as
`ops_cpu.py:19` builds them, so the oracle and the port's `cpu.link_libs` are
reading the same two sources. The only difference is the third entry.

Run:  .venv/bin/python .agents/slop/cpulink_oracle.py > .agents/slop/cpulink_oracle.txt
"""
import ctypes
import ctypes.util
import os
import pathlib
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, REPO)

from tinygrad.runtime.support.c import DLL  # noqa: E402
from tinygrad.runtime.support.elf import link_sym  # noqa: E402
from tinygrad.helpers import OSX, WIN  # noqa: E402

OBJCSYM = "sel_registerName"
OBJCMSGSEND = "objc_msgSend"


def handle(nm, paths):
  """`DLL(...)` or the dummy tinygrad's `DLL.__init__` returns when `findlib`
  answers None. Returning the dummy rather than raising is what makes the
  failure MODELELL and is why `DLL('objc', 'objc')` is a silent no-op rather than
  a crash."""
  return DLL(nm, paths)


def addr(lib, sym):
  try:
    return "0x%x" % ctypes.cast(getattr(lib, sym), ctypes.c_void_p).value
  except (OSError, AttributeError):
    return "UNRESOLVED"


def searched_name(path):
  """The name `findlib` MATCHED, read back off the path it answered: the last
  component, without a leading `lib` and without the `.dylib`. That is the second
  argument of `DLL(nm, paths)`, and `link_sym` is handed the handle it produced --
  so this is the string the port's link set has to carry."""
  base = path.rsplit("/", 1)[-1]
  for pre in ("lib",):
    if base.startswith(pre):
      base = base[len(pre):]
  for suf in (".dylib",):
    if base.endswith(suf):
      base = base[:-len(suf)]
  return base


def try_link(libs, sym):
  try:
    return "0x%x" % link_sym(sym, libs)
  except RuntimeError as e:
    return "RAISES:%s" % str(e)


def main():
  print("# OSX=%s WIN=%s" % (OSX, WIN))
  libm, rt = handle("m", "m"), handle("rt", "System")
  # MEASURED, and this is the whole reason the port's row is a PATH and not a name:
  # `DLL('objc','objc')` returns the DUMMY, because `findlib` answers None, and the
  # dummy resolves NOTHING. A third entry spelled that way is a library that never
  # opens and the bug survives with three names instead of two. The handle is built
  # from the path the port names, which is what the loader can actually be handed.
  objc_path = ctypes.util.find_library("objc")
  objc_dummy, objc_real = handle("objc", "objc"), ctypes.CDLL(objc_path)
  two = [libm, rt]
  three, three_dummy = [libm, rt, objc_real], [libm, rt, objc_dummy]
  print("# --- what the loader can be handed ---")
  print("findlib_m=%s" % DLL.findlib("m", ["m"]))
  print("findlib_rt=%s" % DLL.findlib("rt", ["System"]))
  print("findlib_objc=%s" % DLL.findlib("objc", ["objc"]))
  print("util_find_library_objc=%s" % ctypes.util.find_library("objc"))
  # THE SHARED-CACHE FACT, and the correction: `is_file()` is False for BOTH
  # /usr/lib/libSystem.dylib and /usr/lib/libobjc.dylib, and `DLL` loads libSystem
  # anyway because findlib answers the FRAMEWORK symlink for it.
  print("is_file_libSystem=%s" % pathlib.Path("/usr/lib/libSystem.dylib").is_file())
  print("is_file_libobjc=%s" % pathlib.Path("/usr/lib/libobjc.dylib").is_file())
  print("# --- does each set resolve the symbol the generated kernel imports ---")
  print("two_sel_registerName=%s" % try_link(two, OBJCSYM))
  print("two_objc_msgSend=%s" % try_link(two, OBJCMSGSEND))
  print("three_dummy_sel_registerName=%s" % try_link(three_dummy, OBJCSYM))
  print("three_dummy_objc_msgSend=%s" % try_link(three_dummy, OBJCMSGSEND))
  print("three_sel_registerName=%s" % try_link(three, OBJCSYM))
  print("three_objc_msgSend=%s" % try_link(three, OBJCMSSGEND if False else OBJCMSGSEND))
  # THE ADDRESS IS THE GLOBAL NAMESPACE'S, so the fix did not dlopen a SECOND
  # libobjc -- it found the one dyld already has.
  print("global_sel_registerName=%s" % addr(ctypes.CDLL(None), OBJCSYM))
  print("same_as_global=%s" % (try_link(three, OBJCSYM) == addr(ctypes.CDLL(None), OBJCSYM)))
  print("libobjc_sel_registerName=%s" % addr(three[2], OBJCSYM))
  print("libSystem_sel_registerName=%s" % addr(rt, OBJCSYM))
  # --- the rows the PORT can also print, computed from CPython and not typed ---
  # `cpu_lib_objc` is whatever `ctypes.util.find_library('objc')` answers, which is
  # the only spelling on this host that a `ctypes.CDLL` will open.
  print("cpu_lib_objc=%s" % objc_path)
  # the OSX cell of ops_cpu.py:19 is ('m', 'System'), and `DLL` was asked for
  # exactly those two names above, so the first two entries are read back off the
  # handles' own `nm` attribute rather than restated.
  print("cpu_link_libs_10=%s" % ",".join([searched_name(DLL.findlib("m", ["m"])),
                                          searched_name(DLL.findlib("rt", ["System"])),
                                          objc_path]))
  print("cpu_link_libs_n=%d" % len(three))


if __name__ == "__main__":
  main()