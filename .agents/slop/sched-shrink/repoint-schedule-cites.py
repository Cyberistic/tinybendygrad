#!/usr/bin/env python3
"""repoint-schedule-cites.py -- RE-POINT THE `.bend` LINE CITATIONS THAT THE
**GATE-ROW MOVE** BROKE.

    .venv/bin/python .agents/slop/sched-shrink/repoint-schedule-cites.py \
        --tree <dir> --git-dir <repo> --rows <bendcite.rows> \
        --before-rows <pre-move.rows> [--apply]

**AND THE **BROKEN SET** IS **THE INSTRUMENT's OWN**, **NOT **A HAND LIST**
AND **NOT **A HEURISTIC** -- **AND THAT IS **THE POINT**.

`gates/bendcite-gate.py` IS **THE INSTRUMENT THAT JUDGES **`.bend` -> `.bend`
LINE CITATIONS**, **AND IT WRITES **A ROW PER POINTER**, **AND THE ROW NAMES
THE POINTER, THE VERDICT, AND **THE CONSTRUCT THE POINTER SHOULD HAVE HIT**
(`decl`) **AND **THE `why` **NAMES IT AND **GIVES **ITS LINE**.

**AND **THE `why` IS **THE ANSWER** -- **AND IT IS **READ**, **NOT
GUESSED** -- **AND **THE POINTER'S NEW LINE IS **THE LINE OF **THE
CONSTRUCT **THE `why` NAMES**.

**AND **A `DANGLING-LINE` HAS **NO `why`** -- **AND THAT IS **THE CASE
**THIS MOVE **CREATES** -- **AND **THE **PRE-MOVE** FILE **IS **READ FROM
GIT** AT **THE PIN** -- **AND **THE **CONSTRUCT** IS **THE **DEF **WHOSE
**SPAN **CONTAINS **THE **CITED LINE** -- **AND THE SPAN **IS **THE
**INSTRUMENT's OWN SPAN RULE** (`decl < lo <= end`), **NOT **"THE LAST DEF
ABOVE"**, **AND THAT IS **THE DIFFERENCE** -- **MEASURED 2026-11-10:
`schedule/rangeify.bend:2987` IS INSIDE **`eng_op_name`'s** SPAN** AND NOT
`eng_node`'s**, **AND THE **LAST-DEF-ABOVE** RULE PICKED **`eng_node`** AND
**THE POINTER WAS **STILL WRONG** -- **AND THE INSTRUMENT SAID SO**:
*"the pointer says :2517 and `eng_op_name` is declared at :2577"*.**

**AND **ONLY **A POINTER **THIS MOVE **BROKE** IS **RE-POINTED** -- **AND
**A POINTER **THAT WAS **ALREADY **BROKEN **BEFORE **THE MOVE** IS **LEFT
ALONE** -- **AND THAT IS **THE DIFFERENCE BETWEEN **A RE-POINT** AND **A
GUESS**.

**MEASURED 2026-11-10 ON `tinybendygrad/runtime/device.bend`: THE POINTERS
`schedule/__init__.bend:1139` AND `:1140` WERE **ALREADY BROKEN** -- **AND
`schedule/__init__.bend` **IS NOT **A FILE THIS MOVE TOUCHED** -- **AND THE
INSTRUMENT's "nearest" ANSWER NAMED **`linear`** **AND THE CITATION MEANT
**`schedule`** -- **AND THE TOOL RE-POINTED THEM TO `:1420`**, **WHICH IS
**THE **WRONG CONSTRUCT** -- **AND IT **MADE **THE POINTER LOOK FIXED** --
**AND A POINTER THAT **LOOKS** FIXED **AND IS NOT** IS **WORSE** THAN **A
POINTER THAT IS **RED**."""

import argparse
import csv
import re
import subprocess
from pathlib import Path

DEF = re.compile(r"^def ([A-Za-z_][A-Za-z0-9_.]*)\(")
TYPE = re.compile(r"^type ([A-Za-z_][A-Za-z0-9_]*)")
WANT = re.compile(r"pointer says :\d+ and `([^`]+)` is declared at :(\d+)")
BROKEN = {"DANGLING-LINE", "WRONG-LINE", "WRONG-LINE-BY-BLOCK"}
# **AND THE **FILES **THIS MOVE **TOUCHED** -- **AND **THE LIST IS **THE
# MOVE's OWN OUTPUT**, **NOT **A HAND LIST** -- **AND **IT IS **PASSED IN**."""
MOVED_FILES: set[str] = set()


def spans_of(path: Path) -> list[tuple[str, int, int, int]]:
    """**`(NAME, DECL_LINE, SPAN_START, SPAN_END)` FOR EVERY DECLARATION** --
    **AND THE SPAN **IS **THE INSTRUMENT's OWN**: **A DECLARATION OWNS **THE
    LINES UP TO **THE NEXT DECLARATION** -- **AND THAT IS **HOW **A
    CITATION **INTO **A BODY **IS **FOUND**."""
    lines = path.read_text().split("\n")
    decls: list[tuple[int, str]] = []
    for i, l in enumerate(lines):
        m = DEF.match(l) or TYPE.match(l)
        if m:
            decls.append((i + 1, m.group(1)))
    out = []
    for k, (d, n) in enumerate(decls):
        s = decls[k - 1][0] + 1 if k else 1
        e = decls[k + 1][0] if k + 1 < len(decls) else len(lines)
        out.append((n, d, s, e))
    return out


def owner_at(path: Path, line: int) -> str:
    """**THE NAME **OF **THE DECLARATION **WHOSE SPAN **CONTAINS **THE
    LINE** -- **AND **THE **INSTRUMENT's OWN SPAN RULE**."""
    for n, d, s, e in spans_of(path):
        if d < line <= e:
            return n
    return ""


def driver_site(root: Path, port_rel: str, name: str) -> tuple[str, int] | None:
    """**THE DRIVER **THAT **NOW **OWNS **THE CONSTRUCT** -- **AND IT IS
    **FOUND BY **READING **THE DRIVER's OWN HEADER**, **WHICH NAMES **THE
    PORT FILE IT SERVES** -- **AND THAT IS **A READ** AND NOT **A LIST**."""
    gates = root / "gates"
    if not gates.is_dir():
        return None
    want_port = "tinybendygrad/" + port_rel
    for d in sorted(gates.glob("*.bend")):
        try:
            head = d.read_text().split("\n")[0]
        except OSError:
            continue
        if f"THE GATE DRIVER for `{want_port}`" not in head:
            continue
        for n, dd, s, e in spans_of(d):
            if n == name or n.split(".")[-1] == name:
                return (f"gates/{d.name}", dd)
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tree", required=True)
    ap.add_argument("--git-dir", default="")
    ap.add_argument("--rows", required=True)
    ap.add_argument("--before-rows", default="")
    ap.add_argument("--moved", nargs="*", default=[])
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    root = Path(args.tree)
    port = root / "tinybendygrad"
    gitcwd = Path(args.git_dir) if args.git_dir else root
    MOVED_FILES.update(args.moved)
    with open(args.rows, newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    # **AND THE **PRE-MOVE** ROWS ARE **THE PRE-MOVE INSTRUMENT's OWN** --
    # **AND A POINTER IT **ALREADY** REJECTED IS **NOT **THIS MOVE's
    # BUSINESS**."""
    before: set[tuple[str, str, str]] = set()
    if args.before_rows:
        with open(args.before_rows, newline="") as fh:
            for b in csv.DictReader(fh, delimiter="\t"):
                if b.get("verdict") in BROKEN:
                    before.add((b.get("rel") or "", b.get("subject") or "",
                                b.get("lo") or ""))
    # **AND THE **PRE-MOVE** SPANS ARE **READ FROM GIT** -- **AND **A
    # POINTER **THAT **IS **DANGLING** IS **INSIDE **A **PRE-MOVE** SPAN**."""
    old_owner: dict[tuple[str, int], str] = {}
    try:
        pin = subprocess.run(["git", "rev-parse", "HEAD"], cwd=gitcwd,
                             capture_output=True, text=True, check=True).stdout.strip()
        for tgt in sorted({(r.get("target") or "").replace("tinybendygrad/", "")
                           for r in rows
                           if (r.get("target") or "").startswith("tinybendygrad/schedule/")}):
            g = subprocess.run(["git", "show", f"{pin}:tinybendygrad/{tgt}"],
                               cwd=gitcwd, capture_output=True, text=True)
            if g.returncode != 0:
                continue
            tmp = Path("/tmp/_pre_move.bend")
            tmp.write_text(g.stdout)
            for n, d, s, e in spans_of(tmp):
                for k in range(d + 1, e + 1):
                    old_owner.setdefault((tgt, k), n)
    except Exception as exc:
        print(f"  (git read failed: {exc})")
    changed = 0
    for r in rows:
        if r.get("verdict") not in BROKEN:
            continue
        if before and (r.get("rel") or "", r.get("subject") or "",
                        r.get("lo") or "") in before:
            # **AND **A POINTER THAT WAS **ALREADY **BROKEN** IS **LEFT
            # ALONE** -- **UNLESS **THE **CONSTRUCT **IT NAMES **MOVED** --
            # **AND **THAT IS **THE CASE **THE MOVE **CREATES** -- **AND A
            # POINTER **THAT WAS **WRONG **AND **IS NOW **DANGLING** IS **A
            # POINTER THE MOVE **MADE **WORSE** -- **AND **IT MUST BE
            # RE-POINTED **TOO**."
            #
            # **MEASURED 2026-11-10: `schedule/rangeify.bend:2810`, `:2987`,
            # `:3008` AND `:3055` WERE **`WRONG-LINE`** BEFORE THE MOVE **AND
            # ARE **`DANGLING-LINE`** AFTER IT -- **AND **THE CONSTRUCTS THEY
            # NAME (`rep_scan`, `eng_node`, `eng_range.go`, `eng_op_name`) **ARE
            # **IN **THE PORT** **AND **THEIR **LINES **MOVED** -- **AND **THE
            # POINTERS **MUST **BE **RE-POINTED** -- **AND **A POINTER **THAT
            # WAS **WRONG **AND **IS NOW **DANGLING** IS **WORSE**."
            tgt0 = (r.get("target") or "")
            if tgt0.startswith("tinybendygrad/"):
                tgt0 = tgt0[len("tinybendygrad/"):]
            if tgt0 not in MOVED_FILES:
                print(f"  SKIP (broken before the move, and the target did not move):"
                      f" {r.get('rel')}:{r.get('at')} -> {r.get('subject')}:{r.get('lo')}")
                continue
        rel = r.get("rel") or ""
        target = r.get("target") or ""
        at = (r.get("at") or "")
        lo = (r.get("lo") or "")
        if not rel or not target or not at or not lo.isdigit():
            continue
        rel = rel[len("tinybendygrad/"):] if rel.startswith("tinybendygrad/") else rel
        tgt = target[len("tinybendygrad/"):] if target.startswith("tinybendygrad/") else target
        subject = port / rel
        tpath = port / tgt
        if not subject.exists() or not tpath.exists():
            continue
        hi_s = (r.get("hi") or lo).strip()
        hi = int(hi_s) if hi_s.isdigit() else int(lo)
        # **AND THE **WANTED** CONSTRUCT AND **ITS LINE** COME FROM **THE
        # INSTRUMENT's OWN `why`** -- **AND **A `DANGLING-LINE` HAS **NONE**
        # -- **AND **FOR THOSE **THE CONSTRUCT IS **THE **PRE-MOVE** SPAN's
        # OWNER** -- **AND **THE **NEW LINE** IS **THE **DECLARATION SITE** OF
        # **THAT CONSTRUCT** **IN **THE **MOVED FILE**."""
        want = WANT.search(r.get("why") or "")
        if want:
            name = want.group(1)
        else:
            name = old_owner.get((tgt, int(lo)), "")
        if not name:
            print(f"  SKIP (no construct): {subject.relative_to(root)}:{at} -> {tgt}")
            continue
        site = 0
        for n, d, s, e in spans_of(tpath):
            if n == name:
                site = d
                break
        moved_to = None
        if site == 0:
            hit = driver_site(root, tgt, name)
            if hit is None:
                print(f"  SKIP (no site for {name}):"
                      f" {subject.relative_to(root)}:{at} -> {tgt}")
                continue
            moved_to, site = hit
        lines = subject.read_text().split("\n")
        if int(at) - 1 >= len(lines):
            continue
        line = lines[int(at) - 1]
        stem = Path(tgt).name
        pat = re.compile(r"(" + re.escape(tgt) + r"|" + re.escape(stem) + r"):"
                         + str(lo) + r"(?:-" + str(hi) + r")?")
        # **AND **A **CITING LINE** MAY CARRY **MORE THAN ONE** CITATION
        # **INTO **THE SAME FILE** -- **AND **THE ROWS **ARE **ONE PER
        # CITATION** -- **AND **THE TOOL **MUST **RE-POINT **EVERY ONE** --
        # **AND **THE **FIRST** MATCH **ALONE** LEFT **THE OTHERS** POINTING
        # AT **THE OLD LINE** -- **MEASURED 2026-11-10 ON
        # `tinybendygrad/schedule/rangify.bend`: **LINES 27, 28 AND 37 **EACH
        # CARRY **TWO** CITATIONS **INTO **THE SAME FILE**, **AND THE FIRST
        # PASS RE-POINTED **ONE** OF **EACH** -- **AND THE ROWS FOR **THE
        # OTHER** WERE **STILL `WRONG-LINE`**."""
        found = list(pat.finditer(line))
        if not found:
            print(f"  SKIP (old text not found): {subject.relative_to(root)}:{at}")
            continue
        # **AND THE **SHAPE** IS **KEPT** -- **AND **THE SHAPE IS **THE
        # **MATCHED TEXT's**, **NOT **THE ROW's** -- **AND **THE ROW's `hi`
        # IS **THE INSTRUMENT's SPAN**, **WHICH IS **A **RANGE** **FOR **A
        # SINGLE LINE** (**`lo == hi`**) -- **AND **THE **CITING TEXT's**
        # SPELLING IS **WHAT **THE **TREE **WRITES** -- **AND **THE
        # **CONVENTION** IS **SINGLE** (**44** IN `uop/ops.bend` **AGAINST
        # **7** RANGES**)."
        #
        # **MEASURED 2026-11-10: THE FIRST VERSION WROTE `:236-236` **FOR
        # **A **CITATION **THAT **WAS WRITTEN `:274`** -- **AND A **DIFFERENT
        # SPELLING** OF **THE **SAME POINTER** **IS **NOT **WHAT **THE **TREE
        # **WRITES**."
        was_range = "-" in found[0].group(0).rsplit(":", 1)[1]
        new = f":{site}-{site}" if was_range else f":{site}"
        target_text = moved_to if moved_to else found[0].group(1)
        if not moved_to and all(m.group(0).endswith(new) for m in found):
            print(f"  SKIP (already right): {subject.relative_to(root)}:{at}")
            continue
        # **AND THE REPLACEMENT IS **BUILT **FROM **THE END** -- **AND
        # **THE **OFFSETS **SHIFT** -- **AND **THAT IS **WHY **THE WALK **GOES
        # **BACKWARDS**."""
        out_line = line
        for mm in reversed(found):
            out_line = (out_line[:mm.start()] + target_text + new
                        + out_line[mm.end():])
        lines[int(at) - 1] = out_line
        if args.apply:
            subject.write_text("\n".join(lines))
        changed += 1
        print(f"  {subject.relative_to(root)}:{at}:"
              f" {mm.group(1)}:{lo} -> {target_text}:{site}  (decl={name})")
    print(f"REPOINTED {changed} citation(s)"
          + ("" if args.apply else "  (DRY RUN)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
