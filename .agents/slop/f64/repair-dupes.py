#!/usr/bin/env python3
"""f64/repair-dupes.py -- REPAIR A SNAPSHOT'S DUPLICATED BLOCKS. NEVER THE LIVE TREE.

    .venv/bin/python repair-dupes.py <in.bend> <out.bend>

WHY THIS EXISTS, AND IT IS NOT MY FILE.  On 2026-10-04 the LIVE
`tinybendygrad/renderer/cstyle.bend` stopped compiling with

    SOME PROOFS FAIL
    Error:
    - expected : a fresh name (duplicate declaration: BArg.name)

and, once that was removed, again with `duplicate declaration: Uses.half`, and
so on for every derived-fact reader in the file.  The live file's sha256 is
`bed462b63bda530eefcf99d1b1f7a9672e47b1c962a64f1c890abff7b3d23252`; the hash
`cstyle-live/run-all.log:5` quotes for the same path is
`07ae2766f891e9a85bed84c416bab21f9a17c143730aa26383d685998c97eb7f`.  **THE FILE
MOVED.**  Nine verbatim copies of each reader block is what a scripted block
move that never asserted `end > start` leaves behind (`agent-core.md`: "A
scripted block move must assert `end > start`. One agent lost 841 lines to
this."), and `.agents/slop/proof-close/mut/tinybendygrad/renderer/cstyle.bend`
is modified in the working copy, so a mutation script is the likely writer.
**That is a report, not a repair: the live file is not mine to touch.**

WHAT THIS SCRIPT DOES, and the property that makes it safe: it deletes only
*adjacent, byte-identical* line blocks, one duplication at a time, smallest
first.  It cannot invent, reorder or reword a line, so it cannot silently
change the port.  And its correctness is not asserted, it is CHECKED, two ways:

  * `./bin/bend` must compile the result, and
  * the result must print **the same rows, byte for byte**, as the last known
    GOOD run of this file, which is committed at
    `gates/artifacts/cstyle-live/port.txt` (46291 bytes, 227 gate rows, taken at
    sha256 07ae2766...).

The second check is what makes this a repair rather than a guess: if deleting
the duplicates changed any row, the diff would be non-empty and the caller is
expected to treat the snapshot as UNVERIFIED.

EXIT STATUS: 0 = repaired and byte-identical to `port.txt`; 1 = still broken;
2 = repaired but the rows DIFFER (the caller must say SUBSTRATE, not verdict).
"""
import hashlib
import pathlib
import subprocess
import sys

GOOD = pathlib.Path(__file__).resolve().parents[3] / "gates" / "cstyle-live.rows"
MAXP = 512


def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def dedupe(lines: list[str]) -> tuple[list[str], list[tuple[int, int]]]:
    """Delete every ADJACENT byte-identical block duplication, smallest first.

    Returns the repaired lines and one (line_no_1based, block_len) per deletion,
    so the caller can print exactly what was removed."""
    removed = []
    while True:
        for p in range(1, MAXP + 1):
            hit = None
            for i in range(len(lines) - 2 * p + 1):
                if lines[i:i + p] == lines[i + p:i + 2 * p]:
                    hit = i
                    break
            if hit is not None:
                removed.append((hit + 1, p))
                del lines[hit + p:hit + 2 * p]
                break
        else:
            return lines, removed


def main() -> None:
    src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    lines, removed = dedupe(src.read_text().splitlines(keepends=True))
    dst.write_text("".join(lines))
    print(f"  in  {src}  {len(src.read_text().splitlines())} lines  sha256 {sha(src)[:16]}")
    print(f"  out {dst}  {len(lines)} lines  sha256 {sha(dst)[:16]}")
    print(f"  removed {len(removed)} adjacent identical block(s):")
    for ln, p in removed:
        print(f"    lines {ln}..{ln + p - 1}  ({p} lines)")
    dupes = [d for d in __import__("collections").Counter(
        l.split("(")[0] for l in lines if l.startswith("def ")).items() if d[1] > 1]
    print(f"  duplicate `def` names remaining: {dupes if dupes else 'none'}")
    r = subprocess.run(["./bin/bend", str(dst)], capture_output=True, text=True)
    rows = r.stdout.count("]   py=[")
    print(f"  ./bin/bend -> rc={r.returncode}  rows={rows}")
    if r.returncode != 0 or rows < 220:
        print("  REPAIRED BUT STILL RED; first stderr lines:")
        for l in r.stderr.splitlines()[:6]:
            print("    " + l)
        sys.exit(1)
    if not GOOD.exists():
        print(f"  {GOOD} is absent -- rows vs the recorded good run CANNOT be checked")
        sys.exit(2)
    same = GOOD.read_bytes() == r.stdout.encode()
    print(f"  rows vs committed good run {GOOD.name}: "
          f"{'IDENTICAL, 0 bytes' if same else 'DIFFER'}")
    sys.exit(0 if same else 2)


if __name__ == "__main__":
    main()