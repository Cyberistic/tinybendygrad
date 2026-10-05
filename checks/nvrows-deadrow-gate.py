#!/usr/bin/env python3
r"""nvrows-deadrow-gate.py -- A CENSUS OF GATE-ROW CALL SITES THAT NEVER EXECUTE.

    python3 checks/nvrows-deadrow-gate.py
    python3 checks/nvrows-deadrow-gate.py --plant STRIP|ORPHAN
    python3 checks/nvrows-deadrow-gate.py --plant SELF

WHY IT EXISTS, MEASURED.  `nvdev.bend` has 374 `IP.{,u,s}row(` call sites.  Output
counting cannot see a dead one: the site's own name never appears, so it costs
ZERO duplicate measurements and is invisible to `nv_nvdev_gate.py`, which
compares `name=value` rows against CPython and reported `GATE PASS` on this file
with 6 of the 374 sites never executing.

A DEAD ARM IS INVISIBLE TO EVERY OUTPUT-COUNTING INSTRUMENT, so this counts
ABSENCE.  Bend has no `sys.settrace` and no reflection, so the Bend analogue of a
line tracer is to make every site's row name unique and then look for that unique
name in stdout.  A site that runs is seen; a site that does not run emits nothing
and is absent.  The technique is the same as `.agents/slop/nvdup/nvdup-deadarm.py`
-- a SITE census (a call site the tracer never saw) rather than a LINE census (a
name printed more than once) -- for the same reason: the second cannot see the
first.

THE SANDBOX IS MANDATORY, NOT TIDINESS.  Two measured reasons:
  * a `$TMPDIR` copy of `nvdev.bend` ALONE cannot resolve `import ./ip.bend`, and a
    `$TMPDIR` scratch copy that cannot resolve its imports produced 22 phantom
    blind spots in one unit.  So the import CLOSURE is copied with its repo-
    relative layout intact.
  * the repo tree is never written by this file.

AND THE DISARM IS PROVED OUTPUT-NEUTRAL, because a disarm that moves something is
a defect that has not been named yet.  Every run strips the injected tag back off
and diffs the whole stdout against the untagged baseline; a non-empty diff is a
FAILURE, not a footnote.
"""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[3]
TARGET = REPO / "tinybendygrad/runtime/support/nv/nvdev.bend"
BEND = REPO / "bin/bend"
# `import Base` resolves against the package root, which is the directory named
# `tinybendygrad` -- found by name, not by counting parents, because a fixed
# depth is exactly the kind of citation that goes stale.
PKG = next(p for p in TARGET.resolve().parents if p.name == "tinybendygrad")


def TARGET_PKG_OK(target):
    """True when `target` lives under the live package root."""
    return pathlib.Path(target).resolve().is_relative_to(PKG)

CALL = re.compile(r"IP\.(?:u|s)?row\(")
IMPORT = re.compile(r"^import\s+(\S+)")
TAG = re.compile(r"^(S\d{3}):")   # capture group EXCLUDES the colon; see strip_tag


def import_closure(pkg_root: pathlib.Path, entry: pathlib.Path, fallback=None):
    """Every `.bend` reachable from `entry` by `import`, plus the entry.

    Two resolution forms, both measured in this tree:
      `import ./ip.bend as IP` / `import ../../../helpers.bend as H`  -> relative to the FILE
      `import Base` / `import LAWS/spec.bend as S`                 -> relative to the
        package root (`tinybendygrad/`), which is how `ip.bend:371` and
        `LAWS/spec.bend:48` both resolve.  Getting this wrong is the 22-phantom-
        blind-spot failure: the sandbox then cannot compile and every site reads dead.

    `fallback` is a SECOND package root consulted for anything missing under
    `pkg_root`.  It is needed because the preserved strays carry only the one file
    under test: `strays/origin/tinybendygrad/` holds `nvdev.bend` and `ip.bend` and
    NOT `Base.bend`/`helpers.bend`/`device.bend`/`LAWS/spec.bend`, so without it the
    sandbox does not compile and the census correctly-but-uselessly answers
    INCONCLUSIVE on a file that is fine.  That is a red about the instrument, not
    about the file.
    """
    seen, queue = {entry.resolve()}, [entry.resolve()]
    while queue:
        cur = queue.pop()
        for line in cur.read_text().splitlines():
            m = IMPORT.match(line.strip())
            if not m:
                continue
            tok = m.group(1)
            base = cur.parent if tok.startswith(".") else pkg_root
            tgt = (base / tok).with_suffix(".bend").resolve()
            if not tgt.is_file() and fallback is not None:
                # Re-resolve from the FALLBACK tree at the SAME package-relative
                # position.  Resolving a `../../../x.bend` against the fallback ROOT
                # instead of the fallback's equivalent directory escapes it entirely.
                try:
                    mirror = fallback / cur.relative_to(pkg_root).parent
                except ValueError:
                    mirror = fallback
                alt = (mirror / tok).with_suffix(".bend").resolve()
                if alt.is_file():
                    tgt = alt
            if tgt.is_file() and tgt not in seen:
                seen.add(tgt)
                queue.append(tgt)
    return seen


def sandbox(pkg_root: pathlib.Path, entry: pathlib.Path, dst: pathlib.Path,
             fallback: pathlib.Path = None):
    """Mirror the import closure into `dst`, preserving each file's package-relative path."""
    for f in import_closure(pkg_root, entry, fallback):
        try:
            rel = f.relative_to(pkg_root)
        except ValueError:            # supplied by `fallback`, not by `pkg_root`
            rel = f.relative_to(fallback)
        out = dst / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(f, out)
    return dst / entry.relative_to(pkg_root)


def tag_source(text):
    """Give every `IP.{,u,s}row(` call site a unique `Snnn:` prefix on its NAME.

    Two syntactic forms, both measured, both rewritten bracket-balanced so no
    other argument is touched:
      IP.urow("name", v)              -> IP.urow(String.concat(["S001:", "name"]), v)
      IP.urow(String.concat([...]), v) -> IP.urow(String.concat(["S001:", ...]), v)
    """
    out, sites, n = [], [], 0
    for i, line in enumerate(text.split("\n"), start=1):
        if not CALL.search(line):
            out.append(line)
            continue
        new = line
        for m in reversed(list(CALL.finditer(line))):
            p, e = m.start(), m.end()
            n += 1
            tag = "S%03d:" % n
            if line[e] == '"':
                comma = line.index(",", e)
                new = (new[:p] + line[p:e] + 'String.concat(["' + tag + '", '
                       + line[e:comma] + "]), " + new[comma + 1:])
            else:
                k = new.index("String.concat([", p) + len("String.concat([")
                new = new[:k] + '"' + tag + '", ' + new[k:]
            sites.append((i, tag))
        out.append(new)
    return "\n".join(out), sites


def run(bend_file: pathlib.Path, cwd: pathlib.Path, alarm_s=900):
    """(`stdout`, `rc`). `timeout` is not installed on this box; perl's alarm is."""
    p = subprocess.run(["perl", "-e", "alarm %d; exec @ARGV" % alarm_s,
                        str(BEND), str(bend_file)],
                       capture_output=True, text=True, cwd=cwd)
    return p.stdout, p.returncode


def census(src_text, target, plant=None):
    """(`dead`, `sites`, `live_lines`, `rc`, `neutral`, `stdout`)."""
    if plant == "STRIP":
        # THE TRIAGE'S DAMAGE SHAPE, FAITHFUL: every `IP.{,u,s}row(` becomes a bare
        # `String.concat(`, so the call prints nothing and the name expression is
        # computed and discarded.  This is exactly what
        # `.agents/slop/strays/working/.../nvdev.bend` did to 313 of its 374 sites.
        # It is planted here rather than read out of the stray so the two runs are
        # comparable -- and the stray is also run, as `CENSUS STRAY`, because a
        # faithful reproduction is not the artifact.
        src_text = CALL.sub("String.concat(", src_text)
    if plant == "ORPHAN":
        # ONE more uncalled row group: the smallest SILENT live defect, planted.
        # Unlike STRIP this one still compiles and still prints 820 lines, so
        # `bend --check-only`, `nv_nvdev_gate.py` and every row counter see nothing.
        src_text = src_text.replace(
            "def t_end() -> IO(Unit):",
            'def t_planted_orphan() -> IO(Unit):\n'
            '  do IO<Unit>:\n'
            '    IP.urow("nv_planted_orphan_a", 1)\n'
            '    IP.srow("nv_planted_orphan_b", "x")\n'
            '    IP.urow("nv_planted_orphan_c", 2)\n\n'
            "def t_end() -> IO(Unit):", 1)
    if plant == "SELF":
        # PLANT THE DISARM'S OWN BLIND SPOT, so the limit is a printed number and not
        # a surprise.  The selector is TEXTUAL (`IP.(u|s)?row(`), exactly like
        # `nvdup-deadarm.py`'s `^\s*row(`, so a row emitted through a DIFFERENT
        # printer is invisible to the census.  `nvdev.bend:1770` already declares an
        # unused one -- `def emit(xs: List<&2, String>)` -- which the file's own
        # comment at :1318 describes as "ip.bend's own row printer, one IO.print for
        # a whole list".  Routing one live row through it keeps the row alive and
        # still printed, while the CENSUS loses sight of it: sites 374 -> 373,
        # verdict CLEAN.  That is the blind spot, measured rather than promised.
        src_text = src_text.replace(
            '    IP.urow("nv_vabits_3", nv.va_bits(3))',
            '    IP.emit([String.concat(["nv_vabits_3=", '
            'U32.show(nv.va_bits(3))])])', 1)
    if plant == "REVIVE":
        # THE ONLY FIX, PLANTED: add the one missing line `t_const` needed.  This
        # answers "can the 6 rows come back" -- they can, by being wired, and the
        # census is what says they were never wired.
        src_text = src_text.replace(
            '    +l : Unit <- t_flds_b42()',
            '    +l : Unit <- t_flds_b42()\n'
            '    +m : Unit <- t_const()', 1)

    text, sites = tag_source(src_text)

    # An out-of-tree copy (a preserved stray) is laid out at ITS OWN package root,
    # so `import ./ip.bend` still resolves and the sandbox is a faithful tree
    # rather than a single loose file.
    pkg = PKG if TARGET_PKG_OK(target) else next(
        p for p in target.resolve().parents if p.name == "tinybendygrad")

    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        entry = sandbox(pkg, target, root, PKG)
        # baseline = the same sandbox, untagged; `out` = the SAME file, tagged.
        entry.write_text(src_text)
        base_out, base_rc = run(entry, root)
        entry.write_text(text)
        out, rc = run(entry, root)

    if rc != 0:
        return [], sites, 0, rc, False, out
    # NEUTRALITY: the instrumented run, with every tag REMOVED, must equal the
    # untagged baseline LINE FOR LINE.  Comparing the *non-tag* subset against the
    # whole baseline is wrong -- it compares 10 lines against 821 and always says
    # False, which is how a red that contradicts the tool becomes a red about the
    # instrument instead.
    neutral = [TAG.sub("", l) for l in out.split("\n")] == base_out.split("\n")
    seen = {}
    for line in out.split("\n"):
        m = TAG.match(line)
        if m:
            seen[m.group(1)] = seen.get(m.group(1), 0) + 1
    dead = [(t, i) for i, t in sites if t[:-1] not in seen]  # sites carry "S001:"
    live_lines = sum(seen.values())
    return dead, sites, live_lines, rc, neutral, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plant", default=None,
                    choices=["STRIP", "ORPHAN", "SELF", "REVIVE"])
    ap.add_argument("--file", default=None,
                    help="census a copy instead of the live file "
                         "(e.g. .agents/slop/strays/working/.../nvdev.bend)")
    a = ap.parse_args()
    target = pathlib.Path(a.file).resolve() if a.file else TARGET
    src = target.read_text()
    dead, sites, live_lines, rc, neutral, out = census(src, target, a.plant)
    label = "%s%s" % (target.relative_to(REPO) if target.is_relative_to(REPO) else target,
                      (" PLANT=%s" % a.plant) if a.plant else "")
    print("=" * 78)
    print("DEAD-ROW CENSUS -- %s" % label)
    print("=" * 78)
    print("bend rc                 : %d" % rc)
    print("row call sites in source: %d" % len(sites))
    print("row LINES printed       : %d" % live_lines)
    if rc != 0:
        # A file that does not run is INCONCLUSIVE, not CLEAN.  Reporting 0 dead
        # here would be the exact "green verdict on a wrong answer" this census
        # exists to prevent -- and it is what the triage's `ALL PROOFS CHECK` trap
        # is about, only with the sign flipped.
        print("SITES THAT EXECUTED     : UNKNOWN -- the file did not run")
        print("VERDICT: INCONCLUSIVE -- bend rc %d. The compile lane owns this file;" % rc)
        print("         a row census cannot speak about a program that never ran.")
        return 2
    print("SITES THAT EXECUTED     : %d" % (len(sites) - len(dead)))
    print("SITES THAT NEVER RAN    : %d" % len(dead))
    print("DISARM OUTPUT-NEUTRAL   : %s" % neutral)
    for t, i in dead:
        print("   DEAD  %s  %s:%d" % (t, target.name, i))
    print("VERDICT: %s" % ("CLEAN" if not dead else
                           "%d DEAD SITE(S) -- the file's gate is short that many rows" % len(dead)))
    return 1 if dead or not neutral else 0


if __name__ == "__main__":
    sys.exit(main())