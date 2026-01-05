# HTTPS / Certbot renewal (Alibaba ECS)

This documents how Dify’s `docker/docker-compose.yaml` is set up to use Let’s Encrypt via the `certbot` profile, and how to renew the certificate later.

## How it’s wired

- `nginx` publishes ports `80` and `443` (host ports are controlled by `EXPOSE_NGINX_PORT` / `EXPOSE_NGINX_SSL_PORT`).
- `certbot` (profile: `certbot`) writes certs to `docker/volumes/certbot/conf`.
- `nginx` mounts certs from `docker/volumes/certbot/conf/live`.
- For Let’s Encrypt HTTP-01, nginx must serve `/.well-known/acme-challenge/*` from `docker/volumes/certbot/www`.

## Required `.env` settings

Edit `docker/.env` on the ECS and set at minimum:

```dotenv
# Domain + email for Let’s Encrypt
CERTBOT_DOMAIN=poc.visioniq.tech
CERTBOT_EMAIL=you@example.com

# Nginx virtual host name
NGINX_SERVER_NAME=poc.visioniq.tech

# Enable HTTP-01 challenge location in nginx
NGINX_ENABLE_CERTBOT_CHALLENGE=true

# Enable HTTPS and point nginx to certbot-generated filenames
NGINX_HTTPS_ENABLED=true
NGINX_SSL_CERT_FILENAME=fullchain.pem
NGINX_SSL_CERT_KEY_FILENAME=privkey.pem
```

With the repo’s nginx templates:
- When `NGINX_HTTPS_ENABLED=true`, nginx serves HTTPS on `443` and redirects normal HTTP traffic on `80` to HTTPS.
- When `NGINX_ENABLE_CERTBOT_CHALLENGE=true`, nginx will still serve `/.well-known/acme-challenge/*` on HTTP for certbot.

Notes:
- `fullchain.pem` and `privkey.pem` are the standard certbot/Let’s Encrypt filenames.
- Certificates are stored under `docker/volumes/certbot/conf/live/$CERTBOT_DOMAIN/`.

## First-time issuance

Let’s Encrypt must be able to reach your ECS on **TCP 80** (and you’ll typically also want **TCP 443** open).

From the repo root on the ECS:

```sh
cd docker

# Start nginx + certbot (adds certbot without disturbing other services)
docker compose \
  -f docker-compose.yaml \
  -f ../syncmind/docker-compose.acr.override.yaml \
  --profile certbot \
  up -d nginx certbot

# Request the certificate
docker compose \
  -f docker-compose.yaml \
  -f ../syncmind/docker-compose.acr.override.yaml \
  --profile certbot \
  exec -T certbot /bin/sh /update-cert.sh

# Reload nginx to pick up the new cert
docker compose \
  -f docker-compose.yaml \
  -f ../syncmind/docker-compose.acr.override.yaml \
  up -d --no-deps --force-recreate nginx
```

## Renewal

Let’s Encrypt certs are valid for **90 days**. Renew when the cert has **~30 days or less** remaining.

```sh
cd docker

# Renew if needed (safe to run repeatedly)
docker compose \
  -f docker-compose.yaml \
  -f ../syncmind/docker-compose.acr.override.yaml \
  --profile certbot \
  exec -T certbot /bin/sh /update-cert.sh

# Reload nginx after renewal
docker compose \
  -f docker-compose.yaml \
  -f ../syncmind/docker-compose.acr.override.yaml \
  up -d --no-deps --force-recreate nginx
```

## About disabling port 80

- If you close ECS inbound **TCP 80**, HTTP-01 renewals will fail.
- Options:
  - Keep port 80 open and redirect HTTP → HTTPS (recommended).
  - Close port 80 and temporarily reopen it only when renewing.
  - Switch to DNS-01 validation (requires DNS provider API integration).

## Quick checks

```sh
# Confirm HTTP redirects to HTTPS (should return 301/308)
curl -I http://poc.visioniq.tech

# Confirm nginx is publishing ports on the host
sudo ss -lntp | grep -E ':(80|443)\s'

# Confirm files exist inside nginx
docker compose exec -T nginx sh -lc 'ls -la /etc/letsencrypt/live/"$CERTBOT_DOMAIN"/ && echo OK'
```
