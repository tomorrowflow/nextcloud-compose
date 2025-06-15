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
print_header() { echo -e "${BLUE}=== $1 ===${NC}"; }

# Check if .env file exists
if [ ! -f ".env" ]; then
    print_error ".env file not found"
    exit 1
fi

# Load environment variables
source .env

print_header "Traefik Dashboard Routing Test"
echo "Domain: $DOMAIN_NAME"
echo

# Test 1: Check if Traefik container is running
print_info "Test 1: Checking Traefik container status..."
if docker ps --format "{{.Names}}" | grep -q "^nextcloud-traefik$"; then
    print_success "✓ Traefik container is running"
else
    print_error "✗ Traefik container is not running"
    exit 1
fi

# Test 2: Check internal ping endpoint
print_info "Test 2: Testing Traefik ping endpoint..."
if docker exec nextcloud-traefik wget -qO- http://localhost:8080/ping 2>/dev/null | grep -q "OK"; then
    print_success "✓ Traefik ping endpoint working"
else
    print_error "✗ Traefik ping endpoint not working"
    print_info "Traefik may not be ready yet"
fi

# Test 3: Test dashboard routing without authentication
print_info "Test 3: Testing dashboard routing (expecting 401 Unauthorized)..."
dashboard_response=$(curl -s -w "%{http_code}" -H "Host: $DOMAIN_NAME" "http://localhost/dashboard/" -o /dev/null 2>/dev/null || echo "000")

case $dashboard_response in
    "401")
        print_success "✓ Dashboard routing working correctly (401 = auth required)"
        ;;
    "200")
        print_warning "⚠️  Dashboard accessible without auth (security issue)"
        ;;
    "404")
        print_error "✗ Dashboard not found (404) - request going to Nextcloud"
        print_info "This indicates a routing priority issue"
        ;;
    "000")
        print_error "✗ Could not connect to dashboard"
        ;;
    *)
        print_warning "⚠️  Dashboard returned HTTP $dashboard_response"
        ;;
esac

# Test 4: Test API endpoint routing
print_info "Test 4: Testing API endpoint routing..."
api_response=$(curl -s -w "%{http_code}" -H "Host: $DOMAIN_NAME" "http://localhost/traefik/api/overview" -o /dev/null 2>/dev/null || echo "000")

case $api_response in
    "401")
        print_success "✓ API routing working correctly (401 = auth required)"
        ;;
    "404")
        print_error "✗ API not found (404) - routing issue"
        ;;
    *)
        print_warning "⚠️  API returned HTTP $api_response"
        ;;
esac

# Test 5: Check route priorities in logs
print_info "Test 5: Checking route priorities..."
traefik_priority=$(docker logs nextcloud-traefik 2>&1 | grep -i "traefik-secure.*priority" | tail -1)
nextcloud_priority=$(docker logs nextcloud-traefik 2>&1 | grep -i "nextcloud.*priority" | tail -1)

if [ -n "$traefik_priority" ]; then
    echo "   Traefik route: $(echo $traefik_priority | grep -o 'priority=[0-9]*')"
fi
if [ -n "$nextcloud_priority" ]; then
    echo "   Nextcloud route: $(echo $nextcloud_priority | grep -o 'priority=[0-9]*')"
fi

# Test 6: Check middleware configuration
print_info "Test 6: Checking middleware configuration..."
if docker exec nextcloud-traefik test -f /config/dynamic.yml; then
    if docker exec nextcloud-traefik grep -q "traefik-stripprefix" /config/dynamic.yml; then
        print_success "✓ Strip prefix middleware configured"
    else
        print_error "✗ Strip prefix middleware missing"
    fi
    
    if docker exec nextcloud-traefik grep -q "user-auth" /config/dynamic.yml; then
        print_success "✓ Authentication middleware configured"
    else
        print_error "✗ Authentication middleware missing"
    fi
else
    print_error "✗ dynamic.yml not found"
fi

# Test 7: Test with authentication (if credentials provided)
print_info "Test 7: Testing with authentication..."
if [ -n "$TRAEFIK_DASHBOARD_PASSWORD" ]; then
    auth_response=$(curl -s -w "%{http_code}" -u "admin:$TRAEFIK_DASHBOARD_PASSWORD" -H "Host: $DOMAIN_NAME" "http://localhost/dashboard/" -o /dev/null 2>/dev/null || echo "000")
    
    case $auth_response in
        "200")
            print_success "✓ Dashboard accessible with authentication"
            ;;
        "401")
            print_error "✗ Authentication failed (wrong password?)"
            ;;
        "404")
            print_error "✗ Still getting 404 even with auth (routing issue)"
            ;;
        *)
            print_warning "⚠️  Dashboard with auth returned HTTP $auth_response"
            ;;
    esac
else
    print_warning "⚠️  TRAEFIK_DASHBOARD_PASSWORD not set in .env"
fi

# Summary and recommendations
echo
print_header "Summary and Recommendations"

if [ "$dashboard_response" = "404" ] || [ "$api_response" = "404" ]; then
    print_error "ISSUE DETECTED: Dashboard requests are being routed to Nextcloud"
    echo
    echo "This happens when:"
    echo "1. Route priorities are incorrect"
    echo "2. Traefik labels are not properly configured"
    echo "3. Middleware is not working correctly"
    echo
    echo "Recommended fixes:"
    echo "1. Restart Traefik: docker restart nextcloud-traefik"
    echo "2. Check router configuration: docker-compose logs traefik | grep router"
    echo "3. Verify priorities: Higher numbers = higher priority in Traefik"
    echo "4. Test manually: curl -H 'Host: $DOMAIN_NAME' http://localhost/dashboard/"
    
elif [ "$dashboard_response" = "401" ] && [ "$api_response" = "401" ]; then
    print_success "✅ Dashboard routing is working correctly!"
    echo
    echo "Access your dashboard at:"
    echo "  https://$DOMAIN_NAME/dashboard/"
    echo "  Username: admin"
    echo "  Password: (from your .env file)"
    
else
    print_warning "⚠️  Dashboard routing may have issues"
    echo
    echo "Check the test results above and:"
    echo "1. Ensure Traefik container is healthy"
    echo "2. Verify configuration files exist"
    echo "3. Check recent logs: docker-compose logs traefik"
fi

echo
print_info "For more detailed troubleshooting, run: ./troubleshoot.sh"