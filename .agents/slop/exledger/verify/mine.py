"""Independent classification. AST for .py, comment-stripped lexical for the rest,
plus a TRANSITIVE pass: a script that runs a script that reaches the API."""
import ast, json, pathlib, re, collections

here = pathlib.Path(__file__).parent
frames = {}
for f in (here / "blobs.bin").read_bytes().split(b"\x00FILE ")[1:]:
    head, _, body = f.partition(b"\n")
    path = head.decode().split()[0]
    frames[path] = body.decode("utf-8", "replace")

def code_lines(text, ext):
    """Lines that are EXECUTABLE, not comments."""
    if ext == "py":
        out = []
        for i, l in enumerate(text.splitlines()):
            s = l.strip()
            if not s or s.startswith("#"):
                continue
            out.append(i + 1)
        return out
    if ext in ("sh", "yaml", "yml", "gitignore"):
        return [i + 1 for i, l in enumerate(text.splitlines())
                if l.strip() and not l.strip().startswith("#")]
    if ext in ("js", "ts"):
        out = []
        for i, l in enumerate(text.splitlines()):
            s = l.strip()
            if not s or s.startswith(("//", "*", "/*")):
                continue
            out.append(i + 1)
        return out
    return [i + 1 for i, l in enumerate(text.splitlines())]

TG = re.compile(r"\btinygrad\b")
DYN = re.compile(r"""(?:__import__\s*\(\s*['"]tinygrad|import_module\s*\(\s*['"]tinygrad|"""
                 r"""\bimport\s+tinygrad\b|\bfrom\s+tinygrad\b)""")

def py_api(text):
    """AST truth for a .py file: does it bind or call the tinygrad package?"""
    ev = []
    try:
        tree = ast.parse(text)
    except SyntaxError as e:
        return ["UNPARSEABLE:" + str(e)], None
    tg_alias = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                if a.name.split(".")[0] == "tinygrad":
                    tg_alias.add(a.asname or a.name.split(".")[0])
                    ev.append((n.lineno, f"import {a.name}"))
        elif isinstance(n, ast.ImportFrom):
            if n.module and n.module.split(".")[0] == "tinygrad":
                ev.append((n.lineno, f"from {n.module} import ..."))
    for n in ast.walk(tree):
        if isinstance(n, ast.Name) and n.id in tg_alias:
            ev.append((n.lineno, f"use of bound name {n.id}"))
    return ev, tg_alias

verdicts, evidence = {}, {}
for path, text in frames.items():
    ext = path.rsplit(".", 1)[-1] if "." in path.rsplit("/", 1)[-1] else ""
    lines = text.splitlines()
    body = "\n".join(lines[i - 1] for i in code_lines(text, ext))
    ev, _ = (py_api(text) if ext == "py" else ([], None))
    if ev:
        verdicts[path] = "API"
        evidence[path] = ev[:4]
        continue
    kept = [i for i in code_lines(text, ext)]
    dyn = [(i, lines[i - 1].strip()) for i in kept if DYN.search(lines[i - 1])]
    if dyn:
        verdicts[path] = "API"
        evidence[path] = dyn[:4]
        continue
    if TG.search(body):
        verdicts[path] = "NAME-IN-CODE"
        evidence[path] = [(i, l.strip()) for i, l in enumerate(lines, 1) if TG.search(l)][:4]
        continue
    verdicts[path] = "NONE"

# transitive: a non-python file that EXECUTES a population file already judged API
api = {p for p, v in verdicts.items() if v == "API"}
stems = collections.defaultdict(list)
for p in api:
    stems[p.rsplit("/", 1)[-1]].append(p)
trans = {}
for path, text in frames.items():
    if path in api or path.endswith((".md", ".json", ".html", ".css")):
        continue
    hits = []
    for i, l in enumerate(text.splitlines(), 1):
        s = l.strip()
        if not s or s.startswith("#"):
            continue
        if not (".py" in l or TG.search(l)):
            continue
        for m in re.finditer(r"[\w./-]+\.py\b", l):
            fn = m.group(0).split("/")[-1]
            if fn in stems:
                hits.append((i, s[:150]))
        if re.search(r"python3?\s+-c\b", l) and TG.search(l):
            hits.append((i, s[:150]))
    if hits:
        trans[path] = hits[:3]

print("=== MY COUNTS (mechanism, not disposition) ===")
for k, v in sorted(collections.Counter(verdicts.values()).items()):
    print(f"  {k:14s} {v}")
print(f"\n=== TRANSITIVE (runs a file that reaches the API): {len(trans)} ===")
for p, h in sorted(trans.items()):
    print(f"  {p}  [ledger says: see manifest]")
    for i, l in h:
        print(f"      {i}: {l}")

(here / "my-verdict.json").write_text(json.dumps({"verdicts": verdicts, "transitive": trans}, indent=1))
(here / "my-evidence.json").write_text(json.dumps(evidence, indent=1))