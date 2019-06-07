local testing = require('testing')('mm')
local mm = require('mm')
local sched = require('sched')
local util = require('util')
local ffi = require('ffi')
local assert = require('assert')

testing("BlockPool", function()
   local pool = mm.BlockPool(2^16) -- allocate memory in blocks of 2^16

   local free_blocks = {}

   local function pool_get(size)
      local ptr, block_size = pool:get(size)
      assert.equals(block_size, util.next_power_of_2(size))
      if free_blocks[block_size] and free_blocks[block_size] > 0 then
         free_blocks[block_size] = free_blocks[block_size] - 1
      end
      return ptr, block_size
   end

   local function pool_ret(ptr, block_size)
      pool:ret(ptr, block_size)
      if not free_blocks[block_size] then
         free_blocks[block_size] = 0
      end
      free_blocks[block_size] = free_blocks[block_size] + 1
   end

   local function get_ret()
      local size = math.floor(math.random(256))
      local ptr, block_size = pool_get(size)
      for i=1,math.floor(math.random(10)) do
         sched.yield()
      end
      pool_ret(ptr, block_size)
   end

   local threads = {}
   for i=1,1000 do
      table.insert(threads, sched(get_ret))
   end
   sched.join(threads)

   assert.equals(pool:arena_allocated_bytes(), pool:ptrpool_allocated_bytes())

   local total = 0
   for block_size, count in pairs(free_blocks) do
      total = total + block_size * count
   end
   assert.equals(pool:arena_allocated_bytes(), total)
end)

testing("with_block_1", function()
   local rv = mm.with_block(200, "uint8_t*", function(ptr, block_size)
      assert(ffi.istype("uint8_t*", ptr))
      -- BlockPool only allocates blocks with size = 2^n
      assert.equals(block_size, 256)
      return 100
   end)
   assert.equals(rv, 100)
end)

ffi.cdef [[
struct zz_mm_test_t {
  uint16_t a;
  uint32_t b;
};
]]

testing("with_block_2", function()
   mm.with_block("struct zz_mm_test_t", nil, function(ptr, block_size)
      assert(ffi.istype("struct zz_mm_test_t*", ptr))
      assert.equals(block_size, 8)
   end)
end)
