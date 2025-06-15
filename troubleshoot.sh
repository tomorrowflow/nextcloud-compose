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

# Function to check container status
check_container_status() {
    print_header "Container Status Check"
    
    echo -e "\n${BLUE}Running Containers:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo -e "\n${BLUE}All Nextcloud Containers:${NC}"
    docker ps -a --filter "name=nextcloud" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
}

# Function to check health status
check_health_status() {
    print_header "Health Check Status"
    
    for container in nextcloud-app nextcloud-db nextcloud-redis nextcloud-traefik; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            health_status=$(docker inspect $container --format='{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
            if [ "$health_status" = "healthy" ]; then
                print_success "✓ $container: $health_status"
            elif [ "$health_status" = "starting" ]; then
                print_warning "⏳ $container: $health_status"
                echo "   Health check details:"
                docker inspect $container --format='{{range .State.Health.Log}}  {{.Output}}{{end}}' 2>/dev/null | tail -3
            elif [ "$health_status" = "unhealthy" ]; then
                print_error "✗ $container: $health_status"
                echo "   Health check details:"
                docker inspect $container --format='{{range .State.Health.Log}}  {{.Output}}{{end}}' 2>/dev/null | tail -3
            else
                print_info "ℹ️  $container: no health check configured"
            fi
        else
            print_error "✗ $container: not running"
        fi
    done
}

# Function to check network connectivity
check_network() {
    print_header "Network Connectivity Check"
    
    # Check if proxy network exists
    if docker network ls | grep -q "proxy"; then
        print_success "✓ Docker network 'proxy' exists"
        echo "   Network details:"
        docker network inspect proxy --format='  Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}'
    else
        print_error "✗ Docker network 'proxy' missing"
        echo "   Run: docker network create proxy --driver bridge --subnet=172.18.0.0/24 --gateway=172.18.0.1"
    fi
    
    # Check container network connections
    for container in nextcloud-app nextcloud-traefik; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            networks=$(docker inspect $container --format='{{range $net,$conf := .NetworkSettings.Networks}}{{$net}} {{end}}')
            if echo "$networks" | grep -q "proxy"; then
                print_success "✓ $container: connected to proxy network"
            else
                print_warning "⚠️  $container: not connected to proxy network ($networks)"
            fi
        fi
    done
}

# Function to check Traefik specific issues
check_traefik() {
    print_header "Traefik Diagnostic"
    
    if ! docker ps --format "{{.Names}}" | grep -q "^nextcloud-traefik$"; then
        print_error "✗ Traefik container is not running"
        return 1
    fi
    
    # Test ping endpoint
    if docker exec nextcloud-traefik wget -qO- http://localhost:8080/ping 2>/dev/null | grep -q "OK"; then
        print_success "✓ Traefik ping endpoint accessible"
    else
        print_error "✗ Traefik ping endpoint not accessible"
        echo "   Testing with netcat:"
        if docker exec nextcloud-traefik nc -z localhost 8080; then
            print_warning "   Port 8080 is open but ping endpoint failed"
        else
            print_error "   Port 8080 is not accessible"
        fi
    fi
    
    # Test dashboard routing
    print_info "Testing Traefik dashboard routing..."
    if [ -f ".env" ]; then
        source .env
        # Test internal dashboard access
        dashboard_response=$(curl -s -w "%{http_code}" -H "Host: $DOMAIN_NAME" "http://localhost/dashboard/" -o /dev/null 2>/dev/null || echo "000")
        if [ "$dashboard_response" = "401" ]; then
            print_success "✓ Dashboard routing working (401 = authentication required)"
        elif [ "$dashboard_response" = "200" ]; then
            print_warning "⚠️  Dashboard accessible without authentication"
        elif [ "$dashboard_response" = "404" ]; then
            print_error "✗ Dashboard not found (404) - routing issue"
            echo "   This suggests the request is going to Nextcloud instead of Traefik"
        else
            print_warning "⚠️  Dashboard returned HTTP $dashboard_response"
        fi
        
        # Test API endpoint
        api_response=$(curl -s -w "%{http_code}" -H "Host: $DOMAIN_NAME" "http://localhost/traefik/api/overview" -o /dev/null 2>/dev/null || echo "000")
        if [ "$api_response" = "401" ]; then
            print_success "✓ API routing working (401 = authentication required)"
        elif [ "$api_response" = "404" ]; then
            print_error "✗ API not found (404) - routing issue"
        else
            print_warning "⚠️  API returned HTTP $api_response"
        fi
    fi
    
    # Check route priorities
    print_info "Checking route priorities..."
    docker logs nextcloud-traefik 2>&1 | grep -i "router.*priority" | tail -3 | while read line; do
        echo "   $line"
    done
    
    # Check configuration files
    if docker exec nextcloud-traefik test -f /traefik.yml; then
        print_success "✓ traefik.yml configuration file exists"
    else
        print_error "✗ traefik.yml configuration file missing"
    fi
    
    if docker exec nextcloud-traefik test -f /config/dynamic.yml; then
        print_success "✓ dynamic.yml configuration file exists"
        # Test middleware configuration
        if docker exec nextcloud-traefik grep -q "traefik-stripprefix" /config/dynamic.yml; then
            print_success "✓ traefik-stripprefix middleware configured"
        else
            print_error "✗ traefik-stripprefix middleware missing"
        fi
    else
        print_error "✗ dynamic.yml configuration file missing"
    fi
    
    # Check recent logs for routing errors
    echo -e "\n${BLUE}Recent Traefik logs (routing-related):${NC}"
    docker logs nextcloud-traefik --tail 20 2>&1 | grep -E "(router|middleware|api|dashboard)" | tail -5 | while read line; do
        if echo "$line" | grep -qi "error"; then
            echo -e "  ${RED}$line${NC}"
        else
            echo "  $line"
        fi
    done
}

# Function to check file permissions
check_permissions() {
    print_header "File Permissions Check"
    
    # Check acme.json permissions
    if [ -f "traefik/acme.json" ]; then
        perms=$(stat -c "%a" traefik/acme.json)
        if [ "$perms" = "600" ]; then
            print_success "✓ traefik/acme.json has correct permissions (600)"
        else
            print_warning "⚠️  traefik/acme.json has permissions $perms (should be 600)"
            echo "   Fix with: chmod 600 traefik/acme.json"
        fi
    else
        print_warning "⚠️  traefik/acme.json not found"
        echo "   Create with: touch traefik/acme.json && chmod 600 traefik/acme.json"
    fi
    
    # Check .env permissions
    if [ -f ".env" ]; then
        perms=$(stat -c "%a" .env)
        if [ "$perms" = "600" ]; then
            print_success "✓ .env has correct permissions (600)"
        else
            print_warning "⚠️  .env has permissions $perms (should be 600)"
            echo "   Fix with: chmod 600 .env"
        fi
    else
        print_error "✗ .env file not found"
    fi
}

# Function to check port availability
check_ports() {
    print_header "Port Availability Check"
    
    for port in 80 443 3478 8080 8081; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            process=$(netstat -tulnp 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
            if echo "$process" | grep -q "docker"; then
                print_success "✓ Port $port: used by Docker (expected)"
            else
                print_warning "⚠️  Port $port: used by $process"
            fi
        else
            print_info "ℹ️  Port $port: available"
        fi
    done
}

# Function to test connectivity
test_connectivity() {
    print_header "Connectivity Test"
    
    # Test internal connectivity
    if docker exec nextcloud-app curl -s -o /dev/null -w "%{http_code}" http://localhost:80/status.php | grep -q "200"; then
        print_success "✓ Nextcloud internal connectivity working"
    else
        print_warning "⚠️  Nextcloud internal connectivity issues"
    fi
    
    # Test Traefik proxy
    if [ -f ".env" ]; then
        source .env
        if curl -s -H "Host: $DOMAIN_NAME" http://localhost/status.php 2>/dev/null | grep -q "installed"; then
            print_success "✓ Traefik proxy routing working"
        else
            print_warning "⚠️  Traefik proxy routing issues"
            echo "   Check if DNS points to this server"
        fi
    fi
}

# Function to show recent logs
show_logs() {
    print_header "Recent Container Logs"
    
    for container in nextcloud-app nextcloud-traefik nextcloud-db; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            echo -e "\n${BLUE}=== $container logs (last 5 lines) ===${NC}"
            docker logs $container --tail 5 2>&1 | while read line; do
                if echo "$line" | grep -qi "error\|fatal\|critical"; then
                    echo -e "${RED}$line${NC}"
                elif echo "$line" | grep -qi "warning\|warn"; then
                    echo -e "${YELLOW}$line${NC}"
                else
                    echo "$line"
                fi
            done
        fi
    done
}

# Function to suggest fixes
suggest_fixes() {
    print_header "Common Fixes"
    
    echo -e "${BLUE}If containers are not healthy:${NC}"
    echo "  docker-compose restart"
    echo "  docker-compose down && docker-compose up -d"
    echo
    echo -e "${BLUE}If Traefik is stuck in 'starting':${NC}"
    echo "  docker restart nextcloud-traefik"
    echo "  docker exec nextcloud-traefik wget -qO- http://localhost:8080/ping"
    echo
    echo -e "${BLUE}If Traefik dashboard shows Nextcloud instead:${NC}"
    echo "  # Check route priorities"
    echo "  docker-compose logs traefik | grep -i router"
    echo "  # Restart Traefik to reload routes"
    echo "  docker restart nextcloud-traefik"
    echo "  # Test routing manually"
    echo "  curl -H 'Host: your-domain.com' http://localhost/dashboard/"
    echo "  # Check middleware configuration"
    echo "  docker exec nextcloud-traefik cat /config/dynamic.yml"
    echo
    echo -e "${BLUE}If SSL certificates are not working:${NC}"
    echo "  Check DNS: nslookup your-domain.com"
    echo "  Check firewall: sudo ufw status"
    echo "  Reset certificates: rm traefik/acme.json && touch traefik/acme.json && chmod 600 traefik/acme.json"
    echo
    echo -e "${BLUE}If database connection fails:${NC}"
    echo "  docker-compose logs nextcloud-db"
    echo "  docker exec nextcloud-db mysql -u root -p -e 'SHOW DATABASES;'"
    echo
    echo -e "${BLUE}For complete reset:${NC}"
    echo "  docker-compose down"
    echo "  docker volume prune  # CAUTION: This removes all data!"
    echo "  ./install.sh"
    echo
    echo -e "${BLUE}Debug Traefik routing:${NC}"
    echo "  # Enable debug mode in traefik.yml"
    echo "  # log: level: DEBUG"
    echo "  # Then restart and check logs"
    echo "  docker-compose restart traefik"
    echo "  docker-compose logs -f traefik"
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
    check_network
    echo
    check_traefik
    echo
    check_permissions
    echo
    check_ports
    echo
    test_connectivity
    echo
    show_logs
    echo
    suggest_fixes
    
    echo
    print_info "Troubleshooting complete!"
    print_info "For more detailed logs, run: docker-compose logs -f [service-name]"
}

# Run main function
main "$@"