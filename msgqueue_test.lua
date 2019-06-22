local testing = require('testing')('msgqueue')
local msgqueue = require('msgqueue')
local assert = require('assert')
local ffi = require('ffi')
local net = require('net')
local util = require('util')
local sched = require('sched')
local buffer = require('buffer')
local msgpack = require('msgpack')
local pthread = require('pthread')

-- The `msgqueue` module provides a simple FIFO (First-In First-Out)
-- queue of MessagePack-serialized messages supporting multiple
-- writers and a single reader.
--
-- Writers lock the queue (`lock`), prepare for the write
-- (`prepare_write`), write a single message (`write` or `pack_X`),
-- then unlock the queue (`unlock`). Writers can use a series of API
-- calls (`pack_integer`, `pack_decimal`, `pack_str`, `pack_bin`,
-- `pack_bool`, `pack_array`, `pack_map`, etc.) to construct the
-- message piece by piece or write the entire message at once
-- (`write`). When the write is complete (`finish_write`), the queue's
-- trigger is fired. The reader can poll the associated eventfd for
-- incoming message notifications and then use `unpack` to read and
-- deserialize the next available message.
--
-- The primary (only?) purpose of `msgqueue` is to let C threads
-- safely inject structured events into the scheduler event queue.
--
-- Under normal circumstances, you shall NOT write into the queue from
-- the Lua side, otherwise a deadlock may occur: if the write blocked
-- due to insufficient free space in the queue, the reader - which is
-- assumed to be running in the same Lua VM - would not get a chance
-- to free up space in the queue.

local test_message = {
   123,
   'a',
   {'hello',false,'world',true},
   {a=5, b=8.75, c=3},
   -5,
   {true, false},
   buffer.copy("binary data"),
}

testing('msgqueue/lua', function()
   local q = msgqueue(4096) -- size of the queue in bytes

   q:pack("hello, world!")
   assert.equals(q:unpack(), "hello, world!")

   -- second argument is the serializer (default: msgpack.pack)
   q:pack(test_message, msgpack.pack_array)
   assert.equals(q:unpack(), test_message)

   assert.equals(q:unpack(q:pack(nil)), nil)

   q:delete()
end)

testing('msgqueue/c', function()
   local q = msgqueue(4096)

   local received_message
   local receiver = sched(function()
      -- calling q:unpack() with no messages in the queue -> deadlock
      q.trig_r:poll()
      received_message = q:unpack()
   end)

   -- before a read/write, always lock the queue first
   q:lock()

   -- block until the queue has 128 bytes of free space
   q:prepare_write(128)

   -- write an array of 7 elements
   q:pack_array(7)
   -- [1]: 123
   q:pack_uinteger(123)
   -- [2]: "a"
   q:pack_str("a", 1)
   -- [3]: {"hello, false, "world", true}
   q:pack_array(4)
   q:pack_str("hello", 5)
   q:pack_false()
   q:pack_str("world", 5)
   q:pack_true()
   -- [4]: {a=5, b=8.75, c=3}
   q:pack_map(3)
   q:pack_str("a", 1)
   q:pack_uinteger(5)
   q:pack_str("b", 1)
   q:pack_decimal(8.75)
   q:pack_str("c", 1)
   q:pack_uinteger(3)
   -- [5]: -5
   q:pack_integer(-5)
   -- [6]: {true, false}
   q:pack_array(2)
   q:pack_bool(true)
   q:pack_bool(false)
   -- [7]: "binary data" (11 bytes)
   q:pack_bin("binary data", 11)

   -- notify the reader by firing the queue trigger
   q:finish_write()

   -- unlock the queue
   q:unlock()

   sched.join(receiver)
   assert.equals(received_message, test_message)
   q:delete()
end)

testing('zz_msgqueue_write', function()
   local q = msgqueue(4096)
   local buf = msgpack.pack_array(test_message)
   q:write(buf.ptr, #buf)
   assert.equals(q:unpack(), test_message)
   q:delete()
end)

ffi.cdef [[
struct zz_msgqueue_test_writer_info {
  zz_msgqueue *queue;
  void *msg_data;
  int msg_len;
};

void zz_msgqueue_test_writer(void *arg);
]]

testing('multiple writers (stress test)', function()
   local q = msgqueue(128)
   local writer_count = 100
   local arrived = {}
   local consumer = sched(function()
      local remaining = writer_count
      while remaining > 0 do
         q.trig_r:poll()
         -- when the msgqueue trigger becomes readable, we have at
         -- least one message in the queue waiting to be processed
         local msg = q:unpack()
         arrived[msg.id] = msg
         remaining = remaining - 1
      end
   end)
   local nextid = util.Counter()
   local function make_msg()
      return {
         id = 1000 + nextid(),
         n = math.random(100000),
      }
   end
   local writer_infos = {}
   local msgbufs = {}
   local function start_writer(msg)
      local msgbuf = msgpack.pack(msg)
      msgbufs[msg.id] = msgbuf -- prevent GC
      local info = ffi.new("struct zz_msgqueue_test_writer_info")
      info.queue = q.q
      info.msg_data = msgbuf.ptr
      info.msg_len = #msgbuf
      table.insert(writer_infos, info) -- prevent GC
      local thread_id = ffi.new("pthread_t[1]")
      local rv = ffi.C.pthread_create(thread_id,
                                      nil,
                                      ffi.C.zz_msgqueue_test_writer,
                                      ffi.cast("void*", info))
      if rv ~= 0 then
         ef("cannot create writer thread: pthread_create() failed")
      end
   end
   local expected = {}
   for i=1,writer_count do
      local msg = make_msg()
      expected[msg.id] = msg
      start_writer(msg)
   end
   sched.join(consumer)
   assert.equals(expected, arrived)
   q:delete()
end)
