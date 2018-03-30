local fs = require('fs')
local util = require('util')

local M = {}

local Target = util.Class()

function Target:create(tpath, mp)
   if mp and mp:sub(-1) ~= "/" then
      mp = mp.."/"
   end
   return {
      tpath = tpath,
      mp = mp,
   }
end

function Target:resolve(path)
   if self.mp then
      if path:sub(1,#self.mp) ~= self.mp then
         return nil
      else
         path = path:sub(#self.mp+1)
      end
   end
   return path
end

local function FSTarget(tpath, mp)
   local self = Target(tpath, mp)
   function self:exists(path)
      path = self:resolve(path)
      return path and fs.exists(fs.join(self.tpath, path))
   end
   function self:readfile(path)
      path = self:resolve(path)
      assert(path)
      return fs.readfile(fs.join(self.tpath, path))
   end
   return self
end

local Root = util.Class()

function Root:create()
   return {
      targets = {}
   }
end

function Root:mount(tpath, mp)
   if fs.is_dir(tpath) then
      table.insert(self.targets, FSTarget(tpath, mp))
   else
      ef("unable to mount target: %s", tpath)
   end
end

function Root:exists(path)
   for _,t in ipairs(self.targets) do
      if t:exists(path) then
         return t
      end
   end
   return false
end

function Root:readfile(path)
   for _,t in ipairs(self.targets) do
      if t:exists(path) then
         return t:readfile(path)
      end
   end
   ef("vfs file not found: %s", path)
end

M.Root = Root

local default_root

local function get_default_root()
   if not default_root then
      default_root = Root()
   end
   return default_root
end

local M_mt = {}

-- indexing the module with the name of a Root method returns a proxy
-- which is bound to the default root instance
function M_mt:__index(k)
   local root = get_default_root()
   local method = root[k]
   if type(method) == "function" then
      return function(...)
         return method(root, ...)
      end
   end
end

return setmetatable(M, M_mt)
