#!/usr/bin/env python3
"""comment-only-gate.py -- IS AN EDIT TO A `.bend` FILE COMMENT-ONLY?

    .venv/bin/python gates/comment-only-gate.py --base HEAD -- tinybendygrad/uop/ops.bend
    .venv/bin/python gates/comment-only-gate.py --self-test
    .venv/bin/python gates/comment-only-gate.py --base HEAD --all

AN EDIT IS COMMENT-ONLY IFF THE CODE IT LEAVES BEHIND IS BYTE-IDENTICAL. The proof is
the COMMENT-STRIPPED bytes, and it is NOT the compiler's verdict: `checks/port-compile-gate.py`
plants a whole-line comment at column 0 above an indented body and MEASURED that all three
of its insertion points STILL COMPILE -- so a compiler that says "fine" has said nothing
about whether the edit touched code. The compiler is the SECOND opinion; this is the first.

`strip_comments()` IS COPIED FROM `checks/port-compile-gate.py`, and the copy is the
point: a second implementation of "what is a comment" is a second contract with no
generator, and the two disagree on exactly the case that matters -- a `#` inside a string.
The upstream copy blanks the string literals FIRST and then cuts at the first unquoted
`#`, and it RSTRIPS the result, because a comment-only edit necessarily leaves the
whitespace that preceded the `#` and that whitespace is not code.

BLANK LINES ARE DROPPED, and that is the house fix: a comment-only edit that also adds
or removes a blank line is still a comment-only edit, and a proof that rejects it would be
a proof that has to be argued with.

THE TWO WRONG SHAPES OF A "COMMENT-ONLY EDIT", MEASURED HERE BY `--self-test`:
  A -- a comment appended BETWEEN the pattern and the body of a two-part line DELETES the
       body, and the file may still COMPILE. The comment-stripped proof catches it; the
       compiler does not.
  B -- a whole-line comment at column 0 does NOT break a bend file. The parser skips
       whole-line comments, so the block below is untouched. The proof ACCEPTS it, and the
       lesson survives: an edit's comment-only-ness is PROVEN by the stripped bytes, not
       by the verdict.

THE COMPARISON IS AGAINST A REVISION, NOT AGAINST NOTHING: `--base` names the commit whose
blob is the "before", and the default is `HEAD`. The tree's index is ARMED, so `git diff`
is not a statement about the working copy -- `git cat-file blob <rev>:<path>` is.

THE EXITS ARE `gatekit`'s. `PASS` (0) every file proved comment-only · `FAIL` (1) one file
is not · `REFUSED` (3) the base revision or a file is absent.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED  # noqa: E402


def strip_comments(text: str) -> str:
    """The file with every `#` comment removed -- the PROOF that an edit is comment-only.

    A `#` inside a string is not a comment, and this file's strings carry `"` and `\\`, so the
    string literals are blanked FIRST, the way `checks/substrate.py:672-677` does it.

    COPIED FROM `checks/port-compile-gate.py`. See the module docstring: a second
    implementation of "what is a comment" is a second contract with no generator.
    """
    out = []
    in_str = False
    for ln in text.split("\n"):
        buf, i = [], 0
        while i < len(ln):
            ch = ln[i]
            if in_str:
                if ch == "\\":
                    buf.append(" " * 2)
                    i += 2
                    continue
                if ch == '"':
                    in_str = False
                buf.append(" ")
                i += 1
                continue
            if ch == '"':
                in_str = True
                buf.append(" ")
                i += 1
                continue
            if ch == "#":
                break
            buf.append(ch)
            i += 1
        # RSTRIPPED, because a comment-only edit necessarily leaves the whitespace that
        # preceded the `#`, and that whitespace is not code. MEASURED: without this, the
        # control below reads as "not comment-only" for a difference of two spaces, and a
        # control that is rejected for trailing whitespace is a control that proves nothing.
        out.append("".join(buf).rstrip())
    return "\n".join(out)


def code_of(text: str) -> list[str]:
    """The COMMENT-STRIPPED lines with the BLANK ones dropped.

    THE HOUSE FIX. A comment-only edit may add or remove a blank line -- a comment
    block that grows pushes the blank line after it down -- and a proof that reads that
    as a code change is a proof that has to be argued with on every file."""
    return [ln for ln in strip_comments(text).split("\n") if ln.strip()]


def git_blob(rev: str, path: str) -> str | None:
    """The bytes of `<rev>:<path>`, or None when the path is not in that revision."""
    p = subprocess.run(("git", "--no-optional-locks", "cat-file", "blob", f"{rev}:{path}"),
                       cwd=ROOT, capture_output=True, text=True)
    if p.returncode:
        return None
    return p.stdout


def judge(before: str, after: str) -> tuple[bool, str]:
    """`(is_comment_only, why)` for one file's two texts."""
    b, a = code_of(before), code_of(after)
    if b == a:
        return True, f"{len(a)} code lines, byte-identical after the comments are stripped"
    for i, (x, y) in enumerate(zip(b, a)):
        if x != y:
            return False, f"code line {i + 1} differs: {x.strip()!r} -> {y.strip()!r}"
    return False, (f"the code has {len(b)} lines before and {len(a)} after -- the edit "
                   f"added or removed CODE")


def self_test() -> int:
    """THE TWO WRONG SHAPES, MEASURED, plus the control that must pass."""
    original = ("def f(x: Int) -> Int:\n"
                "  match x:\n"
                "    case 1: 2\n"
                "    case _: 3\n")
    cases = [
        ("CONTROL -- a whole-line comment", original + "# a comment on its own line\n",
         True, "a comment line is comment-only"),
        ("WRONG-SHAPE-A -- a comment between a pattern and its body",
         original.replace("    case 1: 2\n", "    case 1: # a comment swallowed the body\n"),
         False, "the body of the arm is DELETED and the file may still compile"),
        ("A CODE EDIT -- a changed literal", original.replace("case 1: 2", "case 1: 9"),
         False, "the edit changed code, so it is not comment-only"),
        ("A BLANK-LINE EDIT -- a blank line added", original.replace("  match x:\n",
                                                                    "  match x:\n\n"),
         True, "a blank line is not code, so the edit is still comment-only"),
    ]
    bad = 0
    for name, text, want, why in cases:
        got, detail = judge(original, text)
        mark = "OK " if got == want else "BAD"
        print(f"  {mark} {name:<62} comment-only={got!s:<5} {why}")
        print(f"      :: {detail}")
        if got != want:
            bad += 1
    print(f"\n=== self-test: {'FAIL' if bad else 'PASS'}: {bad} wrong answer(s) ===")
    return FAIL if bad else PASS


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    base = "HEAD"
    if "--base" in argv:
        base = argv[argv.index("--base") + 1]
    paths = [a for a in argv if not a.startswith("--") and a not in (base,)]
    if "--all" in argv:
        paths = []
        for dp, dn, fn in os.walk(ROOT / "tinybendygrad"):
            dn[:] = [d for d in dn if d != "__pycache__"]
            paths += [str(Path(dp, f).relative_to(ROOT)) for f in fn if f.endswith(".bend")]
    if not paths:
        print("# comment-only-gate: REFUSED -- no paths were named", file=sys.stderr)
        return REFUSED
    bad = 0
    for rel in sorted(paths):
        live = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        before = git_blob(base, rel)
        if before is None:
            print(f"  REFUSED {rel} -- the path is not in {base}")
            bad += 1
            continue
        ok, why = judge(before, live)
        if not ok:
            print(f"  NOT-COMMENT-ONLY {rel}  {why}")
            bad += 1
    print(f"=== comment-only vs {base}: {'FAIL' if bad else 'PASS'}: "
          f"{len(paths)} file(s), {bad} not comment-only ===")
    return FAIL if bad else PASS


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
