haproxy-selfie -- HAProxy with Prometheus metrics by Lua
========================================================

Table of Contents
-----------------
* [Description](#description)
* [Usage](#Usage)
* [Comparison with HAProxy exporter](#comparison-with-haproxy-exporter)
* [Exported metrics](#exported-metrics)

Description
-----------

HAProxy since version 1.6 has [built in](https://github.com/haproxy/haproxy/blob/master/doc/lua.txt) support for [Lua](http://www.lua.org/manual/5.3/) scripting,
and exposes a bunch of its' internal stats and [APIs](http://www.arpalert.org/src/haproxy-lua-api/1.9/index.html#) to Lua. 

This is a pretty powerful feature, which let HAProxy users tweak HAProxy load balancing behaviour, gather additional stats, inspect/manipulate 
HTTP request/repsonse headers, register background tasks, etc.

And, of course, we can convert internal HAProxy stats and export them in Prometheus format. This is what `haproxy-selfie` is about.
This project consists of several components: 

* Lua [scripts](lua/metrics.lua) to export metrics in [Prometheus](https://prometheus.io/) [format](lua/prometheus.lua).
* [Dockerfile](Dockerfile) and sample HAProxy [config](cfg/builtin.cfg) to build a docker image with HAProxy preconfigured to load the script and serve metrics.
* [docker-compose](docker-compose/haproxy-selfie.yml) file to show how to use this image with a [custom](cfg/sample.cfg) config.
* Sample helm [chart](helm/haproxy-selfie) to show how to use this image in k8s.

Usage
-----

`haproxy-selfie` docker image has the [builtin](cfg/builtin.cfg) config which
configures default timeouts, HAProxy stats socket, loads Lua metrics scripts and defines metrics frontend.

By default `haproxy-selfie` docker image runs HAProxy with `-- /etc/haproxy/conf` command line argument, which
means that besides builtin config HAProxy will also look for configuration files in `/etc/haproxy/conf` directory.

If you have [docker](https://docs.docker.com/) and [docker-compose](https://docs.docker.com/compose/) installed, you can 
start `haproxy-selfie` locally with a custom config:

```
# create /etc/haproxy/conf dir locally
sudo mkdir -p /etc/haproxy/conf
# put your own config there, we are using a sample one
sudo cp cfg/sample.cfg /etc/haproxy/conf/
docker-compose -f docker-compose/haproxy-selfie.yml -p haproxy-selfie up -d
```

If you want to override the builtin config entirely, mount your own config at `/etc/haproxy/builtin.cfg` inside the container.

Comparison with HAProxy exporter
--------------------------------

There is already [HAProxy Exporter](https://github.com/prometheus/haproxy_exporter), so why use `haproxy-selfie` instead?

* You don't need to configure and run an external process alongside HAProxy.
* You don't need to expose a TCP stats port for HAProxy Exporter. `haproxy-selfie` still
[uses](TODO.md) stats socket, but the socket does not need to be exposed externally. 
* [HAProxy Exporter](https://github.com/prometheus/haproxy_exporter/issues/30) exports a bunch of metrics with incorrect type (`gauge` instead of `counter`).
The issue has been there for a while. `haproxy-selfie` uses internal HAProxy information about metric types and just translates it into prometheus types.

Exported metrics
----------------

Metric names we export to Prometheus are pretty self-explanatory, for more details
it's strongly adviced to read the official HAProxy [docs](http://cbonte.github.io/haproxy-dconv/1.9/management.html#9.1).

