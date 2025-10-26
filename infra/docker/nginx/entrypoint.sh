#!/bin/sh
echo "Starting NGINX with environment variables..."

envsubst '${SERVER_NAME} ${SSL_CERTIFICATE} ${SSL_CERTIFICATE_KEY}' < /etc/nginx/nginx.template.conf > /etc/nginx/nginx.conf

exec nginx -g "daemon off;"
