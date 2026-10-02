#include <math.h>
extern void ext_fn(int);
extern int ext_data;
int gdata = 7;
double helper(double x, int n) { double s=0; for(int i=0;i<n;i++) { s += x*sin((double)i)+sqrt(x); ext_fn(i); } return s; }
int main(void) { return (int)helper(1.5, 3) + ext_data + gdata; }
int bump(void) { return gdata + ext_data; }
