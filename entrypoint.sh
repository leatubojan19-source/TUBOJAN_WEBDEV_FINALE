#!/bin/bash
set -e

export PORT=${PORT:-8080}

echo "Starting app on port $PORT"

# Generate JWT keys if they don't exist
if [ ! -f config/jwt/private.pem ]; then
    echo "Generating JWT keys..."
    mkdir -p config/jwt
    openssl genrsa -out config/jwt/private.pem 4096
    openssl rsa -in config/jwt/private.pem -pubout -out config/jwt/public.pem
    # Fix ownership so www-data can read
    chown www-data:www-data config/jwt/private.pem config/jwt/public.pem
    chmod 600 config/jwt/private.pem
    chmod 644 config/jwt/public.pem
fi

# Fix permissions
mkdir -p var/cache var/log var/sessions
chmod -R 777 var || true

# Start PHP-FPM
php-fpm -D
sleep 2

# Run Symfony only if safe
if [ -f bin/console ]; then
    echo "Running Symfony setup..."

    su -s /bin/bash www-data -c "php bin/console cache:clear --env=prod --no-debug" || true
    su -s /bin/bash www-data -c "php bin/console cache:warmup --env=prod" || true

    # ONLY RUN MIGRATIONS IF DATABASE_URL EXISTS
    if [ ! -z "$DATABASE_URL" ]; then
        su -s /bin/bash www-data -c "php bin/console doctrine:migrations:migrate --no-interaction --env=prod" || true
        
        # Load fixtures only if database is empty
        echo "Checking if fixtures are needed..."
        USER_COUNT=$(su -s /bin/bash www-data -c "php bin/console doctrine:query:sql 'SELECT COUNT(*) FROM user' --env=prod --quiet" 2>/dev/null | grep -o '[0-9]*' | head -1)
        
        if [ "$USER_COUNT" = "0" ] || [ -z "$USER_COUNT" ]; then
            echo "Database empty, loading fixtures..."
            su -s /bin/bash www-data -c "php bin/console doctrine:fixtures:load --no-interaction --env=prod" || true
        else
            echo "Database already has data, skipping fixtures."
        fi
        
    else
        echo "DATABASE_URL missing — skipping migrations"
    fi
fi

# Inject port into nginx
envsubst '${PORT}' < /etc/nginx/conf.d/default.conf > /etc/nginx/conf.d/default.conf.tmp && \
mv /etc/nginx/conf.d/default.conf.tmp /etc/nginx/conf.d/default.conf

echo "Starting Nginx..."
exec nginx -g "daemon off;"