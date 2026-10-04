#!/usr/bin/env bash
#
# pi-bootstrap - take a fresh Raspberry Pi OS install to a container-ready,
# hardened homelab box. Every step is idempotent and safe to re-run.
#
# Usage: ./bootstrap.sh [--dry-run] [--only STEP] [--list] [--help]

set -Eeuo pipefail

readonly VERSION="0.1.0"
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pi-bootstrap"
readonly LOG_FILE="$STATE_DIR/bootstrap.log"

DRY_RUN=0
ONLY=""

# Registered steps, in run order, as "name:description".
# Every name needs a matching step_<name> function below.
STEPS=(
  "preflight:Check OS, architecture, user and sudo access"
)

# ---------------------------------------------------------------- output ----

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
else
  C_RESET="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
fi

_log() {
  local level="$1" color="$2"
  shift 2
  printf '%s[%s]%s %s\n' "$color" "$level" "$C_RESET" "$*"
  if (( DRY_RUN == 0 )) && [[ -f $LOG_FILE ]]; then
    printf '%s [%s] %s\n' "$(date -Is)" "$level" "$*" >>"$LOG_FILE"
  fi
}

info() { _log INFO "$C_BLUE" "$@"; }
ok()   { _log OK "$C_GREEN" "$@"; }
warn() { _log WARN "$C_YELLOW" "$@" >&2; }
err()  { _log ERROR "$C_RED" "$@" >&2; }
die()  { err "$@"; exit 1; }

trap 'err "Unexpected failure at line $LINENO (exit code $?)"' ERR

# Run a command, or only print it in --dry-run mode.
# Every step that changes the system must go through this.
run() {
  if (( DRY_RUN )); then
    printf '%s[DRY-RUN]%s would run: %s\n' "$C_YELLOW" "$C_RESET" "$(printf '%q ' "$@")"
    return 0
  fi
  "$@"
}

# ----------------------------------------------------------------- setup ----

usage() {
  cat <<EOF
pi-bootstrap $VERSION

Usage: ./bootstrap.sh [options]

Options:
  --dry-run     Show what would change without changing anything
  --only STEP   Run a single step (see --list)
  --list        List the available steps
  --version     Print the version
  -h, --help    Show this help

Run as your normal user, not root. sudo is used only where needed.
EOF
}

list_steps() {
  local entry
  for entry in "${STEPS[@]}"; do
    printf '  %-12s %s\n' "${entry%%:*}" "${entry#*:}"
  done
}

step_exists() {
  local entry
  for entry in "${STEPS[@]}"; do
    [[ ${entry%%:*} == "$1" ]] && return 0
  done
  return 1
}

init_state() {
  if (( DRY_RUN == 0 )); then
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    touch "$LOG_FILE"
  fi
}

# ----------------------------------------------------------------- steps ----

step_preflight() {
  local user arch
  user="$(id -un)"

  # Never run as root: rootless Podman, lingering and SSH key checks all refer
  # to the invoking user, and root would configure the wrong account.
  if (( EUID == 0 )); then
    die "Run this as your normal user, not root. The script calls sudo only where needed."
  fi
  ok "Running as user '$user'"

  if [[ ! -r /etc/os-release ]]; then
    die "Cannot read /etc/os-release"
  fi
  # Read os-release in a separate process: it defines VERSION, ID and others
  # that would collide with this script's own (read-only) variables, and a
  # plain subshell would inherit the read-only flag.
  local os_id os_like os_name
  os_id="$(sh -c '. /etc/os-release; printf "%s" "${ID:-}"')"
  os_like="$(sh -c '. /etc/os-release; printf "%s" "${ID_LIKE:-}"')"
  os_name="$(sh -c '. /etc/os-release; printf "%s" "${PRETTY_NAME:-unknown}"')"
  case "$os_id:$os_like" in
    *debian*|*raspbian*) ok "OS: $os_name" ;;
    *) warn "Not Debian/Raspberry Pi OS ($os_name); later steps assume apt and systemd" ;;
  esac

  arch="$(uname -m)"
  case "$arch" in
    aarch64|armv7l|armv6l) ok "Architecture: $arch" ;;
    *) warn "Unexpected architecture '$arch'; this was written for Raspberry Pi hardware" ;;
  esac

  if [[ -r /proc/device-tree/model ]]; then
    info "Board: $(tr -d '\0' </proc/device-tree/model)"
  fi

  [[ -d /run/systemd/system ]] || die "systemd is required"
  ok "systemd is running"

  command -v sudo >/dev/null 2>&1 || die "sudo is not installed"
  if (( DRY_RUN )); then
    info "Dry run: skipping the sudo password check"
  elif sudo -v; then
    ok "sudo access confirmed"
  else
    die "sudo access is required"
  fi

  if getent hosts deb.debian.org >/dev/null 2>&1; then
    ok "DNS resolution works"
  else
    warn "Cannot resolve deb.debian.org; package steps will fail without internet"
  fi

  if [[ -n ${SSH_CONNECTION:-} ]]; then
    info "Running over SSH: keep this session open until the run finishes"
  fi
}

# ------------------------------------------------------------------ main ----

main() {
  if (( BASH_VERSINFO[0] < 4 )); then
    die "bash 4 or newer is required"
  fi

  while (( $# )); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --only)
        [[ $# -ge 2 ]] || die "--only needs a step name"
        ONLY="$2"
        shift
        ;;
      --list) list_steps; exit 0 ;;
      --version) echo "$VERSION"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
  done

  if [[ -n $ONLY ]] && ! step_exists "$ONLY"; then
    err "Unknown step '$ONLY'. Available steps:"
    list_steps >&2
    exit 2
  fi

  init_state
  if (( DRY_RUN )); then
    warn "Dry run: nothing will be changed"
  fi

  local entry name desc
  for entry in "${STEPS[@]}"; do
    name="${entry%%:*}"
    desc="${entry#*:}"
    if [[ -n $ONLY && $ONLY != "$name" ]]; then
      continue
    fi
    info "Step: $name - $desc"
    "step_$name"
  done

  ok "Finished"
  if (( DRY_RUN == 0 )); then
    info "Log: $LOG_FILE"
  fi
}

main "$@"
