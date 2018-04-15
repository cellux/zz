local testing = require('testing')
local epoll = require('epoll')

testing("epoll", function()
   local poller = epoll.create()
   poller:close()
end)
