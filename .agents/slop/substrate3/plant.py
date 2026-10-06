#!/usr/bin/env python3
"""Two plants, two states each, on the REAL `checks/substrate.py` (`-n`, so no `bend` runs).

PLANT A -- an `unseen`-shaped ref. `a.bend` gains `Zzz.missing_whole_world(...)`: `Zzz` is an
uppercase prefix that is not an import alias, so it is counted `unseen` and NOT a finding. The
run stays GREEN (rc 0, BAD 0) and the UNSEEN count MOVES. This is the false-negative surface the
COVERAGE line now discloses.

PLANT B -- a broken import. `c.bend` imports `./ghost.bend` (absent): `missing_module` fires and
`G.thing` is `unresolved`, so the sweep goes RED (rc 1). Restored, it goes GREEN again.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PLANT = ROOT / ".agents/slop/substrate3/plant"
PY = ".venv/bin/python"


def run(*files: str) -> tuple[int, str]:
    r = subprocess.run([PY, "checks/substrate.py", "-n", *files],
                       cwd=ROOT, capture_output=True, text=True)
    return r.returncode, r.stdout


def field(out: str, name: str) -> int:
    m = re.search(rf"\b{name}=(\d+)", out)
    return int(m.group(1)) if m else -1


def bad(out: str) -> int:
    m = re.search(r"^BAD (\d+)", out, re.M)
    return int(m.group(1)) if m else -1


def unseen(out: str) -> int:
    m = re.search(r"^COVERAGE .* UNSEEN=(\d+)", out, re.M)
    return int(m.group(1)) if m else -1


def main() -> int:
    PLANT.mkdir(parents=True, exist_ok=True)
    (PLANT / "b.bend").write_text(
        "type Thing is Data:\n  One\n  Two\n\ndef Thing.make() -> Thing: One\n")
    clean = "import ./b.bend as B\n\ndef main() -> B.Thing: B.Thing.make()\n"
    seen = clean + "def bad() -> B.Thing: Zzz.missing_whole_world(B.Thing)\n"

    a, b = str(PLANT / "a.bend"), str(PLANT / "b.bend")
    (PLANT / "a.bend").write_text(clean)
    rc0, out0 = run(a, b)
    (PLANT / "a.bend").write_text(seen)
    rc1, out1 = run(a, b)
    print("PLANT A  unseen-shaped ref")
    print(f"  before: rc={rc0} BAD={bad(out0)} UNSEEN={unseen(out0)}")
    print(f"  after : rc={rc1} BAD={bad(out1)} UNSEEN={unseen(out1)}  "
          f"(delta UNSEEN={unseen(out1) - unseen(out0)}, delta BAD={bad(out1) - bad(out0)})")
    print(f"  STATE 1 GREEN rc=0? {rc0 == 0}   STATE 2 GREEN rc=0? {rc1 == 0}  "
          "<- the unseen ref MOVED the number and did NOT move the verdict")

    broken = "import ./ghost.bend as G\n\ndef u() -> B.Thing: G.thing()\n"
    c = str(PLANT / "c.bend")
    (PLANT / "c.bend").write_text(broken)
    rcB, outB = run(c, b)
    (PLANT / "c.bend").write_text(clean)
    rcG, outG = run(c, b)
    print("PLANT B  broken import")
    print(f"  broken  : rc={rcB} BAD={bad(outB)} missing_module={field(outB, 'missing_module')}")
    print(f"  restored: rc={rcG} BAD={bad(outG)} missing_module={field(outG, 'missing_module')}")
    print(f"  STATE 1 RED rc=1? {rcB == 1}   STATE 2 GREEN rc=0? {rcG == 0}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
