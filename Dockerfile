FROM php:8.0.10-fpm-alpine3.13 as fpm

RUN set -ex && apk --no-cache add tzdata curl ca-certificates libxml2-dev libpng-dev postgresql-dev icu-dev libzip-dev imap-dev zlib-dev
RUN docker-php-ext-configure intl
RUN docker-php-ext-configure imap --with-imap-ssl
RUN docker-php-ext-install gd zip soap bcmath pdo pdo_pgsql pcntl intl sockets imap opcache
ENV TZ=Asia/Tehran

RUN apk add git

COPY ./composer.json composer.lock ./
RUN composer install --no-scripts --no-autoloader --prefer-dist --no-dev \
                     --working-dir=/var/www/html

COPY ./ /tmp/app
RUN chgrp -R 0 /tmp/app && \
    chmod -R g=u /tmp/app && \
    cp -a /tmp/app/. /var/www/html && \
    rm -rf /tmp/app && \
    composer dump-autoload --classmap-authoritative
RUN chmod -R 777 storage/


VOLUME ["/var/www/html"]
ENTRYPOINT ["/usr/local/sbin/php-fpm"]

FROM nginx:alpine as nginx

COPY --from=fpm /var/www/html/public /var/www/html/public
RUN chown -R nginx. /var/cache/nginx/
COPY ./docker/nginx/default.conf /etc/nginx/conf.d/default.conf


FROM php:8.0.10-fpm-alpine3.13 as php_worker

RUN apk add supervisor --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ --no-cache

COPY --from=fpm /var/www/html /var/www/html

COPY ./docker/supervisor/queue.conf /etc/supervisor/queue.conf

VOLUME ["/etc/supervisor"]


CMD ["supervisord", "-c", "/etc/supervisor/queue.conf"]
ENTRYPOINT ["docker-php-entrypoint"]

FROM php:8.0.10-fpm-alpine3.13 as schedule

RUN sed -i 's/memory_limit.*/memory_limit = 5G/g' /usr/local/etc/php/conf.d/user.ini

RUN echo "* * * * * php -d memory_limit=10G /var/www/html/artisan schedule:run >> /dev/null 2>&1" | crontab -

COPY --from=fpm /var/www/html /var/www/html

CMD ["/usr/sbin/crond", "-f", "-L", "15"]
ENTRYPOINT ["docker-php-entrypoint"]
