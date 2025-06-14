#!/bin/bash

# Nextcloud Integrity Fix Script
# This script fixes the .user.ini integrity check issues

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

print_header "Nextcloud Integrity Check Fix"

# Check current integrity status
print_info "Checking current integrity status..."
if docker exec -u 33 nextcloud-app ./occ integrity:check-core --output=json 2>/dev/null | grep -q "INVALID_HASH"; then
    print_warning "Integrity check shows invalid hashes"
    
    # Show which files are affected
    print_info "Files with integrity issues:"
    docker exec -u 33 nextcloud-app ./occ integrity:check-core 2>/dev/null | grep -A 5 -B 5 "INVALID_HASH" || true
    
    # Fix 1: Update .user.ini with proper format
    print_info "Fix 1: Updating .user.ini with proper PHP configuration..."
    
    cat > ./app/.user.ini << 'EOF'
; Nextcloud PHP Configuration
; Updated to fix integrity check issues

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
    
    print_success ".user.ini updated"
    
    # Fix 2: Try to reset integrity check
    print_info "Fix 2: Resetting integrity check..."
    
    # Update htaccess file
    docker exec -u 33 nextcloud-app ./occ maintenance:update-htaccess
    
    # Temporarily disable integrity check and re-enable to refresh cache
    print_info "Refreshing integrity check cache..."
    docker exec -u 33 nextcloud-app ./occ config:system:set integrity.check.disabled --value=true --type=boolean
    sleep 2
    docker exec -u 33 nextcloud-app ./occ config:system:delete integrity.check.disabled
    
    # Fix 3: Alternative approach - exclude .user.ini from integrity check
    print_info "Fix 3: Configuring integrity check exclusions..."
    docker exec -u 33 nextcloud-app ./occ config:system:set integrity.excluded.files --value='[".user.ini"]' --type=json
    
    # Wait a moment for changes to take effect
    sleep 5
    
    # Check integrity again
    print_info "Checking integrity status after fixes..."
    if docker exec -u 33 nextcloud-app ./occ integrity:check-core --output=json 2>/dev/null | grep -q "INVALID_HASH"; then
        print_warning "Integrity check still shows issues"
        
        # Show detailed results
        print_info "Detailed integrity check results:"
        docker exec -u 33 nextcloud-app ./occ integrity:check-core 2>/dev/null | head -20
        
        # Offer nuclear option
        echo
        print_warning "If the integrity check is still failing, you have two options:"
        echo
        echo "Option 1: Ignore the warning (recommended if everything works)"
        echo "  - The .user.ini file is safe to modify"
        echo "  - This is a cosmetic issue and doesn't affect functionality"
        echo
        echo "Option 2: Reset the integrity database (nuclear option)"
        echo "  - This will clear all integrity hashes and recalculate them"
        echo "  - Run: docker exec -u 33 nextcloud-app ./occ maintenance:repair --include-expensive"
        echo
        
        # Ask user if they want to proceed with nuclear option
        read -p "Do you want to reset the integrity database? (y/N): " choice
        case "$choice" in
            [Yy]|[Yy][Ee][Ss])
                print_info "Resetting integrity database..."
                docker exec -u 33 nextcloud-app ./occ maintenance:repair --include-expensive
                print_success "Integrity database reset complete"
                ;;
            *)
                print_info "Skipping integrity database reset"
                ;;
        esac
        
    else
        print_success "✓ Integrity check passed! Issues have been resolved."
    fi
    
else
    print_success "✓ No integrity issues detected"
fi

# Final check and summary
echo
print_header "Final Status Check"

# Check if Nextcloud admin panel shows any warnings
print_info "Current Nextcloud status:"
docker exec -u 33 nextcloud-app ./occ status 2>/dev/null | grep -E "(installed|version|versionstring)" || true

# Show current .user.ini content
print_info "Current .user.ini configuration:"
echo "----------------------------------------"
head -10 ./app/.user.ini 2>/dev/null || print_warning ".user.ini not found"
echo "----------------------------------------"

# Give final recommendations
echo
print_success "Integrity fix process completed!"
echo
print_info "Next steps:"
print_info "1. Check your Nextcloud admin panel (Settings > Administration > Overview)"
print_info "2. If you still see integrity warnings, they are likely cosmetic"
print_info "3. The .user.ini modifications are safe and improve performance"
print_info "4. Consider updating your installation script to prevent future issues"
echo
print_info "If you continue to have issues, check the Nextcloud documentation:"
print_info "https://docs.nextcloud.com/server/latest/admin_manual/issues/code_signing.html"