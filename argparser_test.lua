local argparser = require('argparser')
local assert = require('assert')

-- simple positional arguments

local ap = argparser("command-name", "command short description")
ap:add {
   name = "arg1",
   type = "string",
   desc = "first positional argument",
}
ap:add {
   name = "arg2",
   type = "string",
   desc = "second positional argument",
}
ap:add {
   name = "arg3",
   type = "string",
   desc = "third positional argument",
}
local args = ap:parse {"value1", "value2", "value3"}
assert.equals(args, { arg1 = "value1",
                      arg2 = "value2",
                      arg3 = "value3" })

-- positional arguments + options

local ap = argparser("command-name", "command short description")
ap:add {
   name = "noun",
   type = "string",
   desc = "type of object",
}
ap:add {
   name = "config_path",
   type = "string",
   option = "-c|--config",
   desc = "path to configuration file",
}
ap:add {
   name = "silent",
   type = "bool",
   option = "-s|--silent",
   desc = "don't soak the user in superfluous output",
}
ap:add {
   name = "verbose",
   -- for an option, type defaults to "bool"
   option = "-v|--verbose",
   desc = "don't soak the user in superfluous output",
}
ap:add {
   name = "timeout",
   type = "number",
   option = "--timeout",
   desc = "timeout in seconds",
}
ap:add {
   name = "username",
   type = "string",
   option = "-u|--user",
   desc = "user name",
}
ap:add {
   name = "password",
   type = "string",
   option = "-p|--pass",
   desc = "password",
}
ap:add {
   name = "verb",
   -- for a positional arg, type defaults to "string"
   desc = "name of action to execute",
}

local args = ap:parse {"vm","list",
                       "-c", "/etc/vm.config",
                       "-u", "rb",
                       "-p", "passpass",
                       "-v"}
assert.equals(args, { noun = "vm",
                      verb = "list",
                      config_path = "/etc/vm.config",
                      username = "rb",
                      password = "passpass",
                      silent = false,
                      verbose = true })

local args = ap:parse {"vm","list",
                       "--config", "/etc/vm.config",
                       "--user", "rb",
                       "--pass", "passpass",
                       "--silent",
                       "--timeout", "3600"}
assert.equals(args, { noun = "vm",
                      verb = "list",
                      config_path = "/etc/vm.config",
                      username = "rb",
                      password = "passpass",
                      silent = true,
                      verbose = false,
                      timeout = 3600, })

-- rest arguments

local args, rest = ap:parse {"vm","list",
                             "rest1",
                             "--config", "/etc/vm.config",
                             "--user", "rb",
                             "rest2",
                             "--pass", "passpass",
                             "--silent",
                             "--unknown", "value",
                             "rest3",
                             "-x", "missing"}
assert.equals(args, { noun = "vm",
                      verb = "list",
                      config_path = "/etc/vm.config",
                      username = "rb",
                      password = "passpass",
                      silent = true,
                      verbose = false })

assert.equals(rest, {'rest1',
                     'rest2',
                     '--unknown', 'value',
                     'rest3',
                     '-x', 'missing'})
