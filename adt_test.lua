local adt = require('adt')
local ffi = require('ffi')
local assert = require('assert')

-- List

local l = adt.List()
assert(l:empty())
l:push(10)
l:push(20)
l:push(30)
assert(l:size() == 3)
assert(not l:empty())
assert.equals(l[0], 10)
assert.equals(l[1], 20)
assert.equals(l[2], 30)

local l = adt.List()
l:push(10)
l:push(20)
l:push(30)

local keys = {}
for k in l:iterkeys() do
   table.insert(keys, k)
end
assert.equals(keys, {0, 1, 2})

local values = {}
for v in l:itervalues() do
   table.insert(values, v)
end
assert.equals(values, {10, 20, 30})

local items = {}
for k,v in l:iteritems() do
   items[k] = v
end
assert.equals(items, {[0]=10, [1]=20, [2]=30})

local l = adt.List()
for i=1,10 do
   l:push(sf("item %d", i))
end
assert.equals(l:index("item 1"), 0)
assert.equals(l:index("item 5"), 4)
assert.equals(l:index("item 10"), 9)
assert.equals(l:index("item 20"), nil)

local l = adt.List()
for i=1,10 do
   l:push(sf("item %d", i))
end
l:remove_at(6)
assert.equals(l:size(), 9)
assert.equals(l[5], "item 6")
assert.equals(l[6], "item 8")
assert.equals(l[7], "item 9")
assert.equals(l[8], "item 10")
l:remove_at(8)
assert.equals(l:size(), 8)
assert.equals(l[7], "item 9")
assert.equals(l[8], nil)
l:remove_at(0)
assert.equals(l:size(), 7)
assert.equals(l[0], "item 2")
assert.equals(l[1], "item 3")
l:remove_at(10)
assert.equals(l:size(), 7)

local l = adt.List()
for i=1,10 do
   l:push(sf("item %d", i))
end
l:remove("item 5")
l:remove("item 1")
l:remove("item 10")
assert.equals(l:size(), 7)
assert.equals(l[0], "item 2")
assert.equals(l[1], "item 3")
assert.equals(l[2], "item 4")
assert.equals(l[3], "item 6")
assert.equals(l[4], "item 7")
assert.equals(l[5], "item 8")
assert.equals(l[6], "item 9")

-- List:remove() finds cdata objects

local l = adt.List()
local item1 = ffi.new("uint8_t[16]")
local item2 = ffi.new("uint8_t[16]")
local item3 = ffi.new("uint8_t[16]")
l:push(item1)
l:push(item2)
l:push(item3)
l:remove(item1)
l:remove(item2)
l:remove(item3)
assert(l:empty())

-- List:pop() removes from end
local l = adt.List()
l:push("a")
l:push("b")
assert.equals(l:pop(), "b")
assert.equals(l:pop(), "a")
assert.equals(l:pop(), nil)
assert(l:empty())

-- List:unshift() pushes to front
local l = adt.List()
l:push("a")
l:push("b")
l:unshift("c")
l:unshift("d")
assert.equals(l:size(), 4)
assert.equals(l[0], "d")
assert.equals(l[1], "c")
assert.equals(l[2], "a")
assert.equals(l[3], "b")
assert.equals(l:pop(), "b")
assert.equals(l:shift(), "d")
assert.equals(l:pop(), "a")
assert.equals(l:shift(), "c")
assert(l:empty())

-- List is iterable via ipairs()
local l = adt.List()
l:push(5)
l:push(8)
l:push(13)
local items = {}
for _,v in ipairs(l) do
   table.insert(items, v)
end
assert.equals(items, {5,8,13})

-- OrderedList

local l = adt.OrderedList()
assert(l:empty())
l:push(50)
l:push(10)
l:push(30)
l:push(20)
assert(l:size() == 4)
assert(not l:empty())
assert(l[0] == 10, "l[0]="..l[0])
assert(l[1] == 20, "l[1]="..l[1])
assert(l[2] == 30, "l[2]="..l[2])
assert(l[3] == 50, "l[3]="..l[3])

local l = adt.OrderedList()
l:push("car")
l:push("apple")
l:push("yellowstone")
l:push("bridge")
assert(l[0]=="apple")
assert(l[1]=="bridge")
assert(l[2]=="car")
assert(l[3]=="yellowstone")

local l = adt.OrderedList(function(s) return s:len() end)
l:push("car")
l:push("apple")
l:push("yellowstone")
l:push("bridge")
assert(l[0]=="car")
assert(l[1]=="apple")
assert(l[2]=="bridge")
assert(l[3]=="yellowstone")

assert(l:shift()=="car")
assert(l:shift()=="apple")
assert(l:size()==2)
assert(l[0]=="bridge")
assert(l[1]=="yellowstone")

local l = adt.OrderedList()
l:push(20)
l:push(10)
l:push(30)

local keys = {}
for k in l:iterkeys() do
   table.insert(keys, k)
end
assert.equals(keys, {0, 1, 2})

local values = {}
for v in l:itervalues() do
   table.insert(values, v)
end
assert.equals(values, {10, 20, 30})

local items = {}
for k,v in l:iteritems() do
   items[k] = v
end
assert.equals(items, {[0]=10, [1]=20, [2]=30})

-- Set

local s = adt.Set()

assert(s:empty())
s:push(10)
s:push("abc")
local t = {1,2,3}
s:push(t)
assert(s:size()==3)
assert(not s:empty())
assert(s:contains(10))
assert(s:contains("abc"))
assert(s:contains(t))

s:remove("abc")
assert(s:size()==2)
assert(s:contains(10))
assert(not s:contains("abc"))
assert(s:contains(t))

s:clear()
assert(s:empty())
assert(not s:contains(10))
assert(not s:contains("abc"))
assert(not s:contains(t))

local s = adt.Set()
s:push(10)
s:push("abc")
s:push(t)

local items = {[10]=false, ["abc"]=false, [t]=false}
for i in s:iteritems() do
   items[i] = true
end
assert.equals(items, {[10]=true, ["abc"]=true, [t]=true})

-- Set:remove() finds cdata objects

local s = adt.Set()
local item1 = ffi.new("uint8_t[16]")
local item2 = ffi.new("uint8_t[16]")
local item3 = ffi.new("uint8_t[16]")
s:push(item1)
s:push(item2)
s:push(item3)
s:remove(item1)
s:remove(item2)
s:remove(item3)
assert(s:empty())
