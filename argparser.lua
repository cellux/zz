local re = require('re')

local M = {}

local constructors = {}

constructors['string'] = function(value)
   return tostring(value)
end

constructors['bool'] = function(value)
   return true
end

constructors['number'] = function(value)
   return tonumber(value)
end

local function ArgDescriptor(arg_opts)
   local self = arg_opts
   if not self.name then
      error("argument without a name")
   end
   if not self.type then
      error("argument has no type")
   end
   if not constructors[self.type] then
      ef("invalid type for argument '%s': %s", self.name, self.type)
   end
   if self.option then
      local m = re.match("^-(\\w)\\|--(\\w+)$", self.option)
      if m then
         self.option_short = m[1]
         self.option_long = m[2]
      else
         local m = re.match("^-(\\w)$", self.option)
         if m then
            self.option_short = m[1]
         else
            local m = re.match("^--(\\w+)$", self.option)
            if m then
               self.option_long = m[1]
            end
         end
      end
   end
   function self:is_opt()
      return self.option and true or false
   end
   function self:process(args, values, vidx)
      local ctr = constructors[self.type]
      if self:is_opt() then
         -- option
         if self.type == "bool" then
            args[self.name] = true
            return vidx + 1
         else
            args[self.name] = ctr(values[vidx+1])
            return vidx + 2
         end
      else
         -- positional parameter
         args[self.name] = ctr(values[vidx])
         return vidx + 1
      end
   end
   return self
end

local function ArgParser(command_name, command_description)
   local self = {}

   descriptors = {
      option_short = {},
      option_long = {},
      positional = {},
   }

   function self:add_option_descriptor(opt_type, d)
      local opt_name = d[opt_type]
      if opt_name then
         assert(descriptors[opt_type])
         assert(not descriptors[opt_type][opt_name])
         descriptors[opt_type][opt_name] = d
      end
   end

   function self:add(arg_opts)
      local descriptor = ArgDescriptor(arg_opts)
      if descriptor:is_opt() then
         self:add_option_descriptor('option_short', descriptor)
         self:add_option_descriptor('option_long', descriptor)
      else
         table.insert(descriptors.positional, descriptor)
      end
   end

   local function is_opt(value)
      return value:sub(1,1) == '-'
   end

   local function is_long_opt(value)
      return value:sub(1,2) == '--'
   end

   local function opt_name(value)
      if is_long_opt(value) then
         return value:sub(3)
      else
         return value:sub(2)
      end
   end

   function self:parse(values)
      values = values or _G.arg
      local args = {}
      local rest = {}
      -- set flags to their default value
      local function init_flags(ds)
         for _,d in pairs(ds) do
            if d:is_opt() and d.type=="bool" then
               args[d.name] = d.default or false
            end
         end
      end
      init_flags(descriptors.option_short)
      init_flags(descriptors.option_long)
      -- process values
      local vidx = 1
      local pidx = 1
      while vidx <= #values do
         local value = values[vidx]
         local descriptor
         if is_opt(value) then
            if is_long_opt(value) then
               descriptor = descriptors.option_long[opt_name(value)]
            else
               descriptor = descriptors.option_short[opt_name(value)]
            end
         else
            descriptor = descriptors.positional[pidx]
            if descriptor then
               pidx = pidx + 1
            end
         end
         if descriptor then
            vidx = descriptor:process(args, values, vidx)
         else
            table.insert(rest, value)
            vidx = vidx + 1
         end
      end
      return args, rest
   end

   return self
end

local M_mt = {}

function M_mt:__call(...)
   return ArgParser(...)
end

return setmetatable(M, M_mt)
