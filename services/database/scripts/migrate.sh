#!/bin/bash

# MySQL Migration Script: Host to Docker Staging
# Usage: ./scripts/migrate.sh [database_name]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/.env"

HOST_MYSQL_USER="root"
HOST_MYSQL_HOST="localhost"
HOST_MYSQL_PORT="3306"
DOCKER_MYSQL_CONTAINER="mysql-staging"
DOCKER_MYSQL_USER="root"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if database name provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <database_name>"
    echo "Example: $0 myapp_staging"
    exit 1
fi

DB_NAME=$1
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql"

# Create backup directory
mkdir -p "$BACKUP_DIR"

log_info "Starting migration for database: $DB_NAME"
log_info "Project directory: $PROJECT_DIR"

# Step 1: Check if Docker MySQL is running
log_step "1/7 Checking Docker MySQL container..."
if ! docker ps | grep -q "$DOCKER_MYSQL_CONTAINER"; then
    log_error "Docker MySQL container '$DOCKER_MYSQL_CONTAINER' is not running!"
    log_info "Start it with: docker-compose up -d"
    exit 1
fi
log_info "✓ Docker MySQL is running"

# Step 2: Export from host MySQL
log_step "2/7 Exporting database '$DB_NAME' from host MySQL..."
read -sp "Enter host MySQL root password: " HOST_MYSQL_PASSWORD
echo

if ! mysqldump -h "$HOST_MYSQL_HOST" -P "$HOST_MYSQL_PORT" -u "$HOST_MYSQL_USER" -p"$HOST_MYSQL_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --databases "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null; then
    log_error "Failed to export database from host MySQL"
    log_info "Make sure host MySQL is running and credentials are correct"
    exit 1
fi

if [ ! -s "$BACKUP_FILE" ]; then
    log_error "Backup file is empty. Database may not exist."
    rm -f "$BACKUP_FILE"
    exit 1
fi

log_info "✓ Database exported successfully"
log_info "  Backup file: $BACKUP_FILE"
log_info "  Size: $(du -h "$BACKUP_FILE" | cut -f1)"

# Step 3: Verify Docker MySQL is ready
log_step "3/7 Verifying Docker MySQL readiness..."
RETRIES=30
COUNT=0
while [ $COUNT -lt $RETRIES ]; do
    if docker exec "$DOCKER_MYSQL_CONTAINER" mysqladmin ping -h localhost -u root -p"$MYSQL_ROOT_PASSWORD" --silent 2>/dev/null; then
        break
    fi
    COUNT=$((COUNT + 1))
    echo -n "."
    sleep 2
done
echo

if [ $COUNT -eq $RETRIES ]; then
    log_error "Docker MySQL failed to become ready"
    exit 1
fi
log_info "✓ Docker MySQL is ready"

# Step 4: Create database in Docker if not exists
log_step "4/7 Creating database in Docker MySQL..."
docker exec "$DOCKER_MYSQL_CONTAINER" mysql -u "$DOCKER_MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" 2>/dev/null
log_info "✓ Database created (or already exists)"

# Step 5: Import to Docker MySQL
log_step "5/7 Importing database to Docker MySQL..."
if ! docker exec -i "$DOCKER_MYSQL_CONTAINER" mysql -u "$DOCKER_MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" < "$BACKUP_FILE" 2>/dev/null; then
    log_error "Failed to import database to Docker MySQL"
    exit 1
fi
log_info "✓ Database imported successfully"

# Step 6: Verification
log_step "6/7 Verifying import..."
if docker exec "$DOCKER_MYSQL_CONTAINER" mysql -u "$DOCKER_MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | grep -q "Tables_in"; then
    log_info "✓ Database '$DB_NAME' verified in Docker MySQL"
    TABLE_COUNT=$(docker exec "$DOCKER_MYSQL_CONTAINER" mysql -u "$DOCKER_MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" -N 2>/dev/null)
    log_info "✓ Total tables: $TABLE_COUNT"
else
    log_warn "Could not verify database - please check manually"
fi

# Step 7: Cleanup old backups
log_step "7/7 Cleaning old backups..."
DELETED_COUNT=$(find "$BACKUP_DIR" -name "*.sql" -mtime +7 -print | wc -l)
find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete
log_info "✓ Deleted $DELETED_COUNT backup(s) older than 7 days"

# Summary
echo ""
echo "=========================================="
echo "MIGRATION COMPLETED SUCCESSFULLY!"
echo "=========================================="
echo "Database: $DB_NAME"
echo "Backup: $BACKUP_FILE"
echo "Access: https://${DOMAIN}"
echo ""
echo "Credentials:"
echo "  - Basic Auth: htpasswd users"
echo "  - MySQL Root: root / [from .env]"
echo "  - MySQL User: $MYSQL_USER / [from .env]"
echo "=========================================="
echo ""
log_info "Next steps:"
echo "1. Add to /etc/hosts: $(hostname -I | awk '{print $1}') ${DOMAIN}"
echo "2. Test phpMyAdmin access at https://${DOMAIN}"
echo "3. Verify data integrity"
echo ""