extern int ext_data;
int gdata = 7;
int f(int x) { return x * 3 + 1; }
int g(int x) { return f(x) + gdata + ext_data; }
