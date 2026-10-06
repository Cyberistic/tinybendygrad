/* core_harness.c -- the tiny C harness for lane 1.
 *
 * Bend emits ONE C file per program, and that file owns `main`: it parses the
 * runtime's own flags, then hands the rest to IO.args, which is where
 * core.bend reads its payload from.  So the harness does two things and no
 * more:
 *
 *   1. links against that file with -Dmain=bend_main, which renames the
 *      emitted entry point instead of colliding with the harness's own;
 *   2. calls it, forwarding argv, so the C lane runs the same program on the
 *      same payload as every other lane.
 *
 * Nothing here parses or formats anything: any number printed by this lane
 * came out of the emitted C.  The exit code is the program's own.
 */
int bend_main(int argc, char** argv);

int main(int argc, char** argv) {
  return bend_main(argc, argv);
}
