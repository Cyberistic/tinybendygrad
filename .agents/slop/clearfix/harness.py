#!/usr/bin/env python3
"""The instrument: run a gate file against a chosen `gatekit`, and say what it LEFT BEHIND.

    import harness; harness.run_gate(...), harness.snapshot(...), harness.verdict(...)

FIVE MEASURED PROPERTIES OF THIS INSTRUMENT, each of which is a way the recurring harness
defect in this project hides a wrong answer:

1. **STALE IS A sha256 AGAINST THE PREVIOUS GREEN RUN'S BYTES.** A leftover COUNT cannot
   tell "its own bytes" from "the last good run's bytes", and that distinction IS the claim.
   `verdict()` therefore returns ABSENT / STALE / FRESH per file, never a count.
2. **NOTHING IS DELETED BETWEEN BEATS.** The leftover files ARE the state under test; a
   harness that `rmtree`s the directory between beats deletes the state and then reports the
   deletion as its finding. The scratch root is emptied exactly once, before the first beat,
   and this module never touches it again.
3. **THE BACKGROUND NOISE IS MEASURED BEFORE THE DISCRIMINATOR IS USED.** `bend` prints
   `bend <ver> is available: run bend update` on STDERR on EVERY invocation, green included
   (42 bytes, measured). So "stderr is non-empty" is not "bend said something", and
   `NOTICE` strips that line before anything is asked of stderr.
4. **THE INSTRUMENT MUST BE ABLE TO MOVE.** Every beat prints the sha of what it found, and
   the matrix asserts that a lane which reported ABSENT and a lane which reported STALE
   disagreed -- otherwise a harness stuck on one answer looks identical to a working one.
5. **NO SHADOW TREE.** MEASURED elsewhere in this project: a shadow tree that symlinks
   `tinybendygrad` makes `bend` reject the import and four gates went red on a driver
   byte-identical to the passing one. Every run here executes the real driver and the real
   oracle in this tree; only the ARTIFACT ROOT and the `gatekit` COPY move.
"""
import ast
import contextlib
import hashlib
import importlib
import importlib.util
import io
import os
import re
import runpy
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / "bin" / "bend").is_file())

# `gates/gatekit.py:56`'s own notice, repeated here because the instrument must ask the
# question independently of the thing it measures. If the two ever disagree, the fix is in
# BOTH and not in whichever one happens to be looking.
NOTICE = re.compile(r"^bend \S+ is available: run bend update$")

# A PIN THAT CANNOT MATCH ANYTHING. `oracle_drift` only reports a sha mismatch, so a pin of
# this shape is drift by construction and the beat needs no planted file at all -- which is
# what keeps the drift beat honest: it plants NOTHING in another unit's tree.
DEAD_PIN = "0" * 64


def sha_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha(p):
    return sha_bytes(Path(p).read_bytes())


def said(text):
    """stderr lines that are neither blank nor the update notice."""
    return [l.strip() for l in (text or "").splitlines()
            if l.strip() and not NOTICE.match(l.strip())]


# ---- run one gate ---------------------------------------------------------------
def run_gate(gate, gk, art, name, quiet=False):
    """`(rc, seconds)` for `gate` with `gk` installed as `gatekit`, writing to `art/name`.

    `gk` is a PATH to a gatekit copy, not a module, because the copies differ from the live
    file in `ART` and in one `__init__` line, and the module is re-executed per beat so no
    state leaks from the previous one. `name` is the `Gate`'s own name and IS the directory
    name, so it is passed rather than guessed -- a mismatch here would leave the snapshot
    reading an always-empty directory and the instrument reporting nothing as a finding.

    `quiet` captures the gate's OWN output. Three beats in this harness run the SAME gate with
    the SAME pin and are required to differ only in their artifact directory, and an
    interposed reader sees a gate's stderr as though it were the instrument's own --
    `gates/gatekit.py:179`'s `_say` writes to stderr, so an unquiet beat makes its own
    findings unreadable in the transcript. The text is returned through `gate_output()`.
    """
    # NO ENV VAR. Each frozen `gatekit` copy names its OWN artifact root from its own
    # directory (`freeze.py`), so a run's destination is a property of the COPY and two copies
    # cannot collide. `art` is therefore ASSERTED against the copy's own `ART` rather than
    # setting it: if they disagree, the run writes somewhere this harness will not look, and
    # the instrument then reports an always-empty directory as a finding. MEASURED, in that
    # exact shape, on the version that took an env var instead.
    spec = importlib.util.spec_from_file_location("gatekit", str(gk))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)   # NOT OPTIONAL: an un-executed module in sys.modules
    sys.modules["gatekit"] = mod  # makes `from gatekit import Gate` find THIS one, not gates/'
    # `art` is the ROOT and `name` the `Gate`'s own name, which is its directory: the assert
    # is on the join, because `Gate.__init__` does `ART / name` and nothing else.
    assert (art / name) == (mod.ART / name), (
        f"run_gate was handed {art} but this gatekit's ART is {mod.ART}: the run would write "
        f"where the harness will not look")
    art.mkdir(parents=True, exist_ok=True)
    t0 = time.monotonic()
    # TWO STREAMS, NOT ONE. The noise this harness has to measure is on STDERR -- it is `bend`'s
    # update notice -- and folding stderr into one buffer with stdout would have measured the
    # gate's own summary lines instead and reported a healthy run as talking. MEASURED the
    # first time this was folded: a fully green run showed "3 lines, 0 of them the notice,
    # 3 after stripping", which is stdout's own output and says nothing about stderr at all.
    out, err = (io.StringIO(), io.StringIO()) if quiet else (None, None)
    try:
        if out:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = _run(str(gate))
        else:
            rc = _run(str(gate))
    finally:
        sys.modules.pop("gatekit", None)
    _LAST["out"], _LAST["err"] = (out.getvalue() if out else ""), (err.getvalue() if err else "")
    return rc, time.monotonic() - t0


_LAST = {"out": "", "err": ""}


def gate_output():
    """`(stdout, stderr)` of the most recent `run_gate(quiet=True)`."""
    return _LAST["out"], _LAST["err"]


def mod_art(gk):
    """The artifact root a `gatekit` copy will write into, loaded without importing it as one.

    A caller that needs the root BEFORE a run cannot get it from the module, because the
    module is created and discarded inside `run_gate`. Reading it here costs one extra
    `exec_module` and it keeps the two in step: `run_gate` asserts its `art` against the same
    attribute, so a copy whose `ART` moved is refused rather than silently redirected.
    """
    spec = importlib.util.spec_from_file_location("_gk_probe", str(gk))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return Path(mod.ART)


def _run(gate):
    try:
        runpy.run_path(gate, run_name="__main__")
        return 0
    except SystemExit as e:
        return e.code if isinstance(e.code, int) else 1


# ---- what is on disk ------------------------------------------------------------
def snapshot(d):
    """`{name: sha256}` for every file in `d`, empty dict for a missing or empty directory."""
    d = Path(d)
    return {p.name: sha(p) for p in sorted(d.iterdir()) if p.is_file()} if d.is_dir() else {}


def verdict(now, baseline):
    """One word per file against the previous GREEN run's bytes.

    ABSENT  nothing on disk -- an empty directory cannot be diffed by accident
    STALE   on disk and byte-identical to the previous green run -- THE BUG
    FRESH   on disk and different from the previous green run
    NEW     on disk and never seen in any green run
    """
    out = {}
    for name, h in now.items():
        out[name] = ("STALE" if baseline.get(name) == h
                     else "FRESH" if name in baseline else "NEW")
    return out


def line(v):
    """A verdict as one fixed-width row: `EMPTY` or `name=WORD` per file, in name order."""
    if not v:
        return "EMPTY (0 files)"
    return "  ".join(f"{n}={w}" for n, w in sorted(v.items()))


# ---- variants of a gate file ----------------------------------------------------
def _kwarg(src, name):
    """The literal value of a `Gate(...)` keyword, PARSED not transcribed.

    `retention-check.py` records why: a typed copy of a set the source already declares goes
    stale silently. This reads the gate's own `port_only`, so a gate that changes its list
    changes this fixture's behaviour instead of quietly measuring the wrong rows.
    """


def _bump(seg, delta):
    """`seg` moved by `delta` if it is an integer literal, else `seg` made unsatisfiable.

    A gate that writes `rows=ROWS` gets `ROWS + 1` -- the constant is left alone and the
    arithmetic is appended, so the substitution works for a literal, a name, or a sum, and
    never has to know which. `int(seg) + delta` is the literal case and is what three of the
    nine gates need; the rest take the expression branch.
    """
    try:
        return str(int(seg) + delta)
    except ValueError:
        # `ROWS + -1` is valid Python and ugly; this is the readable form, and it is a
        # fixture nobody reads except a diff.
        return f"{seg} {'+' if delta > 0 else '-'} {abs(delta)}"


def harness_oracle(src):
    """The oracle a gate names, resolved the way `Gate._resolve` resolves it: `gates/` first,
    then the repo root, because most oracles and drivers in `gates/` are RELATIVE paths that
    only exist beside the gate."""
    rel = _kwarg(src, "oracle")
    for base in (ROOT / "gates", ROOT):
        if (base / rel).is_file():
            return (base / rel).resolve()
    raise SystemExit(f"harness: the oracle {rel} named by this gate is not on disk")


def _gate_name(src):
    """A `Gate`'s positional name argument, PARSED rather than pattern-matched.

    It is the artifact DIRECTORY (`ART / name`), so it is the one string in a gate file that
    decides where the state under test lands.
    """
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "Gate":
            return ast.literal_eval(node.args[0])
    raise SystemExit("harness: no Gate(...) call")


_MISSING = object()


def _kwarg(src, name, default=_MISSING):
    """`[kw.arg == name]` for a `Gate(...)` call, with a DEFAULT for gates that omit it.

    Six of the nine gates declare no `port_only` at all -- which is the SIMPLEST shape, since
    nothing is excluded and every row is compared. `default=None` says so, and the first
    version raised instead and killed the matrix on gate five of nine.
    """
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "Gate":
            for kw in node.keywords:
                if kw.arg == name:
                    return ast.literal_eval(kw.value)
    if default is not _MISSING:
        return default
    raise SystemExit(f"harness: no {name}= in this gate's Gate(...) call")


def build_wrong_oracle(gate, out):
    """This gate's real oracle rows with ONE COMPARED row's value replaced.

    The beat it feeds is the NEGATIVE CONTROL: a failure that happens INSIDE `run()`, after
    every lane has written and after the native compile, so the directory holds a full set of
    staged files when the verdict is decided. If the instrument called that STALE it would be
    reporting "red run" rather than "last green run's bytes", and the whole matrix would be
    worth nothing.

    Only a COMPARED row is corrupted. A `port_only` row is excluded from the diff on BOTH
    sides, so changing one would alter nothing and the control would silently not fire.
    """
    src = Path(gate).read_text()
    skip = set(_kwarg(src, "port_only", default=None) or ())
    oracle = harness_oracle(src)
    # `check=True` was a lie about the ORACLE, not about this call: an oracle that exits
    # non-zero still PRINTS its rows on stdout, and several of the nine do (`bc-u32` and
    # `wk-cd` print and then fail a divergence pin). MEASURED as
    # `CalledProcessError: .../ew-consts-oracle.py returned non-zero exit status 2` killing
    # the matrix on gate three of nine. A fixture that refuses to read a real oracle's real
    # output is a fixture that cannot measure six of the nine gates.
    r = subprocess.run([str(ROOT / ".venv" / "bin" / "python"), str(oracle)],
                       capture_output=True, text=True)
    if not r.stdout.strip():
        raise SystemExit(f"build_wrong_oracle: {oracle} printed NOTHING on stdout (rc={r.returncode}"
                         f", stderr={r.stderr.strip()[:120]!r}) -- there are no rows to corrupt")
    rows = r.stdout.splitlines()
    for i, r in enumerate(rows):
        if "=" in r and r.split("=", 1)[0] not in skip:
            rows[i] = r.split("=", 1)[0] + "=CONTROL-" + sha_bytes(r.encode())[:8]
            break
    else:
        raise SystemExit("harness: no compared row to corrupt -- the control would not fire")
    out.write_text(
        "#!/usr/bin/env python3\n"
        f'"""CONTROL FIXTURE for {gate.name}: its real oracle with ONE COMPARED row\'s value\n'
        'replaced, so the lane DIFF fires inside `run()` -- after every lane has written and\n'
        'after the native compile. Generated by harness.build_wrong_oracle; the changed row is\n'
        + "".join(f"    {r!r}\n" for r in rows[:1])
        + '"""\n'
        "import sys\n"
        f"sys.stdout.write({rows_text(rows)!r})\n")
    return out


def rows_text(rows):
    return "\n".join(rows) + "\n"


def gatekit_opt1(gk, out):
    """OPTION 1 as a diff: `pins=` on the `Gate`, and the drift check INSIDE `run()`.

    The brief's option 1 says to remove the early exit so the drift path routes through
    `run()`. That cannot be done in a gate FILE at all: `run()` lives in `gates/gatekit.py`,
    has no drift hook, and `Gate.__init__` takes no pins. So option 1 is not a caller-side
    change -- it is a BIGGER library change than option 2, and it makes the refusal pay for
    three `bend` processes to learn that a sha256 does not match. Written here so the claim
    is measured rather than argued.
    """
    src = Path(gk).read_text()
    src = src.replace("                 warm=\"fatal\"):", "                 warm=\"fatal\", pins=None):", 1)
    src = src.replace("        self.warm_mode = warm", "        self.warm_mode = warm\n"
                    "        self.pins = dict(pins or {})", 1)
    src = src.replace("        ok = False\n        try:\n            self._clear()",
                      "        ok = False\n        try:\n            self._clear()\n"
                      "            for rel, want in self.pins.items():\n"
                      "                if not (ROOT / rel).is_file() or \\\n"
                      "                        hashlib.sha256((ROOT / rel).read_bytes()"
                      ").hexdigest() != want:\n"
                      "                    self._say(f'ORACLE DRIFT: {rel}')\n"
                      "                    return 2", 1)
    out.write_text(src)
    assert src != Path(gk).read_text(), "gatekit_opt1: no anchor matched -- option 1 not built"
    return out


def gatekit_opt3(gk, out):
    """OPTION 3 as a diff: a public `clear()`, for a caller to put in its own `finally`.

    Option 3 needs the caller to wrap its own `sys.exit`, which means it needs a public way to
    clear -- so it too is a library change, plus a per-caller edit that can be forgotten.
    Written here so the comparison is between three built things rather than one built thing
    and two descriptions.
    """
    src = Path(gk).read_text()
    src = src.replace("    def _clear(self):", "    def clear(self):\n"
                    '        """PUBLIC alias: a caller that wraps its own `sys.exit` needs this."""\n'
                    "        self._clear()\n\n    def _clear(self):", 1)
    out.write_text(src)
    assert src != Path(gk).read_text(), "gatekit_opt3: no anchor matched -- option 3 not built"
    return out


def variant(base, out, *, pin="keep", oracle=None, name=None, rows_delta=0):
    """A copy of a gate file with DECLARED substitutions, written to `out`.

    `pin="live"` substitutes the pinned file's ACTUAL sha, which is the green beat: a pin that
    matches is a pin that does not fire. `pin="dead"` substitutes a sha nothing can match,
    which is the drift beat: `oracle_drift` reports a MISMATCH, so no file is planted and no
    other unit's tree is touched. `pin="keep"` and `oracle=None` leave it byte-identical.
    """
    # `base` is a PATH. `src` is not accepted: the first version of this did, and a caller
    # passing gate SOURCE got the whole gate's text treated as a filename -- MEASURED, as
    # `OSError: File name too long: '#!/usr/bin/env python3\n"""mixin-op-gate.py ...`. A
    # parameter that silently accepts the wrong type is a parameter that will.
    src = Path(base).read_text()
    out.parent.mkdir(parents=True, exist_ok=True)
    if pin in ("dead", "live"):
        real = re.search(r'"[0-9a-f]{64}"', src)
        if not real:
            raise SystemExit(f"harness: no 64-hex pin in {base}")
        if pin == "live" or _pin_intact(base, real.group(0)[1:-1]):
            # A pin that ALREADY does not match is left alone under "dead", so on this tree --
            # where mixin-op-gate's pin is stale as committed -- the drift beat runs the LIVE
            # FILE rather than a copy of it.
            want = _pin_target_sha(base) if pin == "live" else DEAD_PIN
            src = src.replace(real.group(0), f'"{want}"', 1)
    if oracle is not None:
        src = src.replace(f'"{_kwarg(src, "oracle")}"', f'"{oracle}"', 1)
    if name is not None:
        # The `Gate`'s NAME is its directory (`ART / name`), so renaming it is how two lanes
        # that share one `gatekit` root are kept apart -- and the substitution is on the
        # positional first argument of `Gate(...)`, which is the only place a name appears.
        src = src.replace(f'Gate(\n    "{_gate_name(src)}"', f'Gate(\n    "{name}"', 1)
        assert f'"{name}"' in src, f"variant: could not rename the Gate to {name}"
    if rows_delta:
        # A ROW-COUNT the gate cannot meet. For the six gates with no `ORACLE_PIN` this is the
        # only red shape available without touching a driver, and it is a legitimate one: the
        # check fires INSIDE `run()` after `_clear()`, which is exactly the property the bug
        # was about.
        #
        # THE VALUE IS NOT ALWAYS A LITERAL. MEASURED: `bc-u32`, `i64-shl` and `i64-shr` write
        # `rows=ROWS`, a module constant, so `ast.literal_eval` raised
        # `ValueError: malformed node ... <ast.Name>` and killed the matrix on gate one of
        # nine. The substitution is therefore made on the AST'S OWN source segment for the
        # `rows=` keyword -- `ast.get_source_segment` -- which handles a literal and a name
        # identically, and is anchored by the keyword so it cannot match a comment.
        kw = next(k for c in ast.walk(ast.parse(src)) if isinstance(c, ast.Call)
                  and getattr(c.func, "id", None) == "Gate"
                  for k in c.keywords if k.arg == "rows")
        seg = ast.get_source_segment(src, kw.value)
        assert seg, "variant: no source segment for `rows=`"
        lines = src.splitlines(keepends=True)
        col = sum(len(l) for l in lines[:kw.value.lineno - 1]) + kw.value.col_offset
        lines[kw.value.lineno - 1] = (lines[kw.value.lineno - 1][:kw.value.col_offset]
                                      + _bump(seg, rows_delta)
                                      + lines[kw.value.lineno - 1][kw.value.end_col_offset:])
        src = "".join(lines)
        assert _bump(seg, rows_delta) in src, "variant: could not move the row count"
    out.write_text(src)
    return out


def _pin_target(gate):
    return ROOT / re.search(r'"(\.agents/[^"]+)"', Path(gate).read_text()).group(1)


def _pin_target_sha(gate):
    p = _pin_target(gate)
    if not p.is_file():
        raise SystemExit(f"harness: the pinned oracle {p} is gone -- the green beat cannot be built")
    return sha(p)


def _pin_intact(gate, pin_hex):
    p = _pin_target(gate)
    return p.is_file() and sha(p) == pin_hex


# ---- the call site's own census, and why it is a DIFFERENT question from clause II ----
def call_site_exits(gate):
    """`(total_exits_before_run, ctor_line, run_line, clears_before_run)` for a gate FILE.

    `gates/retention-check.py`'s clause II counts exits INSIDE `Gate.run`. It cannot see the
    call site at all, because it reads `gates/gatekit.py` and this reads `gates/<gate>.py`.
    That is the whole of the bug: the exits that stranded seven artifacts are in neither its
    denominator nor its numerator.

    `clears_before_run` is the set of removal-shaped calls that appear BEFORE `run()` is
    called -- `unlink`, `rmtree`, `iterdir`, and (the shape option 2 takes) a `clear` on the
    `Gate`. An EMPTY set is the finding: the caller can end the process with the previous run's
    bytes still on disk and nothing of its own has touched the directory.

    This is a STATIC census and it is reported as one, with its denominator printed beside it,
    because a count of exits cannot tell whether the process was ever given the chance to
    clear. It is the reason the repro has to RUN the gate: `NOW/A1` and `OPT2/A1` are the same
    7 lines of source and they differ on disk.
    """
    src = Path(gate).read_text()
    tree = ast.parse(src)
    exits = sorted(n.lineno for n in ast.walk(tree) if isinstance(n, ast.Call)
                   and getattr(n.func, "attr", "") in ("exit", "quit"))
    runs = sorted(n.lineno for n in ast.walk(tree) if isinstance(n, ast.Call)
                  and getattr(n.func, "attr", "") == "run")
    if not runs:
        raise SystemExit(f"call_site_exits: {gate} never calls run() -- no denominator")
    remover = {"unlink", "rmtree", "remove", "rmdir", "iterdir", "walk", "glob", "clear"}
    clears = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and node.lineno < runs[0]:
            fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            if fn in remover:
                clears.add(fn)
    return (sum(1 for e in exits if e < runs[0]), len(exits), runs[0], sorted(clears))