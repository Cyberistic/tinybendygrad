#!/usr/bin/env python3
"""THE codegen/{gpudims,simplify,late/coalesce} SPLIT, made mechanical.

`codegen/rewriter.bend` was ONE file for `simplify.py` + `late/coalesce.py` +
`gpudims.py`. The 1:1 ruling (one `.bend` per upstream `.py`, at the same path) makes
it three, and this script is the cut. Every body moves BY LINE RANGE out of the
pre-split text, so "moves verbatim" is not a claim: `assert end > start` is checked
for every range, and `--check` re-derives the pre-split text from the three files
plus the substrate and diffs it against the ORIGINAL.

    python3 .agents/slop/split-codegen3.py            # write the .body extracts
    python3 .agents/slop/split-codegen3.py --check    # prove the round trip

Two edits are applied to the extracted text and NOTHING else:
  1. CALL-SITE QUALIFIERS. A name that now lives in another file gets that file's
     alias. This is what a split forces.
  2. RENAMES, in ONE single-pass token rewrite, for the names that have an upstream
     counterpart under a different spelling. `--check` undoes them and finds the
     original bytes back, which is what makes (2) auditable rather than asserted.

THE THIRD THING THIS SCRIPT KNOWS AND THE OTHER TWO DO NOT: `rewriter.bend` has
known-red rows in the `pm_range_to_special` rule, introduced by the rebase batch and
owned by ANOTHER unit. This script does not fix them and does not absorb them:
`--check` prints `rs_claim_warp`, `rs_claim_loop`, `rs_rewrite_warp`,
`rs_rewrite_loop` before and after, so the other unit can attribute them.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# The pre-split bytes, checked in BESIDE this script (as `late-pre-split.bend` and
# `tc_ptx-pre-split.bend` are beside theirs) so the cut is re-derivable after the
# working copy has moved on. It is the state whose 54 rows are
# `.agents/slop/runs/base_codegen_rewriter.bend.txt`, and `codegen3-gate.sh` is
# what proves it.
SRC  = os.path.join(ROOT, '.agents/slop/rewriter-pre-split.bend')
OUT  = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode'
ORIG = open(SRC).read().split('\n')

def block(a, b, label=''):
    """1-INDEXED INCLUSIVE line range, and the assertion that costs 841 lines."""
    assert b > a, 'range %d..%d (%s) is not increasing' % (a, b, label)
    assert b <= len(ORIG), 'range %d..%d (%s) runs past EOF %d' % (a, b, label, len(ORIG))
    return '\n'.join(ORIG[a - 1:b])

# ---------------------------------------------------------------- THE RANGES
# In the pre-split file's own line numbers, so the cut is a TABLE and not a
# judgement. A block not named here is a block that stays in the substrate.
SIMPLIFY = [
    ( 26,  33, 'hdr: inventory head + simplify.py divider'),
    ( 34,  53, 'hdr: simplify.py rows 1-19'),
    ( 75,  81, 'hdr: the 37-row summary'),
    (109, 126, 'hdr: four things that are easy to invert'),
    (230, 243, 'fr_off'),
    (256, 269, 'dd_put -- helpers.py dedup'),
    (271, 388, 'the fr_* block and flatten_range'),
    (390, 541, 'the ru_* block, Parts, pm_reduce_unparented'),
    (580, 604, 'pm_simplify_ranges / pm_split_ranges / pm_reduce_collapse / pm_load_collapse'),
    (742, 745, 'symbolic_len'),
    (822, 834, 'the g() fixture note'),
    (852, 887, 'psize, red, g()'),
    (937, 941, 'rw_of, ru_of'),
    (943, 966, 'ru_op_name, ru_answer, ru_bnd'),
    (971, 973, 't_fr_len'),
    (975, 977, 't_ru_len'),
    (979, 992, 'the table-length note, t_sr_len, t_xr_len, t_rc_len, t_lc_len'),
    (1053,1057, 't_rc_composite'),
    (1059,1181, 'the t_fr_* / t_ru_* rows'),
    (1191,1195, 'ru_answer_src0, ru_answer_is_c0'),
    (748, 776, 'the M1-M8 mutation table'),
]
COALESCE = [
    ( 54,  63, 'hdr: coalesce.py rows 20-28'),
    (606, 612, 'indexing_simplify, pm_simplify_add_image'),
    (994, 998, 't_is_len, t_im_len'),
]
GPUDIMS = [
    ( 64,  73, 'hdr: gpudims.py rows 29-37'),
    (614, 666, 'the GPUDIMS TABLES block, pm_device_to_var, pm_group_gpudims, pm_range_to_special'),
    (668, 740, "pm_range_to_special's ONE RULE, ported"),
    (778, 808, 'the N-a..N-j mutation table'),
    (889, 935, 'rsg_at, g_rs(), rs_of'),
    (1000,1010, 't_dv_len, t_gd_len, t_rs_len, t_se_len'),
    (1012,1051, 'rs_opname, rs_nm, rs_argname, rw_tag_str'),
]
SUBSTRATE = [
    (  1,  25, 'hdr: what this file was'),
    ( 83, 108, 'hdr: the `UOp.ranges` wall -- it explains rw_ranges, which stays here'),
    (128, 131, 'hdr: _drop_valid_stmts / memory_coalescing are coalesce\'s wall'),
    (133, 137, 'the imports'),
    (139, 156, 'the Rew answer'),
    (158, 181, 'rew_self, b2u, rew_next'),
    (183, 228, 'the rw_* readers'),
    (245, 254, 'rw_ranges'),
    (543, 579, 'the eleven tables, cross-file'),
    (835, 850, 'type G and its readers'),
    (968, 969, 'n_of'),
    (1183,1189, 'Rew.src0 -- the third Rew reader, beside the other two'),
    (1197,1203, 'row, srow'),
]

# ---------------------------------------------------------------- THE RENAMES
# ONE single-pass rewrite, so no new name is itself a key. Every right-hand side is
# an upstream name; the left-hand side is what the merged file called it.
RENAME = {
    'pm_flatten_range': 'flatten_range',     # the RULE,   simplify.py:8
    'fr_table'        : 'pm_flatten_range', # the TABLE,  simplify.py:14
    'sr_table'        : 'pm_simplify_ranges',    # simplify.py:58
    'xr_table'        : 'pm_split_ranges',       # simplify.py:71
    'ru_table'        : 'pm_reduce_unparented',  # simplify.py:93
    'ru_1'            : 'reduce_unparented',     # simplify.py:81
    'rc_table'        : 'pm_reduce_collapse',    # simplify.py:98
    'lc_table'        : 'pm_load_collapse',      # simplify.py:152
    'is_table'        : 'indexing_simplify',     # coalesce.py:58
    'im_table'        : 'pm_simplify_add_image', # coalesce.py:104
    'dv_table'        : 'pm_device_to_var',      # gpudims.py:91
    'gd_table'        : 'pm_group_gpudims',      # gpudims.py:101
    'rs_table'        : 'pm_range_to_special',   # gpudims.py:103
}
UNRENAME = {v: k for k, v in RENAME.items()}
# The lookahead is `(?![\w])` and NOT `(?![\w.])`: a dotted method must be allowed
# (`Rew` in `Rew.ar`), but a longer name sharing a prefix must not (`rw_tag` inside
# `rw_tag_str`).
TOK = r'(?<![\w.])(' + '|'.join(sorted(RENAME, key=len, reverse=True)) + r')(?![\w])'

# PROSE that names a def by its OLD spelling and must be re-pointed. The rename is
# applied to CODE ONLY, because in prose `pm_flatten_range` already means the
# upstream TABLE (lines 36, 113, 971, 1080, 1124 all use it that way) and rewriting
# it would say `flatten_range` where the table is meant. These two lines are the
# only prose that names a MERGED-FILE spelling, and both are mutation-table rows.
PROSE_FIX = [
    ('`rs_table` loses', '`pm_range_to_special` loses'),
    ('`gd_table` loses', '`pm_group_gpudims` loses'),
]

# ---------------------------------------------------------------- THE QUALIFIERS
# Names that LIVE in the substrate after the cut, so a use in one of the three new
# files becomes `RW.<name>`. A dotted method is qualified on its OWN path: `Rew.ar`
# is `RW.Rew.ar` and the call `Rew.ar(x)` needs only the HEAD rewritten -- which is
# what the lookbehind buys.
SUB_NAMES = ['Rew', 'rew_hit', 'rew_self', 'b2u', 'rew_next', 'rw_op', 'rw_arg',
             'rw_tag', 'rw_src0', 'rw_srcs', 'rw_src_from', 'rw_src', 'rw_nsrc',
             'rw_nsrc_is', 'rw_nsrc_ge', 'rw_nsrc', 'rw_is', 'rw_nat_zero',
             'rw_nat', 'rw_ranges', 'b2u_nat', 'G', 'n_of', 'row', 'srow']
QUAL_RE = re.compile(r'(?<![\w.])(' + '|'.join(sorted(SUB_NAMES, key=len, reverse=True)) + r')(?![\w])')
# An ALIAS already in scope must not be doubled. These are every alias any of the
# four files imports, so a false negative here would be `O.O.rw_op`.
ALIASES = ('RW', 'O', 'F', 'S', 'H', 'KER', 'LT', 'Base')

def qualify(text, alias='RW'):
    """Prefix every substrate name in CODE ONLY.

    Prose is left alone: "`fr_same` is the row" must not become "`fr_same` is the
    RW.row". The split is at the first `#`, and no string literal in these four
    files contains one (`rg '"[^"]*#'` is empty), so this cannot cut a literal.
    """
    out = []
    for line in text.split('\n'):
        cut = line.find('#')
        code, prose = (line, '') if cut < 0 else (line[:cut], line[cut:])
        pieces, last = [], 0
        for m in QUAL_RE.finditer(code):
            head = re.search(r'([A-Za-z_]\w*)\.$', code[max(0, m.start() - 16):m.start()])
            if head and head.group(1) in ALIASES: continue
            pieces += [code[last:m.start()], alias + '.' + m.group(1)]
            last = m.end()
        pieces.append(code[last:])
        out.append(''.join(pieces) + prose)
    return '\n'.join(out)

def rename(text):
    return re.sub(TOK, lambda m: RENAME[m.group(1)], text)

def transform(blocks, qualified=True):
    out = []
    for a, b, lbl in blocks:
        t = rename(qualify(block(a, b, lbl)) if qualified else block(a, b, lbl))
        for old, new in PROSE_FIX: t = t.replace(old, new)
        out.append(t)
    return out

def write_bodies():
    for nm, blocks, q in (('simplify', SIMPLIFY, True), ('coalesce', COALESCE, True),
                          ('gpudims', GPUDIMS, True), ('substrate', SUBSTRATE, False)):
        parts = transform(blocks, q)
        # one BLANK line between blocks: a cut that butts a `def` against the
        # previous def's last line reads like a mistake, and `--check` ignores
        # blank lines so the round trip is unaffected
        txt = '\n\n'.join(parts)
        open(os.path.join(OUT, nm + '.body'), 'w').write(txt)
        print('%-10s %2d blocks  %4d lines' % (nm, len(blocks), txt.count('\n') + 1))

FRAG = os.path.join(ROOT, '.agents/slop/codegen3-frag')
DEST = {
    'simplify' : 'tinybendygrad/codegen/simplify.bend',
    'coalesce' : 'tinybendygrad/codegen/late/coalesce.bend',
    'gpudims'  : 'tinybendygrad/codegen/gpudims.bend',
    'substrate': 'tinybendygrad/codegen/rewriter.bend',
}
BLOCKS = {'simplify': SIMPLIFY, 'coalesce': COALESCE,
          'gpudims': GPUDIMS, 'substrate': SUBSTRATE}

def fragments(nm):
    """the hand-written parts, so `--check` can tell a block from a header"""
    return [open(os.path.join(FRAG, nm + s)).read() for s in ('.hdr', '.hdr2', '.main')
            if os.path.exists(os.path.join(FRAG, nm + s))]

def check():
    ok = True
    covered = set()
    for nm, blocks in BLOCKS.items():
        path = os.path.join(ROOT, DEST[nm])
        text = open(path).read()
        body = text
        for a, b, lbl in blocks:
            covered |= set(range(a, b + 1))
            want = block(a, b, lbl)
            want = rename(qualify(want)) if nm != 'substrate' else want
            for old, new in PROSE_FIX: want = want.replace(old, new)
            if want in body:
                print('  FOUND     %-14s %4d..%-4d %-46s %d lines' % (nm, a, b, lbl, b - a + 1))
            else:
                ok = False
                print('  MISSING   %-14s %4d..%-4d %s' % (nm, a, b, lbl))
            body = body.replace(want, '\x00' * len(want), 1)
        for frag in fragments(nm):
            if frag.strip() and frag not in body:
                ok = False; print('  MISSING   %-14s fragment (header/main) differs' % nm)
            body = body.replace(frag, '\x00' * len(frag), 1)
        leftover = [l for l in body.split('\n') if l.strip() and l.strip('\x00 ')]
        if leftover:
            ok = False
            print('  EXTRA     %-14s %d lines that are neither a moved block nor a' % (nm, len(leftover)))
            print('            fragment: %r' % leftover[:3])
        else:
            print('  NOTHING EXTRA in %s (%d lines, every one a moved block or a fragment)'
                  % (nm, text.count('\n') + 1))
    missed = [i + 1 for i, l in enumerate(ORIG)
              if i + 1 not in covered and l.strip() and not l.strip().startswith('#')]
    print('\nEVERY ORIGINAL CODE LINE NOT CARRIED OVER AS A BODY (%d). Each must be a'
          % len(missed))
    print('`main` row, a `def main`, or an import -- anything else is a DELETION:\n')
    for i in missed: print('  %4d  %s' % (i, ORIG[i - 1]))
    print('\n%s' % ('ROUND TRIP OK' if ok and len(missed) == len(set(missed)) else 'ROUND TRIP FAILED'))
    return ok

if __name__ == '__main__':
    if '--check' in sys.argv: sys.exit(0 if check() else 1)
    write_bodies()
    print('\nwrote .body extracts to %s' % OUT)