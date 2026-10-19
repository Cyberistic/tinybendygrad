"""Dump every population blob from HEAD into one framed stream, for read-only audit."""
import subprocess, pathlib

here = pathlib.Path(__file__).parent
root = here.parents[3]
pop = [l.rstrip("\n") for l in (here / "pop.head.rows").read_text().splitlines() if l]
p = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--format=%(objectname) %(path)"] + pop,
                   capture_output=True, text=True, cwd=root, check=True)
oids = {}
for line in p.stdout.splitlines():
    oid, path = line.split(" ", 1)
    oids[path] = oid
proc = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, cwd=root)
assert proc.stdin and proc.stdout
proc.stdin.write(("\n".join(oids[p] for p in pop) + "\n").encode())
proc.stdin.close()
frames, i = [], 0
while i < len(pop):
    head = proc.stdout.readline().decode().strip()
    oid, kind, size = head.split()
    body = proc.stdout.read(int(size))
    proc.stdout.read(1)
    frames.append(f"\x00FILE {pop[i]} {kind} {size}\n".encode() + body)
    i += 1
proc.wait()
(here / "blobs.bin").write_bytes(b"".join(frames))
print(f"wrote {len(frames)} frames, {sum(len(f) for f in frames)} bytes")