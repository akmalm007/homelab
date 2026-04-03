#!/bin/bash

# Health Check Script
# Verifies all components are working correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

source .env

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_section() { echo -e "\n${BLUE}▶ $1${NC}"; }

ERRORS=0

echo "=========================================="
echo "STAGING DATABASE HEALTH CHECK"
echo "=========================================="

# 1. Docker Check
log_section "Docker Status"
if docker ps | grep -q "mysql-staging"; then
    log_info "MySQL container is running"
    MYSQL_STATUS=$(docker inspect -f '{{.State.Status}}' mysql-staging)
    log_info "MySQL status: $MYSQL_STATUS"
else
    log_error "MySQL container is NOT running"
    ERRORS=$((ERRORS + 1))
fi

if docker ps | grep -q "phpmyadmin-staging"; then
    log_info "phpMyAdmin container is running"
else
    log_error "phpMyAdmin container is NOT running"
    ERRORS=$((ERRORS + 1))
fi

# 2. MySQL Connectivity
log_section "MySQL Connectivity"
if docker exec mysql-staging mysqladmin ping -h localhost -u root -p"$MYSQL_ROOT_PASSWORD" --silent 2>/dev/null; then
    log_info "MySQL is accepting connections"
    
    # Check version
    MYSQL_VERSION=$(docker exec mysql-staging mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT VERSION();" -N 2>/dev/null)
    log_info "MySQL version: $MYSQL_VERSION"
    
    # Check databases
    DB_COUNT=$(docker exec mysql-staging mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');" -N 2>/dev/null)
    log_info "User databases: $DB_COUNT"
else
    log_error "MySQL is NOT accepting connections"
    ERRORS=$((ERRORS + 1))
fi

# 3. phpMyAdmin Connectivity
log_section "phpMyAdmin Connectivity"
if docker exec phpmyadmin-staging wget -qO- http://localhost/ 2>/dev/null | grep -q "phpMyAdmin"; then
    log_info "phpMyAdmin web interface is responding"
else
    log_error "phpMyAdmin web interface is NOT responding"
    ERRORS=$((ERRORS + 1))
fi

# 4. Network Check
log_section "Network Configuration"
if docker network ls | grep -q "staging-db-network"; then
    log_info "Docker network exists"
    
    # Check connected containers
    CONNECTED=$(docker network inspect staging-db-network -f '{{range .Containers}}{{.Name}} {{end}}')
    log_info "Connected containers: $CONNECTED"
else
    log_error "Docker network is missing"
    ERRORS=$((ERRORS + 1))
fi

# 5. Volume Check
log_section "Storage"
if docker volume ls | grep -q "database_mysql_staging_data"; then
    log_info "MySQL data volume exists"
else
    log_warn "MySQL data volume not found (will be created on start)"
fi

# 6. SSL Certificates
log_section "SSL Configuration"
if [ -f nginx-config/cert.pem ] && [ -f nginx-config/cert-key.pem ]; then
    log_info "SSL certificates found"
    CERT_INFO=$(openssl x509 -in nginx-config/cert.pem -noout -subject -dates 2>/dev/null | tr '\n' ' ')
    log_info "Certificate: $CERT_INFO"
else
    log_warn "SSL certificates not found in nginx-config/"
fi

# 7. Nginx Check (if on host)
log_section "Nginx Configuration"
if command -v nginx &> /dev/null; then
    if [ -f /etc/nginx/sites-available/phpmyadmin.conf ]; then
        log_info "Nginx site config exists"
        
        if nginx -t 2>&1 | grep -q "successful"; then
            log_info "Nginx configuration is valid"
        else
            log_error "Nginx configuration test failed"
            nginx -t
            ERRORS=$((ERRORS + 1))
        fi
        
        if [ -L /etc/nginx/sites-enabled/phpmyadmin.conf ]; then
            log_info "Nginx site is enabled"
        else
            log_warn "Nginx site is NOT enabled"
        fi
    else
        log_warn "Nginx site config not found"
    fi
else
    log_warn "Nginx not installed on host"
fi

# 8. Disk Space
log_section "System Resources"
DISK_USAGE=$(df -h "$PROJECT_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -lt 80 ]; then
    log_info "Disk usage: ${DISK_USAGE}%"
else
    log_warn "Disk usage is high: ${DISK_USAGE}%"
fi

# Summary
echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}ALL CHECKS PASSED ✓${NC}"
    echo "=========================================="
    echo ""
    echo "Access Information:"
    echo "  URL: https://$DOMAIN"
    echo "  MySQL Host: mysql-staging (internal)"
    echo "  MySQL Port: 3306"
    exit 0
else
    echo -e "${RED}HEALTH CHECK FAILED ✗${NC}"
    echo "Errors found: $ERRORS"
    echo "=========================================="
    echo ""
    echo "Check logs with: docker-compose logs"
    exit 1
fi