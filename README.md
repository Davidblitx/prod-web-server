# Production-Grade Web Server on AWS

A production-ready single-server web infrastructure built on AWS EC2,
demonstrating real DevOps practices: security hardening, containerization,
reverse proxying, automated monitoring, and self-healing deployments.

## Architecture
Internet → AWS Security Group → UFW Firewall → Nginx :80 → Docker/Flask :5000

## Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Cloud | AWS EC2 (Ubuntu 22.04) | Compute |
| Container | Docker | App isolation and portability |
| Application | Flask + Gunicorn | Web application |
| Web Server | Nginx | Reverse proxy, security headers |
| Firewall | AWS Security Group + UFW | Defense in depth |
| Intrusion Prevention | Fail2Ban | SSH brute force protection |
| Monitoring | Bash + Cron | Health checks every 5 minutes |

## Security Implementation

- SSH key-only authentication (passwords disabled)
- Root login disabled
- Dual-layer firewall (cloud + OS level)
- Fail2Ban blocks IPs after 3 failed SSH attempts
- Non-root user inside Docker container
- Nginx security headers (X-Frame-Options, X-Content-Type-Options, XSS Protection)
- Rate limiting (10 requests/second per IP)
- Hidden server version tokens

## Reliability Features

- Docker restart policy: `--restart unless-stopped`
- Health check cron job every 5 minutes
- Automatic container recovery on failure
- Deployment rollback on failed health check
- Full reboot survival (all services auto-start via systemd)

## Deployment

```bash
# Deploy new version (auto-rolls back if unhealthy)
bash scripts/deploy.sh v2

# Check server status
bash scripts/status.sh

# Force health check
bash scripts/health_check.sh

# Rebuild server from scratch
bash scripts/bootstrap.sh
```

## Verified Scenarios

- ✅ Container crash → auto-recovered in under 5 minutes
- ✅ Bad deployment → automatic rollback to previous version
- ✅ Server reboot → all services restored without manual intervention
- ✅ Real internet traffic and scan attempts → blocked, logged
- ✅ Deployment audit trail with full history

## Project Structure
├── app.py              # Flask application
├── Dockerfile          # Container definition (non-root, production-grade)
├── requirements.txt    # Python dependencies
├── scripts/
│   ├── deploy.sh       # Production deploy with rollback
│   ├── health_check.sh # Automated monitoring and recovery
│   ├── status.sh       # Server status dashboard
│   └── bootstrap.sh    # Full server setup from scratch
└── docs/
└── ARCHITECTURE.md # Full architecture and decision log

## What I Would Add Next

- HTTPS with Let's Encrypt (Certbot)
- Terraform to provision infrastructure as code
- GitHub Actions for automated CI/CD
- Prometheus + Grafana for metrics dashboard
- Multi-server setup with load balancer
