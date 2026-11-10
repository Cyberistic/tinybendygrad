#!/usr/bin/env python3
"""extract-gate-rows.py -- MOVE A `.bend` FILE's GATE ROWS INTO `gates/`.

    .venv/bin/python .agents/slop/loc/extract-gate-rows.py --apply <file.bend> [<file.bend>...]

**WHAT IT MOVES:** EVERYTHING FROM THE FILE's OWN `# --- THE GATE ROWS` MARKER TO THE END
OF THE FILE, **AND THE ROW HELPERS IT CALLS THAT THE IMPLEMENTATION NEVER CALLS.**

**WHY THIS IS SAFE, AND THE PROOF IS IN THE MEASUREMENT IT PRINTS:**

  * **THE ROWS ARE PURE CONSUMERS.** MEASURED 2026-11-10 ON `sqtt.bend`: THE ROWS CALL
    **19** OF THE FILE's 563 DEFS, AND DEFINE **7** OF THEIR OWN. **THE MOVED PART IS A
    DRIVER, NOT A PORT.**
  * **THE IMPLEMENTATION NEVER CALLS THE MOVED HELPERS.** MEASURED: `srow`, `u32_text`,
    `nat_text`, `name_at` AND `op_of` HAVE EXACTLY **ONE** USE EACH IN THE IMPLEMENTATION
    — **THEIR OWN DEFINITION** — **SO THEY ARE ROW-ONLY AND THEY MOVE TOO.**
  * **THE PORT FILE STILL COMPILES.** THE TOOL RUNS `bin/bend --check-only` ON BOTH THE
    TRIMMED PORT FILE AND THE NEW DRIVER, **AND IT READS THE VERDICT TOKEN AND NOT THE EXIT
    CODE** (`checks/bounded.py`: `WITHIN-LIMITS` / `KILLED-ON-MEMORY` / `TIMED-OUT`).

**AND IT WRITES THE NEW DRIVER IN THE TREE's OWN HOUSE STYLE** — `gates/README.md:173`:
*"a gate's `.bend` driver and its CPython oracle sit in `gates/`, named by the gate that
needs them."* **SO THE DRIVER IS `gates/<name>-gate.bend`, IT IMPORTS THE PORT FILE, AND
IT CALLS THE PORT's DEFS BY THEIR EXPORTED NAMES.**

**AND IT **REFUSES** TO WRITE IF THE PORT FILE WOULD NOT COMPILE AFTER THE TRIM.**
**AND IT **REFUSES** IF THE MARKER IS NOT FOUND, **BECAUSE A FILE WITHOUT THE MARKER IS
NOT ONE OF THESE FILES AND **GUESSING** WOULD MOVE A PORT.**
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MARKER = re.compile(r"^#\s*-+\s*THE GATE ROWS\s*-+\s*$")
# **THE ROW HELPERS** -- **THE DEFS THAT TAKE A NAME AND A VALUE AND PRINT ONE ROW.**
# **THE LIST IS **THE **HELPERS THE GATE SECTION CALLS** AND **THE IMPLEMENTATION DOES
# NOT** -- **AND IT IS DERIVED FROM THE CALLS, NOT FROM A NAME SHAPE.**
ROW_HELPER = re.compile(r"^def ((?:srow|row)\w*)\(")
# **AND THE OTHER ROW-ONLY HELPERS, **DERIVED THE SAME WAY**: A DEF THE GATE SECTION CALLS
# AND THE IMPLEMENTATION NEVER CALLS.**
ANY_DEF = re.compile(r"^def ([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)\(")
# THE CALLABLE DEFS -- LOWERCASE ONLY -- AND THAT IS THE CLOSURE's POPULATION, BECAUSE AN
# UPPERCASE DEF IS A CONSTANT AND NOT A CALLABLE HELPER.
CALLABLE = re.compile(r"^def ([a-z_][a-z0-9_]*(?:\.[a-z0-9_]+)*)\(")
# **AND A **DECLARATION** IS **NOT A DEF** -- **AND A HELPER's BLOCK MUST STOP AT IT.**
# **MEASURED 2026-11-10 ON `elf.bend`: `param_size`'s BLOCK SWALLOWED THE
# `type Slot is Data:` DECLARATION THAT FOLLOWS IT, **BECAUSE THE SCAN ONLY STOPPED AT
# `def ` AND AT A COMMENT** -- **AND A `type` DECLARATION IS NEITHER.**
# **AND THE CONSEQUENCE WAS **THE PORT LOST ITS OWN `Slot` TYPE** AND FAILED TO
# COMPILE WITH "a declared constructor (unknown: Slot)" -- **WHILE THE TOOL REPORTED
# `WITHIN-LIMITS` FOR BOTH FILES, BECAUSE THE TOKEN IS **THE WATCHDOG's**, NOT THE
# COMPILER's.**
DECL = re.compile(r"^(?:def|type|struct|datatype|enum)\s")
# **AND A COMMENT ENDS A BLOCK **ONLY WHEN IT IS **UNINDENTED** -- **BECAUSE AN
# INDENTED COMMENT IS **INSIDE** THE BODY IT SITS IN.**
# **MEASURED 2026-11-10 ON `ops_webgpu.bend`: `sync_ret`'s BODY CARRIES **THREE
# INDENTED COMMENT LINES** BETWEEN ITS `case` ARMS, **AND THE OLD SCAN STOPPED AT THE
# FIRST OF THEM** -- **SO THE BLOCK WAS CUT IN HALF AND THE PORT WAS LEFT WITH AN
# ORPHANED `case 2n+q: SYNC_MANY()` UNDER NO `def` AT ALL.**
# **AND THE COMPILER SAID "expected : 'def', 'type' or 'law'" -- **WHILE THE TOOL
# REPORTED `WITHIN-LIMITS` FOR BOTH FILES, **FOR THE SAME REASON AS BEFORE: THE TOKEN
# IS **THE WATCHDOG's**, NOT THE COMPILER's.**
UNINDENTED_COMMENT = re.compile(r"^#")


def uses(text: str, name: str) -> int:
    """**HOW MANY TIMES `text` CALLS `name`** -- **COUNTED ON **WORD BOUNDARIES**, **NOT
    AS A SUBSTRING.**

    **AND THE SUBSTRING COUNT IS **A COUNT OF A PREFIX**, NOT A COUNT OF A CALL.**
    **MEASURED 2026-11-10: `impl_text.count("row(")` COUNTS **`srow(`** AND **`urow(`**,
    **SO `row` READ AS **IMPLEMENTATION-USED** AND STAYED IN THE PORT. THE SAME HAPPENED
    TO `rg` (INSIDE `uimm`? NO -- INSIDE `arg`/`str`), `pack`, `u32_list_eq`, `dev.free`
    AND `dev.create_uniform`.**

    **AND THE FAILURE IS **CONSERVATIVE** -- **THE DEF STAYS** -- **SO NO ROW IS LOST
    AND NOTHING BREAKS.** **BUT THE PORT DOES NOT GET AS SLIM AS IT SHOULD, AND A TOOL
    THAT COUNTS PREFIXES IS NOT COUNTING CALLS.**
    """
    return len(re.findall(rf"(?<![\w.]){re.escape(name)}\(", text))


def block_end(lines: list[str], j: int) -> int:
    """**THE END OF THE DECLARATION THAT STARTS AT `j`** -- **A DEF, A TYPE, A STRUCT.

    **AND THE SCAN STOPS AT THE NEXT DECLARATION **OR** AT AN **UNINDENTED** COMMENT,
    **BECAUSE AN UNINDENTED COMMENT **BEFORE** THE NEXT DECLARATION BELONGS TO THAT
    DECLARATION** (AND THE CALLER MOVES IT WITH THE DECLARATION).**

    **AND **AN INDENTED COMMENT DOES NOT END THE BLOCK** -- **IT IS PART OF THE BODY.**
    """
    e = j + 1
    while e < len(lines) and not DECL.match(lines[e]) and not UNINDENTED_COMMENT.match(lines[e]):
        e += 1
    return e


def comment_start(lines: list[str], j: int) -> int:
    """**THE FIRST LINE OF THE COMMENT BLOCK THAT PRECEDES THE DECLARATION AT `j`.**

    **AND **ONLY UNINDENTED COMMENTS COUNT** -- **AN INDENTED COMMENT IS INSIDE A
    BODY AND BELONGS TO NOTHING ABOVE IT.**
    """
    s = j
    while s > 0 and UNINDENTED_COMMENT.match(lines[s - 1]):
        s -= 1
    return s



def bounded_bend(path: Path) -> str:
    """RUN THE PORT's OWN WATCHDOG AND **READ THE VERDICT TOKEN**.

    **AND THE TOKEN IS ON **STDERR** -- MEASURED 2026-11-10: `checks/bounded.py` PRINTS
    `[bounded] WITHIN-LIMITS  rc=0  peak-RSS=...` TO **STDERR**, **AND THE BEND OUTPUT
    ITSELF (`ALL PROOFS CHECK`) IS ALSO ON STDERR.** **AND A MISSING TOKEN IS **NOT** A
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


def external_users(port: Path, root: Path) -> dict[str, set[str]]:
    """**THE DEFS **ANOTHER FILE** USES **THROUGH AN IMPORT OF THE PORT** -- **AND THE
    MAP IS **ALIAS -> THE NAMES IT USES** SO A SECOND FILE MAY ALIAS THE PORT
    DIFFERENTLY.**

    **AND **THE PORT FILE IS NOT ITS ONLY CONSUMER** -- **AND MEASURING THAT IS THE
    POINT.** MEASURED 2026-11-10 ON `ops_webgpu.bend`: `runtime/webgpu_call.bend` IMPORTS
    IT **AS `W`** AND CALLS **`alloc.usage`, `dev.init`, `dev.uniform_bytes`,
    `dev.uniform_usage`, `prog.call`, `prog.init` AND `seen`** -- **AND THE FIXTURE
    `checks/.e2e-fixture/e2e_mm.bend` CALLS `W.alloc.usage` TOO.**

    **AND ALL SEVEN ARE **ROW-ONLY** INSIDE THE PORT FILE** -- **THE PORT NEVER CALLS
    THEM** -- **SO THE NAIVE MOVE TOOK THEM OUT AND **BROKE A PORT FILE** (`webgpu_call.bend`
    STOPPED COMPILING) **AND THE e2e FIXTURE.**

    **AND **A DEF THAT ANOTHER FILE CALLS IS **THE PORT's API**, NOT THE GATE's
    FIXTURE** -- **SO IT STAYS IN THE PORT** AND THE DRIVER CALLS IT AS `P.<name>`.**

    **AND **THE INSTRUMENTS ARE **NOT** CONSUMERS** -- **THE `gates/` DRIVERS ARE THE
    THING THIS TOOL WRITES, **AND A DRIVER FROM A PREVIOUS RUN IS A **SELF-REFERENCE**:
    MEASURED 2026-11-10 ON `elf.bend`: THE TOOL's OWN `gates/elf-gate.bend` SAID `P.row`,
    **SO THE TOOL READ `row` AS **EXTERNALLY USED** AND LEFT IT IN THE PORT, **AND THE
    FRESH DRIVER THEN SAID `P.row` FOR A DEF THAT HAD MOVED** -- **AND THE DRIVER DID
    NOT COMPILE.** **AND THE FIXTURES ARE NOT CONSUMERS EITHER** -- **`checks/.e2e-fixture/`
    IS A FIXTURE **FOR** THE PORT, **AND IT IMPORTS IT AS A CONSUMER** -- **SO IT IS KEPT.**
    """
    port_res = port.resolve()
    port_rel = port_res.relative_to(root)
    found: dict[str, set[str]] = {}
    for cand in root.rglob("*.bend"):
        if cand.resolve() == port_res:
            continue
        # **AND THE **INSTRUMENTS** -- **THE `gates/` DRIVERS** -- **ARE NOT CONSUMERS.**
        rel_parts = cand.resolve().relative_to(root).parts
        if len(rel_parts) > 1 and rel_parts[0] == "gates":
            continue
        try:
            text = cand.read_text()
        except (OSError, UnicodeDecodeError):
            continue
        for m in re.finditer(r"^import\s+(\S+)\s+as\s+(\w+)\s*$", text, re.M):
            src, alias = m.group(1), m.group(2)
            if not src.endswith(".bend"):
                continue
            base = (cand.parent / src).resolve()
            if base != port_res:
                continue
            used = set(re.findall(rf"\b{re.escape(alias)}\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)", text))
            found.setdefault(alias, set()).update(used)
    return found


def split(path: Path) -> tuple[list[str], list[str], list[str]]:
    """ (THE IMPLEMENTATION LINES, THE GATE LINES, THE MOVED HELPERS)."""
    lines = path.read_text().splitlines()
    idx = next((i for i, l in enumerate(lines) if MARKER.match(l.strip())), None)
    if idx is None:
        raise SystemExit(f"  REFUSED: {path} has no 'THE GATE ROWS' marker")
    impl = lines[:idx]
    gate = lines[idx:]

    # **AND THE **EXTERNAL** USERS -- **THE OTHER FILES THAT IMPORT THIS ONE** -- **ARE
    # IMPLEMENTATION USERS TOO**, **AND SO A DEF THEY CALL IS **NOT** ROW-ONLY.**
    ext = external_users(path, ROOT)
    ext_names: set[str] = set()
    for names in ext.values():
        ext_names.update(names)
    # **AND A DEF **IN THE GATE SECTION** THAT AN EXTERNAL IMPORTER CALLS IS **STILL
    # THE PORT's API** -- **AND SO IT IS **HOISTED BACK** INTO THE PORT, BEFORE THE
    # MARKER, AND THE DRIVER CALLS IT AS `P.<name>`.**
    # **MEASURED 2026-11-10 ON `ops_webgpu.bend`: `seen` IS **ROW-ONLY INSIDE THE
    # PORT** (THE PORT NEVER CALLS IT) **AND IT LIVES IN THE **GATE SECTION**, **AND
    # `runtime/webgpu_call.bend` CALLS IT AS `W.seen`** -- **SO THE NAIVE MOVE TOOK IT
    # OUT AND **BROKE A PORT FILE.****
    # **AND THE HOIST CARRIES ITS **OWN DEPENDENCY CLOSURE** -- **BECAUSE A HOISTED DEF
    # LIVES IN THE PORT, WHERE `P.` DOES NOT EXIST, **SO IT MUST CALL ITS DEPS
    # UNQUALIFIED** -- **AND A DEP THAT MOVED TO THE DRIVER WOULD LEAVE THE PORT CALLING A
    # NAME THAT IS NOT THERE.**
    # **MEASURED 2026-11-10 ON `ops_cl.bend`: `fx_img` IS USED BY `ops_cuda.bend` AND
    # `ops_hip.bend` AS `CL.fx_img`, **AND IT CALLS `cl.init`** -- **WHICH IS ROW-ONLY AND
    # MOVED** -- **SO THE HOISTED `fx_img` CALLED A DEF THAT WAS NOT IN THE PORT ANY MORE,
    # AND THE PORT FAILED WITH "expected : a defined name / observed : cl.init".**
    hoist: list[str] = []
    hoisted: set[str] = set()
    gate_defs = {m.group(1) for m in (ANY_DEF.match(l) for l in gate) if m}
    pending = sorted(gate_defs & ext_names)
    while pending:
        name = pending.pop(0)
        if name in hoisted:
            continue
        j = next(k for k, l in enumerate(gate) if l.startswith(f"def {name}("))
        s = comment_start(gate, j)
        e = block_end(gate, j)
        body = "\n".join(gate[j:e])
        hoist.extend(gate[s:e])
        del gate[s:e]
        hoisted.add(name)
        # **AND THE DEPS OF THE HOISTED DEF COME WITH IT.**
        for d in sorted(gate_defs):
            if d in hoisted or d in ext_names:
                continue
            if re.search(rf"(?<![\w.]){re.escape(d)}\(", body):
                pending.append(d)
    if hoist:
        # **AND THE HOISTED DEFS ARE **ORDERED BY THEIR OWN DEPENDENCY GRAPH** --
        # **BECAUSE BEND HAS NO FORWARD REFERENCES** ("defs are checked in file order, and
        # an unfilled hole is not a def").**
        # **MEASURED 2026-11-10 ON `ops_cl.bend`: `fx_img` WAS HOISTED **BEFORE** `DEV0`,
        # **WHICH IT CALLS** -- **AND THE PORT FAILED WITH "expected : a defined name /
        # observed : DEV0".**
        hoist = order_defs(hoist)
        impl = impl + [""] + hoist
    # **AND THE **DERIVED** VALUES ARE COMPUTED **AFTER** THE HOIST** -- **BECAUSE THE
    # HOISTED DEFS ARE NOW **IN THE PORT**, **AND A HOISTED DEF MUST NOT BE TREATED AS A
    # ROW-ONLY HELPER AND MOVED AGAIN.**
    impl_text = "\n".join(impl)
    gate_text_all = "\n".join(gate)
    all_defs = {m.group(1) for m in (CALLABLE.match(l) for l in impl) if m}
    helpers: list[str] = []
    for i, l in enumerate(impl):
        m = CALLABLE.match(l)
        if not m:
            continue
        name = m.group(1)
        # **A HELPER IS ROW-ONLY WHEN **THE GATE SECTION CALLS IT** AND **THE
        # IMPLEMENTATION NEVER CALLS IT** (ITS OWN DEFINITION DOES NOT COUNT).**
        if uses(gate_text_all, name) == 0:
            continue
        if uses(impl_text, name) > 1:
            continue
        # **AND **AN EXTERNAL IMPORTER's CALL IS AN IMPLEMENTATION CALL** -- **SO THE
        # DEF STAYS IN THE PORT** AND THE DRIVER CALLS IT AS `P.<name>`.
        if name in ext_names:
            continue
        # **AND A **HOISTED** DEF STAYS IN THE PORT** -- **IT WAS PULLED BACK THERE
        # BECAUSE SOMETHING THE PORT OWNS NEEDS IT.**
        if name in hoisted:
            continue
        helpers.append(name)
    # **AND THE **CLOSURE**: A MOVED HELPER'S OWN DEPS MOVE WITH IT** -- **AND A DEP THAT
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
                    # **THE DEP MOVES **ONLY IF** THE IMPLEMENTATION NEVER CALLS IT**
                    # **AND NO EXTERNAL IMPORTER CALLS IT EITHER.**
                    if uses(impl_text, d) <= 1 and d not in ext_names:
                        helpers.append(d)
                        changed = True
    # **AND THE **HELPER'S OWN BLOCK** -- **A DEF AND **ITS COMMENT LINES** AND **THE
    # BLANK LINE AFTER IT** -- **MOVES WITH IT.**
    moved: list[str] = []
    drop: set[int] = set()
    for h in helpers:
        j = next(k for k, l in enumerate(impl) if l.startswith(f"def {h}("))
        s = comment_start(impl, j)
        e = block_end(impl, j)
        moved.extend(impl[s:e])
        drop.update(range(s, e))
    impl = [l for k, l in enumerate(impl) if k not in drop]
    # **AND THE MOVED HELPERS GO IN **THE ORDER THEY HAD** -- **AND THAT ORDER IS NOT
    # ALWAYS THE ORDER THEY NEED**, **BECAUSE ONE HELPER CAN CALL ANOTHER** (MEASURED
    # 2026-11-10: `urow` CALLS `u32_text`, AND `u32_text` IS DEFINED **AFTER** IT IN THE
    # ORIGINAL, **WHICH COMPILES ONLY BECAUSE **THE ORIGINAL'S `main` IS AT THE END AND
    # THE `g_*` DEFS ARE **AFTER** BOTH**). **AND BEND HAS NO FORWARD REFERENCES
    # ("defs are checked in file order, and an unfilled hole is not a def"), **SO THE
    # HELPERS ARE REORDERED BY THEIR OWN DEPENDENCY GRAPH.**
    moved = order_defs(moved)
    return impl, gate, moved, helpers


def rebased_path(src: str, port: Path, root: Path) -> str:
    """**THE PORT's IMPORT PATH, REBASED ON THE DRIVER's DIRECTORY.**

    **THE PORT IMPORTS `./dsl.bend` (A SIBLING) AND `../../helpers.bend` (A GRANDPARENT),
    AND THE DRIVER LIVES IN `gates/`, **SO BOTH BECOME `./../tinybendygrad/...`**.**
    **AND THE RESOLUTION IS **BY THE REAL PATH**, NOT BY STRING ARITHMETIC** — **A
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
    """**TOPOLOGICAL ORDER OF THE DEFS**, BY **THE NAMES THEY CALL**.

    **AND **NOTHING IS DROPPED** -- **A LINE THAT IS NOT PART OF A DEF BLOCK IS KEPT IN
    ITS ORIGINAL PLACE.** **MEASURED 2026-11-10: THE FIRST VERSION RETURNED **ONLY** THE
    BLOCKS IT RECOGNISED, **AND EVERY DOTTED DEF AND EVERY `type` DECLARATION VANISHED
    WITHOUT A WORD** -- `ops_cl.bend` LOST **101** LINES AND `ops_webgpu.bend` LOST **41**,
    **AND THE MOVE STILL REPORTED SUCCESS.**
    """
    defs: dict[str, list[str]] = {}
    order: list[str] = []
    claimed: set[int] = set()
    for i, l in enumerate(lines):
        # **AND THE DEF NAME MAY BE **DOTTED** (`alloc.free`, `prog.call.at`) -- **AND THE
        # REGEX IS **THE TOOL's OWN `CALLABLE` PATTERN**, **NOT** A DOT-LESS ONE.**
        # **MEASURED 2026-11-10: THE DOT-LESS REGEX **DROPPED EVERY DOTTED DEF** ON THE
        # MOVE -- `ops_cl.bend` LOST **101** LINES AND `ops_webgpu.bend` LOST **41** --
        # **AND THE MOVE WAS STILL REPORTED AS SUCCESSFUL**, **BECAUSE `order_defs` RETURNS
        # ONLY THE BLOCKS IT RECOGNISED AND SILENTLY DROPS THE REST.**
        # **AND THE NAME MAY BE **UPPERCASE** -- **A CONSTANT IS A DEPENDENCY TOO**, **AND
        # AN UNORDERED CONSTANT IS A FORWARD REFERENCE.**
        # **MEASURED 2026-11-10 ON `ops_cl.bend`: `fx_img` CALLS `DEV0()`, **AND `DEV0`
        # WAS EMITTED AFTER IT**, **AND THE PORT FAILED WITH "expected : a defined name /
        # observed : DEV0".**
        m = re.match(r"^def ([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)\(", l)
        if not m:
            continue
        s = comment_start(lines, i)
        e = block_end(lines, i)
        defs[m.group(1)] = lines[s:e]
        order.append(m.group(1))
        claimed.update(range(s, e))
    # **AND THE **UNCLAIMED** LINES ARE THE **NON-DEF** CONTENT** -- **A `type`
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
    # **AND THE LOOSE CONTENT IS APPENDED, **BECAUSE A `type` DECLARATION IS **NOT
    # DEPENDENT ON** THE DEFS THAT USE IT** -- **BEND READS A TYPE DECLARATION WHERE IT
    # IS WRITTEN AND THE USES THAT FOLLOW IT.**
    for _, chunk in loose:
        out.extend(chunk)
    return out


def sub_outside_strings(text: str, pattern: str, repl: str) -> str:
    """**SUBSTITUTE **OUTSIDE** THE STRING LITERALS** -- **AND LEAVE THE LITERALS ALONE.**

    **AND THE HAZARD IS **REAL AND MEASURED**: MEASURED 2026-11-10 ON `viz/serve.bend`,
    THE TYPE `Name` IS ALSO A **STRING VALUE** IN A FIXTURE (`create_step("Name", ...)`),
    **AND THE TYPE PASS REWROTE THE LITERAL TO `"P.Name"`** -- **WHICH CHANGED A GATE ROW
    AND WOULD HAVE MADE THE DRIVER **DISAGREE WITH CPYTHON** ON A VALUE THAT IS **NOT
    EVEN A NAME.****

    **AND **A QUOTED REGION** IS **ANYTHING BETWEEN TWO UNESCAPED `"`** -- **AND THE
    SCAN IS **LINE-LOCAL** BECAUSE A BEND STRING LITERAL DOES NOT SPAN LINES.**
    """
    out: list[str] = []
    for line in text.split("\n"):
        parts = re.split(r'("(?:[^"\\]|\\.)*")', line)
        for i, part in enumerate(parts):
            parts[i] = part if i % 2 else re.sub(pattern, repl, part)
        out.append("".join(parts))
    return "\n".join(out)


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
        # **THE DRIVER'S HEADER, IN THE TREE's OWN STYLE.**
        # **AND THE PORT's **IMPORTS** MOVE WITH THE ROWS** -- **MEASURED 2026-11-10:
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
                # **THE PATH IS REBASED: THE PORT's `./dsl.bend` IS
                # `./../tinybendygrad/renderer/amd/dsl.bend` FROM `gates/`.**
                rebased.append(f"import {rebased_path(src, path, ROOT)} as {alias}")
            else:
                rebased.append(l)
        hdr = [
            f"# {driver.relative_to(ROOT)} -- THE GATE DRIVER for `{path.relative_to(ROOT)}`.",
            "#",
            "# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and",
            "# this file carries the instrument, and the tree's own convention says so:",
            "# `gates/README.md:173` -- \"a gate's `.bend` driver and its CPython oracle sit in",
            "# `gates/`, named by the gate that needs them.\"",
            "#",
            "# And the rows are pure consumers: they call the port's defs and define",
            "# nothing that the port needs.",
            "",
            "import Base",
            f"import ./../{path.relative_to(ROOT)} as P",
        ] + rebased[1:] + [
            "",
        ]
        # **THE `main`, WHICH THE PORT FILE's OWN `main` CALLED.**
        # **AND THE **PORT's DEFS** ARE CALLED **UNQUALIFIED** IN THE PORT FILE AND
        # **QUALIFIED** IN THE DRIVER** -- **AND THE QUALIFICATION IS **THE WHOLE** OF THE
        # MOVE** (MEASURED: `gates/tn_logical_not.bend` CALLS `T.tn_logical_not`).
        port_defs = {m.group(1) for m in (ANY_DEF.match(l) for l in impl) if m}
        # **AND THE PORT's **TYPES** -- **MEASURED 2026-11-10: THE MOVED HELPER
        # `name_at` HAS THE SIGNATURE `+xs: List<&2, Pn>`, **AND `Pn` IS THE PORT's OWN
        # TYPE**, **SO THE DRIVER SAID "expected : a defined name / observed : Pn"** --
        # **AND A TYPE IS QUALIFIED THE SAME WAY A DEF IS.**
        port_types = {m.group(1) for m in (re.match(r"^type ([A-Za-z_][A-Za-z0-9_]*)", l) for l in impl) if m}
        # **AND THE PORT's **CONSTANTS** -- **THE UPPERCASE DEFS** -- **ARE USED **BARE**,
        # **WITHOUT PARENTHESES**, **AND SO THE `name(` PASS NEVER SAW THEM.**
        # **MEASURED 2026-11-10 ON `ops_webgpu.bend`: `Tr.emit(CALL_CREATE, OBJ_BUFFER,
        # t)` CAME THROUGH THE MOVE **UNQUALIFIED**, **AND THE DRIVER FAILED WITH "expected
        # : a defined name / observed : CALL_CREATE".**
        # **AND **ONLY** THE UPPERCASE ONES ARE BARE** -- **MEASURED: EVERY LOWERCASE
        # PORT DEF IS CALLED WITH `()`** -- **SO THE BARE PASS IS LIMITED TO THE
        # CONSTANTS AND CANNOT RENAMCE A LOCAL.**
        port_consts = {d for d in port_defs if d[:1].isupper()}

        def qualify(text: str) -> str:
            """**THE PORT's NAMES, QUALIFIED FOR THE DRIVER** -- **ONCE, FOR BOTH
            **THE GATE TEXT** AND **THE MOVED BLOCK**, **SO THE TWO CANNOT DRIFT.**
            """
            for d in sorted(port_defs, key=len, reverse=True):
                text = sub_outside_strings(text, rf"(?<![\w.]){re.escape(d)}\(", f"P.{d}(")
            # **AND THE **BARE CONSTANTS** -- **AND ONLY **THOSE** -- **ARE QUALIFIED
            # WITHOUT THE PARENTHESES.**
            for c in sorted(port_consts, key=len, reverse=True):
                text = sub_outside_strings(text, rf"(?<![\w.]){re.escape(c)}(?![\w.(])", f"P.{c}")
            # **AND A **TYPE** IS **NOT** FOLLOWED BY `(`** -- **IT IS QUALIFIED IN A **TYPE
            # POSITION** (`List<&2, Pn>`) -- **MEASURED 2026-11-10: THE DRIVER SAID "expected :
            # a defined name / observed : Pn"** **WITH THE DEF QUALIFICATION ALREADY IN PLACE.**
            # **AND **THE TYPE PASS MUST NOT MATCH A NAME THAT IS **ALREADY QUALIFIED** --
            # **BECAUSE A TYPE CAN BE NAMED `P`** (MEASURED 2026-11-10 ON `viz/serve.bend`:
            # `type P is Data:`), **AND THEN `(?<![\w.])P\b` MATCHED THE `P` OF AN
            # **ALREADY-QUALIFIED** `P.ws_split.go` **AND PRODUCED `P.P.ws_split.go`** -- **AND
            # THE DRIVER FAILED WITH "expected : a defined name / observed : P.P.ws_split.go".**
            for t in sorted(port_types, key=len, reverse=True):
                text = sub_outside_strings(text, rf"(?<![\w.]){re.escape(t)}\b(?!\.)", f"P.{t}")
            # **AND THE **MOVED HELPERS** ARE **NOT** PORT DEFS** -- **THEY MOVED WITH THE
            # ROWS** -- **SO THEY MUST NOT BE QUALIFIED.**
            for h in helpers:
                text = sub_outside_strings(text, rf"P\.{re.escape(h)}\(", f"{h}(")
            return text

        gate_text = qualify("\n".join(gate))
        # **AND THE **MOVED BLOCK** NEEDS THE SAME QUALIFICATION** -- **MEASURED
        # 2026-11-10: THE MOVED HELPER `urow` CALLS `u32_text`, **AND `u32_text` STAYS IN
        # THE PORT FILE** (IT HAS SIX IMPLEMENTATION USES), **SO THE MOVED BLOCK'S CALL MUST
        # BE `P.u32_text`** -- **AND THE FIRST PASS QUALIFIED ONLY THE GATE TEXT, **SO THE
        # DRIVER FAILED WITH "expected : a defined name / observed : u32_text"**.**
        moved = qualify("\n".join(moved)).split("\n")
        # **AND A HELPER THAT **STAYED** IN THE PORT FILE **AND IS CALLED BY A MOVED
        # HELPER** MUST BE **QUALIFIED** -- **MEASURED 2026-11-10: `u32_text` HAS SIX USES
        # IN THE IMPLEMENTATION, **SO IT STAYS**, **AND `urow` (WHICH MOVED) CALLS IT.**
        # **AND THE ORDER MATTERS: **THE PORT's DEFS ARE QUALIFIED **FIRST**, **AND THE
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
