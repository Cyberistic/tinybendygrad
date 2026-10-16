// fixture header for the autogen oracle. Exercises every arm of tname() that
// can be reached without an ObjC runtime.
#include <stdint.h>
typedef unsigned char u8;
typedef unsigned int u32;

struct Pair { u32 a; u32 b; };
union U { u32 x; u32 y; };
enum Col { RED = 1, GREEN = 2, BLUE = 7 };
enum Neg { N1 = -1, N2 = 4 };
typedef struct Pair PairAlias;
struct Bits { unsigned int lo : 3; unsigned int hi : 5; unsigned int rest : 24; };
struct Nested { struct Pair inner; unsigned int tail; };
struct Arr { u32 data[4]; u32 n; };
struct FP { double d; float f; };
struct Anon { struct { unsigned int a; unsigned int b; }; unsigned int c; };
enum Plain { PA = 10, PB = 20 };

typedef void (*cb_t)(int, unsigned int);
typedef int (*ret_t)(void);

int  addfn(int a, unsigned int b);
void vfn(void);
double dfn(double x);
struct Pair retstruct(struct Pair p);
void takes_arr(struct Arr *a, u32 n);

#define ONE 1
#define HEXLIT 0xdeadbeef
#define WITHU 42u
#define ADDER(a,b) ((a)+(b))
#define BODY 1 + 2
#define EMPTYish
