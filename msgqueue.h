#ifndef ZZ_MSGQUEUE_H
#define ZZ_MSGQUEUE_H

#include <pthread.h>

#include "msgpack.h"
#include "trigger.h"

typedef struct {
  uint8_t *ptr;
  size_t size;
  size_t rpos;
  size_t wpos;
  size_t free_space;
  size_t bytes_transferred;
  cmp_ctx_t *cmp_ctx;
  pthread_mutex_t *mutex;
  pthread_cond_t *cond_r;
  pthread_cond_t *cond_w;
  zz_trigger *trig_r;
} zz_msgqueue;

void zz_msgqueue_lock(zz_msgqueue *q);

void zz_msgqueue_prepare_write(zz_msgqueue *q, size_t length);

/* for writing a single blob of data */
void zz_msgqueue_write(zz_msgqueue *q, void* ptr, size_t size);

/* for building a message piece by piece in MessagePack format */
void zz_msgqueue_pack_integer(zz_msgqueue *q, int64_t d);
void zz_msgqueue_pack_uinteger(zz_msgqueue *q, uint64_t u);
void zz_msgqueue_pack_decimal(zz_msgqueue *q, double d);
void zz_msgqueue_pack_nil(zz_msgqueue *q);
void zz_msgqueue_pack_true(zz_msgqueue *q);
void zz_msgqueue_pack_false(zz_msgqueue *q);
void zz_msgqueue_pack_bool(zz_msgqueue *q, bool b);
void zz_msgqueue_pack_str(zz_msgqueue *q, const char *data, uint32_t size);
void zz_msgqueue_pack_bin(zz_msgqueue *q, const char *data, uint32_t size);
void zz_msgqueue_pack_array(zz_msgqueue *q, uint32_t size);
void zz_msgqueue_pack_map(zz_msgqueue *q, uint32_t size);

void zz_msgqueue_finish_write(zz_msgqueue *q);

void zz_msgqueue_prepare_read(zz_msgqueue *q);
void zz_msgqueue_finish_read(zz_msgqueue *q);

void zz_msgqueue_unlock(zz_msgqueue *q);

/* msgqueue - cmp interop */

bool zz_msgqueue_cmp_reader(struct cmp_ctx_s *ctx, uint8_t *data, size_t limit);
bool zz_msgqueue_cmp_skipper(struct cmp_ctx_s *ctx, size_t count);
size_t zz_msgqueue_cmp_writer(struct cmp_ctx_s *ctx, const uint8_t *data, size_t count);

#endif
