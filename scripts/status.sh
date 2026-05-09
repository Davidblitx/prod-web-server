#!/bin/bash
# ============================================================
# status.sh
# One-command server status overview
# Usage: bash ~/scripts/status.sh
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   SERVER STATUS REPORT — $TIMESTAMP${NC}"
echo -e "${BLUE}============================================${NC}"

# ── SYSTEM ──────────────────────────────────────────────────
echo -e "\n${YELLOW}[ SYSTEM ]${NC}"
echo "  Hostname  : $(hostname)"
echo "  Uptime    : $(uptime -p)"
echo "  Load avg  : $(uptime | awk -F'load average:' '{print $2}')"

# ── MEMORY ──────────────────────────────────────────────────
echo -e "\n${YELLOW}[ MEMORY ]${NC}"
free -h | awk 'NR==2 {printf "  Total: %s  Used: %s  Free: %s  Available: %s\n", $2, $3, $4, $7}'

# ── DISK ────────────────────────────────────────────────────
echo -e "\n${YELLOW}[ DISK ]${NC}"
df -h / | awk 'NR==2 {printf "  Total: %s  Used: %s  Free: %s  Usage: %s\n", $2, $3, $4, $5}'

# ── SERVICES ────────────────────────────────────────────────
echo -e "\n${YELLOW}[ SERVICES ]${NC}"

# Nginx
if systemctl is-active --quiet nginx; then
    echo -e "  Nginx     : ${GREEN}RUNNING${NC}"
else
    echo -e "  Nginx     : ${RED}DOWN${NC}"
fi

# Docker
if systemctl is-active --quiet docker; then
    echo -e "  Docker    : ${GREEN}RUNNING${NC}"
else
    echo -e "  Docker    : ${RED}DOWN${NC}"
fi

# Fail2Ban
if systemctl is-active --quiet fail2ban; then
    echo -e "  Fail2Ban  : ${GREEN}RUNNING${NC}"
else
    echo -e "  Fail2Ban  : ${RED}DOWN${NC}"
fi

# ── CONTAINER ───────────────────────────────────────────────
echo -e "\n${YELLOW}[ CONTAINER ]${NC}"
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' flask-app 2>/dev/null)
CONTAINER_UPTIME=$(docker inspect --format='{{.State.StartedAt}}' flask-app 2>/dev/null)

if [ "$CONTAINER_STATUS" = "running" ]; then
    echo -e "  flask-app : ${GREEN}RUNNING${NC} (started: $CONTAINER_UPTIME)"
else
    echo -e "  flask-app : ${RED}$CONTAINER_STATUS${NC}"
fi

# ── APP HEALTH ───────────────────────────────────────────────
echo -e "\n${YELLOW}[ APP HEALTH ]${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost/health 2>/dev/null)
RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 http://localhost/health 2>/dev/null)

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "  HTTP Check : ${GREEN}OK${NC} (${HTTP_CODE}) — Response time: ${RESPONSE_TIME}s"
else
    echo -e "  HTTP Check : ${RED}FAILED${NC} (HTTP ${HTTP_CODE})"
fi

# ── SECURITY ─────────────────────────────────────────────────
echo -e "\n${YELLOW}[ SECURITY ]${NC}"
BANNED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
FAILED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently failed" | awk '{print $NF}')
echo "  Fail2Ban SSH — Banned IPs: ${BANNED:-0}  |  Current failures: ${FAILED:-0}"

RECENT_ATTEMPTS=$(sudo grep "Invalid user\|Failed password" /var/log/auth.log 2>/dev/null | wc -l)
echo "  Total SSH attack attempts logged: $RECENT_ATTEMPTS"

# ── RECENT TRAFFIC ───────────────────────────────────────────
echo -e "\n${YELLOW}[ RECENT TRAFFIC (last 5 requests) ]${NC}"
sudo tail -5 /var/log/nginx/flask-app.access.log 2>/dev/null | \
    awk '{printf "  %s %s %s %s\n", $1, $7, $9, $10}'

# ── RECENT ALERTS ────────────────────────────────────────────
echo -e "\n${YELLOW}[ RECENT ALERTS ]${NC}"
if [ -s /var/log/app-monitor/alerts.log ]; then
    tail -5 /var/log/app-monitor/alerts.log | sed 's/^/  /'
else
    echo -e "  ${GREEN}No alerts recorded.${NC}"
fi

echo -e "\n${BLUE}============================================${NC}"
echo "  Run 'bash ~/scripts/health_check.sh' to force a check"
echo "  Logs: /var/log/app-monitor/"
echo -e "${BLUE}============================================${NC}"
