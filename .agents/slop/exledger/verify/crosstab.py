"""Per-file cross-tab: my verdict vs the ledger's disposition. Plus a corrected
transitive pass (comment-stripped, same stripper as the main pass)."""
import collections, json, pathlib

here = pathlib.Path(__file__).parent
rows = {r.split("\t")[0]: r.split("\t") for r in (here.parent / "examples.manifest.rows").read_text().splitlines()[1:]}
V = json.loads((here / "my-verdict.json").read_text())["verdicts"]

def strip(path, text):
    ext = path.rsplit(".", 1)[-1] if "." in path.rsplit("/", 1)[-1] else ""
    keep = []
    for i, l in enumerate(text.splitlines()):
        s = l.strip()
        if not s or s.startswith(("#", "//", "/*", "*")):
            continue
        keep.append((i + 1, l))
    return keep

frames = {}
for f in (here / "blobs.bin").read_bytes().split(b"\x00FILE ")[1:]:
    head, _, body = f.partition(b"\n")
    frames[head.decode().split()[0]] = body.decode("utf-8", "replace")

api = {p for p, v in V.items() if v == "API"}
stems = collections.defaultdict(list)
for p in api:
    stems[p.rsplit("/", 1)[-1]].append(p)

trans = {}
for path, text in frames.items():
    if path in api or path.rsplit(".", 1)[-1] in ("md", "json", "html", "css", "png", "ttf", "woff2", "svg", "map", "gz"):
        continue
    hits = []
    for i, l in strip(path, text):
        if ".py" not in l:
            continue
        import re
        for m in re.finditer(r"[\w./-]+\.py\b", l):
            fn = m.group(0).split("/")[-1]
            if fn in stems:
                hits.append((i, l.strip()[:140], stems[fn][0]))
    if hits:
        trans[path] = hits[:2]

print(f"=== CROSS-TAB: my verdict (rows) x ledger disposition (cols) ===")
ct = collections.Counter((V[p], rows[p][3]) for p in rows)
verdicts = ["API", "NAME-IN-CODE", "NONE"]
disps = ["PORT", "MINIMAL", "VERBATIM_COPY", "MINIMAL_COPY", "ALREADY_BEND"]
print(f"{'':14s}" + "".join(f"{d:>14s}" for d in disps))
for v in verdicts:
    print(f"{v:14s}" + "".join(f"{ct[(v,d)]:>14d}" for d in disps))

print(f"\n=== FILES I JUDGE API THAT THE LEDGER DID NOT MARK PORT ({len([p for p in api if rows[p][3]!='PORT'])}) ===")
for p in sorted(api):
    if rows[p][3] != "PORT":
        print(f"  {p}  [ledger {rows[p][3]}: {rows[p][4]}]")
        for i, l in strip(p, frames[p]):
            if "tinygrad" in l:
                print(f"      {i}: {l.strip()[:150]}")
                break

print(f"\n=== FILES THE LEDGER MARKED PORT THAT I DO NOT JUDGE API ({len([p for p in rows if rows[p][3]=='PORT' and V[p]!='API'])}) ===")
for p in sorted(rows):
    if rows[p][3] == "PORT" and V[p] != "API":
        print(f"  {p}  [my verdict {V[p]}]")

print(f"\n=== TRANSITIVE (runs a population file that reaches the API): {len(trans)} ===")
tc = collections.Counter(rows[p][3] for p in trans)
print(f"  by ledger disposition: {dict(tc)}")
for p in sorted(trans):
    i, l, dep = trans[p][0]
    print(f"  [{rows[p][3]:12s}] {p}")
    print(f"        {i}: {l}   ->  {dep}")

(here / "cross-tab.rows").write_text(
    "my_verdict\tledger_disposition\tn\n" +
    "".join(f"{v}\t{d}\t{ct[(v,d)]}\n" for v in verdicts for d in disps if ct[(v, d)]))
(here / "transitive.json").write_text(json.dumps(trans, indent=1))