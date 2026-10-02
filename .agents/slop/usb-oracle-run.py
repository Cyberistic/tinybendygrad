#!/usr/bin/env python3
"""Run every usb oracle in order and concatenate their rows."""
import io, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
for o in ("usb-oracle.py", "usb-oracle-arith.py", "usb-oracle-trace.py", "usb-oracle-strings.py"):
    sys.path.insert(0, os.path.dirname(HERE))
    g = {"__name__": "__main__", "__file__": os.path.join(HERE, o)}
    buf = io.StringIO()
    old = sys.stdout
    sys.stdout = buf
    try:
        exec(compile(io.open(os.path.join(HERE, o)).read(), o, "exec"), g)
    finally:
        sys.stdout = old
    sys.stdout.write(buf.getvalue())
