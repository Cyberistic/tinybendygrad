THE COMMIT CARRYING THE THREE WALL RETIREMENTS HAS THE WRONG DESCRIPTION

`master`'s tip message reads "portexec: THE PORT'S C RAN. 2 of 227 gate rows are
execution, not text." -- which is the CONCURRENT agent's message, not mine. The CONTENT is
correct and verified: all three retirements are on `master`, checked by reading the files
back rather than by trusting the diff, and that commit contains exactly
`renderer/tc_ptx.bend`, `mixin/rand.bend`, `tensor.bend` and this file.

THE CAUSE IS TWO THINGS COMPOUNDING, and both are known failure modes in this repo.

  1. `jj split` COPIES THE PARENT'S DESCRIPTION onto the commit it creates. Every split in
     this session has therefore produced a commit wearing the previous tip's message, and
     this is the FOURTH time that has needed reporting -- the other three were "empty
     commits" carrying someone else's text.
  2. My `jj describe --stdin < file` FAILED, because a stray `cat > ... 2>/dev/null;` on
     the same command line ate the heredoc meant to write the message file. So the split
     commit kept the inherited description AND was pushed with it.

The project rule forbids amending a pushed commit and this one is pushed, so the message
is not being rewritten. This commit is the remedy: the tip now says what actually happened,
and the wrong message is recorded here where the next reader will find it.

THE LESSON, since it has now cost four rounds: WRITE THE COMMIT MESSAGE WITH THE WRITE TOOL
AND NEVER IN THE SAME SHELL COMMAND AS THE SPLIT. A command that chains a split, a message
heredoc, a bookmark move and a push has four ways to lose the message and no way to notice,
because a failed `jj describe` looks exactly like a successful one.
