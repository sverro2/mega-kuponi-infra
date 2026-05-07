# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Ansible infrastructure for a single VPS hosting 13+ coupon websites (`megacupones.*`) that share one Rust API backend and one SvelteKit admin panel. Managed via two playbooks: `site.yml` (idempotent provisioning) and `bootstrap.yml` (one-time setup: clone repos, restore backup, obtain SSL certs).

## Running Playbooks

```bash
# Install collections (once)
ansible-galaxy collection install -r requirements.yml

# Full provisioning — production
ansible-playbook playbooks/site.yml --ask-vault-pass

# Full provisioning — test server
ansible-playbook -i inventory/test.yml playbooks/site.yml --ask-vault-pass

# Bootstrap a fresh server (one-time, after site.yml)
ansible-playbook playbooks/bootstrap.yml --ask-vault-pass

# First run on a brand-new server (SSH still on port 22, password auth)
ansible-playbook playbooks/site.yml --ask-vault-pass --ask-pass -e ansible_port=22

# Target a single role
ansible-playbook playbooks/site.yml --ask-vault-pass --tags nginx
```

## Secrets

Secrets live in `inventory/group_vars/all/vault.yml` (AES256 ansible-vault). Edit with:

```bash
ansible-vault edit inventory/group_vars/all/vault.yml
```

To avoid typing the password every run, set `vault_password_file = .vault_pass` in `ansible.cfg` and put the password in `.vault_pass` (already gitignored).

## Inventory & Variables

- `inventory/hosts.yml` — production (`139.162.148.36:6699`)
- `inventory/test.yml` — test server (`178.105.104.251:6699`)
- `inventory/group_vars/all/vars.yml` — all non-secret config (users, paths, domains, ports, retention policy, etc.)
- `inventory/group_vars/all/vault.yml` — encrypted secrets (DB passwords, Redis password, deploy SSH private keys, restic credentials, API keys)
- `inventory/host_vars/megakuponi-test/vars.yml` — test-server overrides (different domains, different restic repo path, no SSL restore from backup)

## Role Overview

| Role | Responsibility |
|---|---|
| `common` | Users (`ana`, `runner`), SSH hardening (port 6699), swap (8 GB), deploy keys to `/etc/megakuponi/keys/`, unattended-upgrades |
| `firewall` | UFW: deny-in default, allow 6699/80/443 |
| `fail2ban` | Brute-force protection: 24h ban, 5 retries; monitors sshd + nginx-limit-req |
| `redis` | Local-only, password-auth, allkeys-lru eviction |
| `postgres` | DB + two users: `dev` (full) and `ana` (read-only SELECT, writable on a few tables) |
| `app` | Install Rust + Node.js, create app dirs, deploy update/smoke-test scripts to `/usr/local/bin/`, sudoers entries, `Rocket.toml` |
| `nginx` | Reverse proxy: SSL, rate-limit (10 req/s burst 20), static cache (1 yr), → backend :8000, admin :3000 |
| `certbot` | Self-signed placeholder certs (so nginx starts), DH params, certbot.timer |
| `systemd` | `mega-kuponi.service` (Rust) + `mega-kuponi-admin.service` (Node), environment file |
| `backup` | Restic to Hetzner Object Storage; daily 03:00 timer; retention 24h/7d/12w/3m; backs up postgres dump + `/var/www/resources/` + `/etc/letsencrypt/` |

## Deployment Flow

**Fresh server:**
1. Set IP in `inventory/hosts.yml`
2. `site.yml` (services will fail to start — binaries don't exist yet; that's expected)
3. `bootstrap.yml` (clones repos, restores backup, gets SSL certs, builds & starts apps)
4. `site.yml` again to ensure services are up

**Migration from old server:**
- Run `bootstrap.yml` with `-e restic_repo="{{ restic_repo_base }}/production"` to pull the production backup onto the new server
- Verify via `/etc/hosts` before switching DNS

**Day-to-day on the server:**
```bash
sudo /opt/megakuponi/scripts/update.sh           # deploy backend
sudo /opt/megakuponi/scripts/update.sh --admin   # deploy admin panel
sudo /opt/megakuponi/scripts/backup.sh           # manual backup
sudo /opt/megakuponi/scripts/restore.sh          # restore from backup
```

## Key Conventions

- **Idempotent** — all playbooks are safe to re-run; handlers batch service restarts.
- **User separation** — `ana` owns source code and deploy keys; `runner` runs the services; neither has broad sudo.
- **Templates** — Jinja2 `.j2` files in `roles/*/templates/`; variables flow from `vars.yml` / `vault.yml`.
- **Smoke test** — post-deploy route validation runs automatically; skip with `--skip-smoke-test` on the update script.
- **SSH port** is `6699` everywhere; ansible.cfg sets this as default.
