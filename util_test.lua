local util = require('util')
local ffi = require('ffi')
local assert = require('assert')
local buffer = require('buffer')

-- round

assert.equals(util.round(0), 0)
assert.equals(util.round(0.1), 0)
assert.equals(util.round(-0.1), 0)
assert.equals(util.round(0.4), 0)
assert.equals(util.round(-0.4), 0)
-- we use "round half away from zero" method
assert.equals(util.round(0.5), 1)
assert.equals(util.round(-0.5), -1)
assert.equals(util.round(0.9), 1)
assert.equals(util.round(-0.9), -1)

assert.equals(util.round(100), 100)
assert.equals(util.round(100.1), 100)
assert.equals(util.round(99.9), 100)
assert.equals(util.round(100.4), 100)
assert.equals(util.round(99.6), 100)
assert.equals(util.round(100.5), 101)
assert.equals(util.round(99.5), 100)
assert.equals(util.round(100.9), 101)
assert.equals(util.round(99.1), 99)

-- round shall also work for native floats
local f = ffi.new("float[1]")
f[0] = 3.14
assert.equals(util.round(f[0]), 3)
f[0] = -3.14
assert.equals(util.round(f[0]), -3)
f[0] = 3.5
assert.equals(util.round(f[0]), 4)
f[0] = -3.5
assert.equals(util.round(f[0]), -4)
f[0] = 3.64
assert.equals(util.round(f[0]), 4)
f[0] = -3.64
assert.equals(util.round(f[0]), -4)

-- align_*

assert.equals(util.align_down(43, 16), 32)
assert.equals(util.align_up(43, 16), 48)

-- next_power_of_2

assert.equals(util.next_power_of_2(0), 1)
assert.equals(util.next_power_of_2(1), 1)
assert.equals(util.next_power_of_2(2), 2)
assert.equals(util.next_power_of_2(3), 4)
assert.equals(util.next_power_of_2(4), 4)
assert.equals(util.next_power_of_2(5), 8)
assert.equals(util.next_power_of_2(7), 8)
assert.equals(util.next_power_of_2(8), 8)
assert.equals(util.next_power_of_2(9), 16)
assert.equals(util.next_power_of_2(10000), 16384)
assert.equals(util.next_power_of_2(1000000), 1048576)

-- accumulator

local accum = util.Accumulator()
accum:feed(5)
accum(8)
accum(-3)
assert.equals(accum.n, 3)
assert.equals(accum.sum, 5+8-3)
assert.equals(accum.avg, (5+8-3)/3)
assert.equals(accum.min, -3)
assert.equals(accum.max, 8)
assert.equals(accum.last, -3)

-- classes

-- a class without a `create' method creates empty tables as instances
local A = util.Class()
local a = A()
assert.equals(a, {})

-- if we pass a single table to the constructor, it will be the instance
local inst = { x=5, y=8 }
local a = A(inst)
assert(a==inst)

-- a simple getter

function A:get_x()
   return self.x
end
assert.equals(a:get_x(), 5)

-- if we define a `create' method, it will be used to create instances
local A = util.Class()
function A:create(opts)
   return opts or {"undefined"}
end
function A:f()
   return 5
end
function A:g()
   return "hello"
end
local a = A { x=1, y=2 }
assert.equals(a, { x=1, y=2 })
assert.equals(a:f(), 5)
assert.equals(a:g(), "hello")
assert.equals(A(), {"undefined"})
assert.equals(A():f(), 5)

-- inheritance

local B = util.Class(A) -- specify the parent as a single argument
local b = B()
assert.equals(b, {"undefined"}) -- create() method inherited from A
assert.equals(b:g(), "hello")

local C = util.Class(B)
local c = C()
assert.equals(c:f(), 5)

-- method override

function B:f()
   return 10
end

assert.equals(c:f(), 10)

local c = C { a=1, b=3, c=8 }
assert.equals(c, { a=1, b=3, c=8 })
assert.equals(c:f(), 10)
assert.equals(c:g(), "hello")

-- chain
--
-- chaining means replacing the __index metamethod of a table with a
-- proxy to the original one. the proxy can override any of the keys.

local A = util.Class()
local a = A { x = 5, y = 6 }

-- chain with function
a = util.chain(a, function(self, name)
   -- if the function returns a value which is logically true, it is
   -- returned as the lookup result, otherwise, the lookup continues
   -- through the original __index
   return name == "z" and 8
end)
assert.equals(a.x, 5)
assert.equals(a.y, 6)
assert.equals(a.z, 8)
assert.equals(a.w, nil)

-- chain with table
a = util.chain(a, { y = 2, w = 7, z = 4 })
assert.equals(a.x, 5)
assert.equals(a.y, 6) -- y is a direct member of a so we get a.y
                      -- (__index was not used at all)
assert.equals(a.z, 4) -- z is in a descendant so it's overridden
assert.equals(a.w, 7)

-- EventEmitter

local obj = util.EventEmitter {
   x = 5,
   s = "abc",
   f = 1.5,
}

function obj:change_something()
   self.x = 10
   self:emit('something-changed', 1, 2, 3)
end

obj:on('something-changed', function(...)
   assert.equals({...}, {1,2,3})
   obj.s = "hulaboy"
end)

obj:on('something-changed', function(...)
   assert.equals({...}, {1,2,3})
   obj.f = -12.5
end)

assert.equals(obj.x, 5)
assert.equals(obj.s, "abc")
assert.equals(obj.f, 1.5)

obj:change_something()

assert.equals(obj.x, 10)
assert.equals(obj.s, "hulaboy")
assert.equals(obj.f, -12.5)

-- lines

local text = [[	hello
this
is   

good

]]

local lines = {}
for line in util.lines(text) do
   table.insert(lines, line)
end
assert.equals(lines, {"	hello","this","is   ","","good",""})

-- hexstr

assert.equals(util.hexstr(), "")
assert.equals(util.hexstr("abc"), "616263")
assert.equals(util.hexstr("\x00\x55\xaa\xff"), "0055aaff")
assert.equals(util.hexstr(buffer.copy("abc")), "616263")

-- oct

assert.equals(util.oct(777), 511)
assert.equals(util.oct("777"), 511)

-- extend

assert.equals(util.extend({}, {1,2,3}), {1,2,3})
assert.equals(util.extend({1,2,3}, {}), {1,2,3})
assert.equals(util.extend({1,2,3}, nil), {1,2,3})
assert.equals(util.extend({1,2,3}, {4,5,6}), {1,2,3,4,5,6})

-- map

local function square(x) return x*x end
assert.equals(util.map(square, {}), {})
assert.equals(util.map(square, nil), {})
assert.equals(util.map(square, {3,4,5}), {9,16,25})

local t = {
   { name = "John", age = 11 },
   { name = "Jack", age = 22 },
   { name = "Doug", age = 33 },
}

assert.equals(util.map("name", t), { "John", "Jack", "Doug" })
assert.equals(util.map("age", t), { 11, 22, 33 })

-- reduce

assert.equals(15, util.reduce(function(sum,x) return sum+x end, {1,2,3,4,5}, 0))
assert.equals(21, util.reduce(function(sum,x) return sum+x end, {1,2,3,4,5}, 6))

-- filter
local function even(x)
   return x % 2 == 0
end
local function odd(x)
   return not even(x)
end
assert.equals(util.filter(even, nil), {})
assert.equals(util.filter(even, {}), {})
assert.equals(util.filter(even, {1,2,3,4,5}), {2,4})
assert.equals(util.filter(odd, {1,2,3,4,5}), {1,3,5})

-- indexof
assert.equals(nil, util.indexof('x',{}))
assert.equals(nil, util.indexof('x',{'a','b','c','d','e','f'}))
assert.equals(1, util.indexof('a',{'a','b','c','d','e','f'}))
assert.equals(4, util.indexof('d',{'a','b','c','d','e','f'}))
assert.equals(6, util.indexof('f',{'a','b','c','d','e','f'}))

-- contains
assert(not util.contains('x',{}))
assert(not util.contains('x',{'a','b','c','d','e','f'}))
assert(util.contains('a',{'a','b','c','d','e','f'}))
assert(util.contains('d',{'a','b','c','d','e','f'}))
assert(util.contains('f',{'a','b','c','d','e','f'}))
