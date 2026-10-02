#!/usr/bin/env python3
# .agents/slop/nv_bendplus.py -- put `+` on exactly the parameters the COMPILER
# says are read twice, one fix per round, writing before each recompile.
#
# A `+` sweep is otherwise a guess: the notes record `+p: F32` being accepted and
# an UNUSED `+` also being accepted, so "add + everywhere" is not free. Asking
# the compiler which parameter is non-Lone is the cheap exact answer.
import re, subprocess, sys

P = sys.argv[1] if len(sys.argv) > 1 else "tinybendygrad/runtime/support/nv/nvdev.bend"

def compile():
    r = subprocess.run(["./bin/bend", P], capture_output=True, text=True)
    return r.stdout + r.stderr

def save(s):
    open(P, "w").write(re.sub(r'\n{3,}', '\n\n', s))

s = open(P).read()
for it in range(120):
    out = compile()
    m = re.search(r"- expected : (\S+)\n- observed : \1 \(consumed more than once\)", out)
    if not m:
        print(f"STOP after {it} fixes"); print(out[:1500]); break
    name = m.group(1)
    loc = re.search(r"Location: (\S+)", out)
    if not loc:
        print("no Location line"); print(out[:900]); break
    dn = loc.group(1)
    mm = re.search(r"^def " + re.escape(dn) + r"\(", s, re.M)
    if not mm:
        print(f"no def {dn} for {name}"); break
    # the SIGNATURE can span lines: it ends at the ` -> ` and the `:` that closes
    # the parameter list, and a one-line rewrite that stops at the first newline
    # DROPS THE RETURN TYPE -- which the compiler then reads as a law fill.
    start = mm.start()
    depth, i, close = 0, mm.start() + len("def " + dn), None
    while i < len(s):
        if s[i] == "(": depth += 1
        elif s[i] == ")":
            depth -= 1
            if depth == 0: close = i; break
        i += 1
    if close is None:
        print(f"unbalanced parens in {dn}"); break
    ps = s[s.index("(", start) + 1:close]
    parts = [x.strip() for x in ps.split(",")]
    hit = False
    for k, x in enumerate(parts):
        pn = x.split(":")[0].strip().lstrip("+")
        if pn == name and not x.startswith("+"):
            parts[k] = "+" + x; hit = True
    if not hit:
        print(f"{name} is not a parameter of {dn}: {s[start:close+1]}"); break
    s = s[:s.index("(", start) + 1] + ", ".join(parts) + ")" + s[close + 1:]
    save(s)
    print(f"  +{name} in {dn}")