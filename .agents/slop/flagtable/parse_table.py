import re, os, json
from pathlib import Path
from collections import Counter

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
AGENTS = ROOT / "AGENTS.md"
TINYGRAD = ROOT / "tinygrad"

text = AGENTS.read_text()
lines = text.split("\n")

current_section = None
table_rows = []

for i, line in enumerate(lines, 1):
    m = re.match(r'^### (.+)$', line)
    if m:
        current_section = m.group(1).strip()
    # Match table rows: | `FLAG` | default | desc |
    # Also match compound: | `USE_TC` / `TC` | default | desc |
    m = re.match(r'^\|\s*`([A-Z0-9_]+)`(?:\s*/\s*`([A-Z0-9_]+)`)?\s*\|([^|]+)\|([^|]+)\|', line)
    if m:
        flag = m.group(1)
        alias = m.group(2)  # e.g. TC for USE_TC
        default = m.group(3).strip()
        desc = m.group(4).strip()
        table_rows.append({
            "flag": flag,
            "alias": alias,
            "table_default": default,
            "desc": desc,
            "section": current_section,
            "line": i
        })

print(f"Total table rows: {len(table_rows)}")
sec_counts = Counter(r["section"] for r in table_rows)
for s, c in sec_counts.items():
    print(f"  {s}: {c}")

# Show compound rows
for r in table_rows:
    if r["alias"]:
        print(f"  COMPOUND: line {r['line']}: {r['flag']} / {r['alias']}")

out = ROOT / ".agents" / "slop" / "flagtable"
out.mkdir(parents=True, exist_ok=True)
(out / "table_rows.json").write_text(json.dumps(table_rows, indent=2))
print(f"\nSaved to {out}/table_rows.json")
