-- the interval for refreshing proxies stats, in seconds.
metrics_refresh_interval = 5

-- proxies table contains stats for
-- all frontends and backends.
proxies = {}

-- resfresh_proxy_info gets internal stats
-- for a particular proxy, and saves them
-- in the proxies table.
refresh_proxy_info = function(name)

  if core.proxies[name] then
      proxies[name] = proxies[name] or {}
      proxies[name].stats = core.proxies[name]:get_stats()
      proxies[name].servers = proxies[name].servers or {}
      for sname, server in pairs(core.proxies[name].servers) do
          proxies[name].servers[sname] = server:get_stats()
      end
  end

end

--[[

 prom.metrics table holds the mapping between the HAProxy internal names
 for metrics (as returned by Proxy.get_stats() and Server.get_stats()
 methods, see also
 https://github.com/haproxy/haproxy/blob/master/doc/management.txt,
 section "9.1 CSV Format") and the names we present to prometheus.

 Final string for each metric is built by the following formula:
 prom.prefix + variant + metrics[n][1] + optional labels + metric value.
 Allowed variants: "frontend", "backend", "server".
 See prom.build_metrics and prom.build_labels for additional details.
                                                                         ]]--

prom = {
  prefix = "haproxy",
  metrics = {
    bin = { "bytes_in_total", "counter", "LFBS" },
    bout = { "bytes_out_total", "counter", "LFBS" },
    econ = { "connection_errors_total", "counter", "BS" },
    ereq = { "request_errors_total", "counter", "LF" },
    eresp = { "response_errors_total", "counter", "BS" },
    qcur = { "current_queue", "gauge", "BS" },
    qmax = { "max_queue", "counter", "BS" },
    qlimit = { "queue_limit", "gauge", "S" },
    scur = { "current_sessions", "gauge", "LFBS" },
    smax = { "max_sessions", "counter", "LFBS" },
    slim = { "limit_sessions", "gauge", "LFBS" },
    stot = { "total_sessions", "counter", "LFBS" },
    dreq = { "requests_denied_total", "counter", "LFB" },
    dresp = { "responses_denied_total", "counter", "LFBS" },
    wretr = { "retry_warnings_total", "counter", "BS" },
    wredis = { "redispatch_warnings_total", "counter", "BS" },
    weight = { "weight", "gauge", "BS" },
    act = { "active_servers", "gauge", "BS" },
    bck = { "backup_servers", "gauge", "BS" },
    chkfail = { "check_failures_total", "counter", "S" },
    chkdown = { "check_transitions_total", "counter", "BS" },
    lastchg = { "last_transition_interval", "gauge", "BS" },
    throttle = { "throttle_percent", "gauge", "S" },
    downtime = { "downtime_seconds_total", "counter", "BS" },
    lbtot = { "selected_times_total", "counter", "BS" },
    rate = { "current_session_rate", "gauge", "FBS" },
    rate_lim = { "limit_sessions", "gauge", "F" },
    rate_max = { "max_session_rate", "counter", "FBS" },
    ctime = { "connect_time_average", "gauge", "BS" },
    rtime = { "response_time_average", "gauge", "BS" },
    qtime = { "queue_time_average", "gauge", "BS" },
    ttime = { "session_time_average", "gauge", "BS" },
    hrsp_1xx = { "http_responses_total", "counter", "FBS", { code = "1xx" }},
    hrsp_2xx = { "http_responses_total", "counter", "FBS", { code = "2xx" }},
    hrsp_3xx = { "http_responses_total", "counter", "FBS", { code = "3xx" }},
    hrsp_4xx = { "http_responses_total", "counter", "FBS", { code = "4xx" }},
    hrsp_5xx = { "http_responses_total", "counter", "FBS", { code = "5xx" }},
    hrsp_other = { "http_responses_total", "counter", "FBS", { code = "other" }},
    req_rate = { "http_reqeuest_rate", "gauge", "F" },
    req_rate_max = { "http_max_request_rate", "counter", "F" },
    req_tot = { "http_requests_total", "counter", "FB" },
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

-- build_metrics returns rendered prometheus metrics for a particular
-- proxy variant: -- frontend, backend, server.
-- We intentionally don't include "#HELP ..." strings for metrics in the
-- output: prometheus does not need them, human beings can read the docs,
-- and it's always good to save ourselves some bandwith.
prom.build_metrics = function(prom, variant)

    local metrics = core.concat()
    for n, metric in pairs(prom.metrics) do
        if string.find(metric[3], string.upper(string.sub(variant,1,1))) then
            metrics:add("# TYPE "..prom.prefix.."_"..variant.."_"..metric[1].." "..metric[2].."\n")
            local labels = {}
            if metric[4] then
                for k,v in pairs(metric[4]) do
                    labels[k] = v
                end
            end

            for name, proxy in pairs(proxies) do
                if name ~= "GLOBAL" then
                    labels[variant] = name
                    if variant == "server" then
                        if proxy.servers then
                            for sname, server in pairs(proxy.servers) do
                                labels.server = sname
                                if not server[n] then server[n] = 0 end
                                metrics:add(prom.prefix.."_"..variant.."_"..metric[1].."{"..prom.build_labels(labels).."} "..server[n].."\n")
                            end
                        end
                    else
                        if proxy.stats.svname == string.upper(variant) then
                            if not proxy.stats[n] then proxy.stats[n] = 0 end
                            metrics:add(prom.prefix.."_"..variant.."_"..metric[1].."{"..prom.build_labels(labels).."} "..proxy.stats[n].."\n")
                        end
                    end
                end
            end
        end
    end
    return metrics

end

-- metrics is the function to serve rendered prometheus metrics
-- in response to a HTTP GET request.
metrics = function(applet)

   local response = core.concat()
   local frontends = prom:build_metrics("frontend")
   local backends = prom:build_metrics("backend")
   local servers = prom:build_metrics("server")
   response:add(frontends:dump())
   response:add(backends:dump())
   response:add(servers:dump())
   applet:set_status(200)
   applet:add_header("content-type", "text/plain")
   applet:start_response()
   applet:send(response:dump())

end

-- metrics_updater runs refresh_proxy_interval for every
-- proxy each metrics_refresh_interval seconds.
metrics_updater = function()

    while true do
        core.sleep(metrics_refresh_interval)
        for name, _ in pairs(core.proxies) do
            refresh_proxy_info(name)
        end
    end

end

core.register_task(metrics_updater)
core.register_service("metrics", "http", metrics)

