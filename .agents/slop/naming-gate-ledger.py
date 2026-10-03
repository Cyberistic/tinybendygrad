#!/usr/bin/env python3
"""Write the naming gate's review ledger from a table of HAND-MADE judgements.

    python3 .agents/slop/naming-gate-ledger.py

This decides nothing. It replays rulings made by reading upstream and the port
side by side, and it ASSERTS that every live rename candidate is covered -- so a
new candidate, or a table that has fallen behind, is a loud failure here rather
than a silent `UNREVIEWED` line in the ledger.

An exemption is for ONE EXACT AFFIX on ONE name in ONE file. That precision is
load-bearing: with a coarser key the gate's own self-test planted
`selftest_group_gpudims` (from the reviewed `pm_group_gpudims`) and the gate
stayed green.

THE REASON VOCABULARY is short and greppable, because the ledger is an audit
record, not prose:

  UPSTREAM-PREFIX:   the affix is UPSTREAM's own. Dropping it would invent a name.
  LANG-CONSTRAINED:  Bend cannot express the construct, so the affix is forced by
                     the LANGUAGE, not chosen by a naming preference.
  CONVENTION:        a deliberate, file-local convention. Diverges from upstream
                     on purpose and consistently; changing it needs an owner call.
  COINCIDENCE:       the port def is a DIFFERENT concept that merely shares an
                     affix boundary. Not a rename; the detector cannot know that.
  PORT-LOCAL:        the port def is an extra thing upstream has no name for.
  OWNER-RULING-NEEDED: a real divergence, in a file this unit does not own.

Rules are `(upstream_file, affix_regex, reason)`. `re.fullmatch` decides, so
`_OFF` cannot accidentally cover `_OFFSET`. The regexes are TIGHT and per-file on
purpose: a loose global pattern would exempt exactly the thing the gate exists to
catch. First matching rule wins, so a file may carry several.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('ng', os.path.join(HERE, 'naming-gate.py'))
ng = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ng)

# The eleven accessors upstream's `PacketType` metaclass generates per subclass.
SQTT_ACCESSOR = r'(?:cls|dflt|dlo|dmask_over|dmask|field_order|fields|hasdelta|himax|mask|cu)_.*'
# Any ALL-CAPS PREFIX. In `dsl.py` these are accidents rather than renames:
# upstream binds the two-letter name `OFF` (`NULL = OFF = src[124]`), and every
# one of the port's ~50 `*_OFF` constants affixes it.
DSL_CAPSPREFIX = r'[A-Z0-9_]+_'

RULES = [
    # -- UPSTREAM'S OWN PREFIX. `pm_` is upstream's: `pm_simplify_ranges` and
    #    friends are ASSIGNMENTS in upstream tinygrad, so a port that writes
    #    `pm_group_gpudims` is CONSISTENT and stripping `pm_` would invent a name.
    ('codegen/gpudims.py', r'pm_', 'UPSTREAM-PREFIX:pm_-is-upstreams-own'),
    ('codegen/simplify.py', r'pm_', 'UPSTREAM-PREFIX:pm_-is-upstreams-own'),

    # -- THE ONE PAIR I COULD NOT RENAME. `codegen/decomp/dtype.bend` calls
    #    `T.tx_shr` 10x and `T.tx_shl` 12x through the module alias, and that
    #    file is on the do-not-edit list and mid-edit by another agent. So the
    #    rename is a TWO-FILE change this unit may not make.
    ('codegen/decomp/transcendental.py', r'tx_',
     'OWNER-RULING-NEEDED:22-call-sites-in-do-not-edit-dtype.bend'),
    ('codegen/decomp/transcendental.py', r'_lazy',
     'PORT-LOCAL:shl_lazy-and-shr_lazy-are-the-lazy-port-variants'),

    # -- TYPE VARIABLES AND NEIGHBOURING CLASSES. Upstream binds
    #    `T = TypeVar("T")` at module level and Bend has no type variables, so
    #    there is nothing to name. `Tqdm`/`Tensor`/`Tensors` are upstream CLASSES
    #    that merely share a leading letter with the type variable, and the port
    #    reproduces those VERBATIM -- the affix is an accident of the scan.
    ('helpers.py', r'qdm', 'COINCIDENCE:Tqdm-is-an-upstream-class-not-a-TypeVar-T-rename'),
    ('tensor.py', r'ensors?', 'COINCIDENCE:Tensor-and-Tensors-are-upstream-classes'),
    ('tensor.py', r't_(?:const|repr)', 'PORT-LOCAL:t_-prefixed-test-gates-for-TypeVar-T'),

    # -- MONOMORPHISATION. Upstream `cdiv(x:int, y:int)` and friends are generic
    #    over the element type; Bend has no generics, so the port has one def per
    #    concrete type. This is the LANGUAGE, not a naming preference.
    ('helpers.py', r'_(?:i32|u32|str|nat|sign|seq)(?:_go|_str)?',
     'LANG-CONSTRAINED:no-generics-one-def-per-element-type'),
    # -- NO OVERLOADING. Upstream `make_tuple(x:int|Sequence[int], cnt)` and
    #    `argfix(*x)` branch internally; Bend cannot overload, so each arm is
    #    its own def.
    ('helpers.py', r'_(?:of|rep|bad)', 'LANG-CONSTRAINED:no-overloading-split-by-branch'),
    ('helpers.py', r'_or',
     'OWNER-RULING-NEEDED:unwrap_or-vs-unwrap-helpers.bend-is-do-not-edit'),
    ('helpers.py', r'_nest', 'PORT-LOCAL:all_int_nest-is-a-nested-shape-helper'),

    # -- dsl.bend, the register-slice convention. Upstream `dsl.py:66-89` binds
    #    ONE `Reg` per register region; the port splits each into offset and size
    #    and suffixes the offset, so `EXEC_OFF` cannot be confused with
    #    `EXEC_SZ`. Twelve upstream names take that suffix, consistently across
    #    ~50 constants. Consistent and deliberate, so renaming a SUBSET would
    #    make the file LESS navigable -- which cuts against the ruling's own
    #    stated goal. Largest remaining divergence; an owner decision.
    ('renderer/amd/dsl.py', r'_(?:OFF|off|HI|LO|SZ|MARKER)$|(?:16_OFF|Z_OFF|32_MASK)$',
     'OWNER-RULING-NEEDED:dsl-register-slice-offset-suffix-convention'),
    # `VOP2_DPP`/`VOP2_LIT`/`VOP2_SDWA` are VOP2 OPERAND-SHAPE TABLES, a
    # different concept from upstream's `DPP = src[250]` register slice.
    # Disproven by reading the body, not by assuming.
    ('renderer/amd/dsl.py', r'VOP2_\w*',
     'COINCIDENCE:VOP2-operand-table-not-a-register-slice'),
    ('renderer/amd/dsl.py', DSL_CAPSPREFIX,
     'COINCIDENCE:upstream-two-letter-OFF-affixes-every-*-OFF-constant'),

    # -- sqtt.bend. Upstream's `PacketType` metaclass derives every column of
    #    every subclass from one class; Bend has no metaclass and duplicate
    #    declarations are a compile error (`duplicate declaration: foo`). So one
    #    file needs 11 x 48 distinct names. The affix is the honest encoding of
    #    that LANGUAGE limit, not a namespace invented for convenience.
    ('renderer/amd/sqtt.py', SQTT_ACCESSOR,
     'LANG-CONSTRAINED:sqtt-PacketType-metaclass-fanout'),

    # -- TABLES AND CLASS MEMBERS THAT BECAME ACCESSORS. Upstream binds a dict or
    #    a class; the port exposes the lookups, so the name grows an affix saying
    #    WHICH lookup. Consistent and file-local.
    ('renderer/nir.py', r'_\w+', 'CONVENTION:table-became-accessors'),
    ('uop/render.py', r'_\w+|has_', 'CONVENTION:table-became-accessors'),
    ('uop/validate.py', r'_ops', 'CONVENTION:table-became-accessors'),
    ('runtime/support/c.py', r'_\w+', 'CONVENTION:table-became-accessors'),
    ('runtime/support/hcq2.py', r'.*', 'CONVENTION:table-became-accessors'),
    ('runtime/support/autogen.py', r'.*', 'CONVENTION:table-became-accessors'),
    ('runtime/ops_nv.py', r'_\w+', 'CONVENTION:class-members-flattened'),
    ('runtime/support/usb.py', r'_[A-Z_]+', 'CONVENTION:class-members-flattened'),

    # -- MODULE-ALIAS PREFIXES. The alias is the disambiguator, so `def A.name`
    #    would do without an affix -- but these are files this unit does not own.
    ('mixin/elementwise.py', r'ew_', 'OWNER-RULING-NEEDED:ew_-module-prefix-vs-remint'),
    ('mixin/elementwise.py', r'(?:g_promo|t_dt|t_promo)_',
     'PORT-LOCAL:test-gates-and-a-promo-rule-not-ports-of-remint'),
    ('schedule/memory.py', r'.*', 'OWNER-RULING-NEEDED:mem_-module-prefix'),
    ('uop/symbolic.py', r'.*', 'OWNER-RULING-NEEDED:sy_-module-prefix'),

    # -- UPSTREAM DEFINES THE FUNCTION, THE PORT NAMES IT AFTER ITS ROLE.
    ('renderer/cstyle.py', r'.*', 'OWNER-RULING-NEEDED:hip_ocml-emit_hip_ocml'),
    ('renderer/isa/x86.py', r'_\w+', 'OWNER-RULING-NEEDED:encode_calls'),
    ('runtime/ops_cl.py', r'.*', 'OWNER-RULING-NEEDED:binary_check-and-t_check'),
    ('runtime/support/usb.py', r'_(?:prefix|req|trace)$',
     'OWNER-RULING-NEEDED:_req-and-_trace-suffixes'),
    ('nn/datasets.py', r'.*', 'OWNER-RULING-NEEDED:split-per-dataset-split'),
    ('renderer/llvmir.py', r'_\w+',
     'OWNER-RULING-NEEDED:one-upstream-lconst-four-litmus-rows'),

    # -- DIFFERENT CONCEPTS THAT MERELY SHARE AN AFFIX BOUNDARY. Verified by
    #    hand against upstream; the detector cannot tell these from renames.
    ('engine/realize.py', r'.*',
     'COINCIDENCE:arg_is_validate-is-a-predicate-not-a-port-of-_validate'),
    ('engine/worker.py', r'.*',
     'COINCIDENCE:terminate_worker_pool-is-shutdown-not-the-module-global'),
    ('runtime/ops_bend.py', r'.*', 'COINCIDENCE:LANES_SORTED-is-a-different-value'),
    ('runtime/support/compiler_llvm.py', r'_\w+',
     'COINCIDENCE:cerr_depth-and-cerr_inner-are-different-concepts'),
]

HEADER = """\
# THE NAMING GATE REVIEW LEDGER -- one line per RENAME, four tab-separated fields:
#
#\tupstream_file<TAB>upstream_name<TAB>affix<TAB>reason-it-is-not-a-rename
#
# `naming-gate.py` PROPOSES every (file, name, affix); this file ADJUDICATES. The
# gate FAILS on any proposal with no line here, on any line whose reason is still
# UNREVIEWED, and on any line whose proposal has disappeared (stale amnesty is
# unearned amnesty). An exemption covers ONE exact affix on ONE name in ONE
# file: change the prefix and the gate fires again.
#
# Generated by `naming-gate-ledger.py`, which ASSERTS that every live proposal is
# covered -- so a new rename cannot slip in unreviewed.
#
# ABSENT upstream names are deliberately NOT here. An unported name is missing
# implementation, not a misnomer; the gate counts those separately and does not
# fail on them.
"""


def main():
    _, candidates, _ = ng.census()
    detected = {(rel, name, affix): stem
                for (rel, name), hits in candidates.items()
                for affix, stem in hits}

    reason = {}
    for rel, pattern, why in RULES:
        rx = re.compile(pattern)
        if not any(f == rel and rx.fullmatch(a) for (f, _, a) in detected):
            sys.exit('rule matches nothing live, so it is dead weight: %s / %s'
                     % (rel, pattern))
        for key in sorted(detected):
            if key[0] != rel or key in reason or not rx.fullmatch(key[2]):
                continue
            reason[key] = why

    uncovered = sorted(k for k in detected if k not in reason)
    if uncovered:
        sys.exit('UNCOVERED RENAME(S) -- adjudicate these by hand:\n' +
                 '\n'.join('  %s :: %s  +%s  -> %s' % (k[0], k[1], k[2], detected[k])
                           for k in uncovered))

    with open(ng.LEDGER, 'w') as fh:
        fh.write(HEADER)
        for key in sorted(reason):
            fh.write('%s\t%s\t%s\t%s\n' % (key[0], key[1], key[2], reason[key]))
    print('ledger written: %d rename(s), all adjudicated' % len(reason))


if __name__ == '__main__':
    main()