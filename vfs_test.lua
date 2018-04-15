local testing = require('testing')
local vfs = require('vfs')
local fs = require('fs')
local assert = require('assert')
local buffer = require('buffer')

-- ensure we are standing in srcdir
assert(fs.is_dir('testdata'))
assert(fs.is_reg('vfs_test.lua'))

testing("vfs", function()
   local root = vfs.Root()
   assert(not root:exists('arborescence.jpg'))
   root:mount('testdata')
   assert(root:exists('arborescence.jpg'))
   assert.equals(root:readfile('arborescence.jpg'), fs.readfile('testdata/arborescence.jpg'))
   root:mount('.', 'src')
   assert.equals(root:readfile('arborescence.jpg'), fs.readfile('testdata/arborescence.jpg'))
   assert.equals(root:readfile('src/vfs_test.lua'), fs.readfile('./vfs_test.lua'))

   -- vfs readfile returns a buffer
   assert(buffer.is_buffer(root:readfile('arborescence.jpg')))

   -- calls on vfs itself are proxied to a default Root instance
   vfs.mount('testdata', 'assets')
   assert(not vfs.exists('arborescence.jpg'))
   assert(not vfs.exists('testdata/arborescence.jpg'))
   assert(vfs.exists('assets/arborescence.jpg'))
   assert.equals(vfs.readfile('assets/arborescence.jpg'), fs.readfile('testdata/arborescence.jpg'))
end)
