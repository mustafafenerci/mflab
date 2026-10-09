FROM php:8.3-apache

LABEL org.opencontainers.image.title="mflab-php-web" \
      org.opencontainers.image.description="MF Lab: Apache + PHP 8.3 + Composer + Git + Node.js (Laravel ready)" \
      org.opencontainers.image.source="https://github.com/mustafafenerci/mflab" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update && apt-get install -y --no-install-recommends \
        git unzip curl ca-certificates \
        libzip-dev libpng-dev libjpeg-dev libfreetype6-dev \
        libicu-dev libonig-dev libxml2-dev libpq-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        pdo_mysql mysqli pdo_pgsql pgsql mbstring xml zip bcmath gd intl exif opcache \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && a2enmod rewrite \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    APACHE_DOCUMENT_ROOT=/var/www/html

RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
    && printf 'display_errors=On\nerror_reporting=E_ALL\nupload_max_filesize=64M\npost_max_size=64M\n' > /usr/local/etc/php/conf.d/mflab.ini

WORKDIR /var/www/html
