# Shared proxy settings for the 13ft upstream.
# Referenced by the "@app" and "/" locations in nginx.conf.
#
# proxy_buffering is off so the SSE progress stream (/status) reaches the
# browser as it is produced; the app also sends "X-Accel-Buffering: no",
# this is belt and braces and also covers Traefik/Coolify in front.

proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header Connection "";

proxy_buffering off;
proxy_cache off;
proxy_request_buffering off;

proxy_connect_timeout 15s;
# Must outlast the app's own 30s fetch plus any archive.org / archive.today
# fallback attempts.
proxy_send_timeout 300s;
proxy_read_timeout 300s;

proxy_next_upstream off;

# Do not let the proxy turn app errors into blank pages, and never cache
# the bypass results: the app already has a 5 minute in-memory cache.
proxy_intercept_errors off;
add_header X-Robots-Tag "noindex, nofollow" always;
