#ifndef ZZ_BUFFER
#define ZZ_BUFFER

#include <inttypes.h>

#ifndef ZZ_BUFFER_DEFAULT_CAPACITY
#define ZZ_BUFFER_DEFAULT_CAPACITY 1024
#endif

typedef struct {
  uint8_t *data;
  size_t size;
  size_t capacity; /* 0: we are not responsible for freeing data */
} zz_buffer_t;

void zz_buffer_init(zz_buffer_t *self,
                    uint8_t *data,
                    size_t size,
                    size_t capacity);

zz_buffer_t * zz_buffer_new();
zz_buffer_t * zz_buffer_new_with_capacity(size_t capacity);
zz_buffer_t * zz_buffer_new_with_copy(void *data, size_t size);
zz_buffer_t * zz_buffer_new_with_data(void *data, size_t size);

size_t zz_buffer_resize(zz_buffer_t *self, size_t n);
size_t zz_buffer_append(zz_buffer_t *self, const void *data, size_t size);

int zz_buffer_equals(zz_buffer_t *self, zz_buffer_t *other);

void zz_buffer_fill(zz_buffer_t *self, uint8_t c);
void zz_buffer_clear(zz_buffer_t *self);
void zz_buffer_reset(zz_buffer_t *self);

void zz_buffer_free(zz_buffer_t *self);

#endif
