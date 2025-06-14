# Nextcloud Docker Installation with Traefik

A comprehensive, hands-free Nextcloud installation using Docker Compose with Traefik as reverse proxy, including automatic updates and health monitoring.

## 🚀 Features

- **Automated Installation**: Single script setup with interactive configuration
- **SSL Certificates**: Automatic Let's Encrypt certificate generation and renewal
- **Reverse Proxy**: Traefik for routing and load balancing
- **Auto-healing**: Automatically restarts failed containers
- **Auto-updates**: Watchtower keeps containers updated with latest images
- **High Performance**: Redis caching and optimized PHP settings
- **Video Calls**: Nextcloud Talk with high-performance backend
- **Security**: Strong passwords, secure headers, and proper permissions

## 📋 Prerequisites

- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher
- **Domain Name**: Pointing to your server's IP address
- **Ports**: 80, 443, 3478, 8080, 8081 available

## 🛠️ Quick Installation

1. **Clone or download the files:**
   ```bash
   git clone <repository-url>
   cd nextcloud-docker
   ```

2. **Make the installation script executable:**
   ```bash
   chmod +x install.sh
   ```

3. **Run the installation:**
   ```bash
   ./install.sh
   ```

4. **Follow the interactive prompts** to configure:
   - Domain name
   - Let's Encrypt email
   - Traefik dashboard password
   - Database passwords
   - Nextcloud admin credentials

5. **Wait for installation to complete** (5-10 minutes)

## 🌐 Access Points

After installation, you can access:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Nextcloud** | `https://your-domain.com` | Check `.env` file |
| **Traefik Dashboard** | `https://your-domain.com/traefik/dashboard/` | `admin` / (from `.env`) |
| **Nextcloud Talk** | `https://signal.your-domain.com` | Same as Nextcloud |

## 📁 Directory Structure

```
nextcloud-docker/
├── docker-compose.yml          # Main Docker Compose configuration
├── install.sh                  # Installation script
├── .env                        # Environment variables (created by installer)
├── traefik/
│   ├── traefik.yml            # Traefik static configuration
│   ├── config/
│   │   └── dynamic.yml        # Traefik dynamic configuration
│   ├── letsencrypt/           # SSL certificates storage
│   └── acme.json              # Let's Encrypt account info
├── scripts/
│   ├── nextcloud-init.sh      # Nextcloud initialization script
│   └── watchtower-hooks/
│       └── nextcloud-post-update.sh  # Post-update hook
├── app/                       # Nextcloud application files
├── data/                      # Nextcloud user data
└── database/                  # MySQL/MariaDB data
```

## 🔧 Configuration

### Environment Variables

All configuration is stored in the `.env` file created during installation:

```bash
DOMAIN_NAME=your-domain.com
LETSENCRYPT_EMAIL=admin@your-domain.com
TRAEFIK_DASHBOARD_PASSWORD=secure-password
MYSQL_ROOT_PASSWORD=secure-password
MYSQL_PASSWORD=secure-password
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=secure-password
# ... and more
```

### Watchtower Email Notifications (Optional)

To receive email notifications about updates, uncomment and configure these variables in `.env`:

```bash
WATCHTOWER_EMAIL_FROM=watchtower@your-domain.com
WATCHTOWER_EMAIL_TO=admin@your-domain.com
WATCHTOWER_EMAIL_SERVER=smtp.your-domain.com
WATCHTOWER_EMAIL_PORT=587
WATCHTOWER_EMAIL_USER=watchtower@your-domain.com
WATCHTOWER_EMAIL_PASSWORD=your-email-password
```

## 🏥 Health Monitoring

The installation includes comprehensive health monitoring:

- **MariaDB**: Database connectivity and initialization
- **Redis**: Cache service availability
- **Nextcloud**: Application readiness via `/status.php`
- **Traefik**: Reverse proxy health via `/ping`
- **Autoheal**: Monitors and restarts unhealthy containers

## 🔄 Automatic Updates

**Watchtower** automatically updates containers daily at 4 AM:

- Only updates containers with the `watchtower.enable=true` label
- Uses rolling updates to minimize downtime
- Automatically reinstalls PHP extensions (like bz2) after Nextcloud updates
- Sends email notifications about updates (if configured)

### Manual Updates

To update immediately:
```bash
docker-compose pull
docker-compose up -d
```

## 🔒 Security Features

- **SSL/TLS**: Automatic Let's Encrypt certificates with strong cipher suites
- **Security Headers**: HSTS, CSP, and other security headers
- **Access Control**: Basic authentication for Traefik dashboard
- **Network Isolation**: Services run on isolated Docker networks
- **Regular Updates**: Automatic security updates via Watchtower

## 📞 Nextcloud Talk Configuration

The installation includes a high-performance backend for Nextcloud Talk:

1. **Enable Talk app** (done automatically by installer)
2. **Configure High-Performance Backend** in Nextcloud admin settings:
   - **Signaling server**: `wss://signal.your-domain.com`
   - **Signaling secret**: (found in `.env` file)
   - **TURN server**: `signal.your-domain.com:3478`
   - **TURN secret**: (found in `.env` file)

## 🚨 Troubleshooting

### Quick Diagnostic

Run the built-in troubleshooting scripts:
```bash
# General system check
./troubleshoot.sh

# Specific dashboard routing test
./test-dashboard.sh
```

The troubleshooting script checks:
- Container status and health
- Network connectivity
- Traefik configuration
- File permissions
- Port availability
- Recent error logs

The dashboard test script specifically checks:
- Traefik dashboard routing
- Authentication middleware
- Route priorities
- API endpoint access

### Check Container Status
```bash
docker-compose ps
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f nextcloud-app
docker-compose logs -f traefik
```

### Restart Services
```bash
# Restart all
docker-compose restart

# Restart specific service
docker-compose restart nextcloud-app
```

### Common Issues

1. **Port 80/443 already in use**:
   ```bash
   sudo netstat -tlnp | grep :80
   sudo netstat -tlnp | grep :443
   ```

2. **Traefik dashboard shows Nextcloud error instead of dashboard**:
   ```bash
   # Test dashboard routing
   ./test-dashboard.sh
   
   # Check route priorities (higher number = higher priority)
   docker-compose logs traefik | grep -i "router.*priority"
   
   # Restart Traefik to reload routes
   docker restart nextcloud-traefik
   
   # Test routing manually
   curl -H "Host: your-domain.com" http://localhost/traefik/dashboard/
   # Should return 401 (auth required), not 404
   
   # Check middleware configuration
   docker exec nextcloud-traefik cat /config/dynamic.yml | grep -A 5 traefik-stripprefix
   ```

3. **Traefik container stuck in "starting" status**:
   ```bash
   # Check Traefik health status
   docker inspect nextcloud-traefik --format='{{.State.Health.Status}}'
   
   # Check Traefik logs
   docker logs nextcloud-traefik
   
   # Check if ping endpoint is accessible
   docker exec nextcloud-traefik wget -qO- http://localhost:8080/ping
   
   # Restart Traefik if needed
   docker restart nextcloud-traefik
   ```

3. **SSL certificate issues**:
   - Check DNS is pointing to your server
   - Verify ports 80/443 are accessible from internet
   - Check Let's Encrypt rate limits
   - Verify acme.json permissions: `ls -la traefik/acme.json` (should be 600)

4. **Database connection issues**:
   - Wait for full initialization (can take 5-10 minutes)
   - Check MySQL logs: `docker-compose logs -f nextcloud-db`

6. **Traefik dashboard not accessible**:
   ```bash
   # Verify Traefik is routing correctly
   curl -H "Host: your-domain.com" http://localhost/traefik/dashboard/
   
   # Check dynamic configuration
   docker exec nextcloud-traefik cat /config/dynamic.yml
   
   # Verify password hash in dynamic.yml
   docker exec nextcloud-traefik ls -la /config/
   ```

### Traefik Troubleshooting

If Traefik remains stuck in "starting" status:

1. **Check the health check manually**:
   ```bash
   docker exec nextcloud-traefik wget --spider http://localhost:8080/ping
   ```

2. **Disable health checks temporarily** (for debugging):
   ```bash
   # Edit docker-compose.yml and comment out the healthcheck section
   # Then restart: docker-compose up -d traefik
   ```

3. **Check for configuration issues**:
   ```bash
   # Validate Traefik configuration
   docker exec nextcloud-traefik traefik version
   docker logs nextcloud-traefik | grep -i error
   ```

4. **Reset Traefik completely**:
   ```bash
   docker-compose stop traefik
   docker-compose rm -f traefik
   docker-compose up -d traefik
   ```

## 🔧 Maintenance

### Backup
```bash
# Stop services
docker-compose down

# Backup data directories
tar -czf nextcloud-backup-$(date +%Y%m%d).tar.gz \
  app/ data/ database/ traefik/ .env

# Start services
docker-compose up -d
```

### Update Configuration
1. Edit `.env` file
2. Restart services: `docker-compose up -d`

### Clean Up
```bash
# Remove unused images
docker image prune -a

# Remove unused volumes (be careful!)
docker volume prune
```

## 📝 Support

For issues and questions:

1. Check the logs: `docker-compose logs -f`
2. Verify all services are healthy: `docker-compose ps`
3. Review Nextcloud admin panel for warnings
4. Check Traefik dashboard for routing issues

## 📄 License

This project is provided as-is for educational and production use. Please ensure you comply with the licenses of all included software components.

---

**Happy Cloud Computing! ☁️**