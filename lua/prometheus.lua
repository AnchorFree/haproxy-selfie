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
                    labels.addr = metrics.addr
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

return prom
