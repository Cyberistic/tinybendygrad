#!/usr/bin/env python3
"""patch_dtype.py -- write the six `Dt.i64_*` as pure Bend, IN PLACE.

The six FFI defs occupy one contiguous run of `dtype.bend` (the 24 lines from
`def Dt.i64_trunc` through the last `import "./runtime/dtype.js"`), so the
replacement is one anchored span rather than six independent substitutions -- a
substitution that matched nothing would leave the file unchanged and print
success, which is how a gate goes green over a lane that never ran.

IN PLACE, NOT APPENDED: bend has no forward references, so the helpers must be
above their callers, and the seam section is where the six belong.

Reproduce:
  cp -R tinybendygrad $W/tree/ ; git show HEAD:tinybendygrad/helpers.bend > ...
  python3 patch_dtype.py $W/tree
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
BLOCK = (HERE / "i64-pure.bend.txt").read_text().rstrip() + "\n"

NAMES = ["i64_trunc", "i64_floor_div", "i64_floor_mod",
         "i64_cdiv", "i64_cmod", "i64_ceildiv"]


def anchor() -> tuple[int, int]:
    """The span the six occupy, found from the FIRST and LAST of them."""
    dt = pathlib.Path(sys.argv[1]) / "tinybendygrad/dtype.bend"
    src = dt.read_text()
    start = src.index(f"def Dt.{NAMES[0]}(x: H.I64) -> IO(H.I64):")
    end = src.index(f'def Dt.{NAMES[-1]}(a: H.I64, b: H.I64) -> IO(H.I64):')
    tail = src.index('\n', src.index('import "./runtime/dtype.js"', end)) + 1
    for n in NAMES:
        if src.count(f"def Dt.{n}(") != 1:
            sys.exit(f"anchor {n} is not unique")
    return dt, start, tail


def main() -> None:
    dt, start, tail = anchor()
    src = dt.read_text()
    out = src[:start] + BLOCK + src[tail:]
    assert out.count("Dt.i64_trunc") == 1
    dt.write_text(out)
    print(f"patched {dt}: removed {tail - start} BYTES of foreign defs, "
          f"inserted {len(BLOCK.splitlines())} lines of pure Bend")


if __name__ == "__main__":
    main()