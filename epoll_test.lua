local epoll = require('epoll')

local poller = epoll.create()
poller:close()
