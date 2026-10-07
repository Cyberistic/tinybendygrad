"""FLIPTHIRD: does a 22nd `Arg` constructor break the two CLOSED `Arg` matches?

Only `bend` settles this. Neither prior unit ran it -- both declared the cost
structurally and stopped.

METHOD (baseline first, so this is not a change-detector):
  1. BASELINE   compile the two targets on the untouched tree
  2. EXPERIMENT insert ONE line into `type Arg` (a file this unit owns),
                recompile the same two targets
  3. REVERT     restore `ops.bend` byte-for-byte, prove the md5 matches
  4. DIFF       report what appeared, and WHERE

The edit is one line to `ops.bend` ONLY. `render.bend` and `upat.bend` are NOT
this unit's files and are never written -- if they break, the run proves the
break happened WITHOUT editing them, which is the whole point.

Every stream lands in `.err` / `.rows`. No `.txt` is created.
"""
import hashlib, os, re, subprocess, sys

OPS = "tinybendygrad/uop/ops.bend"
TARGETS = ["tinybendygrad/uop/render.bend", "tinybendygrad/uop/upat.bend"]
BEND = "./bin/bend"
BOUND = [".venv/bin/python", "checks/bounded.py", "--seconds", "300", "--mb", "2048", "--"]
# census peaks: render 204 MB, upat 347 MB; sum 551 MB << 60% of 16 GB.

NEW_CTOR = "  ABoolList{bs: List<&2, Bool>}"
ANCHOR = "  ATuple{ys: List<&2, U32>}"


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def compile_bend(target, tag):
    """Run one target under bounded.py; return (token, stderr-text)."""
    err = f".agents/slop/flipthird/{tag}.err"
    with open(err, "wb") as fh:
        rc = subprocess.call(BOUND + [BEND, target], stdout=fh, stderr=subprocess.STDOUT)
    txt = open(err, encoding="utf-8", errors="replace").read()
    m = re.search(r"\[bounded\].*?(KILLED-ON-MEMORY|TIMED-OUT|WITHIN-LIMITS)", txt)
    return (m.group(1) if m else "NO-TOKEN"), txt, rc


def syntax_errors(txt):
    """Bend's compile diagnostics: the lines naming a file:line and a type error."""
    keep = []
    for ln in txt.split("\n"):
        if re.search(r"error|Error|not exhaustive|exhaust", ln):
            keep.append(ln.rstrip())
    return keep


def main():
    report = []
    def say(s=""):
        print(s)
        report.append(s)

    before = md5(OPS)
    say(f"# ops.bend md5 BEFORE  {before}")
    say(f"# targets: {', '.join(TARGETS)}")
    say()

    base = {}
    say("## 1. BASELINE (untouched tree)")
    for t in TARGETS:
        tok, txt, rc = compile_bend(t, "base-" + os.path.basename(t).replace(".bend", ""))
        errs = syntax_errors(txt)
        base[t] = set(errs)
        say(f"  {t}\n    token={tok} rc={rc} error-lines={len(errs)}")
        for e in errs[:12]:
            say(f"      | {e}")
    say()

    # ---- the experiment: ONE line, into a file this unit owns ----
    src = open(OPS, encoding="utf-8").read()
    if ANCHOR not in src:
        say("REFUSED: anchor not found; no edit made")
        return 1
    open(OPS, "w", encoding="utf-8").write(src.replace(ANCHOR, ANCHOR + "\n" + NEW_CTOR, 1))
    after = md5(OPS)
    say(f"## 2. EXPERIMENT -- inserted after `ATuple`: `{NEW_CTOR.strip()}`")
    say(f"# ops.bend md5 EDITED  {after}  (delta is exactly this one line)")
    say()

    say("## 3. RESULT")
    try:
        for t in TARGETS:
            tok, txt, rc = compile_bend(t, "exp-" + os.path.basename(t).replace(".bend", ""))
            new = set(syntax_errors(txt)) - base[t]
            say(f"  {t}\n    token={tok} rc={rc} NEW-error-lines={len(new)}")
            for e in sorted(new)[:20]:
                say(f"      + {e}")
            if not new:
                say("      (no new diagnostic -- the 22nd ctor was ABSORBED)")
    finally:
        open(OPS, "w", encoding="utf-8").write(src)
        restored = md5(OPS)
        say()
        say(f"## 4. REVERT -- ops.bend md5 {restored}  restored={restored == before}")
    open(".agents/slop/flipthird/arg22.rows", "w", encoding="utf-8").write("\n".join(report) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())