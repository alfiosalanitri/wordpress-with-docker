FROM php:8.4-fpm

COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/

RUN apt-get update && apt-get install -y --no-install-recommends \
        unzip \
        git \
        curl \
    && rm -rf /var/lib/apt/lists/*

RUN install-php-extensions \
        gd \
        intl \
        exif \
        mysqli \
        opcache \
        pdo_mysql \
        zip \
        bcmath

# Imagick built from GitHub sources (PECL is unreliable)
RUN install-php-extensions Imagick/imagick@3.8.0

# Install WP-CLI (pinned release, verified against its published SHA-512)
ARG WP_CLI_VERSION=2.12.0
ARG WP_CLI_SHA512=be928f6b8ca1e8dfb9d2f4b75a13aa4aee0896f8a9a0a1c45cd5d2c98605e6172e6d014dda2e27f88c98befc16c040cbb2bd1bfa121510ea5cdf5f6a30fe8832
RUN curl -fsSL -o /usr/local/bin/wp \
        https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar \
    && echo "${WP_CLI_SHA512}  /usr/local/bin/wp" | sha512sum -c - \
    && chmod +x /usr/local/bin/wp

ARG UID
ARG GID

WORKDIR /var/www/html

COPY ./php.ini /usr/local/etc/php/conf.d/custom.ini
