# Nextcloud Docker Compose Setup

A comprehensive, hands-free Nextcloud installation using Docker Compose with Traefik as reverse proxy, including automatic updates and health monitoring.

## ✨ Features

- **Automated Installation**: Single script setup with interactive configuration
- **SSL Certificates**: Automatic Let's Encrypt certificate generation and renewal
- **Reverse Proxy**: Traefik for routing and load balancing
- **Auto-healing**: Automatically restarts failed containers
- **Auto-updates**: Watchtower keeps containers updated with latest images
- **High Performance**: Redis caching, OPcache, and optimized PHP settings via **official pre-installation hooks**
- **Video Calls**: Nextcloud Talk with high-performance backend
- **Security**: Strong passwords, secure headers, and proper permissions
- **Integrity Check Compliance**: PHP configuration via Nextcloud pre-installation hooks

## 🛠️ Requirements

- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher
- **Domain Name**: Pointing to your server's IP address
- **Ports**: 80, 443, 3478, 8080, 8081 available (only 80/tcp, 443/tcp, 3478 tcp/udp world accessable)

## 🚀 Quick Start

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

4. **Follow the interactive prompts to configure:**
   - Domain name
   - Let's Encrypt email
   - Traefik dashboard password
   - Database passwords
   - Nextcloud admin credentials

5. **Start the services:**
   ```bash
   docker-compose up -d
   ```

6. **Wait for installation to complete (5-10 minutes)**

After installation, you can access:

| Service | URL | Credentials |
|---------|-----|-------------|
| Nextcloud | https://your-domain.com | Check .env file |
| Traefik Dashboard | https://your-domain.com/dashboard/ | admin / (from .env) |
| Nextcloud Talk | https://signal.your-domain.com | Same as Nextcloud |

## 📁 Directory Structure

```
nextcloud-docker/
├── docker-compose.yml               # Main Docker Compose configuration
├── install.sh                       # Installation script
├── .env                             # Environment variables (created by installer)
├── .env.example                     # Example environment variables (copy to .env and adjust to your needs)
├── fix-integrity.sh                 # Change handling of .user.ini to exclude from integrity check
├── troubleshoot.sh                  # Nextcloud docker troubleshooting
├── test-dashboard.sh                # Traefik dashboard testing
├── traefik/
│   ├── traefik.yml.example          # Traefik static configuration
│   ├── config
│   │   └── dynamic.yml.example      # Traefik dynamic configuration
│   ├── letsencrypt/                 # SSL certificates storage
│   └── acme.json                    # Let's Encrypt account info
├── hooks/
│   └── pre-installation/            # Official Nextcloud pre-installation hooks
│       └── 01-configure-php.sh      # PHP performance configuration
├── scripts/
│   ├── nextcloud-init.sh            # Nextcloud initialization script (legacy)
│   └── watchtower-hooks/
│       └── nextcloud-post-update.sh # Post-update hook for watchtower
├── app/                             # Nextcloud application files
├── data/                            # Nextcloud user data
└── database/                        # MySQL/MariaDB data
```

## ⚙️ Configuration

All configuration is stored in the `.env` file created during installation:

```env
DOMAIN_NAME=your-domain.com
LETSENCRYPT_EMAIL=admin@your-domain.com
TRAEFIK_DASHBOARD_PASSWORD=secure-password
MYSQL_ROOT_PASSWORD=secure-password
MYSQL_PASSWORD=secure-password
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=secure-password
# ... and more
```

## 🏎️ Performance Optimization

### ✅ Pre-installation Hooks Method

PHP settings are configured via **Nextcloud pre-installation hooks** to ensure optimal performance without integrity check conflicts:

```bash
# Pre-installation hooks are located in:
./hooks/pre-installation/01-configure-php.sh    # PHP performance settings
```

**Key optimizations applied:**
- File upload limits: 16GB upload/post size
- Memory optimization: 2GB PHP memory limit  
- Execution time: 3600 seconds for large operations
- OPcache tuning: JIT enabled, 128MB cache, 10000 files
- Session security: HTTPOnly, Secure, SameSite cookies

## 🛠️ Customizing PHP Settings

If you need to modify PHP settings, you can:

1. **Edit pre-installation hooks (recommended):**
   ```bash
   # Edit ./hooks/pre-installation/01-configure-php.sh
   # Restart containers:
   docker-compose down && docker-compose up -d
   ```

2. **Volume-mount custom PHP configuration: (not tested!)**
   ```yaml
   volumes:
     - ./custom-php.ini:/usr/local/etc/php/conf.d/99-custom.ini:ro
   ```

## 📧 Email Notifications

To receive email notifications about updates, uncomment and configure these variables in `.env`:

```env
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

Watchtower automatically updates containers daily at 4 AM:

- Only updates containers with the `watchtower.enable=true` label
- Uses rolling updates to minimize downtime
- Automatically reinstalls PHP extensions (like bz2) after Nextcloud updates
- Sends email notifications about updates (if configured)

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

1. Enable Talk app (done automatically by installer)
2. Configure High-Performance Backend in Nextcloud admin settings:
   - **Signaling server**: `wss://signal.your-domain.com`
   - **Signaling secret**: (found in `.env` file)
   - **TURN server**: `signal.your-domain.com:3478`
   - **TURN secret**: (found in `.env` file)

## 🎨 Nextcloud Whiteboard Integration

The installation includes a collaborative whiteboard feature for Nextcloud:

### ✅ Features
- **Real-time collaboration**: Multiple users can draw simultaneously
- **Rich drawing tools**: Pens, shapes, text, colors, and more
- **Integration**: Seamlessly integrated with Nextcloud Files and Talk
- **Persistent storage**: Whiteboards are saved as Nextcloud files
- **Access control**: Uses Nextcloud's permission system

### 🔧 Configuration

The whiteboard service is automatically configured during installation:

1. **Enable Whiteboard app** (done automatically by installer)
2. **Access whiteboard** via Nextcloud Files or create new whiteboards directly
3. **Share whiteboards** using Nextcloud's sharing features

### 🌐 Access URLs

| Service | URL | Description |
|---------|-----|-------------|
| Whiteboard API | https://your-domain.com/whiteboard | Backend service endpoint |
| Whiteboard Files | https://your-domain.com/apps/files | Create and manage whiteboard files |

### 🔐 Security Configuration

The whiteboard uses JWT tokens for authentication. The secret is configured in your `.env` file:

```env
WHITEBOARD_JWT_SECRET=your-secure-jwt-secret-for-whiteboard
```

### 📊 Health Monitoring

The whiteboard service includes health checks:
- **Health endpoint**: `https://your-domain.com/whiteboard/health`
- **Monitoring**: Integrated with autoheal service
- **Logs**: Available via `docker-compose logs nextcloud-whiteboard`

### 🛠️ Troubleshooting

If whiteboard features are not working:

1. **Check service status:**
   ```bash
   docker-compose ps nextcloud-whiteboard
   ```

2. **View whiteboard logs:**
   ```bash
   docker-compose logs -f nextcloud-whiteboard
   ```

3. **Verify JWT configuration:**
   ```bash
   # Check if JWT secret is set
   grep WHITEBOARD_JWT_SECRET .env
   ```

4. **Restart whiteboard service:**
   ```bash
   docker-compose restart nextcloud-whiteboard
   ```

## 🔧 Troubleshooting

Run the built-in troubleshooting scripts:

```bash
# General system check
./troubleshoot.sh

# Specific dashboard routing test  
./test-dashboard.sh

# Fix Nextcloud integrity check issues (.user.ini)
./fix-userini-integrity.sh
```

### Common Issues

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

The integrity fix scripts intends to resolve (it seems a long discusses known issue, so this is no **SOLUTION**):
- `.user.ini` integrity check failures
- PHP configuration conflicts
- File checksum mismatches
- Alternative configuration methods

### Manual Commands

```bash
# Check container status
docker-compose ps

# View logs - all services
docker-compose logs -f

# View logs - specific service
docker-compose logs -f nextcloud-app
docker-compose logs -f traefik

# Restart services
docker-compose restart

# Restart specific service
docker-compose restart nextcloud-app
```

### Specific Issues

1. **Port 80/443 already in use:**
   ```bash
   sudo netstat -tlnp | grep :80
   sudo netstat -tlnp | grep :443
   ```

2. **Traefik dashboard shows Nextcloud error instead of dashboard:**
   ```bash
   # Test dashboard routing
   ./test-dashboard.sh
   
   # Check route priorities (higher number = higher priority)
   docker-compose logs traefik | grep -i "router.*priority"
   
   # Restart Traefik to reload routes
   docker restart nextcloud-traefik
   
   # Test routing manually
   curl -H "Host: your-domain.com" http://localhost/dashboard/
   # Should return 401 (auth required)
   
   # Check middleware configuration
   docker exec nextcloud-traefik cat /config/dynamic.yml | grep -A 5 traefik-stripprefix
   ```

3. **Traefik container stuck in "starting" status:**
   ```bash
   # Check Traefik health status
   docker inspect nextcloud-traefik --format='{{.State.Health.Status}}'
   
   # Check Traefik logs
   docker logs nextcloud-traefik
   
   # Check if ping endpoint is accessible from local server
   docker exec nextcloud-traefik wget -qO- http://localhost:8080/ping
   
   # Restart Traefik if needed
   docker restart nextcloud-traefik
   ```

4. **SSL certificate issues:**
   - Check DNS is pointing to your server
   - Verify ports 80/443 are accessible from internet
   - Check Let's Encrypt rate limits
   - Verify acme.json permissions: `ls -la traefik/acme.json` (should be 600)

5. **Database connection issues:**
   - Wait for full initialization (can take 5-10 minutes)
   - Check MySQL logs: `docker-compose logs -f nextcloud-db`

6. **Traefik dashboard not accessible:**
   ```bash
   # Verify Traefik is routing correctly
   curl -H "Host: your-domain.com" http://localhost/dashboard/
   
   # Check dynamic configuration
   docker exec nextcloud-traefik cat /config/dynamic.yml
   
   # Verify password hash in dynamic.yml
   docker exec nextcloud-traefik ls -la /config/
   ```

### Integrity Check Issues

**Note**: This issue occurs when PHP configuration files are modified after Nextcloud calculates its integrity hashes. The `.user.ini` file is safe to modify for performance tuning, but Nextcloud flags it as a security concern. 

**Our solution uses pre-installation hooks which apply configuration BEFORE Nextcloud initialization, this should prevent any integrity issues, but it does not!.**

If Traefik remains stuck in "starting" status:

1. **Check the health check manually:**
   ```bash
   docker exec nextcloud-traefik wget --spider http://localhost:8080/ping
   ```

2. **Disable health checks temporarily (for debugging):**
   ```bash
   # Edit docker-compose.yml and comment out the healthcheck section
   # Then restart:
   docker-compose up -d traefik
   ```

3. **Check for configuration issues:**
   ```bash
   # Validate Traefik configuration
   docker exec nextcloud-traefik traefik version
   docker logs nextcloud-traefik | grep -i error
   ```

4. **Reset Traefik completely:**
   ```bash
   docker-compose stop traefik
   docker-compose rm -f traefik
   docker-compose up -d traefik
   ```

## 🔄 Backup and Restore

```bash
# Stop services
docker-compose down

# Backup data directories
tar -czf nextcloud-backup-$(date +%Y%m%d).tar.gz \
  app/ data/ database/ traefik/ .env

# Start services
docker-compose up -d
```

## 🛠️ Maintenance

- Edit `.env` file
- Restart services: `docker-compose up -d`

```bash
# Clean up Docker
# Remove unused images
docker image prune -a

# Remove unused volumes (be careful!)
docker volume prune
```

## 📞 Support

For issues and questions:
- Check the logs: `docker-compose logs -f`
- Verify all services are healthy: `docker-compose ps`
- Review Nextcloud admin panel for warnings
- Check Traefik dashboard for routing issues

## 📄 License

This project is provided as-is for educational and production use. Please ensure you comply with the licenses of all included software components.

---

**Happy Nexcloud Using! ☁️**