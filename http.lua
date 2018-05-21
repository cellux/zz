local buffer = require('buffer')
local stream = require('stream')
local net = require('net')
local util = require('util')
local sched = require('sched')
local re = require('re')

local M = {}

local function readln(stream)
   return stream:readln("\x0d\x0a")
end

local function writeln(stream, line)
   return stream:writeln(line, "\x0d\x0a")
end

local make_stream = stream -- has a __call metamethod

--[[ headers ]]--

local Headers_mt = {
   -- provides case-insensitive lookup by header name
   __index = function(self, key)
      key = string.lower(key)
      for k,v in pairs(self) do
         if string.lower(k) == key then
            return v
         end
      end
   end,
   __newindex = function(self, key, value)
      rawset(self, key, tostring(value))
   end
}

local header_regex = re.compile("^(\\S+):\\s*(.+)\\s*$")

local function read_headers(stream)
   local headers = {}
   while true do
      line = readln(stream)
      if stream:eof() then
         return nil
      end
      if line == "" then
         break
      end
      local m = header_regex:match(line)
      if not m then
         ef("Invalid header line: %s", line)
      end
      local key = m[1]
      local value = m[2]
      headers[key] = value
   end
   return setmetatable(headers, Headers_mt)
end

local function write_headers(stream, headers)
   for k,v in pairs(headers) do
      writeln(stream, sf("%s: %s", k, v))
   end
   writeln(stream, "")
end

--[[ request ]]--

local Request = util.Class()

function Request:create(opts)
   local self = {
      stream = opts.stream,
      method = opts.method or "GET",
      uri = opts.uri or "/",
      http_version = opts.http_version or "HTTP/1.1",
      _headers = opts.headers or {},
      _body = opts.body,
   }
   setmetatable(self._headers, Headers_mt)
   local host = opts.host or self._headers['Host']
   if host then
      self._headers['Host'] = host
      self.host = host
   end
   local content_length = opts.content_length or self._headers['Content-Length']
   if content_length then
      self._headers['Content-Length'] = tostring(content_length)
      self.content_length = tonumber(content_length)
   end
   return self
end

function Request:header(key, value)
   if value then
      self._headers[key] = value
   end
   return self._headers[key]
end

function Request:read_body()
   if not self.content_length then
      ef("cannot read request body without Content-Length")
   end
   return self.stream:read(self.content_length)
end

local request_line_regex = re.compile("^(\\S+)\\s+(\\S+)\\s+(HTTP/[0-9.]+)$")

local function read_request(stream)
   local request_line = readln(stream)
   if stream:eof() then
      return nil
   end
   local m = request_line_regex:match(request_line)
   if not m then
      ef("invalid request line: %s", request_line)
   end
   local method, uri, http_version = m[1], m[2], m[3]
   local headers = read_headers(stream)
   if stream:eof() then
      return nil
   end
   return Request {
      stream = stream,
      method = method,
      uri = uri,
      http_version = http_version,
      headers = headers
   }
end

local function is_bytes(x)
   return type(x) == "string" or buffer.is_buffer(x)
end

local function write_request(stream, request)
   writeln(stream, sf("%s %s %s", request.method, request.uri, request.http_version))
   local body_writer
   local b = request._body
   if b then
      if type(b) == "function" then
         body_writer = b
      elseif is_bytes(b) then
         body_writer = function(stream) stream:write(b) end
         request:header("Content-Length", #b)
         request.content_length = #b
      else
         ef("invalid body: %s", b)
      end
   else
      request:header("Content-Length", "0")
      request.content_length = 0
   end
   write_headers(stream, request._headers)
   if body_writer then
      body_writer(stream)
   end
end

M.Request = Request
M.read_request = read_request
M.write_request = write_request

--[[ Response ]]--

local Response = util.Class()

local status_reasons = {
   [200] = "OK"
}

function Response:create(opts)
   local status = tonumber(opts.status or 200)
   local status_reason = opts.status_reason or status_reasons[status]
   local self = {
      stream = opts.stream,
      http_version = opts.http_version or "HTTP/1.1",
      status = status,
      status_reason = status_reason or "Shinkansen",
      _headers = opts.headers or {},
      _body = opts.body,
   }
   setmetatable(self._headers, Headers_mt)
   local content_type = opts.content_type or self._headers['Content-Type'] or "application/octet-stream"
   if content_type then
      self._headers['Content-Type'] = content_type
      self.content_type = content_type
   end
   local content_length = opts.content_length or self._headers['Content-Length']
   if content_length then
      self._headers['Content-Length'] = tostring(content_length)
      self.content_length = tonumber(content_length)
   end
   return self
end

function Response:header(key, value)
   if value then
      self._headers[key] = value
   end
   return self._headers[key]
end

function Response:read_body()
   if not self.content_length then
      ef("cannot read response body without Content-Length")
   end
   return self.stream:read(self.content_length)
end

local status_line_regex = re.compile("^(HTTP/[0-9.]+)\\s+([0-9]+)\\s+(.+)$")

local function read_response(stream)
   local status_line = readln(stream)
   if stream:eof() then
      return nil
   end
   local m = status_line_regex:match(status_line)
   if not m then
      ef("invalid status line: %s", status_line)
   end
   local http_version, status, status_reason = m[1], tonumber(m[2]), m[3]
   local headers = read_headers(stream)
   if stream:eof() then
      return nil
   end
   return Response {
      stream = stream,
      http_version = http_version,
      status = status,
      status_reason = status_reason,
      headers = headers,
   }
end

local function write_response(stream, response)
   writeln(stream, sf("%s %d %s", response.http_version, response.status, response.status_reason))
   local body_writer
   local b = response._body
   if b then
      if type(b) == "function" then
         body_writer = b
      elseif is_bytes(b) then
         body_writer = function(stream) stream:write(b) end
         response:header("Content-Length", #b)
         response.content_length = #b
      else
         ef("invalid body: %s", b)
      end
   end
   write_headers(stream, response._headers)
   if body_writer then
      body_writer(stream)
   end
end

M.Response = Response
M.read_response = read_response
M.write_response = write_response

--[[ StreamServer ]]--

local StreamServer = util.Class()

function StreamServer:create(stream, request_handler)
   return {
      stream = make_stream(stream),
      request_handler = request_handler,
      _running = false,
   }
end

function StreamServer:running()
   return self._running
end

function StreamServer:start()
   sched(function()
      self._running = true
      while not self.stream:eof() do
         local req = read_request(self.stream)
         if req == nil then break end
         local res = self.request_handler(req)
         if is_bytes(res) then
            res = Response { body = res }
         end
         write_response(self.stream, res)
      end
      self._running = false
   end)
end

M.StreamServer = StreamServer

--[[ StreamClient ]]--

local StreamClient = util.Class()

function StreamClient:create(stream)
   return {
      stream = make_stream(stream),
      http_version = "HTTP/1.1",
   }
end

function StreamClient:send(req)
   local s = self.stream
   write_request(s, req)
   local res = read_response(s)
   if res == nil then
      self:close()
   end
   return res
end

function StreamClient:close()
   if self.stream then
      self.stream:close()
      self.stream = nil
   end
end

M.StreamClient = StreamClient

return M
