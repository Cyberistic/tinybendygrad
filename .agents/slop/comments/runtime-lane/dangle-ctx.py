import importlib.util, pathlib, sys, re
ROOT=pathlib.Path(__file__).resolve().parents[4]
spec=importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc=importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
only=sys.argv[1] if len(sys.argv)>1 else ""
CONT=re.compile(r"[.!?:,]\s*$|[\)\]\}`'\"_]\s*$|\b(AND|OR|BUT|THE|A|AN|OF|TO|FOR|WITH|IS|WAS|THAT|IT)\s*$",re.I)
for f,ln,blk in cc.blocks():
    rel=str(f.relative_to(cc.PORT))
    if only and not rel.startswith(only): continue
    if len(blk)<2: continue
    if sum(1 for l in blk if l.strip().startswith("# |"))>=3: continue
    if any(l.strip().startswith("# ---") for l in blk): continue
    last=blk[-1].strip(); body=last.lstrip("#").strip()
    if not body or CONT.search(body): continue
    print(f"##### {rel}:{ln+len(blk)-1}")
    for b in blk: print("   ",b)
    print()
