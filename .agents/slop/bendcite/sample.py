import csv, random, sys
rows=[r for r in csv.DictReader(open('.agents/slop/bendcite/rows.rows'), delimiter='\t')]
tier = sys.argv[1]
seed = int(sys.argv[2])
n = int(sys.argv[3])
sel=[r for r in rows if r['verdict']=='WRONG-LINE' and r['tier']==tier]
random.seed(seed)
for r in random.sample(sel, min(n, len(sel))):
    print(f"--- {r['rel']}:{r['at']} -> {r['subject']}:{r['lo']}  claim={r['claim'][:80]}  at_line={r['at_line']}  decl={r['decl']} delta={r['delta']}")
    print(f"    LINE: {r['line'][:125]}")
