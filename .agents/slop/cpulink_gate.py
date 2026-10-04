#!/usr/bin/env python3
"""THE GATE for `link_libs` (`tinybendygrad/runtime/ops_cpu.bend`, upstream
ops_cpu.py:19/21). Two lanes and a set of assertions that are NOT lane rows.

  1. BEND     `./bin/bend tinybendygrad/runtime/ops_cpu.bend` -- 134 rows.
  2. CPYTHON  `.venv/bin/python .agents/slop/cpulink_oracle.py` -- CALLS
              `tinygrad.runtime.support.c.DLL` and
              `tinygrad.runtime.support.elf.link_sym` and `ctypes.util`.

The SHARED rows are the three the port can also compute, and each is diffed:

    cpu_lib_objc         the objc library the loader can actually be handed
    cpu_link_libs_10     the OSX cell of the link set, joined, so ORDER is pinned
    cpu_link_libs_n      how many entries it has

Everything else in the oracle is EVIDENCE, not a port row, because a Bend port
cannot dlopen anything -- it is a pure port and that is not a defect of it. The
evidence is checked as ASSERTIONS, and an assertion that stops holding fails the
gate:

    two_sel_registerName            MUST raise -- this is bug 2, live
    three_dummy_sel_registerName    MUST ALSO raise -- `DLL('objc','objc')` is a
                                     dummy (findlib answers None), so a third entry
                                     spelled as a NAME would leave the bug intact
    three_sel_registerName          MUST resolve
    same_as_global                  MUST be True -- the fix finds the libobjc dyld
                                     already has instead of dlopening a second one
    libSystem_sel_registerName      MUST NOT resolve -- libobjc is not in libSystem
    findlib_objc                    MUST be None -- why the row is a path
    is_file_libSystem               MUST be False -- the shared-cache fact, and the
                                     reason `findlib_rt` matters

    .venv/bin/python .agents/slop/cpulink_gate.py
    .venv/bin/python .agents/slop/cpulink_gate.py --mutate
"""
import difflib
import patch_not_apply as PNA
import os
import subprocess  # noqa: F401  (documented: see the note below)
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PORT = os.path.join(ROOT, "tinybendygrad/runtime/ops_cpu.bend")
OUT = os.path.join(HERE, "cpulink_gate.out")
ERR = os.path.join(HERE, "cpulink_gate.err")

SHARED = ("cpu_lib_objc", "cpu_link_libs_10", "cpu_link_libs_n")

MUST = {
    "two_sel_registerName": "RAISES:Attempting to relocate against an undefined symbol sel_registerName",
    "two_objc_msgSend": "RAISES:Attempting to relocate against an undefined symbol objc_msgSend",
    "three_dummy_sel_registerName": "RAISES:Attempting to relocate against an undefined symbol sel_registerName",
    "three_objc_msgSend": "ADDR",
    "same_as_global": "True",
    "libSystem_sel_registerName": "UNRESOLVED",
    "findlib_objc": "None",
    "is_file_libSystem": "False",
    "is_file_libobjc": "False",
}

MIN_ROWS = 120


def run(cmd):
  rc = os.system(" ".join(cmd) + " > " + OUT + " 2> " + ERR)
  out = open(OUT).read()
  err = open(ERR).read() if os.path.exists(ERR) else ""
  return rc, out, err


def kv(text):
  d = {}
  for line in text.strip().split("\n"):
    if "=" in line and not line.startswith("#"):
      k, v = line.split("=", 1)
      d[k] = v
  return d


def bend_rows():
  for _ in range(5):
    rc, out, _err = run(["./bin/bend", PORT])
    if rc == 0 and out.strip() and not out.startswith("SOME PROOFS FAIL"):
      break
  return out


def verify():
  bend = kv(bend_rows())
  rc, py, err = run([sys.executable, os.path.join(HERE, "cpulink_oracle.py")])
  if rc != 0:
    sys.exit("ORACLE EXITED %d -- its output is not evidence\n%s" % (rc, err[:400]))
  oracle = kv(py)
  print("bend rows carrying '=' = %d" % len(bend))
  if len(bend) < MIN_ROWS:
    sys.exit("BEND LANE EMITTED %d ROWS -- a zero-row lane is not a pass" % len(bend))
  bad = []
  for k in SHARED:
    if k not in bend or k not in oracle:
      print("MISSING %s (bend=%r oracle=%r)" % (k, bend.get(k), oracle.get(k)))
      bad.append(k)
    elif bend[k] != oracle[k]:
      print("DIVERGES %s: port %r oracle %r" % (k, bend[k], oracle[k]))
      bad.append(k)
    else:
      print("AGREES %s=%s" % (k, bend[k]))
  for k, want in MUST.items():
    got = oracle.get(k)
    ok = (got.startswith("0x") if want == "ADDR" else got == want)
    print("%-30s %s  got=%r" % (k, "HOLDS" if ok else "VIOLATED", got))
    if not ok:
      bad.append(k)
  if oracle.get("findlib_rt"):
    print("NOTE findlib_rt=%s -- libSystem IS reachable, via the framework symlink"
          % oracle["findlib_rt"])
  if bad:
    sys.exit("GATE FAILED on %s" % ",".join(bad))
  print("LINK-SET GATE PASSES: %d shared rows agree byte for byte, %d evidence "
        "assertions hold" % (len(SHARED), len(MUST)))
  return 0


MUTATIONS = [
    ("N1  libobjc dropped from the link set (the upstream two-entry set)",
     "  [cpu.lib_m(), cpu.rt_lib_name(osx, win), cpu.lib_objc()]",
     "  [cpu.lib_m(), cpu.rt_lib_name(osx, win)]"),
    ("N2  libobjc FIRST instead of last (`link_sym` returns the first hit, so this",
     "  [cpu.lib_m(), cpu.rt_lib_name(osx, win), cpu.lib_objc()]",
     "  [cpu.lib_objc(), cpu.lib_m(), cpu.rt_lib_name(osx, win)]"),
    ("N3  libobjc named instead of pathed (`DLL('objc','objc')` never opens)",
     'def cpu.lib_objc() -> String: "/usr/lib/libobjc.dylib"',
     'def cpu.lib_objc() -> String: "objc"'),
    ("N4  libobjc last in place of libm (libm lost)",
     "  [cpu.lib_m(), cpu.rt_lib_name(osx, win), cpu.lib_objc()]",
     "  [cpu.rt_lib_name(osx, win), cpu.lib_objc()]"),
    ("N5  the objc path's directory dropped",
     'def cpu.lib_objc() -> String: "/usr/lib/libobjc.dylib"',
     'def cpu.lib_objc() -> String: "/libobjc.dylib"'),
]


def mutate():
  src = open(PORT).read()
  base = kv(bend_rows())
  print("baseline bend rows = %d" % len(base))
  moved, zeros = [], []
  for name, old, new in MUTATIONS:
    if src.count(old) != 1:
      print("%-70s %s (anchor x%d)" % (name, PNA.not_applied(), src.count(old)))
      zeros.append((name, PNA.not_applied("anchor x%d" % src.count(old))))
      continue
    open(PORT, "w").write(src.replace(old, new))
    got = kv(bend_rows())
    open(PORT, "w").write(src)
    names = [k for k in set(list(base) + list(got))
             if base.get(k) != got.get(k)]
    if names:
      print("%-70s moved %3d  %s" % (name, len(names), ",".join(sorted(names)[:6])))
      moved.append((name, len(names)))
    else:
      print("%-70s MOVED NOTHING" % name)
      zeros.append((name, "0 rows"))
  print("\n%d mutations moved rows, %d moved none" % (len(moved), len(zeros)))
  for n, w in zeros:
    print("  ZERO: %s  (%s)" % (n, w))


if __name__ == "__main__":
  if "--mutate" in sys.argv:
    mutate()
  else:
    sys.exit(verify())