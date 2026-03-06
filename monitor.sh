#!/bin/bash
# SignalGuard System Monitor
# Provides real-time operational visibility

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.prod.yml"
ENV_FILE=".env.prod"

print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    SignalGuard System Monitor                ║${NC}"
    echo -e "${BLUE}║                    $(date +'%Y-%m-%d %H:%M:%S UTC')                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

check_system_resources() {
    echo -e "${CYAN}📊 System Resources${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # CPU Information
    cpu_cores=$(nproc)
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    echo -e "CPU Cores: ${GREEN}${cpu_cores}${NC} | Usage: ${YELLOW}${cpu_usage}%${NC}"
    
    # Memory Information
    memory_info=$(free -h | awk 'NR==2{printf "Total: %s | Used: %s | Available: %s | Usage: %.1f%%", $2, $3, $7, $3/$2*100}')
    echo -e "Memory: ${memory_info}"
    
    # Disk Information
    disk_info=$(df -h / | awk 'NR==2{printf "Total: %s | Used: %s | Available: %s | Usage: %s", $2, $3, $4, $5}')
    echo -e "Disk: ${disk_info}"
    
    # Load Average
    load_avg=$(uptime | awk -F'load average:' '{print $2}')
    echo -e "Load Average:${load_avg}"
    echo
}

check_docker_status() {
    echo -e "${CYAN}🐳 Docker Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if docker info &>/dev/null; then
        echo -e "Docker Daemon: ${GREEN}Running${NC}"
        
        # Docker system info
        docker_info=$(docker system df --format "table {{.Type}}\t{{.Total}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}" | tail -n +2)
        echo "Docker System Usage:"
        echo "$docker_info"
    else
        echo -e "Docker Daemon: ${RED}Not Running${NC}"
    fi
    echo
}

check_service_health() {
    echo -e "${CYAN}🏥 Service Health${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    services=("edge-nginx" "postgres" "redis" "backend-api" "worker" "platform-ux" "marketing-web")
    
    for service in "${services[@]}"; do
        if docker compose $COMPOSE_FILES ps "$service" 2>/dev/null | grep -q "Up"; then
            # Get container uptime
            uptime=$(docker inspect --format='{{.State.StartedAt}}' "sg-$service" 2>/dev/null | xargs -I {} date -d {} +%s 2>/dev/null || echo "0")
            current_time=$(date +%s)
            uptime_seconds=$((current_time - uptime))
            uptime_human=$(date -u -d @${uptime_seconds} +"%H:%M:%S" 2>/dev/null || echo "Unknown")
            
            echo -e "${service}: ${GREEN}Running${NC} (${uptime_human})"
        else
            echo -e "${service}: ${RED}Stopped${NC}"
        fi
    done
    echo
}

check_container_resources() {
    echo -e "${CYAN}📈 Container Resource Usage${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get container stats
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || echo "No running containers"
    echo
}

check_sandbox_status() {
    echo -e "${CYAN}🔒 Sandbox System Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check for sandbox containers
    sandbox_containers=$(docker ps --filter "label=signalguard=true" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null || echo "")
    
    if [[ -n "$sandbox_containers" && "$sandbox_containers" != *"NAMES"* ]]; then
        echo "Active Sandbox Containers:"
        echo "$sandbox_containers"
    else
        echo "No active sandbox containers"
    fi
    
    # Check Redis for sandbox metrics
    if docker exec sg-redis redis-cli ping &>/dev/null; then
        tokens=$(docker exec sg-redis redis-cli get "sandbox:tokens" 2>/dev/null || echo "N/A")
        queue_depth=$(docker exec sg-redis redis-cli get "sandbox:queue_depth" 2>/dev/null || echo "0")
        echo -e "Available Tokens: ${GREEN}${tokens}${NC} | Queue Depth: ${YELLOW}${queue_depth}${NC}"
    fi
    echo
}

check_database_status() {
    echo -e "${CYAN}🗄️  Database Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if docker exec sg-postgres pg_isready -U signalguard &>/dev/null; then
        echo -e "PostgreSQL: ${GREEN}Ready${NC}"
        
        # Get connection count
        connections=$(docker exec sg-postgres psql -U signalguard -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "N/A")
        echo -e "Active Connections: ${YELLOW}${connections}${NC}"
        
        # Get database size
        db_size=$(docker exec sg-postgres psql -U signalguard -t -c "SELECT pg_size_pretty(pg_database_size('signalguard'));" 2>/dev/null | xargs || echo "N/A")
        echo -e "Database Size: ${CYAN}${db_size}${NC}"
    else
        echo -e "PostgreSQL: ${RED}Not Ready${NC}"
    fi
    echo
}

check_redis_status() {
    echo -e "${CYAN}🔴 Redis Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if docker exec sg-redis redis-cli ping &>/dev/null; then
        echo -e "Redis: ${GREEN}Running${NC}"
        
        # Get Redis info
        memory_usage=$(docker exec sg-redis redis-cli info memory | grep "used_memory_human" | cut -d: -f2 | tr -d '\r' || echo "N/A")
        connected_clients=$(docker exec sg-redis redis-cli info clients | grep "connected_clients" | cut -d: -f2 | tr -d '\r' || echo "N/A")
        
        echo -e "Memory Usage: ${YELLOW}${memory_usage}${NC} | Connected Clients: ${CYAN}${connected_clients}${NC}"
    else
        echo -e "Redis: ${RED}Not Running${NC}"
    fi
    echo
}

check_network_connectivity() {
    echo -e "${CYAN}🌐 Network Connectivity${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check Nginx health
    if curl -f -s http://localhost/nginx-health >/dev/null 2>&1; then
        echo -e "Nginx Health: ${GREEN}OK${NC}"
    else
        echo -e "Nginx Health: ${RED}Failed${NC}"
    fi
    
    # Check API health (if accessible)
    if curl -f -s http://localhost:9100/health >/dev/null 2>&1; then
        echo -e "API Health: ${GREEN}OK${NC}"
    else
        echo -e "API Health: ${YELLOW}Not Accessible${NC}"
    fi
    echo
}

check_logs_errors() {
    echo -e "${CYAN}📋 Recent Errors${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check for recent errors in logs
    error_count=$(docker compose $COMPOSE_FILES logs --since=1h 2>/dev/null | grep -i error | wc -l || echo "0")
    warning_count=$(docker compose $COMPOSE_FILES logs --since=1h 2>/dev/null | grep -i warning | wc -l || echo "0")
    
    if [[ $error_count -gt 0 ]]; then
        echo -e "Errors (last hour): ${RED}${error_count}${NC}"
    else
        echo -e "Errors (last hour): ${GREEN}0${NC}"
    fi
    
    if [[ $warning_count -gt 0 ]]; then
        echo -e "Warnings (last hour): ${YELLOW}${warning_count}${NC}"
    else
        echo -e "Warnings (last hour): ${GREEN}0${NC}"
    fi
    echo
}

show_quick_actions() {
    echo -e "${CYAN}⚡ Quick Actions${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• View logs: ./deploy.sh logs [service]"
    echo "• Restart service: docker compose $COMPOSE_FILES restart [service]"
    echo "• Check sandbox metrics: curl http://localhost:9100/health"
    echo "• Force cleanup: docker exec sg-worker python -c \"from app.worker.enhanced_scavenger import enhanced_scavenge_orphans; enhanced_scavenge_orphans()\""
    echo "• System backup: ./deploy.sh backup"
    echo
}

# Main execution
main() {
    clear
    print_header
    check_system_resources
    check_docker_status
    check_service_health
    check_container_resources
    check_sandbox_status
    check_database_status
    check_redis_status
    check_network_connectivity
    check_logs_errors
    show_quick_actions
}

# Handle command line arguments
case "${1:-}" in
    --watch|-w)
        while true; do
            main
            echo -e "${BLUE}Refreshing in 30 seconds... (Ctrl+C to exit)${NC}"
            sleep 30
        done
        ;;
    --help|-h)
        echo "SignalGuard System Monitor"
        echo "Usage: $0 [--watch|-w] [--help|-h]"
        echo ""
        echo "Options:"
        echo "  --watch, -w    Continuously monitor (refresh every 30s)"
        echo "  --help, -h     Show this help message"
        ;;
    *)
        main
        ;;
esac
