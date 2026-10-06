# Imagem usada pelo Coolify (modo "atrás do proxy do Coolify").
FROM caddy:2.10-alpine

COPY Caddyfile.coolify /etc/caddy/Caddyfile
COPY routes.caddy /etc/caddy/routes.caddy

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
	CMD wget -qO- http://127.0.0.1/edge-healthz || exit 1
