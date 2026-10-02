extern void ext_fn(int);
extern int ext_data;
int gdata = 7;
double helper(double x, int n) { double s=0; for(int i=0;i<n;i++) { s += x*(double)i; ext_fn(i); } return s + ext_data; }
int bump(void) { return gdata + ext_data; }
