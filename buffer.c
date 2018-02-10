#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "buffer.h"

#define nearest_multiple_of(a, b) \
  (((b) + ((a) - 1)) & ~((a) - 1))

void zz_buffer_init(zz_buffer_t *self,
                    uint8_t *data,
                    size_t size,
                    size_t capacity) {
  self->data = data;
  self->size = size;
  self->capacity = capacity;
}

zz_buffer_t * zz_buffer_new() {
  return zz_buffer_new_with_capacity(ZZ_BUFFER_DEFAULT_CAPACITY);
}

zz_buffer_t * zz_buffer_new_with_capacity(size_t capacity) {
  zz_buffer_t *self = malloc(sizeof(zz_buffer_t));
  if (!self) {
    return NULL;
  }
  uint8_t *data = calloc(capacity, 1);
  if (!data) {
    free(self);
    return NULL;
  }
  size_t size = 0;
  zz_buffer_init(self, data, size, capacity);
  return self;
}

zz_buffer_t * zz_buffer_new_with_copy(void *data, size_t size) {
  zz_buffer_t *self = zz_buffer_new_with_capacity(size);
  memcpy(self->data, data, size);
  self->size = size;
  return self;
}

zz_buffer_t * zz_buffer_new_with_data(void *data, size_t size) {
  zz_buffer_t *self = malloc(sizeof(zz_buffer_t));
  if (!self) {
    return NULL;
  }
  /* capacity=0 means we are not responsible for freeing data */
  zz_buffer_init(self, data, size, 0);
  return self;
}

size_t zz_buffer_resize(zz_buffer_t *self, size_t n) {
  if (self->capacity == 0) {
    fprintf(stderr, "zz_buffer_resize(): attempt to resize externally owned data\n");
    exit(1);
  }
  n = nearest_multiple_of(ZZ_BUFFER_DEFAULT_CAPACITY, n);
  self->data = realloc(self->data, n);
  if (!self->data) return 0;
  self->capacity = n;
  if (self->capacity < self->size) {
    self->size = self->capacity;
  }
  return self->capacity;
}

size_t zz_buffer_append(zz_buffer_t *self, const void *data, size_t size) {
  if (self->capacity == 0) {
    fprintf(stderr, "zz_buffer_append(): attempt to change externally owned data\n");
    exit(1);
  }
  size_t new_size = self->size + size;
  if (new_size > self->capacity) {
    if (!zz_buffer_resize(self, new_size)) {
      return 0;
    }
  }
  memcpy(self->data + self->size, data, size);
  self->size = new_size;
  return size;
}

int zz_buffer_equals(zz_buffer_t *self, zz_buffer_t *other) {
  return (self->size == other->size) &&
    (0 == memcmp(self->data, other->data, self->size));
}

void zz_buffer_fill(zz_buffer_t *self, uint8_t c) {
  if (self->capacity == 0) {
    fprintf(stderr, "zz_buffer_fill(): attempt to change externally owned data\n");
    exit(1);
  }
  memset(self->data, c, self->size);
}

void zz_buffer_clear(zz_buffer_t *self) {
  zz_buffer_fill(self, 0);
}

void zz_buffer_reset(zz_buffer_t *self) {
  self->size = 0;
}

void zz_buffer_free(zz_buffer_t *self) {
  /* capacity=0 means we are not responsible for freeing data */
  if (self->data != NULL && self->capacity != 0) {
    free(self->data);
    self->data = NULL;
  }
  free(self);
}
