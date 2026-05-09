#!/bin/bash
# ============================================================
# bootstrap.sh — Full server setup from scratch
# Run this on a fresh Ubuntu 22.04 server to reproduce
# the entire production environment automatically
#
# Usage: bash bootstrap.sh
# Time: ~5 minutes on t2.micro
# ============================================================
set -euo pipefail

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG="/var/log/bootstrap.log"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }

log "Bootstrap started at $TIMESTAMP"
log "Running as: $(whoami) on $(hostname)"

# ── SYSTEM UPDATE ────────────────────────────────────────────
log "Updating system packages..."
apt update -y && apt upgrade -y
apt install -y curl wget ufw fail2ban unattended-upgrades bc

# ── CREATE DEVOPS USER ───────────────────────────────────────
log "Creating devops user..."
if ! id "devops" &>/dev/null; then
    adduser --disabled-password --gecos "" devops
    usermod -aG sudo devops
    mkdir -p /home/devops/.ssh
    # In real use: copy authorized_keys here
    chown -R devops:devops /home/devops/.ssh
    chmod 700 /home/devops/.ssh
fi

# ── SSH HARDENING ────────────────────────────────────────────
log "Hardening SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%s)
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd
log "SSH hardened."

# ── FIREWALL ─────────────────────────────────────────────────
log "Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable
log "Firewall active."

# ── FAIL2BAN ─────────────────────────────────────────────────
log "Configuring Fail2Ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
cat >> /etc/fail2ban/jail.local << 'EOF'

[sshd]
enabled = true
maxretry = 3
findtime = 600
bantime = 3600
EOF
systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2Ban configured."

# ── DOCKER ───────────────────────────────────────────────────
log "Installing Docker..."
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh
usermod -aG docker ubuntu
usermod -aG docker devops
systemctl enable docker
log "Docker installed."

# ── NGINX ────────────────────────────────────────────────────
log "Installing and configuring Nginx..."
apt install -y nginx
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/flask-app << 'EOF'
limit_req_zone $binary_remote_addr zone=app_limit:10m rate=10r/s;

server {
    listen 80;
    server_name _;
    server_tokens off;

    access_log /var/log/nginx/flask-app.access.log;
    error_log  /var/log/nginx/flask-app.error.log warn;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        limit_req zone=app_limit burst=20 nodelay;
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /health {
        proxy_pass http://127.0.0.1:5000/health;
        access_log off;
    }
}
EOF
ln -sf /etc/nginx/sites-available/flask-app /etc/nginx/sites-enabled/
nginx -t && systemctl enable nginx && systemctl restart nginx
log "Nginx configured."

# ── LOGGING STRUCTURE ────────────────────────────────────────
log "Creating logging structure..."
mkdir -p /var/log/app-monitor
chown devops:devops /var/log/app-monitor
touch /var/log/app-monitor/{health.log,events.log,alerts.log,deployments.log}

# ── AUTO UPDATES ─────────────────────────────────────────────
log "Enabling automatic security updates..."
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades

# ── DONE ─────────────────────────────────────────────────────
log "Bootstrap complete. Server is production-ready."
log "Next steps:"
log "  1. Deploy application: bash ~/scripts/deploy.sh v1"
log "  2. Set up cron jobs: crontab -e"
log "  3. Verify: bash ~/scripts/status.sh"
