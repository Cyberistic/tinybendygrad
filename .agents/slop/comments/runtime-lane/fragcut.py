#!/usr/bin/env python3
"""**THE **FRAGMENT **DETECTOR** -- **A **CUT **THAT **REMOVED **THE **MIDDLE **OF **A
**PARAGRAPH **LEFT **A **FRAGMENT**, **⇒⇒† AND **A **FRAGMENT **IS **A **LINE **THAT **ENDS
**ON **A **WORD **THAT **CANNOT **END **A **SENTENCE**.

**⇒⇒† AND **THE **POPULATION **IS **THE **FILE's **OWN **COMMENT **LINES**, **⇒⇒† AND **THE
**DETECTOR **IS **THE **LEXICAL **ONE**: **A **LINE **THAT **ENDS **ON **ONE **OF **THE
**DETERMINERS **AND **CONJUNCTIONS **BELOW **AND **WHOSE **NEXT **LINE **STARTS **A **NEW
**CLAIM**.

**⇒⇒† AND **THE **DETAINERS**: **a/an/the/this/that/these/those/it/its/they/their/
of/to/for/with/in/on/at/from/by/as/and/or/but/if/when/where/which/than/then/so/yet/
also/only/just/still/very/such/per/is/are/was/were/be/been/has/have/had/do/does/did/
not/no/nor/but/**"""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
DET = re.compile(r"\b(a|an|the|this|that|these|those|it|its|they|their|of|to|for|with|in|on|at|from|by|as|and|or|but|if|when|where|which|than|then|so|yet|also|only|just|still|very|such|per|is|are|was|were|be|been|has|have|had|do|does|did|not|no|nor|into|over|under|about|after|before|between|through|during|without|within|upon|above|below|up|down|out|off|again|further|once|here|there|all|any|both|each|few|more|most|other|some|such|own|same|too|can|will|just|should|now)\s*[.:]?\s*$", re.I)
# **⇒⇒† AND **A **NEW **CLAIM **STARTS **WITH **A **CAPITAL**, **A **DIGIT**, **A **`**`,
# **A **`-`**, **OR **A **LIST **MARKER**.
NEWCLAIM = re.compile(r"^\s*#\s*(\*|`|-|\d+[.)]\s|[A-Z])")
only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    for i in range(len(blk)-1):
        a = blk[i].strip()
        if not a.startswith("#") or a == "#": continue
        body = a.lstrip("#").strip()
        if not DET.search(body): continue
        # **⇒⇒† AND **THE **NEXT **LINE **MUST **START **A **NEW **CLAIM**.
        nxt = blk[i+1]
        if not NEWCLAIM.match(nxt): continue
        print(f"{rel}:{ln+i}  {body[:120]}")
