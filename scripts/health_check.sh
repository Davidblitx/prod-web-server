#!/bin/bash
# ============================================================
# health_check.sh
# Monitors the Flask app and Nginx, restarts if needed
# Runs every 5 minutes via cron
# ============================================================

# ── CONFIG ──────────────────────────────────────────────────
APP_URL="http://localhost/health"          # Goes through Nginx
DIRECT_URL="http://localhost:5000/health"  # Direct to container
CONTAINER_NAME="flask-app"
HEALTH_LOG="/var/log/app-monitor/health.log"
ALERT_LOG="/var/log/app-monitor/alerts.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── HELPER FUNCTIONS ────────────────────────────────────────
log_health() {
    echo "[$TIMESTAMP] $1" >> "$HEALTH_LOG"
}

log_alert() {
    echo "[$TIMESTAMP] ⚠️  ALERT: $1" >> "$ALERT_LOG"
    echo "[$TIMESTAMP] ⚠️  ALERT: $1" >> "$HEALTH_LOG"
}

log_recovery() {
    echo "[$TIMESTAMP] ✅ RECOVERY: $1" >> "$HEALTH_LOG"
    echo "[$TIMESTAMP] ✅ RECOVERY: $1" >> "$ALERT_LOG"
}

# ── CHECK 1: DOCKER CONTAINER ───────────────────────────────
check_container() {
    CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)

    if [ "$CONTAINER_STATUS" != "running" ]; then
        log_alert "Container '$CONTAINER_NAME' is $CONTAINER_STATUS. Attempting restart..."
        docker start "$CONTAINER_NAME" 2>/dev/null || docker run -d \
            --name "$CONTAINER_NAME" \
            --restart unless-stopped \
            -p 5000:5000 \
            flask-app:v1
        sleep 3
        log_recovery "Container restart attempted."
        return 1
    fi
    return 0
}

# ── CHECK 2: APP HTTP RESPONSE ───────────────────────────────
check_app_direct() {
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 "$DIRECT_URL" 2>/dev/null)

    if [ "$HTTP_CODE" != "200" ]; then
        log_alert "Flask app returned HTTP $HTTP_CODE (expected 200). Restarting container..."
        docker restart "$CONTAINER_NAME"
        sleep 5
        log_recovery "Container restarted due to bad HTTP response."
        return 1
    fi
    return 0
}

# ── CHECK 3: NGINX RESPONSE ──────────────────────────────────
check_nginx() {
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 "$APP_URL" 2>/dev/null)

    if [ "$HTTP_CODE" != "200" ]; then
        log_alert "Nginx returned HTTP $HTTP_CODE. Checking nginx service..."

        if ! systemctl is-active --quiet nginx; then
            log_alert "Nginx is DOWN. Attempting restart..."
            sudo systemctl restart nginx
            sleep 2
            log_recovery "Nginx restarted."
        else
            log_alert "Nginx is running but returned $HTTP_CODE. Check config."
        fi
        return 1
    fi
    return 0
}

# ── CHECK 4: DISK SPACE ──────────────────────────────────────
check_disk() {
    DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

    if [ "$DISK_USAGE" -gt 85 ]; then
        log_alert "Disk usage at ${DISK_USAGE}%. Getting critical."
    elif [ "$DISK_USAGE" -gt 70 ]; then
        log_health "WARNING: Disk usage at ${DISK_USAGE}%."
    fi
}

# ── CHECK 5: MEMORY ──────────────────────────────────────────
check_memory() {
    MEM_AVAILABLE=$(free | awk 'NR==2 {printf "%.0f", $7/$2*100}')

    if [ "$MEM_AVAILABLE" -lt 10 ]; then
        log_alert "Available memory critically low: ${MEM_AVAILABLE}% free."
    fi
}

# ── CHECK 6: ERROR RATE ──────────────────────────────────────
check_error_rate() {
    ERRORS=$(sudo tail -100 /var/log/nginx/flask-app.access.log 2>/dev/null | \
        grep -c '" 5' || true)

    if [ "$ERRORS" -gt 10 ]; then
        log_alert "High error rate: $ERRORS 5xx errors in last 100 requests."
    fi
}

# ── RESPONSE TIME CHECK ──────────────────────────────────────
check_response_time() {
    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" \
        --max-time 10 "$APP_URL" 2>/dev/null)

    # Alert if response time > 3 seconds
    SLOW=$(echo "$RESPONSE_TIME > 3.0" | bc -l 2>/dev/null)
    if [ "$SLOW" = "1" ]; then
        log_alert "Slow response: ${RESPONSE_TIME}s (threshold: 3s)"
    fi
}

# ── MAIN EXECUTION ───────────────────────────────────────────
log_health "--- Health check started ---"

check_container
CONTAINER_OK=$?

check_app_direct
APP_OK=$?

check_nginx
NGINX_OK=$?

check_disk
check_memory
check_response_time

# Summary line
if [ $CONTAINER_OK -eq 0 ] && [ $APP_OK -eq 0 ] && [ $NGINX_OK -eq 0 ]; then
    log_health "All checks passed. System healthy."
else
    log_health "One or more checks FAILED. See alerts above."
fi

log_health "--- Health check complete ---"
