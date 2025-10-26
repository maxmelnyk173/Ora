FROM nginx:1.27-alpine

RUN apk add --no-cache gettext

COPY /config/nginx.template.conf /etc/nginx/nginx.template.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
