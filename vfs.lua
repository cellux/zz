local fs = require('fs')
local stream = require('stream')
local util = require('util')

local M = {}

local Target = util.Class()

function Target:new(tpath, mp)
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
   function self:stream(path)
      path = self:resolve(path)
      assert(path)
      local f = fs.open(fs.join(self.tpath, path))
      return stream(f)
   end
   return self
end

local Root = util.Class()

function Root:new()
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

function Root:_get_calling_package_descriptor()
   -- every function of package P has a ZZ_PACKAGE_DESCRIPTOR field in
   -- its environment which contains the package descriptor of P
   local pd = ZZ_PACKAGE_DESCRIPTOR -- this is the pd for zz core

   -- we climb up the stack, looking for the first function whose env
   -- has a ZZ_PACKAGE_DESCRIPTOR different to ours. if we find one,
   -- that's the package which made the current vfs call. if we don't,
   -- the call came from the core package.
   local level = 2
   while true do
      local ok, env = pcall(getfenv, level)
      if not ok or not env then
         break
      end
      if env.ZZ_PACKAGE_DESCRIPTOR and env.ZZ_PACKAGE_DESCRIPTOR ~= pd then
         pd = env.ZZ_PACKAGE_DESCRIPTOR
         break
      end
      level = level + 1
   end

   assert(pd)
   return pd
end

function Root:_possible_vfs_paths_for(path)
   -- path may be fully qualified
   local paths = { path }

   -- path may be located in the calling package
   local pd = self:_get_calling_package_descriptor()
   table.insert(paths, sf('%s/%s', pd.package, path))

   -- path may be located in an import of the calling package
   for _,pkg in ipairs(pd.imports) do
      table.insert(paths, sf('%s/%s', pkg, path))
   end

   return paths
end

function Root:find_target(filter)
   for _,t in ipairs(self.targets) do
      if filter(t) then
         return t
      end
   end
end

function Root:exists(path)
   for _,possible_path in ipairs(self:_possible_vfs_paths_for(path)) do
      local t = self:find_target(function(t)
         return t:exists(possible_path)
      end)
      if t then
         return t
      end
   end
   return false
end

function Root:stream(path)
   for _,possible_path in ipairs(self:_possible_vfs_paths_for(path)) do
      local t = self:find_target(function(t)
         return t:exists(possible_path)
      end)
      if t then
         return t:stream(possible_path)
      end
   end
   ef("vfs file not found: %s", path)
end

function Root:readfile(path)
   local s = self:stream(path)
   local contents = s:read(0)
   s:close()
   return contents
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
