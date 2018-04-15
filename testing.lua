local util = require('util')

local M = {}

local Test = util.Class()

function Test:create(name, testfn, opts)
   return {
      name = name,
      testfn = testfn,
      opts = opts or {},
      ok = nil,
      err = nil,
   }
end

function Test:exclusive()
   self.opts.exclusive = true
   return self
end

function Test:is_exclusive()
   return self.opts.exclusive
end

function Test:nosched()
   self.opts.nosched = true
   return self
end

function Test:is_nosched()
   return self.opts.nosched
end

function Test:run(tc)
   self.ok, self.err = pcall(self.testfn, tc)
end

local TestSuite = util.Class()

function TestSuite:create(name)
   return {
      name = name,
      tests = {},
      suites = {},
      __call = function(self, ...)
         return self:add(...)
      end
   }
end

function TestSuite:add(name, testfn, opts)
   if not testfn then
      local ts = TestSuite(name)
      table.insert(self.suites, ts)
      return ts
   else
      local t = Test(name, testfn, opts)
      table.insert(self.tests, t)
      return t
   end
end

function TestSuite:exclusive(name, testfn)
   return self:add(name, testfn, { exclusive = true })
end

function TestSuite:nosched(name, testfn)
   return self:add(name, testfn, { nosched = true })
end

function TestSuite:walk(process)
   for _,ts in ipairs(self.suites) do
      ts:walk(process)
   end
   for _,t in ipairs(self.tests) do
      process(t)
   end
end

function TestSuite:run(tc)
   self:walk(function(t)
      if t:is_nosched() then
         t:run(tc)
      end
   end)
   local sched = require('sched')
   self:walk(function(t)
      if not t:is_nosched() then
         local function runner()
            t:run(tc)
         end
         if t:is_exclusive() then
            sched.exclusive(runner)
         else
            sched(runner)
         end
      end
   end)
   sched()
   self:walk(function(t)
      pf("%s %s", t.ok and "OK" or "FAIL", t.name)
      if not t.ok then
         print(t.err)
      end
   end)
end

local TestContext = util.Class()

function TestContext:create()
   return {
      _nextid = 0
   }
end

function TestContext:nextid()
   self._nextid = self._nextid + 1
   return self._nextid
end

local root = TestSuite()

function M.run_tests()
   local tc = TestContext()
   root:run(tc)
end

local M_mt = {}

function M_mt:__call(...)
   return root:add(...)
end

return setmetatable(M, M_mt)
