#include <math.h>
int ext_fn_calls = 0;
void ext_fn(int i) { ext_fn_calls += i; }
int ext_data = 41;
double dsin(double x) { return sin(x); }
