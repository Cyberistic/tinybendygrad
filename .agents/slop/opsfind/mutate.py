#!/usr/bin/env python3
"""mutate.py -- THE MUTATION READINGS FOR ops_python_census FINDINGS A, B AND C.

    .venv/bin/python .agents/slop/opsfind/mutate.py

A fix is only a fix if the thing it fixed MOVES. Each plant below edits the ONE
place a revision declares an input, runs the port's fixture lane, and reports
the rows that moved -- for BOTH revisions: the one in git BEFORE the work
(`git show HEAD:...`) and the one on disk AFTER. `bend` resolves imports relative
to the file, so each run is made at the REAL path and the file is put back in a
`finally`: an interrupted run cannot leave a plant in the tree.

THE PLANTS ARE NOT SYMMETRIC, and that is the reading rather than a gap in it.
In the BEFORE revision `pyd_ctor_len`, `pyd_ctor_allocator`, `pyd_ctor_renderers`,
`pyd_ctor_runtime` and `pyd_nrenderers` are bare literals and `pyd_ctor_*`'s
`DEV_*()` tags were DEFINED to be 0/1/2. There is no ctor ORDER declared anywhere
in that file, so an upstream reorder has nothing to move: the honest BEFORE
reading for those three is "no such input exists", and it is printed as such.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad" / "runtime" / "ops_python.bend"
REL = str(PORT.relative_to(ROOT))

# A before-plant, or None plus the reason there is none.
BEFORE = {
    "A1": ((r"(?m)^      core_find\(\[Core\{CORES_METAL\(\), 8, 8, 8, 0, 32\}, "
             r"Core\{CORES_METAL\(\), 8, 8, 8, 1, 32\}\],$",
             "      core_find([Core{CORES_METAL(), 16, 16, 16, 0, 32}, "
             "Core{CORES_METAL(), 16, 16, 16, 1, 32}],"), None),
    "A2": ((r"(?m)^      core_find\(\[Core\{CORES_METAL\(\), 8, 8, 8, 0, 32\}, "
             r"Core\{CORES_METAL\(\), 8, 8, 8, 1, 32\}\],$",
             "      core_find([Core{CORES_METAL(), 8, 8, 8, 0, 64}, "
             "Core{CORES_METAL(), 8, 8, 8, 1, 64}],"), None),
    "A3": (None, "no such input: the BEFORE file declares no ctor ORDER -- the "
                 "three positions ARE the tag values, so an upstream reorder has "
                 "nothing to move and can only be expressed by editing the answers"),
    "A4": (None, "no such input: `pyd_ctor_len` was the literal 4 with nothing "
                 "declared behind it, so 3 is exactly as writable as 4"),
    "A5": (None, "no such input: `pyd_nrenderers` was the literal 1 with nothing "
                 "declared behind it, so 2 is exactly as writable as 1"),
    "A6": (None, "no such input: there was one literal (`True{}`) and nothing to "
                 "COMPARE it against, so a rename of `base64.b64decode` itself "
                 "had no representation in the file"),
}

# (key, label, the same semantic change to the input, applied AFTER, rows read)
PLANTS = [
    ("A1", "tc.py widened the metal FRAGMENT, 8 -> 16 on the core the LOOKUP uses",
     (r"(?m)^def METAL_CORE\(din: U32\) -> Core: Core\{CORES_METAL\(\), 8, 8, 8, din, 32\}$",
      "def METAL_CORE(din: U32) -> Core: Core{CORES_METAL(), 16, 16, 16, din, 32}"),
     ("pywma_metal_dims0",)),
    ("A2", "tc.py gave the metal fragment 64 THREADS instead of 32",
     (r"(?m)^def METAL_CORE\(din: U32\) -> Core: Core\{CORES_METAL\(\), 8, 8, 8, din, 32\}$",
      "def METAL_CORE(din: U32) -> Core: Core{CORES_METAL(), 8, 8, 8, din, 64}"),
     ("pywma_metal_threads",)),
    ("A3", "ops_python.py reordered the ctor: renderers before allocator",
     (r"(?m)^def DEV_ARGS\(\) -> List<&1, U32>: "
      r"\[DEV_DEVICE\(\), DEV_ALLOCATOR\(\), DEV_RENDERERS\(\), DEV_RUNTIME\(\)\]$",
      "def DEV_ARGS() -> List<&1, U32>: [DEV_DEVICE(), DEV_RENDERERS(), DEV_ALLOCATOR(), DEV_RUNTIME()]"),
     ("pyd_ctor_allocator", "pyd_ctor_renderers")),
    ("A4", "ops_python.py dropped an argument from the ctor call",
     (r"(?m)^def DEV_ARGS\(\) -> List<&1, U32>: "
      r"\[DEV_DEVICE\(\), DEV_ALLOCATOR\(\), DEV_RENDERERS\(\), DEV_RUNTIME\(\)\]$",
      "def DEV_ARGS() -> List<&1, U32>: [DEV_ALLOCATOR(), DEV_RENDERERS(), DEV_RUNTIME()]"),
     ("pyd_ctor_len", "pyd_ctor_allocator", "pyd_ctor_renderers", "pyd_ctor_runtime")),
    ("A5", "ops_python.py named a SECOND renderer in the list it passes",
     (r"(?m)^def DEV_RENDERER_CLASSES\(\) -> List<&1, U32>: \[PY_RENDERER\(\)\]$",
      "def DEV_RENDERER_CLASSES() -> List<&1, U32>: [PY_RENDERER(), U32.add(PY_RENDERER(), 1)]"),
     ("pyd_nrenderers",)),
    ("A6", "`base64.b64decode` was renamed -- the decoder's DECLARATION moved",
     (r'(?m)^def b64\.transform\(\) -> String: "base64\.b64decode"$',
      'def b64.transform() -> String: "base64.b64decode2"'),
     ("pyc_is_b64decode", "pyc_refused")),
]


def lane(src=None):
    """The port's fixture lane. With `src`, it is PLANTED at the real path for the
    duration of one run and then restored."""
    if src is None:
        r = subprocess.run(["./bin/bend", REL], capture_output=True, text=True, cwd=str(ROOT))
    else:
        keep = PORT.read_text()
        try:
            PORT.write_text(src)
            r = subprocess.run(["./bin/bend", REL], capture_output=True, text=True, cwd=str(ROOT))
        finally:
            PORT.write_text(keep)
    if r.returncode != 0:
        return None
    return dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)


def main():
    new = PORT.read_text()
    g = subprocess.run(["git", "show", f"HEAD:{REL}"], capture_output=True, text=True, cwd=str(ROOT))
    if g.returncode != 0:
        sys.exit("could not read the BEFORE revision out of git")
    old = g.stdout
    try:
        bases = {"BEFORE": lane(old), "AFTER ": lane()}
        for tag, base in bases.items():
            print(f"{tag} unplanted lane: {len(base) if base else 'DID NOT RUN'} rows")
        for key, label, (pat, sub), rows in PLANTS:
            print(f"\n== {key}  {label}")
            bpat, bwhy = BEFORE[key]
            if bpat is None:
                print(f"   BEFORE  no input to move -- {bwhy}")
            else:
                print(f"   BEFORE  {planted(old, base_old := bases['BEFORE'], bpat, rows)}")
            print(f"   AFTER   {planted(new, bases['AFTER '], (pat, sub), rows)}")
    finally:
        PORT.write_text(new)
    print("\nthe port is restored; a plant never survives this script")


def planted(src, base, plant, rows):
    if base is None:
        return "the port did not run"
    out, n = re.subn(plant[0], plant[1], src)
    if n != 1:
        return f"THE PLANT DID NOT APPLY ({n} sites) -- the reading is NOT a reading"
    got = lane(out)
    if got is None:
        return "the planted port did not run"
    moved = [f"{k}: {base.get(k)} -> {got.get(k)}" for k in rows if base.get(k) != got.get(k)]
    return f"moved {len(moved)}/{len(rows)}  " + ("; ".join(moved) if moved else "NOTHING")


if __name__ == "__main__":
    main()