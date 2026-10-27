# Recovery and backups

This repo is a **recipe**, not a disk image. It rebuilds the *configuration* of
the Pi. The *data* (notes, files, secrets) is deliberately not here, because
the repo is public. It lives in an encrypted restic backup.

## How the backup works

```
 Pi (nightly, automatic)                     Mac (you run it, whenever you like)
 -----------------------                     -----------------------------------
 restic-backup.timer, ~03:30                 scripts/pull-backup.sh
   -> encrypted snapshot into                  -> copies that repository over SSH
      ~/backups/restic on the Pi                  to ~/pi-backups/restic
```

- The Pi **never connects to the Mac**. The only connection is Mac to Pi over
  SSH, the same direction as your normal login. No USB drive is needed.
- The repository is encrypted with a password only you hold, so the copy is
  unreadable without it.
- Snapshots are incremental: after the first full copy, each run only stores
  what changed. Retention: 7 daily, 4 weekly, 6 monthly.
- memos (and Forgejo, once running) are stopped for a few seconds during the
  copy so their SQLite databases are consistent, then started again.

**Important:** until you run `scripts/pull-backup.sh`, the only copy lives on
the Pi's own SD card, so a dead card would take it too. Pull a copy to the Mac
regularly (for example weekly, and after anything important).

| What | Where it lives | Restored by |
|------|----------------|-------------|
| OS packages, containers, timers, journald | this repo | `ansible-playbook` |
| memos notes, dufs files, homer config, Forgejo repos, `dufs.env` | restic repo (Pi, plus your Mac copy) | `restic restore` |
| restic repository password | **your password manager** | you |

## One-time: set up backups

Run on the Pi after the `backup` role has been applied.

1. Create the settings file (replace `kurtoskolac` if your user differs):

       cp ~/pi-bootstrap/ansible/roles/backup/files/restic.env.example ~/.config/restic/restic.env
       sed -i "s#CHANGE_ME#$USER#g" ~/.config/restic/restic.env

2. Create the repository password and **save a copy in your password manager**:

       openssl rand -base64 32 > ~/.config/restic/password
       chmod 600 ~/.config/restic/password ~/.config/restic/restic.env
       cat ~/.config/restic/password

3. Run the first backup by hand and check it:

       ~/.local/bin/restic-backup.sh
       set -a; . ~/.config/restic/restic.env; set +a
       restic snapshots

4. From now on the timer runs it every night (`systemctl --user list-timers`).
   See the last run with `journalctl --user -u restic-backup.service -n 30`.

## Pull a copy to your Mac

On the Mac, from your clone of this repo:

    ./scripts/pull-backup.sh

It refuses to run if the Pi has no repository (so an empty, freshly flashed Pi
can never overwrite your good copy). To check the copy: `brew install restic`,
then `restic -r ~/pi-backups/restic snapshots` and enter the password.

## Rebuild after a dead SD card

1. **Flash** Raspberry Pi OS Lite (64-bit) with Raspberry Pi Imager. In its
   settings set the hostname, your user, your SSH public key, Wi-Fi if needed
   and the timezone. Keeping the old hostname (`mia-search`) means nothing else
   has to change.
2. **Connect** from your Mac. The new card has a new SSH identity, so first run
   `ssh-keygen -R mia-search.local`, then `ssh kurtoskolac@mia-search.local`.
3. **Install the tools** (podman is not installed by the repo yet, see
   "Known gaps"):

       sudo apt update && sudo apt install -y git ansible-core podman restic

4. **Apply the repo:**

       git clone https://github.com/kurtoskolac/pi-bootstrap.git ~/pi-bootstrap
       cd ~/pi-bootstrap/ansible
       ansible-playbook local.yml --diff -K

5. **Put the backup repository back on the Pi.** On the Mac (this pushes from
   the Mac to the Pi, the Pi never connects out):

       rsync -av ~/pi-backups/restic/ kurtoskolac@mia-search.local:backups/restic/

6. **Restore the private settings** on the Pi (they are never in git):

       nano ~/.config/restic/restic.env       # copy of restic.env.example, as in "One-time" step 1
       nano ~/.config/restic/password         # paste the password from your password manager
       chmod 600 ~/.config/restic/*

7. **Restore the data.** Stop the services, restore, start them again.
   `podman unshare` makes restic run inside Podman's user namespace so the
   container-owned files get their original owners back:

       systemctl --user stop memos forgejo mia-files homer
       set -a; . ~/.config/restic/restic.env; set +a
       podman unshare restic restore latest --target /
       systemctl --user start memos forgejo mia-files homer

   To restore only one thing, add `--include /home/kurtoskolac/memos/data`.
   To restore an older snapshot, use its ID from `restic snapshots` instead of `latest`.

8. **Verify:** `podman ps`, then open each service in a browser.

## Known gaps

Not automated yet, so after a rebuild they still need doing by hand:

- Installing `podman` (planned `packages` step in `bootstrap.sh`).
- Enabling the Podman auto-update timer: `systemctl --user enable --now podman-auto-update.timer`.
- SSH hardening, log2ram and zram (planned `ssh-hardening` and `storage` steps).
- Pulling the backup to the Mac is manual. If you forget, the newest data
  exists only on the Pi's card.
- Nothing alerts you if the nightly timer stops working.
- The first run of this whole procedure on a clean card has not been tested yet.
  Do it once on a spare SD card and fix whatever breaks.
