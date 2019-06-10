local bit = require('bit')
local errno = require('errno')
local buffer = require('buffer')

local M = {}

-- List

local List_mt = {}

function List_mt:push(item)
   table.insert(self._items, item)
end

function List_mt:pop()
   return table.remove(self._items)
end

function List_mt:shift()
   return table.remove(self._items, 1)
end

function List_mt:unshift(item)
   table.insert(self._items, 1, item)
end

function List_mt:index(item)
   for i=1, #self._items do
      if self._items[i]==item then
         return i-1
      end
   end
   return nil
end

function List_mt:remove_at(index)
   return table.remove(self._items, index+1)
end

function List_mt:remove(item)
   local index = self:index(item)
   if index then
      self:remove_at(index)
   end
end

function List_mt:size()
   return #self._items
end

function List_mt:empty()
   return #self._items == 0
end

function List_mt:clear()
   self._items = {}
end

function List_mt:__index(pos)
   if type(pos) == "number" then
      return self._items[pos+1]
   else
      return rawget(List_mt, pos)
   end
end

function List_mt:iteritems(selector)
   selector = selector or function(k,v) return k,v end
   local index = 0
   local function next()
      if index >= self:size() then
         return nil
      else
         local k,v = index, self[index]
         index = index + 1
         return selector(k,v)
      end
   end
   return next
end

function List_mt:iterkeys()
   return self:iteritems(function(k,v) return k end)
end

function List_mt:itervalues()
   return self:iteritems(function(k,v) return v end)
end

function List_mt:__ipairs()
   local function iter(t,i)
      i = (i or 0) + 1
      local v = self._items[i]
      if v then return i,v end
   end
   return iter, self._items, nil
end

function M.List()
   local self = {
      _items = {}
   }
   return setmetatable(self, List_mt)
end

-- OrderedList

local OrderedList_mt = {}

function OrderedList_mt:push(item)
   local i = 1
   while i <= #self._items and self.key_fn(item) > self.key_fn(self._items[i]) do
      i = i + 1
   end
   table.insert(self._items, i, item)
end

function OrderedList_mt:__index(pos)
   if type(pos) == "number" then
      return self._items[pos+1]
   else
      return rawget(OrderedList_mt, pos) or rawget(List_mt, pos)
   end
end

function M.OrderedList(key_fn)
   local self = {
      _items = {},
      key_fn = key_fn or function(x) return x end,
   }
   return setmetatable(self, OrderedList_mt)
end

-- Set

local Set_mt = {}
Set_mt.__index = Set_mt

function M.Set()
   local self = {
      _items = {},
      _size = 0,
   }
   return setmetatable(self, Set_mt)
end

function Set_mt:push(item)
   if not self._items[item] then
      self._items[item] = true
      self._size = self._size + 1
   end
end

function Set_mt:remove(item)
   if self._items[item] then
      self._items[item] = nil
      self._size = self._size - 1
   end
end

function Set_mt:contains(item)
   return self._items[item] or false
end

function Set_mt:size()
   return self._size
end

function Set_mt:empty()
   return self._size == 0
end

function Set_mt:clear()
   self._items = {}
   self._size = 0
end

function Set_mt:iteritems()
   local last = nil
   local function _next()
      last = next(self._items, last)
      return last
   end
   return _next
end

--

function M.round(x)
   if x >= 0 then
      return math.floor(tonumber(x) + 0.5)
   else
      return math.ceil(tonumber(x) - 0.5)
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
   local class_mt = { __index = parent }
   function class_mt:__call(...)
      local self = {}
      if class.new then
         self = class:new(...)
      elseif select('#', ...)==1 then
         local arg = select(1, ...)
         if type(arg)=="table" then
            self = arg
         end
      end
      local self_mt = { __index = class }
      if type(self) == "table" then
         local mt_keys = {}
         for k,v in pairs(self) do
            if type(k)=="string" and k:sub(1,2) == "__" then
               table.insert(mt_keys, k)
               self_mt[k] = v
            end
         end
         for _,k in ipairs(mt_keys) do
            if k == "__index" then
               ef("attempt to override __index metamethod")
            end
            self[k] = nil
         end
      end
      return setmetatable(self, self_mt)
   end
   return setmetatable(class, class_mt)
end

function M.chain(self, index, last)
   local function lookup(index, name)
      if type(index)=="table" or type(index)=="cdata" then
         return index[name]
      elseif type(index)=="function" then
         return index(self, name)
      else
         ef("invalid index: %s", index)
      end
   end
   local mt = getmetatable(self)
   if not mt then
      mt = {}
      setmetatable(self, mt)
   end
   local old_index = mt.__index or {}
   if last then
      mt.__index = function(self, name)
         return lookup(old_index, name) or lookup(index, name)
      end
   else
      mt.__index = function(self, name)
         return lookup(index, name) or lookup(old_index, name)
      end
   end
   return self
end

function M.chainlast(self, index)
   return M.chain(self, index, true)
end

function M.ClassLoader(self, require, package_path)
   -- turn any object into a class loader
   -- which can autoload classes from package_path
   --
   -- the constructors of classes loaded this way all take the object
   -- through which they have been loaded as their first argument
   local function load_class(name)
      if package_path then
         return require(sf("%s/%s", package_path, name))
      else
         return require(name)
      end
   end
   local function is_classname(name)
      -- it's a class name if it starts with a capital letter
      local first_byte = name:byte(1,1)
      return first_byte >= 0x41 and first_byte <= 0x5A
   end
   local function index(self, name)
      if is_classname(name) then
         local ok, pkg = pcall(load_class, name)
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
         callbacks[evtype] = M.List()
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

function M.extend(t1, t2)
   if t2 then
      for _,v in ipairs(t2) do
         table.insert(t1, v)
      end
   end
   return t1
end

function M.map(f, t)
   local rv = {}
   if t then
      if type(f) == "string" then
         -- each element in t is a table
         -- map to the value at key f
         local key = f
         f = function(item) 
            return item[key]
         end
      end
      for _,v in ipairs(t) do
         table.insert(rv, f(v))
      end
   end
   return rv
end

function M.reduce(f, t, acc)
   for _,v in ipairs(t) do
      acc = f(acc, v)
   end
   return acc
end

function M.filter(f, t)
   local rv = {}
   if t then
      for _,v in ipairs(t) do
         if f(v) then
            table.insert(rv, v)
         end
      end
   end
   return rv
end

function M.indexof(x, t)
   local index
   for i,v in ipairs(t) do
      if v == x then
         index = i
         break
      end
   end
   return index
end

function M.contains(x, t)
   return M.indexof(x, t) ~= nil
end

function M.reverse(t)
   local rv = {}
   for i=#t,1,-1 do
      table.insert(rv, t[i])
   end
   return rv
end

-- error handling

local Error = M.Class()

function Error:new(level, message, context)
   level = (level or 1) + 2 -- Error() + Error:new()
   local self = context or {}
   self.message = tostring(message or "runtime error")
   self.info = debug.getinfo(level)
   self.traceback = self.traceback or
      debug.traceback(self.message, level)
   self.__tostring = self.__tostring or
      function(self)
         return self.traceback
      end
   return self
end

M.Error = Error

local function is_error(x)
   return type(x)=="table" and x.message and x.info and x.traceback
end

M.is_error = is_error

function M.throwat(level, x, ...)
   level = (level or 1) + 1
   if is_error(x) then
      error(x, 0)
   else
      error(Error(level, x, ...), 0)
   end
end

function M.throw(...)
   M.throwat(2, ...)
end

function M.check_ok(funcname, okvalue, rv)
   if rv ~= okvalue then
      local message = sf("%s() failed: %s", funcname, rv)
      M.throwat(2, message)
   else
      return rv
   end
end

function M.check_bad(funcname, badvalue, rv)
   if rv == badvalue then
      local message = sf("%s() failed: %s", funcname, rv)
      M.throwat(2, message)
   else
      return rv
   end
end

function M.check_errno(funcname, rv, _errno)
   if rv == -1 then
      _errno = _errno or errno.errno()
      local message = sf("%s() failed: %s", funcname, errno.strerror(_errno))
      local context = { errno = _errno }
      M.throwat(2, message, context)
   else
      return rv
   end
end

function M.pcall(f, ...)
   local args = {...}
   local function trampoline()
      return f(unpack(args))
   end
   local function error_handler(e)
      if is_error(e) then
         return e
      else
         return Error(2, e)
      end
   end
   return xpcall(trampoline, error_handler)
end

return M
