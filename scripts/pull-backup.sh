#!/usr/bin/env bash
# Run this on your Mac (or any trusted computer), NOT on the Pi.
#
# Pulls the Pi's encrypted restic repository to this machine over SSH.
# The connection goes Mac -> Pi only: the Pi never reaches into your Mac.
# The repository is encrypted, so the copy is safe even on a shared disk,
# but keep the restic password in your password manager: without it the
# copy cannot be read.
#
# Settings (override with environment variables):
#   PI_HOST       user@host of the Pi          (default: kurtoskolac@mia-search.local)
#   PI_REPO_PATH  repo path on the Pi          (default: backups/restic, relative to its home)
#   BACKUP_DEST   folder on this machine       (default: ~/pi-backups)
set -euo pipefail

PI_HOST="${PI_HOST:-kurtoskolac@mia-search.local}"
PI_REPO_PATH="${PI_REPO_PATH:-backups/restic}"
BACKUP_DEST="${BACKUP_DEST:-$HOME/pi-backups}"

# Safety guard: mirroring with --delete from an empty or missing repo (for
# example a freshly flashed Pi) would wipe the good copy on this machine.
if ! ssh "$PI_HOST" test -f "$PI_REPO_PATH/config" -a -d "$PI_REPO_PATH/data"; then
  echo "pull-backup: no restic repository at $PI_HOST:$PI_REPO_PATH, refusing to sync" >&2
  exit 1
fi

mkdir -p "$BACKUP_DEST/restic"
rsync -av --delete "$PI_HOST:$PI_REPO_PATH/" "$BACKUP_DEST/restic/"

echo
echo "Copy is in $BACKUP_DEST/restic"
echo "Check it (needs restic: brew install restic):"
echo "  restic -r $BACKUP_DEST/restic snapshots"
