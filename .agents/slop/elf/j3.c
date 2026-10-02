extern int ext_data;
extern void ext_fn(int);
static int tab[4] = {1,2,3,4};
int gdata = 7;
int f(int x) { return tab[x&3] + ext_data; }
int g(int x) { int y = f(x); ext_fn(y); return y + gdata; }
