#!/usr/bin/env python3
"""extract-gate-rows-producers.py -- MOVE A `.bend` FILE's GATE ROWS INTO `gates/`.

    .venv/bin/python .agents/slop/loc/extract-gate-rows-producers.py --apply <file.bend> [...]

**WHY A SECOND TOOL, AND WHAT IT IS FOR.** THE PROVEN TOOL
(`extract-gate-rows.py`) FINDS THE GATE SECTION BY A **MARKER LINE**
(`# --- THE GATE ROWS ---`), **AND THAT IS TRUE OF `sqtt.bend` AND FALSE OF THE
FIVE FILES THIS TOOL IS FOR**: THEIR GATE SECTION IS **NOT** A CONTIGUOUS
SUFFIX -- **THE PRODUCER DEFS ARE INTERLEAVED WITH IMPLEMENTATION DEFS**, SO A
SUFFIX SPLIT WOULD **CARRY THE PORT WITH IT** AND **THE MOVE WOULD BE A MOVE
OF THE PORT.**

**SO THE POPULATION IS FOUND BY **DISCOVERY**, NOT BY A MARKER**: A **PRODUCER**
IS **A DEF WHOSE BODY CALLS `row`/`srow`/`urow`**, **AND THE POPULATION IS THE
PRODUCERS PLUS THEIR ROW-ONLY CLOSURE.**

**AND THE PROOF THAT THE POPULATION IS A POPULATION IS **MEASURED, NOT
ASSUMED**: EVERY PRODUCER IS CALLED **ONLY** BY `main` (OR BY ANOTHER
PRODUCER), **SO THE PORT NEVER CALLS A ROW** -- **AND THE TOOL **REFUSES** IF
IT FINDS A PRODUCER THE IMPLEMENTATION CALLS.**

**AND THE TOOL **REFUSES** TO WRITE IF EITHER FILE WOULD NOT COMPILE, **AND IT
READS THE VERDICT TOKEN AND NOT THE EXIT CODE** (`checks/bounded.py`:
`WITHIN-LIMITS` / `KILLED-ON-MEMORY` / `TIMED-OUT`).
"""

import argparse
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# **THE PROVEN TOOL IS LOADED **BY PATH** -- **SO THE QUALIFICATION, THE
# REBASE AND THE ORDERING ARE THE PROVEN ONES AND NOT A REWRITE OF THEM.**
_spec = importlib.util.spec_from_file_location(
    "xgr", ROOT / ".agents/slop/loc/extract-gate-rows.py")
xgr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(xgr)

DEF = re.compile(r"^def ([A-Za-z_][A-Za-z0-9_.]*)\(")
ROW_CALL = re.compile(r"(?<![\w.])(srow|urow|row)\s*\(")


def strip_comments(lines: list[str]) -> list[str]:
    """**THE CODE OF EACH LINE, WITH THE `#` COMMENT REMOVED.**

    **AND THIS MATTERS BECAUSE A COMMENT **CAN** NAME A ROW** -- MEASURED
    2026-11-10 ON `tinybendygrad/runtime/ops_nv.bend`: THE COMMENT ABOVE
    `iface.err_str_of` QUOTES `row("nv_err_0_err", "")` **AND A NAIVE SCAN READ
    `iface.err_str_of` AS A PRODUCER**, **WHICH WOULD HAVE MOVED AN
    IMPLEMENTATION DEF INTO THE DRIVER.**
    """
    return [(l[: l.find("#")] if "#" in l else l) for l in lines]


def def_blocks(lines: list[str]) -> list[tuple[str, int, int]]:
    """ (NAME, START LINE, END LINE) FOR EVERY TOP-LEVEL DEF, IN FILE ORDER."""
    starts = [i for i, l in enumerate(lines) if DEF.match(l)]
    out = []
    for k, i in enumerate(starts):
        end = starts[k + 1] if k + 1 < len(starts) else len(lines)
        out.append((DEF.match(lines[i]).group(1), i, end))
    return out


def block_start(lines: list[str], i: int) -> int:
    """ THE DEF's FIRST LINE, **PULLING IN THE COMMENT LINES ABOVE IT**.

    **AND THE COMMENTS BELOW A DEF (BETWEEN IT AND THE NEXT DEF) ARE **NOT**
    PULLED IN**, **BECAUSE A COMMENT MAY DESCRIBE THE **NEXT** DEF** -- MEASURED
    2026-11-10 ON `ops_qcom.bend`: THE COMMENT ABOVE `t_regs` DESCRIBES
    `reg_line`, **WHICH IS ABOVE `t_regs`** -- **SO THE COMMENT BELOW `reg_line`
    DESCRIBES `t_regs` AND MUST STAY WITH IT.**
    """
    s = i
    while s > 0 and lines[s - 1].strip().startswith("#"):
        s -= 1
    return s


def producers(lines: list[str]) -> tuple[set[str], dict[str, tuple[int, int]]]:
    """ (THE PRODUCER NAMES, THE BLOCK SPANS), FOUND BY **DISCOVERY**."""
    code = strip_comments(lines)
    names: set[str] = set()
    spans: dict[str, tuple[int, int]] = {}
    for name, i, end in def_blocks(code):
        if name in ("row", "srow", "urow"):
            continue
        if ROW_CALL.search("\n".join(code[i:end])):
            names.add(name)
            spans[name] = (i, end)
    return names, spans


def importers_of(path: Path) -> list[Path]:
    """**THE FILES THAT IMPORT `path`, FOUND BY **A DIRECTORY WALK** -- **NOT
    BY A HAND LIST** (DOCTRINE 1: A POPULATION IS DECLARED BY DISCOVERY).

    **AND **EVERY** IMPORT LINE IS EXAMINED** -- **MEASURED 2026-11-10: A
    SINGLE `re.search` FOUND **ONLY THE FIRST** `import ... as ...` LINE, **AND
    `elf.bend`'s FIRST ALIASED IMPORT IS `../../helpers.bend`, **SO `dsl.bend`
    WAS NEVER SEEN** AND THE CROSS-FILE CONSTRAINT WAS SILENTLY INERT.**
    """
    target = path.resolve()
    out: list[Path] = []
    for base in ("tinybendygrad", "gates"):
        for p in (ROOT / base).rglob("*.bend"):
            if p.resolve() == target:
                continue
            for m in re.finditer(r"^import\s+(\S+)\s+as\s+(\w+)\s*$", p.read_text(), re.M):
                try:
                    resolved = (p.parent / m.group(1)).resolve()
                except OSError:
                    continue
                if resolved == target:
                    out.append(p)
                    break
    return out


def external_users(path: Path, names: set[str], alias_of: dict[str, str]) -> dict[str, list[str]]:
    """ THE NAMES **ANOTHER FILE** USES THROUGH ITS IMPORT ALIAS -- **AND SO
    THE DEFS THAT MUST **STAY** IN THE PORT FILE.**

    **MEASURED 2026-11-10 ON `tinybendygrad/renderer/amd/dsl.bend`: `elf.bend`
    CALLS `D.V_LO()`, **AND `V_LO` IS ROW-ONLY INSIDE `dsl.bend`**, **SO THE
    CLOSURE WOULD HAVE MOVED IT** -- **AND `elf.bend` WOULD HAVE FAILED TO
    COMPILE.** **AND THE FIX IS THE TOOL's OWN "STAY-AND-QUALIFY RULE" AT THE
    **TREE** LEVEL: A DEF **ANOTHER FILE** REACHES **STAYS** AND IS CALLED
    `P.<name>` IN THE DRIVER.**
    """
    out: dict[str, list[str]] = {}
    for imp in importers_of(path):
        txt = imp.read_text()
        for m in re.finditer(r"^import\s+(\S+)\s+as\s+(\w+)\s*$", txt, re.M):
            alias = m.group(2)
            for n in names:
                if re.search(r"(?<![\w.])" + re.escape(alias) + r"\." + re.escape(n) + r"(?![\w.])", txt):
                    out.setdefault(n, []).append(str(imp.relative_to(ROOT)))
    return out


def analyse(path: Path) -> dict:
    """ THE POPULATION, THE CLOSURE, AND THE REFUSALS -- **MEASURED**."""
    lines = path.read_text().splitlines()
    code = strip_comments(lines)
    prods, _spans = producers(lines)
    if not prods:
        raise SystemExit(f"  REFUSED: {path} has no row producer")
    blocks = def_blocks(code)
    byname = {n: (i, e) for n, i, e in blocks}
    # **AND THE **CALL GRAPH** -- **AND **THE DEF's OWN DEFINITION LINE IS
    # EXCLUDED** -- **BECAUSE `def reg_line(` **IS** A MATCH FOR `reg_line(`**
    # -- **MEASURED 2026-11-10: WITHOUT THE EXCLUSION EVERY DEF LOOKED CALLED
    # ONCE BY ITSELF AND **THE ROW-ONLY CLOSURE WAS EMPTY** FOR **EVERY**
    # FILE, **AND A MOVED DRIVER **DID NOT COMPILE** BECAUSE ITS OWN HELPERS
    # WERE LEFT BEHIND."""
    calls: dict[str, set[str]] = {}
    for n, i, e in blocks:
        # **AND THE **DEF's OWN NAME** IS EXCLUDED **BY THE LOOKBEHIND**,
        # **NOT BY SKIPPING THE LINE** -- **BECAUSE A **ONE-LINE DEF** CARRIES
        # ITS BODY **ON THE DEF LINE** -- **MEASURED 2026-11-10:
        # `def hx.q(+v: U32) -> String: hx.q.pick(hx.d4(v), hx.width(v))` IS **ONE
        # LINE**, **AND SKIPPING THE LINE DROPPED **EVERY** CALL IT MAKES**,
        # **WHICH IS WHY `hx.width` LOOKED UNCALLED** **AND MOVED** **WHILE
        # `hx.q` **STAYED** **AND `hx.q` **CALLS IT** -- **AND THE PORT WAS
        # LEFT CALLING A DEF THAT HAD LEFT.**
        body = "\n".join(code[i:e])
        called = set()
        for m in byname:
            if m == n:
                continue
            if re.search(r"(?<![\w.])" + re.escape(m) + r"\s*\(", body):
                called.add(m)
        calls[n] = called
    # **AND THE **AGGREGATORS**: A DEF THAT CALLS **ONLY** PRODUCERS AND
    # **NO PORT DEF** IS AN AGGREGATOR AND BELONGS TO THE ROW SECTION.
    aggs: set[str] = set()
    changed = True
    while changed:
        changed = False
        for n, called in calls.items():
            if n in prods or n in aggs or n == "main":
                continue
            if called and called <= (prods | aggs):
                aggs.add(n)
                changed = True
    section = prods | aggs
    # **AND THE REFUSAL: A PRODUCER CALLED BY A DEF **OUTSIDE THE ROW
    # SECTION** -- **AND THE ONLY DEF OUTSIDE THAT MAY CALL ONE IS `main`.**
    # **AND THE **CALLERS** ARE THE INVERSE OF `calls`, **AND GETTING THAT
    # INVERTED **REFUSED EVERY FILE** -- **MEASURED 2026-11-10: `calls[p]` IS
    # **WHAT `p` CALLS**, **NOT **WHO CALLS `p`**.**
    callers_of: dict[str, set[str]] = {n: set() for n in calls}
    for n, called in calls.items():
        for m in called:
            callers_of[m].add(n)
    bad = {p: sorted(callers_of[p] - section - {"main"}) for p in prods if callers_of[p] - section - {"main"}}
    if bad:
        raise SystemExit(f"  REFUSED: {path}: producers called by the implementation: {bad}")
    # **AND THE **ROW-ONLY CLOSURE**: A DEF **THE ROW SECTION CALLS** **AND
    # THE IMPLEMENTATION NEVER CALLS** MOVES WITH THE ROWS.
    # **AND "THE ROW SECTION CALLS IT" IS `callers_of[n] & section`, **AND
    # "THE IMPLEMENTATION CALLS IT" IS `callers_of[n] & (IMPL)`** -- **AND THE
    # INVERSE OF `calls` IS **THE ONLY WAY** TO ASK **BOTH**."
    impl_set = set(calls) - section - {"main"}
    # **AND THE **CROSS-FILE** CONSTRAINT: A DEF **ANOTHER FILE** REACHES
    # **THROUGH THE IMPORT ALIAS** **MUST STAY IN THE PORT FILE** -- **AND THE
    # DRIVER CALLS IT `P.<name>`** (THE TOOL's OWN "STAY-AND-QUALIFY RULE", AT
    # THE **TREE** LEVEL RATHER THAN THE FILE LEVEL).
    alias_of: dict[str, str] = {}
    for l in path.read_text().splitlines():
        m = re.match(r"^import (\S+) as (\w+)$", l)
        if m:
            alias_of[m.group(2)] = m.group(1)
    ext = external_users(path, set(calls), alias_of)
    # **=> AND THE **MOVED SET** IS **THE PROVEN TOOL's OWN RULE** -- **A DEF
    # MOVES IFF **THE ORIGINAL IMPLEMENTATION** CALLS IT **AT MOST ONCE** --
    # **AND THAT ONCE IS **ITS OWN DEFINITION**.
    # **=> AND THE FIRST VERSION USED **A FIXPOINT**, **AND THE FIXPOINT
    # CASCADED** -- **MEASURED 2026-11-10: `sys.reserve_va` IS CALLED ONLY BY
    # THE ROWS, **SO IT MOVED**, **AND THEN `sys.reserve_va.put` MOVED**, **AND
    # THEN `sys.reserve_va.take` MOVED**, **AND THEN `CALL_MMAP` MOVED** --
    # **AND `CALL_MMAP` IS **THE PORT's OWN CONSTANT** (`def CALL_MMAP() ->
    # U32: 2`), **AND THE PORT WAS LEFT WITH **501** LINES AND **NO MMAP
    # CALL**.  **=> AND THE CASCADE IS **THE WRONG SHAPE**: IT GROWS THE MOVE
    # SET **WITHOUT BOUND**, **AND THE PORT MUST KEEP **THE CONSTANTS AND THE
    # SEAMS** IT CALLS.**
    # **=> AND THE PROVEN TOOL's RULE IS **A COUNT OVER THE IMPLEMENTATION
    # TEXT**, **AND THE COUNT IS **OVER **THE CODE**, **NOT THE RAW TEXT** --
    # **SO A COMMENT CANNOT COUNT** -- **AND A DEF's OWN DEFINITION LINE
    # COUNTS ONCE**, **SO THE THRESHOLD IS **2** (THE DEFINITION **PLUS** ONE
    # REAL CALL).**
    impl_names = set(calls) - section - {"main"}
    # **=> AND THE **IMPLEMENTATION TEXT** IS **EVERY DEF THAT IS **NOT** A
    # PRODUCER, **AN AGGREGATOR **OR **A ROW-ONLY HELPER** -- **AND THE
    # HELPER SET IS **WHAT THE FIXPOINT WOULD HAVE FOUND**, **SO THE TWO ARE
    # COMPUTED TOGETHER** -- **AND THE **ONE-SHOT** RULE IS APPLIED **ONCE**,
    # **AND THEN THE **CLOSURE** IS TAKEN **UNDER THE ONE-SHOT RULE** (A DEP OF
    # A MOVED DEF MOVES **ONLY IF **THE IMPLEMENTATION NEVER CALLS IT**).**
    impl_text = "\n".join("\n".join(code[a:e]) for n, a, e in blocks if n in impl_names)
    impl_call_count: dict[str, int] = {}
    for n in calls:
        impl_call_count[n] = len(re.findall(r"(?<![\w.])" + re.escape(n) + r"\s*\(", impl_text))
    moved = set(section)
    changed = True
    while changed:
        changed = False
        for n in calls:
            if n in moved or n == "main":
                continue
            # **=> AND **THE ROW SECTION (OR **A DEF THAT ALREADY MOVED**)
            # CALLS IT**."
            if not (callers_of[n] & moved):
                continue
            # **=> AND **THE IMPLEMENTATION NEVER CALLS IT** -- **AND THAT IS
            # **THE PROVEN TOOL's OWN TEST**, **WITH THE DEF's OWN DEFINITION
            # COUNTED** -- **AND THE DEFINITION IS **NOT** IN THE IMPLEMENTATION
            # TEXT **IF THE DEF IS **ALREADY MOVED**, **SO THE COUNT IS **THE
            # NUMBER OF **IMPLEMENTATION** CALLS** -- **AND **ONE** IS THE
            # THRESHOLD**, **BECAUSE THE PORT's OWN DEF **IS **ONE OF THEM.**
            if impl_call_count[n] > 1:
                continue
            if n in ext:
                continue
            moved.add(n)
            changed = True
    helpers = sorted(moved - section)
    return {"lines": lines, "code": code, "prods": prods, "aggs": aggs, "helpers": helpers,
            "blocks": blocks, "byname": byname, "calls": calls, "ext": ext}


def build(path: Path, info: dict) -> tuple[list[str], list[str]]:
    """ (THE TRIMMED PORT FILE's LINES, THE DRIVER's LINES)."""
    lines = info["lines"]
    prods, aggs, helpers = info["prods"], info["aggs"], info["helpers"]
    moved_names = set(prods) | set(aggs) | set(helpers)
    drop: set[int] = set()
    moved_blocks: list[tuple[int, int]] = []
    for n in moved_names:
        i, e = info["byname"][n]
        s = block_start(lines, i)
        moved_blocks.append((s, e))
        drop.update(range(s, e))
    # **AND THE PORT's `main` **MOVES TO THE DRIVER** -- **AND THE PORT FILE
    # GETS A `main` THAT PRINTS **ONLY ITS OWN SUMMARY ROW**, **WHICH IS THE
    # PORT's** -- **SO THE SUMMARY ROW STAYS IN THE PORT FILE** (THE BRIEF:
    # *"IF THE PORT FILE STILL EMITS ROWS OF ITS OWN ... THOSE ROWS STAY IN THE
    # PORT FILE"*)** **AND THE DRIVER GETS A `main` WITH **NO** SUMMARY ROW,
    # **SO THE UNION OF THE TWO FILES' ROWS IS THE ORIGINAL SET**."
    main_i, main_e = info["byname"]["main"]
    main_block = lines[main_i:main_e]
    summary = [l for l in main_block if re.search(r"IO\.print\(\s*\"[^\"]*done=", l)]
    # **AND THE **SUMMARY ROW** IS **THE PORT's**, **SO IT STAYS IN THE PORT
    # FILE** **AND THE DRIVER's `main` **DROPS IT** -- **MEASURED 2026-11-10:
    # THE FIRST VERSION LEFT IT IN BOTH, **AND THE UNION HAD **441** ROWS
    # INSTEAD OF **440**, **AND `diff` WAS NOT EMPTY.**  **AND THE BRIEF IS
    # EXPLICIT: *"IF THE PORT FILE STILL EMITS ROWS OF ITS OWN ... THOSE ROWS
    # STAY IN THE PORT FILE".***
    driver_main = list(main_block)
    drop.update(range(main_i, main_e))
    # **AND THE `main` BLOCK IS **NOT** IN `moved_blocks`** -- **AND THE
    # LINE `moved_blocks[-1] = (main_i, main_e)` **OVERWROTE THE LAST HELPER's
    # BLOCK** -- **MEASURED 2026-11-10: `mapflag_missing` WAS **DROPPED** AND
    # `mapflag_of.go` **KEPT ITS PLACE**, **AND BEND SAID "expected : a def
    # whose body is implemented before the def is used"**.  **AND THE DRIVER's
    # `main` IS APPENDED AT THE END, **AFTER** THE ORDERING.**
    # **AND THE **MOVED BLOCKS** ARE **ORDERED BY THEIR OWN DEPENDENCY
    # GRAPH**, **BECAUSE BEND HAS NO FORWARD REFERENCES** -- **AND **THE PROVEN
    # TOOL's `order_defs` IS **NOT** USABLE HERE**, **FOR TWO MEASURED
    # REASONS:**
    #   1. **ITS REGEX IS **LOWERCASE-ONLY** (`^def ([a-z_]...)`), **AND THE
    #      PORT's CONSTANTS ARE UPPERCASE** (`PAGEFRAME_MASK_LO`, `VA_ADDR_LO`)
    #      -- **AND `order_defs` RETURNS ONLY THE BLOCKS IT RECOGNISED AND
    #      SILENTLY DROPS THE REST** -- **THE DRIVER LOST **EVERY**
    #      CONSTANT, **AND IT STILL COMPILED**, **AND IT PRINTED **NO ROWS**.**
    #   2. **IT DOES NOT KNOW `main`**, **AND `main` **MUST BE **LAST**,
    #      **AFTER EVERY DEF IT CALLS.**
    # **SO THE ORDERING IS DONE HERE, **AND IT KEEPS EVERY LINE**."
    moved: list[str] = []
    for s, e in moved_blocks:
        moved.extend(lines[s:e])
    # **=> AND A **TYPE** NEVER MOVES -- **MEASURED 2026-11-10 ON
    # `ops_qcom.bend`: THE TYPES SPLIT BETWEEN THE TWO FILES** -- **`Kf` AND
    # `Two` WENT TO THE DRIVER AND THE PORT's OWN CODE SAID "a declared
    # constructor (unknown: Kf)"** -- **=> AND A TYPE IS **A DEFINITION**, **SO
    # IT MUST LIVE IN **ONE** FILE**, **AND THE PORT IS **THE** FILE THAT
    # OWNS THE TYPES** -- **=> AND THE DRIVER NAMES THEM `P.<Type>`, **WHICH
    # IS **THE PROVEN TOOL's OWN TYPE RULE**.
    #
    # **=> AND A `type` BLOCK IS **A GAP BETWEEN TWO DEFS**, **AND THE
    # `block_start` COMMENT-PULL **CAN SWALLOW IT** -- **AND SO THE TYPE
    # LINES ARE **RESTORED TO THE PORT** EXPLICITLY, **AND REMOVED FROM THE
    # MOVED TEXT**.
    type_lines = {i for i, l in enumerate(lines) if l.startswith('type ')}
    moved = [l for l in moved if not l.startswith('type ')]
    type_spans: list[tuple[int, int]] = []
    for i in sorted(type_lines):
        j = i + 1
        # **=> AND THE CONSTRUCTOR IS **AS MANY LINES AS IT TAKES** --
        # **MEASURED 2026-11-10 ON `ops_qcom.bend`: `type Pd is Data:` SPANS
        # **TWO** LINES (`Pd{image_size: U32, ...` AND `    prg_offset: ...}`),
        # **AND THE ONE-LINE RULE TOOK **ONE**, **AND THE PORT SAID "expected :
        # a name (got the keyword 'def')"** -- **=> AND THE SPAN ENDS AT **A
        # BLANK LINE, A `def`, A `type` OR AN `import`.**
        while j < len(lines) and lines[j].strip() != '' \
                and not lines[j].startswith(('#', 'def ', 'type ', 'import ')):
            j += 1
        type_spans.append((i, j + 1))
    # **=> AND THE TYPE'S OWN LINES ARE **REMOVED FROM THE MOVED TEXT** TOO --
    # **MEASURED 2026-11-10 ON `ops_qcom.bend`: THE PORT KEPT `Bi{off: U32,
    # typ: U32}` **AND** THE DRIVER GOT **A SECOND COPY** OF IT, **AND THE
    # DRIVER SAID "expected : 'def', 'type' or 'law' / observed : 'P'"** -- **=> AND
    # THE COPY IS **THE `type` GAP BEING SWALLOWED BY THE PREVIOUS DEF's
    # BLOCK** -- **AND THE PORT's OWN BLOCK ALREADY HOLDS IT**.
    type_line_texts = set()
    for a, b in type_spans:
        for k in range(a, b):
            drop.discard(k)
            type_line_texts.add(lines[k])
    moved = [l for l in moved if l not in type_line_texts]
    moved = order_all(moved)
    # **=> AND A **TYPE** NEVER MOVES -- **MEASURED 2026-11-10 ON
    # `ops_qcom.bend`: THE TYPES SPLIT BETWEEN THE TWO FILES** -- **`Kf` AND
    # `Two` WENT TO THE DRIVER AND THE PORT's OWN CODE SAID "a declared
    # constructor (unknown: Kf)"** -- **=> AND A TYPE IS **A DEFINITION**, **SO
    # IT MUST LIVE IN **ONE** FILE**, **AND THE PORT IS **THE** FILE THAT
    # OWNS THE TYPES** -- **=> AND THE DRIVER NAMES THEM `P.<Type>`, **WHICH
    # IS **THE PROVEN TOOL's OWN TYPE RULE**.
    moved = [l for l in moved if not l.startswith("type ")]
    # **=> AND THE DRIVER's `main` **REPLACES** THE PORT's ORIGINAL `main` **IN
    # THE ORDERED LIST** -- **AND IT GOES **LAST**, **BECAUSE BEND HAS NO
    # FORWARD REFERENCES** -- **AND THE ORDERING PUTS `main` LAST ANYWAY.**
    # **=> AND THE PORT's ORIGINAL `main` BLOCK IS **REMOVED WHOLE** -- **AND
    # NOT JUST ITS `def` LINE** -- **MEASURED 2026-11-10: THE FIRST VERSION
    # REMOVED ONLY THE `def main()` LINE, **AND THE BODY WAS LEFT**, **AND
    # BEND SAID "expected : 'def', 'type' or 'law' / observed : 'd'"** -- **AND
    # A BODY WITHOUT ITS DEF IS **THE "DEAD" VERDICT** IN ANOTHER SHAPE.**
    out_lines: list[str] = []
    skip = False
    for l in moved:
        if l.startswith("def main()"):
            skip = True
            continue
        if skip:
            if l.startswith("def ") or l.startswith("type ") or l.startswith("#"):
                skip = False
            else:
                continue
        out_lines.append(l)
    moved = out_lines
    moved.extend(driver_main)
    # **AND THE PORT FILE KEEPS **EVERYTHING ELSE**, **IN ORDER**."
    impl = [l for k, l in enumerate(lines) if k not in drop]
    # **=> AND THE PORT FILE GETS **NO `main`** -- **AND THAT IS **THE TREE's
    # OWN SHAPE** (`tinybendygrad/renderer/amd/sqtt.bend` HAS NONE **AND EMITS
    # **ZERO** ROWS**) -- **=> AND THE PORT's OWN SUMMARY ROW **MOVED WITH THE
    # `main` THAT PRODUCED IT**, **AND THE UNION OF THE TWO FILES' ROWS IS
    # STILL THE ORIGINAL SET**.
    return impl, moved


def order_all(lines: list[str]) -> list[str]:
    """**EVERY DEF, ORDERED BY ITS OWN DEPENDENCY GRAPH, **AND **NOTHING
    DROPPED** -- **AND `main` **LAST**."

    **AND THE **UPPERCASE CONSTANTS** ARE DEFS TOO** -- **AND THE PROVEN
    TOOL's `order_defs` DROPPED THEM** -- **MEASURED 2026-11-10 ON
    `system.bend`: THE DRIVER WAS **1,904 LINES** **AND PRINTED **NO ROWS**,
    **AND EVERY CONSTANT WAS GONE.**  **AND A COMPILING FILE THAT PRINTS
    NOTHING IS THE "DEAD" VERDICT, **NOT** A PASS.**
    """
    DEF = re.compile(r"^def ([A-Za-z_][A-Za-z0-9_.]*)\(")
    blocks: list[tuple[str | None, list[str]]] = []
    cur_name: str | None = None
    cur: list[str] = []
    for l in lines:
        m = DEF.match(l)
        if m:
            if cur or cur_name is not None:
                blocks.append((cur_name, cur))
            cur_name = m.group(1)
            cur = [l]
        else:
            if cur_name is None:
                # **AND THE PROSE **BEFORE THE FIRST DEF** IS KEPT **AT THE
                # TOP**, **IN ORDER** -- **AND IT IS **NOT** PART OF A BLOCK.**
                blocks.append((None, [l]))
                cur_name = None
                cur = []
            else:
                cur.append(l)
    if cur or cur_name is not None:
        blocks.append((cur_name, cur))
    # **AND THE DEFS BY NAME, **AND THE PROSE KEPT WHERE IT WAS** -- **AND THE
    # PROSE **INSIDE** A DEF'S BLOCK (ITS TRAILING COMMENTS) STAYS WITH IT.**
    named = {n: b for n, b in blocks if n is not None}
    order: list[str] = [n for n, _ in blocks if n is not None]
    out: list[str] = []
    seen: set[str] = set()

    def emit(name: str, stack: tuple[str, ...] = ()) -> None:
        if name in seen or name not in named:
            return
        text = "\n".join(named[name])
        deps = [d for d in named
                if d != name and re.search(r"(?<![\w.])" + re.escape(d) + r"\s*\(", text)]
        for d in deps:
            if d not in stack:
                emit(d, stack + (name,))
        seen.add(name)
        out.extend(named[name])

    for n in order:
        if n == "main":
            continue
        emit(n)
    # **AND `main` **LAST**, **AFTER EVERYTHING IT CALLS** -- **AND THE
    # PROSE **THAT PRECEDED IT** GOES WITH IT.**
    if "main" in named:
        out.extend(named["main"])
    return out


def driver_text(path: Path, info: dict, moved: list[str], impl: list[str]) -> str:
    """ THE DRIVER's TEXT, USING **THE PROVEN TOOL's OWN MACHINERY**."""
    driver = ROOT / "gates" / f"{path.stem}-gate.bend"
    # **THE PORT's IMPORTS MOVE WITH THE ROWS, **REBASED ON `gates/`** -- **AND
    # THE REBASE IS **THE PROVEN TOOL's `rebased_path`**, **BY REAL PATH**."""
    imports = [l for l in impl if l.startswith("import ")]
    rebased: list[str] = []
    for l in imports:
        m = re.match(r"^import (\S+) as (\w+)$", l)
        if m:
            rebased.append(f"import {xgr.rebased_path(m.group(1), path, ROOT)} as {m.group(2)}")
        else:
            rebased.append(l)
    hdr = [
        f"# {driver.relative_to(ROOT)} -- THE GATE DRIVER for `{path.relative_to(ROOT)}`.",
        "#",
        "# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND",
        "# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:",
        "# `gates/README.md:173` -- \"a gate's `.bend` driver and its CPython oracle sit in",
        "# `gates/`, named by the gate that needs them.\"",
        "#",
        "# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE",
        "# NOTHING THAT THE PORT NEEDS.",
        "",
        "import Base",
        f"import ./../{path.relative_to(ROOT)} as P",
    ] + rebased[1:] + [
        "",
    ]
    # **AND THE PORT's DEFS ARE QUALIFIED `P.<name>` AND ITS TYPES `P.<Type>`,
    # **AND THE **MOVED** DEFS ARE **NOT** -- **BY THE PROVEN TOOL's OWN
    # REGEXES** -- **AND THE ORDER MATTERS: THE PORT's DEFS ARE QUALIFIED
    # FIRST AND THE MOVED DEFS ARE **UN**QUALIFIED AFTER, **SO A MOVED DEF
    # SHADOWS THE PORT's.**
    port_defs = {m.group(1) for m in (xgr.ANY_DEF.match(l) for l in impl) if m}
    # **AND **`main` IS **NOT** A PORT DEF** -- **IT IS THE DRIVER's OWN
    # ENTRY POINT** -- **AND QUALIFYING IT GAVE `def P.main()`, **WHICH BEND
    # COMPILES AND WHICH PRINTS **NOTHING**, BECAUSE A `P.main` IS NOT THE
    # ENTRY POINT** -- **MEASURED 2026-11-10 ON `system.bend`: THE DRIVER
    # COMPILED (`WITHIN-LIMITS`), **PRINTED **ZERO** ROWS**, **AND THE PORT
    # FILE PRINTED **ONE** (`sy-done=1`) -- **SO **THE UNION WAS **ONE** ROW
    # INSTEAD OF **440**.**  **A GATE THAT COMPILES AND PRINTS NOTHING IS
    # **THE "DEAD" VERDICT**, **NOT** A PASS.**
    port_defs.discard("main")
    port_types = {m.group(1) for m in (re.match(r"^type ([A-Za-z_][A-Za-z0-9_]*)", l) for l in impl) if m}
    moved_names = set(info["prods"]) | set(info["aggs"]) | set(info["helpers"])

    def qualify(text: str) -> str:
        # **AND THE QUALIFICATION IS **STRING- AND COMMENT-AWARE** -- **AND
        # THE FIRST VERSION WAS NOT** -- **MEASURED 2026-11-10: THE ROW
        # `sy_flag_name_4` PRINTS **THE STRING** `"MAP_FIXED_NOREPLACE"`, **AND
        # THE BARE-CONSTANT RULE REWROTE IT INSIDE THE STRING** **AND INSIDE
        # THE COMMENTS**, **AND THE ROW's VALUE CHANGED** -- **AND A ROW
        # WHOSE VALUE CHANGED IS **A DIFFERENCE**, **NOT** A MOVE.**
        return _qualify_spans(text, port_defs, port_types, moved_names)

    body = qualify("\n".join(moved)).split("\n")
    return "\n".join(hdr + body) + "\n"


def _code_spans(text: str) -> list[tuple[int, int]]:
    """ THE SPANS OF **CODE** -- **THE STRING LITERALS AND THE COMMENTS ARE
    EXCLUDED**, **SO A NAME INSIDE ONE IS NEVER TOUCHED**.

    **AND **A COMMENT RUNS TO THE END OF ITS LINE** -- **AND EVERYTHING IN
    IT IS SKIPPED**, **INCLUDING ITS QUOTES** -- **MEASURED 2026-11-10: THE
    FIRST VERSION SCANNED **CHARACTER BY CHARACTER** AND TREATED A `"` **INSIDE
    A COMMENT** AS THE START OF A STRING, **AND THE SPAN RAN TO THE NEXT `"`
    **SOMEWHERE ELSE IN THE FILE**, **AND EVERY DEF IN BETWEEN WAS SKIPPED** --
    **AND `gid.of.p2` WAS **NEVER QUALIFIED** **AND BEND SAID "expected : a
    defined name".**
    """
    spans: list[tuple[int, int]] = []
    i = 0
    n = len(text)
    start = 0
    while i < n:
        c = text[i]
        if c == "#":
            # **AND THE COMMENT IS **SKIPPED WHOLE**, **AND ITS QUOTES ARE
            # **NOT** QUOTES.**
            spans.append((start, i))
            j = text.find("\n", i)
            i = n if j < 0 else j
            start = i
        elif c == '"':
            spans.append((start, i))
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
            i += 1
            start = i
        else:
            i += 1
    spans.append((start, n))
    return spans


def _apply(text: str, spans: list[tuple[int, int]], fn) -> str:
    out = []
    pos = 0
    for a, b in spans:
        out.append(text[pos:a])
        out.append(fn(text[a:b]))
        pos = b
    out.append(text[pos:])
    return "".join(out)


def _qualify_spans(text: str, port_defs: set[str], port_types: set[str], moved_names: set[str]) -> str:
    """ THE QUALIFICATION, **AND IT **NEVER** TOUCHES A STRING OR A COMMENT**."""
    def once(chunk: str) -> str:
        for d in sorted(port_defs, key=len, reverse=True):
            chunk = re.sub(rf"(?<![\w.]){re.escape(d)}\(", f"P.{d}(", chunk)
        for t in sorted(port_types, key=len, reverse=True):
            # **=> AND A **TYPE CONSTRUCTOR PATTERN** (`Kf{nm: String}`) IS
            # **NOT **A TYPE REFERENCE** -- **AND `P.Kf{...}` IS NOT VALID
            # BEND** -- **MEASURED 2026-11-10 ON `ops_qcom.bend`: THE DRIVER
            # SAID "expected : 'def', 'type' or 'law' / observed : 'P'"** --
            # **=> AND **A TYPE NAME IMMEDIATELY FOLLOWED BY `{`** IS A
            # **CONSTRUCTOR**, **AND IT STAYS BARE.**
            # **=> AND A **TYPE NAME IN A PATTERN** (`case Pd{image_size, ...}`)
            # **IS **A TYPE REFERENCE** **AND MUST BE `P.Pd`** -- **AND
            # `gates/dtype-gate.bend:54` **IS THE PROOF**: IT READS
            # `case P.Fix{fx, wi, ch, wf, i32, ub}: fx` -- **=> AND THE
            # **EARLIER** REFUSAL (`P.Kf{...}`) WAS **NOT **THE PATTERN** **BUT
            # **THE TYPE DECLARATION**, **WHICH HAD MOVED** -- **AND **IT** DOES
            # **NOT** MOVE ANY MORE.
            chunk = re.sub(rf"(?<![\w.]){re.escape(t)}\b", f"P.{t}", chunk)
        for h in moved_names:
            chunk = re.sub(rf"P\.{re.escape(h)}\(", f"{h}(", chunk)
        for d in sorted(port_defs, key=len, reverse=True):
            if d in moved_names:
                continue
            chunk = re.sub(rf"(?<![\w.]){re.escape(d)}\b(?!\s*\()", f"P.{d}", chunk)
        for h in moved_names:
            # **=> AND THE UN-QUALIFICATION MUST NOT **EAT THE PREFIX OF A
            # LONGER NAME** -- **MEASURED 2026-11-10: `P.Tr.has.go(` BECAME
            # `Tr.has.go(` **BECAUSE `P.Tr.has` MATCHED AND THE `.go` WAS LEFT
            # BEHIND**, **AND BEND SAID "expected : a defined name / observed :
            # Tr.has.go"** -- **AND `Tr.has.go` **STAYS IN THE PORT**, **SO THE
            # DRIVER MUST CALL `P.Tr.has.go(`.**
            chunk = re.sub(rf"P\.{re.escape(h)}\b(?!\s*\()(?!\.)", h, chunk)
        return chunk

    return _apply(text, _code_spans(text), once)


def compile_of(path: Path) -> tuple[str, str]:
    """ (THE MEMORY VERDICT, THE **BEND** VERDICT) -- **AND THE BEND VERDICT
    IS **THE** ONE THAT MATTERS.**

    **MEASURED 2026-11-10: `checks/bounded.py` PRINTS `WITHIN-LIMITS` **AND**
    `said=SOME PROOFS FAIL | Error: | - expected : a defined name` **IN THE SAME
    LINE** -- **AND THE PROVEN TOOL READS ONLY THE TOKEN**, **SO A FILE THAT
    DOES NOT COMPILE PASSES ITS COMPILE CHECK.**  **AND A COMPILE CHECK THAT
    ACCEPTS A FILE THAT DOES NOT COMPILE IS **THE "DEAD" VERDICT IN DISGUISE.**
    **SO THE CHECK READS **THE BEND's OWN VERDICT**: `ALL PROOFS CHECK` IS
    THE PASS AND **ANYTHING ELSE IS A FAIL.**
    """
    r = subprocess.run(
        [".venv/bin/python", "checks/bounded.py", "--mb", "3072", "--", "./bin/bend", str(path)],
        cwd=ROOT, capture_output=True, text=True, timeout=900)
    both = r.stdout + r.stderr
    mem = "NO-TOKEN"
    for token in ("WITHIN-LIMITS", "KILLED-ON-MEMORY", "TIMED-OUT"):
        if token in both:
            mem = token
            break
    if "ALL PROOFS CHECK" in both:
        bend = "ALL PROOFS CHECK"
    elif "SOME PROOFS FAIL" in both:
        bend = "SOME PROOFS FAIL"
    elif "Error:" in both:
        bend = "ERROR"
    elif r.returncode == 0:
        # **⇒ AND **A FILE THAT PRINTS ITS ROWS AND **EXITS 0** IS **A PASS**
        # -- **AND `bin/bend` DOES NOT PRINT `ALL PROOFS CHECK` FOR A FILE
        # WHOSE `main` PRINTS ROWS** -- **MEASURED 2026-11-10 ON
        # `system.bend`: THE DRIVER PRINTED **439** ROWS, **EXITED 0**, **AND
        # ITS STDERR WAS **0 BYTES**, **AND THE VERDICT WAS `NO-VERDICT`
        # UNTIL THIS BRANCH** -- **⇒ AND `NO-VERDICT` IS **NOT** A PASS,
        # **SO THE BRANCH IS **rc==0 AND NO ERROR TEXT**.**
        bend = "OK (rc=0, no error)"
    else:
        bend = "NO-VERDICT"
    return mem, bend


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", nargs="*", default=[])
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if not args.apply:
        print(__doc__)
        return 0
    for rel in args.apply:
        path = ROOT / rel
        info = analyse(path)
        impl, moved = build(path, info)
        driver = ROOT / "gates" / f"{path.stem}-gate.bend"
        print(f"  {rel}: {len(info['prods'])} producers, {len(info['aggs'])} aggregators, "
              f"{len(info['helpers'])} row-only helpers")
        print(f"    port: {len(info['lines'])} -> {len(impl)} lines;  driver: {len(moved)} lines")
        if args.dry_run:
            continue
        driver.write_text(driver_text(path, info, moved, impl))
        path.write_text("\n".join(impl) + "\n")
        mem_a, bend_a = compile_of(path)
        mem_b, bend_b = compile_of(driver)
        print(f"    port file: {mem_a} / {bend_a}   driver: {mem_b} / {bend_b}")
        if bend_a.startswith("SOME") or bend_a == "ERROR" or bend_a == "NO-VERDICT" \
           or bend_b.startswith("SOME") or bend_b == "ERROR" or bend_b == "NO-VERDICT":
            print("    **REFUSED: one of the two did not compile -- RESTORE BOTH.**")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
