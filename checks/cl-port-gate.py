#!/usr/bin/env python3
"""cl-port-gate.py -- does `tinybendygrad/runtime/autogen/libclang.bend` answer the
oracle's rows, and can the answer be wrong?

Four things are checked, and the fourth is the one that makes the first three mean
something.

  1. THE JOIN.  Both sides parse the SAME fixture bytes and are answered by the
     SAME pinned dylib, and every shared row is compared as a whole `name=value`
     line.  Not by row name: a name-comparing harness reported 0 for all 30
     mutations in one unit and 0 for all 68 in another (agent-core.md).
  2. THE CENSUS.  rows-present against rows-expected, on BOTH sides, EVERY run,
     under the base fixture and under each plant.  A missing row and a passing row
     look identical from outside -- a planted layout once made rows VANISH.
  3. THE TWO DERIVATIONS.  `spelling=` is libclang's own answer and `c=` is the C
     declaration's; `offof_bytes` is a DIVISION of `offof_bits`.  A row that is
     internally inconsistent is a row that was manufactured.
  4. TWO PLANTS AND A DISARM.
       plant-long-a    `int a;` -> `long a;`.  Must move rows on BOTH sides and
                       move the SAME rows.
       disarm-comment  `int a;` -> `int a; /* 8 */`.  Same line, same size of
                       edit, opposite outcome: the row set must be byte-identical.
       plant-div       `bits / 8` -> `bits / 4` in the PORT's C only.  `offof_bits`
                       must NOT move and `offof_bytes` MUST.  This is the only
                       control that can say the division is a division and not a
                       second, independent reading.

    python3 checks/cl-port-gate.py            # 1-3
    python3 checks/cl-port-gate.py --plants   # 1-4

Nothing here patches the live tree.  Every plant lives in a scratch directory and
every file the port needs is COPIED there; the only thing the live tree lends is
`libclang.bend` itself.
"""
from __future__ import annotations

import argparse, base64, os, re, shutil, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BEND = REPO / "bin" / "bend"
SHIM = REPO / ".agents" / "slop" / "clangshim"
PORT = REPO / "tinybendygrad" / "runtime" / "autogen" / "libclang.bend"
ORACLE = SHIM / "oracle.py"
CFFI = SHIM / "libclang-ffi.c"
FIXH = SHIM / "fixture.h"
CLIB = "/Library/Developer/CommandLineTools/usr/lib"
LIVE_IMPORT = 'import "../../../.agents/slop/clangshim/libclang-ffi.c"'
C_SPELL_LIVE = re.search(r"#define CL_FIELD_SPELL\s+(.*)", FIXH.read_text()).group(1).strip()
assert LIVE_IMPORT.split('"')[1] in PORT.read_text(), "the live libclang.bend does not carry the FFI import"

# --- the comparison, stated before it is run ---------------------------------
#
# The oracle prints `opaque=_mem_` on its RECORD row and the port cannot: `_mem_`
# is the single byte-array member `tinygrad/runtime/support/c.py`'s `Struct`
# exposes, a ctypes mechanism with no C counterpart.  That ONE token is dropped,
# from the ORACLE's side only.
ORACLE_ONLY_TOKENS = {"opaque=_mem_"}
# the oracle's `%-12s` padding is layout, not fact, and is not reproduced
WS = re.compile(r"[ \t]+")

SHARED_ROWS = 10      # the oracle's ten, compared line by line
PORT_ONLY_ROWS = 3    # what the port prints and the oracle does not claim

# --- the plants, each with all FOUR copies of the fixture fact ---------------
#
# A plant that edits one copy is a half-plant, and CL-9 is what happens: measured
# here, `int a;` -> `long a;` in the source text ALONE leaves the oracle printing
# 7 of its 10 rows and exiting 1, because its `FIELDS` offset column states the C
# declaration and now contradicts libclang.  So the four copies are the spec.
PLANTS = {
    "plant-long-a": {
        "src": (b"int a;", b"long a;"),
        "struct": ("int a;", "long a;"),
        # long is 8-aligned on this target, so a=0..7, b=8, c=16.  These are the
        # C DECLARATION's numbers and the oracle's own `assert bits == off*8`
        # is what proves them against libclang at run time rather than here.
        "spell": '{ "long", "char", "double", "struct Pair" }',
        "fields": '[("a", 0, "long"), ("b", 8, "char"), ("c", 16, "double")]',
    },
    "disarm-comment": {
        "src": (b"int a;", b"int a; /* 8 */"),
        "struct": ("int a;", "int a; /* 8 */"),
        "spell": None,      # the declaration did not change type
        "fields": None,
    },
}


def norm(line: str, drop: set[str]) -> str | None:
    toks = [t for t in WS.split(line.strip()) if t and t not in drop]
    return " ".join(toks) if toks else None


def rows(text: str, drop: set[str]) -> list[str]:
    return [n for n in (norm(ln, drop) for ln in text.splitlines()) if n]


def field_of(row: str, key: str) -> str | None:
    m = re.search(rf"(?:^|\s){re.escape(key)}=(\S+)", row)
    return m.group(1) if m else None


def fixture_bytes(path: Path = FIXH) -> bytes:
    """CL_FIXTURE_SRC, read out of the C header the port actually compiles."""
    m = re.search(r'CL_FIXTURE_SRC\[\] =((?:\s*"(?:[^"\\]|\\.)*")+);', path.read_text())
    if not m:
        raise SystemExit(f"{path} has no CL_FIXTURE_SRC")
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
    return "".join(p.encode().decode("unicode_escape") for p in parts).encode()


def oracle_src() -> bytes:
    m = re.search(r'SRC = b"""(.*?)"""', ORACLE.read_text(), re.S)
    if not m:
        raise SystemExit("oracle.py has no SRC")
    return m.group(1).encode()


def splice(t: str, first: str, is_end, body: list[str]) -> str:
    """Replace the whole LINE REGION that starts with `first` and ends at `is_end`.

    Region, not string.  A global `str.replace` on `int a;` edits BOTH the
    declaration and the literal -- measured: `int a; /* 8 */ /* 8 */` -- and
    keeping the old terminator as well as writing a new body duplicates it:
    measured `"int top;\\n"` twice.  Both were found by the gate failing, not by
    reading, which is the argument for a row census.
    """
    lines = t.split("\n")
    i = next(k for k, l in enumerate(lines) if l.startswith(first))
    j = next(k for k in range(i + 1, len(lines)) if is_end(lines[k]))
    return "\n".join(lines[:i] + [lines[i]] + body + lines[j + 1:])


def c_literal(src: bytes) -> list[str]:
    """`src` as the body of the `CL_FIXTURE_SRC` literal, last line terminated."""
    ls = src.decode().split("\n")
    body = ['  "%s\\n"' % l for l in ls[:-1]]
    return body[:-1] + [body[-1][:-1] + '";']


def decl_lines(src: bytes) -> list[str]:
    """The fixture's C declaration, DERIVED FROM ITS OWN BYTES, opener excluded.

    Not typed.  A hand-written copy of the declaration is a second fixture and
    CL-8 is what happens to it: the first disarm in that note moved
    `SIZE struct Pair` 16 -> 24 because it was a second plant in a disguise.
    """
    out, depth = [], 0
    for l in src.decode().split("\n"):
        t = l.strip()
        if not t:
            continue
        if t.startswith("struct Pair"):
            depth += 1
            continue
        if depth and t == "};":
            depth -= 1
        out.append(l)
    return out


def replant_fixture_h(text: str, src: bytes) -> str:
    """Replant the C DECLARATION and the `CL_FIXTURE_SRC` literal, from `src`.

    Two named splices, so a half-plant is visible rather than doubled.
    """
    text = splice(text, "struct Pair {", lambda l: l.strip() == "int top;", decl_lines(src))
    return splice(text, "static const char CL_FIXTURE_SRC[] =",
                  lambda l: l.rstrip().endswith('";'), c_literal(src))


def run_oracle(work: Path, src: bytes | None = None, fields: str | None = None) -> tuple[str, str, int]:
    """The oracle from the live file, or from a PLANTED COPY of it in `work`."""
    if src is None:
        r = subprocess.run([sys.executable, str(ORACLE)], cwd=REPO, capture_output=True, text=True)
        return r.stdout, r.stderr, r.returncode
    copy = work / "oracle_planted.py"
    text = ORACLE.read_text()
    # base64 and not `repr(bytes)`: repr emits REAL newlines, which is a
    # SyntaxError, which is a 0-row oracle run, which reads as a passing gate.
    text = re.sub(r'SRC = b""".*?"""',
                  'SRC = base64.b64decode("%s")' % base64.b64encode(src).decode(),
                  text, count=1, flags=re.S)
    if fields is not None:
        text = re.sub(r"FIELDS = \[.*\]", "FIELDS = " + fields, text, count=1)
    text = text.replace("import ctypes, functools, os, sys", "import base64, ctypes, functools, os, sys")
    # the planted copy lives in the scratch tree, so parents[3] is not the repo
    text = text.replace('sys.path.insert(0, str(Path(__file__).resolve().parents[3]))',
                        f"sys.path.insert(0, {str(REPO)!r})")
    copy.write_text(text)
    r = subprocess.run([sys.executable, str(copy)], cwd=REPO, capture_output=True, text=True)
    return r.stdout, r.stderr, r.returncode


def stage_port(dst: Path) -> Path:
    """COPY the live `libclang.bend` into a scratch dir and rewrite its one C import.

    The live file imports `.agents/slop/clangshim/libclang-ffi.c` relative to the
    repo tree; in the scratch dir the helper sits beside the .bend.  Copied, never
    edited: a plant that touched the live tree would be a plant in the INPUT and
    not in the FIXTURE, which is a different experiment entirely.
    """
    dst.mkdir(parents=True, exist_ok=True)
    out = dst / "libclang.bend"
    text = PORT.read_text().replace(LIVE_IMPORT, 'import "./libclang-ffi.c"')
    out.write_text(text)
    return out


class Run:
    """One build and one run of one side.  The artefacts are removed FIRST: a
    stale `port.out` beside a failed build is how STAGE1's first attempt passed on
    the previous two-line program's value."""

    def __init__(self, work: Path, bend: Path, csrc: Path, hdr: Path):
        self.work, self.bend, self.csrc, self.hdr = work, bend, csrc, hdr
        self.gen, self.bin = work / "port.gen.c", work / "port.out"

    def __call__(self) -> tuple[str, str, int]:
        for f in (self.gen, self.bin):
            f.unlink(missing_ok=True)
        for src in (self.csrc, self.hdr):      # a planted header already IS in place
            dst = self.work / src.name
            if src.resolve() != dst.resolve():
                shutil.copy(src, dst)
        b = subprocess.run([str(BEND), str(self.bend), "-o", str(self.gen)],
                           cwd=self.work, capture_output=True, text=True)
        if b.returncode != 0 or not self.gen.exists() or self.gen.stat().st_size == 0:
            return "", f"BEND BUILD FAILED rc={b.returncode}\n{b.stdout}{b.stderr}", b.returncode
        c = subprocess.run(["cc", "-I.", self.gen.name, f"-L{CLIB}", "-lclang", f"-Wl,-rpath,{CLIB}",
                            "-o", self.bin.name], cwd=self.work, capture_output=True, text=True)
        if c.returncode != 0:
            return "", f"CC FAILED rc={c.returncode}\n{c.stdout}{c.stderr}", c.returncode
        r = subprocess.run([f"./{self.bin.name}"], cwd=self.work, capture_output=True, text=True)
        return r.stdout, r.stderr, r.returncode


def base_run(tmp: Path) -> dict:
    out, err, rc = Run(tmp, stage_port(tmp), CFFI, FIXH)()
    orc, orc_err, orc_rc = run_oracle(tmp)
    return dict(out=out, err=err, rc=rc, orc=orc, orc_err=orc_err, orc_rc=orc_rc)


def check_join(b: dict, tag: str, shared: list[str] | None, fails: list[str],
               orc_rows: list[str] | None) -> tuple[list[str], list[str]]:
    sh = [r for r in rows(b["out"], set()) if not r.startswith("PORT ")]
    po = [r for r in rows(b["out"], set()) if r.startswith("PORT ")]
    orr = rows(b["orc"], ORACLE_ONLY_TOKENS)
    print(f"\n{tag}: rc port={b['rc']} oracle={b['orc_rc']}  "
          f"port stderr={len(b['err'])}B oracle stderr={len(b['orc_err'])}B")
    print(f"{tag}: ROWS shared port={len(sh)}/{SHARED_ROWS} oracle={len(orr)}/{SHARED_ROWS}"
          f"   port-only={len(po)}/{PORT_ONLY_ROWS}")
    if b["rc"] != 0 or b["orc_rc"] != 0:
        fails.append(f"{tag}: rc port={b['rc']} oracle={b['orc_rc']}\n{b['err']}{b['orc_err']}")
    if len(sh) != SHARED_ROWS:
        fails.append(f"{tag}: port printed {len(sh)} shared rows, expected {SHARED_ROWS}")
    if len(orr) != SHARED_ROWS:
        fails.append(f"{tag}: oracle printed {len(orr)} shared rows, expected {SHARED_ROWS}")
    if len(po) != PORT_ONLY_ROWS:
        fails.append(f"{tag}: port printed {len(po)} port-only rows, expected {PORT_ONLY_ROWS}")
    only_p = [r for r in sh if r not in orr]
    only_o = [r for r in orr if r not in sh]
    for r in only_p:
        print(f"  PORT-ONLY   {r}")
    for r in only_o:
        print(f"  ORACLE-ONLY {r}")
    if only_p or only_o:
        fails.append(f"{tag}: {len(only_p)} port-only / {len(only_o)} oracle-only shared rows")
    else:
        print(f"{tag}: DIFF 0 port-only, 0 oracle-only -- all {SHARED_ROWS} rows equal")
    if shared is not None:
        moved = [r for r in sh if r not in shared]
        moved_o = [r for r in orr if r not in orc_rows]
        for r in moved:
            print(f"  moved {r}")
        if not moved and not moved_o and not tag.startswith("disarm"):
            fails.append(f"{tag}: NOTHING moved on either side -- the edit changed no answer")
        if sorted(moved) != sorted(moved_o):
            fails.append(f"{tag}: the two sides moved DIFFERENT rows: port {moved} oracle {moved_o}")
    return sh, orr


def check_derivation(sh: list[str], orr: list[str], tag: str, fails: list[str]) -> None:
    """`spelling=` vs `c=`, and `offof_bytes` vs `offof_bits`, on every FIELD row."""
    bad = []
    for r in sh + orr:
        if not r.startswith("FIELD "):
            continue
        if field_of(r, "spelling") != field_of(r, "c"):
            bad.append(f"{tag}: {r} -- libclang's spelling and the C declaration disagree")
        b, y = field_of(r, "offof_bits"), field_of(r, "offof_bytes")
        if b is None or y is None or int(y) * 8 != int(b):
            bad.append(f"{tag}: {r} -- offof_bytes*8 != offof_bits")
    for b in bad:
        fails.append(b)
    n = len([r for r in sh if r.startswith("FIELD ")])
    print(f"{tag}: DERIV spelling==c and offof_bytes*8==offof_bits on {n}/{n} FIELD rows: "
          f"{'yes' if not bad else 'NO'}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plants", action="store_true")
    args = ap.parse_args()
    tmp = Path(os.environ.get("TMPDIR", "/tmp")) / "cl-port-gate"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    fails: list[str] = []

    fb, osrc = fixture_bytes(), oracle_src()
    print(f"FIXTURE port={len(fb)}B oracle={len(osrc)}B  same={fb == osrc}")
    if fb != osrc:
        fails.append(f"FIXTURE: the two sides would read DIFFERENT bytes ({fb!r} vs {osrc!r})")

    base = base_run(tmp)
    shared, orc_rows = check_join(base, "BASE", None, fails, None)
    check_derivation(shared, orc_rows, "BASE", fails)

    if not args.plants:
        print(f"\nFAILURES: {len(fails)}")
        for f in fails:
            print(" ", f)
        return 1 if fails else 0

    for tag, spec in PLANTS.items():
        pdir = tmp / tag
        pdir.mkdir(parents=True)
        new_src = oracle_src().replace(*spec["src"])
        if new_src == oracle_src():
            fails.append(f"{tag}: the plant text {spec['src']!r} is not in the fixture")
        htext = replant_fixture_h(FIXH.read_text(), new_src)
        if spec["spell"]:
            htext = htext.replace(C_SPELL_LIVE, spec["spell"])
        hdr = pdir / "fixture.h"
        hdr.write_text(htext)
        # every copy of the fact must have taken the edit, or this is a half-plant
        if fixture_bytes(hdr) != new_src:
            fails.append(f"{tag}: the planted header's CL_FIXTURE_SRC != the planted SRC")
        if not all(ln.strip() in htext for ln in decl_lines(new_src)):
            fails.append(f"{tag}: the planted header's struct Pair did not take the edit")
        if spec["spell"] and spec["spell"] not in htext:
            fails.append(f"{tag}: the planted header's CL_FIELD_SPELL did not take the edit")
        out, err, rc = Run(pdir, stage_port(pdir), CFFI, hdr)()
        orc, orc_err, orc_rc = run_oracle(pdir, new_src, spec["fields"])
        sh, orr = check_join(dict(out=out, err=err, rc=rc, orc=orc, orc_err=orc_err, orc_rc=orc_rc),
                             tag, shared, fails, orc_rows)
        check_derivation(sh, orr, tag, fails)
        if tag.startswith("disarm"):
            # the ONE place a "nothing moved" result is the PASS condition
            moved = [r for r in sh if r not in shared]
            if moved or sorted(sh) != sorted(shared):
                fails.append(f"{tag}: the row set MOVED -- this 'disarm' is a second plant")
                for r in moved:
                    print(f"  MOVED-BY-THE-DISARM {r}")
            else:
                print(f"{tag}: DISARM same lever, same line, opposite outcome -- "
                      "the row set is byte-identical to the unplanted run")

    # ---- plant-div: one measurement, two readers ---------------------------
    ddir = tmp / "plant-div"
    ddir.mkdir(parents=True)
    bent = CFFI.read_text()
    n = bent.count("bits / 8")
    if n == 0:
        fails.append("plant-div: no `bits / 8` in libclang-ffi.c to plant in")
    cdiv = ddir / "libclang-ffi.c"
    cdiv.write_text(bent.replace("bits / 8", "bits / 4"))
    out, err, rc = Run(ddir, stage_port(ddir), cdiv, FIXH)()
    sh = [r for r in rows(out, set()) if not r.startswith("PORT ")]
    print(f"\nplant-div: sites patched in the C = {n}  rc={rc}  rows={len(sh)}/{SHARED_ROWS}")
    for old in shared:
        if not old.startswith("FIELD "):
            continue
        new = next((y for y in sh if y.split()[1] == old.split()[1]), None)
        if not new:
            fails.append(f"plant-div: FIELD {old.split()[1]} VANISHED")
            continue
        bits, bytes_ = field_of(old, "offof_bits"), field_of(old, "offof_bytes")
        if field_of(new, "offof_bits") != bits:
            fails.append(f"plant-div: offof_bits moved for FIELD {old.split()[1]} "
                         f"({bits} -> {field_of(new,'offof_bits')}) -- the two columns are "
                         "NOT one measurement")
        # A THEOREM, not a zero: field `a` sits at bit 0 and 0/8 == 0/4 == 0, so no
        # divisor and no fixture can separate them.  Only non-zero offsets can be
        # required to move, and those are the ones required to.
        if int(bits) == 0:
            print(f"  THEOREM FIELD a offof_bytes cannot move: 0/n == 0 for every n")
            continue
        if field_of(new, "offof_bytes") == bytes_:
            fails.append(f"plant-div: offof_bytes did NOT move for FIELD {old.split()[1]} "
                         "-- the division is not load-bearing")
        else:
            print(f"  ONE MEASUREMENT TWO READERS  FIELD {old.split()[1]}  offof_bits stayed "
                  f"{bits}  while  offof_bytes moved {bytes_} -> {field_of(new,'offof_bytes')}")

    print(f"\nFAILURES: {len(fails)}")
    for f in fails:
        print(" ", f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())