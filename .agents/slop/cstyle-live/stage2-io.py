#!/usr/bin/env python3
"""stage2-io.py -- write the input bytes and read the output bytes, in the SAME dtype tinygrad
used, so the comparison never crosses a representation boundary.

  usage: stage2-io.py in <hex>            # write 16 bytes from a float32 hex string
         stage2-io.py out <file> <hex>    # compare a 16-byte file against a float32 hex
         stage2-io.py diff <fileA> <fileB>

`out` REFUSES to print "OK" for a file whose bytes are the sentinel -12345.0f in any lane:
that is the file a kernel that wrote nothing leaves, and it must never be read as an answer.
"""
import pathlib, struct, sys

SENTINEL = struct.pack("<f", -12345.0)


def read(p):
  b = pathlib.Path(p).read_bytes()
  if len(b) != 16:
    raise SystemExit(f"stage2-io: {p} is {len(b)} bytes, not 16")
  return b


def floats(b):
  return list(struct.unpack("<4f", b))


if sys.argv[1] == "in":
  pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(sys.argv[3]))
  print(f"wrote {sys.argv[2]}: {floats(bytes.fromhex(sys.argv[3]))}")
elif sys.argv[1] == "out":
  got, want = read(sys.argv[2]), bytes.fromhex(sys.argv[3])
  sent = [i for i in range(4) if got[i * 4:i * 4 + 4] == SENTINEL]
  if sent:
    print(f"MISMATCH {sys.argv[2]}: lane(s) {sent} still hold the sentinel -12345.0 -- the "
          f"kernel did not write them")
    sys.exit(1)
  n = sum(1 for a, b in zip(got, want) if a != b)
  print(f"{'OK' if n == 0 else 'MISMATCH'} {sys.argv[2]}: got {got.hex()} "
        f"{floats(got)}  want {want.hex()} {floats(want)}  differing bytes: {n}")
  sys.exit(0 if n == 0 else 1)
elif sys.argv[1] == "diff":
  a, b = read(sys.argv[2]), read(sys.argv[3])
  print(f"diff bytes {sys.argv[2]} vs {sys.argv[3]}: {sum(1 for x, y in zip(a, b) if x != y)}")
else:
  raise SystemExit("usage: stage2-io.py in|out|diff ...")