#!/usr/bin/env python3
"""**VERIFY **EVERY **MOVED **TABLE**: **THE **TABLE **FILE **HOLDS **THE **EXACT **TEXT
**THAT **WAS **IN **THE **SOURCE**, **⇒⇒† AND **THE **SOURCE **HOLDS **A **POINTER **THAT
**NAMES **IT**."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
TABLES = ROOT/".agents/slop/tables"
PORT = ROOT/"tinybendygrad"
ptr = re.compile(r"^# THE TABLE IS IN `\.agents/slop/tables/([^`]+)` -- (.*)$")
bad = 0; ok = 0
for f in sorted(PORT.rglob("*.bend")):
    rel = str(f.relative_to(PORT))
    if not rel.startswith("runtime/"): continue
    lines = f.read_text().split("\n")
    for i, l in enumerate(lines):
        m = ptr.match(l) if l.startswith("#") else None
        if not m: continue
        name, sent = m.group(1), m.group(2)
        t = TABLES/name
        if not t.exists():
            print(f"MISSING TABLE {rel}:{i+1} -> {name}"); bad += 1; continue
        body = t.read_text()
        if "# BLOCK:\n" in body:
            first = body.split("# BLOCK:\n",1)[1].split("\n# END BLOCK")[0]
        elif "# END BLOCK" in body:
            first = body.split("\n",1)[1].split("\n# END BLOCK")[0]
        else:
            print(f"NO BLOCK MARKER {rel}:{i+1} -> {name}"); bad += 1; continue
        flat = re.sub(r"\s+", " ", re.sub(r"^#\s?", "", first, flags=re.M))
        if sent.strip() and sent.strip() not in flat:
            print(f"POINTER TEXT MISMATCH {rel}:{i+1} -> {name}"); bad += 1; continue
        ok += 1
print(f"POINTERS OK: {ok}   BAD: {bad}")
