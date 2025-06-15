#!/bin/bash

# Official Nextcloud Pre-installation Hook: bz2 Extension Installation
# This runs BEFORE Nextcloud initialization

set -e

echo "📦 Installing bz2 extension via pre-installation hook..."

# Update package list and install bz2 development files
apt-get update
apt-get install -y libbz2-dev

# Install bz2 PHP extension
docker-php-ext-install bz2

# Enable the extension
docker-php-ext-enable bz2

# Verify installation
if php -m | grep -q bz2; then
    echo "✅ bz2 extension installed and enabled successfully"
else
    echo "❌ Failed to install bz2 extension"
    exit 1
fi

echo "✅ Pre-installation bz2 extension setup completed"