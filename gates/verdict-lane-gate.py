#!/usr/bin/env python3
"""verdict-lane-gate.py -- THE PORT'S PROOFS AGAINST THE LEAN-VERIFIED KERNEL.

    .venv/bin/python gates/verdict-lane-gate.py                # the lanes, the classes, the verdict
    .venv/bin/python gates/verdict-lane-gate.py --plant        # the plant, the control, the wrong shapes
    .venv/bin/python gates/verdict-lane-gate.py --write-pins   # the pins for the source as it stands

WHAT THIS GATE CLAIMS, AND WHY IT IS NOT A SECOND COMPILE GATE.

`checks/port-compile-gate.py` asks "DOES THE PORT COMPILE?" -- 165 of 169 files
compile, 4 are cold by design -- and it asks `--check-only`, which is the
UNVERIFIED TypeScript checker.  `references/bend/bend2/main.ts:816` asks a
STRONGER question: `--verdict` re-checks the same book against the Lean-verified
kernel (BendTT).  The two lanes are not the same instrument, so their AGREEMENT
is a claim worth making and their DISAGREEMENT is a finding worth failing on.

BUT THE DEFAULT `--verdict` LANE IS NOT A FUNCTION OF THIS REPOSITORY, AND THAT
IS THE FINDING THIS GATE IS BUILT ON.  `references/bend/bend2/safe.ts`'s
`kernel_bin()` is, in effect:

    const hash = sha256(LEAN_VERSION + "\\0" + bendtt.lean)[:16];
    const dir  = ~/.bend/bendtt/<hash>;
    const bin  = dir/bendtt;
    if (fs.existsSync(bin)) { return bin; }     // USED AS-IS, NEVER REBUILT, NEVER CHECKED

so the verdict is decided by a BINARY OUTSIDE THE REPOSITORY -- and BOTH
`references/` AND `bin/bend` ARE `.gitignore`d (`.gitignore:2` and `:5`), so the
kernel's SOURCE is outside it too.  MEASURED 2026-10-22
(`.agents/slop/verdict-hunt2/REPORT.md` §3 M11): with `HOME` pointed at a
temporary directory holding a TWO-LINE SHELL SCRIPT where the kernel goes, the
verdict FLIPPED BOTH WAYS with NOTHING CHANGED IN THE REPOSITORY.

SO THE FIX IS THE OVERRIDE THE COMPILER ALREADY HONOURS -- `kernel_bin()` reads
`process.env.BENDTT` FIRST and returns it UNCONDITIONALLY -- AND THIS GATE USES
IT: it BUILDS the kernel from `references/bend/bend2/bendtt.lean` into a
directory IT OWNS, PINS the binary's sha256, and RUNS the lanes with `BENDTT=`
set to that pinned path.  A kernel whose sha256 is not the pin is REFUSED (3),
NOT RUN.

THE THREE THINGS THE LANE'S ANSWER MUST NOT DEPEND ON, AND HOW EACH IS CUT.

  `~/.bend/bendtt/`   `BENDTT=` is set, and `kernel_bin()` returns it before it
                      looks at the cache.  MEASURED by plant case HOME-POISON:
                      a treated kernel planted in a private HOME's cache does
                      not move the verdict by one byte.
  `~/.bend/check.json` the compiler's daily version check.  `BEND_NO_TELEMETRY=1`
                      skips it entirely (`main.ts:186-188`) and the lane's HOME
                      is a PRIVATE EMPTY DIRECTORY, so the file is neither read
                      nor written.  MEASURED: its mtime is unchanged after a
                      full run.
  `~/.elan`           the Lean toolchain is a BUILD INPUT and nothing else: the
                      gate records the Lean version it used, refuses a version
                      that is not the pinned one, and -- the part that matters --
                      the toolchain can only reach the verdict through a binary
                      whose sha256 does not match the pin, which is REFUSED (3).
  the network         `BEND_NO_TELEMETRY=1` and a private HOME.  The gate runs
                      no command that fetches anything: `lean`, `leanc` and
                      `bend` are local.

THE FIVE VERDICTS, AS EXITS (`gates/gatekit.py`: PASS 0, FAIL 1, REFUSED 3,
SKIP 4, DEAD 5).  `AGENTS.md`: "SKIP IS NOT PASS".

  PASS 0     every file in the population got BOTH lanes' answers, no file
             DISAGREED, and at least one file REACHED THE KERNEL and passed --
             without that last clause a population of refusals would be a green
             that measured nothing.
  FAIL 1     at least one file DISAGREED: the two lanes gave different
             answers, or the same file was VERIFIED by one and refused by the
             other.  This is the whole point of the lane: `--check-only` is the
             unverified checker and `--verdict` is the verified one.
  REFUSED 3  a PRECONDITION was absent: no `bin/bend`; no `lean`/`leanc`; the
             kernel did not build; a PIN did not match; the population is empty;
             or no file reached the kernel at all.
  DEAD 5     a lane RAN and emitted NOTHING, after its retries.  Not a FAIL: the
             instrument did not answer.
  SKIP 4     NOT PRODUCED BY THIS GATE.  Named so the vocabulary is complete and
             so a reader who sees 4 somewhere knows it came from elsewhere
             (`checks/e2e.py`).

THE POPULATION IS DISCOVERED, NOT LISTED (`AGENTS.md` doctrine 1).  The rule, in
one sentence: a port `.bend` file is a PROOF ROOT when nothing in the port
imports it AND its transitive import closure contains a file that DECLARES A
LAW; the population is the union of those closures.  The import edges are the
files' own `import` lines and the laws are bend2's own `law` keyword
(`references/bend/bend2/bend.ts:50`), so both halves are read from the source and
neither is a hand list.  MEASURED on this revision: TWO roots, and the closure
of the proof aggregate is the seven files this gate reports.

WHAT IS NOT THE GATE'S FAILURE.  A proof file that REFUSES UNDER BOTH LANES is
not a disagreement: it is the port's proof being incomplete (`Error: N TODOs
found.`), or the port relying on foreign code (`Error: N defs rely on unsafe or
foreign code:`).  Those are REPORTED as their own class -- `AGREE-INCOMPLETE`
and `AGREE-FOREIGN` -- and they do not turn the gate red.  A gate that failed on
the port's incompleteness would be red for a reason that is not about the
kernel, and would be red tomorrow for the same reason.

THE PLANT IS THE PROOF THAT THIS GATE CAN GO RED.  `--plant` runs five cases on
COPIES; the working tree is never edited.  A row that cannot go red is worse
than no row, so the plant's own cases are the deliverable's proof.
"""
import argparse
import hashlib
import json
import os
import re
import resource
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get("TINYGRAD_ROOT", HERE.parent)).resolve()
sys.path.insert(0, str(HERE))

import gatekit  # noqa: E402
from bendlock import bend_lock  # noqa: E402
from gatekit import (  # noqa: E402
    BEND,
    BEND_ABSENT,
    DEAD,
    FAIL,
    PASS,
    REFUSED,
    SKIP,
    VERDICT,
    _said,
    verdict_of,
)

# --------------------------------------------------------------------------- THE PINS
#
# FOUR NUMBERS AND A VERSION, AND EACH ONE NAMES A THING THAT EXISTS:
#
#   PIN_LEAN_VERSION     the Lean the compiler's own `kernel_bin()` demands
#                        (`references/bend/bend2/safe.ts`: `LEAN_VERSION`), and
#                        the one the pinned kernel was built with.
#   PIN_SRC_SHA256       `references/bend/bend2/bendtt.lean` -- the SOURCE the
#                        pinned kernel was built from.  `references/` is
#                        `.gitignore`d, so this number is the only thing that
#                        ties the kernel to a fixed body of text.
#   PIN_KERNEL_SHA256    the BUILT BINARY.  This is the load-bearing pin: it is
#                        what the gate checks BEFORE it executes anything, and
#                        it is what makes the lane's answer a function of this
#                        repository rather than of a cache in somebody's home.
#   PIN_KERNEL_BYTES     the size, because a sha256 and a size disagreeing is a
#                        signal and a sha256 alone is not.
#
# A PIN IN A COMMENT IS A PIN THAT CANNOT FAIL (`gates/gatekit.py`'s
# `oracle_drift`), so these are CODE.  `--write-pins` prints the replacement
# constants for the source as it stands, and they move in the SAME commit as the
# source they describe.
PIN_LEAN_VERSION = "4.34.0"
PIN_SRC_SHA256 = "cc78aa9ff3491ff1b788797bdcab4cb98107dcb1730ed99834f6933b11d88335"
PIN_KERNEL_SHA256 = "7e7a4899bfd6b793fae3253cfee1f297ae9239f0e858795985dab6a5e990905b"
PIN_KERNEL_BYTES = 3307264

# THE COMPILER'S TWO VERDICT TOKENS, read from the compiler's own source
# (`references/bend/bend2/main.ts:81` and `:83`) rather than re-typed from
# memory, because a token this file gets wrong is a verdict it cannot read.
PASS_TOKEN = "ALL PROOFS CHECK"
FAIL_TOKEN = "SOME PROOFS FAIL"

# THE PORT'S ROOT, and the two file classes this gate's population is made of.
PORT = "tinybendygrad"

# A LANE THAT PRODUCED NOTHING AT ALL IS THE COMPILER'S MEASURED STACK FLAKE
# (about 1 run in 20, `gates/gatekit.py`'s `_lane`), so it is retried.  The
# bound is `gatekit.TRIES`, not a number of its own.
TRIES = gatekit.TRIES

# A LANE THAT HANGS IS A LANE THAT MEASURED NOTHING, and a gate that waits
# forever is a gate nobody can read.  MEASURED on this revision, three runs of
# each of the fourteen lanes: the slowest is 0.17 s and the fastest is 0.08 s,
# so this is a hundred times the observed worst case.  (The FIRST run under a
# FRESH HOME was 1.20 s, because `bun` re-transpiles into the private HOME's
# cache -- so the bound covers that too.)
LANE_TIMEOUT_S = 120

# THE CLASSES A LANE'S ANSWER CAN TAKE.  `VERIFIED` is the only one that means
# the kernel was consulted and agreed.
C_VERIFIED = "VERIFIED"
C_INCOMPLETE = "INCOMPLETE"
C_FOREIGN = "FOREIGN"
C_MISMATCH = "MISMATCH"
C_FINDING = "FINDING"
C_NO_MEASUREMENT = "NO-MEASUREMENT"


# --------------------------------------------------------------------------- the population
IMPORT_RE = re.compile(r"^\s*import\s+(\S+)")
LAW_RE = re.compile(r"^\s*law\s", re.M)
PROOF_DEF_RE = re.compile(r"->\s*\{.*\}\s*:")


def port_files(root):
    """Every `.bend` file under the port.  A DIRECTORY WALK, because `glob` returns `[]`
    when the files are on disk and it did."""
    port = root / PORT
    if not port.is_dir():
        return []
    return sorted(p.resolve() for p in port.rglob("*.bend") if p.is_file())


def imports_of(path):
    """The files this one imports.  bend2 resolves `import ./x.bend` relative to the
    IMPORTING FILE's own directory (`gates/mixin-op-plant.py`'s header), so the
    edges are resolved the same way."""
    out = []
    for line in path.read_text(errors="replace").splitlines():
        m = IMPORT_RE.match(line)
        if m and m.group(1).endswith(".bend"):
            out.append((path.parent / m.group(1)).resolve())
    return out


def declares_a_law(path):
    """Does this file declare a law?  bend2's own `law` keyword
    (`references/bend/bend2/bend.ts:50`) OR a def whose type is a proof."""
    text = path.read_text(errors="replace")
    return bool(LAW_RE.search(text)) or bool(PROOF_DEF_RE.search(text))


def closure(path, graph, known):
    """The transitive import closure of `path`, over the files that exist."""
    seen, stack = set(), [path]
    while stack:
        q = stack.pop()
        if q in seen or q not in known:
            continue
        seen.add(q)
        stack.extend(graph.get(q, ()))
    return seen


def proof_population(root):
    """`(population, roots, law_files)`.

    THE RULE, in one sentence: a port `.bend` file is a PROOF ROOT when NO other
    port `.bend` file imports it AND its transitive import closure contains a
    file that DECLARES A LAW; the population is the union of those closures.

    BOTH HALVES ARE READ FROM THE SOURCE.  The import edges are the files' own
    `import` lines and the laws are bend2's own `law` keyword, so neither is a
    hand list and neither can rot without the population moving with it.

    MEASURED on this revision: TWO roots -- `LAWS/PROOF-ALL.bend` (the aggregate
    the port itself calls "the aggregate gate") and
    `runtime/autogen/libclang.bend` (the FFI file, which declares 335 laws of its
    own and is imported by nothing).  The aggregate's closure is the six proof
    files and libclang's is itself, so the population is SEVEN files.
    """
    files = port_files(root)
    known = set(files)
    graph = {p: imports_of(p) for p in known}
    law = {p for p in known if declares_a_law(p)}
    imported = set()
    for deps in graph.values():
        imported.update(deps)
    roots = sorted(p for p in known if p not in imported and (closure(p, graph, known) & law))
    population = set()
    for r in roots:
        population |= closure(r, graph, known)
    return sorted(population), roots, sorted(law)


# --------------------------------------------------------------------------- the kernel
def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def compiler_cache_key(src_text, lean_version=PIN_LEAN_VERSION):
    """The cache key `kernel_bin()` computes: sha256(LEAN_VERSION + "\\0" + text)[:16].

    It is over the SOURCE TEXT, not over the source's sha256, so it cannot be
    derived from the pin -- it is computed here only to REPORT which directory
    the compiler's OWN default path would have used, so a reader can see that
    the gate's directory and the compiler's directory are different places.
    """
    h = hashlib.sha256()
    h.update(lean_version.encode())
    h.update(b"\0")
    h.update(src_text.encode())
    return h.hexdigest()[:16]


def default_toolchain_dir():
    """`~/.elan/toolchains/leanprover--lean4---v<version>/bin` -- the directory
    `kernel_bin()` itself looks in.  It is a BUILD INPUT and nothing else; see
    the header's "the three things the lane's answer must not depend on"."""
    home = Path(os.path.expanduser("~"))
    return home / ".elan" / "toolchains" / ("leanprover--lean4---v" + PIN_LEAN_VERSION) / "bin"


def resolve_tool(name, toolchain):
    """The toolchain's copy if it is there, else the one on PATH, else None."""
    p = Path(toolchain) / name
    if p.exists():
        return str(p)
    return shutil.which(name)


def run_timed(argv, cwd):
    """`(rc, stdout, stderr, seconds, peak_rss_bytes)`.

    THE PEAK RSS IS MEASURED, NOT GUESSED, because the Lean build is the
    heaviest thing in this tree and the tree's rule is a SUM over concurrently
    running children.  `/usr/bin/time -l -o FILE` writes the child's OWN stdout
    and stderr through and the report to FILE, so the tool's diagnostics and the
    measurement stay separable.  Without it the peak falls back to
    `getrusage(RUSAGE_CHILDREN)`, which is the maximum over ALL children waited
    for and is therefore an UPPER BOUND on this one.
    """
    report = Path(tempfile.mkdtemp(prefix="verdictlane-time-")) / "report"
    has_time = Path("/usr/bin/time").exists()
    wrapped = (["/usr/bin/time", "-o", str(report), "-l"] + argv) if has_time else list(argv)
    t0 = time.time()
    proc = subprocess.run(wrapped, capture_output=True, text=True, cwd=str(cwd))
    elapsed = time.time() - t0
    peak = 0
    if has_time and report.exists():
        for line in report.read_text().splitlines():
            m = re.match(r"\s*(\d+)\s+maximum resident set size", line)
            if m:
                peak = int(m.group(1))
    if not peak:
        # WITHOUT /usr/bin/time THIS IS AN UPPER BOUND ON THE CHILDREN WAITED FOR,
        # NOT THIS CHILD'S PEAK: `ru_maxrss` for children is the maximum over all
        # of them.  It is reported as such rather than as a measurement.
        peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss * 1024
    shutil.rmtree(report.parent, ignore_errors=True)
    return proc.returncode, proc.stdout, proc.stderr, elapsed, peak


def build_kernel(src, dest, toolchain):
    """`(ok, receipt)`.  The build `kernel_bin()` performs, reproduced.

    THE THREE COMMANDS, in this order, in `dest`, with `cwd` set to `dest` --
    MEASURED against `safe.ts`'s own `kernel_bin()`:

        lean  -c bendtt.c bendtt.lean
        leanc -O3 -DNDEBUG bendtt.c -o bendtt

    and the version gate BEFORE them:

        lean --version      must be the pinned version

    `dest` is a directory THIS GATE OWNS.  It is never `~/.bend/`, which is the
    compiler's cache and the place the prior hunt's treated kernel lived.
    """
    receipt = {"source": str(src), "dest": str(dest), "built": False}
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    lean = resolve_tool("lean", toolchain)
    leanc = resolve_tool("leanc", toolchain)
    if lean is None or leanc is None:
        receipt["why"] = (f"no Lean toolchain: `lean` and `leanc` are not in {toolchain} "
                          f"and not on PATH")
        return False, receipt
    receipt["lean"] = lean
    receipt["leanc"] = leanc
    rc, out, err, secs, peak = run_timed([lean, "--version"], dest)
    version = ""
    m = re.search(r"^Lean \(version ([^,\s)]+)", out, re.M)
    if m:
        version = m.group(1)
    receipt["lean_version"] = version
    receipt["lean_version_seconds"] = round(secs, 3)
    if rc != 0 or not version:
        receipt["why"] = f"`lean --version` failed (rc={rc}): {_said(err)[:200]}"
        return False, receipt
    if version != PIN_LEAN_VERSION:
        receipt["why"] = (f"the Lean version is {version!r} and the pin is "
                          f"{PIN_LEAN_VERSION!r}: a different toolchain must not be "
                          f"accepted silently")
        return False, receipt
    shutil.copyfile(src, dest / "bendtt.lean")
    steps = [("lean -c", [lean, "-c", "bendtt.c", "bendtt.lean"]),
             ("leanc -O3", [leanc, "-O3", "-DNDEBUG", "bendtt.c", "-o", "bendtt"])]
    timings = {}
    peaks = {}
    for label, argv in steps:
        rc, out, err, secs, peak = run_timed(argv, dest)
        timings[label] = round(secs, 3)
        peaks[label] = peak
        if rc != 0:
            receipt["why"] = (f"`{label}` failed (rc={rc}): "
                              f"{(_said(err) or out.strip())[:200]}")
            receipt["build_seconds"] = timings
            receipt["build_peak_rss_bytes"] = peaks
            return False, receipt
    receipt["build_seconds"] = timings
    receipt["build_peak_rss_bytes"] = peaks
    receipt["build_seconds_total"] = round(sum(timings.values()), 3)
    receipt["build_peak_rss_bytes_max"] = max(peaks.values())
    receipt["built"] = True
    # THE BUILD'S OWN RECEIPT, BESIDE THE BINARY.  A CACHED KERNEL IS REPORTED
    # WITH THE LEAN VERSION THAT BUILT IT, so a run that did NOT build anything
    # still says which toolchain the pinned binary came from.
    (dest / "build.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return True, receipt


def resolve_kernel(args, src):
    """`(kernel_path, receipt)`, or `(None, receipt)` with the reason in the receipt.

    THE ORDER IS THE POINT.  The kernel is BUILT FIRST and PINNED SECOND, so
    the thing the gate checks is the thing the gate made, and a kernel that
    cannot be made is a REFUSAL rather than a run against somebody else's
    cache.
    """
    receipt = {}
    if args.kernel:
        kernel = Path(args.kernel)
        if not kernel.is_file():
            receipt["why"] = f"the kernel {kernel} is not there"
            return None, receipt
        receipt["built"] = False
        receipt["kernel_path"] = str(kernel)
    else:
        src_sha = sha256_file(src)
        dest = Path(args.kernel_dir) / src_sha[:16]
        kernel = dest / "bendtt"
        if kernel.is_file() and not args.rebuild:
            receipt["built"] = False
            receipt["cached"] = True
            receipt["kernel_path"] = str(kernel)
            # THE CACHED KERNEL'S OWN RECEIPT, so a run that built nothing still
            # says WHICH LEAN BUILT THE PINNED BINARY.
            sidecar = dest / "build.json"
            if sidecar.is_file():
                try:
                    receipt["build"] = json.loads(sidecar.read_text())
                    receipt["lean_version"] = receipt["build"].get("lean_version")
                except (OSError, ValueError):
                    pass
        else:
            ok, built = build_kernel(src, dest, Path(args.toolchain_dir))
            receipt.update(built)
            if not ok:
                return None, receipt
            receipt["kernel_path"] = str(kernel)
    receipt["kernel_sha256"] = sha256_file(kernel)
    receipt["kernel_bytes"] = kernel.stat().st_size
    return kernel, receipt


def check_pins(kernel, receipt, src):
    """`(ok, why)`.  THE GATE'S LOAD-BEARING CHECK.

    Three comparisons and a version, and the order is the order of how much a
    mismatch tells the reader:

      the SOURCE   did the text the kernel was built from change?
      the BINARY   is the binary the gate is about to EXECUTE the pinned one?
      the SIZE     does it agree with the pin about its own size?

    A mismatch is a REFUSAL (3), NOT A RUN: the gate does not execute a binary
    whose identity it cannot vouch for, and it says which number moved.
    """
    src_sha = sha256_file(src)
    receipt["source_sha256"] = src_sha
    receipt["source_bytes"] = src.stat().st_size
    receipt["pinned_source_sha256"] = PIN_SRC_SHA256
    receipt["pinned_kernel_sha256"] = PIN_KERNEL_SHA256
    receipt["pinned_kernel_bytes"] = PIN_KERNEL_BYTES
    if src_sha != PIN_SRC_SHA256:
        return False, (f"the kernel source moved: {src.name} is {src_sha} and the pin is "
                       f"{PIN_SRC_SHA256}. The source lives in a GITIGNORED clone "
                       f"(references/, .gitignore:2), so a pin is the only thing that "
                       f"names it. Re-take the pins with --write-pins in the SAME commit.")
    if receipt["kernel_sha256"] != PIN_KERNEL_SHA256:
        return False, (f"the kernel is not the pinned one: {receipt['kernel_sha256']} != "
                       f"{PIN_KERNEL_SHA256}. It was NOT run.")
    if receipt["kernel_bytes"] != PIN_KERNEL_BYTES:
        return False, (f"the kernel is {receipt['kernel_bytes']} bytes and the pin says "
                       f"{PIN_KERNEL_BYTES}. It was NOT run.")
    return True, ""


# --------------------------------------------------------------------------- the lanes
class Lane:
    """ONE COMPILER, ONE KERNEL, ONE HOME.

    THE HOME IS PRIVATE AND EMPTY.  It is created by the gate and it holds
    nothing, so the child cannot see `~/.bend/bendtt/` (the cached kernel),
    `~/.bend/check.json` (the telemetry cache) or `~/.elan` (the toolchain).
    The kernel is handed over by an ABSOLUTE PATH in `BENDTT`, which
    `kernel_bin()` returns before it looks at anything else.
    """

    def __init__(self, kernel, home, compiler=BEND, tries=TRIES):
        self.kernel = Path(kernel)
        self.home = Path(home)
        self.compiler = Path(compiler)
        self.tries = tries

    def env(self):
        env = dict(os.environ)
        env["BENDTT"] = str(self.kernel)
        env["BEND_NO_TELEMETRY"] = "1"
        env["HOME"] = str(self.home)
        return env

    def run(self, path, mode):
        """`(rc, stdout, stderr)` for one lane, after the flake retries."""
        last = (None, "", "")
        for _ in range(self.tries):
            try:
                proc = subprocess.run([str(self.compiler), str(path), mode],
                                      capture_output=True, text=True, env=self.env(),
                                      cwd=str(ROOT), timeout=LANE_TIMEOUT_S)
            except subprocess.TimeoutExpired:
                last = (None, "", f"the lane timed out after {LANE_TIMEOUT_S}s")
                continue
            out, err = proc.stdout or "", proc.stderr or ""
            last = (proc.returncode, out, err)
            # THE FLAKE IS "NOTHING AT ALL", not "a non-zero exit": a type error
            # exits non-zero and says so, and retrying it 25 times would waste
            # 25 runs of a 1.4 GB process to learn the same thing.
            if out.strip() or _said(err):
                break
        return last


def classify(rc, out, err):
    """The class of ONE lane's answer.  Read STDOUT FIRST, because that is where
    the compiler puts its success token (`main.ts:820` writes `PASS` to fd 1 and
    `FAIL` to fd 2), and because the update notice and the kernel's own output
    are noise on stderr."""
    lines_out = [l for l in out.splitlines() if l.strip()]
    said = _said(err, lines=8)
    if lines_out and lines_out[0].strip() == PASS_TOKEN and rc == 0:
        return C_VERIFIED
    if not lines_out and not said:
        return C_NO_MEASUREMENT
    if "TODOs found" in said:
        return C_INCOMPLETE
    if "rely on unsafe or foreign code" in said:
        return C_FOREIGN
    if "mismatch between the TypeScript implementation" in said:
        return C_MISMATCH
    return C_FINDING


def agreement(check_cls, verdict_cls):
    """`AGREE-<class>` when the two lanes said the same thing, else `DISAGREE`."""
    if check_cls == verdict_cls:
        return f"AGREE-{check_cls}"
    return "DISAGREE"


def evaluate(lane, files):
    """The per-file rows.  One row per file, two lanes per file."""
    rows = []
    for f in files:
        crc, cout, cerr = lane.run(f, "--check-only")
        vrc, vout, verr = lane.run(f, "--verdict")
        cc, vc = classify(crc, cout, cerr), classify(vrc, vout, verr)
        rows.append({
            "file": str(Path(f).relative_to(ROOT)) if str(f).startswith(str(ROOT)) else str(f),
            "check": cc,
            "verdict": vc,
            "agreement": agreement(cc, vc),
            "check_rc": crc,
            "verdict_rc": vrc,
            "check_said": _said(cerr, lines=3),
            "verdict_said": _said(verr, lines=3),
        })
    return rows


def decide(rows):
    """`(code, why)` -- the gate's OWN verdict, by the five-verdict vocabulary."""
    if not rows:
        return REFUSED, "the population is empty: no proof file was found to judge"
    if any(r["agreement"] == "DISAGREE" for r in rows):
        bad = [r["file"] for r in rows if r["agreement"] == "DISAGREE"]
        return FAIL, ("the two lanes disagree on " + ", ".join(bad)
                      + " -- --check-only is the unverified checker and --verdict is the "
                        "verified one")
    if any(C_NO_MEASUREMENT in (r["check"], r["verdict"]) for r in rows):
        bad = [r["file"] for r in rows if C_NO_MEASUREMENT in (r["check"], r["verdict"])]
        return DEAD, ("a lane ran and emitted nothing on " + ", ".join(bad)
                      + " -- that is DEAD, not a FAIL")
    if not any(r["agreement"] == f"AGREE-{C_VERIFIED}" for r in rows):
        return REFUSED, ("no file in the population reached the kernel, so the kernel was "
                         "never exercised: this would be a green that measured nothing")
    return PASS, ""


def row_text(r):
    return (f"{r['file']}\tcheck={r['check']}\tverdict={r['verdict']}"
            f"\tagreement={r['agreement']}\tcheck-rc={r['check_rc']}"
            f"\tverdict-rc={r['verdict_rc']}")


# --------------------------------------------------------------------------- the run
def git_head():
    """The HEAD this run measured.  READ WITH `env -u GIT_INDEX_FILE`: the tree's
    index is ARMED (`checks/index-arm-gate.py`), and an armed index answers a
    `git` question about the INDEX rather than about the commit."""
    try:
        r = subprocess.run(["env", "-u", "GIT_INDEX_FILE", "git", "rev-parse", "HEAD"],
                           capture_output=True, text=True, cwd=str(ROOT))
        return r.stdout.strip() if r.returncode == 0 else "unknown"
    except OSError:
        return "unknown"


def write_artifacts(art, rows, receipt, code):
    """The artifacts, STAGED and PROMOTED (`gates/gatekit.py`'s convention: a
    `.tmp.` name until the run is good)."""
    art = Path(art)
    art.mkdir(parents=True, exist_ok=True)
    tmp = art / ".tmp.rows"
    tmp.write_text("\n".join(row_text(r) for r in rows) + "\n")
    tmp.replace(art / "rows")
    (art / "kernel.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    (art / "verdict.rc").write_text(f"{code}\n")


def clear_artifacts(art):
    """The gate's OWN artifacts, removed, BEFORE anything can fail.

    `gates/gatekit.py`'s rule is "a red run leaves an EMPTY directory, and an
    empty directory cannot be diffed by accident".  ITS directory is
    `gates/artifacts/<gate>/`, which the gate owns outright, so it can empty the
    whole thing.

    **THIS GATE'S ARTIFACT DIRECTORY IS CHOSEN BY `--artifacts`, SO IT MAY NOT
    BE THE GATE'S ALONE.**  MEASURED 2026-10-23: a run with
    `--artifacts .agents/slop/verdictlane` DELETED THE REPORT THAT WAS SITTING
    BESIDE THE ROWS, because the clear removed every file in the directory.  A
    clear that can delete a file the gate did not write is a clear that can
    delete somebody's work -- so this one removes ONLY THE THREE FILES THE GATE
    WRITES, and leaves everything else alone.

    The stale-rows hazard the rule exists for is still closed: `rows` is one of
    the three, so a red run leaves no table of the last green run.
    """
    art = Path(art)
    art.mkdir(parents=True, exist_ok=True)
    for name in ("rows", "kernel.json", "verdict.rc"):
        (art / name).unlink(missing_ok=True)


def gate_main(args):
    src = Path(args.bend_dir) / "bendtt.lean"
    art = Path(args.artifacts)
    # FIRST, AND BEFORE ANY CHECK CAN FAIL: the output directory is EMPTIED
    # (`gates/gatekit.py`'s rule, and the reason for it).
    clear_artifacts(art)
    receipt = {}
    if not src.is_file():
        return refuse(f"the kernel source {src} is not there. `references/` is GITIGNORED "
                      f"(.gitignore:2), so the compiler must be fetched before this gate can "
                      f"say anything.", art, receipt)
    if BEND == BEND_ABSENT or not Path(BEND).exists():
        return refuse("the toolchain is absent: there is no `bin/bend` in this tree",
                      art, receipt)

    kernel, built = resolve_kernel(args, src)
    receipt.update(built)
    if kernel is None:
        return refuse(built.get("why", "the kernel did not build"), art, receipt)
    ok, why = check_pins(kernel, receipt, src)
    receipt["pin_ok"] = ok
    if not ok:
        return refuse(why, art, receipt)

    population, roots, law = proof_population(ROOT)
    receipt["population"] = [str(Path(p).relative_to(ROOT)) for p in population]
    receipt["roots"] = [str(Path(p).relative_to(ROOT)) for p in roots]
    receipt["law_files"] = [str(Path(p).relative_to(ROOT)) for p in law]
    receipt["head"] = git_head()
    receipt["timestamp_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    receipt["home"] = args.home
    if not population:
        return refuse("the population is empty: no proof file was found to judge", art, receipt)

    print(f"verdict-lane-gate: the kernel is {receipt['kernel_sha256']} "
          f"({receipt['kernel_bytes']} bytes), built={receipt.get('built')}, "
          f"lean={receipt.get('lean_version')}, source={receipt['source_sha256'][:16]}")
    print(f"verdict-lane-gate: the population is {len(population)} file(s), "
          f"from {len(roots)} discovered root(s): "
          f"{', '.join(str(Path(r).relative_to(ROOT)) for r in roots)}")

    home = Path(args.home)
    home.mkdir(parents=True, exist_ok=True)
    lane = Lane(kernel, home)
    with bend_lock():
        rows = evaluate(lane, population)
    code, why = decide(rows)
    for r in rows:
        print("  " + row_text(r))
    receipt["verdict"] = VERDICT.get(code, str(code))
    write_artifacts(art, rows, receipt, code)
    if code == PASS:
        print(f"verdict-lane-gate: PASS -- {len(rows)} file(s) judged, no disagreement, and "
              f"{sum(1 for r in rows if r['agreement'] == f'AGREE-{C_VERIFIED}')} of them reached "
              f"the kernel")
        print(f"verdict-lane-gate: the five verdicts are PASS {PASS}, FAIL {FAIL}, "
              f"REFUSED {REFUSED}, SKIP {SKIP} (not produced by this gate), DEAD {DEAD}")
        return PASS
    print(f"verdict-lane-gate: {verdict_of(code)}: {why}", file=sys.stderr)
    return code


def refuse(why, art=None, receipt=None):
    """A REFUSAL, AND NOT A VERDICT.

    The receipt is still written when there is one, because a refusal a reader
    cannot inspect is a refusal nobody can test (`checks/devpin.py`'s measured
    reason), and the exit status is 3 -- `REFUSED`, which is NOT `FAIL` and NOT
    `PASS`."""
    print(f"== REFUSED, NOT A VERDICT: verdict-lane-gate: {why}", file=sys.stderr)
    if art is not None:
        try:
            art = Path(art)
            art.mkdir(parents=True, exist_ok=True)
            if receipt:
                receipt["verdict"] = "REFUSED"
                (art / "kernel.json").write_text(
                    json.dumps(receipt, indent=2, sort_keys=True) + "\n")
            (art / "verdict.rc").write_text(f"{REFUSED}\n")
        except OSError:
            pass
    return REFUSED


# --------------------------------------------------------------------------- the plant
PLANT_MARKER = "powf"


def treated_kernel(path, marker=None):
    """A TREATED KERNEL: a two-line shell script where the kernel goes.

    MEASURED 2026-10-22 (`.agents/slop/verdict-hunt2/REPORT.md` §3 M11): a script
    of this shape at the kernel's path flips the verdict BOTH WAYS with nothing
    changed in the repository.  The same shape is the plant here, so the gate's
    ability to notice it is MEASURED rather than asserted.

    `marker` makes it TARGETED: it fails iff the elaboration mentions that name,
    so the disagreement is localised to the files that carry it.  With no marker
    it fails everything, which is the blanket shape.
    """
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    if marker:
        body = (f"#!/bin/sh\n"
                f"if grep -q '{marker}' \"$1\"; then echo '{FAIL_TOKEN}'; exit 1; fi\n"
                f"echo '{PASS_TOKEN}'\n")
    else:
        body = f"#!/bin/sh\necho '{FAIL_TOKEN}'\nexit 1\n"
    p.write_text(body)
    p.chmod(0o755)
    return p


def scratch_family(dest, files):
    """The proof family, COPIED, preserving the layout its `import` lines need."""
    dest = Path(dest)
    for f in files:
        rel = Path(f).relative_to(ROOT / PORT)
        t = dest / rel
        t.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(f, t)
    return dest


def plant_main(args):
    """SEVEN CASES, ON COPIES.  The working tree is never edited.

    A plant that reads `git show HEAD:` plants nothing the moment HEAD carries
    the defect, so every case here works on COPIES and on the working tree's
    bytes.

    THE PLANT'S OWN ROWS ARE REMOVED FIRST, so a refused plant leaves no table
    of the last green one -- the same rule the gate follows for its own three
    artifacts.
    """
    src = Path(args.bend_dir) / "bendtt.lean"
    (Path(args.artifacts) / "plant.rows").unlink(missing_ok=True)
    if not src.is_file():
        return refuse(f"the kernel source {src} is not there")
    if BEND == BEND_ABSENT or not Path(BEND).exists():
        return refuse("the toolchain is absent: there is no `bin/bend` in this tree")
    kernel, receipt = resolve_kernel(args, src)
    if kernel is None:
        return refuse(receipt.get("why", "the kernel did not build"))
    ok, why = check_pins(kernel, receipt, src)
    if not ok:
        return refuse(why)

    population, roots, _ = proof_population(ROOT)
    work = Path(tempfile.mkdtemp(prefix="verdictlane-plant-"))
    home = work / "home"
    home.mkdir(parents=True, exist_ok=True)
    results = []
    rows_out = []

    def record(name, want, got, why, ok=None):
        if ok is None:
            ok = (want == got)
        results.append((name, want, got, why, ok))
        rows_out.append(f"{name}\twant={want}\tgot={got}\t{'OK' if ok else 'NOT AS EXPECTED'}"
                        f"\t{why}")

    # --- THE CONTROL: the un-planted gate, on the real tree.
    lane = Lane(kernel, home)
    with bend_lock():
        base_rows = evaluate(lane, population)
    base_code, _ = decide(base_rows)
    record("CONTROL-REAL-TREE", VERDICT[PASS], VERDICT.get(base_code, str(base_code)),
           "the gate on the tree as it stands")

    # --- PLANT 1: a TARGETED kernel.  It fails on the files whose elaboration
    # mentions PLANT_MARKER, so the disagreement is LOCALISED.
    targeted = treated_kernel(work / "treated-targeted" / "bendtt", PLANT_MARKER)
    lane = Lane(targeted, home)
    with bend_lock():
        t_rows = evaluate(lane, population)
    t_code, _ = decide(t_rows)
    disagree = sorted(r["file"] for r in t_rows if r["agreement"] == "DISAGREE")
    agree = sorted(r["file"] for r in t_rows if r["agreement"] == f"AGREE-{C_VERIFIED}")
    # THE MARKER IS IN `LAWS/alu.bend`, AND THE AGGREGATE `LAWS/PROOF-ALL.bend`
    # IMPORTS IT, SO BOTH MUST DISAGREE -- AND `LAWS/spec.bend`, WHICH DOES NOT
    # CARRY THE MARKER, MUST NOT.  THE SET IS THE CLAIM; THE VERDICT ALONE IS
    # NOT, BECAUSE A BLANKET KERNEL WOULD ALSO PRODUCE `FAIL`.
    #
    # AND THE SET IS AN ANCHOR, NOT A CONSTANT: if the port's proof family
    # moves, this case reports NOT AS EXPECTED and says so -- which is the
    # right outcome, because a plant that silently re-anchored itself would
    # stop proving anything (`gates/mixin-op-plant.py`: "the anchor is not in
    # the file as it stands ... re-anchored -- NOT that it should fall back to
    # reading git").
    want_disagree = {"tinybendygrad/LAWS/alu.bend", "tinybendygrad/LAWS/PROOF-ALL.bend"}
    record("PLANT-TARGETED-KERNEL", VERDICT[FAIL], VERDICT.get(t_code, str(t_code)),
           f"disagree={disagree} agree-verified={agree}",
           ok=(t_code == FAIL and set(disagree) == want_disagree
               and agree == ["tinybendygrad/LAWS/spec.bend"]))
    for r in t_rows:
        rows_out.append(f"PLANT-TARGETED-KERNEL\t{row_text(r)}")

    # --- PLANT 2: a BLANKET kernel.  Everything the kernel would pass now fails.
    blanket = treated_kernel(work / "treated-blanket" / "bendtt", None)
    lane = Lane(blanket, home)
    with bend_lock():
        b_rows = evaluate(lane, population)
    b_code, _ = decide(b_rows)
    b_disagree = sum(1 for r in b_rows if r["agreement"] == "DISAGREE")
    record("PLANT-BLANKET-KERNEL", VERDICT[FAIL], VERDICT.get(b_code, str(b_code)),
           f"disagree={b_disagree} of {len(b_rows)}",
           ok=(b_code == FAIL and b_disagree == 3))

    # --- PLANT 3: the PIN.  A kernel that is not the pinned one must be
    # REFUSED, NOT RUN.  This is the gate's OWN `check_pins`, on the treated
    # kernel, so it exercises the function the real run uses.
    p_receipt = {"kernel_sha256": sha256_file(blanket),
                 "kernel_bytes": blanket.stat().st_size}
    p_ok, p_why = check_pins(blanket, p_receipt, src)
    p_code = PASS if p_ok else REFUSED
    record("PLANT-PIN-MISMATCH", VERDICT[REFUSED], VERDICT.get(p_code, str(p_code)), p_why)

    # --- PLANT 4: a compiler that says NOTHING.  A lane that ran and emitted
    # nothing is DEAD, and DEAD is not PASS and is not FAIL -- it is the fifth
    # verdict, and this is the case that proves the gate can say it.  The stub
    # is a compiler that exits 0 without writing a byte, which is the shape of
    # the compiler's measured stack flake.
    stub = work / "silent-compiler"
    stub.parent.mkdir(parents=True, exist_ok=True)
    stub.write_text("#!/bin/sh\nexit 0\n")
    stub.chmod(0o755)
    lane = Lane(kernel, home, compiler=stub, tries=3)
    with bend_lock():
        d_rows = evaluate(lane, population[:1])
    d_code, d_why = decide(d_rows)
    record("PLANT-SILENT-COMPILER", VERDICT[DEAD], VERDICT.get(d_code, str(d_code)), d_why)

    # --- PLANT 4: the HOME.  A treated kernel in the compiler's OWN cache
    # directory, inside a private HOME, must not move the verdict: the gate
    # hands the kernel over by absolute path, so the cache is never consulted.
    poisoned = work / "poisoned-home"
    cache = poisoned / ".bend" / "bendtt" / compiler_cache_key(src.read_text())
    cache.mkdir(parents=True, exist_ok=True)
    treated_kernel(cache / "bendtt", None)
    (poisoned / ".bend" / "check.json").write_text(
        json.dumps({"t": int(time.time()), "ver": "99.99.99", "notice": "POISONED"}) + "\n")
    lane = Lane(kernel, poisoned)
    with bend_lock():
        h_rows = evaluate(lane, population)
    h_code, _ = decide(h_rows)
    same = [row_text(r) for r in h_rows] == [row_text(r) for r in base_rows]
    record("PLANT-HOME-POISON", VERDICT[PASS], VERDICT.get(h_code, str(h_code)),
           f"the rows are identical to the control: {same}", ok=same)

    # --- PLANT 5: the COMMENT CONTROL.  A comment-only edit to a copy of the
    # proof family must move nothing.
    scratch = scratch_family(work / "scratch", population)
    target = scratch / "LAWS" / "alu.bend"
    original = target.read_text()
    target.write_text(original + "\n# verdict-lane control: a comment, and no code\n")
    lane = Lane(kernel, home)
    with bend_lock():
        c_orig = lane.run(ROOT / PORT / "LAWS" / "alu.bend", "--verdict")
        c_copy = lane.run(target, "--verdict")
    c_cls = classify(*c_orig)
    k_cls = classify(*c_copy)
    record("PLANT-COMMENT-CONTROL", c_cls, k_cls,
           "a comment-only copy must be judged exactly as the original is")

    # --- THE SUMMARY.  Each case names what it expected and what it got.
    width = max(len(n) for n, *_ in results)
    bad = 0
    print()
    for name, want, got, why, ok in results:
        if not ok:
            bad += 1
        print(f"{name:<{width}}  want={want:<8} got={got:<8} {'OK' if ok else 'NOT AS EXPECTED'}"
              f"  -- {why}")
    print()
    print(f"=== plant: {'FAIL' if bad else 'PASS'}: {bad} case(s) not as expected ===")
    out = Path(args.artifacts) / "plant.rows"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(rows_out) + "\n")
    return 1 if bad else 0


def write_pins(args):
    """The pins for the source as it stands, ready to be pasted.

    A PIN MOVES WITH THE THING IT DESCRIBES, in the same commit.  This is how
    that move is made: it prints the constants, and a human pastes them.
    """
    src = Path(args.bend_dir) / "bendtt.lean"
    if not src.is_file():
        return refuse(f"the kernel source {src} is not there")
    src_sha = sha256_file(src)
    dest = Path(args.kernel_dir) / src_sha[:16]
    kernel = dest / "bendtt"
    if not kernel.is_file():
        ok, receipt = build_kernel(src, dest, Path(args.toolchain_dir))
        if not ok:
            return refuse(receipt.get("why", "the kernel did not build"))
    print(f"# the source: {src}")
    print(f"PIN_LEAN_VERSION = {PIN_LEAN_VERSION}")
    print(f"PIN_SRC_SHA256 = {sha256_file(src)}")
    print(f"PIN_KERNEL_SHA256 = {sha256_file(kernel)}")
    print(f"PIN_KERNEL_BYTES = {kernel.stat().st_size}")
    print(f"# the compiler's own cache key for this source: "
          f"{compiler_cache_key(src.read_text())}")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--plant", action="store_true",
                    help="the plant, the control, and the wrong shapes")
    ap.add_argument("--write-pins", action="store_true",
                    help="print the pins for the kernel source as it stands")
    ap.add_argument("--kernel", default=None,
                    help="use this kernel instead of building one (it is still PIN-CHECKED)")
    ap.add_argument("--kernel-dir", default=None,
                    help="where to build the kernel (default: a private temp dir)")
    ap.add_argument("--toolchain-dir", default=None,
                    help="the Lean toolchain's bin dir (default: the elan one)")
    ap.add_argument("--bend-dir", default=None,
                    help="the directory holding bendtt.lean (default: references/bend/bend2)")
    ap.add_argument("--home", default=None,
                    help="the HOME the lanes run under (default: a private empty dir)")
    ap.add_argument("--artifacts", default=None,
                    help="where the rows and the receipt go (default: gates/artifacts/verdict-lane)")
    ap.add_argument("--rebuild", action="store_true",
                    help="build the kernel even if one is already there")
    args = ap.parse_args(argv)

    args.bend_dir = args.bend_dir or str(ROOT / "references" / "bend" / "bend2")
    args.kernel_dir = args.kernel_dir or str(
        Path(tempfile.gettempdir()) / "bendtt-verdictlane")
    args.toolchain_dir = args.toolchain_dir or str(default_toolchain_dir())
    args.artifacts = args.artifacts or str(ROOT / "gates" / "artifacts" / "verdict-lane")
    if not args.home:
        args.home = str(Path(tempfile.mkdtemp(prefix="verdictlane-home-")))
    if args.plant:
        return plant_main(args)
    if args.write_pins:
        return write_pins(args)
    return gate_main(args)


if __name__ == "__main__":
    sys.exit(main())
