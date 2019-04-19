-- the interval for refreshing proxies stats, in seconds.
metrics_refresh_interval = 5

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

--[[

 prom.translations table holds the mapping between the HAProxy internal names
 for metrics (as returned by Proxy.get_stats() and Server.get_stats()
 methods, see also
 https://github.com/haproxy/haproxy/blob/master/doc/management.txt,
 section "9.1 CSV Format") and the names we present to prometheus.

 Final string for each metric is built by the following formula:
 prom.prefix + variant + translation + optional labels + metric value.
 Allowed variants: "frontend", "backend", "server", "listener".
 See prom.build_metrics and prom.build_labels for additional details.
                                                                         ]]--

prom = {
  prefix = "haproxy",
  translations = {
    bin = "bytes_in_total",
    bout = "bytes_out_total",
    econ = "connection_errors_total",
    ereq = "request_errors_total",
    eresp = "response_errors_total",
    qcur = "current_queue",
    qmax = "max_queue",
    qlimit = "queue_limit",
    scur = "current_sessions",
    smax = "max_sessions",
    slim = "limit_sessions",
    stot = "total_sessions",
    dreq = "requests_denied_total",
    dresp = "responses_denied_total",
    wretr = "retry_warnings_total",
    wredis = "redispatch_warnings_total",
    weight = "weight",
    act = "active_servers",
    bck = "backup_servers",
    chkfail = "check_failures_total",
    chkdown = "check_transitions_total",
    lastchg = "last_transition_interval",
    throttle = "throttle_percent",
    downtime = "downtime_seconds_total",
    lbtot = "selected_times_total",
    rate = "current_session_rate",
    rate_lim = "limit_sessions",
    rate_max = "max_session_rate",
    ctime = "connect_time_average",
    rtime = "response_time_average",
    qtime = "queue_time_average",
    ttime = "session_time_average",
    hrsp_1xx = { "http_responses_total", { code = "1xx" }},
    hrsp_2xx = { "http_responses_total", { code = "2xx" }},
    hrsp_3xx = { "http_responses_total", { code = "3xx" }},
    hrsp_4xx = { "http_responses_total", { code = "4xx" }},
    hrsp_5xx = { "http_responses_total", { code = "5xx" }},
    hrsp_other = { "http_responses_total", { code = "other" }},
    req_rate = "http_request_rate",
    req_rate_max = "http_max_request_rate",
    req_tot = "http_requests_total"
  },
  types = {
    counter = "^[CM]",
    gauge = "^[AaDGLRm]"
  }
}

-- build_labels converts a table with labels into a string.
prom.build_labels = function(labels)

    local l = core.concat()
    for k,v in pairs(labels) do
        l:add(k.."=\""..v.."\",")
    end
    local lstring = l:dump()
    return string.sub(lstring,1,-2)

end

-- get_type converts internal HAProxy metric type into
-- either "counter" or "gauge" for prometheus.
prom.get_type = function(mtype)

    if mtype:match(prom.types.counter) then
        return "counter"
    elseif mtype:match(prom.types.gauge) then
        return "gauge"
    end
    return "untyped"

end

-- build_metrics returns rendered prometheus metrics for a particular
-- proxy variant: -- listener, frontend, backend, server.
-- We intentionally don't include "#HELP ..." strings for metrics in the
-- output: prometheus does not need them, human beings can read the docs,
-- and it's always good to save ourselves some traffic.
prom.build_metrics = function(prom, variant)

    local response = core.concat()

    for n, t in pairs(prom.translations) do

        if stats.metrics[variant] and stats.metrics.has[variant][n] then

            local translation = ""
            local predefined_labels = {}
            if type(t) == "table" then
                translation = t[1]
                for k,v in pairs(t[2]) do
                    predefined_labels[k] = v
                end
            else
                translation = t
            end

            response:add("# TYPE "..prom.prefix.."_"..variant.."_"..translation.." "..prom.get_type(stats.metrics.has[variant][n]:sub(2,2)).."\n")
            for proxy_id, metrics in pairs(stats.metrics[variant]) do
                local labels = predefined_labels
                if variant == "server" then
                    labels.server = metrics.svname
                    labels.backend = metrics.pxname
                else
                    labels[variant] = metrics.pxname
                end
                if metrics[n] then
                    response:add(prom.prefix.."_"..variant.."_"..translation.."{"..prom.build_labels(labels).."} "..metrics[n].."\n")
                end
            end
        end
    end
    return response

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
   applet:add_header("content-encoding", "gzip")
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

