"""Targeted hunt for the SPECIFIC false-negative shapes the brief names.
One line per hit; a shape with zero hits is a result, not an absence."""
import pathlib, re, json, collections

here = pathlib.Path(__file__).parent
frames = {}
for f in (here / "blobs.bin").read_bytes().split(b"\x00FILE ")[1:]:
    head, _, body = f.partition(b"\n")
    frames[head.decode().split()[0]] = body.decode("utf-8", "replace")
rows = {r.split("\t")[0]: r.split("\t") for r in (here.parent / "examples.manifest.rows").read_text().splitlines()[1:]}

SHAPES = {
  "import-split-across-lines": re.compile(r"(?:^|\n)\s*(?:from|import)\s*\\\s*\n\s*tinygrad"),
  "line-continuation-import":  re.compile(r"(?:from|import)\s+\\\s*\n"),
  "dynamic-import_module":     re.compile(r"import_module\s*\(\s*['\"][^'\"]*tinygrad"),
  "dunder-__import__":         re.compile(r"__import__\s*\(\s*['\"][^'\"]*tinygrad"),
  "getattr-on-builtins":       re.compile(r"getattr\s*\(\s*__import__"),
  "exec-of-constructed":       re.compile(r"\b(?:exec|eval)\s*\("),
  "shell-python-c-tinygrad":   re.compile(r"python3?\s+-c\b[^\n]*tinygrad"),
  "js-require-tinygrad":       re.compile(r"""(?:require\(|^import\s)[^\n]*['"][^'"]*tinygrad"""),
  "js-runtime-path":           re.compile(r"""['"][^'"]*(?:ops_webgpu|ops_js|ops_cpu|renderer/wgsl|runtime/ops_)"""),
  "import-parent-pkg":         re.compile(r"(?:^|\n)\s*from\s+tinygrad\b"),
  "numpy-only-no-tg":          re.compile(r"(?:^|\n)\s*(?:from|import)\s+(\w+)"),
}

hits = collections.defaultdict(list)
for p, t in frames.items():
    for i, l in enumerate(t.splitlines(), 1):
        for name, rx in SHAPES.items():
            if name == "numpy-only-no-tg":
                continue
            if rx.search(l):
                hits[name].append((p, i, l.strip()[:150], rows[p][3]))

for name in SHAPES:
    if name == "numpy-only-no-tg":
        continue
    h = hits[name]
    print(f"\n### {name}: {len(h)} hit(s)")
    for p, i, l, d in h[:14]:
        print(f"  [{d:13s}] {p}:{i}: {l}")
    if len(h) > 14:
        print(f"  ... and {len(h)-14} more")

print("\n\n### WHAT EACH FILE IMPORTS (top-level roots, .py only) — the AST ground truth")
import ast, collections as C
roots = C.Counter()
for p, t in frames.items():
    if not p.endswith(".py"):
        continue
    try:
        tree = ast.parse(t)
    except SyntaxError:
        print(f"  UNPARSEABLE {p}")
        continue
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                roots[a.name.split(".")[0]] += 1
        elif isinstance(n, ast.ImportFrom) and n.module and n.level == 0:
            roots[n.module.split(".")[0]] += 1
print("  " + ", ".join(f"{k}:{v}" for k, v in roots.most_common()))