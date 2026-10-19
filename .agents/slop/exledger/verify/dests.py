"""Audit the ported_path column: collisions, escapes, extension rules, self-reference."""
import pathlib, collections

here = pathlib.Path(__file__).parent
rows = [l.rstrip("\n").split("\t") for l in (here.parent / "examples.manifest.rows").read_text().splitlines()[1:]]
print(f"rows={len(rows)} cols={len(rows[0])}")

# 1. duplicates on the destination
by_dest = collections.defaultdict(list)
for up, ext, loc, disp, reason, dest in rows:
    by_dest[dest].append((up, disp))
coll = {d: v for d, v in by_dest.items() if len(v) > 1}
print(f"\nDISTINCT ported_path = {len(by_dest)} of {len(rows)} rows")
print(f"COLLIDING destinations = {len(coll)}")
for d, v in sorted(coll.items()):
    print(f"  {d} <- {len(v)}")
    for up, disp in v:
        print(f"      {up}  [{disp}]")

# 2. destinations outside tinybendygrad/
out = [r for r in rows if not r[5].startswith("tinybendygrad/")]
print(f"\nDESTINATIONS NOT UNDER tinybendygrad/ = {len(out)}")
for r in out:
    print(f"  {r[0]} -> {r[5]}")

# 3. extension rule: does a .py upstream always land on .bend?
ext_of = lambda p: p.rsplit(".", 1)[-1] if "." in p.rsplit("/", 1)[-1] else "(none)"
bad = [(r[0], ext_of(r[0]), r[3], r[5]) for r in rows if ext_of(r[0]) == "py" and not r[5].endswith(".bend")]
print(f"\n.py upstream NOT landing on .bend = {len(bad)}")
for b in bad:
    print(f"  {b[0]}  [{b[2]}] -> {b[3]}")

# 4. self-reference: destination == upstream path, or upstream is itself port output
selfref = [r for r in rows if r[5].endswith(".bend") and r[0].endswith(".bend")]
print(f"\n.upstream==.bend rows (destination is a .bend for a .bend source) = {len(selfref)}")
for r in selfref:
    print(f"  {r[0]}  [{r[3]}] -> {r[5]}  reason={r[4]!r}")

# 5. same basename, different tree (collision that a flatten would create)
print(f"\nledgers reasons in use: {sorted({r[4] for r in rows})}")