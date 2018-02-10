local mm = require('mm')
local sched = require('sched')
local util = require('util')
local assert = require('assert')

-- BlockPool

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

for i=1,1000 do
   sched(get_ret)
end
sched()

assert.equals(pool:arena_allocated_bytes(), pool:ptrpool_allocated_bytes())

local total = 0
for block_size, count in pairs(free_blocks) do
   total = total + block_size * count
end
assert.equals(pool:arena_allocated_bytes(), total)
