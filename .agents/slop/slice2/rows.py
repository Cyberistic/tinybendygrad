#!/usr/bin/env python3
"""Read the pin-cite gate's OWN rows for a frozen tree and print the rows for the
named files. Loaded BY PATH -- the instrument is not re-implemented here."""
import importlib.util, sys, csv
from pathlib import Path
ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
spec = importlib.util.spec_from_file_location("pc", ROOT/"gates/pin-cite-gate.py")
pc = importlib.util.module_from_spec(spec); spec.loader.exec_module(pc)
tree = Path(sys.argv[1])
want = set(sys.argv[2:])
census = pc.load_census()
up, local = pc.collect(census, tree)
pin = pc.declared_pin()
corpus = census.Upstream(pc.UPSTREAM)
pc.resolve_all(census, up, corpus, pin)
for c in up:
  if c["rel"] in want:
    print("%-58s %-46s %s  at_pin=%-5s claim=%s present=%s" % (
      c["rel"], c["subject"], c["lo"], c["at_pin"], ",".join(c["toks"]), ",".join(c["present"])))
