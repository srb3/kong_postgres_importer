local function sleep(n)
  os.execute("sleep " .. tonumber(n))
end

local function mockbackend(applet)
  -- sleep(0.09)
  applet:set_status(200)
  applet:add_header("content-length", 2)
  applet:add_header("content-type", "text/html")
  applet:start_response()
  applet:send("OK")
end

core.register_service("mockbackend", "http", mockbackend)
