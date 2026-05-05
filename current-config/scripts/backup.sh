#!/bin/bash
set -euo pipefail

echo 'Creating dump of megakuponi database...'
sudo -u postgres pg_dump -Fc megakuponi > /tmp/db.dump

echo 'Syncing backup...'
restic backup \
  /var/www/resources \
  /etc/letsencrypt \
  /tmp/db.dump

rm -f /tmp/db.dump

echo "Removing backups that are too old"
restic forget \
  --keep-hourly 24 \
  --keep-daily 7 \
  --keep-weekly 12 \
  --keep-monthly 3 \
  --prune

echo 'Backup finished!'
