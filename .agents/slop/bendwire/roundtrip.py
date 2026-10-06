"""The byte-identity guard: one PACKET.in through the PRE-FIX executor, the POST-FIX executor and (when
present) the PACKET.out the device itself wrote, then a byte diff of all PACKET.out.

usage: .venv/bin/python roundtrip.py <packet-dir> [grid...]
       <packet-dir> holds PACKET.in, optionally PACKET.out, optionally ARGV (whose tail is the grid).
       default grid is 1 1 1.
"""
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
OLD = pathlib.Path.home() / "Library/Caches/tinygrad/bend-executor-970cbc1d5f288c9a"
NEW = pathlib.Path((HERE / "EXE").read_text().strip())


def run(exe: pathlib.Path, pkt: str, args: list[str]):
    d = pathlib.Path(tempfile.mkdtemp())
    (d / "PACKET.in").write_text(pkt)
    r = subprocess.run([str(exe), str(d / "PACKET.in"), *args], capture_output=True, text=True)
    assert r.returncode == 0, (exe.name, r.returncode, r.stderr[:500])
    return (d / "PACKET.out").read_bytes()


def main():
    src = pathlib.Path(sys.argv[1])
    args = sys.argv[2:] or ["1", "1", "1"]
    pkt = (src / "PACKET.in").read_text()
    old, new = run(OLD, pkt, args), run(NEW, pkt, args)
    dev = (src / "PACKET.out").read_bytes() if (src / "PACKET.out").exists() else None
    dig = lambda b: hashlib.sha256(b).hexdigest()[:16]  # noqa: E731
    print(f"{src.name}/PACKET.in  {len(pkt)} B   grid {args}")
    print(f"  old-exec {len(old):>7} B  {dig(old)}")
    print(f"  new-exec {len(new):>7} B  {dig(new)}")
    if dev is not None:
        print(f"  device   {len(dev):>7} B  {dig(dev)}")
    print(f"  old == new : {old == new}")
    assert old == new, "BYTE MISMATCH old vs new"
    if dev is not None:
        assert new == dev, "BYTE MISMATCH new vs device"
    print("  BYTE-IDENTICAL")


if __name__ == "__main__":
    main()
