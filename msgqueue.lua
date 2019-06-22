local ffi = require('ffi')
local msgpack = require('msgpack')
local trigger = require('trigger')
local pthread = require('pthread')
local util = require('util')

ffi.cdef [[

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

]]

local M = {}

local Queue = util.Class()

function Queue:new(size)
   local ptr = ffi.new("uint8_t[?]", size)
   local mutex = ffi.C.zz_pthread_mutex_alloc()
   local cond_r = ffi.C.zz_pthread_cond_alloc()
   local cond_w = ffi.C.zz_pthread_cond_alloc()
   local trig_r = trigger.Semaphore()
   local q = ffi.new("zz_msgqueue", {
      ptr = ptr,
      size = size,
      rpos = 0,
      wpos = 0,
      free_space = size,
      bytes_transferred = 0,
      mutex = mutex,
      cond_r = cond_r,
      cond_w = cond_w,
      trig_r = trig_r,
   })
   local msgpack_context = msgpack.Context {
      state = q,
      reader = ffi.C.zz_msgqueue_cmp_reader,
      skipper = ffi.C.zz_msgqueue_cmp_skipper,
      writer = ffi.C.zz_msgqueue_cmp_writer,
   }
   q.cmp_ctx = msgpack_context.ctx
   util.check_ok("pthread_mutex_init", 0, ffi.C.pthread_mutex_init(q.mutex, nil))
   util.check_ok("pthread_cond_init", 0, ffi.C.pthread_cond_init(q.cond_r, nil))
   util.check_ok("pthread_cond_init", 0, ffi.C.pthread_cond_init(q.cond_w, nil))
   local self = {
      ptr = ptr,
      mutex = mutex,
      cond_r = cond_r,
      cond_w = cond_w,
      trig_r = trig_r,
      q = q,
      msgpack_context = msgpack_context,
   }
   return self
end

-- low-level API

function Queue:lock()
   ffi.C.zz_msgqueue_lock(self.q)
end

function Queue:prepare_write(length)
   ffi.C.zz_msgqueue_prepare_write(self.q, length)
end

function Queue:write(ptr, size)
   ffi.C.zz_msgqueue_write(self.q, ptr, size)
end

function Queue:pack_integer(d)
   ffi.C.zz_msgqueue_pack_integer(self.q, d)
end

function Queue:pack_uinteger(u)
   ffi.C.zz_msgqueue_pack_uinteger(self.q, u)
end

function Queue:pack_decimal(d)
   ffi.C.zz_msgqueue_pack_decimal(self.q, d)
end

function Queue:pack_nil()
   ffi.C.zz_msgqueue_pack_nil(self.q)
end

function Queue:pack_true()
   ffi.C.zz_msgqueue_pack_true(self.q)
end

function Queue:pack_false()
   ffi.C.zz_msgqueue_pack_false(self.q)
end

function Queue:pack_bool(b)
   ffi.C.zz_msgqueue_pack_bool(self.q, b)
end

function Queue:pack_str(data, size)
   ffi.C.zz_msgqueue_pack_str(self.q, data, size)
end

function Queue:pack_bin(data, size)
   ffi.C.zz_msgqueue_pack_bin(self.q, data, size)
end

function Queue:pack_array(size)
   ffi.C.zz_msgqueue_pack_array(self.q, size)
end

function Queue:pack_map(size)
   ffi.C.zz_msgqueue_pack_map(self.q, size)
end

function Queue:finish_write()
   ffi.C.zz_msgqueue_finish_write(self.q)
end

function Queue:prepare_read()
   ffi.C.zz_msgqueue_prepare_read(self.q)
end

function Queue:finish_read()
   ffi.C.zz_msgqueue_finish_read(self.q)
end

function Queue:unlock()
   ffi.C.zz_msgqueue_unlock(self.q)
end

-- high-level API

function Queue:pack(x, serialize)
   serialize = serialize or msgpack.pack
   local buf = serialize(x)
   self:write(buf.ptr, #buf)
end

function Queue:unpack()
   ffi.C.zz_msgqueue_lock(self.q)
   ffi.C.zz_msgqueue_prepare_read(self.q)
   local rv = self.msgpack_context:read()
   ffi.C.zz_msgqueue_finish_read(self.q)
   ffi.C.zz_msgqueue_unlock(self.q)
   return rv
end

function Queue:delete()
   self.ptr = nil
   if self.mutex then
      ffi.C.pthread_mutex_destroy(self.mutex)
      ffi.C.zz_pthread_mutex_free(self.mutex)
      self.mutex = nil
   end
   if self.cond_r then
      ffi.C.pthread_cond_destroy(self.cond_r)
      ffi.C.zz_pthread_cond_free(self.cond_r)
      self.cond_r = nil
   end
   if self.cond_w then
      ffi.C.pthread_cond_destroy(self.cond_w)
      ffi.C.zz_pthread_cond_free(self.cond_w)
      self.cond_w = nil
   end
   if self.trig_r then
      self.trig_r:delete()
      self.trig_r = nil
   end
   self.q = nil
   self.msgpack_context = nil
end

local M_mt = {}

function M_mt:__call(...)
   return Queue(...)
end

return setmetatable(M, M_mt)
