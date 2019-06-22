#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "msgqueue.h"

#define MIN(a,b) ((a) < (b) ? (a) : (b))

void zz_msgqueue_lock(zz_msgqueue *q) {
  int rv = pthread_mutex_lock(q->mutex);
  if (rv != 0) {
    fprintf(stderr, "msgqueue: cannot lock mutex for read\n");
    exit(1);
  }
}

void zz_msgqueue_prepare_write(zz_msgqueue *q, size_t length) {
  if (length > q->size) {
    fprintf(stderr, "msgqueue: length (%d) exceeds queue size (%d)\n", length, q->size);
    exit(1);
  }
  while (q->free_space < length) {
    int rv = pthread_cond_wait(q->cond_w, q->mutex);
    if (rv != 0) {
      fprintf(stderr, "msgqueue: pthread_cond_wait(cond_w) failed\n");
      exit(1);
    }
  }
  q->bytes_transferred = 0;
}

void zz_msgqueue_finish_write(zz_msgqueue *q) {
  q->free_space -= q->bytes_transferred;
  // notify reader
  zz_trigger_fire(q->trig_r);
  pthread_cond_signal(q->cond_r); // for extra safety
}

void zz_msgqueue_prepare_read(zz_msgqueue *q) {
  while (q->free_space == q->size) {
    // the Lua side should call zz_msgqueue_prepare_read() only after
    // q->trig_r fired
    //
    // when this assumption holds, we should not get here
    int rv = pthread_cond_wait(q->cond_r, q->mutex);
    if (rv != 0) {
      fprintf(stderr, "msgqueue: pthread_cond_wait(cond_r) failed\n");
      exit(1);
    }
  }
  q->bytes_transferred = 0;
}

void zz_msgqueue_finish_read(zz_msgqueue *q) {
  q->free_space += q->bytes_transferred;
  pthread_cond_broadcast(q->cond_w); // notify writers
}

void zz_msgqueue_unlock(zz_msgqueue *q) {
  int rv = pthread_mutex_unlock(q->mutex);
  if (rv != 0) {
    fprintf(stderr, "msgqueue: cannot unlock mutex\n");
    exit(1);
  }
}

static size_t read_bytes(zz_msgqueue *q, void *ptr, size_t size) {
  size_t bytes_read = 0;
  size_t chunk_size = MIN(size, q->size - q->rpos);
  if (chunk_size > 0) {
    memcpy(ptr, q->ptr + q->rpos, chunk_size);
    q->rpos = (q->rpos + chunk_size) % q->size;
    bytes_read += chunk_size;
  }
  if (bytes_read < size) {
    chunk_size = size - bytes_read;
    memcpy(ptr + bytes_read, q->ptr, chunk_size);
    q->rpos += chunk_size;
    bytes_read += chunk_size;
  }
  q->bytes_transferred += bytes_read;
  return bytes_read;
}

static size_t write_bytes(zz_msgqueue *q, const void *ptr, size_t size) {
  size_t bytes_written = 0;
  size_t chunk_size = MIN(size, q->size - q->wpos);
  if (chunk_size > 0) {
    memcpy(q->ptr + q->wpos, ptr, chunk_size);
    q->wpos = (q->wpos + chunk_size) % q->size;
    bytes_written += chunk_size;
  }
  if (bytes_written < size) {
    chunk_size = size - bytes_written;
    memcpy(q->ptr, ptr + bytes_written, chunk_size);
    q->wpos += chunk_size;
    bytes_written += chunk_size;
  }
  q->bytes_transferred += bytes_written;
  return bytes_written;
}

void zz_msgqueue_write(zz_msgqueue *q, void* ptr, size_t size) {
  zz_msgqueue_lock(q);
  zz_msgqueue_prepare_write(q, size);
  write_bytes(q, ptr, size);
  zz_msgqueue_finish_write(q);
  zz_msgqueue_unlock(q);
}

#define CHECK(op) \
  if (!op) { \
    fprintf(stderr, #op " failed\n"); \
    exit(1); \
  }

void zz_msgqueue_pack_integer(zz_msgqueue *q, int64_t d) {
  CHECK(cmp_write_integer(q->cmp_ctx, d));
}

void zz_msgqueue_pack_uinteger(zz_msgqueue *q, uint64_t u) {
  CHECK(cmp_write_uinteger(q->cmp_ctx, u));
}

void zz_msgqueue_pack_decimal(zz_msgqueue *q, double d) {
  CHECK(cmp_write_decimal(q->cmp_ctx, d));
}

void zz_msgqueue_pack_nil(zz_msgqueue *q) {
  CHECK(cmp_write_nil(q->cmp_ctx));
}

void zz_msgqueue_pack_true(zz_msgqueue *q) {
  CHECK(cmp_write_true(q->cmp_ctx));
}

void zz_msgqueue_pack_false(zz_msgqueue *q) {
  CHECK(cmp_write_false(q->cmp_ctx));
}

void zz_msgqueue_pack_bool(zz_msgqueue *q, bool b) {
  CHECK(cmp_write_bool(q->cmp_ctx, b));
}

void zz_msgqueue_pack_str(zz_msgqueue *q, const char *data, uint32_t size) {
  CHECK(cmp_write_str(q->cmp_ctx, data, size));
}

void zz_msgqueue_pack_bin(zz_msgqueue *q, const char *data, uint32_t size) {
  CHECK(cmp_write_bin(q->cmp_ctx, data, size));
}

void zz_msgqueue_pack_array(zz_msgqueue *q, uint32_t size) {
  CHECK(cmp_write_array(q->cmp_ctx, size));
}

void zz_msgqueue_pack_map(zz_msgqueue *q, uint32_t size) {
  CHECK(cmp_write_map(q->cmp_ctx, size));
}

bool zz_msgqueue_cmp_reader(struct cmp_ctx_s *ctx, uint8_t *data, size_t limit) {
  zz_msgqueue *q = (zz_msgqueue*) ctx->buf;
  if (limit > q->size) {
    return false;
  }
  size_t bytes_read = read_bytes(q, data, limit);
  return bytes_read == limit;
}

bool zz_msgqueue_cmp_skipper(struct cmp_ctx_s *ctx, size_t count) {
  zz_msgqueue *q = (zz_msgqueue*) ctx->buf;
  if (count > q->size) {
    return false;
  }
  q->rpos = (q->rpos + count) % q->size;
  q->bytes_transferred += count;
  return true;
}

size_t zz_msgqueue_cmp_writer(struct cmp_ctx_s *ctx, const uint8_t *data, size_t count) {
  zz_msgqueue *q = (zz_msgqueue*) ctx->buf;
  if (count > q->size) {
    return 0;
  }
  size_t bytes_written = write_bytes(q, data, count);
  return bytes_written == count ? bytes_written : 0;
}

/* test support */

struct zz_msgqueue_test_writer_info {
  zz_msgqueue *queue;
  void *msg_data;
  int msg_len;
};

void zz_msgqueue_test_writer(void *arg) {
  struct zz_msgqueue_test_writer_info *info = (struct zz_msgqueue_test_writer_info*) arg;
  zz_msgqueue_write(info->queue, info->msg_data, info->msg_len);
}
