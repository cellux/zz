local M = {}

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

return M
