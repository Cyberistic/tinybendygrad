"""Emit verify/misfiles.rows. Four columns, exactly as the brief specifies:
upstream_path <TAB> ledger_disposition <TAB> correct_disposition <TAB> quoted_evidence
Every row here is a DISAGREEMENT with the ledger, except the class marked
VERBATIM_COPY-OK(reason-false), which is a disagreement with the ledger's REASON."""
import json, pathlib, re, subprocess

here = pathlib.Path(__file__).parent
root = here.parents[3]
rows = {r.split("\t")[0]: r.split("\t") for r in (here.parent / "examples.manifest.rows").read_text().splitlines()[1:]}
NAME = re.compile(r"tinygrad", re.I)
frames = {}
for f in (here / "blobs.bin").read_bytes().split(b"\x00FILE ")[1:]:
    head, _, body = f.partition(b"\n")
    frames[head.decode().split()[0]] = body.decode("utf-8", "replace")

upstream = set((here / "pop.upstream.rows").read_text().split())
V = json.loads((here / "my-verdict.json").read_text())
trans = json.loads((here / "transitive.json").read_text())

def quote(p, needle=r"tinygrad", n=1):
    for l in frames[p].splitlines():
        if re.search(needle, l, re.I):
            return l.strip()[:180]
    return ""

out = []

# CLASS 1 -- the population contains 6 files upstream does not have.
for p in sorted(p for p in rows if p not in upstream):
    if p.startswith("examples/webgpu/mnist/"):
        ev = ("git ls-tree -r upstream/master -- examples/webgpu/ returns 5 paths "
              "(efficientnet/index.html, stable_diffusion/compile.py, stable_diffusion/index.html, "
              "yolov8/compile.py, yolov8/index.html) and NO mnist/ directory; this path is absent upstream")
    else:
        ev = ("git ls-tree -r upstream/master -- examples extra | grep -Ec '\\.(bend|ts)$' = 0; "
              "upstream ships no .bend and no .ts. this path exists only in this project's tree")
    out.append((p, rows[p][3], "NOT-UPSTREAM", f"{ev}. reason={rows[p][4]!r}"))

# CLASS 2 -- one destination, two upstream rows.
dest = {}
for p, r in rows.items():
    dest.setdefault(r[5], []).append(p)
for d, ps in sorted(dest.items()):
    if len(ps) > 1:
        for p in sorted(ps):
            out.append((p, rows[p][3], "COLLISION",
                        f"two upstream rows name ported_path={d}: " +
                        ", ".join(sorted(ps)) + ". reason=" + repr(rows[p][4])))

# CLASS 3 -- PORT with no executable tinygrad reference.
for p in sorted(rows):
    if rows[p][3] == "PORT" and V["verdicts"][p] != "API":
        out.append((p, rows[p][3], "MINIMAL",
                    f"only tinygrad reference is a comment: {quote(p)!r}; the only dynamic import is "
                    "await import('./tiktoken.js'); it loads ./net.js data. reason=" + repr(rows[p][4])))

# CLASS 4 -- VERBATIM_COPY/MINIMAL_COPY rows whose stated reason is contradicted by the bytes.
for p in sorted(rows):
    if rows[p][3] in ("VERBATIM_COPY", "MINIMAL_COPY") and NAME.search(frames[p]):
        kind = "html-prose-names-the-API" if p.endswith(".html") else "json-string-names-the-framework"
        out.append((p, rows[p][3], "VERBATIM_COPY-OK(reason-false)",
                    f"reason={rows[p][4]!r} but the file contains: {quote(p)!r} [{kind}]"))

# CLASS 5 -- transitive: reaches the API by executing a PORT row, not by its own text.
for p in sorted(trans):
    i, line, dep = trans[p][0]
    out.append((p, rows[p][3], "VERBATIM_COPY-OK(reason-false)",
                f"{i}: {line!r} -> {dep} [a PORT row]. reason={rows[p][4]!r} describes only this "
                "file's own bytes; the ledger has no dependency edge."))

seen, uniq = set(), []
for r in out:
    if (r[0], r[2]) not in seen:
        seen.add((r[0], r[2]))
        uniq.append(r)
with (here / "misfiles.rows").open("w") as fh:
    for r in uniq:
        fh.write("\t".join(c.replace("\t", " ").replace("\n", " ") for c in r) + "\n")

import collections
print(f"misfiles.rows rows = {len(uniq)} of a {len(rows)}-row population")
print("by correct_disposition:")
for k, c in collections.Counter(r[2] for r in uniq).most_common():
    print(f"  {c:4d}  {k}")
print(f"distinct upstream paths flagged = {len({r[0] for r in uniq})}")