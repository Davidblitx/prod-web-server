# 🚀 Production-Grade Web Server on AWS

> A hardened, self-healing web infrastructure on AWS EC2 — built the way real production systems are built.

![AWS](https://img.shields.io/badge/AWS-EC2-orange?logo=amazonaws)
![Docker](https://img.shields.io/badge/Docker-containerized-blue?logo=docker)
![Nginx](https://img.shields.io/badge/Nginx-reverse--proxy-green?logo=nginx)
![Python](https://img.shields.io/badge/Python-Flask-yellow?logo=python)
![Security](https://img.shields.io/badge/Security-hardened-red?logo=shield)

---

## What This Is

Most tutorials show you how to get a server running. This project shows what happens **after** — security hardening, automated recovery, zero-downtime deployments, and surviving real internet traffic.

This is a single-server infrastructure that demonstrates:
- **Defense in depth** — two independent firewall layers
- **Self-healing** — containers recover automatically without human intervention
- **Safe deployments** — automatic rollback if a new version breaks
- **Production mindset** — every decision documented with reasoning

---

## Architecture

```
Internet Traffic
      │
      ▼
┌─────────────────────────────────────────────┐
│  AWS Security Group                          │
│  (Cloud-level firewall — ports 22, 80 only) │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  UFW Firewall (OS-level)                    │
│  Second layer — independent of AWS          │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  Nginx :80                                  │
│  • Reverse proxy                            │
│  • Security headers                         │
│  • Rate limiting (10 req/s per IP)          │
│  • Version tokens hidden                    │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  Docker Container                           │
│  Flask + Gunicorn :5000                     │
│  • Non-root user                            │
│  • Isolated filesystem                      │
│  • Auto-restart on crash                   │
└─────────────────────────────────────────────┘
```

---

## Security Implementation

| Layer | Control | What It Does |
|---|---|---|
| Cloud | AWS Security Group | Allows only ports 22 and 80 |
| OS | UFW Firewall | Second independent firewall layer |
| SSH | Key-only auth | Password authentication disabled |
| SSH | Root login disabled | No direct root access |
| SSH | Fail2Ban | Blocks IPs after 3 failed attempts |
| App | Non-root Docker user | Container breach can't escalate |
| HTTP | Nginx security headers | X-Frame-Options, XSS protection, content-type |
| HTTP | Rate limiting | 10 requests/second per IP — blocks floods |
| HTTP | Version hiding | Server fingerprinting prevented |

**Defense in depth** means if one layer fails, the others still hold. This is a fundamental security principle used in all production systems.

---

## Reliability Features

### Self-Healing Container
```bash
docker run --restart unless-stopped ...
```
If the container crashes at 3am, it comes back up automatically. No on-call wake-up needed.

### Automated Health Monitoring
A cron job runs every 5 minutes, hits the health endpoint, and restarts the container if it's unhealthy:
```
*/5 * * * * /home/ubuntu/scripts/health_check.sh
```

### Safe Deployments With Automatic Rollback
```bash
bash scripts/deploy.sh v2
```
The deploy script:
1. Pulls the new version
2. Starts it alongside the old one
3. Runs a health check
4. If healthy → cuts over traffic, removes old container
5. If unhealthy → automatically rolls back to previous version, logs the failure

### Full Reboot Survival
All services are registered with systemd. A server reboot brings everything back without any manual intervention.

---

## Verified in Production

These scenarios were actually tested against the live server — not just documented:

| Scenario | Result |
|---|---|
| Container crash | Auto-recovered in under 5 minutes |
| Bad deployment pushed | Automatic rollback to previous version |
| Server reboot | All services restored without manual intervention |
| Real internet scan attempts | Blocked by Fail2Ban + rate limiting, logged |
| Deployment audit | Full history with timestamps preserved |

---

## Quick Start

### Deploy a new version
```bash
bash scripts/deploy.sh v2
```

### Check server status
```bash
bash scripts/status.sh
```

### Force a health check
```bash
bash scripts/health_check.sh
```

### Rebuild the entire server from scratch
```bash
bash scripts/bootstrap.sh
```

---

## Project Structure

```
├── app.py                  # Flask application
├── Dockerfile              # Container definition (non-root, production config)
├── requirements.txt        # Python dependencies
├── scripts/
│   ├── bootstrap.sh        # Full server setup from scratch
│   ├── deploy.sh           # Production deploy with automatic rollback
│   ├── health_check.sh     # Automated monitoring and container recovery
│   └── status.sh           # Server status dashboard
└── docs/
    └── ARCHITECTURE.md     # Full architecture decisions and reasoning
```

---

## Stack

| Layer | Technology |
|---|---|
| Cloud | AWS EC2 (Ubuntu 22.04) |
| Container | Docker |
| Application | Flask + Gunicorn |
| Web Server | Nginx |
| Firewall | AWS Security Group + UFW |
| Intrusion Prevention | Fail2Ban |
| Monitoring | Bash + Cron |
| Init System | systemd |

---

## What I Would Add Next

- **HTTPS** with Let's Encrypt (Certbot) — TLS termination at Nginx
- **Terraform** to provision the EC2 instance as Infrastructure-as-Code
- **GitHub Actions** CI/CD pipeline — push to main → auto-deploy
- **Prometheus + Grafana** — metrics dashboard replacing bash monitoring
- **Multi-server setup** with an Application Load Balancer for high availability

---

## Key Learnings

Building this taught me the difference between *running* a server and *operating* one. Getting Nginx to serve a Flask app takes 20 minutes. Building something that survives crashes, bad deployments, and brute force attacks — and recovers itself — takes genuine systems thinking.

The most valuable part wasn't the implementation. It was asking "what breaks this?" for every component and building a response to each answer.
