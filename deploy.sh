#!/bin/bash
set -euo pipefail

# SignalGuard Production Deployment Script
# Usage: ./deploy.sh [start|stop|restart|status|logs|update]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.prod.yml"
ENV_FILE=".env.prod"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        error "Docker Compose is not available"
        exit 1
    fi
    
    # Check environment file
    if [[ ! -f "$ENV_FILE" ]]; then
        error "Environment file $ENV_FILE not found"
        error "Copy .env.prod.example to $ENV_FILE and configure it"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Resource validation
validate_resources() {
    log "Validating system resources..."
    
    # Check available memory (minimum 20GB for 22GB system)
    available_mem=$(free -g | awk '/^Mem:/{print $7}')
    if [[ $available_mem -lt 18 ]]; then
        warn "Low available memory: ${available_mem}GB (recommended: 18GB+)"
    fi
    
    # Check CPU cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 4 ]]; then
        warn "Low CPU cores: ${cpu_cores} (recommended: 4+)"
    fi
    
    # Check disk space
    available_disk=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $available_disk -lt 50 ]]; then
        warn "Low disk space: ${available_disk}GB (recommended: 50GB+)"
    fi
    
    success "Resource validation completed"
}

# Start services
start_services() {
    log "Starting SignalGuard services..."
    
    # Pull latest images
    docker compose $COMPOSE_FILES --env-file "$ENV_FILE" pull
    
    # Start services
    docker compose $COMPOSE_FILES --env-file "$ENV_FILE" up -d
    
    # Wait for services to be healthy
    log "Waiting for services to be healthy..."
    sleep 30
    
    # Check service health
    check_health
    
    success "SignalGuard services started successfully"
}

# Stop services
stop_services() {
    log "Stopping SignalGuard services..."
    docker compose $COMPOSE_FILES --env-file "$ENV_FILE" down
    success "SignalGuard services stopped"
}

# Restart services
restart_services() {
    log "Restarting SignalGuard services..."
    stop_services
    start_services
}

# Check service health
check_health() {
    log "Checking service health..."
    
    services=("postgres" "redis" "backend-api" "worker")
    
    for service in "${services[@]}"; do
        if docker compose $COMPOSE_FILES ps "$service" | grep -q "Up"; then
            success "$service is running"
        else
            error "$service is not running"
        fi
    done
    
    # Check API health endpoint
    if curl -f -s http://localhost/nginx-health > /dev/null; then
        success "Nginx health check passed"
    else
        warn "Nginx health check failed"
    fi
}

# Show service status
show_status() {
    log "SignalGuard service status:"
    docker compose $COMPOSE_FILES --env-file "$ENV_FILE" ps
    
    echo ""
    log "Resource usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

# Show logs
show_logs() {
    service=${2:-}
    if [[ -n "$service" ]]; then
        docker compose $COMPOSE_FILES --env-file "$ENV_FILE" logs -f "$service"
    else
        docker compose $COMPOSE_FILES --env-file "$ENV_FILE" logs -f
    fi
}

# Update services
update_services() {
    log "Updating SignalGuard services..."
    
    # Pull latest images
    docker compose $COMPOSE_FILES --env-file "$ENV_FILE" pull
    
    # Restart services with new images
    docker compose $COMPOSE_FILES --env-file "$ENV_FILE" up -d
    
    # Clean up old images
    docker image prune -f
    
    success "SignalGuard services updated successfully"
}

# Backup data
backup_data() {
    log "Creating backup..."
    
    backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup database
    docker compose $COMPOSE_FILES --env-file "$ENV_FILE" exec -T postgres pg_dump -U signalguard signalguard > "$backup_dir/database.sql"
    
    # Backup storage
    docker run --rm -v sg-storage:/data -v "$PWD/$backup_dir":/backup alpine tar czf /backup/storage.tar.gz -C /data .
    
    success "Backup created in $backup_dir"
}

# Main command handler
case "${1:-}" in
    start)
        check_prerequisites
        validate_resources
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        check_prerequisites
        restart_services
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$@"
        ;;
    update)
        check_prerequisites
        update_services
        ;;
    backup)
        backup_data
        ;;
    health)
        check_health
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs [service]|update|backup|health}"
        echo ""
        echo "Commands:"
        echo "  start   - Start all services"
        echo "  stop    - Stop all services"
        echo "  restart - Restart all services"
        echo "  status  - Show service status and resource usage"
        echo "  logs    - Show logs (optionally for specific service)"
        echo "  update  - Pull latest images and restart services"
        echo "  backup  - Create database and storage backup"
        echo "  health  - Check service health"
        exit 1
        ;;
esac
