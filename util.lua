local adt = require('adt')
local bit = require('bit')
local errno = require('errno')
local buffer = require('buffer')

local M = {}

function M.round(x)
   if x >= 0 then
      return math.floor(x+0.5)
   else
      return math.ceil(x-0.5)
   end
end

function M.align_down(x, alignment)
   return x - x % alignment
end

function M.align_up(x, alignment)
   return x + (alignment - (x % alignment)) % alignment
end

function M.next_power_of_2(x)
   local rv = 1
   x = x - 1
   while x > 0 do
      x = bit.rshift(x, 1)
      rv = bit.lshift(rv, 1)
   end
   return rv
end

function M.check_ok(funcname, okvalue, rv)
   if rv ~= okvalue then
      error(sf("%s() failed: %s", funcname, rv), 2)
   else
      return rv
   end
end

function M.check_bad(funcname, badvalue, rv)
   if rv == badvalue then
      error(sf("%s() failed: %s", funcname, rv), 2)
   else
      return rv
   end
end

function M.check_errno(funcname, rv)
   if rv == -1 then
      error(sf("%s() failed: %s", funcname, errno.strerror()), 2)
   else
      return rv
   end
end

function M.Counter()
   local count = 0
   return function()
      count = count + 1
      return count
   end
end

function M.Accumulator()
   local self = {
      last = nil,
      n = 0,
      sum = 0,
      avg = 0,
      min = nil,
      max = nil,
   }
   function self:feed(x)
      self.n = self.n + 1
      self.sum = self.sum + x
      self.avg = self.sum / self.n
      if not self.max or x > self.max then
         self.max = x
      end
      if not self.min or x < self.min then
         self.min = x
      end
      self.last = x
   end
   return setmetatable(self, { __call = self.feed })
end

function M.Class(parent)
   local class = {}
   local mt = { __index = parent }
   function mt:__call(...)
      local self = {}
      if class.create then
         self = class:create(...)
      elseif select('#', ...)==1 then
         local arg = select(1, ...)
         if type(arg)=="table" then
            self = arg
         end
      end
      return setmetatable(self, { __index = class })
   end
   return setmetatable(class, mt)
end

function M.chain(self, index)
   local function lookup(index, name)
      if type(index)=="table" then
         return index[name]
      elseif type(index)=="function" then
         return index(self, name)
      else
         ef("invalid index: %s", index)
      end
   end
   local mt = getmetatable(self)
   local old_index = mt.__index
   local function new_index(self, name)
      return lookup(index, name) or lookup(old_index, name)
   end
   mt.__index = new_index
   return self
end

function M.ClassLoader(self, package_path)
   -- turn any object into a class loader
   -- which can autoload classes from package_path
   function self:require(name)
      return require(sf("%s.%s", package_path, name))
   end
   function self:new(name, ...)
      local constructor = self:require(name)
      return constructor(...)
   end
   local function is_classname(name)
      -- it's a class name if it starts with a capital letter
      local first_byte = name:byte(1,1)
      return first_byte >= 0x41 and first_byte <= 0x5A
   end
   local function index(self, name)
      if is_classname(name) then
         local ok, pkg = pcall(self.require, self, name)
         return ok and pkg
      end
   end
   return M.chain(self, index)
end

function M.EventEmitter(self, invoke_fn)
   self = self or {}
   invoke_fn = invoke_fn or function(cb, evtype, ...) cb(...) end
   local callbacks = {}
   function self:on(evtype, cb)
      if not callbacks[evtype] then
         callbacks[evtype] = adt.List()
      end
      callbacks[evtype]:push(cb)
   end
   function self:off(evtype, cb)
      if callbacks[evtype] then
         local cbs = callbacks[evtype]
         local i = cbs:index(cb)
         if i then
            cbs:remove_at(i)
         end
         if callbacks[evtype]:empty() then
            callbacks[evtype] = nil
         end
      end
   end
   function self:emit(evtype, ...)
      local cbs = callbacks[evtype]
      if cbs then
         for cb in cbs:itervalues() do
            invoke_fn(cb, evtype, ...)
         end
      end
   end
   return self
end

function M.lines(s)
   local index = 1
   local function next()
      local rv = nil
      if index <= #s then
         local lf_pos = s:find("\n", index, true)
         if lf_pos then
            rv = s:sub(index, lf_pos-1)
            index = lf_pos+1
         else
            rv = s:sub(index)
            index = #s+1
         end
      end
      return rv
   end
   return next
end

function M.hexstr(data)
   if not data then
      return ""
   end
   local buf = buffer.wrap(data)
   local hex = buffer.new(2*#buf)
   for i=0,#buf-1 do
      hex:append(sf("%02x", buf[i]))
   end
   return tostring(hex)
end

function M.oct(s)
   return tonumber(tostring(s), 8)
end

return M
