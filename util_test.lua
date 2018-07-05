local testing = require('testing')('util')
local util = require('util')
local ffi = require('ffi')
local assert = require('assert')
local buffer = require('buffer')

testing("round", function()
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
end)

testing("align", function()
   assert.equals(util.align_down(43, 16), 32)
   assert.equals(util.align_up(43, 16), 48)
end)

testing("next_power_of_2", function()
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
end)

testing("Accumulator", function()
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
end)

testing("classes", function()
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
end)

testing("instance metamethods", function()
   local A = util.Class()
   function A:create()
      return {
         a=1, b=3, c=8,
         __call = function(self, x)
            return self.c + x
         end
      }
   end
   local a = A()
   assert.equals(a(10), 18)
end)

testing("constructor should not override __index", function()
   local A = util.Class()
   A.x = 5
   assert.throws('attempt to override __index metamethod', function()
      local a = A { __index = {} }
   end)
   function A:create()
      return { __index = {} }
   end
   assert.throws('attempt to override __index metamethod', function()
      local a = A()
   end)
end)

testing("chain", function()
   -- chaining means replacing the __index metamethod of a table with
   -- a function or table which can override any of the keys

   local A = util.Class()
   A.x = 5
   A.z = 3
   local B = util.Class(A)
   B.y = 8
   B.w = 4
   local b = B { y = 6 }

   local orig_b = b
   local orig_b_mt = getmetatable(b)
   local orig_b_mt__index = getmetatable(b).__index

   -- chaining with a function
   b = util.chain(b, function(self, name)
      -- if the function returns a value which is logically true, it is
      -- returned as the lookup result, otherwise, the lookup continues
      -- through the original __index
      return name == "z" and 8
   end)
   assert.equals(b.x, 5) -- comes from A
   assert.equals(b.y, 6) -- comes from b
   assert.equals(b.z, 8) -- supplied by the chained function
   assert.equals(b.w, 4) -- comes from B
   assert.equals(b.o, nil)

   -- the object remains the same
   assert.equals(b, orig_b)

   -- the metatable remains the same
   assert.equals(getmetatable(b), orig_b_mt)

   -- but __index is replaced by a proxy
   assert(getmetatable(b).__index ~= orig_b_mt__index)

   -- chaining with a table
   b = util.chain(b, { y = 2, w = 7, z = 4 })
   assert.equals(b.x, 5) -- comes from A
   assert.equals(b.y, 6) -- y is a direct member of b so we get b.y
                         -- (__index was not used at all)
   assert.equals(b.z, 4) -- z is in a descendant so it's overridden
   assert.equals(b.w, 7)

   -- when chaining a table which does not yet have a metatable, a new
   -- metatable is created automatically
   local x = { a=1, b=2, c=3 }
   assert.type(getmetatable(x), "nil")
   local x = util.chain(x, { x = 5 })
   assert.type(getmetatable(x), "table")
   assert.equals(x.a, 1)
   assert.equals(x.b, 2)
   assert.equals(x.c, 3)
   assert.equals(x.x, 5)
   assert.equals(x.y, nil)
end)

testing("chainlast", function()
   -- the only difference to chain() is that the supplied proxy is
   -- called only if the key has not been found anywhere

   local A = util.Class()
   A.x = 5
   A.z = 3
   local B = util.Class(A)
   B.y = 8
   B.w = 4
   local b = B { y = 6 }

   b = util.chain(b, { x = 10 })
   -- with chain(), the proxy is called immediately if the lookup key
   -- is not found in the object
   assert.equals(b.x, 10)

   b = util.chainlast(b, { z = 11, p = 7 })
   -- with chainlast(), the proxy is called only if z cannot be found
   -- anywhere while traversing the __index chain
   assert.equals(b.z, 3)
   assert.equals(b.p, 7)
end)

testing("EventEmitter", function()
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
end)

testing("lines", function()
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
end)

testing("hexstr", function()
   assert.equals(util.hexstr(), "")
   assert.equals(util.hexstr("abc"), "616263")
   assert.equals(util.hexstr("\x00\x55\xaa\xff"), "0055aaff")
   assert.equals(util.hexstr(buffer.copy("abc")), "616263")
end)

testing("oct", function()
   assert.equals(util.oct(777), 511)
   assert.equals(util.oct("777"), 511)
end)

testing("extend", function()
   assert.equals(util.extend({}, {1,2,3}), {1,2,3})
   assert.equals(util.extend({1,2,3}, {}), {1,2,3})
   assert.equals(util.extend({1,2,3}, nil), {1,2,3})
   assert.equals(util.extend({1,2,3}, {4,5,6}), {1,2,3,4,5,6})
end)

testing("map", function()
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
end)

testing("reduce", function()
   assert.equals(15, util.reduce(function(sum,x) return sum+x end, {1,2,3,4,5}, 0))
   assert.equals(21, util.reduce(function(sum,x) return sum+x end, {1,2,3,4,5}, 6))
end)

testing("filter", function()
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
end)
   
testing("indexof", function()
   assert.equals(nil, util.indexof('x',{}))
   assert.equals(nil, util.indexof('x',{'a','b','c','d','e','f'}))
   assert.equals(1, util.indexof('a',{'a','b','c','d','e','f'}))
   assert.equals(4, util.indexof('d',{'a','b','c','d','e','f'}))
   assert.equals(6, util.indexof('f',{'a','b','c','d','e','f'}))
end)
   
testing("contains", function()
   assert(not util.contains('x',{}))
   assert(not util.contains('x',{'a','b','c','d','e','f'}))
   assert(util.contains('a',{'a','b','c','d','e','f'}))
   assert(util.contains('d',{'a','b','c','d','e','f'}))
   assert(util.contains('f',{'a','b','c','d','e','f'}))
end)
   
testing("reverse", function()
   assert.equals(util.reverse({1,2,3,4}), {4,3,2,1})
end)

local function make_thrower(throw, ...)
   local throw_args = {...}
   local function thrower()
      throw(unpack(throw_args))
   end
   local function willthrow()
      thrower()
   end
   local function maythrow()
      willthrow()
   end
   return maythrow
end

testing("throw", function()
   local f = make_thrower(util.throw)
   local ok, e = pcall(f)
   assert.is_false(ok)
   assert(util.is_error(e))
   assert.equals(e.class, "error")
   assert.equals(e.message, "runtime error")
   assert.equals(tostring(e), "runtime error")
   assert.type(e.info, "table")
   assert.equals(e.info.name, "thrower")
   assert.type(e.info.source, "string")
   assert.type(e.info.short_src, "string")
   assert.type(e.info.linedefined, "number")
   assert.type(e.info.lastlinedefined, "number")
   assert.type(e.info.currentline, "number")

   local f = make_thrower(util.throw, "my-error")
   local ok, e = pcall(f)
   assert.is_false(ok)
   assert(util.is_error(e))
   assert.equals(e.class, "my-error")
   assert.equals(e.message, "runtime error")
   assert.equals(tostring(e), "runtime error")

   local f = make_thrower(util.throw, "my-error", "this is an error message")
   local ok, e = pcall(f)
   assert.is_false(ok)
   assert(util.is_error(e))
   assert.equals(e.class, "my-error")
   assert.equals(e.message, "this is an error message")
   assert.equals(tostring(e), "this is an error message")
   -- we also get a traceback of the location where the error was thrown
   local traceback_pattern = "^this is an error message\nstack traceback:\n\\s+[^[:space:]]+/util_test\\.lua:\\d+: in function 'thrower'\n"
   assert.match(traceback_pattern, e.traceback)
end)

testing("throwat", function()
   local f = make_thrower(util.throwat, 2, "my-error", "this is an error message")
   local ok, e = pcall(f)
   assert.is_false(ok)
   assert(util.is_error(e))
   assert.equals(e.class, "my-error")
   assert.equals(e.message, "this is an error message")
   assert.equals(tostring(e), "this is an error message")
   local traceback_pattern = "^this is an error message\nstack traceback:\n\\s+[^[:space:]]+/util_test\\.lua:\\d+: in function 'willthrow'\n"
   assert.match(traceback_pattern, e.traceback)
end)

testing("pcall", function()
   local f = make_thrower(error, "blah")
   local ok, e = util.pcall(f)
   assert.is_false(ok)
   assert(util.is_error(e))
   assert.equals(e.class, "error")
   assert.match("^\\S+/util_test\\.lua:\\d+: blah", e.message)
   assert.match("^\\S+/util_test\\.lua:\\d+: blah", tostring(e))
   local traceback_pattern = "^\\S+/util_test\\.lua:\\d+: blah\nstack traceback:\n\\s+\\S+/util_test\\.lua:\\d+: in function 'thrower'\n"
   assert.match(traceback_pattern, e.traceback)

   local f = make_thrower(util.throwat, 2, "merv", "joie")
   local ok, e = util.pcall(f)
   assert.is_false(ok)
   assert(util.is_error(e))
   assert.equals(e.class, "merv")
   assert.equals(e.message, "joie")
   assert.equals(tostring(e), "joie")
   local traceback_pattern = "^joie\nstack traceback:\n\\s+\\S+/util_test\\.lua:\\d+: in function 'willthrow'\n"
   assert.match(traceback_pattern, e.traceback)
end)
