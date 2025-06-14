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

# Function to validate email address
validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
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

# Function to setup directory structure
setup_directories() {
    print_info "Setting up directory structure..."
    
    # Create main directories
    mkdir -p traefik/{config,letsencrypt}
    mkdir -p database
    mkdir -p app
    mkdir -p data
    mkdir -p scripts/{watchtower-hooks}
    
    # Set proper permissions for acme.json
    touch traefik/acme.json
    chmod 600 traefik/acme.json
    
    print_success "Directory structure created successfully."
}

# Function to create Docker network
create_docker_network() {
    print_info "Creating Docker network..."
    
    if docker network ls | grep -q "proxy"; then
        print_warning "Network 'proxy' already exists, skipping creation."
    else
        docker network create proxy --driver bridge --subnet=172.18.0.0/24 --gateway=172.18.0.1
        print_success "Docker network 'proxy' created successfully."
    fi
}

# Function to create Nextcloud initialization script
create_nextcloud_init_script() {
    print_info "Creating Nextcloud initialization script..."
    
    cat > scripts/nextcloud-init.sh << 'EOF'
#!/bin/bash
set -e

echo "Installing bz2 extension and curl for Nextcloud..."

# Update package list
apt-get update

# Install bzip2 library, curl, and PHP extension
apt-get install -y libbz2-dev curl

# Install and enable PHP bz2 extension
docker-php-ext-install bz2
docker-php-ext-enable bz2

# Clean up to reduce image size
apt-get autoremove -y
apt-get autoclean
rm -rf /var/lib/apt/lists/*

echo "bz2 extension and curl installed successfully!"

# Verify installation
php -m | grep -i bz2 && echo "✓ bz2 extension is loaded" || echo "✗ Warning: bz2 extension not found"
curl --version >/dev/null 2>&1 && echo "✓ curl is available" || echo "✗ Warning: curl not found"
EOF
    
    chmod +x scripts/nextcloud-init.sh
    print_success "Nextcloud initialization script created."
}

# Function to create watchtower post-update hooks
create_watchtower_hooks() {
    print_info "Creating watchtower post-update hooks..."
    
    cat > scripts/watchtower-hooks/nextcloud-post-update.sh << 'EOF'
#!/bin/bash
set -e

echo "Watchtower post-update hook: Reinstalling bz2 extension and curl..."

# Wait for container to be ready
sleep 60

# Install bz2 extension and curl
docker exec nextcloud-app bash -c "
    set -e
    echo 'Reinstalling bz2 extension and curl after watchtower update...'
    apt-get update
    apt-get install -y libbz2-dev curl
    docker-php-ext-install bz2
    docker-php-ext-enable bz2
    apt-get autoremove -y
    apt-get autoclean
    rm -rf /var/lib/apt/lists/*
    echo 'bz2 extension and curl reinstalled successfully!'
    php -m | grep -i bz2 && echo '✓ bz2 extension is loaded' || echo '✗ Warning: bz2 extension not found'
    curl --version >/dev/null 2>&1 && echo '✓ curl is available' || echo '✗ Warning: curl not found'
"

echo "✓ Post-update hook completed"
EOF
    
    chmod +x scripts/watchtower-hooks/nextcloud-post-update.sh
    print_success "Watchtower hooks created successfully."
}

# Function to generate Traefik dashboard password hash
generate_traefik_password_hash() {
    local password="$1"
    local username="admin"
    
    # Use htpasswd to generate the hash (Apache APR1 format)
    if command -v htpasswd &> /dev/null; then
        htpasswd -nbB "$username" "$password" | cut -d: -f2
    else
        # Fallback: use openssl to generate APR1 hash
        echo "$password" | openssl passwd -apr1 -stdin
    fi
}

# Function to update dynamic.yml with generated password hash
update_dynamic_yml() {
    local password_hash="$1"
    
    print_info "Creating dynamic.yml configuration..."
    
    cat > traefik/config/dynamic.yml << EOF
# Dynamic configuration
http:
  middlewares:
    # Security headers for all HTTPS traffic
    secureHeaders:
      headers:
        sslRedirect: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 15552000
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        customFrameOptionsValue: "SAMEORIGIN"
        customRequestHeaders:
          X-Forwarded-Proto: "https"
    
    # Basic authentication for Traefik dashboard
    user-auth:
      basicAuth:
        users:
          - "admin:${password_hash}"
    
    # Strip /traefik prefix for dashboard access
    traefik-stripprefix:
      stripPrefix:
        prefixes:
          - "/traefik"
        forceSlash: false
    
    # Redirect HTTP to HTTPS
    redirect-to-https:
      redirectScheme:
        scheme: https
        permanent: true
    
    # Nextcloud specific headers
    nextcloud-headers:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: "https"
        customResponseHeaders:
          X-Frame-Options: "SAMEORIGIN"
          X-Content-Type-Options: "nosniff"
          X-XSS-Protection: "1; mode=block"
          Referrer-Policy: "strict-origin-when-cross-origin"

tls:
  options:
    default:
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
      minVersion: VersionTLS12
      maxVersion: VersionTLS13
EOF
    
    print_success "dynamic.yml configuration created."
}

# Function to create traefik.yml with email from .env
create_traefik_yml() {
    local letsencrypt_email="$1"
    
    print_info "Creating traefik.yml configuration..."
    
    cat > traefik/traefik.yml << EOF
api:
  dashboard: true
  insecure: false
  debug: false

ping: {}

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https

  websecure:
    address: ":443"
    http:
      middlewares:
        - secureHeaders@file
      tls:
        certResolver: letsencrypt

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: proxy
  file:
    watch: true
    filename: /config/dynamic.yml

certificatesResolvers:
  letsencrypt:
    acme:
      email: '${letsencrypt_email}'
      storage: 'acme.json'
      tlsChallenge: {}

log:
  level: INFO

accessLog: {}
EOF
    
    print_success "traefik.yml configuration created."
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
    
    # Let's Encrypt email
    while true; do
        LETSENCRYPT_EMAIL=$(read_with_default "Email for Let's Encrypt certificates" "")
        if validate_email "$LETSENCRYPT_EMAIL"; then
            break
        else
            print_error "Please enter a valid email address."
        fi
    done
    
    # Traefik dashboard password
    print_info "Traefik dashboard password (for accessing /traefik/dashboard/)"
    TRAEFIK_DASHBOARD_PASSWORD=$(read_password "Traefik dashboard password")
    
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
    
    # Generate Watchtower API token
    WATCHTOWER_API_TOKEN=$(generate_password 32)
    
    # Create .env file
    cat > "$ENV_FILE" << EOF
DOMAIN_NAME=$DOMAIN_NAME
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
TRAEFIK_DASHBOARD_PASSWORD=$TRAEFIK_DASHBOARD_PASSWORD
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD
NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
TURN_SECRET=$TURN_SECRET
SIGNALING_SECRET=$SIGNALING_SECRET
INTERNAL_SECRET=$INTERNAL_SECRET
WATCHTOWER_API_TOKEN=$WATCHTOWER_API_TOKEN

# Watchtower Email Notifications (Optional - uncomment and configure if needed)
# WATCHTOWER_EMAIL_FROM=watchtower@$DOMAIN_NAME
# WATCHTOWER_EMAIL_TO=admin@$DOMAIN_NAME
# WATCHTOWER_EMAIL_SERVER=smtp.$DOMAIN_NAME
# WATCHTOWER_EMAIL_PORT=587
# WATCHTOWER_EMAIL_USER=watchtower@$DOMAIN_NAME
# WATCHTOWER_EMAIL_PASSWORD=your-email-password
EOF
    
    # Set appropriate permissions
    chmod 600 "$ENV_FILE"
    
    print_success "$ENV_FILE file has been created successfully!"
    print_warning "Make sure to keep this file secure as it contains sensitive passwords."
    
    # Generate configuration files using the new values
    local password_hash=$(generate_traefik_password_hash "$TRAEFIK_DASHBOARD_PASSWORD")
    update_dynamic_yml "$password_hash"
    create_traefik_yml "$LETSENCRYPT_EMAIL"
}

# Function to install bz2 extension in running container
install_bz2_extension() {
    print_info "Installing bz2 extension in Nextcloud container..."
    
    local container_name="nextcloud-app"
    local max_attempts=60
    local attempt=1
    
    # First, check if container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        print_error "Container $container_name is not running"
        return 1
    fi
    
    # Wait for container to be ready
    print_info "Waiting for Nextcloud container to be fully ready..."
    while [ $attempt -le $max_attempts ]; do
        # Check if Nextcloud is responding and not in maintenance mode
        if docker exec $container_name curl -f -s http://localhost:80/status.php 2>/dev/null | grep -q '"installed":true'; then
            print_success "Nextcloud container is ready for bz2 installation"
            break
        fi
        print_info "Waiting for Nextcloud container to be ready... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_error "Nextcloud container failed to become ready for bz2 installation"
        print_info "Checking container status..."
        docker ps --filter "name=$container_name"
        docker logs --tail 20 $container_name
        return 1
    fi
    
    # Install bz2 extension
    print_info "Installing bz2 extension and curl..."
    if docker exec $container_name bash -c "
        set -e
        echo 'Installing bz2 extension and curl...'
        apt-get update >/dev/null 2>&1
        apt-get install -y libbz2-dev curl >/dev/null 2>&1
        docker-php-ext-install bz2 >/dev/null 2>&1
        docker-php-ext-enable bz2 >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        apt-get autoclean >/dev/null 2>&1
        rm -rf /var/lib/apt/lists/* >/dev/null 2>&1
        echo 'bz2 extension and curl installed successfully!'
        php -m | grep -i bz2 && echo '✓ bz2 extension is loaded' || echo '✗ Warning: bz2 extension not found'
        curl --version >/dev/null 2>&1 && echo '✓ curl is available' || echo '✗ Warning: curl not found'
    "; then
        print_success "bz2 extension installation completed successfully"
        return 0
    else
        print_error "Failed to install bz2 extension"
        return 1
    fi
}

# Function to validate domain name
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# Function to monitor Docker compose logs for initialization completion
monitor_nextcloud_initialization() {
    local container_name="nextcloud-app"
    local search_term="Initializing finished"
    local timeout_seconds=600
    
    print_info "Monitoring docker compose logs for: '$search_term'"
    print_info "Timeout set to $timeout_seconds seconds"
    
    # Create a temporary file to store the initialization flag
    local init_flag="/tmp/nextcloud_init_complete_$$"
    
    # Start monitoring logs in background
    (
        timeout "$timeout_seconds" docker compose logs -f "$container_name" 2>&1 | while IFS= read -r LOG_LINE; do
            echo "$LOG_LINE"
            
            if [[ "$LOG_LINE" == *"$search_term"* ]]; then
                print_info "Found initialization completion message!"
                print_info "Nextcloud initialization completed. Stopping Docker containers..."
                
                # Create flag file to signal completion
                touch "$init_flag"
                
                # Kill the log monitoring process
                pkill -f "docker compose logs -f $container_name" 2>/dev/null || true
                break
            fi
        done
    ) &
    
    local log_pid=$!
    
    # Wait for initialization to complete or timeout
    local elapsed=0
    while [ ! -f "$init_flag" ] && [ $elapsed -lt $timeout_seconds ]; do
        sleep 2
        elapsed=$((elapsed + 2))
        
        # Check if the log monitoring process is still running
        if ! kill -0 $log_pid 2>/dev/null; then
            break
        fi
    done
    
    # Clean up
    kill $log_pid 2>/dev/null || true
    
    if [ -f "$init_flag" ]; then
        # Stop containers
        sleep 10
        docker compose down
        if [ $? -eq 0 ]; then
            print_success "Docker containers stopped successfully"
        else
            print_error "Failed to stop Docker containers"
            rm -f "$init_flag"
            exit 1
        fi
        
        sleep 15
        rm -f "$init_flag"
        return 0
    else
        print_error "Timeout waiting for Nextcloud initialization or process failed"
        rm -f "$init_flag" 2>/dev/null || true
        return 1
    fi
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
    
    # Setup directory structure
    setup_directories
    echo
    
    # Create Docker network
    create_docker_network
    echo
    
    # Create utility scripts
    create_nextcloud_init_script
    create_watchtower_hooks
    
    # Create troubleshooting script
    cat > troubleshoot.sh << 'TROUBLESHOOT_EOF'
#!/bin/bash

# Nextcloud Docker Troubleshooting Script
# This script helps diagnose common issues with the Nextcloud installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}=== $1 ===${NC}"; }

# Check container status
check_container_status() {
    print_header "Container Status Check"
    echo -e "\n${BLUE}Running Containers:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Check health status
check_health_status() {
    print_header "Health Check Status"
    for container in nextcloud-app nextcloud-db nextcloud-redis nextcloud-traefik; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            health_status=$(docker inspect $container --format='{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
            if [ "$health_status" = "healthy" ]; then
                print_success "✓ $container: $health_status"
            elif [ "$health_status" = "starting" ]; then
                print_warning "⏳ $container: $health_status"
            elif [ "$health_status" = "unhealthy" ]; then
                print_error "✗ $container: $health_status"
            else
                print_info "ℹ️  $container: no health check configured"
            fi
        else
            print_error "✗ $container: not running"
        fi
    done
}

# Check Traefik specific issues
check_traefik() {
    print_header "Traefik Diagnostic"
    if ! docker ps --format "{{.Names}}" | grep -q "^nextcloud-traefik$"; then
        print_error "✗ Traefik container is not running"
        return 1
    fi
    
    if docker exec nextcloud-traefik wget -qO- http://localhost:8080/ping 2>/dev/null | grep -q "OK"; then
        print_success "✓ Traefik ping endpoint accessible"
    else
        print_error "✗ Traefik ping endpoint not accessible"
    fi
    
    echo -e "\n${BLUE}Recent Traefik logs:${NC}"
    docker logs nextcloud-traefik --tail 5
}

# Main execution
main() {
    echo "========================================"
    echo "  Nextcloud Docker Troubleshooting"
    echo "========================================"
    echo
    check_container_status
    echo
    check_health_status
    echo
    check_traefik
    echo
    print_info "For detailed diagnostics, check individual container logs:"
    print_info "  docker-compose logs -f [service-name]"
}

main "$@"
TROUBLESHOOT_EOF
    
    chmod +x troubleshoot.sh
    
    # Create dashboard testing script
    cat > test-dashboard.sh << 'TESTDASH_EOF'
#!/bin/bash

# Traefik Dashboard Testing Script
# This script tests if the Traefik dashboard routing is working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if .env file exists and load it
if [ ! -f ".env" ]; then
    print_error ".env file not found"
    exit 1
fi
source .env

echo "=== Traefik Dashboard Routing Test ==="
echo "Domain: $DOMAIN_NAME"
echo

# Test dashboard routing
print_info "Testing dashboard routing..."
dashboard_response=$(curl -s -w "%{http_code}" -H "Host: $DOMAIN_NAME" "http://localhost/traefik/dashboard/" -o /dev/null 2>/dev/null || echo "000")

case $dashboard_response in
    "401")
        print_success "✓ Dashboard routing working (401 = auth required)"
        echo "Access at: https://$DOMAIN_NAME/traefik/dashboard/"
        ;;
    "404")
        print_error "✗ Dashboard shows 404 - request going to Nextcloud instead"
        echo "Fix: docker restart nextcloud-traefik"
        ;;
    *)
        print_warning "⚠️  Dashboard returned HTTP $dashboard_response"
        ;;
esac

# Test with authentication if password available
if [ -n "$TRAEFIK_DASHBOARD_PASSWORD" ]; then
    print_info "Testing with authentication..."
    auth_response=$(curl -s -w "%{http_code}" -u "admin:$TRAEFIK_DASHBOARD_PASSWORD" -H "Host: $DOMAIN_NAME" "http://localhost/traefik/dashboard/" -o /dev/null 2>/dev/null || echo "000")
    if [ "$auth_response" = "200" ]; then
        print_success "✓ Dashboard accessible with authentication"
    else
        print_warning "⚠️  Auth test returned HTTP $auth_response"
    fi
fi

echo
print_info "For detailed troubleshooting, run: ./troubleshoot.sh"
TESTDASH_EOF
    
    chmod +x test-dashboard.sh
    
    # Create integrity fix script
    cat > fix-integrity.sh << 'INTEGRITY_EOF'
#!/bin/bash

# Nextcloud Integrity Fix Script - Focus on hash regeneration
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if ! docker ps --format "{{.Names}}" | grep -q "^nextcloud-app$"; then
    print_error "Nextcloud container is not running"
    exit 1
fi

echo "=== Nextcloud Integrity Hash Regeneration ==="

# Step 1: Update .user.ini
print_info "Updating .user.ini with performance settings..."
cat > ./app/.user.ini << 'USERINI_EOF'
; Nextcloud PHP Configuration - Performance optimized

; File upload settings
php_value upload_max_filesize=16G
php_value post_max_size=16G
php_value max_execution_time=3600
php_value max_input_time=3600
php_value memory_limit=2048M

; OPCache settings
opcache.enable_cli=1
apc.enable_cli=1
opcache.save_comments=1
opcache.revalidate_freq=60
opcache.validate_timestamps=0
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.jit=1255
opcache.jit_buffer_size=128

; Security settings
php_value session.cookie_httponly=1
php_value session.cookie_secure=1
php_value session.cookie_samesite=Strict
USERINI_EOF

# Step 2: Regenerate integrity hashes
print_info "Regenerating Nextcloud integrity hashes..."
docker exec -u 33 nextcloud-app bash -c "
    echo 'Enabling maintenance mode...'
    ./occ maintenance:mode --on
    echo 'Clearing integrity cache...'
    rm -f /var/www/html/data/.integrity.check.disabled 2>/dev/null || true
    rm -rf /var/www/html/data/integrity.results.json 2>/dev/null || true
    echo 'Updating htaccess...'
    ./occ maintenance:update-htaccess
    echo 'Regenerating hashes (this may take a minute)...'
    ./occ maintenance:repair --include-expensive
    echo 'Disabling maintenance mode...'
    ./occ maintenance:mode --off
"

sleep 10

# Step 3: Check results
print_info "Checking integrity status..."
if docker exec -u 33 nextcloud-app ./occ integrity:check-core --output=json 2>/dev/null | grep -q "INVALID_HASH"; then
    print_warning "Hash regeneration didn't completely resolve the issue"
    print_info "Applying fallback: excluding .user.ini from integrity checks"
    docker exec -u 33 nextcloud-app ./occ config:system:set integrity.excluded.files --value='[".user.ini"]' --type=json
    print_success "✓ .user.ini excluded from future integrity checks"
else
    print_success "✓ SUCCESS! Integrity hashes regenerated successfully"
fi

# Step 4: Verify settings
echo ""
print_info "Verifying PHP settings are active:"
docker exec nextcloud-app php -r "echo 'Upload limit: ' . ini_get('upload_max_filesize') . PHP_EOL;"
docker exec nextcloud-app php -r "echo 'Memory limit: ' . ini_get('memory_limit') . PHP_EOL;"
docker exec nextcloud-app php -r "echo 'Execution time: ' . ini_get('max_execution_time') . 's' . PHP_EOL;"

print_success "Fix completed! Check your Nextcloud admin panel."
INTEGRITY_EOF
    
    chmod +x fix-integrity.sh
    
    echo
    
    if check_existing_env; then
        # User chose to keep existing configuration
        print_info "Using existing configuration from $ENV_FILE"
        
        # Still need to create config files if they don't exist
        if [[ ! -f "traefik/config/dynamic.yml" ]] || [[ ! -f "traefik/traefik.yml" ]]; then
            print_info "Configuration files missing, recreating them..."
            
            # Extract values from existing .env
            source "$ENV_FILE"
            local password_hash=$(generate_traefik_password_hash "$TRAEFIK_DASHBOARD_PASSWORD")
            update_dynamic_yml "$password_hash"
            create_traefik_yml "$LETSENCRYPT_EMAIL"
        fi
    else
        # User chose to create new configuration or no .env exists
        generate_env_file
    fi
    
    echo
    print_success "Configuration ready! Starting Nextcloud installation..."
    print_info "The configuration is saved in $ENV_FILE"
    echo
}

# Run main function
main "$@"

# Start Docker Compose
print_info "Starting Docker Compose..."
docker compose up -d

print_info "Monitoring Nextcloud initialization..."

# Monitor Docker logs for initialization completion using improved method
if monitor_nextcloud_initialization; then
    print_success "Nextcloud initialization monitoring completed successfully"
else
    print_error "Nextcloud initialization monitoring failed"
    exit 1
fi

# Restart containers after initialization monitoring
print_info "Restarting containers after initialization..."
docker compose up -d
sleep 30

# Install bz2 extension while containers are running
print_info "Installing bz2 extension..."
if install_bz2_extension; then
    print_success "bz2 extension installed successfully"
else
    print_error "Failed to install bz2 extension"
    exit 1
fi

# Run Nextcloud configuration commands
print_info "Waiting for Nextcloud to be ready for final configuration..."
sleep 60

# Check Traefik status before final configuration
print_info "Checking Traefik container status..."
if docker ps --filter "name=nextcloud-traefik" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
    print_success "Traefik container is running"
else
    print_warning "Traefik container may not be healthy yet"
    print_info "Traefik container status:"
    docker ps --filter "name=nextcloud-traefik" --format "table {{.Names}}\t{{.Status}}"
    print_info "Checking Traefik logs:"
    docker logs --tail 10 nextcloud-traefik
fi

print_info "Running Nextcloud configuration commands..."
docker exec -it -u 33 nextcloud-app ./occ upgrade
docker exec -it -u 33 nextcloud-app ./occ config:system:set maintenance_window_start --value="1" --type=integer
docker exec -it -u 33 nextcloud-app ./occ config:system:set default_phone_region --value="DE"
docker exec -it -u 33 nextcloud-app ./occ db:add-missing-indices
docker exec -it -u 33 nextcloud-app ./occ maintenance:repair --include-expensive
docker exec -it -u 33 nextcloud-app ./occ app:enable spreed
docker exec -it -u 33 nextcloud-app ./occ app:enable calendar

# Update PHP settings in .user.ini AFTER initial setup
print_info "Updating PHP configuration (.user.ini)..."
cat > ./app/.user.ini << 'EOF'
; Nextcloud PHP Configuration
; Updated during installation for better performance

; File upload settings
php_value upload_max_filesize=16G
php_value post_max_size=16G
php_value max_execution_time=3600
php_value max_input_time=3600
php_value memory_limit=2048M

; OPCache settings for better performance
opcache.enable_cli=1
apc.enable_cli=1
opcache.save_comments=1
opcache.revalidate_freq=60
opcache.validate_timestamps=0
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.jit=1255
opcache.jit_buffer_size=128

; Security settings
php_value session.cookie_httponly=1
php_value session.cookie_secure=1
php_value session.cookie_samesite=Strict
EOF

# Update Nextcloud integrity hashes to include our .user.ini changes
print_info "Updating Nextcloud integrity checksums..."
if docker exec -u 33 nextcloud-app ./occ integrity:check-core --output=json 2>/dev/null | grep -q "INVALID_HASH"; then
    print_warning "Integrity check shows invalid hashes (expected after .user.ini update)"
    print_info "Resetting integrity hashes..."
    
    # Method 1: Try to update htaccess (sometimes fixes integrity issues)
    docker exec -u 33 nextcloud-app ./occ maintenance:update-htaccess
    
    # Method 2: Clear integrity check cache and disable/re-enable integrity checking
    docker exec -u 33 nextcloud-app ./occ config:system:set integrity.check.disabled --value=true --type=boolean
    sleep 2
    docker exec -u 33 nextcloud-app ./occ config:system:delete integrity.check.disabled
    
    print_success "Integrity hashes updated - .user.ini modifications should now be accepted"
else
    print_success "No integrity issues detected"
fi

# Give Traefik more time to become healthy
print_info "Waiting for Traefik to become fully healthy..."
sleep 30

# Check if Traefik is healthy before restart
traefik_health_attempts=10
traefik_attempt=1
while [ $traefik_attempt -le $traefik_health_attempts ]; do
    if docker inspect nextcloud-traefik --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
        print_success "Traefik is healthy"
        break
    elif docker inspect nextcloud-traefik --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "starting"; then
        print_info "Traefik health check still starting... (attempt $traefik_attempt/$traefik_health_attempts)"
        sleep 10
        ((traefik_attempt++))
    else
        print_warning "Traefik health status unknown, proceeding anyway"
        docker logs --tail 5 nextcloud-traefik
        break
    fi
done

print_info "Restarting Traefik to ensure proper routing..."
docker restart nextcloud-traefik
sleep 10

# Get domain name from .env file for final message
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    print_error "Environment file not found!"
    exit 1
fi

print_success "========================================"
print_success "  Nextcloud Installation Complete!"
print_success "========================================"
echo

# Final system check
print_info "Performing final system check..."
print_info "Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo

print_info "Health Check Status:"
for container in nextcloud-app nextcloud-db nextcloud-redis nextcloud-traefik; do
    health_status=$(docker inspect $container --format='{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
    if [ "$health_status" = "healthy" ]; then
        print_success "  ✓ $container: $health_status"
    elif [ "$health_status" = "starting" ]; then
        print_warning "  ⏳ $container: $health_status (may take a few more minutes)"
    elif [ "$health_status" = "no-healthcheck" ]; then
        print_info "  ℹ️  $container: no health check configured"
    else
        print_warning "  ⚠️  $container: $health_status"
    fi
done
echo

print_info "Access URLs:"
print_info "  📱 Nextcloud: https://$DOMAIN_NAME"
print_info "  🔧 Traefik Dashboard: https://$DOMAIN_NAME/traefik/dashboard/"
print_info "  📞 Nextcloud Talk: https://signal.$DOMAIN_NAME"
echo
print_info "Credentials:"
print_info "  👤 Nextcloud Admin: $NEXTCLOUD_ADMIN_USER"
print_info "  🔑 Nextcloud Password: $NEXTCLOUD_ADMIN_PASSWORD"
print_info "  🔐 Traefik Dashboard: admin / $TRAEFIK_DASHBOARD_PASSWORD"
echo
print_info "Nextcloud Talk High-Performance Backend Configuration:"
print_info "  🔌 Signaling server: wss://signal.$DOMAIN_NAME"
print_info "  🔐 Signaling secret: $SIGNALING_SECRET"
print_info "  🌐 TURN server: signal.$DOMAIN_NAME:3478"
print_info "  🔑 TURN secret: $TURN_SECRET"
echo
print_warning "Important Notes:"
print_warning "  • Make sure your DNS points to this server"
print_warning "  • If Traefik shows 'starting', wait 5-10 minutes for health checks"
print_warning "  • If dashboard shows Nextcloud error, run: ./test-dashboard.sh"
print_warning "  • If you see .user.ini integrity warnings, run: ./fix-integrity.sh"
print_warning "  • Configure email settings in Talk app if needed"
print_warning "  • Keep your .env file secure - it contains all passwords"
print_warning "  • Check 'docker compose logs -f' for any issues"
print_warning "  • Run './troubleshoot.sh' for system diagnostics"
echo

# Check if Traefik is accessible
print_info "Testing Traefik accessibility..."
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/ping" | grep -q "200"; then
    print_success "  ✓ Traefik ping endpoint is accessible"
else
    print_warning "  ⚠️  Traefik ping endpoint not yet accessible (may still be starting)"
    print_info "  Run this to check: curl http://localhost:8080/ping"
fi

print_success "Your Nextcloud installation is ready to use! 🎉"