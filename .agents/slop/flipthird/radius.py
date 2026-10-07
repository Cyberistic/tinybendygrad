"""FLIPTHIRD exp2: the MEASURED blast radius of a 22nd `Arg` constructor.

The same one-line probe as arg22.py, but over every file this unit OWNS plus
the two it is forbidden to touch, so the answer is a radius rather than a pair.

Ownership, verbatim from the brief:
  OWNED     ops.bend fold.bend movement.bend prepare.bend tensor.bend
  FORBIDDEN render.bend upat.bend checks/ gates/ AGENTS.md

Nothing in the forbidden set is WRITTEN. Compiling is not editing.
"""
import hashlib, os, re, subprocess, sys

OPS = "tinybendygrad/uop/ops.bend"
OWNED = ["tinybendygrad/uop/ops.bend",
         "tinybendygrad/uop/fold.bend",
         "tinybendygrad/mixin/movement.bend",
         "tinybendygrad/schedule/prepare.bend",
         "tinybendygrad/tensor.bend"]
FORBIDDEN = ["tinybendygrad/uop/render.bend", "tinybendygrad/uop/upat.bend"]
TARGETS = OWNED + FORBIDDEN
BEND = "./bin/bend"
BOUND = [".venv/bin/python", "checks/bounded.py", "--seconds", "400", "--mb", "2048", "--"]
NEW_CTOR = "  ABoolList{bs: List<&2, Bool>}"
ANCHOR = "  ATuple{ys: List<&2, U32>}"


def compile_bend(target, tag):
    err = f".agents/slop/flipthird/e2-{tag}.err"
    with open(err, "wb") as fh:
        subprocess.call(BOUND + [BEND, target], stdout=fh, stderr=subprocess.STDOUT)
    txt = open(err, encoding="utf-8", errors="replace").read()
    m = re.search(r"(KILLED-ON-MEMORY|TIMED-OUT|WITHIN-LIMITS)", txt)
    # bend's real diagnostic: `- expected : cases for <ctor>`
    want = sorted(set(re.findall(r"expected : cases for ([\w.]+)", txt)))
    other = sorted(set(re.findall(r"- ([A-Za-z_ ]+expected[^\n]*)", txt)))
    return (m.group(1) if m else "NO-TOKEN"), want, other


def main():
    out = []
    def say(s=""):
        print(s); out.append(s)

    before = hashlib.md5(open(OPS, "rb").read()).hexdigest()
    say("# FLIPTHIRD exp2 -- radius of ONE added `Arg` constructor")
    say(f"# probe: insert `{NEW_CTOR.strip()}` after `ATuple` in {OPS} (owned), then REVERT")
    say()

    say(f"{'file':42} {'ownership':10} {'base-token':14} {'new-ctor-token':16} verdict")
    say("-" * 110)
    base = {}
    for t in TARGETS:
        base[t] = compile_bend(t, "base-" + t.replace("/", "_").replace(".bend", ""))

    src = open(OPS, encoding="utf-8").read()
    assert ANCHOR in src
    open(OPS, "w", encoding="utf-8").write(src.replace(ANCHOR, ANCHOR + "\n" + NEW_CTOR, 1))
    try:
        for t in TARGETS:
            tok, want, other = compile_bend(t, "exp-" + t.replace("/", "_").replace(".bend", ""))
            btok, bwant, bother = base[t]
            own = "OWNED" if t in OWNED else "FORBIDDEN"
            added = [c for c in want if c not in bwant]
            if not added:
                v = "ABSORBED (22nd ctor costs this file NOTHING)"
            else:
                v = "BREAKS: needs " + ", ".join(added)
            say(f"{t:42} {own:10} {btok:14} {tok:16} {v}")
            if bwant:
                say(f"{'':42} {'':10} baseline already wants: {', '.join(bwant)}")
    finally:
        open(OPS, "w", encoding="utf-8").write(src)
        say()
        say(f"# REVERT {OPS}: md5 {hashlib.md5(open(OPS,'rb').read()).hexdigest()} "
            f"== {before} -> {hashlib.md5(open(OPS,'rb').read()).hexdigest() == before}")
    open(".agents/slop/flipthird/radius.rows", "w").write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()