"""Recon: every population file that names 'tinygrad' ANYWHERE, with the regex verdict."""
import pathlib, re

here = pathlib.Path(__file__).parent
LEDGER = re.compile(r"\b(from|import)\s+tinygrad|\btinygrad\.")
NAME = re.compile(r"tinygrad", re.IGNORECASE)

frames = (here / "blobs.bin").read_bytes().split(b"\x00FILE ")
out = []
for f in frames[1:]:
    head, _, body = f.partition(b"\n")
    path, kind, size = head.decode().split()
    text = body.decode("utf-8", "replace")
    lines = text.splitlines()
    hits = [i + 1 for i, l in enumerate(lines) if NAME.search(l)]
    rx = [i for i, l in enumerate(lines) if LEDGER.search(l)]
    out.append((path, kind, int(size), len(hits), len(rx), hits[:6]))

rows = [r for r in out if r[3]]
with (here / "names-tinygrad.rows").open("w") as fh:
    for p, k, s, n, r, h in rows:
        fh.write(f"{p}\t{k}\t{s}\tany={n}\tregex={r}\tfirst={','.join(map(str,h))}\n")
print(f"population={len(out)}  naming tinygrad anywhere={len(rows)}")
print(f"naming it but regex-blind={len([r for r in rows if r[3] and not r[4]])}")
print(f"regex-hit={len([r for r in out if r[4]])}  no-name-at-all={len([r for r in out if not r[3]])}")