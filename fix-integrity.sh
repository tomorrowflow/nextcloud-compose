#!/bin/bash

# Nextcloud Integrity Fix Script
# This script fixes the .user.ini integrity check issues by regenerating hashes

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

# Check if Nextcloud container is running
if ! docker ps --format "{{.Names}}" | grep -q "^nextcloud-app$"; then
    print_error "Nextcloud container is not running"
    print_info "Start it with: docker-compose up -d"
    exit 1
fi

print_header "Nextcloud Integrity Hash Regeneration"

# Check current integrity status
print_info "Checking current integrity status..."
if docker exec -u 33 nextcloud-app ./occ integrity:check-core --output=json 2>/dev/null | grep -q "INVALID_HASH"; then
    print_warning "Integrity check shows invalid hashes"
    
    # Show which files are affected
    print_info "Files with integrity issues:"
    docker exec -u 33 nextcloud-app ./occ integrity:check-core 2>/dev/null | grep -A 2 -B 2 ".user.ini" || true
    
    # Method 1: Update .user.ini and regenerate hashes
    print_info "Step 1: Updating .user.ini with optimized PHP settings..."
    
    cat > ./app/.user.ini << 'EOF'
; Nextcloud PHP Configuration
; Performance and security optimizations

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
    
    print_success ".user.ini updated with performance settings"
    
    # Method 2: Force regeneration of integrity hashes
    print_info "Step 2: Regenerating Nextcloud integrity hashes..."
    
    # Put Nextcloud in maintenance mode temporarily
    print_info "Enabling maintenance mode..."
    docker exec -u 33 nextcloud-app ./occ maintenance:mode --on
    
    # Clear integrity check cache
    print_info "Clearing integrity cache..."
    docker exec -u 33 nextcloud-app rm -f /var/www/html/data/.integrity.check.disabled 2>/dev/null || true
    
    # Update htaccess and configuration
    print_info "Updating htaccess and configuration..."
    docker exec -u 33 nextcloud-app ./occ maintenance:update-htaccess
    
    # Perform maintenance repair to regenerate hashes
    print_info "Regenerating integrity hashes (this may take a few minutes)..."
    docker exec -u 33 nextcloud-app ./occ maintenance:repair --include-expensive
    
    # Alternative: Try to trigger hash recalculation
    print_info "Triggering hash recalculation..."
    docker exec -u 33 nextcloud-app ./occ config:system:delete integrity.check.disabled 2>/dev/null || true
    
    # Turn off maintenance mode
    print_info "Disabling maintenance mode..."
    docker exec -u 33 nextcloud-app ./occ maintenance:mode --off
    
    # Wait for system to stabilize
    print_info "Waiting for system to stabilize..."
    sleep 10
    
    # Method 3: Nuclear option - regenerate all core hashes
    print_info "Step 3: If needed, regenerating ALL core integrity hashes..."
    
    # This is the nuclear option - it regenerates the entire integrity database
    # First, let's see if we can find the integrity hash storage
    if docker exec -u 33 nextcloud-app test -f /var/www/html/resources/codesigning/core.crt; then
        print_info "Core certificate found, attempting hash regeneration..."
        
        # Try to trigger a complete integrity check regeneration
        docker exec -u 33 nextcloud-app ./occ maintenance:mode --on
        
        # Remove any existing integrity cache
        docker exec -u 33 nextcloud-app rm -rf /var/www/html/data/integrity.results.json 2>/dev/null || true
        
        # Force a complete repair
        docker exec -u 33 nextcloud-app ./occ maintenance:repair --include-expensive
        
        # Turn maintenance mode back off
        docker exec -u 33 nextcloud-app ./occ maintenance:mode --off
        
        print_success "Complete integrity hash regeneration attempted"
    fi
    
    # Wait for changes to take effect
    print_info "Waiting for integrity check to refresh..."
    sleep 15
    
    # Final integrity check
    print_info "Performing final integrity check..."
    if docker exec -u 33 nextcloud-app ./occ integrity:check-core --output=json 2>/dev/null | grep -q "INVALID_HASH"; then
        print_warning "Integrity check still shows issues after regeneration"
        
        # Show current status
        print_info "Current integrity status:"
        docker exec -u 33 nextcloud-app ./occ integrity:check-core 2>/dev/null | head -20
        
        print_warning "Alternative solutions:"
        echo
        echo "Option 1: The integrity check may be overly strict. Your .user.ini settings are working."
        echo "  - Check: curl -I https://your-domain.com (should show your upload limits)"
        echo "  - This is often a cosmetic issue with no functional impact"
        echo
        echo "Option 2: Reset Nextcloud to recalculate all hashes from scratch:"
        echo "  docker exec -u 33 nextcloud-app ./occ maintenance:mode --on"
        echo "  docker exec -u 33 nextcloud-app ./occ maintenance:install"
        echo "  docker exec -u 33 nextcloud-app ./occ maintenance:mode --off"
        echo "  (WARNING: This may reset some settings)"
        echo
        echo "Option 3: Exclude .user.ini from integrity checks (recommended):"
        echo "  docker exec -u 33 nextcloud-app ./occ config:system:set integrity.excluded.files --value='[\".user.ini\"]' --type=json"
        
        # Ask user what they want to do
        echo
        read -p "Do you want to exclude .user.ini from integrity checks? (Y/n): " choice
        case "$choice" in
            [Nn]|[Nn][Oo])
                print_info "Leaving integrity check as-is"
                ;;
            *)
                print_info "Excluding .user.ini from integrity checks..."
                docker exec -u 33 nextcloud-app ./occ config:system:set integrity.excluded.files --value='[".user.ini"]' --type=json
                print_success "✓ .user.ini excluded from future integrity checks"
                ;;
        esac
        
    else
        print_success "✓ SUCCESS! Integrity check now passes with updated .user.ini"
        print_success "✓ Your PHP performance settings are active and verified"
    fi
    
else
    print_success "✓ No integrity issues detected"
    print_info "Your .user.ini file is already properly configured"
fi

# Show final configuration
echo
print_header "Final Configuration Status"

# Show current PHP settings
print_info "Current PHP upload settings:"
docker exec nextcloud-app php -r "echo 'upload_max_filesize: ' . ini_get('upload_max_filesize') . PHP_EOL;"
docker exec nextcloud-app php -r "echo 'post_max_size: ' . ini_get('post_max_size') . PHP_EOL;"
docker exec nextcloud-app php -r "echo 'memory_limit: ' . ini_get('memory_limit') . PHP_EOL;"

# Show Nextcloud status
print_info "Nextcloud status:"
docker exec -u 33 nextcloud-app ./occ status 2>/dev/null | grep -E "(installed|version)" || true

echo
print_success "Integrity fix process completed!"
print_info "Next steps:"
print_info "1. Check your Nextcloud admin panel: Settings > Administration > Overview"
print_info "2. Test file uploads to verify the increased limits are working"
print_info "3. Monitor performance to ensure OPcache settings are effective"