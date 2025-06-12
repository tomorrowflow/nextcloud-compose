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

# Function to check if Docker is installed
check_docker() {
    print_info "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH."
        echo
        echo "Docker is required for this Nextcloud installation."
        echo "Please install Docker first:"
        echo "  - Visit: https://docs.docker.com/get-docker/"
        echo "  - Or use your package manager (e.g., apt install docker.io)"
        echo
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed or not available."
        echo
        echo "Docker Compose is required for this Nextcloud installation."
        echo "Please install Docker Compose:"
        echo "  - Visit: https://docs.docker.com/compose/install/"
        echo "  - Or use your package manager"
        echo
        exit 1
    fi
    
    print_success "Docker and Docker Compose are installed."
}

# Function to check if .env exists and ask user what to do
# Returns 0 if keeping existing config, 1 if creating new config
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
                    return 0
                    ;;
                [Nn]|[Nn][Oo])
                    print_info "Creating new configuration..."
                    return 1
                    ;;
                *)
                    print_error "Please answer y (yes) or n (no)."
                    ;;
            esac
        done
    else
        print_info "No existing $ENV_FILE found. Creating new configuration..."
        return 1
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
    
    # Create .env file
    cat > "$ENV_FILE" << EOF
DOMAIN_NAME=$DOMAIN_NAME
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD
NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
EOF
    
    # Set appropriate permissions
    chmod 600 "$ENV_FILE"
    
    print_success "$ENV_FILE file has been created successfully!"
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
    
    # Check Docker installation first
    check_docker
    echo
    
    if check_existing_env; then
        # User chose to keep existing configuration
        print_info "Using existing configuration from $ENV_FILE"
    else
        # User chose to create new configuration or no .env exists
        generate_env_file
    fi
    
    echo
    print_success "Configuration ready! You can now proceed with your Nextcloud installation."
    print_info "The configuration is saved in $ENV_FILE"
    
    # Add your additional commands here
    # For example:
    # print_info "Running additional setup commands..."
    # docker-compose up -d
    # etc.
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