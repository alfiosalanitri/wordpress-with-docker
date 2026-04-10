FROM php:8.3-fpm

# Install necessary system packages
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libonig-dev \
    libzip-dev \
    libxml2-dev \
    libicu-dev \
    imagemagick \
    libmagickwand-dev \
    unzip \
    git \
    curl \
    && pecl install imagick \
    && docker-php-ext-enable imagick \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
       gd \
       intl \
       exif \
       mbstring \
       mysqli \
       opcache \
       pdo \
       pdo_mysql \
       zip \
       bcmath \
       xml \
    && rm -rf /var/lib/apt/lists/*

# Enable recommended extensions
RUN docker-php-ext-enable mysqli pdo_mysql opcache

ARG UID
ARG GID

# Set working directory
WORKDIR /var/www/html

# Copy custom php.ini if present
COPY ./php.ini /usr/local/etc/php/conf.d/custom.ini