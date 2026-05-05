# Megakuponi Server Architecture

## Overview

Single VPS (Ubuntu 24.04, Hetzner/Linode) running 13+ websites across multiple country-code domains. All sites share one Rust backend and one SvelteKit admin panel. No load balancer or cluster — just nginx as reverse proxy in front of everything.

---

## Services

| Service | Type | Port | Runs as |
|---|---|---|---|
| `mega-kuponi` | Rust/Rocket HTTP API | 8000 (local) | `runner` |
| `mega-kuponi-admin` | SvelteKit/Node.js admin panel | 3000 (local) | `runner` |
| `nginx` | Reverse proxy + static files | 80, 443 | `www-data` |
| `postgresql` | Database | 5432 (local) | `postgres` |
| `redis` | Session/cache store | 6379 (local, password-protected) | `redis` |
| `fail2ban` | Intrusion prevention | — | root |
| `certbot` | SSL cert renewal (systemd timer) | — | root |
| `restic` | Backup to object storage (cron) | — | root |

SSH runs on port **6699** (non-standard, for reduced noise).

---

## Users

| User | Purpose | Notes |
|---|---|---|
| `root` | Server administration | SSH on port 6699; 2 authorized keys (both svenbrettschneider@proton.me) |
| `ana` | Content editing, source code, FTP | Has deploy SSH keys for git pull; source in `/home/ana/source/`; FTP write access to resources |
| `runner` | Runs backend and admin services | System user; write access only to `/var/www/resources/` |

---

## Domains

### Active (HTTPS, all proxied through nginx)

| Domain | Backend |
|---|---|
| www.megacupones.cl | port 8000 |
| www.megacupones.co | port 8000 |
| www.megacupones.com.mx | port 8000 |
| www.megacupones.pe | port 8000 |
| www.megakuponi.hr | port 8000 |
| www.megakuponi.rs | port 8000 |
| www.megakuponi.si | port 8000 |
| www.megakuponi.ba | port 8000 |
| www.megakupony.com.ua | port 8000 |
| www.megakupony.kz | port 8000 |
| www.megacupones.uy | port 8000 |
| www.megacupones.ar | port 8000 |
| www.animamedia.nl | port 3000 (admin panel) |

### Disabled (return 404)
- megacupones.com.py / www.megacupones.com.py
- megacupones.com.bo / www.megacupones.com.bo

### Nginx routing notes
- Non-www → www redirect for all domains
- HTTP → HTTPS redirect for all domains
- `/resources/` served as static files from `/var/www/resources/`, cached 1 year
- `/admin-api/` on all domains proxied to port 8000 (backend)
- Rate limit: 10 req/s per IP, burst 20, returns 429 on breach
- SSL: Let's Encrypt cert at `/etc/letsencrypt/live/animamedia.nl/` (SAN cert covering all active domains)

---

## Filesystem Layout

```
/var/www/
├── application/          # Rust backend binary + Jinja templates
│   ├── mega-kuponi       # compiled binary
│   └── templates/        # Rocket templates
├── admin-app/            # Built SvelteKit admin (node_modules + build/)
│   ├── build/
│   ├── package.json
│   └── node_modules/
└── resources/            # User-uploaded images/assets (writable by runner, FTP by ana)
    └── images/
        └── vectors/

/home/ana/source/
├── mega-kuponi/          # Rust backend source (git repo)
└── mega-kuponi-administration/  # Admin frontend source (git repo)

/etc/restic/
├── env                   # S3 credentials + repo URL
└── password              # Restic encryption password

/etc/megakuponi/keys/     # Deploy SSH keys (managed by ansible, not in git)
├── id-dev                # Deploy key for mega-kuponi repo
└── id-dev-admin          # Deploy key for mega-kuponi-administration repo
```

---

## Database (PostgreSQL)

- **Database:** `megakuponi`
- **User `dev`:** Application user, full privileges on all tables
- **User `ana`:** Content/FTP user, read-only SELECT on all tables by default
- **User `postgres`:** Superuser

---

## Deployment Workflow

### Backend (Rust)
```
sudo /opt/megakuponi/scripts/update.sh
```
1. `git pull` (using deploy key at `/etc/megakuponi/keys/id-dev`)
2. `cargo build --release`
3. Copy templates + binary to `/var/www/application/`
4. `systemctl restart mega-kuponi`
5. Run FTL route validation smoke test

### Admin panel (SvelteKit/Node.js)
```
sudo /opt/megakuponi/scripts/update-admin.sh
```
1. `git pull` (using deploy key at `/etc/megakuponi/keys/id-dev-admin`)
2. `npm install && npm run build`
3. Copy build to `/var/www/admin-app/`
4. `npm ci --omit dev` in target dir
5. `systemctl restart mega-kuponi-admin`

Scripts are runnable by any user via sudoers rule (no password required for these specific scripts).

---

## Backup (restic)

- **Schedule:** daily systemd timer
- **What:** `/var/www/resources`, `/etc/letsencrypt`, postgres dump (`pg_dump -Fc megakuponi`)
- **Where:** Hetzner Object Storage (`s3:hel1.your-objectstorage.com/megakuponibackup`)
- **Retention:** 24 hourly, 7 daily, 12 weekly, 3 monthly
- **Config:** `/etc/restic/env` (credentials), `/etc/restic/password` (encryption key)

---

## Secrets

All secrets are stored in Ansible Vault (`group_vars/all/vault.yml`). The vault file is encrypted and safe to commit to git. Decrypt with: `ansible-vault edit group_vars/all/vault.yml`.

Secrets managed:
- PostgreSQL passwords (dev user, ana user)
- Redis password
- Rocket secret key + verification secret
- Mailjet API key + secret
- Doppio API key
- Restic S3 credentials + encryption password
- SSH deploy key contents (id-dev, id-dev-admin)
- Root authorized SSH keys

---

## fail2ban

- **bantime:** 24h
- **findtime:** 24h
- **maxretry:** 5
- **Active jails:** `sshd` (port 6699), `nginx-limit-req`
- **ignoreip:** localhost + current server IP (update when migrating)
