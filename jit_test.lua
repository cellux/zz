local testing = require('testing')('jit')

testing("bcsave", function()
   local bcsave = require("jit.bcsave")
   assert(type(bcsave.start)=="function")
end)
