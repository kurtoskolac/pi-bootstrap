# Recovery and backups

This repo is a **recipe**, not a disk image. It rebuilds the *configuration* of
the Pi. The *data* (notes, files, secrets) is deliberately not here, because
the repo is public. It lives in an encrypted restic backup whose destination
and password are stored privately on the Pi and in your password manager.

| What | Where it lives | Restored by |
|------|----------------|-------------|
| OS packages, containers, timers, journald | this repo | `ansible-playbook` |
| memos notes, dufs files, homer config, Forgejo repos, `dufs.env` | restic backup | `restic restore` |
| restic repository password | **your password manager** | you |

## One-time: set up backups

Run on the Pi after the `backup` role has been applied.

1. Pick the destination and edit the settings file:

       mkdir -p ~/.config/restic
       cp ~/pi-bootstrap/ansible/roles/backup/files/restic.env.example ~/.config/restic/restic.env
       nano ~/.config/restic/restic.env      # set RESTIC_REPOSITORY and the path to your home

2. Create the repository password and **save a copy in your password manager**:

       openssl rand -base64 32 > ~/.config/restic/password
       chmod 600 ~/.config/restic/password ~/.config/restic/restic.env
       cat ~/.config/restic/password

3. Run the first backup by hand and check it:

       ~/.local/bin/restic-backup.sh
       set -a; . ~/.config/restic/restic.env; set +a
       restic snapshots

4. The timer then runs it every night at about 03:30 (`systemctl --user list-timers`).
   Check the last run with `journalctl --user -u restic-backup.service -n 30`.

memos (and Forgejo, once running) are stopped for a few seconds during the
copy so their SQLite databases are consistent, then started again.

## Rebuild after a dead SD card

1. **Flash** Raspberry Pi OS Lite (64-bit) with Raspberry Pi Imager. In its
   settings set the hostname, your user, your SSH public key, Wi-Fi if needed
   and the timezone. Keeping the old hostname (`mia-search`) means nothing else
   has to change.
2. **Connect** from your Mac. The new card has a new SSH identity, so first run
   `ssh-keygen -R mia-search.local`, then `ssh kurtoskolac@mia-search.local`.
3. **Install the tools** (podman is not installed by the repo yet, see
   "Known gaps"):

       sudo apt update && sudo apt install -y git ansible-core podman

4. **Apply the repo:**

       git clone https://github.com/kurtoskolac/pi-bootstrap.git ~/pi-bootstrap
       cd ~/pi-bootstrap/ansible
       ansible-playbook local.yml --diff -K

5. **Restore the private files** by hand (they are never in git):

       mkdir -p ~/.config/restic
       nano ~/.config/restic/restic.env       # same destination as before
       nano ~/.config/restic/password         # paste the password from your password manager
       chmod 600 ~/.config/restic/*

6. **Restore the data.** Stop the services, restore, start them again.
   `podman unshare` makes restic run inside Podman's user namespace so the
   container-owned files get their original owners back:

       systemctl --user stop memos forgejo mia-files homer
       set -a; . ~/.config/restic/restic.env; set +a
       podman unshare restic restore latest --target /
       systemctl --user start memos forgejo mia-files homer

   To restore only one thing, add `--include /home/kurtoskolac/memos/data`.
   To restore an older snapshot, use its ID from `restic snapshots` instead of `latest`.

7. **Verify:** `podman ps`, then open each service in a browser.

## Known gaps

Not automated yet, so after a rebuild they still need doing by hand:

- Installing `podman` (planned `packages` step in `bootstrap.sh`).
- Enabling the Podman auto-update timer: `systemctl --user enable --now podman-auto-update.timer`.
- SSH hardening, log2ram and zram (planned `ssh-hardening` and `storage` steps).
- The first run of this whole procedure on a clean card has not been tested yet.
  Do it once on a spare SD card and fix whatever breaks.
