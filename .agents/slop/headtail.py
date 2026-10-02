#!/usr/bin/env python3
"""headtail.py -- for each HEADTAIL hit, decide whether the cons is a STRUCTURAL
tail (correct as written) or an ACCUMULATOR that nobody reverses (the bug).

`List.append(a, A, xs, ys)` IS `xs ++ ys`, so `List.append(a, A, [x], acc)` CONSES
and builds a list BACKWARDS.  Two things can make that right:

  STRUCTURAL   `acc` is not an accumulator at all -- it is the matched tail
               (`case x <> acc:`) or a rebuilt tail (`[h] ++ rest` where `rest`
               is the def's own result).  Consing the head in front is the whole
               point.  Nothing to reverse.

  ACC+REVERSE  `acc` IS an accumulator, and a `List.reverse(.., .., acc)` on the
               way out undoes the cons: `sz.bend`'s `added.rs`/`added`,
               `helpers.bend`'s `ansistrip.done2`, `mxm_pick.go`/`mxm_pick`.

  ACC+BARE     `acc` IS an accumulator and no caller reverses it.  THE BUG.
               `mixin/movement.bend`'s `mx_pool_f` was exactly this: it answered
               `f_` backwards and all 70 of its gate rows were constant fixtures,
               so the direction was unobservable.

The verdict is read from SOURCE in both directions -- is `acc` bound by a `<>`
pattern, and does any CALLER reverse it -- and the deciding line is printed with
each row so the split can be hand-read.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SWEEP = os.path.join(ROOT, ".agents/slop/bendcall-sweep.py")

DEF_RE = re.compile(r"^def\s+([A-Za-z_][\w.]*)\s*\(")
HIT_RE = re.compile(r"\[HEADTAIL\] (\S+?):(\d+): List\.append\('[^']*', '[^']*', "
                    r"'(\[[^\]]*\])', '([^']*)'\)")
REV_RE = re.compile(r"List\.reverse\([^)]*\)")
CALL_RE = re.compile(r"\b([A-Za-z_][\w.]*)\s*\(")
NOTDEFS = {"List", "U32", "Nat", "Bool", "String", "F32", "F64", "Maybe", "IO",
           "Array", "Map", "Set", "Cmp", "Char", "Sigma", "Pair", "Result", "Or",
           "And", "IO2", "File", "IO"}


def all_defs(path: str) -> dict[str, tuple[int, str]]:
    lines = open(path).read().split("\n")
    out, i = {}, 0
    while i < len(lines):
        m = DEF_RE.match(lines[i])
        if not m:
            i += 1
            continue
        body, j = [], i
        while j < len(lines):
            if j > i and DEF_RE.match(lines[j]):
                break
            body.append(lines[j])
            j += 1
        out[m.group(1)] = (i + 1, "\n".join(body))
        i = j
    return out


def _args_at(s: str, open_at: int) -> str | None:
    depth, i, n = 0, open_at, len(s)
    while i < n:
        if s[i] == "(":
            depth += 1
        elif s[i] == ")":
            depth -= 1
            if depth == 0:
                return s[open_at + 1:i]
        i += 1
    return None


def _selfcalls_with(body: str, name: str, binder: str) -> list[str]:
    """Every balanced-paren argument list of a `name(...)` call naming `binder`."""
    out = []
    for m in re.finditer(r"(?<![.\w])" + re.escape(name) + r"\s*\(", body):
        inner = _args_at(body, m.end() - 1)
        if inner and re.search(r"(?<![\w.])" + re.escape(binder) + r"(?![\w.])", inner):
            out.append(inner)
    return out


def main() -> None:
    out = subprocess.run([sys.executable, SWEEP], capture_output=True, text=True,
                         cwd=ROOT).stdout
    hits = [(m.group(1), int(m.group(2)), m.group(3), m.group(4))
            for m in (HIT_RE.search(l) for l in out.split("\n")) if m]
    rels = sorted({h[0] for h in hits})
    files = {rel: all_defs(os.path.join(ROOT, rel)) for rel in rels}

    # reverse call graph: callee name -> {defs that mention it}
    callers: dict[str, set[str]] = defaultdict(set)
    for rel, defs in files.items():
        for nm, (_, body) in defs.items():
            for c in CALL_RE.findall(body):
                if c.split(".")[0] not in NOTDEFS:
                    callers[c].add(nm)

    rows = []
    for rel, line, lit, acc in hits:
        lines = open(os.path.join(ROOT, rel)).read().split("\n")
        k = next(j for j in range(line - 1, -1, -1) if DEF_RE.match(lines[j]))
        name = DEF_RE.match(lines[k]).group(1)
        body = files[rel][name][1]
        dline = files[rel][name][0]
        # 1. STRUCTURAL: `acc` is a `<>` tail binder
        st = re.search(r"<>\s*\+?" + re.escape(acc) + r"\s*:", body)
        if st:
            rows.append(("STRUCTURAL",
                         f"{rel}:{line} `{name}`: `{acc}` is bound by "
                         f"`{st.group(0)}` -- a matched tail, consing is the point"))
            continue
        # 2. NOT A FOLD: `acc` is a plain parameter and this def does not recurse
        #    on itself.  `prepend(self, src)` and `tn_alu.of(.., srcs)` prepend a
        #    SRC to a src list (`UOp(op, src=(self,)+src)`); nothing accumulates.
        #    The header line is dropped so the def's own signature does not count.
        #    The self-call scan is BALANCED-PAREN, because the accumulator is
        #    always nested inside the call that builds it:
        #        mx_pool_f.go(t, u, v, r, List.append(&2, U32, [mx_fs(..)], acc))
        #    A `[^)]*` scan stops at `List.append(`'s close and MISSES it -- which
        #    is exactly the bug it existed to find, so it was measured here.
        hdrless = body.split("\n", 1)[1] if "\n" in body else ""
        if not _selfcalls_with(hdrless, name, acc):
            rows.append(("NOT-A-FOLD",
                         f"{rel}:{line} `{name}`: `{acc}` is a parameter and `{name}` "
                         f"does not recurse on it -- a prepend into a src list"))
            continue
        # 3. A FOLD.  Walk CALLERS IN THIS FILE for a List.reverse on `acc`.
        seen, frontier, paid = set(), [name], None
        while frontier and paid is None:
            nxt = []
            for nm in frontier:
                for caller in callers.get(nm, ()):
                    if caller in seen or caller not in files[rel]:
                        continue
                    seen.add(caller)
                    cbody = files[rel][caller][1]
                    for rv in REV_RE.finditer(cbody):
                        # the reverse is paid either by naming the ACCUMULATOR
                        # (`List.reverse(.., .., acc)`) or by wrapping the FOLD'S
                        # OWN CALL (`List.reverse(.., .., AxisVals.go(xs, Nil{}))`,
                        # which is `AxisVals.str`).  The second form reversed all
                        # four ACC+BARE rows to zero, so it is required.
                        pays = acc in rv.group(0) or name in rv.group(0)
                        if not pays:
                            continue
                        paid = (rel, files[rel][caller][0],
                                cbody[:rv.start()].count("\n") + files[rel][caller][0],
                                caller)
                        break
                    nxt.append(caller)
                if paid:
                    break
            frontier = nxt
        if paid:
            f, cline, at, caller = paid
            rows.append(("ACC+REVERSE",
                         f"{rel}:{line} `{name}`: reversed by `{caller}` at "
                         f"{os.path.relpath(f, ROOT)}:{at}"))
        else:
            rows.append(("ACC+BARE",
                         f"{rel}:{line} `{name}` (def {rel}:{dline}): `{lit} ++ {acc}`"
                         f" -- accumulator, no caller reverses it"))

    for v in ("ACC+BARE", "STRUCTURAL", "ACC+REVERSE", "NOT-A-FOLD"):
        sel = [r for k, r in rows if k == v]
        print(f"\n--- {v}: {len(sel)} ---")
        for r in sorted(sel):
            print("  " + r)
    print(f"\n=== {len(hits)} hits: "
          f"{sum(1 for k,_ in rows if k=='STRUCTURAL')} STRUCTURAL, "
          f"{sum(1 for k,_ in rows if k=='NOT-A-FOLD')} NOT-A-FOLD, "
          f"{sum(1 for k,_ in rows if k=='ACC+REVERSE')} ACC+REVERSE, "
          f"{sum(1 for k,_ in rows if k=='ACC+BARE')} ACC+BARE ===")


if __name__ == "__main__":
    main()