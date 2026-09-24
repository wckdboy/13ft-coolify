# Landing page + reverse proxy in front of the 13ft app.
FROM nginx:1.27-alpine

LABEL org.opencontainers.image.title="13ft-web" \
      org.opencontainers.image.description="Custom landing page and reverse proxy for 13ft (13 Feet Ladder)" \
      org.opencontainers.image.source="https://github.com/wasi-master/13ft" \
      org.opencontainers.image.licenses=MIT

# Replace the stock default server with our proxy config.
# proxy_13ft.inc uses the .inc extension on purpose: nginx only auto-includes
# *.conf from conf.d, so the shared proxy settings stay explicitly included.
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY proxy_13ft.inc /etc/nginx/conf.d/proxy_13ft.inc

# Static landing page (single self-contained file).
COPY site/ /usr/share/nginx/html/

EXPOSE 80

# nginx:alpine ships busybox wget, so no extra packages are needed.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1

STOPSIGNAL SIGQUIT
