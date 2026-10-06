import re, os, json
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
TINYGRAD = ROOT / "tinygrad"
OUT = ROOT / ".agents" / "slop" / "flagtable"

table_rows = json.loads((OUT / "table_rows.json").read_text())

# Build a set of all flag names from the table
table_flags = set()
for row in table_rows:
    table_flags.add(row["flag"])
    if row.get("alias"):
        table_flags.add(row["alias"])

# For each flag, check if it appears ANYWHERE in tinygrad/ source
# This includes: variable references, getenv("FLAG") calls, string literals, etc.
read_coverage = {}

for flag in sorted(table_flags):
    pattern = rf'\b{flag}\b'
    reads = []
    for pyfile in sorted(TINYGRAD.rglob("*.py")):
        try:
            content = pyfile.read_text()
        except:
            continue
        for i, line in enumerate(content.split("\n"), 1):
            if re.search(pattern, line):
                relpath = str(pyfile.relative_to(ROOT))
                reads.append(f"{relpath}:{i}")
    read_coverage[flag] = reads

# Print summary
print("=== READ COVERAGE ===")
read_count = 0
not_read = []
for flag in sorted(table_flags):
    if read_coverage[flag]:
        read_count += 1
    else:
        not_read.append(flag)

print(f"Total table flags: {len(table_flags)}")
print(f"Found in tinygrad/: {read_count}")
print(f"NOT found: {len(not_read)}")
if not_read:
    print(f"\nFlags NOT found anywhere in tinygrad/:")
    for f in not_read:
        print(f"  {f}")

# Save
(OUT / "read_coverage.json").write_text(json.dumps(read_coverage, indent=2))
