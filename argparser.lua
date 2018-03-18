local re = require('re')

local M = {}

local constructors = {}

constructors['string'] = tostring
constructors['number'] = tonumber
constructors['bool'] = function(value) return true end

local function ArgDescriptor(arg_opts)
   local self = arg_opts
   if not self.name then
      ef("argument without a name")
   end
   if not self.type then
      if self.option then
         self.type = "bool"
      else
         self.type = "string"
      end
   end
   if not constructors[self.type] then
      ef("invalid type for argument '%s': %s", self.name, self.type)
   end
   if self.option then
      local m = re.Matcher(self.option)
      if m:match("^-(\\w)\\|--(\\w+)$") then
         self.option_short = m[1]
         self.option_long = m[2]
      elseif m:match("^-(\\w)$") then
         self.option_short = m[1]
      elseif m:match("^--(\\w+)$") then
         self.option_long = m[1]
      else
         ef("invalid option spec: %s", self.option)
      end
   end
   function self:is_option()
      return self.option and true or false
   end
   function self:collect(args, values, vidx)
      -- process argument at values[vidx]
      -- store value into args[self.name]
      -- return number of processed values
      local ctr = constructors[self.type]
      if self:is_option() then
         -- option (long or short)
         if self.type == "bool" then
            -- bool options don't need an extra argument
            -- simple presence of the option means the value is true
            args[self.name] = true
            return 1
         else
            -- for non-bool options the value is the next argument
            args[self.name] = ctr(values[vidx+1])
            return 2
         end
      else
         -- positional parameter
         args[self.name] = ctr(values[vidx])
         return 1
      end
   end
   return self
end

local function ArgParser(command_name, command_description)
   local self = {}

   local descriptors = {
      option_short = {},
      option_long = {},
      positional = {},
   }

   local function add_option_descriptor(option_type, d)
      local option_name = d[option_type]
      if option_name then
         assert(descriptors[option_type])
         if descriptors[option_type][option_name] then
            ef("double definition for option: %s", option_name)
         end
         descriptors[option_type][option_name] = d
      end
   end

   function self:add(arg_opts)
      local descriptor = ArgDescriptor(arg_opts)
      if descriptor:is_option() then
         -- only those will be added which are actually defined
         add_option_descriptor('option_short', descriptor)
         add_option_descriptor('option_long', descriptor)
      else
         table.insert(descriptors.positional, descriptor)
      end
   end

   local function is_option(value)
      return value:sub(1,1) == '-'
   end

   local function is_long_option(value)
      return value:sub(1,2) == '--'
   end

   local function option_name(value)
      if is_long_option(value) then
         return value:sub(3)
      else
         return value:sub(2)
      end
   end

   function self:parse(values)
      -- the runtime stores command line args into _G.arg
      values = values or _G.arg
      local args = {}
      local rest = {}
      -- set bool options to their default values
      local function init_options(ds)
         for _,d in pairs(ds) do
            if d.type=="bool" then
               args[d.name] = d.default or false
            end
         end
      end
      init_options(descriptors.option_short)
      init_options(descriptors.option_long)
      -- collect values
      local vidx = 1
      local pidx = 1
      while vidx <= #values do
         local value = values[vidx]
         local descriptor
         if is_option(value) then
            local name = option_name(value)
            if is_long_option(value) then
               descriptor = descriptors.option_long[name]
            else
               descriptor = descriptors.option_short[name]
            end
         else
            descriptor = descriptors.positional[pidx]
            if descriptor then
               pidx = pidx + 1
            end
         end
         if descriptor then
            vidx = vidx + descriptor:collect(args, values, vidx)
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
