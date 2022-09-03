-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local BatchQueue = require "kong.tools.batch_queue"
local cjson = require "cjson"
local url = require "socket.url"
local http = require "resty.http"
local table_clear = require "table.clear"
local sandbox = require"kong.tools.sandbox".sandbox

local kong = kong
local ngx = ngx
local encode_base64 = ngx.encode_base64
local tostring = tostring
local tonumber = tonumber
local concat = table.concat
local fmt = string.format
local pairs = pairs
local update_secrets, secret_reference_fields
local has_secrets, secrets = pcall(require, "resty.secrets.kong")

if has_secrets then
  update_secrets = secrets.update_secrets
  secret_reference_fields = {"token"}
end

local sandbox_opts = {env = {kong = kong, ngx = ngx}}

local queues = {} -- one queue per unique plugin config
local parsed_urls_cache = {}
local headers_cache = {}
local params_cache = {ssl_verify = false, headers = headers_cache}

-- Parse host url.
-- @param `url` host url
-- @return `parsed_url` a table with host details:
-- scheme, host, port, path, query, userinfo
local function parse_url(host_url)

  local parsed_url = parsed_urls_cache[host_url]

  if parsed_url then
    return parsed_url
  end

  parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
    elseif parsed_url.scheme == "https" then
      parsed_url.port = 443
    end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end

  parsed_url.target = parsed_url.query and
                          fmt("%s://%s:%d%s?%s", parsed_url.scheme,
                              parsed_url.host, parsed_url.port, parsed_url.path,
                              parsed_url.query) or
                          fmt("%s://%s:%d%s", parsed_url.scheme,
                              parsed_url.host, parsed_url.port, parsed_url.path)

  parsed_urls_cache[host_url] = parsed_url

  return parsed_url
end

-- Sends the provided payload (a string) to the configured plugin host
-- @return true if everything was sent correctly, falsy if error
-- @return error message if there was an error
local function send_payload(self, conf, payload)

  -- For Secret Manager integration
  -- call to decrypt any encrypted secrets
  if has_secrets then
    update_secrets(conf, secret_reference_fields)
  end

  local method = conf.method
  local timeout = conf.timeout
  local keepalive = conf.keepalive
  local content_type = conf.content_type
  local http_endpoint = conf.http_endpoint
  local token = conf.token
  local debug = conf.debug

  local parsed_url = parse_url(http_endpoint)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)

  local httpc = http.new()
  httpc:set_timeout(timeout)

  table_clear(headers_cache)
  if conf.headers then
    for h, v in pairs(conf.headers) do
      headers_cache[h] = v
    end
  end

  headers_cache["Host"] = parsed_url.host
  headers_cache["Content-Type"] = content_type
  headers_cache["Content-Length"] = #payload
  if parsed_url.userinfo then
    headers_cache["Authorization"] = "Basic " ..
                                         encode_base64(parsed_url.userinfo)
  end

  -- Splunk auth token
  -- Depending on the customers needs the token can be passed as an auth header
  -- or the token could be passed as a query param. Also username and password
  -- can be used with basic auth. (see above).
  -- options described here https://docs.splunk.com/Documentation/SplunkCloud/8.2.2111/Data/FormateventsforHTTPEventCollector
  if token then
    if debug then
      kong.log.debug("token: ", token)
    end
    headers_cache["Authorization"] = "Splunk " .. token
  end

  params_cache.method = method
  params_cache.body = payload
  params_cache.keepalive_timeout = keepalive

  kong.log.debug("url: ", parsed_url.target)
  -- note: `httpc:request` makes a deep copy of `params_cache`, so it will be
  -- fine to reuse the table here
  local res, err = httpc:request_uri(parsed_url.target, params_cache)
  if not res then
    return nil,
           "failed request to " .. host .. ":" .. tostring(port) .. ": " .. err
  end

  -- always read response body, even if we discard it without using it on success
  local response_body = res.body
  local success = res.status < 400
  local err_msg

  if not success then
    err_msg = "request to " .. host .. ":" .. tostring(port) ..
                  " returned status code " .. tostring(res.status) ..
                  " and body " .. response_body
  end

  return success, err_msg
end

local function json_array_concat(entries)
  return "[" .. concat(entries, ",") .. "]"
end

local function get_queue_id(conf)
  return fmt("%s:%s:%s:%s:%s:%s:%s:%s:%s", conf.http_endpoint, conf.method,
             conf.content_type, conf.timeout, conf.keepalive, conf.retry_count,
             conf.queue_size, conf.token, conf.flush_timeout)
end

local SplunkHecHandler = {PRIORITY = 12, VERSION = "0.1.4"}

function SplunkHecHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression, sandbox_opts)())
    end
  end

  -- start of splunk specific data structure
  -- see https://docs.splunk.com/Documentation/SplunkCloud/8.2.2111/Data/FormateventsforHTTPEventCollector
  -- event contains the kong request / response stats
  local tmp_entry = {sourcetype = "AccessLog", event = kong.log.serialize()}
  -- json encode the data structure before
  -- sending to Splunk
  local entry = cjson.encode(tmp_entry)

  local queue_id = get_queue_id(conf)
  local q = queues[queue_id]
  if not q then
    -- batch_max_size <==> conf.queue_size
    local batch_max_size = conf.queue_size or 1
    local process = function(entries)
      local payload = batch_max_size == 1 and entries[1] or
                          json_array_concat(entries)
      return send_payload(self, conf, payload)
    end

    local opts = {
      retry_count = conf.retry_count,
      flush_timeout = conf.flush_timeout,
      batch_max_size = batch_max_size,
      process_delay = 0,
    }

    local err
    q, err = BatchQueue.new(process, opts)
    if not q then
      kong.log.err("could not create queue: ", err)
      return
    end
    queues[queue_id] = q
  end

  q:add(entry)
end

return SplunkHecHandler
