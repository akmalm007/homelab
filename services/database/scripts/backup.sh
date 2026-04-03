#!/bin/bash

# Database Backup Script
# Usage: ./scripts/backup.sh [database_name] or ./scripts/backup.sh all

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

source .env

BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DOCKER_MYSQL_CONTAINER="mysql-staging"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if container is running
if ! docker ps | grep -q "$DOCKER_MYSQL_CONTAINER"; then
    log_error "MySQL container is not running!"
    exit 1
fi

# Function to backup single database
backup_database() {
    local DB_NAME=$1
    local BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql"
    
    log_info "Backing up database: $DB_NAME"
    
    if docker exec "$DOCKER_MYSQL_CONTAINER" mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null; then
        
        # Compress backup
        gzip "$BACKUP_FILE"
        log_info "✓ Backup completed: ${BACKUP_FILE}.gz"
        log_info "  Size: $(du -h "${BACKUP_FILE}.gz" | cut -f1)"
    else
        log_error "Failed to backup database: $DB_NAME"
        return 1
    fi
}

# Main logic
if [ $# -eq 0 ]; then
    log_warn "Usage: $0 <database_name> | all"
    log_info "Available databases:"
    docker exec "$DOCKER_MYSQL_CONTAINER" mysql -u root -p"$MYSQL_ROOT_PASSWORD" \
        -e "SHOW DATABASES;" -N 2>/dev/null | grep -v "information_schema\|performance_schema\|mysql\|sys"
    exit 0
fi

if [ "$1" == "all" ]; then
    log_info "Backing up all databases..."
    DATABASES=$(docker exec "$DOCKER_MYSQL_CONTAINER" mysql -u root -p"$MYSQL_ROOT_PASSWORD" \
        -e "SHOW DATABASES;" -N 2>/dev/null | grep -v "information_schema\|performance_schema\|mysql\|sys")
    
    for DB in $DATABASES; do
        backup_database "$DB"
    done
else
    backup_database "$1"
fi

# Cleanup old backups (keep last 7 days)
log_info "Cleaning up old backups..."
find "$BACKUP_DIR" -name "*.gz" -mtime +7 -delete

log_info "Backup process completed!"