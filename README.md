# megakuponi-infra

Ansible playbook for provisioning the Megakuponi server — a single Ubuntu 24.04 VPS running 13+ coupon websites across multiple country domains, backed by a Rust/Rocket API and a SvelteKit admin panel.

For a full description of the server architecture see [`current-config/server-description.md`](current-config/server-description.md).

---

## Prerequisites

On your local machine:

```bash
sudo dnf install ansible   # Fedora
# or: sudo apt install ansible

# Install required Ansible collections (one-time)
ansible-galaxy collection install -r requirements.yml
```

On the server: a fresh Ubuntu 24.04 VPS with root SSH access.

---

## One-time setup

### 1. Set the server IP

Edit `inventory/hosts.yml` and replace `YOUR_SERVER_IP`:

```yaml
all:
  hosts:
    megakuponi:
      ansible_host: YOUR_SERVER_IP
```

### 2. Fill in secrets

The vault file holds all secrets (passwords, API keys, SSH deploy keys). It is encrypted — decrypt it to edit:

```bash
ansible-vault edit group_vars/all/vault.yml
```

If you are setting up from scratch and have no existing vault, create one:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

Store the vault password in your password manager. You can also save it locally so you don't have to type it on every run:

```bash
echo 'your-vault-password' > .vault_pass && chmod 600 .vault_pass
```

Then uncomment `vault_password_file = .vault_pass` in `ansible.cfg`. The `.vault_pass` file is already in `.gitignore`.

### 3. Verify variables

Review `group_vars/all/vars.yml` — most values are already correct. The main ones to check on a new setup:

| Variable | Description |
|---|---|
| `ssh_port` | SSH port on the server (currently `6699`) |
| `swap_size` | Swap file size (currently `8G`) |
| `auto_updates_enabled` | Automatic security patches (default `true`) |
| `auto_reboot_enabled` | Monthly reboot on day 1 at 03:30 (default `true`) |
| `admin_email` | Where backup failure alerts are sent |

---

## Deploying a fresh server

### Step 1 — Point DNS to the new server

All domains must resolve to the new server IP before certbot can issue certificates. Wait for propagation before continuing.

### Step 2 — Run the main playbook

**Production:**
```bash
ansible-playbook playbooks/site.yml --ask-vault-pass
```

**Test server:**
```bash
ansible-playbook -i inventory/test.yml playbooks/site.yml --ask-vault-pass
```

This installs and configures everything: users, firewall, nginx, PostgreSQL, Redis, fail2ban, certbot timer, backup timer, systemd services. The services will fail to start at this point — that is expected, the binaries don't exist yet.

### Step 3 — Run the bootstrap playbook

**Production:**
```bash
ansible-playbook playbooks/bootstrap.yml --ask-vault-pass
```

**Test server:**
```bash
ansible-playbook -i inventory/test.yml playbooks/bootstrap.yml --ask-vault-pass
```

This handles everything needed to go from a provisioned-but-empty server to a running one:

1. Clones both git repositories
2. Obtains SSL certificates from Let's Encrypt
3. Restores the database from the latest restic backup
4. Restores `/var/www/resources/` from the latest restic backup
5. Builds and deploys the Rust backend and SvelteKit admin panel

### Migrating to a new server

If you're replacing an existing server rather than starting fresh, you don't need DNS to point to the new server first. The backup already includes `/etc/letsencrypt`, so valid SSL certificates are restored automatically and certbot is skipped.

**1.** Run `site.yml` on the new server (DNS still points to old server — that's fine).

**2.** Run bootstrap pointing at the production repo:
```bash
ansible-playbook playbooks/bootstrap.yml --ask-vault-pass \
  -e restic_repo="{{ restic_repo_base }}/production"
```

**3.** Verify the new server works by adding a temporary `/etc/hosts` entry on your machine pointing the domains to the new IP.

**4.** Lower the TTL on your DNS records to 60 seconds and wait for that to propagate (check with `dig +short example.com`).

**5.** Switch DNS to the new server. Propagation will be fast due to the low TTL.

**6.** Restore DNS TTL to normal once the cutover is confirmed.

During the brief propagation window some requests will still hit the old server. Since no new content is being added this is fine — the only side effect is that users may briefly lose their session and need to log in again.

### Step 4 — Run the main playbook once more

```bash
ansible-playbook playbooks/site.yml --ask-vault-pass
```

This starts the systemd services now that the binaries exist.

---

## Day-to-day operations

### Deploy an update

```bash
sudo /opt/megakuponi/scripts/update.sh [options]
```

| Flag | Description |
|---|---|
| _(none)_ | Deploy backend, run smoke test |
| `--admin` | Also deploy the admin panel |
| `--branch <branch>` | Backend git branch to deploy (default: `main`) |
| `--admin-branch <branch>` | Admin git branch to deploy (default: `main`) |
| `--debug` | Build backend in debug mode instead of release |
| `--skip-smoke-test` | Skip FTL route validation after deploy |
| `--help` | Show usage information |

```bash
# Common examples
sudo /opt/megakuponi/scripts/update.sh
sudo /opt/megakuponi/scripts/update.sh --admin
sudo /opt/megakuponi/scripts/update.sh --branch feature/x --admin --admin-branch main
sudo /opt/megakuponi/scripts/update.sh --debug --skip-smoke-test
```

Can be run by any user via `sudo` without a password prompt (configured via sudoers).

### Run a manual backup

```bash
sudo /opt/megakuponi/scripts/backup.sh
```

### Restore from backup

```bash
# Restore from this server's own backup
sudo /opt/megakuponi/scripts/restore.sh

# Restore from production backup (useful on test server)
sudo /opt/megakuponi/scripts/restore.sh --from-production
```

This extracts the backup to `/tmp/megakuponi-restore/` and prints the exact commands to restore the database and resources. After restoring the database, re-apply database permissions:

```bash
sudo -u postgres pg_restore --clean -d megakuponi /tmp/megakuponi-restore/tmp/db.dump
sudo /opt/megakuponi/scripts/grant-db-permissions.sh
rm -rf /tmp/megakuponi-restore
```

### Check service status

```bash
systemctl status mega-kuponi
systemctl status mega-kuponi-admin
journalctl -u mega-kuponi -f
```

### Check fail2ban

```bash
fail2ban-client status
fail2ban-client status sshd
```

---

## Re-running the playbook

The playbook is idempotent — safe to re-run at any time to apply configuration changes. After editing any file in this repo:

```bash
ansible-playbook playbooks/site.yml --ask-vault-pass
```

To apply changes to a single role only:

```bash
ansible-playbook playbooks/site.yml --ask-vault-pass --tags nginx
ansible-playbook playbooks/site.yml --ask-vault-pass --tags fail2ban
```

---

## Secrets management

All secrets live in `group_vars/all/vault.yml`, encrypted with Ansible Vault.

| Secret | Description |
|---|---|
| `vault_postgres_app_password` | PostgreSQL password for the `dev` application user |
| `vault_postgres_ana_password` | PostgreSQL password for the `ana` read-only user |
| `vault_redis_password` | Redis auth password |
| `vault_rocket_secret_key` | Rocket framework secret key |
| `vault_rocket_verification_secret` | Rocket verification secret |
| `vault_mailjet_key` / `vault_mailjet_secret` | Mailjet API credentials (also used for backup failure alerts) |
| `vault_doppio_api_key` | Doppio API key |
| `vault_restic_aws_access_key` / `vault_restic_aws_secret_key` | Hetzner Object Storage credentials for backups |
| `vault_restic_password` | Restic repository encryption password |
| `vault_deploy_key_backend` | SSH deploy key for the `mega-kuponi` repo |
| `vault_deploy_key_admin` | SSH deploy key for the `mega-kuponi-administration` repo |
| `vault_root_authorized_keys` | Authorized SSH public keys for root login |

To rotate a secret: edit the vault, update the value, re-run the playbook.

---

## Repository structure

```
├── ansible.cfg                  # Ansible configuration
├── inventory/hosts.yml          # Server IP
├── group_vars/all/
│   ├── vars.yml                 # Non-secret configuration
│   └── vault.yml                # Encrypted secrets
├── playbooks/
│   ├── site.yml                 # Main playbook (run on every change)
│   └── bootstrap.yml            # First-time setup (run once after site.yml)
├── roles/
│   ├── common/                  # Base packages, users, SSH, swap, auto-updates
│   ├── firewall/                # UFW rules
│   ├── fail2ban/                # Intrusion prevention
│   ├── redis/                   # Redis with password auth
│   ├── postgres/                # PostgreSQL + database + users
│   ├── app/                     # Directory layout, Rust, Node, deploy scripts
│   ├── nginx/                   # nginx config + vhosts for all domains
│   ├── certbot/                 # Let's Encrypt renewal timer
│   ├── systemd/                 # mega-kuponi + mega-kuponi-admin services
│   └── backup/                  # restic backup + daily timer + failure alerts
└── current-config/              # Reference copies of current server config
    └── server-description.md    # Full architecture documentation
```
