local ffi = require('ffi')
local bit = require('bit')
local util = require('util')

local M = {}

local BLOCK_POOL_ARENA_SIZE = 2^16

local function Arena(arena_size)
   local arena = ffi.new("uint8_t[?]", arena_size)
   local offset = 0
   local self = {}
   function self:alloc(block_size)
      if offset + block_size > arena_size then
         return nil
      else
         local ptr = ffi.cast("void*", arena + offset)
         offset = offset + block_size
         return ptr
      end
   end
   function self:allocated_bytes()
      return offset
   end
   return self
end

local function ArenaAllocator(arena_size)
   local past_arenas = {} -- collect refs to prevent GC
   local current_arena = Arena(arena_size)
   local self = {}
   function self:alloc(block_size)
      local ptr = current_arena:alloc(block_size)
      if ptr == nil then
         -- arena is full
         table.insert(past_arenas, current_arena)
         current_arena = Arena(arena_size)
         ptr = current_arena:alloc(block_size)
         if ptr == nil then
            ef("cannot allocate block of size %d from arena", block_size)
         end
      end
      return ptr
   end
   function self:allocated_bytes()
      local total = current_arena:allocated_bytes()
      for _,arena in pairs(past_arenas) do
         total = total + arena:allocated_bytes()
      end
      return total
   end
   return setmetatable(self, { __call = self.alloc })
end

local function PtrPool(alloc, block_size)
   local capacity = 16
   local ptrs = ffi.new("void*[?]", capacity)
   local length = 0
   local index = 0
   local self = {}
   function self:getptr()
      if index == length then
         if length == capacity then
            local new_capacity = capacity * 2
            local new_ptrs = ffi.new("void*[?]", new_capacity)
            ffi.copy(new_ptrs, ptrs, capacity * ffi.sizeof("void*"))
            capacity = new_capacity
            ptrs = new_ptrs
         end
         ptrs[length] = alloc(block_size)
         length = length + 1
      end
      local ptr = ptrs[index]
      index = index + 1
      return ptr
   end
   function self:retptr(ptr)
      assert(index > 0)
      index = index - 1
      ptrs[index] = ptr
   end
   function self:length()
      return length
   end
   return self
end

local function BlockPool(arena_size)
   local aa = ArenaAllocator(arena_size)
   local ptrpools = {}
   local self = {}
   function self:get(block_size)
      block_size = util.next_power_of_2(block_size)
      local ptrpool = ptrpools[block_size]
      if not ptrpool then
         ptrpool = PtrPool(aa, block_size)
         ptrpools[block_size] = ptrpool
      end
      return ptrpool:getptr(), block_size
   end
   function self:ret(ptr, block_size)
      ptrpools[block_size]:retptr(ptr)
   end
   function self:arena_allocated_bytes()
      return aa:allocated_bytes()
   end
   function self:ptrpool_allocated_bytes()
      local total = 0
      for block_size, ptrpool in pairs(ptrpools) do
         total = total + block_size * ptrpool:length()
      end
      return total
   end
   return self
end

M.BlockPool = BlockPool

local block_pool = BlockPool(BLOCK_POOL_ARENA_SIZE)

function M.get_block(size, ptr_type)
   ptr_type = ptr_type or "void*"
   if type(size) == "string" then
      ptr_type = size.."*"
      size = ffi.sizeof(size)
   end
   local ptr, block_size = block_pool:get(size)
   return ffi.cast(ptr_type, ptr), block_size
end

function M.ret_block(ptr, block_size)
   block_pool:ret(ptr, block_size)
end

return M
