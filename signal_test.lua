local testing = require('testing')('signal')
local assert = require('assert')
local sched = require('sched')
local process = require('process')
local signal = require('signal')

testing:before(function(ctx)
   ctx.signal_data = {}
   function ctx.handler(data)
      local signum, pid = unpack(data)
      if signum == signal.SIGUSR1 then
         sched.emit('SIGUSR1', data)
      end
   end
   sched.on('signal', ctx.handler)
end)

testing:after(function(ctx)
   sched.off('signal', ctx.handler)
end)

testing('signal listeners', function(ctx)
   process.kill(nil, signal.SIGUSR1)
   local data = sched.wait('SIGUSR1')
   assert.type(data, 'table')
   local signum, pid = unpack(data)
   assert.equals(signum, signal.SIGUSR1)
   assert.equals(pid, process.getpid())
end)
