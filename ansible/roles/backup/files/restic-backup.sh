#!/usr/bin/env bash
# Nightly encrypted backup of the homelab's container data with restic.
#
# Installed to ~/.local/bin by the `backup` Ansible role and run by the
# restic-backup.timer user timer. The destination and password are NOT in this
# repo: they live in ~/.config/restic/restic.env on the Pi
# (template: ansible/roles/backup/files/restic.env.example).
set -euo pipefail

CONF="${RESTIC_ENV_FILE:-$HOME/.config/restic/restic.env}"
if [ ! -r "$CONF" ]; then
  echo "restic-backup: missing $CONF (copy restic.env.example and edit it)" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$CONF"
: "${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY in $CONF}"
: "${RESTIC_PASSWORD_FILE:?set RESTIC_PASSWORD_FILE in $CONF}"
export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

# What to back up. Keep in sync with quadlets_data_dirs in the quadlets role.
# filebrowser/ includes dufs.env; that is fine, the repository is encrypted.
CANDIDATES=(
  "$HOME/memos/data"
  "$HOME/filebrowser"
  "$HOME/homer/assets"
  "$HOME/picker/html"
  "$HOME/forgejo/data"
  "$HOME/forgejo/config"
)
PATHS=()
for p in "${CANDIDATES[@]}"; do
  [ -e "$p" ] && PATHS+=("$p")
done
if [ "${#PATHS[@]}" -eq 0 ]; then
  echo "restic-backup: nothing to back up" >&2
  exit 1
fi

# Services with SQLite databases are stopped for the few seconds the copy takes
# so the snapshot is consistent. They are restarted on exit, even on failure.
SERVICES=(memos forgejo)
STOPPED=()
restart_services() {
  for s in "${STOPPED[@]}"; do
    systemctl --user start "$s" || echo "restic-backup: could not restart $s" >&2
  done
}
trap restart_services EXIT
for s in "${SERVICES[@]}"; do
  if systemctl --user is-active --quiet "$s"; then
    systemctl --user stop "$s"
    STOPPED+=("$s")
  fi
done

# Some data dirs are owned by rootless Podman's mapped sub-UIDs. `podman
# unshare` runs restic inside the same user namespace, so it can read them
# (and restores give them back the right owners).
RESTIC=(podman unshare restic)

if ! "${RESTIC[@]}" cat config >/dev/null 2>&1; then
  echo "restic-backup: initialising repository $RESTIC_REPOSITORY"
  "${RESTIC[@]}" init
fi

"${RESTIC[@]}" backup --tag nightly --one-file-system "${PATHS[@]}"

# Back online as soon as the snapshot is taken; pruning can take a while.
restart_services
STOPPED=()

"${RESTIC[@]}" forget --tag nightly --keep-daily 7 --keep-weekly 4 --keep-monthly 6

# Sundays: reclaim space and verify the repository structure.
if [ "$(date +%u)" = 7 ]; then
  "${RESTIC[@]}" prune
  "${RESTIC[@]}" check
fi
