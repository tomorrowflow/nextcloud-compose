#!/bin/bash

# Official Nextcloud Pre-installation Hook: PHP Configuration
# This runs BEFORE Nextcloud initialization to prevent integrity issues

set -e

echo "🔧 Configuring PHP settings via pre-installation hook..."

# Create optimized PHP configuration
cat > /var/www/html/.user.ini << 'PHPEOF'
; Nextcloud Performance Configuration
; Applied via official pre-installation hooks

; File Upload Settings
upload_max_filesize = 16G
post_max_size = 16G
max_input_time = 3600
max_execution_time = 3600

; Memory Settings
memory_limit = 2G

; OPcache Settings (Performance)
opcache.enable = 1
opcache.enable_cli = 1
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.memory_consumption = 128
opcache.save_comments = 1
opcache.revalidate_freq = 60
opcache.jit_buffer_size = 128M
opcache.jit = 1255

; Session Security
session.cookie_httponly = 1
session.cookie_secure = 1
session.cookie_samesite = "Lax"

; General Security
expose_php = Off
allow_url_fopen = Off

; Error Logging
log_errors = On
error_log = /var/log/php_errors.log

; File handling
file_uploads = On
max_file_uploads = 100

; Timezone
date.timezone = UTC
PHPEOF

echo "✅ Pre-installation PHP configuration completed"