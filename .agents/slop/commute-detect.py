#!/usr/bin/env python3
"""THE COMMUTATIVE-REORDER DETECTOR -- empirical half.

WHY THIS EXISTS. The static half (`.agents/slop/unobservable-census.py`) proves a
row is blind from the row TEXT. This tool finds the blindness directly, by
flipping the behaviour and watching nothing move, so the claim does not rest on
an argument about the encoding.

TWO ORDER-DIRECTED MUTATION CLASSES, both derived from the port's OWN source,
both `wrong behaviour` rather than `refused`:

  C -- COMMUTATIVE-CHILDEN SWAP. At every construction of a commutative op
       (ADD, MUL, MAX, AND, OR, XOR, CMPEQ, CMPNE -- the set `uop/ops.bend`
       `is_comm` itself declares), swap src[0] and src[1]. A correct port and a
       WRONG port must both answer the same thing on a commutative node, so a
       row that does not move here has no ordering coverage at all; a row that
       DOES move is reading the src order of a node whose order is not
       information, which is itself reportable.

  A -- `List.append(x, A, xs, ys)` IS `xs ++ ys`. Swapping the last two
       arguments at every `List.append` site is the head/tail swap that
       agent-core records as having cost a real bug. Order-directed, and the
       shape the project already knows is a trap.

RULES THIS TOOL ENFORCES, each because breaking it has cost the project:

  * EVERY mutation runs against a FROZEN COPY made by `git archive`-equivalent
    of the LIVE tree, never the live tree. Other agents are mid-edit in these
    files.
  * THE COPY MUST REPRODUCE THE LIVE HASH before anything is mutated. Asserted
    per file with md5. A copy that does not reproduce is a FAILURE, not a run.
  * A PATCH THAT DOES NOT APPLY PRINTS `PATCH DID NOT APPLY`. Never "0 rows".
    A dead patch reading as a pass is what let M26 sit undetected.
  * A ZERO-ROW bend run is INDistinguishable from "did not start" (bend
    stack-overflows ~1 run in 20), so it is retried and a lane that never
    prints a row is a FAILURE.
  * The diff is over WHOLE `name=value` LINES, never over row names.

Usage:
  .venv/bin/python .agents/slop/commute-detect.py PORT [PORT ...] [--class C|A] [--top N]
"""
from __future__ import annotations

import hashlib
import os
import pathlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
COMM_OPS = ("ADD", "MUL", "MAX", "AND", "OR", "XOR", "CMPEQ", "CMPNE")

# `OpsADD{}, [a, b, c]` -- an op value followed by its src list.
COMM_SITE = re.compile(r"(Ops(?:%s)\{\},\s*\[)([^\[\]]*)(\])" % "|".join(COMM_OPS))
APPEND_SITE = re.compile(r"List\.append\(")


def split_top(s: str) -> list[str]:
    """Split on top-level commas. Bracket depth is counted, quotes respected."""
    out, depth, cur, q = [], 0, [], None
    for ch in s:
        if q:
            cur.append(ch)
            if ch == q:
                q = None
            continue
        if ch in "\"'":
            q = ch
            cur.append(ch)
        elif ch in "([{":
            depth += 1
            cur.append(ch)
        elif ch in ")]}":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def md5(p: pathlib.Path) -> str:
    return hashlib.md5(p.read_bytes()).hexdigest()


# ---------------------------------------------------------------- freezing
class Frozen:
    """A byte-exact copy of the live tree's `tinybendygrad/` plus a bend runner."""

    def __init__(self) -> None:
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="commute-freeze-"))
        self.src = ROOT / "tinybendygrad"
        self.dst = self.dir / "tinybendygrad"
        shutil.copytree(self.src, self.dst, symlinks=True)
        os.symlink(ROOT / "references", self.dir / "references")
        (self.dir / "bin").mkdir()
        os.symlink(ROOT / "bin" / "bend", self.dir / "bin" / "bend")
        self.check()

    def check(self) -> None:
        """THE HASH ASSERTION. A copy that does not reproduce the live tree is
        a failure, not a run: every later number would be about the wrong bytes."""
        bad = []
        for p in sorted(self.src.rglob("*.bend")):
            q = self.dst / p.relative_to(self.src)
            if not q.exists() or md5(p) != md5(q):
                bad.append(str(p.relative_to(self.src)))
        if bad:
            raise SystemExit("FROZEN COPY DOES NOT REPRODUCE THE LIVE TREE:\n  "
                             + "\n  ".join(bad))
        self.n_files = sum(1 for _ in self.src.rglob("*.bend"))
        print(f"frozen copy reproduces the live tree: {self.n_files} .bend files, "
              f"md5-verified, under {self.dir}")

    def src_of(self, rel: str) -> pathlib.Path:
        return self.dst / rel

    def substrate_stable(self, scope: list[str]) -> tuple[list[str], list[str]]:
        """WHICH live `.bend` files changed while this tool was running.

        `scope` is the port set plus everything it transitively imports; a file
        OUTSIDE the scope cannot change the numbers for the ports inside it, and
        discarding a 20-minute run because `renderer/cstyle.bend` — which
        `codegen/late/linearizer.bend` never imports — moved would be its own
        kind of dishonesty. Both lists are reported.

        agent-core records `fold.bend` and `movement.bend` going transiently
        uncompilable from a concurrent agent and one baseline silently
        corrupted, so a run whose IN-SCOPE substrate moved is DISCARDED.
        """
        moved = []
        for p in sorted(self.src.rglob("*.bend")):
            q = self.dst / p.relative_to(self.src)
            if not q.exists() or md5(p) != md5(q):
                moved.append(str(p.relative_to(self.src)))
        in_scope = [x for x in moved if any(x == s or x.startswith(s.split("/")[0] + "/")
                                            for s in scope)]
        return moved, in_scope

    def bend(self, rel: str, tries: int = 6) -> str:
        """Run a port. A ZERO-ROW run is the bend stack overflow, not a result."""
        last = ""
        for _ in range(tries):
            last = subprocess.run([str(self.dir / "bin" / "bend"), str(self.dst / rel)],
                                  capture_output=True, text=True,
                                  cwd=str(self.dir), timeout=1800).stdout
            if any("=" in ln for ln in last.splitlines()):
                return last
        raise SystemExit(f"ZERO ROWS from {rel} after {tries} tries -- bend did not run "
                         f"(the ~1-in-20 stack overflow). stderr tail:\n{last[-400:]}")



# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve() / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows_of = _rebase_gate.rows


def diff_rows(a: dict[str, str], b: dict[str, str]) -> list[str]:
    """WHOLE `name=value` LINES, per agent-core. Names alone moved nothing."""
    moved = []
    for k in sorted(set(a) | set(b)):
        if a.get(k) != b.get(k):
            moved.append(k)
    return moved


# ------------------------------------------------------------- mutations
def sites_comm(text: str) -> list[tuple[int, str, str]]:
    """(offset, old, new) for every commutative src-swap site."""
    out = []
    for m in COMM_SITE.finditer(text):
        parts = split_top(m.group(2))
        if len(parts) < 2 or not parts[0].strip() or not parts[1].strip():
            continue
        swapped = [parts[1], parts[0]] + parts[2:]
        new = m.group(1) + ",".join(swapped) + m.group(3)
        if new != m.group(0):
            out.append((m.start(), m.group(0), new))
    return out


def sites_append(text: str) -> list[tuple[int, str, str]]:
    """(offset, old, new) for every `List.append` last-two-argument swap."""
    out = []
    for m in APPEND_SITE.finditer(text):
        i, depth, q = m.end(), 0, None
        while i < len(text):
            ch = text[i]
            if q:
                if ch == q:
                    q = None
            elif ch in "\"'":
                q = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if i >= len(text):
            continue
        args = split_top(text[m.end():i])
        if len(args) < 2 or not args[-1].strip() or not args[-2].strip():
            continue
        # ONLY WHEN THE TWO ARGUMENTS HAVE THE SAME SHAPE. Swapping a `String`
        # accumulator with a `List` is not a behaviour change, it is a type
        # error, and a site that cannot compile is reported as
        # `PATCH DID NOT APPLY` and EXCLUDED -- never counted as a zero.
        if not _same_shape(args[-1], args[-2]):
            continue
        sw = args[:-2] + [args[-1], args[-2]]
        new = "List.append(" + ",".join(sw) + ")"
        out.append((m.start(), text[m.start():i + 1], new))
    return out


def _same_shape(a: str, b: str) -> bool:
    """Do two `List.append` arguments have the same syntactic shape?

    `[x]` and `[y]` are the same shape (both one-element list literals), as are
    `acc` and `t` (both bare applications). A `String` and a `List` are not, and
    swapping them is a compile error rather than a wrong answer.
    """
    def shape(x: str) -> str:
        x = x.strip()
        if x.startswith("[") and x.endswith("]"):
            return "list"
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*", x):
            return "bare"
        return "other"
    return shape(a) == shape(b) and shape(a) != "other"


def apply(text: str, off: int, old: str, new: str) -> str:
    if text[off:off + len(old)] != old:
        raise AssertionError("anchor moved")
    return text[:off] + new + text[off + len(old):]


# ------------------------------------------------------------- ports
PORTS = {
    # name -> (bend file relative to tinybendygrad/, [extra files also frozen])
    "late/linearizer": ["codegen/late/linearizer.bend"],
    "late/regalloc": ["codegen/late/regalloc.bend"],
    "late/gater": ["codegen/late/gater.bend"],
    "cstyle": ["renderer/cstyle.bend"],
    "ops_cl": ["runtime/ops_cl.bend", "runtime/ops_cuda.bend", "runtime/ops_hip.bend"],
    "ops_cpu_null": ["runtime/ops_cpu.bend", "runtime/ops_null.bend"],
    "ops_dsp": ["runtime/ops_dsp.bend"],
    "tc_ptx": ["renderer/tc_ptx.bend"],
    "gpudims": ["codegen/gpudims.bend"],
    "codegen/init": ["codegen/__init__.bend"],
    # The AMD renderer set: this is where the project's two CONFIRMED
    # commutative/order defects live (`generate.bend`'s `kern.sorted` /
    # `kern.unsorted` both 16, and `insert`'s `<` vs `>=` also 16). The gates
    # above are dominated by scalar/total rows and carry almost no commutative
    # population, so a census that stopped there would have measured nothing.
    "amd/generate": ["renderer/amd/generate.bend"],
    "amd/elf": ["renderer/amd/elf.bend"],
    "amd/dsl": ["renderer/amd/dsl.bend"],
    "amd/sqtt": ["renderer/amd/sqtt.bend"],
}


def main(argv: list[str]) -> int:
    classes = {"C", "A"}
    if "--class" in argv:
        i = argv.index("--class")
        classes = set(argv[i + 1].split(","))
        del argv[i:i + 2]
    top = 25
    if "--top" in argv:
        i = argv.index("--top")
        top = int(argv[i + 1])
        del argv[i:i + 2]
    names = [a for a in argv if not a.startswith("--")] or list(PORTS)
    fr = Frozen()
    print()
    print("PRE-FLIGHT: every port must print rows from the FROZEN copy before any")
    print("mutation runs. A zero-row port is the bend stack overflow, or another")
    print("agent mid-edit; it is NOT a result.")
    dead = []
    for nm in names:
        for rel in PORTS.get(nm, []):
            try:
                n = len(rows_of(fr.bend(rel)))
            except SystemExit as e:
                print(f"  PRE-FLIGHT FAIL {rel}: {e}")
                dead.append(rel)
                continue
            print(f"  pre-flight {rel}: {n} rows")
    if dead:
        raise SystemExit("PRE-FLIGHT FAILED -- no census was run:\n  " + "\n  ".join(dead))
    print()
    grand_base = grand_moved = 0
    report = []
    for nm in names:
        files = PORTS.get(nm)
        if files is None:
            print(f"!! unknown port {nm}")
            continue
        base = {}
        for rel in files:
            base.update(rows_of(fr.bend(rel)))
        if not base:
            print(f"!! {nm}: zero baseline rows")
            continue
        moved: set[str] = set()
        n_sites = n_applied = 0
        failed: list[str] = []
        detail = []
        for rel in files:
            p = fr.src_of(rel)
            orig = p.read_text()
            pool = []
            if "C" in classes:
                pool += [("C", *s) for s in sites_comm(orig)]
            if "A" in classes:
                pool += [("A", *s) for s in sites_append(orig)]
            for kind, off, old, new in pool:
                n_sites += 1
                label = f"{Path(rel).name}:{orig[:off].count(chr(10)) + 1}:{kind}"
                why = None
                out = None
                try:
                    p.write_text(apply(orig, off, old, new))
                    try:
                        out = fr.bend(rel)
                    except SystemExit as e:
                        why = str(e).splitlines()[0]
                except AssertionError:
                    why = "anchor moved"
                finally:
                    p.write_text(orig)
                if out is None or not rows_of(out):
                    why = why or "mutant printed ZERO rows"
                    failed.append(f"{label}: {why}")
                    print(f"PATCH DID NOT APPLY  {label}: {why}")
                    continue
                # ONLY A SITE THAT APPLIED AND RAN COUNTS. A site that did not
                # apply is NOT a zero -- reporting one as a zero is precisely how
                # M26 sat undetected, so the two are separate columns and a port
                # with zero applied sites reports NO MEASUREMENT, not 0%.
                n_applied += 1
                m = diff_rows(base, rows_of(out))
                moved.update(m)
                detail.append((label, m))
        hit = (len(moved) / len(base)) if n_applied else None
        grand_base += len(base)
        grand_moved += len(moved)
        report.append((nm, len(base), n_sites, n_applied, len(moved), hit,
                       sorted(set(base) - moved) if n_applied else [], failed))
        if n_applied:
            print(f"--- {nm}: {len(base)} rows, {n_sites} sites ({n_applied} applied, "
                  f"{len(failed)} did not apply), {len(moved)} rows moved, "
                  f"hit rate {hit*100:.1f}%")
        else:
            print(f"--- {nm}: {len(base)} rows, {n_sites} sites, 0 APPLIED "
                  f"-> NO MEASUREMENT (every patch failed; a zero here is not a result)")
    print()
    print("=" * 110)
    print("COMMUTATIVE-REORDER / HEAD-TAIL-SWAP HIT RATE  (rows moved / rows, over APPLIED sites)")
    print("=" * 110)
    print(f"{'port':20} {'rows':>6} {'sites':>6} {'appl':>6} {'moved':>7} {'hit%':>8} {'blind':>7}")
    for nm, nb, ns, nap, nmv, hit, blind, failed in report:
        hs = f"{hit*100:>7.1f}%" if hit is not None else "   NO-MEAS"
        print(f"{nm:20} {nb:>6} {ns:>6} {nap:>6} {nmv:>7} {hs} {len(blind) if nap else '-':>7}")
    meas = [r for r in report if r[5] is not None]
    if meas:
        tot = sum(r[1] for r in meas)
        mv = sum(r[4] for r in meas)
        print("-" * 110)
        print(f"{'TOTAL (measured)':20} {tot:>6} {sum(r[2] for r in meas):>6} "
              f"{sum(r[3] for r in meas):>6} {mv:>7} {mv/tot*100:>7.1f}%")
    nmeas = [r for r in report if r[5] is None]
    if nmeas:
        print()
        print(f"{len(nmeas)} port(s) reported NO MEASUREMENT because no patch applied:")
        for nm, *_rest in nmeas:
            print(f"      {nm}")
    portset = sorted({r for nm in names for r in PORTS.get(nm, [])})
    moved, in_scope = fr.substrate_stable(portset)
    print()
    if in_scope:
        print("SUBSTRATE MOVED -- IN SCOPE. THESE NUMBERS ARE ABOUT A TREE THAT NO")
        print("LONGER EXISTS, and this run is NOT a result. Another agent is mid-edit in:")
        for x in in_scope:
            print(f"      {x}")
    else:
        print(f"substrate check: no in-scope .bend file changed during this run "
              f"({len(portset)} port files + their first-level imports)")
    if moved:
        print(f"  ({len(moved)} live .bend file(s) moved OUT of scope, which cannot")
        print("   affect these ports because they are not imported by any of them:")
        for x in moved:
            print(f"      {x}")
    print()
    for nm, nb, ns, nap, nmv, hit, blind, failed in report:
        if not nap:
            print(f"--- {nm}: NO MEASUREMENT ({len(failed)} of {ns} patches did not apply)")
            for f in failed[:12]:
                print(f"      DID NOT APPLY  {f}")
            continue
        print(f"--- {nm}: {len(blind)} of {nb} rows no APPLIED order mutation moved "
              f"({len(blind)*100/nb:.0f}% of the port)")
        for b in blind[:top]:
            print(f"      {b}")
        if failed:
            print(f"    ({len(failed)} of {ns} sites did not apply and are EXCLUDED, not counted as zeros)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
