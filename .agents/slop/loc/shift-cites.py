#!/usr/bin/env python3
"""shift-cites.py -- move a port citation's line number with the line it names.

    .venv/bin/python .agents/slop/loc/shift-cites.py --base DIR [--apply]

`blank.py` deleted 3,802 blank lines from 192 port files, and this tree cites
positions: `uop/fold.bend:630` means the construct at that line. Deleting a line
above a construct moves it, and a pointer left behind is a wrong answer that
still reads like a citation -- `gates/bendcite-gate.py` went from 545 of 1320
pointers failing to 800 (measured 2026-11-11, HEAD^ against HEAD).

`--base` is a checkout of the tree BEFORE the deletion. The mapping is exact
because the deletion is: every removed line was blank, so a citation to old line
`n` names new line `n - (removed lines before n)`. A pointer that was already
wrong stays equally wrong, which is the property that makes this a shift and not
a repair -- `bendcite` returning to its 545 is the check.

Four spellings are resolved the way `bendcite` resolves them -- the full path,
the path under `tinybendygrad/`, `dir/basename`, and a bare basename when it is
unique in the port. A basename that is not unique is left alone, because the
citation does not say which file it means and a guess is a new wrong answer.
"""

import argparse
import difflib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# The subject is a PATH, and a path's last component may itself carry a colon
# (`mixin/dtype.bend:350`); what matters is that the SUBJECT is a file the
# port owns and the NUMBER is a line in it. So the subject is matched loosely
# and the file is resolved against the port's own list afterwards.
CITE = re.compile(r"(?P<subj>[A-Za-z0-9_][\w/.-]*\.bend):(?P<n>\d+)(?:-(?P<n2>\d+))?")


def removed_lines(old: list[str], new: list[str], rel: str, other: list) -> set[int]:
    """1-based indices of `old` that the collapse dropped.

    The walk is a DIFF, not a subsequence match: two blank lines are equal to
    each other, so "the new file is a subsequence of the old one" is true of many
    alignments and says nothing about WHICH blank went. `difflib` gives the
    alignment, and every hunk here must be a deletion of blank lines -- the
    assert is the proof that the two files differ only in blanks.
    """
    gone: set[int] = set()
    matcher = difflib.SequenceMatcher(a=old, b=new, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        if tag != "delete":
            # A `replace` is a blank removed AND text moved: the collapse deleted
            # one blank and the file's own text moved up. The blank is still a
            # blank, and the rest is another unit's edit -- so the blank half is
            # mapped and the text half is refused below.
            if tag == "replace" and (i2 - i1) == (j2 - j1) + 1:
                for i in range(i1, i2):
                    if old[i].strip() == "":
                        gone.add(i + 1)
                    else:
                        other.append((rel, i + 1, old[i]))
                continue
            other.append((rel, i1 + 1, old[i1]))
            continue
        for i in range(i1, i2):
            if old[i].strip() == "":
                gone.add(i + 1)
            else:
                # A DELETION THAT CARRIES TEXT is not a blank removal: it is
                # another unit's edit, and this file was dirty when `blank.py`
                # ran. Such a file is not a shift -- it is somebody else's work --
                # so it is refused here rather than silently mapped.
                other.append((rel, i + 1, old[i]))
    return gone


SUFFIXES = (".bend", ".py", ".md", ".rows", ".tsv", ".json", ".sh", ".js", ".mjs", ".c")


def tracked_files() -> list[Path]:
    """The tree's own files, and nothing else.

    `ROOT.rglob("*")` walks `.git` (10,808 objects), `references/` (a vendored
    tree) and `.agents/slop/` (1,036 `.bend` files), which is why the first run
    took longer than fifteen minutes. The population is `git ls-tree -r HEAD`,
    which is the tree's own declaration of what it owns.
    """
    out = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], capture_output=True,
                         text=True, cwd=ROOT).stdout.split()
    return [ROOT / name for name in out if Path(name).suffix in SUFFIXES]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    base = Path(args.base)
    changed = subprocess.run(
        ["git", "ls-tree", "-r", "HEAD^", "--name-only", "--", "tinybendygrad"],
        capture_output=True, text=True, cwd=ROOT,
    ).stdout.split()
    changed = [p for p in changed if p.endswith(".bend")]

    shift: dict[str, dict[str, set[int]]] = {}
    changed_by_blank: set[str] = set()
    other: list = []
    for rel in changed:
        old_text = (base / rel).read_text()
        new_text = (ROOT / rel).read_text()
        if old_text == new_text:
            continue
        gone = removed_lines(old_text.split("\n"), new_text.split("\n"), rel, other)
        if gone:
            shift[rel] = gone
            changed_by_blank.add(rel)

    if other:
        print(f"  {len(other)} lines in {len({r for r,_,_ in other})} files are NOT blank removals -- refused:",
              file=sys.stderr)
        for rel, n, line in other[:10]:
            print(f"    {rel}:{n}  {line[:70]}", file=sys.stderr)

    # A citation spells its subject as `ops.bend`, `uop/ops.bend` or
    # `tinybendygrad/uop/ops.bend`, and `mixin/dtype.bend` is spelled with the
    # directory but WITHOUT the `tinybendygrad/` prefix. So a spelling is
    # matched by its SUFFIX: the subject ends with the path, and the part
    # before it is the tree's own prefix. `dtype.bend` alone is ambiguous and
    # is left alone.
    spellings: dict[str, str] = {}
    for rel in shift:
        inner = rel.split("/", 1)[1]
        spellings[rel] = rel
        spellings[inner] = rel
        name = Path(rel).name
        if sum(1 for r in changed if Path(r).name == name) == 1:
            spellings[name] = rel

    def resolve(subject: str) -> str | None:
        """The port file a citation's subject names, or None.

        A BARE basename is ambiguous and is NOT resolved by guessing: the tree
        has two `movement.bend` and two `dtype.bend` files, so `movement.bend:316`
        says nothing about which one it means. A citation that names a file
        ambiguously cannot be moved, and the refusal is the honest answer --
        `bendcite-gate.py` counts those by UNCLAIMED, not as wrong.
        """
        if subject in spellings:
            return spellings[subject]
        hits = [r for r in shift if r.endswith("/" + subject) or r == subject]
        return hits[0] if len(hits) == 1 else None

    cache: dict[str, str] = {}
    total = 0
    for path in tracked_files():
        if not path.is_file():
            continue
        # The file must not have MOVED ITSELF: a citation's line number is
        # about the file it names, and a file that changed under the shift
        # (another unit's edit) has no mapping. Those are refused, and the
        # refusal is printed.
        rel = str(path.relative_to(ROOT))
        if rel in shift and rel not in changed_by_blank:
            print(f"  REFUSED {rel}: it changed for another reason", file=sys.stderr)
            continue
        # ONLY the port's own comments cite a port file's line. A `.py` under
        # `.agents/slop/` is a scratch copy of a gate and its numbers are its
        # own; `checks/census.tsv` is a CRLF file whose bytes must not move; and
        # a `.rows` artifact is a measurement. So the population is the PORT and
        # the GATES that judge it, and the tree says so by name.
        rel = str(path.relative_to(ROOT))
        if not (rel.startswith("tinybendygrad/") or rel.startswith("gates/")):
            continue
        text = path.read_text(errors="surrogateescape")
        out, hit = [], 0
        pos = 0
        for m in CITE.finditer(text):
            rel = resolve(m.group("subj"))
            if rel is None:
                continue
            n = int(m.group("n"))
            gone = shift[rel]
            if not 1 <= n <= 10**6:
                continue
            new_n = n - sum(1 for g in gone if g < n)
            n2 = m.group("n2")
            new_n2 = None
            if n2 is not None:
                new_n2 = int(n2) - sum(1 for g in gone if g < int(n2))
            if new_n == n and (new_n2 is None or new_n2 == int(n2)):
                continue
            out.append(text[pos : m.start("n")])
            out.append(str(new_n))
            if new_n2 is not None:
                out.append("-" + str(new_n2))
            pos = m.end("n2") if n2 is not None else m.end("n")
            hit += 1
        if hit:
            out.append(text[pos:])
            total += hit
            cache[str(path.relative_to(ROOT))] = "".join(out)
            if args.apply:
                path.write_text("".join(out), errors="surrogateescape")
            else:
                print(f"  {hit:3d}  {path.relative_to(ROOT)}")

    print(f"  {total} citations shifted in {len(cache)} files"
          + ("" if args.apply else "  (dry run; --apply writes them)"), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
