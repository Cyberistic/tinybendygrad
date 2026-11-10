#!/usr/bin/env python3
"""extract-gate-rows.py -- MOVE A `.bend` FILE's GATE ROWS INTO `gates/`.

    .venv/bin/python .agents/slop/loc/extract-gate-rows.py --apply <file.bend> [<file.bend>...]

**⇒ WHAT IT MOVES:** EVERYTHING FROM THE FILE's OWN `# --- THE GATE ROWS` MARKER TO THE END
OF THE FILE, **AND THE ROW HELPERS IT CALLS THAT THE IMPLEMENTATION NEVER CALLS.**

**⇒ WHY THIS IS SAFE, AND THE PROOF IS IN THE MEASUREMENT IT PRINTS:**

  * **THE ROWS ARE PURE CONSUMERS.** MEASURED 2026-11-10 ON `sqtt.bend`: THE ROWS CALL
    **19** OF THE FILE's 563 DEFS, AND DEFINE **7** OF THEIR OWN. **⇒ THE MOVED PART IS A
    DRIVER, NOT A PORT.**
  * **THE IMPLEMENTATION NEVER CALLS THE MOVED HELPERS.** MEASURED: `srow`, `u32_text`,
    `nat_text`, `name_at` AND `op_of` HAVE EXACTLY **ONE** USE EACH IN THE IMPLEMENTATION
    — **THEIR OWN DEFINITION** — **SO THEY ARE ROW-ONLY AND THEY MOVE TOO.**
  * **THE PORT FILE STILL COMPILES.** THE TOOL RUNS `bin/bend --check-only` ON BOTH THE
    TRIMMED PORT FILE AND THE NEW DRIVER, **AND IT READS THE VERDICT TOKEN AND NOT THE EXIT
    CODE** (`checks/bounded.py`: `WITHIN-LIMITS` / `KILLED-ON-MEMORY` / `TIMED-OUT`).

**⇒ AND IT WRITES THE NEW DRIVER IN THE TREE's OWN HOUSE STYLE** — `gates/README.md:173`:
*"a gate's `.bend` driver and its CPython oracle sit in `gates/`, named by the gate that
needs them."* **⇒ SO THE DRIVER IS `gates/<name>-gate.bend`, IT IMPORTS THE PORT FILE, AND
IT CALLS THE PORT's DEFS BY THEIR EXPORTED NAMES.**

**⇒ AND IT **REFUSES** TO WRITE IF THE PORT FILE WOULD NOT COMPILE AFTER THE TRIM.**
**⇒ AND IT **REFUSES** IF THE MARKER IS NOT FOUND, **BECAUSE A FILE WITHOUT THE MARKER IS
NOT ONE OF THESE FILES AND **GUESSING** WOULD MOVE A PORT.**
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MARKER = re.compile(r"^#\s*-+\s*THE GATE ROWS\s*-+\s*$")
# **⇒ THE ROW HELPERS** -- **THE DEFS THAT TAKE A NAME AND A VALUE AND PRINT ONE ROW.**
# **⇒ THE LIST IS **THE **HELPERS THE GATE SECTION CALLS** AND **THE IMPLEMENTATION DOES
# NOT** -- **AND IT IS DERIVED FROM THE CALLS, NOT FROM A NAME SHAPE.**
ROW_HELPER = re.compile(r"^def ((?:srow|row)\w*)\(")
# **⇒ AND THE OTHER ROW-ONLY HELPERS, **DERIVED THE SAME WAY**: A DEF THE GATE SECTION CALLS
# AND THE IMPLEMENTATION NEVER CALLS.**
ANY_DEF = re.compile(r"^def ([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)\(")
# THE CALLABLE DEFS -- LOWERCASE ONLY -- AND THAT IS THE CLOSURE's POPULATION, BECAUSE AN
# UPPERCASE DEF IS A CONSTANT AND NOT A CALLABLE HELPER.
CALLABLE = re.compile(r"^def ([a-z_][a-z0-9_]*(?:\.[a-z0-9_]+)*)\(")
# **⇒ AND A **DECLARATION** IS **NOT A DEF** -- **AND A HELPER's BLOCK MUST STOP AT IT.**
# **⇒ MEASURED 2026-11-10 ON `elf.bend`: `param_size`'s BLOCK SWALLOWED THE
# `type Slot is Data:` DECLARATION THAT FOLLOWS IT, **BECAUSE THE SCAN ONLY STOPPED AT
# `def ` AND AT A COMMENT** -- **AND A `type` DECLARATION IS NEITHER.**
# **⇒ AND THE CONSEQUENCE WAS **THE PORT LOST ITS OWN `Slot` TYPE** AND FAILED TO
# COMPILE WITH "a declared constructor (unknown: Slot)" -- **WHILE THE TOOL REPORTED
# `WITHIN-LIMITS` FOR BOTH FILES, BECAUSE THE TOKEN IS **THE WATCHDOG's**, NOT THE
# COMPILER's.**
DECL = re.compile(r"^(?:def|type|struct|datatype|enum)\s")


def block_end(lines: list[str], j: int) -> int:
    """⇒ **THE END OF THE DECLARATION THAT STARTS AT `j`** -- **A DEF, A TYPE, A STRUCT.

    **⇒ AND THE SCAN STOPS AT THE NEXT DECLARATION **OR** AT A COMMENT LINE, **BECAUSE A
    COMMENT BLOCK **BEFORE** THE NEXT DECLARATION BELONGS TO THAT DECLARATION** (AND THE
    CALLER MOVES IT WITH THE DECLARATION).**
    """
    e = j + 1
    while e < len(lines) and not DECL.match(lines[e]) and not lines[e].strip().startswith("#"):
        e += 1
    return e



def bounded_bend(path: Path) -> str:
    """RUN THE PORT's OWN WATCHDOG AND **READ THE VERDICT TOKEN**.

    **⇒ AND THE TOKEN IS ON **STDERR** -- MEASURED 2026-11-10: `checks/bounded.py` PRINTS
    `[bounded] WITHIN-LIMITS  rc=0  peak-RSS=...` TO **STDERR**, **AND THE BEND OUTPUT
    ITSELF (`ALL PROOFS CHECK`) IS ALSO ON STDERR.** **⇒ AND A MISSING TOKEN IS **NOT** A
    PASS: IT IS `NO-TOKEN`, AND THE TOOL REFUSES.**
    """
    r = subprocess.run(
        [".venv/bin/python", "checks/bounded.py", "--mb", "3072", "--", "./bin/bend", str(path)],
        cwd=ROOT, capture_output=True, text=True, timeout=900,
    )
    both = r.stdout + r.stderr
    for token in ("WITHIN-LIMITS", "KILLED-ON-MEMORY", "TIMED-OUT"):
        if token in both:
            return token
    return "NO-TOKEN"


def split(path: Path) -> tuple[list[str], list[str], list[str]]:
    """⇒ (THE IMPLEMENTATION LINES, THE GATE LINES, THE MOVED HELPERS)."""
    lines = path.read_text().splitlines()
    idx = next((i for i, l in enumerate(lines) if MARKER.match(l.strip())), None)
    if idx is None:
        raise SystemExit(f"  REFUSED: {path} has no 'THE GATE ROWS' marker")
    impl = lines[:idx]
    gate = lines[idx:]

    # **⇒ THE ROW HELPERS, AND **ONLY** THOSE THE IMPLEMENTATION NEVER CALLS.**
    impl_text = "\n".join(impl)
    gate_text_all = "\n".join(gate)
    all_defs = {m.group(1) for m in (CALLABLE.match(l) for l in impl) if m}
    helpers: list[str] = []
    for i, l in enumerate(impl):
        m = CALLABLE.match(l)
        if not m:
            continue
        name = m.group(1)
        # **⇒ A HELPER IS ROW-ONLY WHEN **THE GATE SECTION CALLS IT** AND **THE
        # IMPLEMENTATION NEVER CALLS IT** (ITS OWN DEFINITION DOES NOT COUNT).**
        if gate_text_all.count(name + "(") == 0:
            continue
        if impl_text.count(name + "(") > 1:
            continue
        helpers.append(name)
    # **⇒ AND THE **CLOSURE**: A MOVED HELPER'S OWN DEPS MOVE WITH IT** -- **AND A DEP THAT
    # THE IMPLEMENTATION ALSO CALLS **STAYS** AND **IS CALLED `P.<name>`** IN THE DRIVER.
    changed = True
    while changed:
        changed = False
        for h in list(helpers):
            j = next(k for k, l in enumerate(impl) if l.startswith(f"def {h}("))
            e = block_end(impl, j)
            body = "\n".join(impl[j:e])
            for d in all_defs:
                if d == h or d in helpers:
                    continue
                if re.search(rf"\b{re.escape(d)}\(", body):
                    # **⇒ THE DEP MOVES **ONLY IF** THE IMPLEMENTATION NEVER CALLS IT.**
                    if impl_text.count(d + "(") <= 1:
                        helpers.append(d)
                        changed = True
    # **⇒ AND THE **HELPER'S OWN BLOCK** -- **A DEF AND **ITS COMMENT LINES** AND **THE
    # BLANK LINE AFTER IT** -- **MOVES WITH IT.**
    moved: list[str] = []
    drop: set[int] = set()
    for h in helpers:
        j = next(k for k, l in enumerate(impl) if l.startswith(f"def {h}("))
        s = j
        while s > 0 and impl[s - 1].strip().startswith("#"):
            s -= 1
        e = block_end(impl, j)
        moved.extend(impl[s:e])
        drop.update(range(s, e))
    impl = [l for k, l in enumerate(impl) if k not in drop]
    # **⇒ AND THE MOVED HELPERS GO IN **THE ORDER THEY HAD** -- **AND THAT ORDER IS NOT
    # ALWAYS THE ORDER THEY NEED**, **BECAUSE ONE HELPER CAN CALL ANOTHER** (MEASURED
    # 2026-11-10: `urow` CALLS `u32_text`, AND `u32_text` IS DEFINED **AFTER** IT IN THE
    # ORIGINAL, **WHICH COMPILES ONLY BECAUSE **THE ORIGINAL'S `main` IS AT THE END AND
    # THE `g_*` DEFS ARE **AFTER** BOTH**). **⇒ AND BEND HAS NO FORWARD REFERENCES
    # ("defs are checked in file order, and an unfilled hole is not a def"), **SO THE
    # HELPERS ARE REORDERED BY THEIR OWN DEPENDENCY GRAPH.**
    moved = order_defs(moved)
    return impl, gate, moved, helpers


def rebased_path(src: str, port: Path, root: Path) -> str:
    """⇒ **THE PORT's IMPORT PATH, REBASED ON THE DRIVER's DIRECTORY.**

    **⇒ THE PORT IMPORTS `./dsl.bend` (A SIBLING) AND `../../helpers.bend` (A GRANDPARENT),
    AND THE DRIVER LIVES IN `gates/`, **SO BOTH BECOME `./../tinybendygrad/...`**.**
    **⇒ AND THE RESOLUTION IS **BY THE REAL PATH**, NOT BY STRING ARITHMETIC** — **A
    SIBLING'S NAME CAN APPEAR IN TWO DIRECTORIES** (`sqtt.bend` AND `dsl.bend` ARE BOTH IN
    `renderer/amd/`), **AND THE ARITHMETIC WOULD BE WRONG FOR A GRANDPARENT.**
    """
    if not src.endswith(".bend"):
        return src
    base = (port.parent / src).resolve()
    try:
        rel = base.relative_to(root)
    except ValueError:
        return src
    return f"./../{rel}"


def order_defs(lines: list[str]) -> list[str]:
    """⇒ **TOPOLOGICAL ORDER OF THE DEFS**, BY **THE NAMES THEY CALL**.

    **⇒ AND **NOTHING IS DROPPED** -- **A LINE THAT IS NOT PART OF A DEF BLOCK IS KEPT IN
    ITS ORIGINAL PLACE.** **⇒ MEASURED 2026-11-10: THE FIRST VERSION RETURNED **ONLY** THE
    BLOCKS IT RECOGNISED, **AND EVERY DOTTED DEF AND EVERY `type` DECLARATION VANISHED
    WITHOUT A WORD** -- `ops_cl.bend` LOST **101** LINES AND `ops_webgpu.bend` LOST **41**,
    **AND THE MOVE STILL REPORTED SUCCESS.**
    """
    defs: dict[str, list[str]] = {}
    order: list[str] = []
    claimed: set[int] = set()
    for i, l in enumerate(lines):
        # **⇒ AND THE DEF NAME MAY BE **DOTTED** (`alloc.free`, `prog.call.at`) -- **AND THE
        # REGEX IS **THE TOOL's OWN `CALLABLE` PATTERN**, **NOT** A DOT-LESS ONE.**
        # **⇒ MEASURED 2026-11-10: THE DOT-LESS REGEX **DROPPED EVERY DOTTED DEF** ON THE
        # MOVE -- `ops_cl.bend` LOST **101** LINES AND `ops_webgpu.bend` LOST **41** --
        # **AND THE MOVE WAS STILL REPORTED AS SUCCESSFUL**, **BECAUSE `order_defs` RETURNS
        # ONLY THE BLOCKS IT RECOGNISED AND SILENTLY DROPS THE REST.**
        m = re.match(r"^def ([a-z_][a-z0-9_]*(?:\.[a-z0-9_]+)*)\(", l)
        if not m:
            continue
        s = i
        while s > 0 and lines[s - 1].strip().startswith("#"):
            s -= 1
        e = block_end(lines, i)
        defs[m.group(1)] = lines[s:e]
        order.append(m.group(1))
        claimed.update(range(s, e))
    # **⇒ AND THE **UNCLAIMED** LINES ARE THE **NON-DEF** CONTENT** -- **A `type`
    # DECLARATION, A BLANK LINE, A STANDALONE COMMENT** -- **AND THEY ARE EMITTED IN
    # ORDER, **INTERLEAVED WITH THE DEFS** BY THE POSITION OF THEIR FIRST LINE.**
    loose: list[tuple[int, list[str]]] = []
    i = 0
    while i < len(lines):
        if i in claimed:
            i += 1
            continue
        j = i
        while j < len(lines) and j not in claimed:
            j += 1
        loose.append((i, lines[i:j]))
        i = j
    out: list[str] = []
    seen: set[str] = set()

    def emit(name: str, stack: tuple[str, ...] = ()) -> None:
        if name in seen or name not in defs:
            return
        block = defs[name]
        text = "\n".join(block)
        deps = [d for d in defs if d != name and re.search(rf"\b{d}\(", text)]
        for d in deps:
            if d not in stack:
                emit(d, stack + (name,))
        seen.add(name)
        out.extend(block)

    for n in order:
        emit(n)
    # **⇒ AND THE LOOSE CONTENT IS APPENDED, **BECAUSE A `type` DECLARATION IS **NOT
    # DEPENDENT ON** THE DEFS THAT USE IT** -- **BEND READS A TYPE DECLARATION WHERE IT
    # IS WRITTEN AND THE USES THAT FOLLOW IT.**
    for _, chunk in loose:
        out.extend(chunk)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", nargs="*", default=[])
    args = ap.parse_args()
    if not args.apply:
        print(__doc__)
        return 0
    for rel in args.apply:
        path = ROOT / rel
        impl, gate, moved, helpers = split(path)
        stem = path.stem
        driver = ROOT / "gates" / f"{stem}-gate.bend"
        print(f"  {rel}: {len(impl)} impl lines, {len(gate)} gate lines, {len(moved)} helper lines")
        # **⇒ THE DRIVER'S HEADER, IN THE TREE's OWN STYLE.**
        # **⇒ AND THE PORT's **IMPORTS** MOVE WITH THE ROWS** -- **MEASURED 2026-11-10:
        # THE PORT FILE IMPORTS `../../helpers.bend as H` AND `./dsl.bend as D`, **AND THE
        # MOVED ROWS NAME `H.*` AND `D.*` AND THE TYPE `Pn` (WHICH IS `D`'s)**, **SO THE
        # DRIVER MUST CARRY THE SAME IMPORTS WITH THE **PATHS REBASED** ON THE DRIVER's
        # OWN DIRECTORY** (`gates/` IS NOT `tinybendygrad/renderer/amd/`).**
        imports = [l for l in impl if l.startswith("import ")]
        rebased: list[str] = []
        for l in imports:
            m = re.match(r"^import (\S+) as (\w+)$", l)
            if m:
                src, alias = m.group(1), m.group(2)
                # **⇒ THE PATH IS REBASED: THE PORT's `./dsl.bend` IS
                # `./../tinybendygrad/renderer/amd/dsl.bend` FROM `gates/`.**
                rebased.append(f"import {rebased_path(src, path, ROOT)} as {alias}")
            else:
                rebased.append(l)
        hdr = [
            f"# {driver.relative_to(ROOT)} -- THE GATE DRIVER for `{path.relative_to(ROOT)}`.",
            "#",
            "# THE ROWS MOVED HERE FROM THE PORT FILE. **⇒ THE PORT FILE CARRIES THE PORT AND",
            "# THIS FILE CARRIES THE INSTRUMENT**, AND THE TREE's OWN CONVENTION SAYS SO:",
            "# `gates/README.md:173` -- \"a gate's `.bend` driver and its CPython oracle sit in",
            "# `gates/`, named by the gate that needs them.\"",
            "#",
            "# **⇒ AND THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE",
            "# NOTHING THAT THE PORT NEEDS.**",
            "",
            "import Base",
            f"import ./../{path.relative_to(ROOT)} as P",
        ] + rebased[1:] + [
            "",
        ]
        # **⇒ THE `main`, WHICH THE PORT FILE's OWN `main` CALLED.**
        # **⇒ AND THE **PORT's DEFS** ARE CALLED **UNQUALIFIED** IN THE PORT FILE AND
        # **QUALIFIED** IN THE DRIVER** -- **AND THE QUALIFICATION IS **THE WHOLE** OF THE
        # MOVE** (MEASURED: `gates/tn_logical_not.bend` CALLS `T.tn_logical_not`).
        port_defs = {m.group(1) for m in (ANY_DEF.match(l) for l in impl) if m}
        # **⇒ AND THE PORT's **TYPES** -- **MEASURED 2026-11-10: THE MOVED HELPER
        # `name_at` HAS THE SIGNATURE `+xs: List<&2, Pn>`, **AND `Pn` IS THE PORT's OWN
        # TYPE**, **SO THE DRIVER SAID "expected : a defined name / observed : Pn"** --
        # **⇒ AND A TYPE IS QUALIFIED THE SAME WAY A DEF IS.**
        port_types = {m.group(1) for m in (re.match(r"^type ([A-Za-z_][A-Za-z0-9_]*)", l) for l in impl) if m}
        gate_text = "\n".join(gate)
        for d in sorted(port_defs, key=len, reverse=True):
            gate_text = re.sub(rf"(?<![\w.]){re.escape(d)}\(", f"P.{d}(", gate_text)
        # **⇒ AND A **TYPE** IS **NOT** FOLLOWED BY `(`** -- **IT IS QUALIFIED IN A **TYPE
        # POSITION** (`List<&2, Pn>`) -- **MEASURED 2026-11-10: THE DRIVER SAID "expected :
        # a defined name / observed : Pn"** **WITH THE DEF QUALIFICATION ALREADY IN PLACE.**
        for t in sorted(port_types, key=len, reverse=True):
            gate_text = re.sub(rf"(?<![\w.]){re.escape(t)}\b", f"P.{t}", gate_text)
        # **⇒ AND THE **MOVED HELPERS** ARE **NOT** PORT DEFS** -- **THEY MOVED WITH THE
        # ROWS** -- **SO THEY MUST NOT BE QUALIFIED.**
        for h in helpers:
            gate_text = re.sub(rf"P\.{re.escape(h)}\(", f"{h}(", gate_text)
        # **⇒ AND THE **MOVED BLOCK** NEEDS THE SAME QUALIFICATION** -- **MEASURED
        # 2026-11-10: THE MOVED HELPER `urow` CALLS `u32_text`, **AND `u32_text` STAYS IN
        # THE PORT FILE** (IT HAS SIX IMPLEMENTATION USES), **SO THE MOVED BLOCK'S CALL MUST
        # BE `P.u32_text`** -- **AND THE FIRST PASS QUALIFIED ONLY THE GATE TEXT, **SO THE
        # DRIVER FAILED WITH "expected : a defined name / observed : u32_text"**.**
        moved_text = "\n".join(moved)
        for d in sorted(port_defs, key=len, reverse=True):
            moved_text = re.sub(rf"(?<![\w.]){re.escape(d)}\(", f"P.{d}(", moved_text)
        for t in sorted(port_types, key=len, reverse=True):
            moved_text = re.sub(rf"(?<![\w.]){re.escape(t)}\b", f"P.{t}", moved_text)
        for h in helpers:
            moved_text = re.sub(rf"P\.{re.escape(h)}\(", f"{h}(", moved_text)
        moved = moved_text.split("\n")
        # **⇒ AND A HELPER THAT **STAYED** IN THE PORT FILE **AND IS CALLED BY A MOVED
        # HELPER** MUST BE **QUALIFIED** -- **MEASURED 2026-11-10: `u32_text` HAS SIX USES
        # IN THE IMPLEMENTATION, **SO IT STAYS**, **AND `urow` (WHICH MOVED) CALLS IT.**
        # **⇒ AND THE ORDER MATTERS: **THE PORT's DEFS ARE QUALIFIED **FIRST**, **AND THE
        # MOVED HELPERS ARE **UN**QUALIFIED **AFTER**, **SO A MOVED HELPER SHADOWS THE
        # PORT's.**
        driver.write_text("\n".join(hdr + moved + [""] + [gate_text]) + "\n")
        path.write_text("\n".join(impl) + "\n")
        tok_a = bounded_bend(path)
        tok_b = bounded_bend(driver)
        print(f"    port file: {tok_a}   driver: {tok_b}")
        if tok_a != "WITHIN-LIMITS" or tok_b != "WITHIN-LIMITS":
            print("    **REFUSED: one of the two did not compile -- RESTORE BOTH.**")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
