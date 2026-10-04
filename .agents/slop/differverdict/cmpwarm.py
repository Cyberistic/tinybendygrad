#!/usr/bin/env python3
"""Per-file comparison of the frozen shell oracle's artifacts against checks/differ.py's.

Answers, PER FILE and never as a summary: which artifacts each side produced, and how many
lines differ. A single "IDENTICAL" over 150 files hides the one that differs -- and a file
only one side produced is a stronger finding than a differing one, because one direction is
an artifact LOST and the other is a NEW CLAIM NOTHING CHECKED.

Also extracts, separately, the VERDICT lines and the DENOMINATOR lines, because those are the
claim; the rest is bookkeeping. `?=0` measures omission and never the verdict.
"""
import re
import sys
from pathlib import Path

SLOP = Path(__file__).resolve().parent
A, B = SLOP / "warm-oracle", SLOP / "warm-python"


def body(p: Path) -> bytes:
    return p.read_bytes()


def nonblank(p: Path) -> bytes:
    """`grep -v '^[[:space:]]*$'` — the shell's own snapshot form, so a trailing blank line
    is a real difference and a blank line is not hashed in at all."""
    return b"".join(ln + b"\n" for ln in body(p).split(b"\n")[:-1] if ln.strip())


def diff_lines(a: Path, b: Path) -> tuple[int, str]:
    """Unified-diff differing-line count, plus the first hunk. difflib spells differences
    its own way; this is only a COUNT plus a human-readable excerpt, never the verdict."""
    import difflib
    al = nonblank(a).decode(errors="replace").splitlines()
    bl = nonblank(b).decode(errors="replace").splitlines()
    sm = difflib.SequenceMatcher(a=al, b=bl, autojunk=False)
    changed, first = 0, ""
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        n = max(i2 - i1, j2 - j1)
        changed += n
        if not first:
            first = (f"  {tag}: oracle={al[i1:i2][:3]} python={bl[j1:j2][:3]}"[:600])
    return changed, first


def verdict_lines(p: Path) -> dict:
    """graph -> (VERDICT, DENOMINATOR). The two claims, read from the per-graph files."""
    out = {}
    txt = p.read_text(errors="replace")
    v = re.findall(r"VERDICT: ([A-Z]+)", txt)
    d = re.findall(r"DENOMINATOR:(.*)", txt)
    out["_verdicts_all"] = v
    out["_denominators_all"] = [x.strip() for x in d]
    return out


def main():
    if not A.is_dir() or not B.is_dir():
        print(f"missing: {A} exists={A.is_dir()}  {B} exists={B.is_dir()}")
        return 2
    an = {p.name for p in A.iterdir() if p.is_file()}
    bn = {p.name for p in B.iterdir() if p.is_file()}
    lost = sorted(an - bn)
    new = sorted(bn - an)
    both = sorted(an & bn)
    rows, differing, same = [], [], 0
    for name in both:
        n, ex = diff_lines(A / name, B / name)
        rows.append((name, n, ex))
        if n:
            differing.append(name)
        else:
            same += 1
    w = max((len(r[0]) for r in rows + [(("LOST:" + x), 0, "") for x in lost]
             + [(("NEW:" + x), 0, "") for x in new]), default=10)
    print(f"oracle wrote {len(an)} files, python wrote {len(bn)} files, "
          f"{len(both)} names in common")
    print(f"BYTE-IDENTICAL: {same}   DIFFERING: {len(differing)}   "
          f"LOST (oracle only): {len(lost)}   NEW (python only): {len(new)}")
    print()
    print("=== LOST ARTIFACTS: oracle writes, python does NOT ===")
    for n in lost:
        print(f"  LOST {n}  ({body(A/n).count(chr(10).encode())} lines in oracle)")
    if not lost:
        print("  (none)")
    print()
    print("=== NEW CLAIMS: python writes, oracle NEVER made them ===")
    for n in new:
        print(f"  NEW  {n}  ({body(B/n).count(chr(10).encode())} lines)")
    if not new:
        print("  (none)")
    print()
    print("=== PER-FILE differing-line counts (only files that differ) ===")
    for name, n, ex in rows:
        if n:
            print(f"  {name.ljust(w)}  {n:6d} differing lines")
            if ex:
                print(ex)
    if not differing:
        print("  (none)")
    print()
    print("=== VERDICT + DENOMINATOR, per graph (THE CLAIM, read separately) ===")
    vg = sorted(p.name for p in A.glob("D1-graph-*.txt"))
    print(f"  {'graph'.ljust(12)} {'oracle VERDICT/DENOM':46} {'python VERDICT/DENOM':46} same?")
    bad = 0
    for name in vg:
        g = re.search(r"D1-graph-(.*)\.txt", name).group(1)
        ao, bo = verdict_lines(A / name), verdict_lines(B / name)
        av = ao["_verdicts_all"][-1] if ao["_verdicts_all"] else "(none)"
        bv = bo["_verdicts_all"][-1] if bo["_verdicts_all"] else "(none)"
        ad = ao["_denominators_all"][-1] if ao["_denominators_all"] else "(none)"
        bd = bo["_denominators_all"][-1] if bo["_denominators_all"] else "(none)"
        same_v = av == bv
        same_d = ad == bd
        if not (same_v and same_d):
            bad += 1
        print(f"  {g.ljust(12)} {av + ' ' + ad[:36]:46} {bv + ' ' + bd[:36]:46} "
              f"{'Y' if same_v else 'N-VERDICT'}{'' if same_d else ' N-DENOM'}")
    print(f"  graphs whose VERDICT or DENOMINATOR differs: {bad} of {len(vg)}")
    print()
    print("=== ops-reached / ? ledger lines, per graph ===")
    pa, pb = {}, {}
    for tag, store, base in (("O", pa, A), ("P", pb, B)):
        for p in base.glob("D1-graph-*.txt"):
            g = re.search(r"D1-graph-(.*)\.txt", p.name).group(1)
            t = p.read_text(errors="replace")
            store[g] = re.findall(r"(ops-reached=\S+.*|\?=\S+.*)", t)
    for g in sorted(set(pa) | set(pb)):
        same = pa.get(g) == pb.get(g)
        print(f"  {g.ljust(12)} oracle={pa.get(g)} python={pb.get(g)} {'same' if same else 'DIFFERS'}")
    print()
    print("=== SUMMARY LINE-BY-LINE (D0-run-summary.txt) ===")
    sa = (A / "D0-run-summary.txt").read_text(errors="replace").splitlines()
    sb = (B / "D0-run-summary.txt").read_text(errors="replace").splitlines()
    ka = {ln.split("=", 1)[0]: ln.split("=", 1)[1] for ln in sa if "=" in ln}
    kb = {ln.split("=", 1)[0]: ln.split("=", 1)[1] for ln in sb if "=" in ln}
    for k in sorted(set(ka) | set(kb)):
        o, p = ka.get(k, "(ABSENT)"), kb.get(k, "(ABSENT)")
        print(f"  {k.ljust(18)} oracle={o!r:26} python={p!r:26} {'same' if o == p else 'DIFFERS'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())