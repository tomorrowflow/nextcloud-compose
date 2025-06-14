#!/bin/bash
set -e

echo "Installing bz2 extension for Nextcloud..."

# Update package list
apt-get update

# Install bzip2 library and PHP extension
apt-get install -y libbz2-dev

# Install and enable PHP bz2 extension
docker-php-ext-install bz2
docker-php-ext-enable bz2

# Clean up to reduce image size
apt-get autoremove -y
apt-get autoclean
rm -rf /var/lib/apt/lists/*

echo "bz2 extension installed successfully!"

# Verify installation
php -m | grep -i bz2 && echo "bz2 extension is loaded" || echo "Warning: bz2 extension not found"