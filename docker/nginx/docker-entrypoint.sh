#!/bin/bash

HTTPS_CONFIG=''
HTTP_REDIRECT_SERVER=''
HTTP_LISTEN="listen ${NGINX_PORT};"
CATCHALL_SERVERS=''
CATCHALL_SSL_DIRECTIVES=''

if [ "${NGINX_HTTPS_ENABLED}" = "true" ]; then
    # When HTTPS is enabled, bind the main server only on the SSL port.
    # A separate HTTP server will handle ACME challenges and redirect everything else to HTTPS.
    HTTP_LISTEN=''

    # Check if the certificate and key files for the specified domain exist
    if [ -n "${CERTBOT_DOMAIN}" ] && \
       [ -f "/etc/letsencrypt/live/${CERTBOT_DOMAIN}/${NGINX_SSL_CERT_FILENAME}" ] && \
       [ -f "/etc/letsencrypt/live/${CERTBOT_DOMAIN}/${NGINX_SSL_CERT_KEY_FILENAME}" ]; then
        SSL_CERTIFICATE_PATH="/etc/letsencrypt/live/${CERTBOT_DOMAIN}/${NGINX_SSL_CERT_FILENAME}"
        SSL_CERTIFICATE_KEY_PATH="/etc/letsencrypt/live/${CERTBOT_DOMAIN}/${NGINX_SSL_CERT_KEY_FILENAME}"
    else
        SSL_CERTIFICATE_PATH="/etc/ssl/${NGINX_SSL_CERT_FILENAME}"
        SSL_CERTIFICATE_KEY_PATH="/etc/ssl/${NGINX_SSL_CERT_KEY_FILENAME}"
    fi
    export SSL_CERTIFICATE_PATH
    export SSL_CERTIFICATE_KEY_PATH

    # SSL directives for the HTTPS catch-all server (no listen line here)
    CATCHALL_SSL_DIRECTIVES="ssl_certificate ${SSL_CERTIFICATE_PATH};
ssl_certificate_key ${SSL_CERTIFICATE_KEY_PATH};
ssl_protocols ${NGINX_SSL_PROTOCOLS};
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;"
    export CATCHALL_SSL_DIRECTIVES

    # set the HTTPS_CONFIG environment variable to the content of the https.conf.template
    HTTPS_CONFIG=$(envsubst < /etc/nginx/https.conf.template)
    export HTTPS_CONFIG
    # Substitute the HTTPS_CONFIG in the default.conf.template with content from https.conf.template
    envsubst '${HTTPS_CONFIG}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf
fi
export HTTPS_CONFIG

export HTTP_REDIRECT_SERVER
export HTTP_LISTEN
export CATCHALL_SERVERS
export CATCHALL_SSL_DIRECTIVES

if [ "${NGINX_ENABLE_CERTBOT_CHALLENGE}" = "true" ]; then
    ACME_CHALLENGE_LOCATION='location /.well-known/acme-challenge/ { root /var/www/html; }'
else
    ACME_CHALLENGE_LOCATION=''
fi
export ACME_CHALLENGE_LOCATION

# Catch-all default servers: drop requests that don't match NGINX_SERVER_NAME (e.g. direct IP access).
# Keep ACME challenge reachable on HTTP if enabled.
CATCHALL_SERVERS="server {
        listen ${NGINX_PORT} default_server;
        server_name _;

        ${ACME_CHALLENGE_LOCATION}

        location / {
            return 444;
        }
}"

if [ "${NGINX_HTTPS_ENABLED}" = "true" ]; then
        CATCHALL_SERVERS="${CATCHALL_SERVERS}

server {
        listen ${NGINX_SSL_PORT} ssl default_server;
        server_name _;

        ${CATCHALL_SSL_DIRECTIVES}

        location / {
            return 444;
        }
}"
fi
export CATCHALL_SERVERS

# Build the HTTP redirect server after ACME_CHALLENGE_LOCATION is known.
# This keeps HTTP-01 validation working while forcing normal traffic onto HTTPS.
if [ "${NGINX_HTTPS_ENABLED}" = "true" ]; then
    HTTP_REDIRECT_SERVER="server {
    listen ${NGINX_PORT};
    server_name ${NGINX_SERVER_NAME};

    ${ACME_CHALLENGE_LOCATION}

    location / {
      return 301 https://\$host\$request_uri;
    }
}"
fi
export HTTP_REDIRECT_SERVER

# Only substitute known env vars. Do NOT substitute nginx runtime variables like $host, $scheme, etc.
env_vars='${NGINX_SERVER_NAME},${NGINX_HTTPS_ENABLED},${NGINX_PORT},${NGINX_SSL_PORT},${NGINX_SSL_CERT_FILENAME},${NGINX_SSL_CERT_KEY_FILENAME},${NGINX_SSL_PROTOCOLS},${NGINX_WORKER_PROCESSES},${NGINX_CLIENT_MAX_BODY_SIZE},${NGINX_KEEPALIVE_TIMEOUT},${NGINX_PROXY_READ_TIMEOUT},${NGINX_PROXY_SEND_TIMEOUT},${NGINX_ENABLE_CERTBOT_CHALLENGE},${CERTBOT_DOMAIN},${CERTBOT_EMAIL},${CERTBOT_OPTIONS},${HTTPS_CONFIG},${ACME_CHALLENGE_LOCATION},${HTTP_REDIRECT_SERVER},${HTTP_LISTEN},${CATCHALL_SERVERS},${CATCHALL_SSL_DIRECTIVES},${SSL_CERTIFICATE_PATH},${SSL_CERTIFICATE_KEY_PATH}'

envsubst "$env_vars" < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
envsubst "$env_vars" < /etc/nginx/proxy.conf.template > /etc/nginx/proxy.conf
envsubst "$env_vars" < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf

# Start Nginx using the default entrypoint
exec nginx -g 'daemon off;'
