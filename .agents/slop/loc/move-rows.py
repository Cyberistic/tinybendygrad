#!/usr/bin/env python3
"""move-rows.py -- move a port file's gate rows into a `gates/` driver.

    .venv/bin/python .agents/slop/loc/move-rows.py <port.bend> <gates/driver.bend>

THE REGION. From the first row printer (`def row(`, `def srow(`, ...) to the end
of `main`, which is the first column-0 non-comment line after it. What follows is
the file's footer and it stays.

THE RENAME. Every top-level name the port defines before that region becomes
`P.<name>` in the driver, because a driver may only consume. A name the driver
defines for itself (the printers, `main`) is not in the port region and is left
alone.

WHAT MUST HOLD, AND IT IS CHECKED BY THE CALLER, NOT HERE: the port file printed
one row set before the move and the driver prints the same set after it. This
tool only writes the driver; `--cut` also removes the region from the port file,
and the port must still compile after that (a def the port still needs would
fail loudly, which is the point).
"""

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

DECL = re.compile(r"^\s*(?:def|type)\s+([A-Za-z_][\w.]*)")
# A `case` arm's binders: `case v <> t`, `case Some{+x}`, `case False{}`.
CASE_ARM = re.compile(r"^\s*case\s+")
QUOTED = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
WORD = re.compile(r"[A-Za-z_]\w*")
IMPORT = re.compile(r"^import\s+(\S+)\s+as\s+(\w+)")
PRINTER = re.compile(r"^def (row|srow|brow|urow|lrow|slrow|rows|urows)\(")
DEF = re.compile(r"^def\s+([A-Za-z_][\w.]*)\s*\(")
ASSIGN = re.compile(r"^([A-Za-z_]\w*)\s*[:=]")
TYPE = re.compile(r"^type\s+([A-Za-z_]\w*)")
HEADER = """# {path} -- the gate driver for `{port}`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../{port_noext} as P
"""


def region(lines: list[str]) -> tuple[int, int]:
    start = next(i for i, l in enumerate(lines) if PRINTER.match(l))
    # The region's END is the first column-0 line that is not a comment after the
    # region's own `main`. A file whose region has NO `main` -- because the rows
    # were already moved once and the port kept only the seam -- ends at EOF.
    mains = [i for i, l in enumerate(lines[start:], start) if l.startswith("def main")]
    if not mains:
        return start, len(lines)
    main = mains[0]
    end = len(lines)
    for i in range(main + 1, len(lines)):
        if lines[i] and not lines[i][0].isspace() and not lines[i].startswith("#"):
            end = i
            break
    return start, end


def names_of(lines: list[str], end: int) -> set[str]:
    names = set()
    for l in lines[:end]:
        for pat in (DEF, ASSIGN, TYPE):
            m = pat.match(l)
            if m:
                names.add(m.group(1).split(".")[0])
    return names


METHOD = re.compile(r"^def\s+([A-Za-z_]\w*)\.")
DECLARED = re.compile(r"^(?:def|type)\s+([A-Za-z_]\w*)(?:\s|\(|$)", re.M)
ASSIGNED = re.compile(r"^([A-Za-z_]\w*)\s*[:=]", re.M)


def declared_in(lines: list[str]) -> set[str]:
    """Names the region itself declares -- and only those.

    A `def Hit.tg(...)` EXTENDS a type the port defines; it does not make `Hit`
    local, so the method form contributes nothing here. Measured: counting it made
    the driver spell `case Hit{...}` at a `type Hit` that had stayed in the port,
    and the error was `a declared constructor (unknown: Hit)`.
    """
    text = "\n".join(lines)
    # A `def N.m` in the region EXTENDS the namespace `N` -- it does not declare
    # it -- and a namespace that the PORT also declares must keep the port's
    # meaning. MEASURED 2026-11-11: the amdev region declares `v.pack` and the
    # port declares `v.fmt3`, so the namespace `v` is the PORT's and every
    # `v.*` in the driver is `P.v.*`. Counting the region's `v.pack` as a
    # declaration of `v` removed `v` from the prefix set and the driver answered
    # `expected: a defined name` for `v.fmt3`.
    declared = set(DECLARED.findall(text)) | set(ASSIGNED.findall(text))
    methods = {m.group(1).split(".")[0] for m in METHOD.finditer(text)}
    return declared - methods


CASE_BIND = re.compile(r"^\s*case\s+(?:[^:]*?\b)?([A-Za-z_]\w*)\s*<>", re.M)


def bound_names(lines: list[str]) -> set[str]:
    """The names a `case` pattern BINDS, over the whole region.

    A `case` arm's names are the pattern's own, and prefixing them turns a
    pattern into something else: MEASURED 2026-11-11, the amdev driver answered
    `expected: a pattern (a binder or a constructor), observed:
    ../tinybendygrad/runtime/support/am/amdev.v`. The binder is then USED in the
    arm's body, and the body can be several lines down, so the decision has to be
    made for the region and not for the line.
    """
    out: set[str] = set()
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("case "):
            continue
        # THE PATTERN IS UP TO THE `:` -- and a `case` arm whose body is on the
        # NEXT line has no `:` in it at all, so the pattern is the whole line.
        pat = stripped[len("case "):]
        if ":" in pat:
            pat = pat.split(":")[0]
        # A BINDER IS A BARE NAME IN A `<>` LIST: `case v <> t` binds `v` and `t`.
        # A name in ANY other position is a CONSTRUCTOR (`Some{...}`) or a
        # QUALIFIED name (`O.Arena`), and neither is a binder.
        # MEASURED 2026-11-11: the first version took every bare name in the
        # pattern, so `v` -- bound by some OTHER arm's `case v <> t` -- was
        # treated as a binder EVERYWHERE and the driver printed `v.fmt3` instead
        # of `P.v.fmt3`.
        for arm in pat.split("|"):
            m = re.search(r"\b([A-Za-z_]\w*)\s*<>", arm)
            if not m:
                continue
            head = arm[: m.start()]
            for nm in re.findall(r"\b([A-Za-z_]\w*)\b", head):
                if nm in ("Some", "None", "Nil", "True", "False"):
                    continue
                if re.search(rf"\b{re.escape(nm)}\{{", head):
                    continue
                out.add(nm)
            # THE TAIL's binders: `case v <> t` binds BOTH `v` and `t`. But `t`
            # is a NAME THE PORT MAY ALSO DEFINE, and the binder wins only
            # INSIDE ITS OWN ARM -- so a binder whose name is a port def is
            # ambiguous and must NOT be treated as a binder everywhere.
            tail = arm[m.start():]
            for nm in re.findall(r"\b([A-Za-z_]\w*)\b", tail):
                if nm in ("Some", "None", "Nil", "True", "False"):
                    continue
                out.add(nm)
    return out


def arm_map(lines: list[str]) -> list[set[str]]:
    """For each line, the names the `case` arm it belongs to BINDS.

    An arm is the `case` line and the lines that follow it until the next `case`
    or the next column-0 definition. The arm's BODY uses the binder, and the
    textual tool cannot see the arm's extent from the line alone -- so the
    region is walked once and every line is labelled with its arm's binders.

    MEASURED 2026-11-11: the amdev region binds `v` in `case v <> t` and the
    port has a namespace `v`, so the driver's `Q.v` was not a pattern and the
    port's `v.fmt3` was unreachable. The second import (`as Q`) plus this map is
    what makes both reachable.
    """
    out: list[set[str]] = []
    current: set[str] = set()
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("case ") or (line and not line[0].isspace() and not stripped.startswith("#")):
            current = set()
            pat = stripped[len("case "):] if stripped.startswith("case ") else ""
            if ":" in pat:
                pat = pat.split(":")[0]
            for arm in pat.split("|"):
                m = re.search(r"\b([A-Za-z_]\w*)\s*<>", arm)
                if not m:
                    continue
                head = arm[: m.start()]
                for nm in re.findall(r"\b([A-Za-z_]\w*)\b", head):
                    if nm in ("Some", "None", "Nil", "True", "False"):
                        continue
                    if re.search(rf"\b{re.escape(nm)}\{{", head):
                        continue
                    current.add(nm)
                for nm in re.findall(r"\b([A-Za-z_]\w*)\b", arm[m.start():]):
                    if nm in ("Some", "None", "Nil", "True", "False"):
                        continue
                    current.add(nm)
        out.append(set(current))
    return out


def prefix(line: str, names: set[str], bound: set[str] | None = None,
            collided: set[str] | None = None,
            arm_binders: set[str] | None = None,
            region_members: set[str] | None = None) -> str:
    """Prefix the port's names in one line.

    `names` are the port's top-level names (a namespace's first component), and
    `bound` are the names a `case` pattern BINDS. A binder SHADOWS the port's
    name -- but only inside its own arm -- and a textual tool cannot see the
    arm's extent. So a binder that is ALSO a port name is ambiguous, and the
    honest answer is to prefix the port's name and let the arm's binder win
    where it is a binder. That is what `bound` is for: a name that is a binder
    and NOT a port name is never prefixed, and a name that is a port name is
    prefixed unless the LINE ITSELF is a pattern.
    """
    # A quoted span is DATA. A row name like `"npy-done"` holds `npy`, and `npy` is
    # also a port def, so a prefixer that reads through quotes printed `P.npy-done=1`.
    inside = set()
    for q in QUOTED.finditer(line):
        inside.update(range(q.start(), q.end()))
    # A declaration NAME is the new binding, not a reference to the port's -- and
    # it is the region's OWN name, so it is never qualified. MEASURED 2026-11-11:
    # the amdev region declares `v.pack` and the prefixer wrote `def Q.v.pack`,
    # which is not a declaration at all.
    for d in DECL.finditer(line):
        inside.update(range(d.start(1), d.end(1)))
    out, i = [], 0
    for m in WORD.finditer(line):
        out.append(line[i : m.start()])
        w = m.group(0)
        prev = "".join(out)[-1:] if out else ""
        # A PATTERN's binder is not a reference: `case v <> t` binds `v` and
        # `t`, and prefixing them (`case P.v <> P.t`) is not a pattern at all.
        # MEASURED 2026-11-11: the amdev driver answered `expected: a pattern
        # (a binder or a constructor), observed: ../tinybendygrad/.../amdev.v`.
        # A `case` arm's PATTERN is up to the `:` and its BODY is after it, and
        # the pattern's binders are the arm's own -- so a name inside the
        # pattern is not a reference. The arm's body may be on the NEXT line,
        # so the decision has to be made per PATTERN, not per line.
        # THE PATTERN IS UP TO THE `:` -- and the arm's BODY is after it. So a
        # token is in the PATTERN only if it is BEFORE the colon. MEASURED
        # 2026-11-11: the check was `CASE_ARM.match(line[:m.start()])`, and on a
        # line that BEGINS with `case` that is true for EVERY token -- so the
        # arm's body (`[Meth.name(mm)]`) was treated as a pattern and the
        # driver answered `expected: a defined name, observed: Meth.name`.
        pat = line.split(":")[0]
        is_pattern = bool(CASE_ARM.match(line[:m.start()])) and m.start() < len(pat)
        if is_pattern:
            # A BINDER SHADOWS THE PORT'S NAME IN THIS PATTERN ONLY. So the
            # pattern's binders are not prefixed, and the port's name IS
            # prefixed everywhere else -- including the arm's BODY, which is on
            # the next line and uses the binder.
            for nm in re.findall(r"\b([A-Za-z_]\w*)\b", pat):
                if nm in ("case", "Some", "None", "Nil", "True", "False"):
                    continue
                if re.search(rf"\b{re.escape(nm)}\{{", pat):
                    continue
                if nm in names:
                    # the binder wins in the PATTERN -- so it is not prefixed
                    # HERE. The arm's body is a different line and is handled
                    # there.
                    is_pattern = True
                    break
        if bound and w in bound and w not in names:
            is_pattern = True
        if bound and w in bound and w in names:
            # A BINDER THAT SHADOWS A PORT NAME. The arm's body uses the binder
            # and the binder's scope is the arm -- and the textual tool cannot
            # see the arm's extent. So the PORT'S name is reached by the second
            # alias (`Q.v.fmt3`) and the BINDER keeps its own spelling (`v`).
            # That is why the driver imports the port twice.
            is_pattern = False
        # A NAMESPACE is not a name: the port's `v.fmt3` is ONE def, and the
        # driver must spell it `P.v.fmt3` -- so the prefix goes on the FIRST
        # component of a qualified name and the rest follows.
        # A NAMESPACE IS THE NAME BEFORE THE DOT. The port's `v.fmt3` is one
        # def, and the driver must spell it `P.v.fmt3` -- so the prefix goes on
        # `v` and the member follows. MEASURED 2026-11-11: the prefixer skipped
        # every qualified name (the previous character is ".") and the amdev
        # driver answered `expected: a defined name` for `v.fmt3`.
        # A COLLIDED NAME -- a namespace the region BINDS and the port DEFINES --
        # is spelled with the SECOND alias, so the binder keeps its own name.
        # And in a PATTERN the binder wins, so the name is not qualified there.
        if m.start() in inside:
            out.append(w)
        elif collided and w in collided:
            # THE BINDER IN ITS OWN ARM, AND THE PORT'S NAMESPACE EVERYWHERE
            # ELSE. The arm's body is the next line and uses the binder, so the
            # binder must keep its name THERE too -- and the textual tool cannot
            # see the arm's extent. So the collided name is spelled `Q.` ONLY
            # where it is NOT the binder's own use, and the binder's uses are
            # found by the ARM: a `case` arm and the lines that belong to it.
            # THE MEMBER AFTER THE DOT: `nxt` starts with "." and then the
            # member's NAME -- so the member is the text up to the next
            # non-identifier character, not `nxt.split(".")[0]` (which is the
            # EMPTY string, because the split is on the leading dot).
            nxt = line[m.end():]
            member = ""
            if nxt.startswith("."):
                member = re.match(r"\.([A-Za-z_]\w*)", nxt).group(1)
            if member and region_members and member in region_members:
                # THE MEMBER IS THE REGION'S OWN, so the NAMESPACE is the
                # region's too -- bare. MEASURED 2026-11-11: the driver's
                # `P.aspm.index_str` was the PORT's member and the port has
                # none (the region's own `def aspm.index_str` moved out with
                # the rows), so the answer was `expected: a defined name`.
                out.append(w)
            elif arm_binders and w in arm_binders:
                out.append(w)
            else:
                out.append(f"Q.{w}")
        else:
            out.append(f"P.{w}" if (w in names and prev != "." and m.start() not in inside
                                     and not is_pattern) else w)
        i = m.end()
    out.append(line[i:])
    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("driver")
    ap.add_argument("--cut", action="store_true")
    args = ap.parse_args()

    port = Path(args.port)
    driver = Path(args.driver)
    lines = port.read_text().split("\n")
    start, end = region(lines)
    # A name the region DECLARES is the region's own, and gets no prefix even when
    # the port declares one too -- `type TFP` is in both, and prefixing its uses
    # while the declaration stays local is a type error at the first call.
    # A name the port declares BEFORE the region and the region EXTENDS -- a
    # `def Cx.k` where `type Cx` is above -- is a namespace the region owns
    # methods of, and the driver cannot reopen it: the port's `Cx` and the
    # driver's `Cx` would be two different types. So such a namespace stays
    # with the port, and the region is cut ABOVE it.
    pre = names_of(lines, start)
    # A namespace the region EXTENDS -- `def Cx.k` where `type Cx` is ABOVE the
    # region -- cannot move: the port's `Cx` and the driver's `Cx` would be two
    # different types, and `nvdev.bend`'s `IP.Cx` would name the port's. So the
    # region is cut ABOVE the first such namespace, and the namespace stays with
    # the port.
    methods = {m.group(1) for m in METHOD.finditer("\n".join(lines[start:end]))}
    extended = {n for n in methods if n in pre}
    if extended:
        for i, line in enumerate(lines[start:end], start):
            m = re.match(r"^(?:def|type)\s+([A-Za-z_]\w*)(?:\s|\(|$)", line)
            if m and m.group(1) in extended:
                start = i
                break
    # THE PORT'S NAMES, MINUS THE REGION'S OWN. A name the region DECLARES is
    # the region's -- `aspm.index_str` in the amdev region -- and the port's
    # namespace `aspm` is then shadowed in the driver.
    declared = declared_in(lines[start:end])
    # THE PORT'S NAMES, MINUS THE REGION'S OWN TOP-LEVEL DEFINITIONS. A name
    # the region declares as `def N.m` EXTENDS the namespace `N` -- it does not
    # declare `N` -- so `N` stays the port's and the driver's `N.m` is `P.N.m`.
    # A name the region declares as `def N` or `type N` IS the region's.
    region_own = set()
    for l in lines[start:end]:
        m = re.match(r"^(?:def|type)\s+([A-Za-z_]\w*)\s*[( ]", l)
        if m:
            region_own.add(m.group(1))
    names = names_of(lines, start) - region_own
    # THE NAMES THE REGION BINDS AND THE PORT ALSO DEFINES. A `case v <> t`
    # binds `v`, and the port has a NAMESPACE `v` (`v.fmt3`) -- so the driver's
    # `P.` prefix would turn the binder into `P.v`, which is not a pattern, and
    # NOT prefixing it would leave the port's namespace unreachable.
    # BEND CAN IMPORT ONE FILE UNDER TWO ALIASES (MEASURED: `import ... as P` and
    # `import ... as Q` in the same file compiles), so the driver imports the
    # port twice: `P` for the top-level names and `Q` for the collided ones.
    # THE COLLIDED NAMES: the port's names that the region BINDS, and the port's
    # names that the region also DECLARES. Both are the same class -- the
    # driver's spelling of the port's name and the region's own spelling are
    # different things and need different aliases.
    # THE COLLIDED NAMESPACES: the port's names the region BINDS, and the port's
    # names whose namespace the region EXTENDS. A namespace the region extends
    # is BOTH -- the region's `def aspm.index_str` extends `aspm` and the port
    # has `aspm.at` -- so the driver has to say WHICH one it means, and the
    # second alias (`Q`) is the port's.
    extended = {n for n in names
                if re.search(rf"^def\s+{re.escape(n)}\.", "\n".join(lines[start:end]), re.M)}
    collided = sorted((names & bound_names(lines[start:end])) | extended)
    header = HEADER.format(
        path=args.driver,
        port=args.port,
        port_noext=re.sub(r"\.bend$", ".bend", args.port),
    ).split("\n")
    # The port's own imports come too: a row that reaches `D.head` or `H.ceildiv`
    # needs the alias, and the alias is defined once, in the port file's header.
    # `Base` is already the driver's first line, and a relative path resolves
    # from the port's directory, so it is re-spelled from the driver's.
    for l in lines[:start]:
        m = IMPORT.match(l)
        if not m:
            continue
        target, alias = m.group(1), m.group(2)
        if target == "Base":
            continue
        if target.startswith("."):
            target = os.path.relpath(
                os.path.normpath(os.path.join(port.parent, target)), driver.parent
            )
            target = f"./{target}"
        header.append(f"import {target} as {alias}")
    if collided:
        # THE SECOND ALIAS, for the namespaces the region BINDS. MEASURED
        # 2026-11-11: the amdev region binds `v` in `case v <> t` and the port has
        # a namespace `v` (`v.fmt3`), so the driver's `P.v` was not a pattern and
        # the port's `v.fmt3` was unreachable. Bend imports one file under two
        # aliases -- MEASURED: `import ... as P` and `import ... as Q` in the same
        # file compiles.
        port_target = "./../" + re.sub(r"\.bend$", ".bend", args.port)
        header.append(f"import {port_target} as Q")
    bound = bound_names(lines[start:end])
    arms = arm_map(lines[start:end])
    region_members = {mm.group(1) for l in lines[start:end]
                      for mm in re.finditer(r"^def\s+\w+\.(\w+)", l, re.M)}
    body = [prefix(l, names, bound, collided, a, region_members)
            for l, a in zip(lines[start:end], arms)]
    driver.parent.mkdir(parents=True, exist_ok=True)
    driver.write_text("\n".join(header + body).rstrip("\n") + "\n")

    if args.cut:
        note = [
            f"# THE GATE MOVED TO `{args.driver}`.",
            "#",
            "# The rows are consumers: each calls a def above through `P.`, and the",
            "# driver defines nothing this file needs, which is the line",
            "# `gates/README.md:173` draws.",
            "#",
            "# Every expectation in the driver is generated by calling CPython, so no row",
            "# there is typed by hand.",
        ]
        port.write_text("\n".join(lines[:start] + note + lines[end:]).replace("\n\n\n\n", "\n\n") + "\n")
        print(f"  the port is now {len(lines[:start]) + len(note) + len(lines[end:])} lines")

    print(f"{args.port}: {len(lines)} lines, region {start + 1}..{end} ({end - start})")
    print(f"{args.driver}: written, {len(header) + end - start} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
