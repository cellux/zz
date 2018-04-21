#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "buffer.h"

#define nearest_multiple_of(a, b) \
  (((b) + ((a) - 1)) & ~((a) - 1))

size_t zz_buffer_resize(zz_buffer_t *self, size_t new_cap) {
  if (self->cap == 0) {
    fprintf(stderr, "zz_buffer_resize(): attempt to resize externally owned data\n");
    exit(1);
  }
  new_cap = nearest_multiple_of(ZZ_BUFFER_DEFAULT_CAPACITY, new_cap);
  self->ptr = realloc(self->ptr, new_cap);
  if (!self->ptr) return 0;
  self->cap = new_cap;
  if (self->cap < self->len) {
    self->len = self->cap;
  }
  return self->cap;
}

size_t zz_buffer_append(zz_buffer_t *self, const void *data, size_t size) {
  if (self->cap == 0) {
    fprintf(stderr, "zz_buffer_append(): attempt to change externally owned data\n");
    exit(1);
  }
  size_t new_len = self->len + size;
  if (new_len > self->cap) {
    if (!zz_buffer_resize(self, new_len)) {
      return 0;
    }
  }
  memcpy(self->ptr + self->len, data, size);
  self->len = new_len;
  return size;
}

int zz_buffer_equals(zz_buffer_t *self, zz_buffer_t *other) {
  return (self->len == other->len) &&
    (self->len == 0 || (0 == memcmp(self->ptr, other->ptr, self->len)));
}
