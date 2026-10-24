# pi-bootstrap

[![ShellCheck](https://github.com/kurtoskolac/pi-bootstrap/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/kurtoskolac/pi-bootstrap/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Take a fresh Raspberry Pi OS install to a container-ready, hardened homelab box
with one script. Built on a Raspberry Pi 3B (1 GB RAM) running rootless Podman.

Every step is **idempotent** (safe to re-run) and supports **`--dry-run`**, so you
can see exactly what would change before anything does.

> **Status:** early development. Only the preflight step exists so far.

## Usage

```bash
git clone git@github.com:kurtoskolac/pi-bootstrap.git
cd pi-bootstrap
./bootstrap.sh --list        # show the steps
./bootstrap.sh --dry-run     # preview, changes nothing
./bootstrap.sh               # run everything
./bootstrap.sh --only preflight
```

Run it as your normal user, not root. It calls `sudo` only where needed.

## Steps

| Step | What it does | Status |
|------|--------------|--------|
| `preflight` | Checks OS, architecture, user, sudo, DNS | done |
| `packages` | Installs podman, podman-compose, tmux, btop, ncdu, lnav | planned |
| `ssh-hardening` | Key-only SSH with a lockout guard and automatic rollback | planned |
| `storage` | Sets up log2ram and zram to spare the SD card | planned |
| `containers` | Enables lingering and `podman-restart` so containers survive reboots | planned |

## Design rules

- Nothing changes the system outside `run`, so `--dry-run` is always honest.
- Anything that could lock you out is guarded and verified before it is applied.
- ShellCheck must pass in CI.

## License

MIT
## Deploying the stack (Quadlets + Ansible)

`quadlets/` holds the container units, `systemd/homelab.target` groups them,
and `ansible/` deploys everything to `~/.config/...` on the Pi.

One-time prep on the Pi:

```
sudo apt install ansible-core git
cp quadlets/dufs.env.example ~/filebrowser/dufs.env   # then edit it
```

Apply the repo to the Pi (it pulls and configures itself):

```
ansible-pull -U https://github.com/kurtoskolac/pi-bootstrap.git ansible/local.yml
```

Or from a local clone:

```
cd ansible && ansible-playbook local.yml
```

Check what's running:

```
systemctl --user status homelab.target
podman ps
```

Secrets (`*.env`) are never committed. Only `*.env.example` files are.
