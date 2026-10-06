#!/usr/bin/env python3
"""loopfix/belt.py -- the SECOND of the two belts that measure a change to `fold.bend`.

    .venv/bin/python .agents/slop/loopfix/belt.py [--mode chunks|kv] BEFORE_DIR AFTER_DIR
    .venv/bin/python .agents/slop/loopfix/belt.py --selftest

WHY A SECOND BELT, AND WHY THIS ONE. Belt 1 is `diff -r` over whole files: it answers
"did any byte move", which is the question a blast radius asks, and it cannot be wrong
about a row because it does not parse rows. This belt answers DIFFERENT questions per
artefact, because the two artefacts are in two formats and a reader that understood one
and was pointed at the other would prove nothing:

| artefact | format | what this belt asserts |
|---|---|---|
| the 22-graph corpus | `<n>:<bytes>` chunks joined by ONE space (`graphcmp.bend:42`, `:529`) | every row's chunk walk ends exactly at end-of-line, and reads 8 chunks |
| `fold.bend`'s 334-row self-test | `name=value`, one `=` per line | every line has exactly one `=`, and the NAME SEQUENCE is unchanged |

THE TWO TOKENIZERS SHARE NO REGEX WITH EACH OTHER OR WITH `diff`. A whitespace splitter
would have lost 216 of 228 rows once already
(`.agents/slop/pin-tree-oracle-report.md`); the chunk walker cannot, and `--selftest`
feeds it `… PTX tensor_cores sm_75` to prove it.

**UNREADABLE IS A FAILURE, IN `main()` AND NOT ONLY IN THE SELFTEST.** The second version
of this file had it fixed in `--selftest` and STILL HOLE in `main()`, which is why it
answered `IDENTICAL [UNREADABLE] … 334 unreadable` and exited **0** on the self-test
corpus -- a belt agreeing with a corpus it cannot read, which is the trap this project
keeps paying for. `main()` now refuses: a mode that cannot parse a file is a red run, not
a quiet pass, and the fix is to point it at the right mode.
"""
from __future__ import annotations

import shutil
import sys
import tempfile
from pathlib import Path

COLUMNS = 8          # `graphcmp.bend:529`'s `row`: EIGHT chunks, seven single spaces


# --------------------------------------------------------------------------- chunks
def walk(line: str) -> list[str] | str:
    """Walk `<n>:<bytes>` chunks joined by EXACTLY ONE space.

    Returns the chunk bodies, or a reason naming the byte offset where the walk stopped.
    """
    out, i, n = [], 0, len(line)
    while i < n:
        j = line.find(":", i)
        if j < 0:
            return f"NO-COUNT at byte {i}: {line[i:i + 40]!r}"
        count = line[i:j]
        if not count.isdigit():
            return f"NON-NUMERIC-COUNT at byte {i}: {count!r}"
        k = int(count)
        body = line[j + 1:j + 1 + k]
        if len(body) != k:
            return f"TRUNCATED chunk {len(out)}: wanted {k}B, got {len(body)}B at byte {j + 1}"
        out.append(body)
        i = j + 1 + k
        if i < n:
            if line[i] != " ":
                return f"NO-SEPARATOR after chunk {len(out) - 1} at byte {i}: {line[i]!r}"
            i += 1
    return out


# ---------------------------------------------------- the self-test: name + payload
# THE SELF-TEST CORPUS IS **MIXED**, and MEASURED, not assumed: of its 334 rows, 31 are
# `name=value`, 93 are `name <chunked text>` carrying no `=` at all, and 210 are `name`
# plus space-separated `k=v` pairs holding 2, 4 or 6 of them. So a mode that splits on `=`
# reads 93 of 334 rows as garbage -- which is what the first version of this mode did,
# reporting `241 rows, 93 bad` and calling the corpus unreadable: correctly, and for a
# reason of its own making. The one shape ALL THREE KINDS SHARE is `NAME` + SEPARATOR +
# PAYLOAD, NAME carrying neither a space nor a `=`, and that is what this mode asserts.
#
# **ITS TEETH ARE ON THE NAMES AND NOT ON THE VALUES, AND THAT IS NOT A WEAKNESS TO HIDE.**
# The values are `fold.bend`'s own arithmetic and belt 1's byte diff owns them. What this
# mode adds is a CENSUS: a row that is RENAMED with every value intact, or DROPPED, or
# reordered, moves the name sequence, and moves here.
NAME = __import__("re").compile(r"[A-Za-z_][A-Za-z0-9_.\-]*")


def kv(line: str) -> tuple[str, str] | str:
    m = NAME.match(line)
    if not m:
        return f"NO-NAME at byte 0: {line[:40]!r}"
    name, rest = m.group(0), line[m.end():]
    if rest and rest != rest.rstrip():
        return "TRAILING-WHITESPACE: the payload is not consumed exactly"
    if rest and rest[0] not in " =":
        return f"NO-SEPARATOR at byte {m.end()}: {rest[:20]!r}"
    return name, rest


def names(path: Path) -> tuple[list[str], list[str]]:
    got, bad = [], []
    for raw in path.read_text().splitlines():
        if not raw.strip():
            continue
        got.append(raw)
        if raw.startswith("#"):
            continue
        r = walk(raw) if raw[0].isdigit() else kv(raw)
        if isinstance(r, str):
            bad.append(f"{raw[:48]}: {r}")
        elif isinstance(r, list) and len(r) != COLUMNS:
            bad.append(f"{raw[:48]}: {len(r)} chunks, expected {COLUMNS}")
    return got, bad


def keys(path: Path) -> tuple[list[str], list[str]]:
    """(the NAME of every row, per-row reasons). The name list is the point: a row whose
    NAME moved is a row that moved even when every value agreed."""
    got, bad = [], []
    for raw in path.read_text().splitlines():
        if not raw.strip():
            continue
        if raw.startswith("#"):
            continue
        r = kv(raw)
        if isinstance(r, str):
            bad.append(f"{raw[:48]}: {r}")
        else:
            got.append(r[0])
    return got, bad


def read(path: Path, mode: str) -> tuple[int, list[str]]:
    body, bad = (names(path) if mode == "chunks" else keys(path))
    return len(body), bad


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    mode, rest = "chunks", [a for a in argv[1:] if not a.startswith("--")]
    for a in argv[1:]:
        if a.startswith("--mode="):
            mode = a.split("=", 1)[1]
    if len(rest) < 2 or mode not in ("chunks", "kv"):
        print("usage: belt.py [--mode=chunks|kv] BEFORE_DIR AFTER_DIR")
        return 2
    a, b = Path(rest[0]), Path(rest[1])
    fails = 0
    for nm in sorted({p.name for p in a.glob("*.rows")} | {p.name for p in b.glob("*.rows")}):
        pa, pb = a / nm, b / nm
        if not (pa.exists() and pb.exists()):
            print(f"  {nm}: MISSING ON ONE SIDE (before={pa.exists()} after={pb.exists()})")
            fails += 1
            continue
        na, ba = read(pa, mode)
        nb, bb = read(pb, mode)
        same = ba == bb and pa.read_bytes() == pb.read_bytes()
        # UNREADABLE IS A FAILURE. This line is the whole reason the second version of
        # this file had to be rewritten.
        verdict = "IDENTICAL" if same else "MOVED    "
        if ba or bb:
            verdict = "UNREADABLE"
        print(f"  {nm}: {verdict} [{mode}] before[{na} rows, {len(ba)} bad] "
              f"after[{nb} rows, {len(bb)} bad]")
        for why in (ba + bb)[:3]:
            print(f"      {why}")
        fails += 0 if (same and not ba and not bb) else 1
    print(f"=== belt.py --mode={mode}: {fails} moved or unreadable ===")
    return 1 if fails else 0


# --------------------------------------------------------------- the self-test corpus
# THE CORPUS IS THE REAL ARTEFACT, NOT A HAND-TYPED ONE. The first version of this file
# typed its own `<n>:` counts, got two of them wrong, and its own CONTROL caught it -- a
# self-test whose fixture is written by hand has a hand-written expected value inside it,
# which is the tautology this project keeps rebuilding.
HERE = Path(__file__).resolve().parent
GRAPH = HERE / "base" / "loop.rows"
SELF = HERE / "selftest-frozen-old.rows"


def reseat(cs: list[str]) -> str:
    """Rebuild a row from chunk BODIES, computing every count. Never type a count."""
    return " ".join(f"{len(c)}:{c}" for c in cs)


def selftest() -> int:
    """The belt must REACT, and it must be READABLE before it is allowed to react."""
    results: list[tuple[str, bool]] = []
    graph_body = GRAPH.read_text()
    self_body = SELF.read_text()
    with tempfile.TemporaryDirectory(prefix="belt.") as td:
        d = Path(td)
        (d / "old").mkdir()
        (d / "new").mkdir()

        def run(mode: str) -> int:
            return main(["belt.py", f"--mode={mode}", str(d / "old"), str(d / "new")])

        def put(rows: list[str]) -> None:
            """BOTH sides, so `put` sets up a CONTROL. A plant writes ONE side -- and the
            first version of this file wrote both, so every chunk plant compared a file
            with itself, answered `IDENTICAL`, and four of them FAILED. A plant that
            cannot move is a plant that passes."""
            for side in ("old", "new"):
                (d / side / "x.rows").write_text("\n".join(rows) + "\n")

        def plant(mode: str, name: str, rows: list[str]) -> None:
            (d / "new" / "x.rows").write_text("\n".join(rows) + "\n")
            n, bad = read(d / "new" / "x.rows", mode)
            results.append((f"PLANT {name} [{n} rows, {len(bad)} bad]", run(mode) == 1))

        # ---------------- chunks
        put(graph_body.splitlines())
        n, bad = read(d / "old" / "x.rows", "chunks")
        results.append((f"CONTROL chunks: the REAL corpus is READABLE ({n} rows, {len(bad)} bad)",
                        n > 2 and not bad))
        results.append(("CONTROL chunks: identical copies pass", run("chunks") == 0))

        body = [ln for ln in graph_body.splitlines() if ln and not ln.startswith("#")]
        cs = walk(body[-1])
        assert isinstance(cs, list), cs
        head, last = body[:-1], body[-1]

        # A SPACE INSIDE A CHUNK, with the count reseated -- the case a whitespace
        # tokenizer gets wrong and this one cannot.
        spacey = list(cs)
        spacey[7] += " PTX tensor_cores sm_75"
        plant("chunks", "SPACE: one chunk holds `PTX tensor_cores sm_75`",
              head + [reseat(spacey)])
        results.append(("PLANT chunks SPACE: and that row still walks to 8",
                        len(walk(reseat(spacey))) == COLUMNS))
        plant("chunks", "TRUNCATE: a body one byte short of its count",
              head + [last.replace("4:CALL", "4:CAL", 1)])
        plant("chunks", "PAD: a trailing space the count does not cover", head + [last + " "])
        plant("chunks", "PAD-MID: two spaces where the format has one",
              head + [last.replace(" 2:i0", "  2:i0", 1)])
        plant("chunks", "DROP: a row deleted outright", head)
        plant("chunks", "SWAP: two columns exchanged, every count still right",
              head + [reseat(cs[1:4] + cs[4:7] + [cs[0], cs[7]])])

        # ---------------- name + payload
        put(self_body.splitlines())
        n, bad = read(d / "old" / "x.rows", "kv")
        results.append((f"CONTROL kv: the REAL self-test is READABLE ({n} rows, {len(bad)} bad)",
                        n == 334 and not bad))
        results.append(("CONTROL kv: identical copies pass", run("kv") == 0))

        kvrows = [ln for ln in self_body.splitlines() if ln and not ln.startswith("#")]
        results.append(("CONTROL kv: every row has a NAME",
                        len(keys(d / "old" / "x.rows")[0]) == len(kvrows)))

        # A RENAMED row: every value intact and `diff` sees one byte. This is the case
        # that makes a name census worth having, and it is why this mode is not a
        # restatement of belt 1.
        renamed = [ln.replace("rg_", "RG_", 1) if ln.startswith("rg_") else ln
                   for ln in kvrows]
        plant("kv", "RENAME: a row's NAME changed and every value stayed", renamed)
        plant("kv", "DROP: 40 of 334 rows", kvrows[:40])
        plant("kv", "REORDER: 334 rows in the opposite order", kvrows[::-1])
        plant("kv", "PADDED: a trailing space on every row", [ln + " " for ln in kvrows])
        plant("kv", "NOSEP: the separator replaced by a tab",
              [ln.replace(" ", "\t", 1) if " " in ln else ln for ln in kvrows])
        plant("kv", "BARE: a row reduced to a `=` and nothing else", ["="] * 334)

        # ---------------- THE ASYMMETRY, WHICH IS A PROPERTY AND NOT AN ACCIDENT
        # The first version of this file claimed a `kv` corpus was UNREADABLE under
        # `--mode=chunks`, and the case FAILED: `names()` falls back to `kv` for any row
        # that does not start with a digit, so chunks mode is a deliberate SUPERSET and
        # reads both corpora. The claim was wrong, not the code -- and a selftest that
        # asserts a falsehood is a selftest that will be "fixed" by breaking the reader.
        # So the asymmetry is stated the other way round, and this pins it.
        put(kvrows)
        (d / "new" / "x.rows").write_text("\n".join(renamed) + "\n")
        results.append(("ASYMMETRY: --mode=chunks is a SUPERSET and reads the kv corpus",
                        run("chunks") == 1))
        put(graph_body.splitlines())
        (d / "new" / "x.rows").write_text(
            "\n".join([body[-1].replace("4:CALL", "4:CAL", 1)] + head) + "\n")
        results.append(("ASYMMETRY: --mode=kv cannot read a chunk corpus, and FAILS",
                        run("kv") == 1))

    failed = 0
    for nm, ok in results:
        print(f"[{('PASS' if ok else 'FAIL'):>4}] {nm}")
        failed += 0 if ok else 1
    print(f"=== selftest {'PASS' if not failed else 'FAIL'}: {len(results)} case(s), "
          f"{failed} failed ===")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))