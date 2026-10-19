"""Print the matching lines for the regex-blind-but-naming files."""
import pathlib, re, sys

here = pathlib.Path(__file__).parent
NAME = re.compile(r"tinygrad", re.IGNORECASE)
want = {l.split("\t")[0] for l in (here / "names-tinygrad.rows").read_text().splitlines()
        if l.split("\t")[3].split("=")[1] != "0" and l.split("\t")[4].split("=")[1] == "0"}
for f in (here / "blobs.bin").read_bytes().split(b"\x00FILE ")[1:]:
    head, _, body = f.partition(b"\n")
    path = head.decode().split()[0]
    if path not in want:
        continue
    print(f"\n===== {path} =====")
    for i, l in enumerate(body.decode("utf-8", "replace").splitlines()):
        if NAME.search(l):
            print(f"  {i+1}: {l.strip()[:190]}")