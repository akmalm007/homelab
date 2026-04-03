#!/bin/bash

# One-Click Setup Script for Staging Database
# Usage: ./scripts/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

log_info "Starting Staging Database Setup"
log_info "Project directory: $PROJECT_DIR"
echo ""

# Step 1: Check prerequisites
log_step "1/6 Checking prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed"
    exit 1
fi

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose is not installed"
    exit 1
fi

# Check mkcert
if ! command -v mkcert &> /dev/null; then
    log_warn "mkcert is not installed. Install with: sudo apt install mkcert"
fi

log_info "✓ Prerequisites met"

# Step 2: Create environment file
log_step "2/6 Setting up environment..."
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        log_warn "Created .env from .env.example"
        log_warn "Please edit .env with your passwords before continuing"
        nano .env
    else
        log_error ".env.example not found"
        exit 1
    fi
else
    log_info "✓ .env file exists"
fi

source .env

# Step 3: Generate SSL certificates
log_step "3/6 Setting up SSL certificates..."
if [ ! -f nginx-config/cert.pem ]; then
    if command -v mkcert &> /dev/null; then
        log_info "Generating certificates with mkcert..."
        cd nginx-config
        mkcert -install
        mkcert "$DOMAIN" localhost 127.0.0.1 ::1 $(hostname -I | awk '{print $1}')
        mv "${DOMAIN}.pem" cert.pem
        mv "${DOMAIN}-key.pem" cert-key.pem
        cd ..
        log_info "✓ SSL certificates generated"
    else
        log_warn "mkcert not found. Creating self-signed certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout nginx-config/cert-key.pem \
            -out nginx-config/cert.pem \
            -subj "/C=US/ST=State/L=City/O=Homelab/CN=$DOMAIN"
        log_info "✓ Self-signed certificate created"
    fi
else
    log_info "✓ SSL certificates already exist"
fi

# Step 4: Setup nginx
log_step "4/6 Configuring nginx..."

# Install apache2-utils if needed
if ! command -v htpasswd &> /dev/null; then
    log_info "Installing apache2-utils..."
    sudo apt-get update && sudo apt-get install -y apache2-utils
fi

# Create htpasswd if not exists
if [ ! -f /etc/nginx/.htpasswd-phpmyadmin ]; then
    log_warn "Creating htpasswd file..."
    read -p "Enter username for Basic Auth: " USERNAME
    sudo htpasswd -c /etc/nginx/.htpasswd-phpmyadmin "$USERNAME"
    log_info "✓ Basic Auth configured"
else
    log_info "✓ htpasswd already exists"
fi

# Check nginx config
if [ -f /etc/nginx/sites-available/phpmyadmin.conf ]; then
    log_info "✓ Nginx config already exists"
else
    log_warn "Please manually copy nginx-config/phpmyadmin.conf to /etc/nginx/sites-available/"
    log_warn "Then run: sudo ln -s /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/"
fi

# Step 5: Start Docker containers
log_step "5/6 Starting Docker containers..."
docker-compose up -d

# Wait for MySQL to be ready
log_info "Waiting for MySQL to be ready..."
RETRIES=60
COUNT=0
while [ $COUNT -lt $RETRIES ]; do
    if docker exec mysql-staging mysqladmin ping -h localhost -u root -p"$MYSQL_ROOT_PASSWORD" --silent 2>/dev/null; then
        break
    fi
    COUNT=$((COUNT + 1))
    echo -n "."
    sleep 2
done
echo

if [ $COUNT -eq $RETRIES ]; then
    log_error "MySQL failed to start"
    docker-compose logs mysql-staging
    exit 1
fi

log_info "✓ Docker containers started"

# Step 6: Health check
log_step "6/6 Running health check..."
./scripts/health-check.sh

# Final message
echo ""
echo "=========================================="
echo "SETUP COMPLETED!"
echo "=========================================="
echo ""
echo "Access Information:"
echo "  URL: https://$DOMAIN"
echo "  MySQL Host: mysql-staging (from other containers)"
echo "  MySQL Port: 3306"
echo ""
echo "Next Steps:"
echo "1. Add to /etc/hosts: $(hostname -I | awk '{print $1}') $DOMAIN"
echo "2. Run migration: ./scripts/migrate.sh your_database"
echo "3. Access phpMyAdmin at https://$DOMAIN"
echo ""
echo "Useful commands:"
echo "  docker-compose logs -f    # View logs"
echo "  docker-compose down       # Stop containers"
echo "  ./scripts/backup.sh       # Backup database"
echo "=========================================="