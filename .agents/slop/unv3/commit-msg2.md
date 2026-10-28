slop: the citation-slice REPORT and the instruments that made it

The 124 rows this slice closed are the PROSE, and the report says what each
change was and what it measured. The instruments are named for what they measure,
and `mine.py` reads the slice file the orchestrator gave this unit -- the file list
is NEVER written twice.

  REPORT.md      the counts, the four kinds of change, the three verifications, and
                 what was NOT fixed and why
  mine.py       counts the slice rows in a gate rows file
  show.py       the slice remaining unverifiable rows, WITH the port own text
  showb.py      the slice stale .bend pointers, with the construct that IS at the line
  check.sh      measures the slice on a FROZEN COPY of the LIVE tree (--tree DIR)
  decl.py       where a .bend construct is declared, now
  proof.py      the COMMENT-ONLY PROOF, via port-compile-gate.py strip_comments()
  compile.sh    compiles each file, ONE bend at a time, reads the VERDICT TOKEN
  plant.sh      the two plants, on copies
  put.py        puts an upstream token on a citation own line

`work-*/` and `base/` are MEASUREMENT COPIES and are NOT COMMITTED: the base copy
is 479 MB and the plant copy is 1.4 GB, and a frozen `git archive` of HEAD is the
WRONG copy -- the files this slice does not own MOVE, and a pointer into a file
this slice does not own must name the line that file has NOW.
