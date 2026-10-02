extern int ext_data;
int gdata = 7;
int f(int x) { return gdata + x; }
int g(int x) { return f(x) + ext_data; }
