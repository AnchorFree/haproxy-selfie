haproxy-selfie -- Lua script for HAProxy to export metrics in prometheus format
===============================================================================

Table of Contents
-----------------
* [Description](#description)
* [Exported metrics](#exported-metrics)

Description
-----------

HAProxy since version 1.6 has [built in](https://github.com/haproxy/haproxy/blob/master/doc/lua.txt) support for [Lua](http://www.lua.org/manual/5.3/) scripting,
and exposes a bunch of its' internal stats and [APIs](http://www.arpalert.org/src/haproxy-lua-api/1.9/index.html#) to Lua. 

This is a pretty powerful feature, which let HAProxy users tweak HAProxy load balancing behaviour, gather additional stats, inspect/manipulate 
HTTP request/repsonse headers, register background tasks, etc.

And, of course, we can convert internal HAProxy stats and export them in Prometheus format. This is what haproxy-selfie is about.
This project consists of several components: 

* Lua [script](lua/metrics.lua) to export metrics in Prometheus format.
* [Dockerfile](Dockerfile) and sample HAProxy [config](cfg/builtin.cfg) to build a docker image with HAProxy preconfigured to load the script and serve metrics.
* [docker-compose](docker-compose/haproxy-selfie.yml) file to show how to use this image with a [custom](cfg/sample.cfg) config.
* Sample helm [chart](helm/haproxy-selfie) to show how to use this image in k8s.

Exported metrics
----------------


