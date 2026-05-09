# Production Web Server — Architecture Document

**Author:** David Onoja  
**Date:** May 2026  
**Server:** AWS EC2 t2.micro — Ubuntu 22.04 LTS  
**Status:** Production  

---

## System Overview

A production-grade single-server web infrastructure that runs a 
containerized Flask application, secured against common threats, 
with automated monitoring and recovery.

## Architecture Diagram

Internet
│
▼
[AWS Security Group]     — Cloud firewall: ports 22, 80, 443 only
│
▼
[UFW Firewall]           — OS firewall: second enforcement layer
│
▼
[Nginx :80]              — Reverse proxy, security headers, rate limiting
│
▼
[Docker Container :5000] — Flask + Gunicorn, non-root user
│
▼
[Health Monitor]         — Cron every 5min, auto-restart on failure

## Security Decisions

| Decision | Reason |
|----------|--------|
| SSH key-only authentication | Passwords are brute-forceable. Keys are not. |
| PermitRootLogin no | Root compromise = total system loss |
| Two firewalls (Security Group + UFW) | Defense in depth. One layer failing doesn't expose the server. |
| Fail2Ban on SSH | Automated blocking of brute force attempts |
| Non-root Docker user | Container compromise gives limited user, not root |
| Nginx in front of Flask | Flask/Gunicorn never directly exposed to internet |
| server_tokens off | Hides Nginx version from attackers |
| Rate limiting (10r/s) | Limits impact of DoS attempts |

## Reliability Mechanisms

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Container crash | Docker restart policy | Auto-restart in seconds |
| Container removed | health_check.sh cron | Recreate container |
| App returns errors | Error rate check in health script | Alert logged |
| Nginx down | health_check.sh | Auto-restart |
| Server reboot | systemd enable on all services | All services start automatically |
| Bad deployment | deploy.sh health check fails | Automatic rollback to previous |

## Port Architecture

| Port | Service | Accessible From |
|------|---------|----------------|
| 22 | SSH | My IP only |
| 80 | Nginx (HTTP) | Public internet |
| 443 | Nginx (HTTPS) | Public internet (future) |
| 5000 | Flask/Docker | Internal only (127.0.0.1) |

## Scripts

| Script | Purpose | When to Run |
|--------|---------|-------------|
| deploy.sh | Deploy new version with rollback | Every code change |
| health_check.sh | Monitor and auto-recover | Every 5 min via cron |
| status.sh | Server overview dashboard | On SSH login |
| bootstrap.sh | Rebuild server from scratch | New server setup |

## Incident Runbook

### App is down (502 Bad Gateway)
1. `docker ps` — is container running?
2. `docker logs flask-app` — why did it fail?
3. `docker start flask-app` or `bash ~/scripts/deploy.sh latest`
4. `curl http://localhost/health` — verify recovery

### Can't reach server on port 80
1. Check AWS Security Group — is port 80 allowed?
2. `sudo ufw status` — is UFW blocking it?
3. `systemctl status nginx` — is Nginx running?
4. `sudo nginx -t` — is config valid?
5. `ss -tlnp | grep :80` — is anything listening?

### SSH connection refused
1. Check AWS Security Group — port 22 allowed from your IP?
2. Use AWS EC2 Serial Console for emergency access
3. Check `/var/log/auth.log` for Fail2Ban bans

## What I Would Add With More Time

- HTTPS/SSL with Let's Encrypt (Certbot)
- Terraform to provision infrastructure as code
- GitHub Actions for automated CI/CD on git push
- Prometheus + Grafana for real-time metrics dashboard
- AWS CloudWatch for centralized logging
- Multiple servers with a load balancer
