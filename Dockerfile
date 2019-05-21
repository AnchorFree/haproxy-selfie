FROM haproxy:1.9-alpine
LABEL maintainer="v.zorin@anchorfree.com"


ENV HAPROXY_HTTP_PORT 80
ENV HAPROXY_HTTPS_PORT 443
ENV HAPROXY_TIMEOUT_CONNECT "5000ms"
ENV HAPROXY_TIMEOUT_SERVER "10000ms"
ENV HAPROXY_TIMEOUT_CLIENT "15000ms"
ENV HAPROXY_METRICS_PORT 9101
ENV HAPROXY_STATS_REFRESH_INTERVAL 5

RUN apk add --no-cache lua5.3-ossl lua5.3-inspect ca-certificates openssl && mkdir -p /etc/haproxy/system /etc/haproxy/user /etc/haproxy/conf /etc/haproxy/lualibs
COPY lua/*.lua /etc/haproxy/system/
COPY lua/libs /etc/haproxy/lualibs/
COPY cfg/builtin.cfg /etc/haproxy/

ENV LUA_PATH "/usr/share/lua/5.3/?.lua;/etc/haproxy/lualibs/?/?.lua;;"
ENV LUA_CPATH "/usr/share/lua/5.3/?.so;;"

ENTRYPOINT ["/usr/local/sbin/haproxy"]
CMD [ "-W", "-f", "/etc/haproxy/builtin.cfg", "--", "/etc/haproxy/conf" ]
