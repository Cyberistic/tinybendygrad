extern void ext_fn(int);
extern int ext_data;
int gdata = 7;
static const double tbl[4] = {1.5, 2.5, 3.5, 4.5};
double helper(double x, int n) { double s=0; for(int i=0;i<n;i++) { s += x*tbl[i&3] + (double)i; ext_fn(i); } return s + ext_data; }
int bump(void) { return gdata + ext_data; }
const char *msg = "hello elf";
int _start_c(void) { return (int)helper(1.0,2); }
