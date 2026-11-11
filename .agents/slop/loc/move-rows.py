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
    return set(DECLARED.findall(text)) | set(ASSIGNED.findall(text))


def prefix(line: str, names: set[str]) -> str:
    # A quoted span is DATA. A row name like `"npy-done"` holds `npy`, and `npy` is
    # also a port def, so a prefixer that reads through quotes printed `P.npy-done=1`.
    inside = set()
    for q in QUOTED.finditer(line):
        inside.update(range(q.start(), q.end()))
    # A declaration NAME is the new binding, not a reference to the port's.
    for d in DECL.finditer(line):
        inside.update(range(d.start(1), d.end(1)))
    out, i = [], 0
    for m in WORD.finditer(line):
        out.append(line[i : m.start()])
        w = m.group(0)
        prev = "".join(out)[-1:] if out else ""
        out.append(f"P.{w}" if (w in names and prev != "." and m.start() not in inside) else w)
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
    names = names_of(lines, start) - declared_in(lines[start:end])
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
    body = [prefix(l, names) for l in lines[start:end]]
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

    print(f"{args.port}: {len(lines)} lines, region {start + 1}..{end} ({end - start})")
    print(f"{args.driver}: written, {len(header) + end - start} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
