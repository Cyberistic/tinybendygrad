#!/usr/bin/env python3
"""Does `.agents/slop/helpers-tc-gate.sh` write what THREE DOCUMENTS say it writes?

THE FAILURE THIS EXISTS TO CATCH, and it is not a typo. `.agents/slop/revive/REVIVE.md:217`,
`.agents/TODO.md:320` and `.agents/slop/notes/bend2-constraints.md:24437` all carry the SAME pair
of claims: that `helpers-tc-gate.py` was renamed to `oracles/helpers-tc-gate.rows`, and that
"the driver now writes `$GT.rows`". Both were false in the tree at the same time, and they agreed
with EACH OTHER, which is the part that makes the failure survive review: three citations of one
another are not three independent witnesses. The committed driver wrote `$GT.py`; nothing was ever
moved into `oracles/`; and the run whose output all three quote (`237 shared rows, 3 lanes
identical`) is an output line the driver produces EITHER WAY, so the quote certified nothing.

So the assertion is not "does the text say `.rows`". It is: does the file the driver NAMES match
the file the driver WRITES, and does the directory a document names match the driver's own `GT=`
prefix. A rename is a claim about a WRITE PATH, and a write path is checkable.

usage: .venv/bin/python .agents/slop/txtgen/docs-agree-with-driver.py [--against HEAD]

exit 0  every document agrees with the driver
exit 1  a document and the driver disagree, and it says which is wrong
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
DRIVER = ".agents/slop/helpers-tc-gate.sh"
DOCS = (".agents/slop/revive/REVIVE.md", ".agents/TODO.md",
        ".agents/slop/notes/bend2-constraints.md")

# What the driver WRITES: the `GT=` prefix, and every lane name built from it. `$GT.py` is what a
# `.py` gate-namespace artefact is CALLED; the extension is the whole claim, so it is read off the
# source rather than assumed.
LANE = re.compile(r'\$GT\.([A-Za-z0-9_.]+)')





def at(rev, path):
    """A file as it was at `rev`, or as it is now when `rev` is None."""
    if rev is None:
        return (ROOT / path).read_text()
    return subprocess.run(["git", "show", f"{rev}:{path}"], cwd=ROOT,
                          capture_output=True, text=True, check=True).stdout


def main() -> int:
    against = "HEAD" if "--against" in sys.argv else None
    src = at(against, DRIVER)
    label = f"{DRIVER}@{against}" if against else f"{DRIVER} (working tree)"
    print(f"{'REPLAYING THE COMMITTED STATE' if against else 'THE LIVE STATE'}  "
          f"driver AND documents both from {against or 'the working tree'}")

    gt = re.search(r'^GT=(\S+)', src, re.M)
    lanes = sorted(set(LANE.findall(src)))
    written = [n for n in lanes if n.split(".")[-1] in ("rows", "txt")]
    print(f"DRIVER  {label}")
    print(f"  GT= prefix            {gt.group(1) if gt else 'ABSENT'}")
    print(f"  lanes it names        {lanes}")

    py_lane = [n for n in lanes if n.split(".")[0] == "py"]
    ok = True
    for doc in DOCS:
        # WHITESPACE-NORMALISED, because a document that wraps `$GT.rows` onto the next line has
        # not stopped claiming it, and a checker that cannot see a wrapped citation is a checker
        # that reports agreement for the wrong reason.
        text = " ".join(at(against, doc).split())
        # ONLY the `.rows` claim is a destination claim. A document also says
        # `helpers-tc-gate.py` -- that is the HISTORICAL name being described, correctly -- and
        # `helpers-tc-gate.sh` -- that is the driver. Holding either to the driver's `GT=` would be
        # the checker being wrong in the same way these documents were.
        claims_dest = sorted(set(re.findall(r'[\w./-]*helpers-tc-gate\.rows\b', text)))
        claims_rows = "writes `$GT.rows`" in text
        # THE TWO ASSERTIONS, and the second is the one that was false three times over:
        # the extension, and the DESTINATION. A claimed destination is only true if it starts with
        # the driver's own `GT=` prefix -- otherwise the document is describing a move that never
        # happened, which is exactly what all three did.
        dir_ok = bool(claims_dest) and all(c.startswith(gt.group(1)) for c in claims_dest) \
            if gt else False
        agree = claims_rows and bool(py_lane) is False and dir_ok
        ok &= agree
        print(f"\nDOC     {doc}")
        print(f"  claims the driver writes `$GT.rows`   {claims_rows}")
        print(f"  claims the destination                {claims_dest or 'none named'}")
        print(f"  driver's GT= is the claimed parent    {dir_ok}")
        print(f"  driver writes a `.py` lane            {py_lane or 'none'}")
        print(f"  VERDICT  {'agrees' if agree else 'DISAGREES WITH THE DRIVER'}")

    print("\nVERDICT: every document agrees with the driver." if ok
          else "\nVERDICT: A DOCUMENT DISAGREES WITH THE DRIVER. Three documents citing one another"
               " is not three witnesses.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())