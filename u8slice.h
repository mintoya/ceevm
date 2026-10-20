#include "stddef.h"
#include "stdint.h"
typedef struct u8slice u8slice;
struct u8slice {
  size_t len;
  unsigned char *ptr;
};
