import re, os, json
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
TINYGRAD = ROOT / "tinygrad"

# Find all ContextVar("FLAG", default) and getenv("FLAG", default) declarations
# Pattern: ContextVar("FLAG", default_value) or getenv("FLAG", default)
decl_re = re.compile(r'(?:ContextVar|getenv)\(\s*"([A-Z0-9_]+)"\s*,\s*([^)]+)\)')

declarations = {}  # flag -> list of (file, line, default_expr, full_match)

for pyfile in sorted(TINYGRAD.rglob("*.py")):
    try:
        content = pyfile.read_text()
    except:
        continue
    for i, line in enumerate(content.split("\n"), 1):
        for m in decl_re.finditer(line):
            flag = m.group(1)
            default_expr = m.group(2).strip()
            relpath = str(pyfile.relative_to(ROOT))
            if flag not in declarations:
                declarations[flag] = []
            declarations[flag].append({
                "file": relpath,
                "line": i,
                "default_expr": default_expr,
                "context": line.strip()
            })

print(f"Total flags with declarations: {len(declarations)}")
for flag in sorted(declarations.keys()):
    decls = declarations[flag]
    print(f"\n{flag}:")
    for d in decls:
        print(f"  {d['file']}:{d['line']}  default={d['default_expr']}")
        print(f"    {d['context'][:120]}")

# Save
out = ROOT / ".agents" / "slop" / "flagtable"
(out / "declarations.json").write_text(json.dumps(declarations, indent=2))
