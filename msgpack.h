#ifndef ZZ_MSGPACK_H
#define ZZ_MSGPACK_H

#include <stdbool.h>

#include "buffer.h"
#include "cmp.h"

typedef struct {
  zz_buffer_t *buffer;
  uint32_t pos;
} zz_cmp_buffer_state;

#define zz_cmp_ctx_state(ctx) ((zz_cmp_buffer_state*)((ctx)->buf))
#define zz_cmp_ctx_buffer(ctx) ((zz_cmp_ctx_state(ctx))->buffer)
#define zz_cmp_ctx_pos(ctx) ((zz_cmp_ctx_state(ctx))->pos)
#define zz_cmp_ctx_len(ctx) (zz_cmp_ctx_buffer(ctx)->len)
#define zz_cmp_ctx_ptr(ctx) (zz_cmp_ctx_buffer(ctx)->ptr)

bool zz_cmp_buffer_reader(struct cmp_ctx_s *ctx, void *data, size_t limit);
size_t zz_cmp_buffer_writer(struct cmp_ctx_s *ctx, const void *data, size_t count);

/* some handy cmp extensions */

/* these all accept doubles without a fractional part */

bool zz_cmp_read_size_t(cmp_ctx_t *ctx, size_t *s);
bool zz_cmp_write_size_t(cmp_ctx_t *ctx, size_t s);

bool zz_cmp_read_ssize_t(cmp_ctx_t *ctx, ssize_t *s);
bool zz_cmp_write_ssize_t(cmp_ctx_t *ctx, ssize_t s);

bool zz_cmp_read_ptr(cmp_ctx_t *ctx, void **ptr);
bool zz_cmp_write_ptr(cmp_ctx_t *ctx, void *ptr);

bool zz_cmp_read_int(cmp_ctx_t *ctx, int32_t *i);

#endif
