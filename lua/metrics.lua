-- include Prometheus related code
prom = dofile("/etc/haproxy/system/prometheus.lua")

-- stats table holds the current metrics table, which
-- is refreshed periodically by stats.updater.
-- It also has a bunch of methods to get and parse the metrics.
stats = {
    refresh_interval = tonumber(os.getenv("HAPROXY_STATS_REFRESH_INTERVAL")) or 5,
    socket = os.getenv("HAPROXY_STATS_SOCKET_PATH") or "/var/run/haproxy.sock",
    socket_timeout = os.getenv("HAPROXY_STATS_SOCKET_TIMEOUT") or 5,
    metrics = {}
}

-- socket_cmd is an auxiliary function to send arbitary
-- commands to the HAProxy management socket.
stats.socket_cmd = function(cmd)

    local socket = core.tcp()
    socket:settimeout(stats.socket_timeout)
    socket:connect(stats.socket)
    socket:send(cmd)
    local resp, err = socket:receive("*a")
    socket:close()
    return resp, err

end

-- get_proxy_variant determines the proxy variant, which is encoded in
-- the first letter of proxy_id.
stats.get_proxy_variant = function(proxy_id)

    local variants_map = { L = "listener", F = "frontend", B = "backend", S = "server" }
    local v = proxy_id:sub(1,1)
    return variants_map[v]

end

-- build_metrics_tables creates a new metrics table
-- populated with metrics parsed from stats_raw.
stats.build_metrics_table = function (stats_raw)

    local metrics = { has = { listener = {}, frontend = {}, backend = {}, server = {} }, by_srv_addr = {}, by_srv_name = {} }

    for s in stats_raw:gmatch("[^\r\n]+") do

        local f1, metric_type, metric_value = s:match("([^:]+):([^:]+:[^:]+):([^:]+)")
        if f1 then
            local proxy_id, _, metric_name = f1:match("([LFBS]%.[^.]+%.[^.]+)%.([^.]+)%.([^.]+).*")
            local variant = stats.get_proxy_variant(proxy_id)

            metrics[variant] = metrics[variant] or {}
            metrics[variant][proxy_id] = metrics[variant][proxy_id] or {}
            metrics[variant][proxy_id][metric_name] = metric_value
            metrics.has[variant][metric_name] = metrics.has[variant][metric_name] or metric_type
        end
    end
    for id, m in pairs(metrics.server) do
        metrics.by_srv_addr[m.addr] = id
        metrics.by_srv_name[m.svname] = id
    end
    return metrics

end

-- stats.show_metrics is the function to serve rendered Prometheus metrics
-- in response to a HTTP GET request.
stats.show_metrics = function(applet)

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

-- stats.updater updates stats.metrics
-- table each refresh_interval seconds.
stats.updater = function()

    local stats_raw, err = stats.socket_cmd("show stat typed\n")
    if err ~= nil then
        core.log(core.err, "Error getting stats from the socket: "..err)
    else
        stats.metrics = stats.build_metrics_table(stats_raw)
    end

    while true do
        core.sleep(stats.refresh_interval)
        local stats_raw, err = stats.socket_cmd("show stat typed\n")
        if err ~= nil then
            core.log(core.err, "Error getting stats from the socket: "..err)
        else
            stats.metrics = stats.build_metrics_table(stats_raw)
        end
    end

end

core.register_task(stats.updater)
core.register_service("metrics", "http", stats.show_metrics)

