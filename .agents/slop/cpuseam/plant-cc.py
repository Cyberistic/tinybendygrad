#!/usr/bin/env python3
"""plant-cc.py -- THE PLANT, AS A `cc` WRAPPER.

THE SEAM TAKES THE COMPILER AS AN ARGUMENT (`Cpu.compile(src, argv)`, whose
argv BEGINS WITH THE COMPILER), WHICH IS UPSTREAM's OWN SHAPE:
`getenv("CC", 'clang')` (`tinygrad/runtime/support/compiler_cpu.py:21`).  ⇒ THE
PLANT IS THE `cc`.

IT REWRITES ONE TOKEN OF THE C SOURCE ON STDIN AND THEN EXECS THE REAL `cc`
WITH THE SAME ARGUMENTS AND THE PATCHED SOURCE ON STDIN -- SO THE ARGV IS
EXACTLY THE SEAM's ARGV, AND THE ONLY DIFFERENCE IS THE SOURCE'S BYTES.

IT REFUSES (rc=1, MESSAGE ON STDERR) IF THE TOKEN IS ABSENT, BECAUSE A PLANT
THAT SILENTLY DID NOTHING WOULD BE A ROW THAT CANNOT GO RED.

THE TOKEN COMES FROM `PLANT_OLD` AND THE REPLACEMENT FROM `PLANT_NEW`; THE REAL
COMPILER COMES FROM `PLANT_CC` (DEFAULT `/usr/bin/cc`).

⇒ MEASURED: THE FIRST VERSION READ STDIN AND WROTE THE PATCHED SOURCE TO ITS
OWN STDOUT, SO THE REAL `cc` FOUND AN EMPTY STDIN AND THE SEAM REPORTED
"cc failed" WITH rc=10. THE SOURCE MUST GO BACK ON *STDIN*, AND A TEMP FILE
THAT IS UNLINKED BEFORE THE EXEC IS THE WAY: THE FD STAYS VALID AND NOTHING IS
LEFT BEHIND.
"""
import os
import sys
import tempfile

OLD = os.environ.get("PLANT_OLD", "").encode()
NEW = os.environ.get("PLANT_NEW", "").encode()
CC = os.environ.get("PLANT_CC", "/usr/bin/cc")

data = sys.stdin.buffer.read()
if not OLD:
    sys.stderr.write("plant-cc: PLANT_OLD is unset\n")
    sys.exit(1)
if OLD not in data:
    sys.stderr.write(f"plant-cc: the token {OLD!r} is absent from the source\n")
    sys.exit(1)
data = data.replace(OLD, NEW)

fd, path = tempfile.mkstemp(prefix="plantcc", suffix=".c")
os.write(fd, data)
os.unlink(path)
os.lseek(fd, 0, os.SEEK_SET)
os.dup2(fd, 0)
if os.environ.get("PLANT_DUMP"):
    with open(os.environ["PLANT_DUMP"], "wb") as f:
        f.write(data)
os.execv(CC, [CC] + sys.argv[1:])
