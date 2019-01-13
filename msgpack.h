#ifndef ZZ_MSGPACK_H
#define ZZ_MSGPACK_H

#include <stdbool.h>

#include "buffer.h"
#include "cmp.h"

typedef struct {
  zz_buffer_t *buffer;
  uint32_t pos;
} zz_cmp_buffer_state;

bool zz_cmp_buffer_reader(struct cmp_ctx_s *ctx, void *data, size_t limit);
bool zz_cmp_buffer_skipper(struct cmp_ctx_s *ctx, size_t count);
size_t zz_cmp_buffer_writer(struct cmp_ctx_s *ctx, const void *data, size_t count);

#endif
