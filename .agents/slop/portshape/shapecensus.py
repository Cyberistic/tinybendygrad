"""Port records vs upstream dataclasses: the FIELD SET, by brace-balanced parse.

The subject is a SHAPE, so the parse must be a real parse: `ast` for upstream and a
brace-balanced scan for the Bend records. A lexical regex over a record body stops at
the FIRST `}`, and a Bend record body may contain nested braces (`Maybe<&2, X>` has
none, but `List<&2, Map<&2, U32>>` does) -- so the FIRST regex UNDERCOUNTED and the
SECOND overcounted. This one balances.
"""
import ast, pathlib, re, sys

def upstream_fields():
    out = {}
    for p in pathlib.Path("tinygrad").rglob("*.py"):
        try: tree = ast.parse(p.read_text(errors="replace"))
        except SyntaxError: continue
        for n in ast.walk(tree):
            if isinstance(n, ast.ClassDef):
                f = [t.target.id for t in n.body if isinstance(t, ast.AnnAssign) and isinstance(t.target, ast.Name)]
                if f: out.setdefault(n.name, (set(f), str(p)))
    return out

def port_records():
    out = {}
    for p in pathlib.Path("tinybendygrad").rglob("*.bend"):
        txt = p.read_text(errors="replace")
        for m in re.finditer(r"^type (\w+) is Data:", txt, re.M):
            name = m.group(1)
            rm = re.search(rf"^\s*{re.escape(name)}\{{", txt[m.end():], re.M)
            if not rm: continue
            start = m.end() + rm.end() - 1
            depth = 0
            for j in range(start, len(txt)):
                if txt[j] == "{": depth += 1
                elif txt[j] == "}":
                    depth -= 1
                    if depth == 0: break
            inner = txt[start+1:j]
            # COMMENTS ARE NOT FIELDS. A `#` runs to the end of the line, and a Bend record
            # may put one BETWEEN two fields -- so the comment text was being read as a
            # field NAME (`'# (h, w) if this is an image2d buffer,'`), and a comment that
            # CONTAINED A COMMA split a field in two. Strip them BEFORE the split.
            inner = re.sub(r"#[^\n]*", "", inner)
            fields = set()
            depth = 0; cur = ""
            for ch in inner:
                if ch in "{<(": depth += 1
                elif ch in "}> )".replace(" ", ""): depth -= 1
                cur += ch
                if ch == "," and depth == 0:
                    nm = cur.split(":")[0].strip()
                    if nm: fields.add(nm)
                    cur = ""
            nm = cur.split(":")[0].strip()
            if nm: fields.add(nm)
            out.setdefault(name, (fields, str(p)))
    return out

up = upstream_fields(); port = port_records()
matched = [n for n in port if n in up]
rows = []
for n in matched:
    gone = up[n][0] - port[n][0]
    if gone: rows.append((n, sorted(gone), str(port[n][1])))
print(f"  upstream dataclasses with fields: {len(up)}")
print(f"  port `type X is Data` records   : {len(port)}")
print(f"  MATCHED by NAME                  : {len(matched)}")
print(f"  matched AND missing upstream flds: {len(rows)}")
for n, g, path in rows:
    print(f"    {n:24} missing {g}  ({path})")
