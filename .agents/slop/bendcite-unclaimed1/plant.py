#!/usr/bin/env python3
"""plant.py -- the PLANT for this slice.

**A TEXT EDIT ON A COPY** that breaks ONE re-pointed citation, and a BYTE-IDENTICAL
copy that stays green.  NEVER `git show HEAD:` -- the subject of the plant is a COPY
of the port tree ON DISK, edited as TEXT, so the plant proves the instrument reads
the tree it is pointed at.

THE CITATION CHOSEN IS DISCOVERED, NOT NAMED: the first row in the slice's own
re-pointed set whose verdict is RESOLVES **BY A DECLARATION** (not by a mention),
and whose cited line IS the construct's declaration line.  The plant MOVES that
construct by inserting CODE above it, which is what a unit editing the port does,
and the pointer -- which was AT the declaration -- is now one line above it.

THE CONTROL IS A SECOND COPY OF THE SAME SNAPSHOT, so the two arms compare the
same tree and not two trees.
"""
import collections, importlib.util, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path('/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
WORK = Path('/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/work')

spec = importlib.util.spec_from_file_location('bc', ROOT/'gates/bendcite-gate.py')
bc = importlib.util.module_from_spec(spec); spec.loader.exec_module(bc)

MINE = {l.strip() for l in open(WORK/'mine.txt') if l.strip()}
# THE SLICE'S OWN RE-POINTED CITATIONS: the `symbol=` fields this slice wrote.
SYMBOL = bc.SYMBOL_FIELD


def repointed_rows(rows):
    """The rows whose claim came from a `symbol=` FIELD this slice wrote."""
    out = []
    for r in rows:
        if r['rel'] not in MINE:
            continue
        if not r.get('claims'):
            continue
        if any('=' in c and not c.startswith('_') for c in r['claims']):
            out.append(r)
    return out


def main() -> int:
    snap = WORK / 'plant-snap'
    if snap.exists():
        shutil.rmtree(snap)
    snap.mkdir(parents=True)
    shutil.copytree(ROOT/'tinybendygrad', snap/'tinybendygrad')
    (snap/'references').mkdir()
    (snap/'references'/'bend').symlink_to(ROOT/'references'/'bend')

    base_rows, corpus = bc.census(snap)
    by = collections.Counter(r['verdict'] for r in base_rows)
    print(f"PLANT control : {dict(by)}")

    # THE POINTER MOVED IS DISCOVERED: a RESOLVES row in one of MY files whose claim
    # came from a `symbol=` FIELD this slice wrote, and whose cited line IS the
    # DECLARATION of that symbol -- so the pointer is AT the construct and a text
    # edit that moves the construct moves the pointer's target out from under it.
    target = None
    for r in base_rows:
        if r['rel'] not in MINE or r['verdict'] != 'RESOLVES':
            continue
        if 'symbol=' not in r.get('line', ''):
            continue
        # THE CONSTRUCT THE `symbol=` NAMES MUST BE DECLARED AT THE CITED LINE.  The
        # gate's own `decl` is 0 for the MENTION arm, so the DECLARATION is read
        # from the corpus -- the target file's own construct table.
        names = {n for (n, d, s, e) in corpus.constructs.get(r.get('target', ''), [])}
        decls = [(n, d) for (n, d) in
                 [(n, d) for (n, d, s, e) in corpus.constructs.get(r.get('target', ''), [])]]
        sym = None
        for m in SYMBOL.finditer(r.get('line', '')):
            sym = m.group(1)
            break
        if not sym:
            continue
        if sym not in names:
            continue
        # THE VICTIM IS A PORT FILE, not the COMPILER's: the plant is about the
        # PORT's own substrate, and `references/bend/bend2/` is a RESOLUTION corpus.
        if not r.get('target', '').startswith('tinybendygrad/'):
            continue
        at_decl = [d for (n, d) in decls if n == sym]
        if not at_decl or at_decl[0] != int(r['lo']):
            continue
        target = r
        break
    if target is None:
        print("PLANT REFUSED: no re-pointed declaration-pointer in the slice's own files")
        return 3
    name = target['at_line']
    k = 1
    print(f"PLANT the pointer moved is {target['rel']}:{target['at']} -> "
          f"{target['subject']}:{target['lo']}, and the construct it names is `{name}` "
          f"declared at {target['target']}:{target['decl'] or target['lo']}; "
          f"{k} line(s) are inserted above it")

    moved = WORK / 'plant-moved'
    if moved.exists():
        shutil.rmtree(moved)
    shutil.copytree(snap, moved)
    victim = moved / target['target']
    body = victim.read_text().split('\n')
    # THE EDIT INSERTS CODE DIRECTLY ABOVE THE CONSTRUCT, not at the top of the
    # file: a construct's SPAN includes the comment run above it, so a line
    # inserted ABOVE the file only shifts the declaration and the pointer stays
    # inside the span.  Inserting IMMEDIATELY ABOVE the `def` puts the pointer
    # on the line the new code occupies, which is OUTSIDE the construct.
    # THE EDIT INSERTS CODE, NOT A COMMENT, for the same reason.
    decl = int(target['decl'] or target['lo'])
    body = body[:decl - 1] + ["def plant_probe(x: U32) -> U32: x"] * k + body[decl - 1:]
    victim.write_text('\n'.join(body) + '\n')

    moved_rows, _mc = bc.census(moved)
    after = next((r for r in moved_rows
                  if r['rel'] == target['rel'] and r['at'] == target['at']
                  and r['subject'] == target['subject'] and r['lo'] == target['lo']), None)
    print(f"PLANT control : {target['verdict']}  (the pointer holds)")
    print(f"PLANT moved   : {after['verdict'] if after else '(the row is gone)'}")
    bad = []
    if after is None or after['verdict'] != 'WRONG-LINE':
        bad.append(f"the moved pointer did not go red: {after['verdict'] if after else 'gone'}")
    mv = collections.Counter(r['verdict'] for r in moved_rows)
    print(f"PLANT control : {dict(by)}")
    print(f"PLANT moved   : {dict(mv)}")
    if mv.get('WRONG-LINE', 0) <= by.get('WRONG-LINE', 0):
        bad.append("the moved copy did not add a stale pointer")

    # THE CONTROL IS A SECOND COPY OF THE SAME SNAPSHOT, NOT THE LIVE TREE.
    twin = WORK / 'plant-twin'
    if twin.exists():
        shutil.rmtree(twin)
    shutil.copytree(snap, twin)
    twin_rows, _tc = bc.census(twin)
    if [r['verdict'] for r in twin_rows] != [r['verdict'] for r in base_rows]:
        bad.append("the byte-identical twin did not reproduce the control")
    else:
        print("PLANT twin    : reproduces the control exactly (byte-identical)")

    if bad:
        print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
        return 1
    print("PLANT OK: a text edit that moves the construct makes the re-pointed pointer "
          "stale, and a byte-identical copy does not")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
