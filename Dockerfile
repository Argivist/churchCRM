# Use a specific, modern PHP 8.1 Apache image
FROM php:8.1-apache

LABEL maintainer="george@dawouds.com"

EXPOSE 80

# Install necessary system dependencies for PHP extensions and common utilities
RUN apt-get update && \
    apt-get install -y \
    libxml2-dev \
    gettext \
    locales \
    locales-all \
    libpng-dev \
    libzip-dev \
    libfreetype6-dev \
    libjpeg-dev \
    libonig-dev \
    libcurl4-openssl-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install common PHP extensions
RUN docker-php-ext-install -j$(nproc) \
    xml \
    exif \
    pdo_mysql \
    gettext \
    iconv \
    mysqli \
    zip \
    curl \
    mbstring

RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install -j$(nproc) gd

# Configure PHP settings
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" && \
    sed -i 's/^upload_max_filesize.*$/upload_max_filesize = 2G/g' $PHP_INI_DIR/php.ini && \
    sed -i 's/^post_max_size.*$/post_max_size = 2G/g' $PHP_INI_DIR/php.ini && \
    sed -i 's/^memory_limit.*$/memory_limit = 2G/g' $PHP_INI_DIR/php.ini && \
    sed -i 's/^max_execution_time.*$/max_execution_time = 120/g' $PHP_INI_DIR/php.ini

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy your entire ChurchCRM application code into a specific directory inside the container
# This copies EVERYTHING from your local project root (where Dockerfile is) into /var/www/html/churchcrm
COPY . /var/www/html/churchcrm

# !!! IMPORTANT CHANGE HERE !!!
# Set the working directory to where composer.json is located inside the container.
# Since your local composer.json is in 'src', it will be at /var/www/html/churchcrm/src in the container.
WORKDIR /var/www/html/churchcrm/src

# Run Composer to install PHP dependencies with increased memory limit
# This command is now expected to work as your local composer update succeeded!
RUN php -d memory_limit=-1 /usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction

# !!! IMPORTANT CHANGE HERE !!!
# Change WORKDIR back to the application's main root for subsequent commands like permissions and Apache config.
# Permissions and Apache's DocumentRoot refer to paths relative to /var/www/html/churchcrm.
WORKDIR /var/www/html/churchcrm

# Set appropriate permissions for writable directories (ChurchCRM needs these)
# These paths are now relative to /var/www/html/churchcrm.
RUN chown -R www-data:www-data src/temp src/session src/Images/Person src/Images/Family && \
    chmod -R 775 src/temp src/session src/Images/Person src/Images/Family

# --- Apache Configuration ---
# Create the directory for sites-available
RUN mkdir -p /etc/apache2/sites-available/
# Copy our custom virtual host config for ChurchCRM
COPY docker/apache/churchcrm.conf /etc/apache2/sites-available/churchcrm.conf
# Disable the default Apache site and enable our ChurchCRM site
RUN a2dissite 000-default.conf || true && \
    a2ensite churchcrm.conf && \
    a2enmod rewrite

# The base image already has Apache configured to serve.
# This CMD ensures Apache stays in the foreground for Docker.
CMD ["apache2ctl", "-D", "FOREGROUND"]