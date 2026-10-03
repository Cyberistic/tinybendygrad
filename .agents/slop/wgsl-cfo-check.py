"""Check renderer/wgsl.bend's gate rows: does the port lane equal the CPython lane?

r(name, got, want) PRINTS `name = [got]   py=[want]` -- IT DOES NOT COMPARE. Nothing in the .bend
file compares anything; the comparison lives here. So this script IS the gate for those rows, and a
parser that silently drops rows turns the gate into a change-detector.

Two rules this script obeys because it has already broken both:
  1. NEVER silently drop a row. Every line is either a compared row or reported UNPARSED, and an
     unparsed line is a FAILURE, not a skip. My first version parsed 169 of 187 and reported the
     rest as agreement.
  2. A 0-row result is indistinguishable from "not started" (bend's machine stack overflows on
     ~1 run in 20 and sometimes prints nothing). Re-run before concluding anything.

Run: .venv/bin/python .agents/slop/wgsl-cfo-check.py <wgsl.bend>
"""
import re, subprocess, sys

BEND = "./bin/bend"
TIMEOUT = 2400
ROW = re.compile(r"^(?P<name>.*?) = \[(?P<got>.*)\]\s+py=\[(?P<want>.*)\]$")


def lane(path):
    """Return (compared, unparsed, attempts). Retries, because 0 rows is the stack-overflow flake."""
    for attempt in range(1, 6):
        r = subprocess.run([BEND, path], capture_output=True, text=True, timeout=TIMEOUT)
        lines = [ln for ln in r.stdout.splitlines() if ln.strip()]
        if lines:
            break
    else:
        return {}, ["NO ROWS after 5 attempts -- stack overflow, or the file is broken"], 5
    cmp_, unparsed = {}, []
    for ln in lines:
        m = ROW.match(ln)
        if m:
            cmp_[m.group("name")] = (m.group("got"), m.group("want"))
        else:
            unparsed.append(ln)
    return cmp_, unparsed, attempt


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "tinybendygrad/renderer/wgsl.bend"
    cmp_, unparsed, attempts = lane(path)
    total = len(cmp_) + len(unparsed)
    bad = [(n, g, w) for n, (g, w) in cmp_.items() if g != w]
    print(f"file={path}  attempts={attempts}  lines={total}  compared={len(cmp_)}  "
          f"unparsed={len(unparsed)}  disagreements={len(bad)}")
    for n, (g, w) in sorted(cmp_.items()):
        print(f"  {'OK  ' if g == w else 'DIFF'} {n:36} got={g:22} want={w}")
    if unparsed:
        print(f"\nUNPARSED ({len(unparsed)}) -- these are NOT compared, so they are not gated:")
        for ln in unparsed[:20]:
            print(f"  {ln[:110]}")
    if bad:
        print(f"\nDISAGREEMENTS ({len(bad)}):")
        for n, g, w in bad:
            print(f"  {n}\n    got  ={g}\n    want ={w}")
    if not cmp_:
        print("FAIL: the lane produced NO comparable rows. An empty lane is NOT a pass -- it is the\n"
              "      signature of bend's stack overflow (~1 run in 20) or of a broken file, and\n"
              "      reporting it as 0 disagreements is a FALSE PASS. Do not conclude anything.")
        for ln in unparsed[:10]:
            print(f"  {ln[:110]}")
        return 1
    return 1 if (bad or unparsed) else 0


if __name__ == "__main__":
    sys.exit(main())