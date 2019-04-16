FROM haproxy:1.9-alpine
LABEL maintainer="v.zorin@anchorfree.com"

ENV HAPROXY_METRICS_PORT 9101
ENV HAPROXY_HTTP_PORT 80
ENV HAPROXY_HTTPS_PORT 443
ENV HAPROXY_TIMEOUT_CONNECT "5000ms"
ENV HAPROXY_TIMEOUT_SERVER "10000ms"
ENV HAPROXY_TIMEOUT_CLIENT "15000ms"

RUN apk add --no-cache ca-certificates openssl && mkdir -p /etc/haproxy/system /etc/haproxy/user /etc/haproxy/conf
COPY lua/metrics.lua /etc/haproxy/system/
COPY cfg/builtin.cfg /etc/haproxy/

ENTRYPOINT ["/usr/local/sbin/haproxy"]
CMD [ "-W", "-db", "-f", "/etc/haproxy/builtin.cfg", "--", "/etc/haproxy/conf" ]
