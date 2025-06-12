#!/bin/bash

# Nextcloud Installation Setup Script
# This script creates or updates the .env file for Nextcloud installation

set -euo pipefail

ENV_FILE=".env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to generate random password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Function to read password with confirmation
read_password() {
    local prompt="$1"
    local password
    local password_confirm
    
    while true; do
        echo -n "$prompt: " >&2
        read -s password
        echo >&2
        
        echo -n "Confirm $prompt: " >&2
        read -s password_confirm
        echo >&2
        
        if [[ "$password" == "$password_confirm" ]]; then
            if [[ -z "$password" ]]; then
                echo -e "${RED}[ERROR]${NC} Password cannot be empty. Please try again." >&2
                continue
            fi
            echo "$password"
            return 0
        else
            echo -e "${RED}[ERROR]${NC} Passwords do not match. Please try again." >&2
        fi
    done
}

# Function to read input with default value
read_with_default() {
    local prompt="$1"
    local default_value="$2"
    local input
    
    if [[ -n "$default_value" ]]; then
        read -p "$prompt [$default_value]: " input
        echo "${input:-$default_value}"
    else
        read -p "$prompt: " input
        while [[ -z "$input" ]]; do
            print_error "This field cannot be empty."
            read -p "$prompt: " input
        done
        echo "$input"
    fi
}

# Function to check if .env exists and ask user what to do
check_existing_env() {
    if [[ -f "$ENV_FILE" ]]; then
        print_info "Found existing $ENV_FILE file."
        echo
        cat "$ENV_FILE"
        echo
        
        while true; do
            read -p "Do you want to keep the existing configuration? (y/n): " choice
            case "$choice" in
                [Yy]|[Yy][Ee][Ss])
                    print_success "Keeping existing configuration."
                    exit 0
                    ;;
                [Nn]|[Nn][Oo])
                    print_info "Creating new configuration..."
                    break
                    ;;
                *)
                    print_error "Please answer y (yes) or n (no)."
                    ;;
            esac
        done
    else
        print_info "No existing $ENV_FILE found. Creating new configuration..."
    fi
}

# Function to generate .env file
generate_env_file() {
    print_info "Please provide the following information for your Nextcloud installation:"
    echo
    
    # Domain name
    DOMAIN_NAME=$(read_with_default "Domain name (e.g., nextcloud.example.com)" "")
    
    # MySQL root password
    print_info "MySQL root password (used for database administration)"
    MYSQL_ROOT_PASSWORD=$(read_password "MySQL root password")
    
    # MySQL Nextcloud password
    print_info "MySQL password for Nextcloud database user"
    MYSQL_PASSWORD=$(read_password "MySQL Nextcloud password")
    
    # Nextcloud admin user
    NEXTCLOUD_ADMIN_USER=$(read_with_default "Nextcloud admin username" "admin")
    
    # Nextcloud admin password
    print_info "Nextcloud admin password"
    NEXTCLOUD_ADMIN_PASSWORD=$(read_password "Nextcloud admin password")
    
    # Generate Redis password automatically
    print_info "Generating secure Redis password..."
    REDIS_PASSWORD=$(generate_password 24)

    # Creating secure random strings for talk-hpb
    TURN_SECRET=`openssl rand --hex 32`
    SIGNALING_SECRET=`openssl rand --hex 32`
    INTERNAL_SECRET=`openssl rand --hex 32`
    
    # Create .env file
    cat > "$ENV_FILE" << EOF
DOMAIN_NAME=$DOMAIN_NAME
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD
NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
TURN_SECRET=$TURN_SECRET
SIGNALING_SECRET=$SIGNALING_SECRET
INTERNAL_SECRET=$INTERNAL_SECRET
EOF
    
    # Set appropriate permissions
    chmod 600 "$ENV_FILE"
    
    print_success "$ENV_FILE file has been created successfully!"

    print_success "Please note the following details for the Nextcloud Talk High-Performance Backend"
    print_success "Signaling server: wss://signal.$DOMAIN_NAME"
    print_success "Signaling secret: $SIGNALING_SECRET"

    print_success "Turn server: signal.$DOMAIN_NAME:3478"
    print_success "Turn secret: $TURN_SECRET"
    print_warning "Make sure to keep this file secure as it contains sensitive passwords."
}

# Function to validate domain name
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# Main execution
main() {
    echo "========================================"
    echo "  Nextcloud Installation Setup"
    echo "========================================"
    echo
    
    check_existing_env
    generate_env_file
    
    echo
    print_success "Setup completed! We will now proceed with your Nextcloud installation."
    print_info "The configuration has been saved to $ENV_FILE"
}

# Run main function
main "$@"

# Start Docker Compose
print_info "Starting Docker Compose..."
docker compose up -d

print_info "Monitoring Nextcloud initialization..."

# Monitor Docker logs for initialization completion
docker logs -f nextcloud-app 2>&1 | while read LOG_LINE; do
  echo "$LOG_LINE"
  if [[ "$LOG_LINE" == *"nextcloud-app  | Initializing finished"* ]]; then
    print_info "Nextcloud initialization completed. Stopping Docker containers..."
    docker-compose down
    break
  fi
done

# Increase file handling in PHP
printf "php_value upload_max_filesize=16G
php_value post_max_size=16G" >> /opt/containers/nextcloud/app/.user.ini

printf "opcache.enable_cli => 1\napc.enable_cli => 1
opcache.save_comments => 1
opcache.revalidate_freq => 60
opcache.validate_timestamps => 0
opcache.interned_strings_buffer => 8
opcache.max_accelerated_files => 10000
opcache.memory_consumption => 128
opcache.jit => 1255
opcache.jit_buffer_size => 128" >> /opt/containers/nextcloud/app/.user.ini

# Start Docker Compose again
print_info "Starting Docker Compose..."
docker compose up -d

# Run Nextcloud configuration commands
docker exec -it -u 33 nextcloud-app ./occ config:system:set maintenance_window_start --value="1" --type=integer
docker exec -it -u 33 nextcloud-app ./occ config:system:set default_phone_region --value="DE"
docker exec -it -u 33 nextcloud-app ./occ db:add-missing-indices
docker exec -it -u 33 nextcloud-app ./occ maintenance:repair --include-expensive
docker exec -it -u 33 nextcloud-app ./occ app:enable spreed
docker exec -it -u 33 nextcloud-app ./occ app:enable calendar

print_success "Nextcloud installation is complete. You can access it at https://$DOMAIN_NAME"