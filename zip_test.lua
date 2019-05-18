local testing = require('testing')('zip')
local zip = require('zip')
local fs = require('fs')
local stream = require('stream')
local assert = require('assert')

testing("version", function()
   assert.type(zip.version(), 'string')
end)

testing("open", function()
   fs.with_tmpdir(function(tmpdir)
      assert.throws('No such file', function()
         local zip = zip.open(fs.join(tmpdir, 'nonexistent.zip'))
      end)
   end)
end)

testing("create+close does not create empty archives", function()
   fs.with_tmpdir(function(tmpdir)
      local zip = zip.open(fs.join(tmpdir, 'test.zip'), zip.ZIP_CREATE)
      zip:close()
      assert(not fs.exists(fs.join(tmpdir, 'test.zip')))
   end)
end)

testing("the rest", function()
   fs.with_tmpdir(function(tmpdir)
      local zf = zip.open(fs.join(tmpdir, 'test.zip'), zip.ZIP_CREATE)

      -- file_add / source_file
      zf:file_add("some/path/data.txt", zf:source_file("testdata/www.google.com.txt"))
      zf:file_add("some/path/arbor.jpg", zf:source_file("testdata/arborescence.jpg"))

      -- file_add / source_buffer
      zf:file_add("heiligenkreuz", zf:source_buffer("Wir sind beim Heiligenkreuz", 8)) -- data, len

      zf:close()

      assert(fs.exists(fs.join(tmpdir, 'test.zip')))

      local zf = zip.open(fs.join(tmpdir, 'test.zip'))

      -- get_num_entries
      assert.equals(zf:get_num_entries(), 3)

      -- name_locate
      assert.equals(zf:name_locate("arbor.jpg"), -1)
      assert.equals(zf:name_locate("arbor.jpg", zip.ZIP_FL_NODIR), 1)
      assert.equals(zf:name_locate("some/path/arbor.jpg"), 1)
      assert.equals(zf:name_locate("some/path/data.txt"), 0)
      assert.equals(zf:name_locate("heiligenkreuz"), 2)

      -- get_name
      assert.equals(zf:get_name(0), "some/path/data.txt")
      assert.equals(zf:get_name(1), "some/path/arbor.jpg")
      assert.equals(zf:get_name(2), "heiligenkreuz")
      assert.throws('Invalid argument', function()
         zf:get_name(10)
      end)

      -- stat
      assert.throws('No such file', function()
         local st = zf:stat("nonexistent")
      end)
      local st = zf:stat("some/path/data.txt")
      assert.equals(st.name, "some/path/data.txt")
      assert.equals(st.index, 0)
      assert.equals(st.size, 501)
      local st = zf:stat("some/path/arbor.jpg")
      assert.equals(st.name, "some/path/arbor.jpg")
      assert.equals(st.index, 1)
      assert.equals(st.size, 81942)
      local st = zf:stat("heiligenkreuz")
      assert.equals(st.name, "heiligenkreuz")
      assert.equals(st.index, 2)
      assert.equals(st.size, 8)

      -- stat_index
      assert.throws('Invalid argument', function()
         local st = zf:stat_index(10)
      end)
      local st = zf:stat_index(0)
      assert.equals(st.name, "some/path/data.txt")
      assert.equals(st.index, 0)
      assert.equals(st.size, 501)
      local st = zf:stat_index(1)
      assert.equals(st.name, "some/path/arbor.jpg")
      assert.equals(st.index, 1)
      assert.equals(st.size, 81942)
      local st = zf:stat_index(2)
      assert.equals(st.name, "heiligenkreuz")
      assert.equals(st.index, 2)
      assert.equals(st.size, 8)

      -- fopen, fread (via stream), close
      local f = zf:fopen("some/path/arbor.jpg")
      assert.equals(stream(f):read(0), fs.readfile("testdata/arborescence.jpg"))
      f:close()

      local f = zf:fopen("some/path/data.txt")
      assert.equals(stream(f):read(0), fs.readfile("testdata/www.google.com.txt"))
      f:close()

      local f = zf:fopen("heiligenkreuz")
      assert.equals(stream(f):read(0), "Wir sind")
      f:close()

      -- ZipFile:close() is an alias for ZipFile:fclose()
      assert.equals(f.close, f.fclose)

      zf:close()
   end)
end)
