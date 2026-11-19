#include <stdio.h>

void test(float* restrict data0_20, float* restrict data1_12, float* restrict data2_15) {
  for (int Lidx0 = 0; Lidx0 < 5; Lidx0++) {
    int cast0 = ((int)(Lidx0));
    for (int Lidx1 = 0; Lidx1 < 4; Lidx1++) {
      int cast1 = ((int)(Lidx1));
      int cast2 = ((int)(0));
      int alu0 = ((3*0)+(3*cast1));
      int alu1 = (15*0);
      int cast3 = ((int)(1));
      int cast4 = ((int)(2));
      *(data0_20+((cast0+(5*cast1))%20)) = (((data1_12+((cast2+alu0)%12))*(data2_15+((cast0+(5*cast2)+alu1)%15)))+((data1_12+((cast3+alu0)%12))*(data2_15+((cast0+(5*cast3)+alu1)%15)))+((data1_12+((cast4+alu0)%12))*(data2_15+((cast0+(5*cast4)+alu1)%15))));
    }
  }
}
int main(void) {
  float data0_20[20] = {-99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99, -99};
  float data1_12[12] = {1, 2, 3, 0, 1, 2, 3, 1, 0, 2, 0, 1};
  float data2_15[15] = {1, 0, 2, 0, 1, 0, 1, 0, 2, 0, 2, 0, 1, 0, 2};
  test(data0_20, data1_12, data2_15);
  int changed = 0;
  for (int i = 0; i < 20; i++) if (data0_20[i] != -99.0f) changed++;
  printf("changed=%d\n", changed);
  printf("out=");
  for (int i = 0; i < 20; i++) printf("%s%.0f", i ? " " : "", data0_20[i]);
  printf("\n");
  return 0;
}
