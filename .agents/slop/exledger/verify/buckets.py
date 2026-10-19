"""Check the ledger README's two numeric claims, and enumerate every bucket that is
not decided by 'reaches the API', with the evidence that decides it."""
import collections, pathlib, re

here = pathlib.Path(__file__).parent
rows = {r.split("\t")[0]: r.split("\t") for r in (here.parent / "examples.manifest.rows").read_text().splitlines()[1:]}
frames = {}
for f in (here / "blobs.bin").read_bytes().split(b"\x00FILE ")[1:]:
    head, _, body = f.partition(b"\n")
    frames[head.decode().split()[0]] = body.decode("utf-8", "replace")
NAME = re.compile(r"tinygrad", re.I)
ext = lambda p: p.rsplit(".", 1)[-1] if "." in p.rsplit("/", 1)[-1] else "(none)"

md = [p for p in rows if ext(p) == "md"]
md_names = [p for p in md if NAME.search(frames[p])]
print(f"README CLAIM A: '24 of the 26 .md reference it; 2 do not'")
print(f"  measured: {len(md)} .md rows, {len(md_names)} name tinygrad, {len(md)-len(md_names)} do not")
print(f"  the {len(md)-len(md_names)} that do not: {[p for p in md if not NAME.search(frames[p])]}")
print(f"  README says 2 -> {'HOLDS' if len(md)-len(md_names)==2 else 'FALSE, it is '+str(len(md)-len(md_names))}")

sh = [p for p in rows if ext(p) == "sh"]
import json
V = json.loads((here / "my-verdict.json").read_text())["verdicts"]
sh_api = [p for p in sh if V[p] == "API"]
sh_name = [p for p in sh if NAME.search(frames[p])]
print(f"\nREADME CLAIM B: '117 of the 119 .sh files need no tinygrad API; the other 2 do'")
print(f"  measured: {len(sh)} .sh rows; REACH the API (AST/lexical): {len(sh_api)}")
print(f"  NAME tinygrad anywhere: {len(sh_name)} -> {[p.split('/')[-1]+':'+rows[p][3] for p in sh_name]}")
print(f"  the 'other 2' are: {[ (p, rows[p][3], rows[p][4]) for p in sh_name ]}")
print(f"  README says 2 REACH the API -> {'HOLDS' if len(sh_api)==2 else 'FALSE, it is '+str(len(sh_api))}")

print(f"\n=== BUCKETS NOT DECIDED BY 'reaches the API' ===")
for disp in ("MINIMAL", "VERBATIM_COPY", "MINIMAL_COPY", "ALREADY_BEND"):
    sel = sorted(p for p in rows if rows[p][3] == disp)
    e = collections.Counter(ext(p) for p in sel)
    print(f"\n-- {disp} n={len(sel)}  by ext: {dict(e)}")
    if disp in ("MINIMAL", "ALREADY_BEND"):
        for p in sel:
            print(f"   {p}   reason={rows[p][4]!r}")
    if disp == "VERBATIM_COPY":
        named = [p for p in sel if NAME.search(frames[p])]
        print(f"   VERBATIM_COPY rows that DO contain the string 'tinygrad': {len(named)} of {len(sel)}")
        for p in named:
            ln = next(l.strip() for l in frames[p].splitlines() if NAME.search(l))
            print(f"     {p}\n         reason={rows[p][4]!r}\n         {ln[:140]}")
    if disp == "MINIMAL_COPY":
        for p in sel:
            print(f"   {p}   reason={rows[p][4]!r}")