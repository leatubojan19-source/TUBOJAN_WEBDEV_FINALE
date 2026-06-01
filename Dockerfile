FROM php:8.3-fpm

WORKDIR /var/www/html

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl zip unzip \
    libicu-dev libxml2-dev libonig-dev \
    nginx gettext-base \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions
RUN docker-php-ext-install \
    intl xml pdo pdo_mysql mbstring opcache

# Composer
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin \
    --filename=composer

# Copy project
COPY . .

# DEBUG: Verify nelmio/cors-bundle is in lock file
RUN cat composer.lock | grep -A 5 '"name": "nelmio/cors-bundle"' || echo "BUNDLE NOT FOUND IN LOCK"

# DEBUG: Check bundles.php
RUN cat config/bundles.php | grep -i cors || echo "CORS BUNDLE NOT IN bundles.php"
RUN ls -la config/bundles.php || echo "bundles.php NOT FOUND"

# Install dependencies
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install \
    --no-dev \
    --optimize-autoloader \
    --no-interaction \
    --no-scripts

# DEBUG: Verify bundle was installed
RUN ls -la vendor/nelmio/ || echo "NELMIO VENDOR DIR NOT FOUND"

# Fix Symfony writable dirs (IMPORTANT)
RUN mkdir -p var/cache var/log var/sessions \
    && chmod -R 777 var

# Nginx configs
COPY nginx-main.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Entry script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

CMD ["/entrypoint.sh"]