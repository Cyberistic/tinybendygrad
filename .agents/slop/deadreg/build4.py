#!/usr/bin/env python3
"""deadreg/build4.py -- THE FOUR CONFIGURATIONS, and the registered-effect count
of `runtime/dtype.c` in each.

WHY FOUR, AND NOT ONE.  `agent-core.md` and the brief are both right that a
registration is dead only if NO REACHABLE BUILD reaches its law, and that a
`file:line` or an id cited across two builds is a citation between two
namespaces (`CID_SZ_READ_DIR` is id 44 in one build and
`CID__________TINYBENDYGRAD_SZ_SZ_READ_DIR` is id 16 in another).  A single
build therefore cannot decide reachability; it can only decide "reachable in
BUILD X".  The precedent is SZLANE's four: `probe-none` / one seam alone / the
other seam alone / everything.  All four must compile, and each must register
exactly the effects its build reached.

COUNTS COME FROM `cc -E`, because that is the preprocessor's answer to "which
`io_eff(...)` calls actually land in the binary" -- not grep over the source,
which counts TEXT and not CODE.  `bend -o` IS NOT A BUILD; it emits C.

THE SCRATCH TREE IS A FULL `tinybendygrad` COPY.  Not `$TMPDIR`-only: a `.bend`
whose relative `import` cannot resolve emits something plausible and wrong.  The
copy is under `$TMPDIR` because nothing here is an artifact, and the live tree
is never written -- verified by md5 at the end.

    python3 deadreg/build4.py            # the four, plus the reachability census
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[3]
BEND = REPO / "bin" / "bend"
BOUNDED = REPO / "checks" / "bounded.py"
PY = REPO / ".venv" / "bin" / "python"
C_LANE = "tinybendygrad/runtime/dtype.c"
JS_LANE = "tinybendygrad/runtime/dtype.js"

# EVERY `bend` RUN IS UNDER BOTH BOUNDS.  On 2026-10-05 two
# `bun references/bend/bend2/main.ts` processes took all system memory (swap 1.6 of
# 2.0 GB, load 48) and crashed the machine; `ulimit` appears nowhere in this tree's
# scripts, the runaway was a SPAWNED GRANDCHILD, and `perl -e 'alarm N; exec @ARGV'`
# bounds TIME AND NOTHING ELSE.  `bounded.py` exit 3 = killed on memory, 4 = timed
# out, and rc 142 is MY OWN SIGALRM, which proves nothing.  `--mb 2048` is the
# starting ceiling and this unit never needed to raise it: measured peak RSS for
# these emits is ~450 MB.
BOUND = [str(PY), str(BOUNDED), "--seconds", "900", "--mb", "2048", "--"]


def bend(args: list[str]) -> subprocess.CompletedProcess:
    """The ONLY way this unit invokes the compiler."""
    assert BOUNDED.exists(), "checks/bounded.py is missing -- refusing to run `bend` bare"
    return subprocess.run(BOUND + [str(BEND)] + args, capture_output=True, text=True)

# The ten registrations, by the law each one serves.  Names are NOT taken on
# trust from the brief: `regs()` below reads them out of the file.
TEN = ["bf16", "fp16", "fp8_from", "fp8_to", "i64_trunc", "i64_floor_div",
       "i64_floor_mod", "i64_cdiv", "i64_cmod", "i64_ceildiv"]

# One call per law, typed to what `dtype.bend` declares TODAY.  These are the
# rows stage 8 asks for, so a configuration that reaches a seam is reaching the
# same law stage 8's row reaches -- that is what makes the two comparable.
CALL = {
    "bf16":          ("D.Dt.bf16(F32.bits(1.5))", "F32"),
    "fp16":          ("D.Dt.fp16(1.5)", "F32"),
    "fp8_from":      ("D.Dt.fp8_from(F32.bits(1.5), 0)", "U32"),
    "fp8_to":        ("D.Dt.fp8_to(60, 0)", "F32"),
    # DECIMAL `H.i64_of_hi_lo` LITERALS, never hex.  MEASURED here: `0xfffffff8`
    # is read by bend 2.0.34 as "a numeric literal, observed 'x'" -- the `x` is
    # the first character of `x` in whatever it thinks it is parsing.  The values
    # are produced by the same masking `jsstage.py:hi_lo` does, and
    # `deadreg/check.py` asserts all four calls print the CPython answers.
    "i64_trunc":     ("D.Dt.i64_trunc(H.i64_of_hi_lo(0, 7))", "H.I64"),
    "i64_floor_div": ("D.Dt.i64_floor_div(H.i64_of_hi_lo(4294967295, 4294967288), "
                      "H.i64_of_hi_lo(0, 4))", "H.I64"),
    "i64_floor_mod": ("D.Dt.i64_floor_mod(H.i64_of_hi_lo(4294967295, 4294967288), "
                      "H.i64_of_hi_lo(0, 4))", "H.I64"),
    "i64_cdiv":      ("D.Dt.i64_cdiv(H.i64_of_hi_lo(4294967295, 4294967289), "
                      "H.i64_of_hi_lo(0, 4))", "H.I64"),
    "i64_cmod":      ("D.Dt.i64_cmod(H.i64_of_hi_lo(4294967295, 4294967289), "
                      "H.i64_of_hi_lo(0, 4))", "H.I64"),
    "i64_ceildiv":   ("D.Dt.i64_ceildiv(H.i64_of_hi_lo(0, 7), "
                      "H.i64_of_hi_lo(0, 4))", "H.I64"),
}

# NO `import Base`.  MEASURED: with `import Base` in the prologue every law call
# type-checks as `@-R:Type -> @k:(@_:F32 -> IO.OP<R>) -> IO.OP<R>` instead of as
# its value, and the probe dies with "expected F32".  `jsstage.py`'s prologue --
# `dtype.bend` and `helpers.bend` and nothing else -- compiles all twenty of its
# rows, so the prologue is copied from the lane that is known to work rather than
# guessed at.
PROLOGUE = """import %s/tinybendygrad/dtype.bend as D
import %s/tinybendygrad/helpers.bend as H

def main() -> IO(Unit):
  do IO<Unit>:
%s
    IO.print("DEADREG %s rows=%d")
"""

# THE POSITIVE CONTROL, AND WHY IT MUST REWRITE `dtype.bend` IN THE SCRATCH TREE
# RATHER THAN DECLARE A LAW OF ITS OWN.
#
# A CID is mangled with the DEFINING FILE'S path: `sz.bend`'s `Sz.read_dir` is
# `CID__________TINYBENDYGRAD_SZ_SZ_READ_DIR`.  A control declared in a probe at
# any other path is therefore a DIFFERENT NAME, and `dtype.c`'s
# `#ifdef CID(Dt.bf16)` could not fire for it however many times the control
# called it.  That is not a fixable detail, it is the finding: **NO FILE OUTSIDE
# `dtype.bend`'S OWN PATH CAN EVER MAKE THESE TEN GUARDS FIRE.**  So the control
# has to rewrite the one file whose path the CIDs are mangled from -- in the
# SCRATCH COPY, never in the substrate.
#
# It is `sz.bend:124-128`'s shape verbatim: the `import` lines ARE the body of an
# `IO` law, so the pure def is replaced WHOLE -- header AND body -- not retyped in
# place.  MEASURED HERE: replacing only the header leaves the old body as an
# orphan and bend dies with "expected : 'def', 'type' or 'law' / observed : 'F'"
# at the first line of it, which is `dtype.bend:611`.
#
# AND THE WRAPPER MUST FOLLOW, because bend type-checks the whole imported module:
# `float_to_bf16` returns `F32` and its body is the law's value, so retyping the
# law alone makes the wrapper a `F32` def whose body is an `IO`.  That is the
# second of `sz.bend`'s two edits.
CTL_SEAM = ('@unsafe\ndef Dt.%s(%s) -> IO(%s):\n'
            '  import "./runtime/dtype.c"\n  import "./runtime/dtype.js"\n')
# (pure header, pure body, wrapper head) for the ONE law the control retypes.
CTL_BF16 = ("def Dt.bf16(+bits: U32) -> F32:",
            "  F.F32.from_bits(Bool.pick(U32, U32.is_eq(U32.and(bits, 2139095040),\n"
            "                                           2139095040), bits,\n"
            "                             bf16.round(bits)))\n",
            # The wrapper only needs its ARROW retyped.  MEASURED HERE: binding
            # the law with `<-` inside it, as `gate.py`'s predecessor draft did,
            # is a parse error -- an `IO` def's body is a single expression that
            # IS an `IO`, which is `sz.bend:1071` (`Bool.pick(IO(Row), ...)`) and
            # not a `do` block.  `Dt.bf16(...)` is already `IO(F32)`, so it is the
            # body unchanged.
            ("def float_to_bf16(x: F32) -> F32:\n  Dt.bf16(F32.bits(x))\n",
             "def float_to_bf16(x: F32) -> IO(F32):\n  Dt.bf16(F32.bits(x))\n"))


def regs(csrc: str) -> list[str]:
    """The laws `dtype.c` registers, read OUT OF THE FILE.  The brief said to
    confirm the count rather than take its line numbers."""
    return re.findall(r"io_eff\(CID\(Dt\.(\w+)\)", csrc)


def patch_seam(tree: pathlib.Path, law: str) -> None:
    """Make ONE law of the scratch tree's `dtype.bend` an `IO` seam importing
    `dtype.c`/`dtype.js`.  ANCHOR-ASSERTED: `assert s.count(a) == 1`, because a
    patch that silently matched nothing is how a control becomes a green run
    about nothing."""
    head, bdy, (wrap, wrap_io) = CTL_BF16
    assert law == "bf16", "the control carries one law's anchors, not %r" % law
    f = tree / "tinybendygrad" / "dtype.bend"
    s = f.read_text()
    for a in (head + "\n" + bdy, wrap):
        assert s.count(a) == 1, "control anchor %r occurs %dx in dtype.bend" % (a, s.count(a))
    s = s.replace(head + "\n" + bdy, CTL_SEAM % ("bf16", "+bits: U32", "F32"))
    s = s.replace(wrap, wrap_io)
    assert 'import "./runtime/dtype.c"' in s and 'import "./runtime/dtype.js"' in s
    f.write_text(s)


def body(names: list[str], decl: str) -> str:
    """Bind each law's value.  THE BIND IS THE REACH, so the shape is read from
    `dtype.bend`'s own DECLARATION, exactly as `jsstage.py:emit` does -- a
    hard-coded shape would be a probe that refuses on whichever side of the purity
    change the tree happens to be on."""
    out = []
    for n in names:
        ex, ty = CALL[n]
        # `<-` for BOTH, and a PURE law lifted with `IO.pure` -- `jsstage.py:emit`
        # spells it exactly so.  MEASURED HERE: binding a pure law with `=` inside
        # `do IO<Unit>` types the whole call as `@-R:Type -> @k:(..) -> IO.OP<R>`
        # and the probe dies with "expected F32".
        rhs = ex if is_io_law(decl, n) else f"IO.pure({ty}, {ex})"
        out.append(f"    {n} : {ty} <- {rhs}")
    return "\n".join(out)


def is_io_law(decl: str, name: str) -> bool:
    """`dtype.bend`'s own declaration.  `jsstage.py`'s SEAM_DECL, same regex: this
    is a shared fact about the substrate and re-deriving it here would be a second
    place for it to rot."""
    m = re.search(r"^def Dt\.%s\(.*?\)\s*->\s*(IO\(|[A-Z])" % re.escape(name), decl, re.M)
    return bool(m) and m.group(1) == "IO("


def config(work: pathlib.Path, tree: pathlib.Path, tag: str, names: list[str],
           seam: str | None = None) -> dict:
    """-> one configuration's own numbers, for BOTH lanes.  `cc -E` decides the C
    lane's count and the emitted JS is read directly, because JS has no
    conditional compilation at all -- `dtype.js` registers by STRING key.

    `seam` is the ONE law to make an `IO` seam in the scratch tree's `dtype.bend`,
    for the positive control.  `None` for the four real configurations, so they
    measure the tree as it ships.  THE PATCH IS APPLIED HERE, INSIDE `config`,
    because the predecessor applied it in the CALLER for one arm and not the other
    -- so `probe-ctl-seam` ran UNPATCHED and printed an emit byte-identical to
    `probe-bf16` (3124 lines each).  A positive control that never patched anything
    is the one failure mode this gate cannot have."""
    if seam is not None:
        patch_seam(tree, "bf16" if seam == "disarm" else seam)
    src = PROLOGUE % (tree, tree,
                      body(names, (tree / "tinybendygrad" / "dtype.bend").read_text()),
                      tag, len(names))
    bend_f = work / f"{tag}.bend"
    bend_f.write_text(src)
    # `bend -o` IS NOT A BUILD: it emits C and JS and compiles neither, `cc` is the
    # build.  And `bend -o` on a file that does NOT COMPILE LEAVES THE PREVIOUS
    # artifact in place -- made twice in this project -- so unlink first and a
    # stale artifact can never be counted as this run's.
    got = {}
    for ext in ("c", "js"):
        a = work / f"{tag}.{ext}"
        a.unlink(missing_ok=True)
        r = bend([str(bend_f), "-o", str(a)])
        got[ext] = {"rc": r.returncode, "path": a, "text": a.read_text() if a.exists() else "",
                    "err": (r.stdout + r.stderr)[-800:] if (r.returncode or not a.exists()) else ""}
    if got["c"]["rc"] or not got["c"]["text"]:
        return dict(tag=tag, bend_rc=got["c"]["rc"], emitted=False, err=got["c"]["err"],
                    pasted=False, io_eff=0, cids=[], cc_rc=None, js_regs=0,
                    js_bytes=0, js_dtype=0)
    # THE COUNTER MUST NAME THE LANE, TWICE OVER.
    #
    # (1) NOT A RAW `io_eff(` COUNT.  MEASURED HERE: that reads 2 in EVERY
    # configuration INCLUDING `probe-none`, because the emitted RUNTIME defines
    # `io_eff` and registers `IO.print` for itself.  That constant offset is the
    # whole difference between "registers nothing" and "registers three".
    #
    # (2) NOT `io_eff(CID_...)` EITHER, and this is the mechanism behind the
    # brief's fact 2 seen from the inside.  MEASURED HERE: `bend -o` rewrites
    # `CID(Dt.bf16)` inside the pasted `dtype.c` into the path-mangled
    # `CID____TREE_TINYBENDYGRAD_DTYPE_DT_BF16` and `#define`s THAT to a plain
    # integer, so `cc` sees `io_eff(14, bf16_run, 0)` and NO `CID_` token survives
    # into the preprocessed output at all.  A counter keyed on `CID_` reads 0 in a
    # build where the registration is PRESENT -- the worst direction for a gate to
    # be wrong in.  So the counter is keyed on `dtype.c`'s OWN TEN RUN FUNCTIONS,
    # which are the things being registered.
    p = subprocess.run(["cc", "-E", "-P", str(got["c"]["path"])], capture_output=True, text=True)
    pp = p.stdout
    runs = set(re.findall(r"^static Term (\w+)\(Env", (tree / C_LANE).read_text(), re.M))
    landed = [m for m in re.findall(r"io_eff\s*\(\s*[^,]+,\s*(\w+)\s*,", pp) if m in runs]
    # WHAT BEND ITSELF ANSWERED: it emits the `#define` for a CID only for a law
    # some build reaches, and that `#define` is the guard's whole condition.
    defined = sorted({m[4:].lower() for m in re.findall(
        r"^#define (CID_+[A-Z0-9_]*DTYPE_DT_[A-Z0-9_]+) [0-9]+", got["c"]["text"], re.M)})
    # THE JS LANE.  `dtype.js` has no `#ifdef`, so the question is not "did the
    # guard fire" but "is any byte of this file in the emitted bundle".  Counted
    # over `dtype.js`'s OWN top-level declarations, which is a census of the file
    # rather than a guess at what it might contribute.
    js = got["js"]["text"]
    js_declared = re.findall(r"^function (dtype_\w+)\(", (tree / JS_LANE).read_text(), re.M)
    # THE ASYMMETRY, AS A NUMBER.  `dtype.js` has NO `#ifdef`, so it is
    # all-or-nothing: MEASURED, ONE reached law pastes the whole file and
    # registers ALL TEN of its handlers (`io_eff("....Dt.fp16", dtype_fp16)` and
    # eight more sit beside `Dt.bf16`'s), where the C lane's guard registers
    # exactly one.  So the C column counts per law and the JS column cannot.
    js_regs = len([l for l in re.findall(r"^io_eff\(\"([^\"]+)\"", js, re.M) if "Dt." in l])
    return {"tag": tag, "bend_rc": 0, "emitted": True, "lines": len(got["c"]["text"].splitlines()),
            "pasted": "fp8_encode" in got["c"]["text"], "cc_rc": p.returncode,
            "io_eff": len(landed), "landed": landed, "cids": defined,
            "js_rc": got["js"]["rc"], "js_bytes": len(js), "js_regs": js_regs,
            "js_dtype": sum(1 for d in js_declared if ("function %s(" % d) in js),
            "err": (p.stderr or "")[-400:]}


def md5(p: pathlib.Path) -> str:
    return hashlib.md5(p.read_bytes()).hexdigest()


def main() -> int:
    cpath = REPO / C_LANE
    before = md5(cpath)
    found = regs(cpath.read_text())
    print("READ OUT OF %s, NOT TAKEN ON TRUST" % C_LANE)
    print("  io_eff(CID(Dt.<name>)) registrations: %d   %s" % (len(found), ", ".join(found)))
    print("  equals the ten named in the brief:  %s" % (sorted(found) == sorted(TEN)))
    print("  guarded by #ifdef CID(...):         %d of %d"
          % (cpath.read_text().count("#ifdef CID(Dt."), len(found)))

    decl = (REPO / "tinybendygrad" / "dtype.bend").read_text()
    print("\nREACHABILITY OF EACH LAW, FROM dtype.bend's OWN DECLARATION")
    print("  %-14s %-10s %s" % ("law", "dtype.bend", "dtype.c registration"))
    for n in TEN:
        io = is_io_law(decl, n)
        print("  %-14s %-10s %s" % (
            n, "IO(..)" if io else "PURE",
            "reachable ONLY if some build declares it IO AND imports dtype.c"))
    print("  dtype.bend `import \"./runtime/dtype.*\"` lines: %d"
          % len(re.findall(r'import\s+"\./runtime/dtype\.', decl)))
    print("  dtype.bend `IO(` occurrences:                    %d" % decl.count("IO("))

    configs = [
        ("probe-none", [], None),
        ("probe-bf16", ["bf16"], None),
        ("probe-ceildiv", ["i64_ceildiv"], None),
        ("probe-all", TEN, None),
        # THE POSITIVE CONTROL, and it is the instrument that makes the other
        # four mean anything.  `probe-{none,bf16,ceildiv,all}` all show the same
        # `io_eff` count; on their own that is ALSO what a BROKEN GUARD looks
        # like -- a guard that never fires, or a CID the preprocessor cannot see.
        # This configuration makes ONE of the ten laws an `IO` seam in the
        # scratch tree's `dtype.bend`, so the whole machinery runs end to end.
        #
        # IT IS A DIAGNOSTIC AND NOT A SUBSTRATE CHANGE.  It lives here, in the
        # unit's slop, and it is never proposed for `tinybendygrad/`: re-declaring
        # `Dt.bf16` as a seam in the substrate would undo LASTLAW's committed
        # retirement of it to make a gate green, which is precisely the thing the
        # brief forbids.
        #
        # WHAT IT DECIDES: whether `dtype.c` is pasted and its guard FIRES when a
        # CID really is allocated.  If it does, then the four probes above read
        # "unreachable", not "guarded wrongly".
        ("probe-ctl-seam", ["bf16"], "bf16"),
        # THE DISARM: the same reach, with the GUARD'S NAME changed.  Identical
        # `dtype.bend`, identical call, `dtype.c` pasted exactly the same way --
        # and 0 registrations, because the guard now asks for a CID no build
        # allocates.  So the count tracks THE LAW'S REACH, not the file's text,
        # which is what makes the four real probes' 0 a measurement.
        ("probe-ctl-disarm", ["bf16"], "disarm"),
    ]
    rows = []
    with tempfile.TemporaryDirectory() as td:
        base = pathlib.Path(td)
        # A FULL copy per configuration: the control MUTATES `dtype.bend` in the
        # scratch tree, so sharing one tree would leak the seam into the four
        # real configurations -- which are the ones that must measure the tree as
        # it ships.  A shared tree here would have reported 1 registration for all
        # six and been the most flattering wrong answer available.
        for tag, names, seam in configs:
            tree, work = base / tag / "tree", base / tag / "w"
            tree.mkdir(parents=True)
            work.mkdir(parents=True)
            # A FULL copy, AND ONE PER CONFIGURATION: a `.bend` whose relative
            # import cannot resolve compiles to something plausible and wrong, and
            # the control MUTATES `dtype.bend`, so a shared tree would leak the
            # seam into the four real configurations -- the ones that must measure
            # the tree as it ships.
            shutil.copytree(REPO / "tinybendygrad", tree / "tinybendygrad")
            if seam == "disarm":
                # THE GUARD'S NAME, not the law's reach.  Same patched
                # `dtype.bend`, same call, same paste -- and 0 registrations,
                # because the guard now asks for a law this build does NOT reach,
                # so bend emits no `#define` for it and `#ifdef` is false.  So the
                # count tracks THE LAW'S REACH, not the file's text, which is what
                # makes the four real probes' 0 a measurement and not a broken
                # guard.
                #
                # IT MUST BE ANOTHER REAL LAW, not an invented name.  MEASURED HERE:
                # `#ifdef CID(Dt.NOT_A_LAW)` makes `bend` itself refuse -- "CID(Dt.
                # NOT_A_LAW) names no constructor or def" -- so the disarm has to
                # name something that EXISTS and is UNREACHED, which is the harder
                # and better test: the guard is satisfied by the file's text and
                # denied by the build.
                c = tree / C_LANE
                cs = c.read_text()
                assert cs.count("#ifdef CID(Dt.bf16)") == 1
                c.write_text(cs.replace("#ifdef CID(Dt.bf16)", "#ifdef CID(Dt.i64_cmod)"))
            r = config(work, tree, tag, names, seam)
            rows.append(r)

    print("\nTHE FOUR CONFIGURATIONS, PLUS THE CONTROL THAT MAKES THEIR ZEROS MEAN")
    print("SOMETHING.  `cc -E` COUNTS THE C LANE, because the registrations that land")
    print("in the binary are PREPROCESSED OUTPUT, not source text.  The JS lane is read")
    print("off the EMIT: it has no `#ifdef`, so its question is not \"did the guard fire\"")
    print("but \"is any byte of `dtype.js` in the bundle\".")
    print("  %-16s %4s %7s %4s %8s %5s %9s %9s %9s  %s"
          % ("config", "bend", "C lines", "cc", "C regs", "JSrc", "JS bytes",
             "JS regs", "JS fns", "dtype.c in the build"))
    for r in rows:
        if not r["emitted"]:
            print("  %-16s %4d %7s %4s %8d %5s %9s %9s %9s  DID NOT COMPILE -- see err"
                  % (r["tag"], r["bend_rc"], "NO", "-", 0, "-", "-", "-", "-"))
            print("      %s" % r["err"].strip().replace("\n", "\n      "))
            continue
        print("  %-16s %4d %7d %4d %8d %5d %9d %9d %9d  %s" % (
            r["tag"], r["bend_rc"], r["lines"], r["cc_rc"], r["io_eff"], r["js_rc"],
            r["js_bytes"], r["js_regs"], r["js_dtype"],
            ("pasted" if r["pasted"] else "NOT pasted") +
            ("  " + ", ".join(r["cids"]) if r["cids"] else "")))

    four = [r for r in rows if not r["tag"].startswith("probe-ctl")]
    ctl = [r for r in rows if r["tag"].startswith("probe-ctl")]
    print("\n  FOUR REAL CONFIGURATIONS:  %d C and %d JS registrations landed, of %d and %d declared"
          % (sum(r["io_eff"] for r in four), sum(r["js_regs"] for r in four), len(found), len(found)))
    for r in ctl:
        print("  %-25s %d C, %d JS  (one law reached; `dtype.js` is ALL-OR-NOTHING)"
              % (r["tag"], r["io_eff"], r["js_regs"]))
    print("  the four zeros read UNREACHABLE, not BROKEN-GUARD: %s"
          % ("YES -- the positive control fired"
             if ctl and ctl[0]["io_eff"] > 0
             else "NO -- THE POSITIVE CONTROL DID NOT FIRE, SO THIS TABLE IS ABOUT NOTHING"))
    print("  live tree md5 unchanged: %s" % (md5(cpath) == before))
    return 0


if __name__ == "__main__":
    sys.exit(main())