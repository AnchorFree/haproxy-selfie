-- include prometheus related code
prom = dofile("/etc/haproxy/system/prometheus.lua")

-- the interval for refreshing proxies stats, in seconds.
metrics_refresh_interval = tonumber(os.getenv("HAPROXY_METRICS_REFRESH_INTERVAL")) or 5

-- stats table holds the current metrics table, which
-- is refreshed periodically by metrics_updater.
-- It also has some methods to get and parse the metrics.
stats = { metrics = {} }

-- get_typed_stats fetches raw stats from the stat socket.
stats.get_typed_stats = function()

    local socket = core.tcp()
    socket:settimeout(1)
    socket:connect("/var/run/haproxy.sock")
    socket:send("show stat typed\n")
    local stats_raw, err = socket:receive("*a")
    socket:close()
    return stats_raw

end

-- get_variant determines the proxy variant, which is encoded in
-- the first letter of proxy_id.
stats.get_variant = function(proxy_id)

    local variant = "server"
    local v = proxy_id:sub(1,1)
    if v == "L" then
        variant = "listener"
    elseif v == "F" then
        variant = "frontend"
    elseif v == "B" then
        variant = "backend"
    end
    return variant

end

-- build_metrics_tables creates a new metrics table
-- populated with metrics parsed from stats_raw.
stats.build_metrics_table = function (stats_raw)

    local metrics = { has = { listener = {}, frontend = {}, backend = {}, server = {} } }

    for s in stats_raw:gmatch("[^\r\n]+") do

        local f1, metric_type, metric_value = s:match("([^:]+):([^:]+:[^:]+):([^:]+)")
        local proxy_id, _, metric_name = f1:match("([LFBS]%.[^.]+%.[^.]+)%.([^.]+)%.([^.]+).*")
        local variant = stats.get_variant(proxy_id)

        metrics[variant] = metrics[variant] or {}
        metrics[variant][proxy_id] = metrics[variant][proxy_id] or {}
        metrics[variant][proxy_id][metric_name] = metric_value

        metrics.has[variant][metric_name] = metrics.has[variant][metric_name] or metric_type
    end
    return metrics

end

-- metrics is the function to serve rendered prometheus metrics
-- in response to a HTTP GET request.
metrics = function(applet)

   local response = core.concat()

   local listeners = prom:build_metrics("listener")
   local frontends = prom:build_metrics("frontend")
   local backends = prom:build_metrics("backend")
   local servers = prom:build_metrics("server")

   response:add(listeners:dump())
   response:add(frontends:dump())
   response:add(backends:dump())
   response:add(servers:dump())
   applet:set_status(200)
   applet:add_header("content-type", "text/plain")
   applet:add_header("content-length", string.len(response:dump()))
   applet:start_response()
   applet:send(response:dump())

end

-- metrics_updater updates stats.metrics
-- table each metrics_refresh_interval seconds.
metrics_updater = function()

    stats_raw = stats.get_typed_stats()
    stats.metrics = stats.build_metrics_table(stats_raw)

    while true do
        core.sleep(metrics_refresh_interval)
        stats_raw = stats.get_typed_stats()
        stats.metrics = stats.build_metrics_table(stats_raw)
    end

end

core.register_task(metrics_updater)
core.register_service("metrics", "http", metrics)

