/* addrprobe.c -- THE `Nat` POINTER QUESTION, ANSWERED BEFORE IT WAS RELIED ON.
 *
 * A `Term` is one 64-bit word and a Bend `Nat` is a double, so a real address can
 * only cross the FFI if it fits under 2^51 -- the MEASURED `Nat` ceiling, since
 * 2^52-1 aborts. This prints the heap and the stack addresses of THIS machine and
 * states the comparison, so the claim in STAGE2.md rests on a measurement rather
 * than on the fact that the lanes happened to pass.
 *
 *     cc -O0 addrprobe.c -o addrprobe && ./addrprobe && ./addrprobe
 *
 * WHY A LITERAL WOULD BE THE WRONG EXPECTATION: these addresses are ASLR-dependent
 * and change on every run. `ffi-experiment/EXPECTED.md` (E8) records the same
 * lesson for the same reason -- the invariant is that C and Bend agree about the
 * SAME PROCESS's address, never that either equals a constant.
 */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
  void *a = malloc(4096), *b = malloc(4096);
  int x;
  unsigned long long m = (unsigned long long)a, s = (unsigned long long)&x;
  printf("MALLOC 0x%llx = %llu   under_2p51 %d  under_2p48 %d\n",
         m, m, m < (1ULL << 51), m < (1ULL << 48));
  printf("STACK  0x%llx = %llu   under_2p51 %d  under_2p48 %d\n",
         s, s, s < (1ULL << 51), s < (1ULL << 48));
  printf("ceilings: 2^51-1 = %llu   2^48-1 = %llu\n",
         (1ULL << 51) - 1, (1ULL << 48) - 1);
  printf("two mallocs distinct: %d\n", a != b);
  return 0;
}
