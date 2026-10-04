#!/usr/bin/env python3
"""
Reorder the defs of a .bend file so every def PRECEDES every def it uses.

bend 2.0.35 refuses a forward reference AND a mutual one:

    expected : a filled definition (an unfilled law is a dead claim:
               live code cannot use it)

so declaration order is load-bearing, and hand-ordering an 85-def emitter is a
trap.  This walks the file, builds the use graph, and topologically sorts.

A def that uses ITSELF is left in place: self-recursion is legal.

Usage: python3 .agents/slop/ag-order.py <file.bend> [--write]

FOUR PARSER PROBLEMS, all of which produce a WRONG FILE RATHER THAN AN ERROR,
which is why each is written down.  The first three cost a rewrite each.

1. `emit_tail` builds a Bend file out of STRING LITERALS, so its body contains
   lines reading `def main() -> IO(Unit):` at column 0.  A `def` inside an
   unclosed `String.concat([` is emitted TEXT.  Bracket depth decides.
2. Counting brackets over RAW LINES is wrong because the emitted header quotes
   prose containing unbalanced parentheses -- `whole-operation effect (\`def
   f(..) -> IO(R)\`` is one -- and a naive count leaves the scanner at a
   non-zero depth forever, after which it silently finds 21 defs in a file with
   72.  Quote state must carry ACROSS lines and only code outside literals
   counts.
3. A leading comment must travel with its def, but the walk back must stop at a
   BLANK LINE.  Walking back over blanks as well makes every def claim the
   PREVIOUS def's comment, and the emitted file duplicates each comment once per
   def below it: 545 lines became 2391 with the section-1 comment repeated 64
   times, and the file still typechecked.
4. Comment blocks must not OVERLAP.  Each block starts at
   max(comment_start, previous_block_end + 1), or the join below emits the same
   lines once per block that claims them.
"""
import pathlib, re, sys

DEF = re.compile(r"^def\s+([A-Za-z_][A-Za-z0-9_.]*)\s*[(:]")
TYPE = re.compile(r"^type\s+([A-Za-z_][A-Za-z0-9_]*)\s+is\b")
USE = re.compile(r"(?<![\w.])([a-z][a-zA-Z0-9_]*(?:\.[a-z][a-zA-Z0-9_]*)*)\s*\(")
BUILTIN = {"List", "String", "Nat", "Bool", "Maybe", "IO", "File", "Result",
           "Unit", "Pair", "Cmp", "Char", "Empty", "Sigma", "Either", "Or",
           "Array", "Map", "Chan", "App", "Event", "Image", "Audio", "Window",
           "Socket", "Listener", "TCP", "UDP", "Process", "Word", "U32", "F32"}


def strip_strings(lines):
    """blank out string-literal CONTENTS, keeping the delimiters.

    Quote state carries ACROSS lines: an unbalanced paren inside a quoted
    comment must not move the bracket depth.
    """
    out, inq = [], False
    for line in lines:
        buf, i = [], 0
        while i < len(line):
            c = line[i]
            if inq:
                if c == "\\" and i + 1 < len(line):
                    i += 2
                    continue
                if c == '"':
                    inq = False
                    buf.append(c)
                else:
                    buf.append(" ")
                i += 1
                continue
            if c == '"':
                inq = True
                buf.append(c)
                i += 1
                continue
            if c == "#":  # whole-line comment: nothing left to scan
                buf.append(" " * (len(line) - i))
                break
            buf.append(c)
            i += 1
        out.append("".join(buf))
    return out


def depth_delta(code: str) -> int:
    return sum(1 for x in code if x in "([") - sum(1 for x in code if x in ")]")


def uses(body_lines) -> set[str]:
    found = set()
    for line in body_lines:
        for m in USE.finditer(line):
            found.add(m.group(1))
    return found - BUILTIN


def block(lines, code, i, depth):
    """(name, body_line_indices) for the def or type starting at line `i`."""
    m = DEF.match(lines[i]) or TYPE.match(lines[i])
    name = m.group(1)
    body, j, d = [i], i + 1, depth_delta(code[i])
    while j < len(lines) and (d != 0 or lines[j].startswith((" ", "\t")) or lines[j] == ""):
        d += depth_delta(code[j])
        body.append(j)
        j += 1
    while body and lines[body[-1]] == "":
        body.pop()
        j -= 1
    return name, body, j, d


def scan(lines, code, pattern):
    out, i, depth = [], 0, 0
    while i < len(lines):
        if not (pattern.match(lines[i]) and depth == 0):
            depth += depth_delta(code[i])
            i += 1
            continue
        name, body, j, d = block(lines, code, i, depth)
        out.append((name, body, j))
        i, depth = j, d
    return out


def main() -> int:
    path = pathlib.Path(sys.argv[1])
    lines = path.read_text().split("\n")
    code = strip_strings(lines)
    bl = scan(lines, code, DEF)
    tys = scan(lines, code, TYPE)

    n_top = sum(1 for l in lines if DEF.match(l))
    if len(bl) != n_top:
        print(f"parser found {len(bl)} defs, grep finds {n_top} -- refusing to reorder",
              file=sys.stderr)
        return 1

    names = {b[0] for b in bl}
    deps = {n: (uses([code[i] for i in body]) & names) - {n} for n, body, _ in bl}
    order, done, pending = [], set(), [b[0] for b in bl]
    while pending:
        ready = [n for n in pending if deps[n] <= done]
        if not ready:
            print(f"CYCLE among {sorted(set(pending))}", file=sys.stderr)
            return 1
        order += ready
        done |= set(ready)
        pending = [n for n in pending if n not in done]

    first = min(b[1][0] for b in bl + tys)
    head = "\n".join(lines[:first]).rstrip("\n")

    # A def's own comment is the CONTIGUOUS `#` run above it, clamped so two
    # blocks never claim the same lines.
    def slice_with_comment(b):
        _, body, end = b
        s = body[0]
        while s - 1 > 0 and lines[s - 1].startswith("#"):
            s -= 1
        return "\n".join(lines[s:end])

    # The EMITTED order is `order`, the topological one. Sorting the blocks back
    # into file order here silently undoes the whole sort, and it fails QUIETLY:
    # the file still typechecks, it is just ordered as it always was, so the tool
    # reports success on every run while `to_tr` stays above `enc`.
    by_name = {b[0]: b for b in bl}
    pos = {n: by_name[n] for n in order}
    out = head + "\n\n\n" + "\n\n\n".join(
        [slice_with_comment(t) for t in tys]
        + [slice_with_comment(pos[n]) for n in order]) + "\n"

    if "--write" in sys.argv:
        path.write_text(out)
        print(f"reordered {len(order)} defs, {len(tys)} types")
    else:
        print("\n".join(f"{i:3d} {n}" for i, n in enumerate(order)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())