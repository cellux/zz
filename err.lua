local M = {}

local Err_mt = {
   __tostring = function(self)
      return string.format("%s (%d)", self.msg, self.code)
   end,
}

function M.Err(code, msg, bt)
   local self = {
      code = code,
      msg = msg,
      bt = bt or debug.traceback(msg, 2),
   }
   return setmetatable(self, Err_mt)
end

local M_mt = {
  __call = function(self, ...)
     return M.Err(...)
  end,
}

return setmetatable(M, M_mt)
