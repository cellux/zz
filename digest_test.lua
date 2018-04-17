local testing = require('testing')('digest')
local digest = require('digest')
local buffer = require('buffer')
local assert = require('assert')
local fs = require('fs')
local util = require('util')

local function fibonacci()
   local queue = {1,1}
   local function next()
      local rv = queue[1]
      queue[1] = queue[2]
      queue[2] = rv + queue[1]
      return rv
   end
   return next
end

local function test_digest(buf, digest_fn, digest_hex)
   -- process the whole string at once
   assert.equals(util.hexstr(digest_fn(buf)), digest_hex)
   -- process data in chunks
   local digest = digest_fn()
   local offset = 0
   for n in fibonacci() do
      local chunk_size = math.min(#buf-offset, n)
      digest:update(buf.ptr+offset, chunk_size)
      offset = offset + chunk_size
      if offset == #buf then
         break
      end
   end
   assert.equals(util.hexstr(digest:final()), digest_hex)
end

testing("hexstr", function()
   assert.equals(util.hexstr(buffer.copy('abcd')), '61626364')
end)

testing("digest", function()
   local data = fs.readfile('testdata/arborescence.jpg')
   test_digest(data, digest.md4, '97d7daac924ff41af3e37b14373ac179')
   test_digest(data, digest.md5, '58823f6d5e1d154d37d9aa2dbaf27371')
   test_digest(data, digest.sha1, '77dd6183ed6e8b0f829ae70844f9de74b5151d46')
   test_digest(data, digest.sha224, '828f4268bdf4ae05d1ca32d0618840d29bec8309627b595f702c07ce')
   test_digest(data, digest.sha256, 'fb0069a988163cead062b2b1b5dfca23a5d0e0a8abace9cbaf1007a0dc4931ae')
   test_digest(data, digest.sha384, 'aa86c8de290c6c635da4bf6cff3d9e162d12070db9dda0660c20ee36b5759a2ee24d0bb01a89f746989fad971cb0d782')
   test_digest(data, digest.sha512, 'a9ecfab822675ac5b0cf90dbe52897c9f0cd515f61ee725d967c0334c38f4abf6111f1d616e515e785306ab19846e168d4a814eb32b247a91534fec3ed20c32e')
   --test_digest(data, digest.mdc2, '13d5d1eb5ec6fd5de026113b45975a92')
   test_digest(data, digest.ripemd160, 'b4054d90852eaa7696c55f7bfcd2e3eff284c2bc')
end)
