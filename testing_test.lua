local assert = require('assert')
local sched = require('sched')
local fs = require('fs')

local testing = require('testing')
-- the return value of this require() call is a top-level TestSuite
-- object predefined by the testing module (root_suite)

-- we can either add our tests directly to the root suite or create
-- child suites and add tests to those

local markers = {}

testing:add('add a test directly to the root suite', function()
   assert.equals(1,1)
   markers.oneisone = true
end)

-- if we do not pass a function, testing:add() creates a child suite

local child = testing:add('adding a child suite')
child:add('add a test to the child suite', function()
   assert.equals(2,2)
   markers.twoistwo = true
end)
child:add('add another test to the child suite', function()
   assert.equals(-2,-2)
   markers.minustwoisminustwo = true
end)

-- testing(...) is shorthand for testing:add(...)
-- (this also works on a child suite)

testing('the testing() shorthand', function()
   assert.equals(3,3)
   markers.threeisthree = true
end)

-- tests within a suite are not guaranteed to run sequentially
--
-- the only thing we can guarantee (for the current implementation) is
-- that tests in child suites are _scheduled_ later than tests of the
-- parent suite

testing(function()
   assert.equals(markers, {
      oneisone = true,
      threeisthree = true
   })
end)

-- if you want to do something after all tests in a suite finished,
-- use an after hook:

testing:after(function()
   assert.equals(markers, {
      oneisone = true,
      twoistwo = true,
      minustwoisminustwo = true,
      threeisthree = true
   })
end)

-- tests marked as `exclusive` own the CPU until they finish (i.e. the
-- scheduler won't schedule another thread until they finish)
--
-- note: use this feature sparingly as it can easily lead to lockups

local normal_results = {}

testing('normal 123', function()
   table.insert(normal_results, 1)
   sched.yield()
   table.insert(normal_results, 2)
   sched.yield()
   table.insert(normal_results, 3)
   sched.yield()
end)

testing('normal 456', function()
   table.insert(normal_results, 4)
   sched.yield()
   table.insert(normal_results, 5)
   sched.yield()
   table.insert(normal_results, 6)
   sched.yield()

   assert.equals(normal_results, { 1,4,2,5,3,6 })
end)

local exclusive_results = {}

testing:exclusive('exclusive 123', function()
   table.insert(exclusive_results, 1)
   sched.yield()
   table.insert(exclusive_results, 2)
   sched.yield()
   table.insert(exclusive_results, 3)
   sched.yield()
end)

testing:exclusive('exclusive 456', function()
   table.insert(exclusive_results, 4)
   sched.yield()
   table.insert(exclusive_results, 5)
   sched.yield()
   table.insert(exclusive_results, 6)
   sched.yield()

   assert.equals(exclusive_results, { 1,2,3,4,5,6 })
end)

-- tests marked as `nosched` are executed upfront in a separate round,
-- when the scheduler has not yet been created
--
-- this feature is mostly (only?) useful for testing the scheduler
-- itself

testing('running under a scheduler', function()
   assert(sched.running())
end)

testing:nosched('not running under a scheduler', function()
   assert(not sched.running())
end)

-- `before` hooks are executed once, before all tests within a suite

local suite = testing('before hooks')
suite:before(function(ctx)
   -- the passed table is a test context which can be used to store
   -- arbitrary objects
   --
   -- these objects are accessible in all descendants of the suite
   ctx.conn = 'this could be a database connection mock'
end)
suite:before(function(ctx)
   -- :before() can be used several times to add any number of hooks
   ctx.http_client = 'http client'
end)

suite:add('check test context', function(ctx)
   assert.equals(ctx.conn, 'this could be a database connection mock')
   assert.equals(ctx.http_client, 'http client')
   -- context modifications are scoped to the running test
   ctx.http_client = 'https client'
   ctx.checked = true
end)

suite('context modifications cannot escape their scope', function(ctx)
   assert.equals(ctx.http_client, 'http client')
   assert.is_nil(ctx.checked)
end)

-- after hooks are executed once, after all tests within a suite

suite:after(function(ctx)
   assert.equals(ctx.conn, 'this could be a database connection mock')
   assert.equals(ctx.http_client, 'http client')
end)

-- after hooks do not see context modifications made by children

suite:after(function(ctx)
   assert.is_nil(ctx.checked)
end)

-- child suites see context modifications of their parent

local child = suite:add('child')
child('child suites inherit context modifications', function(ctx)
   assert.equals(ctx.conn, 'this could be a database connection mock')
   assert.equals(ctx.http_client, 'http client')
end)

-- before_each and after_each hooks are run before and after each test

local counter = 0

suite:before(function()
  assert.equals(counter, 0)
end)

suite:before_each(function()
   counter = counter + 1
end)

suite('inside a test, counter should be 1', function()
   assert.equals(counter, 1)
end)

suite:after_each(function()
   counter = counter - 1
end)

suite:after(function()
   assert.equals(counter, 0)
end)

-- nosched tests cannot use before/after hooks

suite:nosched('nosched tests cannot use before/after hooks', function(ctx)
   assert.is_nil(ctx.conn)
   assert.is_nil(ctx.http_client)
end)

-- but they can use before_each and after_each

suite:nosched('nosched tests can use before_each/after_each hooks', function(ctx)
  assert.equals(counter, 1)
end)

-- the test context provides a nextid() method which can be used to
-- generate an integer guaranteed to be unique within the current test
-- run

testing('nextid', function(ctx)
   local id1 = ctx:nextid()
   assert.type(id1, 'number')
   local id2 = ctx:nextid()
   assert.type(id2, 'number')
   assert(id1 ~= id2)
end)

-- tests marked as `with_tmpdir` get a temporary directory which is
-- automatically removed when the test finishes (or fails)
--
-- the path of the temp directory is available as ctx.tmpdir

local s = testing('with_tmpdir')
s:before(function(ctx)
   assert.is_nil(ctx.saved_tmpdir_path)
   ctx.save_tmpdir_path = function(path)
      ctx.saved_tmpdir_path = path
   end
end)
s:after(function(ctx)
   assert.type(ctx.saved_tmpdir_path, "string")
   -- verify that the temp dir was removed
   assert(not fs.is_dir(ctx.saved_tmpdir_path))
end)
s:with_tmpdir('with_tmpdir', function(ctx)
   -- the temp directory path is at ctx.tmpdir
   assert.type(ctx.tmpdir, "string")
   assert(fs.is_dir(ctx.tmpdir))
   -- save_tmpdir_path() is inherited from parent context
   -- (a variable set in ctx would not be seen in the parent)
   ctx.save_tmpdir_path(ctx.tmpdir)
end)
