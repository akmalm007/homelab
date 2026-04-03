# Isolated Staging Database with phpMyAdmin

A fully isolated, secure staging database environment using Docker with nginx reverse proxy, HTTP Basic Auth, and SSL.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        HOST SERVER                          │
│  ┌─────────────────┐         ┌──────────────────────────┐   │
│  │   Nginx (host)  │────────▶│  phpMyAdmin (Docker)     │   │
│  │   - SSL         │  Proxy  │  - Internal network only │   │
│  │   - Basic Auth  │         │  - No external ports     │   │
│  └─────────────────┘         └───────────┬──────────────┘   │
│                                          │                  │
│                                          ▼                  │
│                             ┌──────────────────────────┐    │
│                             │   MySQL (Docker)         │    │
│                             │   - Private network only │    │
│                             │   - Fully isolated       │    │
│                             └──────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Security Features

- **Fully Isolated MySQL**: No ports exposed to host or internet
- **HTTP Basic Auth**: Additional layer before phpMyAdmin
- **SSL/TLS**: Encrypted connections
- **Rate Limiting**: 5 requests per minute per IP
- **Private Docker Network**: No external access
- **Strong Credentials**: Separate root and team user accounts

## Quick Start

### 1. Prerequisites

```bash
# Install required packages
sudo apt update
sudo apt install -y docker docker-compose apache2-utils mkcert

# Install mkcert CA
mkcert -install
```

### 2. Setup SSL Certificate

**For Homelab (mkcert - recommended):**
```bash
# Generate local certificate
cd ~/Homelab/services/database
mkcert phpmyadmin.local localhost 127.0.0.1 ::1 $(hostname -I | awk '{print $1}')

# Move certificates
mv phpmyadmin.local.pem nginx-config/cert.pem
mv phpmyadmin.local-key.pem nginx-config/cert-key.pem
```

**For Production (Let's Encrypt):**
```bash
# Get certificate
sudo certbot certonly --nginx -d phpmyadmin.yourdomain.com

# Update nginx-config/phpmyadmin.conf paths
```

### 3. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit with your passwords
nano .env
```

### 4. Setup Basic Auth

```bash
# Create htpasswd file (replace 'admin' with your username)
sudo htpasswd -c /etc/nginx/.htpasswd-phpmyadmin admin

# Add more users
sudo htpasswd /etc/nginx/.htpasswd-phpmyadmin team_member1
```

### 5. Configure Nginx

```bash
# Copy nginx configuration
sudo cp nginx-config/phpmyadmin.conf /etc/nginx/sites-available/

# Edit domain and certificate paths
sudo nano /etc/nginx/sites-available/phpmyadmin.conf

# Enable site
sudo ln -s /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 6. Start Services

```bash
# Start Docker containers
docker-compose up -d

# Verify
./scripts/health-check.sh
```

## Database Migration

### Export from Host MySQL

```bash
# Make script executable
chmod +x scripts/migrate.sh

# Run migration
./scripts/migrate.sh your_database_name
```

### Manual Import/Export

```bash
# Export from Docker MySQL
docker exec mysql-staging mysqldump -u root -p your_database > backups/export.sql

# Import to Docker MySQL
docker exec -i mysql-staging mysql -u root -p your_database < backups/export.sql
```

## Directory Structure

```
~/Homelab/services/database/
├── docker-compose.yml      # Main compose file
├── .env                    # Environment variables (create from .env.example)
├── .env.example            # Example environment file
├── README.md               # This file
├── backups/                # Database backups
├── init-scripts/           # SQL initialization scripts
├── nginx-config/           # Nginx configuration
│   ├── phpmyadmin.conf     # Nginx site config
│   ├── cert.pem            # SSL certificate (homelab)
│   └── cert-key.pem        # SSL private key (homelab)
└── scripts/                # Helper scripts
    ├── migrate.sh          # Host to Docker migration
    ├── setup.sh            # One-click setup
    ├── backup.sh           # Automated backups
    └── health-check.sh     # Health verification
```

## Access Information

- **URL**: https://phpmyadmin.local (homelab) or your domain
- **Basic Auth**: Your htpasswd username + password
- **MySQL Root**: root + password from .env
- **MySQL User**: staging_user + password from .env

## Maintenance

### Backup Automation

Add to crontab:
```bash
# Daily backup at 2 AM
0 2 * * * /home/$USER/Homelab/services/database/scripts/backup.sh >> /var/log/db-backup.log 2>&1
```

### Update Container

```bash
# Pull latest images
docker-compose pull

# Recreate containers
docker-compose up -d
```

### View Logs

```bash
# All containers
docker-compose logs -f

# Specific container
docker-compose logs -f mysql-staging
docker-compose logs -f phpmyadmin
```

## Troubleshooting

### Container won't start
```bash
docker-compose logs mysql-staging
docker-compose logs phpmyadmin
```

### Can't connect to phpMyAdmin
```bash
# Check if containers are running
docker-compose ps

# Check nginx configuration
sudo nginx -t

# Check nginx error logs
sudo tail -f /var/log/nginx/phpmyadmin-error.log
```

### Migration fails
```bash
# Check host MySQL connection
mysql -u root -p -e "SHOW DATABASES;"

# Check Docker MySQL connection
docker exec -it mysql-staging mysql -u root -p -e "SHOW DATABASES;"
```

## Security Checklist

- [ ] Strong passwords in .env file
- [ ] Basic Auth configured
- [ ] SSL certificates installed
- [ ] Firewall rules set (if exposing externally)
- [ ] Backups configured
- [ ] Host MySQL bind-address set to 127.0.0.1 (if keeping it)

## License

MIT - For homelab and testing purposes