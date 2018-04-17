#include <stdio.h>
#include <string.h>

#include "msgpack.h"

#define MIN(a,b) ((a) < (b) ? (a) : (b))

bool zz_cmp_buffer_reader(struct cmp_ctx_s *ctx, void *data, size_t limit) {
  zz_cmp_buffer_state *state = (zz_cmp_buffer_state*) ctx->buf;
  if (state->pos >= state->buffer->len) {
    return false;
  }
  size_t left_in_buf = state->buffer->len - state->pos;
  size_t bytes_to_read = MIN(left_in_buf, limit);
  memcpy(data, state->buffer->ptr + state->pos, bytes_to_read);
  state->pos += bytes_to_read;
  return bytes_to_read == limit;
}

size_t zz_cmp_buffer_writer(struct cmp_ctx_s *ctx, const void *data, size_t count) {
  zz_cmp_buffer_state *state = (zz_cmp_buffer_state*) ctx->buf;
  uint32_t bytes_appended = zz_buffer_append(state->buffer, data, count);
  state->pos += bytes_appended;
  /* cmp.c uses the return value as a bool so I guess it must be
     non-zero if all bytes could be written and 0 otherwise */
  return bytes_appended == count ? bytes_appended : 0;
}

bool zz_cmp_read_size_t(cmp_ctx_t *ctx, size_t *s) {
  cmp_object_t obj;
  if (!cmp_read_object(ctx, &obj)) {
    return false;
  }
  switch (obj.type) {
  case CMP_TYPE_POSITIVE_FIXNUM:
  case CMP_TYPE_UINT8:
    *s = (size_t) obj.as.u8;
    return true;
  case CMP_TYPE_UINT16:
    *s = (size_t) obj.as.u16;
    return true;
  case CMP_TYPE_UINT32:
    *s = (size_t) obj.as.u32;
    return true;
  case CMP_TYPE_UINT64:
    *s = (size_t) obj.as.u64;
    return true;
  case CMP_TYPE_DOUBLE:
    *s = (size_t) obj.as.dbl;
    if (*s != obj.as.dbl) {
      fprintf(stderr, "zz_cmp_read_size_t: double value for size_t has fractional part\n");
      return false;
    }
    return true;
  default:
    fprintf(stderr, "zz_cmp_read_size_t: value must be serialized as uint or double, but got cmp type marker %d\n", obj.type);
    return false;
  }
}

bool zz_cmp_write_size_t(cmp_ctx_t *ctx, size_t s) {
  if (sizeof(size_t) == sizeof(uint32_t)) {
    return cmp_write_u32(ctx, s);
  }
  else if (sizeof(size_t) == sizeof(uint64_t)) {
    return cmp_write_u64(ctx, s);
  }
  else {
    fprintf(stderr, "zz_cmp_write_size_t: cannot serialize size_t value, neither as u32, nor as u64\n");
    return false;
  }
}

bool zz_cmp_read_ssize_t(cmp_ctx_t *ctx, ssize_t *s) {
  cmp_object_t obj;
  if (!cmp_read_object(ctx, &obj)) {
    return false;
  }
  switch (obj.type) {
  case CMP_TYPE_POSITIVE_FIXNUM:
  case CMP_TYPE_UINT8:
    *s = (ssize_t) obj.as.u8;
    return true;
  case CMP_TYPE_UINT16:
    *s = (ssize_t) obj.as.u16;
    return true;
  case CMP_TYPE_UINT32:
    *s = (ssize_t) obj.as.u32;
    if (*s != obj.as.u32) {
      fprintf(stderr, "zz_cmp_read_ssize_t: u32 value for ssize_t doesn't fit into 31 bits\n");
      return false;
    }
    return true;
  case CMP_TYPE_UINT64:
    *s = (ssize_t) obj.as.u64;
    if (*s != obj.as.u64) {
      fprintf(stderr, "zz_cmp_read_ssize_t: u64 value for ssize_t doesn't fit into 63 bits\n");
      return false;
    }
    return true;
  case CMP_TYPE_NEGATIVE_FIXNUM:
  case CMP_TYPE_SINT8:
    *s = (ssize_t) obj.as.s8;
    return true;
  case CMP_TYPE_SINT16:
    *s = (ssize_t) obj.as.s16;
    return true;
  case CMP_TYPE_SINT32:
    *s = (ssize_t) obj.as.s32;
    return true;
  case CMP_TYPE_SINT64:
    *s = (ssize_t) obj.as.s64;
    return true;
  case CMP_TYPE_DOUBLE:
    *s = (ssize_t) obj.as.dbl;
    if (*s != obj.as.dbl) {
      fprintf(stderr, "zz_cmp_read_ssize_t: double value for ssize_t has fractional part\n");
      return false;
    }
    return true;
  default:
    fprintf(stderr, "zz_cmp_read_ssize_t: value must be serialized as int or double, but got cmp type marker %d\n", obj.type);
    return false;
  }
}

bool zz_cmp_write_ssize_t(cmp_ctx_t *ctx, ssize_t s) {
  if (sizeof(ssize_t) == sizeof(int32_t)) {
    return cmp_write_s32(ctx, s);
  }
  else if (sizeof(ssize_t) == sizeof(int64_t)) {
    return cmp_write_s64(ctx, s);
  }
  else {
    fprintf(stderr, "zz_cmp_write_ssize_t: cannot serialize ssize_t value, neither as s32, nor as s64\n");
    return false;
  }
}

bool zz_cmp_read_ptr(cmp_ctx_t *ctx, void **ptr) {
  return zz_cmp_read_size_t(ctx, (size_t*) ptr);
}

bool zz_cmp_write_ptr(cmp_ctx_t *ctx, void *ptr) {
  return zz_cmp_write_size_t(ctx, (size_t) ptr);
}

bool zz_cmp_read_int(cmp_ctx_t *ctx, int32_t *i) {
  cmp_object_t obj;

  if (!cmp_read_object(ctx, &obj))
    return false;

  switch (obj.type) {
  case CMP_TYPE_POSITIVE_FIXNUM:
  case CMP_TYPE_NEGATIVE_FIXNUM:
  case CMP_TYPE_SINT8:
    *i = obj.as.s8;
    return true;
  case CMP_TYPE_UINT8:
    *i = obj.as.u8;
    return true;
  case CMP_TYPE_SINT16:
    *i = obj.as.s16;
    return true;
  case CMP_TYPE_UINT16:
    *i = obj.as.u16;
    return true;
  case CMP_TYPE_SINT32:
    *i = obj.as.s32;
    return true;
  case CMP_TYPE_UINT32:
    *i = (int32_t) obj.as.u32;
    if (*i != obj.as.u32) {
      fprintf(stderr, "zz_cmp_read_int: u32 value doesn't fit into 31 bits\n");
      return false;
    }
    return true;
  case CMP_TYPE_DOUBLE:
    *i = (int32_t) obj.as.dbl;
    if (*i != obj.as.dbl) {
      fprintf(stderr, "zz_cmp_read_int: double value for i32 has fractional part\n");
      return false;
    }
    return true;
  default:
    fprintf(stderr, "zz_cmp_read_int: value must be serialized as int or double, but got cmp type marker %d\n", obj.type);
    return false;
  }
}
