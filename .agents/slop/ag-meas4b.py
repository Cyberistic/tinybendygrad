#!/usr/bin/env python3
"""MEASUREMENT 4, final form: the COUNT of autogen-sourced constants that have
caused a real port bug, taken from the repo's own records and re-checked where
a record gives enough information to re-check.

The project-wide figure the repo records is 533 numeric constant defs across 7
committed device/renderer files. This script counts the DEFECTS, not the
population, and attributes each to its source file in autogen/.
"""
import os, re
ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"

RECORDS = [
 # (count, source of the constant, what went wrong, where it is recorded)
 (33, "tinygrad/runtime/autogen/nv_570.py (+ nv_580/nv_610, nv.py)",
     "ops_nv.bend: 33 of 219 hand-typed constants WRONG behind 590 green rows; "
     "all eleven CLASS_* ids among them, so the class ladder never matched a real GPU",
     ".agents/TODO.md:1195-1201"),
 (1, "tinygrad/runtime/autogen/bnxt.py", "BNXT_VENDOR shipped as 5356 where the header says 5348",
     ".agents/TODO.md:1745"),
 (2, "tinygrad/runtime/autogen/libusb.py",
     "SENTINEL_MAGIC 1363148800 vs 0x51000000 = 1358954496; FAST_P1_MASK 215 vs 0b11011111 = 223",
     ".agents/TODO.md:1757-1758"),
 (1, "tinygrad/runtime/autogen/libusb.py",
     "E_SYNTH / enum_libusb_class_code had the wrong entry count (the real table has 19)",
     ".agents/TODO.md:1786-1791"),
 (1, "tinygrad/runtime/autogen/libusb.py",
     "struct_libusb_transfer field ORDER transposed relative to the header, "
     "invisible to a count-based gate",
     ".agents/TODO.md:1745-1749 (the usb.py:350-351 by-NAME access)"),
]
print("### autogen-sourced constants that caused a REAL port bug, per this repo's records")
tot = 0
for n, src, what, where in RECORDS:
    tot += n
    print(f"\n  {n:3d}  from {src}")
    print(f"        {what}")
    print(f"        recorded at {where}")
print(f"\nTOTAL ATTRIBUTABLE TO autogen/: {tot}")
print()
print("For contrast, the POPULATION the repo records: 533 numeric constant defs")
print("across ops_nv 222, ops_metal 106, ops_cl 103, ops_webgpu 67,")
print("ops_cpu_null 29, cstyle 6, tc_ptx 6 (.agents/TODO.md:1213-1216).")
print()
print("NOTE WHAT IS NOT IN THE COUNT: the two nv/ip `nv_query_litter` and the")
print("renderer/cstyle 17-of-215 are NOT autogen constants (nv/ip is a hand")
print("oracle over ops_nv.py; cstyle is not an autogen binding), so they are")
print("the WRONG-KIND evidence and are excluded deliberately.")
