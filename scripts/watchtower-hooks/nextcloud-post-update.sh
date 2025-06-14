#!/bin/bash

# Function to install bz2 extension in Nextcloud container
install_nextcloud_bz2() {
    echo "Installing bz2 extension in Nextcloud container..."
    
    # Wait for container to be running
    local container_name="nextcloud-app"
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec $container_name test -f /var/www/html/version.php 2>/dev/null; then
            echo "Nextcloud container is ready"
            break
        fi
        echo "Waiting for Nextcloud container to be ready... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        echo "Error: Nextcloud container failed to start properly"
        return 1
    fi
    
    # Install bz2 extension
    docker exec $container_name bash -c "
        set -e
        echo 'Installing bz2 extension...'
        apt-get update
        apt-get install -y libbz2-dev
        docker-php-ext-install bz2
        docker-php-ext-enable bz2
        apt-get autoremove -y
        apt-get autoclean
        rm -rf /var/lib/apt/lists/*
        echo 'bz2 extension installed successfully!'
        php -m | grep -i bz2 && echo '✓ bz2 extension is loaded' || echo '✗ Warning: bz2 extension not found'
    "
    
    if [ $? -eq 0 ]; then
        echo "✓ bz2 extension installation completed successfully"
        return 0
    else
        echo "✗ Failed to install bz2 extension"
        return 1
    fi
}

# Function to setup watchtower post-update hook
setup_watchtower_hooks() {
    echo "Setting up watchtower post-update hooks..."
    
    # Create hooks directory
    mkdir -p ./scripts/watchtower-hooks
    
    # Create post-update script for Nextcloud
    cat > ./scripts/watchtower-hooks/nextcloud-post-update.sh << 'EOF'
#!/bin/bash
set -e

echo "Watchtower post-update hook: Installing bz2 extension..."

# Check if this is a Nextcloud container update
if [[ "$WATCHTOWER_CONTAINER_NAME" == *"nextcloud-app"* ]]; then
    echo "Nextcloud container was updated, reinstalling bz2 extension..."
    
    # Wait a bit for container to stabilize
    sleep 30
    
    # Install bz2 extension
    docker exec nextcloud-app bash -c "
        set -e
        echo 'Reinstalling bz2 extension after watchtower update...'
        apt-get update
        apt-get install -y libbz2-dev
        docker-php-ext-install bz2
        docker-php-ext-enable bz2
        apt-get autoremove -y
        apt-get autoclean
        rm -rf /var/lib/apt/lists/*
        echo 'bz2 extension reinstalled successfully!'
        php -m | grep -i bz2 && echo '✓ bz2 extension is loaded' || echo '✗ Warning: bz2 extension not found'
    "
    
    # Restart container to ensure changes take effect
    docker restart nextcloud-app
    
    echo "✓ Nextcloud post-update hook completed"
fi
EOF
    
    chmod +x ./scripts/watchtower-hooks/nextcloud-post-update.sh
    echo "✓ Watchtower hooks setup completed"
}

# Function to be called during initial installation
setup_nextcloud_extensions() {
    echo "=== Setting up Nextcloud Extensions ==="
    
    # Create scripts directory
    mkdir -p ./scripts
    
    # Install bz2 extension
    install_nextcloud_bz2
    
    # Setup watchtower hooks
    setup_watchtower_hooks
    
    echo "=== Nextcloud Extensions Setup Complete ==="
}

# Alternative: Enhanced watchtower configuration with notifications
setup_enhanced_watchtower() {
    echo "Setting up enhanced watchtower configuration..."
    
    # Create watchtower notification script
    cat > ./scripts/watchtower-notification.sh << 'EOF'
#!/bin/bash
# Watchtower notification and post-update script

case "$1" in
    "updated")
        echo "Container $WATCHTOWER_CONTAINER_NAME was updated"
        # If Nextcloud was updated, reinstall bz2
        if [[ "$WATCHTOWER_CONTAINER_NAME" == *"nextcloud-app"* ]]; then
            /path/to/your/scripts/watchtower-hooks/nextcloud-post-update.sh
        fi
        ;;
    "failed")
        echo "Container $WATCHTOWER_CONTAINER_NAME update failed"
        ;;
esac
EOF
    
    chmod +x ./scripts/watchtower-notification.sh
    echo "✓ Enhanced watchtower setup completed"
}

echo "Nextcloud installation functions loaded."
echo "Available functions:"
echo "  - install_nextcloud_bz2"
echo "  - setup_watchtower_hooks" 
echo "  - setup_nextcloud_extensions"
echo "  - setup_enhanced_watchtower"