#ifndef ZZ_BUFFER
#define ZZ_BUFFER

#include <inttypes.h>

#ifndef ZZ_BUFFER_DEFAULT_CAPACITY
#define ZZ_BUFFER_DEFAULT_CAPACITY 1024
#endif

typedef struct {
  uint8_t *ptr;
  size_t cap; /* 0: we are not responsible for freeing data */
  size_t len;
} zz_buffer_t;

size_t zz_buffer_resize(zz_buffer_t *self, size_t new_cap);
size_t zz_buffer_append(zz_buffer_t *self, const void *data, size_t size);

int zz_buffer_equals(zz_buffer_t *self, zz_buffer_t *other);

#endif
