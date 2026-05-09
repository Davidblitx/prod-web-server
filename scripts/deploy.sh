#!/bin/bash
# ============================================================
# deploy.sh — Production deployment script
# Usage: bash ~/scripts/deploy.sh [version_tag]
# Example: bash ~/scripts/deploy.sh v2
# ============================================================
set -euo pipefail
# set -e  → exit immediately on any error
# set -u  → treat unset variables as errors
# set -o pipefail → catch errors in pipes too

# ── CONFIG ──────────────────────────────────────────────────
APP_DIR="/home/devops/app"
IMAGE_NAME="flask-app"
CONTAINER_NAME="flask-app"
VERSION="${1:-latest}"          # use argument or default to "latest"
DEPLOY_LOG="/var/log/app-monitor/deployments.log"
HEALTH_URL="http://localhost/health"
ROLLBACK_TAG="previous"

# ── COLORS ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DEPLOYER=$(whoami)

# ── HELPERS ─────────────────────────────────────────────────
log() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
    echo "[$TIMESTAMP] $1" >> "$DEPLOY_LOG"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$TIMESTAMP] SUCCESS: $1" >> "$DEPLOY_LOG"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$TIMESTAMP] WARN: $1" >> "$DEPLOY_LOG"
}

fail() {
    echo -e "${RED}[FAILED]${NC} $1"
    echo "[$TIMESTAMP] FAILED: $1" >> "$DEPLOY_LOG"
    exit 1
}

# ── HEALTH CHECK FUNCTION ────────────────────────────────────
wait_for_health() {
    local max_attempts=12   # 12 x 5 seconds = 60 second timeout
    local attempt=1

    log "Waiting for app to become healthy..."

    while [ $attempt -le $max_attempts ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 5 "$HEALTH_URL" 2>/dev/null)

        if [ "$HTTP_CODE" = "200" ]; then
            success "App is healthy after $attempt attempt(s)."
            return 0
        fi

        echo "  Attempt $attempt/$max_attempts — HTTP $HTTP_CODE, waiting..."
        sleep 5
        attempt=$((attempt + 1))
    done

    return 1  # failed to become healthy
}

# ── ROLLBACK FUNCTION ────────────────────────────────────────
rollback() {
    warn "Initiating rollback to previous version..."

    # Check if previous image exists
    if docker image inspect "${IMAGE_NAME}:${ROLLBACK_TAG}" > /dev/null 2>&1; then
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true

        docker run -d \
            --name "$CONTAINER_NAME" \
            --restart unless-stopped \
            -p 5000:5000 \
            "${IMAGE_NAME}:${ROLLBACK_TAG}"

        sleep 5

        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 5 "$HEALTH_URL" 2>/dev/null)

        if [ "$HTTP_CODE" = "200" ]; then
            success "Rollback successful. Previous version restored."
        else
            fail "Rollback also failed. MANUAL INTERVENTION REQUIRED."
        fi
    else
        fail "No previous image found. Cannot rollback. MANUAL INTERVENTION REQUIRED."
    fi
}

# ════════════════════════════════════════════════════════════
# MAIN DEPLOYMENT SEQUENCE
# ════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  DEPLOYMENT STARTED${NC}"
echo -e "${BLUE}  Version : $VERSION${NC}"
echo -e "${BLUE}  By      : $DEPLOYER${NC}"
echo -e "${BLUE}  Time    : $TIMESTAMP${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

log "Deployment started by $DEPLOYER — version: $VERSION"

# ── STEP 1: Pre-flight checks ────────────────────────────────
log "Step 1/7: Pre-flight checks..."

# Check app directory exists
[ -d "$APP_DIR" ] || fail "App directory $APP_DIR not found."

# Check Dockerfile exists
[ -f "$APP_DIR/Dockerfile" ] || fail "Dockerfile not found in $APP_DIR."

# Check Docker is running
docker info > /dev/null 2>&1 || fail "Docker daemon is not running."

# Check Nginx is running
systemctl is-active --quiet nginx || warn "Nginx is not running. Traffic may be affected."

success "Pre-flight checks passed."

# ── STEP 2: Tag current image as rollback target ─────────────
log "Step 2/7: Preserving current version for rollback..."

if docker image inspect "${IMAGE_NAME}:latest" > /dev/null 2>&1; then
    docker tag "${IMAGE_NAME}:latest" "${IMAGE_NAME}:${ROLLBACK_TAG}"
    success "Current version tagged as '${ROLLBACK_TAG}'."
else
    warn "No existing image to preserve. First deployment."
fi

# ── STEP 3: Build new image ──────────────────────────────────
log "Step 3/7: Building new Docker image: ${IMAGE_NAME}:${VERSION}..."

cd "$APP_DIR"

if docker build -t "${IMAGE_NAME}:${VERSION}" -t "${IMAGE_NAME}:latest" .; then
    success "Image built: ${IMAGE_NAME}:${VERSION}"
else
    fail "Docker build failed. Aborting deployment."
fi

# ── STEP 4: Stop old container ───────────────────────────────
log "Step 4/7: Stopping current container..."

if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
    success "Old container stopped and removed."
else
    warn "No running container found. Starting fresh."
fi

# ── STEP 5: Start new container ──────────────────────────────
log "Step 5/7: Starting new container..."

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p 5000:5000 \
    --label "version=${VERSION}" \
    --label "deployed_by=${DEPLOYER}" \
    --label "deployed_at=${TIMESTAMP}" \
    "${IMAGE_NAME}:${VERSION}"

success "Container started."

# ── STEP 6: Health verification ──────────────────────────────
log "Step 6/7: Verifying application health..."

if wait_for_health; then
    success "Health check passed."
else
    fail_msg="App failed health check after 60 seconds."
    warn "$fail_msg"
    rollback
    fail "Deployment failed. Rolled back to previous version."
fi

# ── STEP 7: Post-deployment summary ─────────────────────────
log "Step 7/7: Post-deployment summary..."

RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" \
    --max-time 5 "$HEALTH_URL" 2>/dev/null)

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  DEPLOYMENT SUCCESSFUL${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "  Version   : ${VERSION}"
echo -e "  Image     : ${IMAGE_NAME}:${VERSION}"
echo -e "  Response  : ${RESPONSE_TIME}s"
echo -e "  Container : $(docker ps --filter name=$CONTAINER_NAME --format '{{.Status}}')"
echo -e "${GREEN}============================================${NC}"
echo ""

success "Deployment complete. Version $VERSION is live."
